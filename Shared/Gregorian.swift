import Foundation

nonisolated extension Calendar {
    /// The Gregorian calendar on `zone`'s clock — what every year, month and
    /// day the app counts, keeps or compares is counted on.
    ///
    /// Never `Calendar.current` for that. A reader can set their phone to the
    /// Japanese calendar, where 2026 is the year 8 of Reiwa, or the Buddhist
    /// one, where it is 2569: a year read off one calendar and handed to
    /// another lands in 4044 or in the year 8, and a day kept as `0008-10-12`
    /// means nothing to a device set otherwise. The reader's own calendar is
    /// for naming months and days on screen, never for counting them.
    static func gregorian(in zone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// This calendar's clock, counted on the Gregorian calendar — itself
    /// where it already is one, which spares a list of hundreds a calendar
    /// made for each row.
    var asGregorian: Calendar {
        identifier == .gregorian ? self : .gregorian(in: timeZone)
    }
}
