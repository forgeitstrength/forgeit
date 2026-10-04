import Foundation

/// Swift port of index.html's local nutrition estimator (splitFoodSegments /
/// estimateMacrosFromIngredients / findFuzzyFoodMatch). Entirely offline — no
/// network call, matches against NutritionIngredient/NutritionUnit rows
/// fetched once and cached by NutritionService. See CLAUDE.md for the
/// `findFuzzyFoodMatch` bug this already had to fix once on the web side
/// (a one-ingredient preset swallowing a whole different meal) — the fix
/// (require >= 2 shared tokens before trusting a reuse match) is baked in
/// here from the start.
struct ComposedMacros {
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let alcoholG: Double
    let matchedCount: Int
    let totalSegments: Int
    let matchedNames: [String]
}

enum NutritionEstimator {
    static let stopwords: Set<String> = [
        "with", "and", "the", "a", "an", "of", "from", "for", "in", "on", "without", "boiled", "grill", "grilled",
        "gms", "gm", "g", "cup", "cups", "tbsp", "tsp", "ml", "oz", "lb", "lbs", "whole", "big", "small", "large",
    ]

    static func tokenize(_ s: String) -> [String] {
        let lowered = s.lowercased()
        let ns = lowered as NSString
        let pattern = try! NSRegularExpression(pattern: "[^a-z0-9\\s]")
        let cleaned = pattern.stringByReplacingMatches(in: lowered, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        return cleaned
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 && !stopwords.contains($0) && !$0.allSatisfy { $0.isNumber } }
    }

    static func matchScore(_ a: String, _ b: String) -> Double {
        let ta = Set(tokenize(a)), tb = Set(tokenize(b))
        guard !ta.isEmpty, !tb.isEmpty else { return 0 }
        let overlap = ta.intersection(tb).count
        return Double(overlap) / Double(min(ta.count, tb.count))
    }

    static let fuzzyThreshold = 0.7

    static func findIngredientMatch(_ text: String, ingredients: [NutritionIngredient]) -> NutritionIngredient? {
        var best: NutritionIngredient?
        var bestScore = 0.0
        for ing in ingredients {
            var names = [ing.name]
            names.append(contentsOf: ing.aliases)
            for n in names {
                let score = matchScore(text, n)
                if score > bestScore { bestScore = score; best = ing }
            }
        }
        guard bestScore >= fuzzyThreshold else { return nil }
        return best
    }

    static func findUnitGrams(_ unitWord: String, category: String, units: [NutritionUnit]) -> Double? {
        guard !unitWord.isEmpty else { return nil }
        func norm(_ u: String) -> String {
            var s = u.lowercased()
            if s.hasSuffix("s") { s.removeLast() }
            return s
        }
        let uNorm = norm(unitWord)
        if let row = units.first(where: { norm($0.unit) == uNorm && $0.category == category }) { return row.gramsPerUnit }
        if let row = units.first(where: { norm($0.unit) == uNorm && $0.category == "generic" }) { return row.gramsPerUnit }
        return nil
    }

    private static let wordNumbers: [String: String] = [
        "quarter": "0.25", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6",
        "half": "0.5", "a": "1", "an": "1",
    ]

