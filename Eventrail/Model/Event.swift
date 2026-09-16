import Foundation

/// A performer billed on an event's public Eventernote page.
struct Performer: Identifiable, Hashable {
    let name: String
    let role: String

    var id: String { "\(name)|\(role)" }
}

/// An event as imported from a public Eventernote page.
///
/// Everything here is publicly published information displayed verbatim: titles,
/// venues and performer names stay in the language Eventernote published them in
/// and are never translated. The reader's own record lives in ``Tracking``.
struct Event: Identifiable, Hashable {
    let id: String
    let title: String
    /// The headline act, used when grouping the library by artist.
    let artist: String
    let venue: String
    /// Ward, city and capacity, as printed on the venue's page.
    let venueDetail: String
    let doorsOpen: Date
    let startsAt: Date
    /// The venue's time zone. Door and start times are shown in it: an event at
    /// 17:00 in Tokyo reads 17:00 wherever the reader happens to be.
    let timeZone: TimeZone
    /// How many people list this event on Eventernote — imported, never edited here.
    let listedAttendees: Int
    let performers: [Performer]
    /// The original page. Account actions happen there, not in this app.
    let sourceURL: URL

    var isUpcoming: Bool { startsAt >= .now }
}

extension Event {
    /// Dates and times render in the venue's zone, but in the reader's locale.
    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar
    }

    private func formatted(_ style: Date.FormatStyle) -> String {
        var style = style
        style.timeZone = timeZone
        return startsAt.formatted(style)
    }

    /// "Sat, Oct 3" in US English, formatted for the reader's locale elsewhere.
    var dayLine: String {
        formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    var timeLine: String {
        time(of: startsAt)
    }

    var doorsLine: String {
        time(of: doorsOpen)
    }

    private func time(of date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// "Saturday, October 3, 2026" — the detail sheet's fuller form.
    var longDateLine: String {
        formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }

    /// "OCTOBER 2026" for the group header.
    var monthGroupLabel: String {
        formatted(.dateTime.month(.wide).year()).localizedUppercase
    }

    var monthGroupKey: DateComponents {
        calendar.dateComponents([.year, .month], from: startsAt)
    }
}
