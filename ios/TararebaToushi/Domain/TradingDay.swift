import Foundation

/// A civil date with no dependency on the device's calendar or time zone.
nonisolated struct TradingDay: Hashable, Comparable, Sendable {
    let rawValue: String
    let date: Date

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? TimeZone(secondsFromGMT: 32_400) ?? .gmt
        return calendar
    }

    init(_ rawValue: String) throws {
        guard rawValue.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else {
            throw DataIssue("日付の形式が正しくありません。")
        }
        let parts = rawValue.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1900...2200).contains(parts[0]),
            let date = Self.calendar.date(
                from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        else {
            throw DataIssue("日付の範囲が正しくありません。")
        }
        let checked = Self.calendar.dateComponents([.year, .month, .day], from: date)
        guard checked.year == parts[0], checked.month == parts[1], checked.day == parts[2] else {
            throw DataIssue("存在しない日付が含まれています。")
        }
        self.rawValue = rawValue
        self.date = date
    }

    init(date: Date) throws {
        let parts = Self.calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            throw DataIssue("日付を読み取れませんでした。")
        }
        try self.init(String(format: "%04d-%02d-%02d", year, month, day))
    }

    func yearsBefore(_ years: Int) throws -> TradingDay {
        guard let earlier = Self.calendar.date(byAdding: .year, value: -years, to: date) else {
            throw DataIssue("期間を計算できませんでした。")
        }
        return try TradingDay(date: earlier)
    }

    var label: String { rawValue.replacingOccurrences(of: "-", with: "/") }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
