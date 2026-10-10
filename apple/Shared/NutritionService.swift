import Foundation

enum MacroSource {
    case saved, savedFuzzy, composed(ComposedMacros), defaultGuess
}

@MainActor
final class NutritionService: ObservableObject {
    private let client: SupabaseClient

    @Published var date: String = DateUtils.todayString()
    @Published var proteinCurrent: Double = 0
    @Published var carbsCurrent: Double = 0
    @Published var fatCurrent: Double = 0
    @Published var fiberCurrent: Double = 0
    @Published var proteinTarget: Double = 0
    @Published var carbsTarget: Double = 0
    @Published var fatTarget: Double = 0
    @Published var fiberTarget: Double = 0
    @Published var waterTotalMl: Int = 0
    @Published var waterTargetMl: Int = 3000
    @Published var foodEntries: [NutritionLogEntry] = []
    @Published var supplements: [String] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastLogMessage: String?

    private var ingredients: [NutritionIngredient] = []
    private var units: [NutritionUnit] = []
    private var foodItems: [FoodItem] = []
    private var referenceLoaded = false

    init(client: SupabaseClient) { self.client = client }

    func loadReferenceDataIfNeeded() async {
        guard !referenceLoaded else { return }
        do {
            async let ing: [NutritionIngredient] = client.select("nutrition_ingredients", query: [URLQueryItem(name: "limit", value: "1000")], as: [NutritionIngredient].self)
            async let unt: [NutritionUnit] = client.select("nutrition_units", query: [URLQueryItem(name: "limit", value: "1000")], as: [NutritionUnit].self)
            (ingredients, units) = try await (ing, unt)
            referenceLoaded = true
        } catch {
            errorMessage = "Couldn't load nutrition reference data: \(error.localizedDescription)"
        }
    }

