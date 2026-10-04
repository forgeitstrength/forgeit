import Foundation

enum DateUtils {
    /// Matches index.html's todayStr(): local calendar date, not UTC.
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func todayString() -> String { dayFormatter.string(from: Date()) }

    static func string(from date: Date) -> String { dayFormatter.string(from: date) }

    static func date(from string: String) -> Date? { dayFormatter.date(from: string) }
}
