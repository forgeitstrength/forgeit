import Foundation

// Mirrors the Supabase `public` schema used by index.html. Column names match
// exactly (snake_case) via CodingKeys so Codable can talk to PostgREST directly.

struct WorkoutDay: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let code: String
    let name: String
    let sequenceOrder: Int
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case id, code, name, active
        case userId = "user_id"
        case sequenceOrder = "sequence_order"
    }
}

struct ExerciseCycle: Codable, Equatable {
    let cycle: Int
    let prescription: String
}

struct Exercise: Codable, Identifiable, Equatable {
    let id: String
    let workoutDayId: String
    let section: String
    let name: String
    let orderIndex: Int
    let cycles: [ExerciseCycle]
    let muscleGroup: String?
    let videoUrl: String?
    let notes: String?
    let equipment: String?

    enum CodingKeys: String, CodingKey {
        case id, section, name, cycles, notes, equipment
        case workoutDayId = "workout_day_id"
        case orderIndex = "order_index"
        case muscleGroup = "muscle_group"
        case videoUrl = "video_url"
    }
}

struct WorkoutSession: Codable, Identifiable, Equatable {
    var id: String?
    let userId: String
    let workoutDayId: String
    let cycleNumber: Int
    let date: String // yyyy-MM-dd
    var setsCompleted: Int
    var setsTotal: Int
    var generalNote: String?
    var issueNote: String?

    enum CodingKeys: String, CodingKey {
        case id, date
        case userId = "user_id"
        case workoutDayId = "workout_day_id"
        case cycleNumber = "cycle_number"
        case setsCompleted = "sets_completed"
        case setsTotal = "sets_total"
        case generalNote = "general_note"
        case issueNote = "issue_note"
    }
}

struct SessionExerciseLog: Codable, Identifiable, Equatable {
    var id: String?
    let sessionId: String
    let exerciseId: String
    var actual: String?
    var completed: Bool

    enum CodingKeys: String, CodingKey {
        case id, actual, completed
        case sessionId = "session_id"
        case exerciseId = "exercise_id"
    }
}

struct NutritionLogEntry: Codable, Identifiable, Equatable {
    var id: String?
    let userId: String
    var name: String
    let date: String
    var covers: [String]
    var hadShake: Bool
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var alcoholG: Double?
    var fiberG: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, date, covers
        case userId = "user_id"
        case hadShake = "had_shake"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case alcoholG = "alcohol_g"
        case fiberG = "fiber_g"
    }
}

struct FoodItem: Codable, Identifiable, Equatable {
    var id: String?
    let userId: String
    var name: String
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var alcoholG: Double?
    var fiberG: Double?
    var covers: [String]
    var hadShake: Bool
    var useCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, covers
        case userId = "user_id"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case alcoholG = "alcohol_g"
        case fiberG = "fiber_g"
        case hadShake = "had_shake"
        case useCount = "use_count"
    }
}

struct NutritionIngredient: Codable, Equatable {
    let name: String
    let aliases: [String]
    let category: String
    let proteinPer100: Double
    let carbsPer100: Double
    let fatPer100: Double
    let alcoholPer100: Double

    enum CodingKeys: String, CodingKey {
        case name, aliases, category
        case proteinPer100 = "protein_g_per_100"
        case carbsPer100 = "carbs_g_per_100"
        case fatPer100 = "fat_g_per_100"
        case alcoholPer100 = "alcohol_g_per_100"
    }
}

struct NutritionUnit: Codable, Equatable {
    let unit: String
    let category: String
    let gramsPerUnit: Double

    enum CodingKeys: String, CodingKey {
        case unit, category
        case gramsPerUnit = "grams_per_unit"
    }
}

struct DailyTarget: Codable, Equatable {
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let fiberG: Double?
    let waterTargetMl: Int?

    enum CodingKeys: String, CodingKey {
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case waterTargetMl = "water_target_ml"
    }
}

struct WaterLogEntry: Codable {
    let userId: String
    let date: String
    let ml: Int
    enum CodingKeys: String, CodingKey { case date, ml; case userId = "user_id" }
}

struct SupplementLogEntry: Codable {
    let userId: String
    let date: String
    let name: String
    enum CodingKeys: String, CodingKey { case date, name; case userId = "user_id" }
}

// MARK: - Insert-only payloads
//
// Encodable always writes an Optional's nil as JSON `null`, never omits the
// key — and an explicit `"id": null` in an INSERT blocks Postgres from
// applying the column's `gen_random_uuid()` default (a default only fires
// when the column is left out of the statement entirely). So every table
// with a server-generated id gets a matching "New*" struct with no id field
// at all for inserts; the id-bearing struct above is for decoding responses.

struct NewWorkoutSession: Encodable {
    let userId: String
    let workoutDayId: String
    let cycleNumber: Int
    let date: String
    let setsCompleted: Int
    let setsTotal: Int
    let generalNote: String?
    let issueNote: String?

    enum CodingKeys: String, CodingKey {
        case date
        case userId = "user_id"
        case workoutDayId = "workout_day_id"
        case cycleNumber = "cycle_number"
        case setsCompleted = "sets_completed"
        case setsTotal = "sets_total"
        case generalNote = "general_note"
        case issueNote = "issue_note"
    }
}

struct NewSessionExerciseLog: Encodable {
    let sessionId: String
    let exerciseId: String
    let actual: String
    let completed: Bool

    enum CodingKeys: String, CodingKey {
        case actual, completed
        case sessionId = "session_id"
        case exerciseId = "exercise_id"
    }
}

struct NewNutritionLogEntry: Encodable {
    let userId: String
    let name: String
    let date: String
    let covers: [String]
    let hadShake: Bool
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let alcoholG: Double
    let fiberG: Double

    enum CodingKeys: String, CodingKey {
        case name, date, covers
        case userId = "user_id"
        case hadShake = "had_shake"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case alcoholG = "alcohol_g"
        case fiberG = "fiber_g"
    }
}

struct NewFoodItem: Encodable {
    let userId: String
    let name: String
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let alcoholG: Double
    let fiberG: Double
    let covers: [String]
    let hadShake: Bool
    let useCount: Int

    enum CodingKeys: String, CodingKey {
        case name, covers
        case userId = "user_id"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case alcoholG = "alcohol_g"
        case fiberG = "fiber_g"
        case hadShake = "had_shake"
        case useCount = "use_count"
    }
}
