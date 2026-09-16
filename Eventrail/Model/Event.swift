import Foundation

/// Someone billed on an event's public Eventernote page.
///
/// The site bills performers by name only; it publishes no instrument or role,
/// so there is none to show here.
nonisolated struct Performer: Identifiable, Hashable, Codable, Sendable {
    let name: String
    /// Eventernote's own identifier, when the page linked the name to a profile.
    let actorID: Int?

    var id: String { actorID.map(String.init) ?? name }

    init(name: String, actorID: Int? = nil) {
        self.name = name
        self.actorID = actorID
    }
}

/// An event as imported from a public Eventernote page.
///
/// Everything here is publicly published information displayed verbatim: titles,
/// venues and performer names stay in the language Eventernote published them in
/// and are never translated. The reader's own record lives in ``Tracking``.
///
/// A search result carries only what a list row prints, so times, performers and
/// the listed head count are optional until ``isDetailed`` is true and the
/// event's own page has been imported.
nonisolated struct Event: Identifiable, Hashable, Codable, Sendable {
    /// Eventernote's event id, as it appears in the page's path.
    let id: String
    let title: String
    /// The first name billed, used when grouping the library by artist.
    let artist: String
    let venue: String
    /// Address and capacity, as printed on the venue's page.
    var venueDetail: String?
    /// The venue's Eventernote id, so its page can be imported on demand.
    let placeID: Int?
    /// Midnight in the venue's zone on the day of the event. Eventernote always
    /// publishes the day; it often has no times yet for an announced event.
    let date: Date
    let doorsOpen: Date?
    let startsAt: Date?
    let endsAt: Date?
    /// The venue's time zone. Door and start times are shown in it: an event at
    /// 17:00 in Tokyo reads 17:00 wherever the reader happens to be.
    let timeZone: TimeZone
    /// How many people list this event on Eventernote — imported, never edited here.
    let listedAttendees: Int?
    let performers: [Performer]
    /// The flyer Eventernote hosts for the event.
    let imageURL: URL?
    /// The original page. Account actions happen there, not in this app.
    let sourceURL: URL
    /// Whether the event's own page has been imported, or only a list row.
    let isDetailed: Bool

    /// Events are published in Japan Standard Time.
    static let publishedZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt

    /// Orders the library. A day with no published start time sorts to its
    /// own morning rather than to whatever the reader's zone calls midnight.
    var sortDate: Date { startsAt ?? date }

    /// Upcoming until its day is over: an event announced without a start time
    /// should not drop into Past at the stroke of midnight.
    var isUpcoming: Bool {
        (calendar.date(byAdding: .day, value: 1, to: date) ?? date) > .now
    }
}

nonisolated extension Event {
    /// Dates and times render in the venue's zone, but in the reader's locale.
    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar
    }

    private func formatted(_ style: Date.FormatStyle) -> String {
        var style = style
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// "Sat, Oct 3" in US English, formatted for the reader's locale elsewhere.
    var dayLine: String {
        formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// Nil whenever Eventernote has not published the time yet.
    var timeLine: String? { startsAt.map(time(of:)) }
    var doorsLine: String? { doorsOpen.map(time(of:)) }
    var endsLine: String? { endsAt.map(time(of:)) }

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
        calendar.dateComponents([.year, .month], from: date)
    }
}

nonisolated extension Event {
    /// Replaces the imported fields with a freshly imported copy, keeping this
    /// event's identity. The reader's ``Tracking`` lives outside the event and
    /// is untouched by any import.
    func merging(_ imported: Event) -> Event {
        Event(
            id: id,
            title: imported.title,
            artist: imported.artist,
            venue: imported.venue,
            // A list row has no venue detail; a re-import of one must not blank
            // out what the venue's page already supplied.
            venueDetail: imported.venueDetail ?? venueDetail,
            placeID: imported.placeID ?? placeID,
            date: imported.date,
            doorsOpen: imported.doorsOpen ?? doorsOpen,
            startsAt: imported.startsAt ?? startsAt,
            endsAt: imported.endsAt ?? endsAt,
            timeZone: imported.timeZone,
            listedAttendees: imported.listedAttendees ?? listedAttendees,
            performers: imported.performers.isEmpty ? performers : imported.performers,
            imageURL: imported.imageURL ?? imageURL,
            sourceURL: imported.sourceURL,
            isDetailed: imported.isDetailed || isDetailed
        )
    }
}
