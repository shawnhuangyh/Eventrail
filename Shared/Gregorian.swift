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

nonisolated extension FormatStyle where Self == Date.FormatStyle {
    /// Dates named on the Gregorian calendar, in the reader's language, on
    /// `zone`'s clock — for a part of a day the app counts there, printed on
    /// its own: a month over a day's number, a year after "2 years ago".
    ///
    /// The reader's own calendar names a date printed whole. A part of one
    /// printed alone beside a Gregorian figure is another matter: on a phone
    /// set to the Chinese or the Hebrew calendar a results day of 12 October
    /// was that calendar's month over the 12, a day that does not exist, and
    /// on the Japanese one a memory of 2025 read "1 year ago · 7".
    static func gregorian(in zone: TimeZone = .current) -> Date.FormatStyle {
        Date.FormatStyle(calendar: .gregorian(in: zone), timeZone: zone)
    }
}