    static func normalizeWordNumbers(_ text: String) -> String {
        var result = replaceAll(text, pattern: "\\bhalf an?\\b", withTemplate: "0.5", caseInsensitive: true)
        let pattern = try! NSRegularExpression(pattern: "\\b(quarter|one|two|three|four|five|six|half|a|an)\\b", options: .caseInsensitive)
        let ns = result as NSString
        var output = ""
        var lastEnd = 0
        for m in pattern.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
            output += ns.substring(with: NSRange(location: lastEnd, length: m.range.location - lastEnd))
            let word = ns.substring(with: m.range).lowercased()
            output += wordNumbers[word] ?? ns.substring(with: m.range)
            lastEnd = m.range.location + m.range.length
        }
        output += ns.substring(from: lastEnd)
        result = output
        return result
    }

    private static func replaceAll(_ text: String, pattern: String, withTemplate template: String, caseInsensitive: Bool = false) -> String {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let ns = text as NSString
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }

    private static func splitByRegex(_ text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [text] }
        let ns = text as NSString
        var result: [String] = []
        var lastEnd = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result.append(ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd)))
            lastEnd = match.range.location + match.range.length
        }
        result.append(ns.substring(from: lastEnd))
        return result
    }

    /// Paren-aware split: a comma inside "(...)" doesn't start a new segment,
    /// and a run like "2 cups rice 180g salmon" is cut wherever a second
    /// "<number><unit-word>" starts, even with no punctuation between items.
    static func splitFoodSegments(_ text: String) -> [String] {
        let str = normalizeWordNumbers(text)
        var masked = ""
        var depth = 0
        for ch in str {
            if ch == "(" { depth += 1 }
            if ch == ")" { depth = max(0, depth - 1) }
            masked.append((ch == "," && depth > 0) ? " " : ch)
        }
        let topSegments = splitByRegex(masked, pattern: ",|\\band\\b|\\+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var out: [String] = []
        let subQtyPattern = try! NSRegularExpression(pattern: "([\\d.\\/]+)\\s*([a-zA-Z]+)")
        for seg in topSegments {
            let ns = seg as NSString
            let matches = subQtyPattern.matches(in: seg, range: NSRange(location: 0, length: ns.length))
            if matches.count <= 1 {
                out.append(seg)
                continue
            }
            for (i, m) in matches.enumerated() {
                let start = m.range.location
                let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
                let piece = ns.substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: .whitespaces)
                if !piece.isEmpty { out.append(piece) }
            }
        }
        return out
    }

    /// Entirely local — decomposes free-typed food text against the
    /// nutrition_ingredients/nutrition_units reference tables. A segment
    /// that can't be confidently matched AND sized is skipped rather than
    /// guessed, same as the web app.
    static func estimateMacros(from text: String, ingredients: [NutritionIngredient], units: [NutritionUnit]) -> ComposedMacros? {
        let segments = splitFoodSegments(text)
        var protein = 0.0, carbs = 0.0, fat = 0.0, alcohol = 0.0
        var resolved = 0
        var matchedNames: [String] = []
        let leadingQtyPattern = try! NSRegularExpression(pattern: "^([\\d.\\/]+)\\s*([a-zA-Z]*)")

        for seg in segments {
            let ns = seg as NSString
            guard let m = leadingQtyPattern.firstMatch(in: seg, range: NSRange(location: 0, length: ns.length)) else { continue }
            let qtyStr = ns.substring(with: m.range(at: 1))
            let unitRange = m.range(at: 2)
            let unitStr = unitRange.location != NSNotFound ? ns.substring(with: unitRange) : ""

            let qty: Double
            if qtyStr.contains("/") {
                let parts = qtyStr.split(separator: "/")
                guard parts.count == 2, let n = Double(parts[0]), let d = Double(parts[1]), d != 0 else { continue }
                qty = n / d
            } else {
                guard let q = Double(qtyStr) else { continue }
                qty = q
            }
            guard qty.isFinite, qty != 0 else { continue }
            guard let ing = findIngredientMatch(seg, ingredients: ingredients) else { continue }
            guard let perUnit = findUnitGrams(unitStr, category: ing.category, units: units) else { continue }

            let scale = (qty * perUnit) / 100
            protein += ing.proteinPer100 * scale
            carbs += ing.carbsPer100 * scale
            fat += ing.fatPer100 * scale
            alcohol += ing.alcoholPer100 * scale
            resolved += 1
            matchedNames.append(ing.name)
        }

        guard resolved > 0 else { return nil }
        return ComposedMacros(
            proteinG: protein.rounded(), carbsG: carbs.rounded(), fatG: fat.rounded(), alcoholG: alcohol.rounded(),
            matchedCount: resolved, totalSegments: segments.count, matchedNames: matchedNames
        )
    }

    /// Reuses a previously-logged food's macros for a re-typed description of
    /// the same meal. Requires at least 2 tokens of real overlap on both
    /// sides — a single shared staple word ("rice", "chicken") is not enough
    /// (that's the bug that corrupted real logged data on the web app; see
    /// CLAUDE.md). Exact-name matches should be checked by the caller first.
    static func findFuzzyFoodMatch(_ name: String, in items: [FoodItem]) -> FoodItem? {
        let nameTokenCount = Set(tokenize(name)).count
        var best: FoodItem?
        var bestScore = 0.0
        for item in items {
            let otherCount = Set(tokenize(item.name)).count
            if min(nameTokenCount, otherCount) < 2 { continue }
            let score = matchScore(name, item.name)
            if score > bestScore { bestScore = score; best = item }
        }
        return bestScore >= fuzzyThreshold ? best : nil
    }
}
