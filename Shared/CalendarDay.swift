import Foundation

/// A day on the calendar, with no time and no clock: the day a ticket site
/// says results are out, which is the same day wherever the reader is.
///
/// Kept as `2026-10-12`, so a record reads the same in every zone and in the
/// CloudKit Console — a Gregorian year, month and day, whatever calendar the
/// phone that wrote it is set to. Every `calendar` handed in below is read
/// for its clock alone; the day is counted on the Gregorian calendar
/// (``Foundation/Calendar/gregorian(in:)``). Taken from the reader's own on a
/// phone set to the Japanese calendar, the day was kept as `0008-10-12` — the
/// year of Reiwa — and read back on every other device as the year 8.
nonisolated struct CalendarDay: Hashable, Comparable, Sendable {
    var year: Int
    var month: Int
    var day: Int

    /// The day a moment falls on, on `calendar`'s clock — the reader's, by
    /// default.
    init(_ date: Date, in calendar: Calendar = .current) {
        let parts = calendar.asGregorian.dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 1970
        month = parts.month ?? 1
        day = parts.day ?? 1
    }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Midnight starting the day, on `calendar`'s clock.
    func date(in calendar: Calendar = .current) -> Date {
        calendar.asGregorian.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    /// Whole days from today to this one: 0 today, negative once it is past.
    func daysAway(from now: Date = .now, in calendar: Calendar = .current) -> Int {
        let counted = calendar.asGregorian
        return counted.dateComponents([.day], from: counted.startOfDay(for: now), to: date(in: counted)).day ?? 0
    }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    var text: String { String(format: "%04d-%02d-%02d", year, month, day) }

    init?(text: String) {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: Self.gregorianYear(parts[0]), month: parts[1], day: parts[2])
    }

    /// The Gregorian year a kept year stands for. The builds before every day
    /// was counted on the Gregorian calendar kept the year of the reader's own:
    /// on a phone set to the Japanese calendar the year of Reiwa (8 for 2026),
    /// on one set to the Buddhist calendar the Buddhist Era (2569). Neither is
    /// a year a results day falls in, so each is read back as the year it
    /// was — save a day picked in Heisei, early in 2019, which reads as Reiwa
    /// and cannot be told apart.
    ///
    /// Read so and not written back: the old column is never written again,
    /// and the first change to the list moves it into rows of this build's
    /// own (``LibraryLottery``).
    private static func gregorianYear(_ year: Int) -> Int {
        switch year {
        case 1 ..< 100: year + 2018
        case 2400...: year - 543
        default: year
        }
    }
}

nonisolated extension CalendarDay: Codable {
    init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let day = CalendarDay(text: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Not a day: \(text)"))
        }
        self = day
    }

    func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(text)
    }
}

nonisolated extension CalendarDay {
    /// Whether this day, in an earlier year, comes round on `today`: the same
    /// month and the same day — and the 29th of February on the 28th in a
    /// year without one, so an event on a leap day comes round every year
    /// rather than every fourth. What On This Day reads its memories by, in
    /// the app and on its widget.
    func comesRound(on today: CalendarDay) -> Bool {
        if month == today.month, day == today.day { return true }
        return month == 2 && day == 29
            && today.month == 2 && today.day == 28 && !Self.isLeapYear(today.year)
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
    }
}