    func loadDay(_ day: String = DateUtils.todayString()) async {
        guard let userId = client.currentUserId else { return }
        date = day
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            await loadReferenceDataIfNeeded()
            async let logs: [NutritionLogEntry] = client.select(
                "nutrition_log",
                query: [
                    URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                    URLQueryItem(name: "date", value: "eq.\(day)"),
                    URLQueryItem(name: "order", value: "created_at.asc"),
                ], as: [NutritionLogEntry].self
            )
            async let targets: [DailyTarget] = client.select(
                "daily_targets",
                query: [
                    URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                    URLQueryItem(name: "order", value: "effective_date.desc"),
                    URLQueryItem(name: "limit", value: "1"),
                ], as: [DailyTarget].self
            )
            async let water: [WaterLogEntry] = client.select(
                "water_log",
                query: [URLQueryItem(name: "user_id", value: "eq.\(userId)"), URLQueryItem(name: "date", value: "eq.\(day)")],
                as: [WaterLogEntry].self
            )
            async let supplementRows: [[String: String]] = client.select(
                "supplement_log",
                query: [
                    URLQueryItem(name: "user_id", value: "eq.\(userId)"), URLQueryItem(name: "date", value: "eq.\(day)"),
                    URLQueryItem(name: "select", value: "name"), URLQueryItem(name: "order", value: "created_at.asc"),
                ], as: [[String: String]].self
            )
            async let items: [FoodItem] = client.select(
                "food_items",
                query: [
                    URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                    URLQueryItem(name: "order", value: "use_count.desc,last_used_at.desc"),
                    URLQueryItem(name: "limit", value: "100"),
                ], as: [FoodItem].self
            )

            let (fetchedLogs, fetchedTargets, fetchedWater, fetchedSupplements, fetchedItems) =
                try await (logs, targets, water, supplementRows, items)

            foodEntries = fetchedLogs
            proteinCurrent = fetchedLogs.reduce(0) { $0 + ($1.proteinG ?? 0) }
            carbsCurrent = fetchedLogs.reduce(0) { $0 + ($1.carbsG ?? 0) }
            fatCurrent = fetchedLogs.reduce(0) { $0 + ($1.fatG ?? 0) }
            fiberCurrent = fetchedLogs.reduce(0) { $0 + ($1.fiberG ?? 0) }

            let target = fetchedTargets.first
            proteinTarget = target?.proteinG ?? 165
            carbsTarget = target?.carbsG ?? 380
            fatTarget = target?.fatG ?? 70
            fiberTarget = target?.fiberG ?? 0
            waterTargetMl = target?.waterTargetMl ?? 3000

            waterTotalMl = fetchedWater.reduce(0) { $0 + $1.ml }
            supplements = fetchedSupplements.compactMap { $0["name"] }
            foodItems = fetchedItems
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var kcalToday: Int {
        let alcohol = foodEntries.reduce(0.0) { $0 + ($1.alcoholG ?? 0) }
        return Int((proteinCurrent * 4 + carbsCurrent * 4 + fatCurrent * 9 + alcohol * 7).rounded())
    }

    /// Mirrors logFoodBtn's handler: exact match on a saved food name, else a
    /// fuzzy match against recent foods, else the local ingredient-composer,
    /// else a flat per-tag guess. Logs to nutrition_log and updates the
    /// food_items usage cache either way.
    func logFood(name: String, tags: Set<String>, hadShake: Bool, manualAlcohol: Double?, manualFiber: Double?) async {
        guard let userId = client.currentUserId, !name.isEmpty else { return }
        await loadReferenceDataIfNeeded()

        let exact = foodItems.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        let fuzzy = exact == nil ? NutritionEstimator.findFuzzyFoodMatch(name, in: foodItems) : nil
        let known = exact ?? fuzzy

        var protein = 0.0, carbs = 0.0, fat = 0.0
        var alcohol = manualAlcohol ?? 0
        var fiber = manualFiber ?? 0
        var source: MacroSource = .defaultGuess

        if let known {
            protein = known.proteinG ?? 0; carbs = known.carbsG ?? 0; fat = known.fatG ?? 0
            if manualAlcohol == nil { alcohol = known.alcoholG ?? 0 }
            if manualFiber == nil { fiber = known.fiberG ?? 0 }
            source = exact != nil ? .saved : .savedFuzzy
        } else if let composed = NutritionEstimator.estimateMacros(from: name, ingredients: ingredients, units: units) {
            protein = composed.proteinG; carbs = composed.carbsG; fat = composed.fatG
            if manualAlcohol == nil { alcohol = composed.alcoholG }
            source = .composed(composed)
        } else {
            protein = tags.contains("Protein") ? 15 : 0
            carbs = tags.contains("Carbs") ? 20 : 0
            fat = tags.contains("Fat") ? 6 : 0
        }

        do {
            let entry = NewNutritionLogEntry(
                userId: userId, name: name, date: date, covers: Array(tags), hadShake: hadShake,
                proteinG: protein, carbsG: carbs, fatG: fat, alcoholG: alcohol, fiberG: fiber
            )
            try await client.insert("nutrition_log", values: entry)
            await recordFoodItemUsage(name: name, covers: Array(tags), hadShake: hadShake, protein: protein, carbs: carbs, fat: fat, alcohol: alcohol, fiber: fiber)
            await loadDay(date)
            switch source {
            case .saved: lastLogMessage = "Logged — used your saved macros"
            case .savedFuzzy: lastLogMessage = "Logged — matched to a saved food (check serving size)"
            case .composed(let c):
                lastLogMessage = "Logged — composed from \(c.matchedNames.joined(separator: ", "))" +
                    (c.matchedCount < c.totalSegments ? " (\(c.matchedCount)/\(c.totalSegments) items sized — rest skipped)" : "")
            case .defaultGuess: lastLogMessage = "Logged — rough guess, edit in the app if off"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recordFoodItemUsage(name: String, covers: [String], hadShake: Bool, protein: Double, carbs: Double, fat: Double, alcohol: Double, fiber: Double) async {
        guard let userId = client.currentUserId else { return }
        let existing = foodItems.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        do {
            if let existing, let id = existing.id {
                struct Patch: Encodable {
                    let useCount: Int; let proteinG: Double; let carbsG: Double; let fatG: Double; let alcoholG: Double; let fiberG: Double
                    let covers: [String]; let hadShake: Bool
                    enum CodingKeys: String, CodingKey {
                        case useCount = "use_count", proteinG = "protein_g", carbsG = "carbs_g", fatG = "fat_g"
                        case alcoholG = "alcohol_g", fiberG = "fiber_g", covers
                        case hadShake = "had_shake"
                    }
                }
                let patch = Patch(useCount: existing.useCount + 1, proteinG: protein, carbsG: carbs, fatG: fat, alcoholG: alcohol, fiberG: fiber, covers: covers, hadShake: hadShake)
                _ = try await client.update("food_items", query: [URLQueryItem(name: "id", value: "eq.\(id)")], values: patch)
            } else {
                let item = NewFoodItem(userId: userId, name: name, proteinG: protein, carbsG: carbs, fatG: fat, alcoholG: alcohol, fiberG: fiber, covers: covers, hadShake: hadShake, useCount: 1)
                try await client.insert("food_items", values: item)
            }
        } catch {
            // best-effort — never block the log over this
        }
    }

    func logWater(ml: Int) async {
        guard let userId = client.currentUserId else { return }
        waterTotalMl += ml // optimistic
        do {
            try await client.insert("water_log", values: WaterLogEntry(userId: userId, date: date, ml: ml))
        } catch {
            waterTotalMl -= ml
            errorMessage = error.localizedDescription
        }
    }

    func logSupplement(_ name: String) async {
        guard let userId = client.currentUserId, !name.isEmpty else { return }
        do {
            try await client.insert("supplement_log", values: SupplementLogEntry(userId: userId, date: date, name: name))
            supplements.append(name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
