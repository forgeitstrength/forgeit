import SwiftUI

struct WatchQuickLogView: View {
    @EnvironmentObject var nutrition: NutritionService
    private let waterOptions = [250, 500, 750]
    private let commonSupplements = ["Creatine", "Whey", "Vitamin D", "Fish Oil"]

    var body: some View {
        NavigationStack {
            List {
                Section("Water — \(nutrition.waterTotalMl) ml") {
                    ForEach(waterOptions, id: \.self) { ml in
                        Button("+\(ml) ml") { Task { await nutrition.logWater(ml: ml) } }
                    }
                }
                Section("Supplements") {
                    ForEach(commonSupplements, id: \.self) { name in
                        let logged = nutrition.supplements.contains(name)
                        Button {
                            Task { await nutrition.logSupplement(name) }
                        } label: {
                            HStack {
                                Text(name)
                                if logged { Spacer(); Image(systemName: "checkmark").foregroundStyle(.green) }
                            }
                        }
                        .disabled(logged)
                    }
                }
                Section {
                    Text("\(nutrition.kcalToday) kcal today").font(.caption)
                    Text("P \(Int(nutrition.proteinCurrent))g · C \(Int(nutrition.carbsCurrent))g · F \(Int(nutrition.fatCurrent))g")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Quick Log")
        }
    }
}
