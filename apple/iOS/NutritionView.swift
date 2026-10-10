import SwiftUI

struct NutritionView: View {
    @EnvironmentObject var nutrition: NutritionService
    @State private var foodText = ""
    @State private var selectedTags: Set<String> = []
    @State private var hadShake = false
    @State private var supplementText = ""

    private let allTags = ["Protein", "Carbs", "Fat"]
    private let waterOptions = [250, 500, 750]
    private let commonSupplements = ["Creatine", "Whey", "Vitamin D", "Fish Oil"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = nutrition.errorMessage {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }

                    macroRings

                    Text("\(nutrition.kcalToday) kcal today").font(.footnote).foregroundStyle(.secondary)

                    logFoodSection
                    foodListSection
                    waterSection
                    supplementSection
                }
                .padding()
            }
            .navigationTitle("Nutrition")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await nutrition.loadDay(nutrition.date) }
        }
    }

    private var macroRings: some View {
        HStack(spacing: 16) {
            macroBar(label: "Protein", current: nutrition.proteinCurrent, target: nutrition.proteinTarget, color: .red)
            macroBar(label: "Carbs", current: nutrition.carbsCurrent, target: nutrition.carbsTarget, color: .blue)
            macroBar(label: "Fat", current: nutrition.fatCurrent, target: nutrition.fatTarget, color: .yellow)
        }
    }

    private func macroBar(label: String, current: Double, target: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color(.secondarySystemBackground), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: target > 0 ? min(1, current / target) : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(current))g").font(.caption.bold())
            }
            .frame(width: 64, height: 64)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var logFoodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Log food").font(.headline)
            TextField("What did you eat? e.g. 2 idli, chutney", text: $foodText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            HStack {
                ForEach(allTags, id: \.self) { tag in
                    Button {
                        if selectedTags.contains(tag) { selectedTags.remove(tag) } else { selectedTags.insert(tag) }
                    } label: {
                        Text(tag).font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(selectedTags.contains(tag) ? Color.orange : Color(.secondarySystemBackground))
                            .foregroundStyle(selectedTags.contains(tag) ? Color.white : Color.primary)
                            .clipShape(Capsule())
                    }
                }
                Toggle("Shake", isOn: $hadShake).font(.caption).labelsHidden()
                Text("🥤").opacity(hadShake ? 1 : 0.3)
            }
            Button("Log") {
                let text = foodText
                Task {
                    await nutrition.logFood(name: text, tags: selectedTags, hadShake: hadShake, manualAlcohol: nil, manualFiber: nil)
                    foodText = ""; selectedTags = []; hadShake = false
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(foodText.trimmingCharacters(in: .whitespaces).isEmpty)

            if let msg = nutrition.lastLogMessage {
                Text(msg).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var foodListSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today's food").font(.headline)
            if nutrition.foodEntries.isEmpty {
                Text("Nothing logged yet.").font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(nutrition.foodEntries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).font(.subheadline)
                        Text("P \(Int(entry.proteinG ?? 0))g · C \(Int(entry.carbsG ?? 0))g · F \(Int(entry.fatG ?? 0))g")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var waterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Water — \(nutrition.waterTotalMl) ml today").font(.headline)
            HStack {
                ForEach(waterOptions, id: \.self) { ml in
                    Button("+\(ml) ml") { Task { await nutrition.logWater(ml: ml) } }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var supplementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Supplements").font(.headline)
            HStack {
                ForEach(commonSupplements, id: \.self) { name in
                    let logged = nutrition.supplements.contains(name)
                    Button(name) { Task { await nutrition.logSupplement(name) } }
                        .buttonStyle(.bordered)
                        .tint(logged ? .green : .gray)
                        .disabled(logged)
                }
            }
            HStack {
                TextField("Other supplement", text: $supplementText)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let name = supplementText
                    Task { await nutrition.logSupplement(name); supplementText = "" }
                }
                .disabled(supplementText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
