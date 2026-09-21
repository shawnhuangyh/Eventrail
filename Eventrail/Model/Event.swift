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

/// A hashtag an event's page publishes, and the timeline the site points it at.
///
/// Both halves are carried because the site publishes both: the tag as it is
/// written, and the search it links to. Composing the second from the first
/// would mean guessing at a host, and Eventernote still writes its links
/// against `mobile.twitter.com`.
nonisolated struct Hashtag: Identifiable, Hashable, Codable, Sendable {
    /// As printed, with the "#".
    let tag: String
    /// The timeline for the tag, as the page links it.
    let searchURL: URL

    var id: String { tag }
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
    /// The address alone, without the capacity beside it. Kept apart from
    /// ``venueDetail`` because a calendar entry needs something a map can
    /// resolve, and "10,000人" is not part of any address.
    var venueAddress: String?
    /// The venue's Eventernote id, so its page can be imported on demand.
    let placeID: Int?
    /// Midnight in the venue's zone on the day of the event. Eventernote always
    /// publishes the day; it often has no times yet for an announced event.
    ///
    /// Kept as an instant, and so re-readable: what the site printed is a wall
    /// clock, and ``published(in:)`` is how these four are read again once the
    /// hall turns out to keep a different one.
    var date: Date
    var doorsOpen: Date?
    var startsAt: Date?
    var endsAt: Date?
    /// The venue's time zone. Door and start times are shown in it: an event at
    /// 17:00 in Tokyo reads 17:00 wherever the reader happens to be.
    ///
    /// ``publishedZone`` until something says otherwise, because the page
    /// prints a clock and never a zone; the hall's own once ``VenuePlaces`` has
    /// placed it outside Japan — see ``published(in:)``.
    var timeZone: TimeZone
    /// How many people list this event on Eventernote — imported, never edited here.
    let listedAttendees: Int?
    let performers: [Performer]
    /// 概要, as the page's own members wrote it.
    ///
    /// The one free-written field on an Eventernote event, and so where
    /// everything the site has no box for ends up: ticket prices and seat
    /// types, the on-sale date, which tour the night belongs to, who is on
    /// which stage. Kept with its line breaks, because most of them are
    /// written as a list rather than as a paragraph.
    var summary: String? = nil
    /// 関連リンク: where the announcement was made — the promoter's page, the
    /// ticket agency, the post that broke the news.
    ///
    /// Nil where no import has asked for them, empty where the page carries
    /// none, and the difference matters to ``merging(_:)``: a list row has no
    /// links and must not blank out what the event's own page supplied.
    var relatedLinks: [URL]? = nil
    /// Twitterハッシュタグ: what to follow the night under.
    var hashtags: [Hashtag]? = nil
    /// Who last edited the page, as the site's edit history names them.
    ///
    /// Eventernote's pages are written by its members rather than by the
    /// promoter, so how recently one was touched is part of reading it: an
    /// upcoming date last edited two years ago has times nobody has checked
    /// since.
    var editedBy: String? = nil
    /// When that edit was, from the "127日前" the history prints beside it.
    /// Turned into a date at import, so it does not go on saying "127 days"
    /// for as long as the copy is held.
    var editedAt: Date? = nil
    /// The flyer Eventernote hosts for the event.
    let imageURL: URL?
    /// The original page. Account actions happen there, not in this app.
    let sourceURL: URL
    /// Whether the event's own page has been imported, or only a list row.
    let isDetailed: Bool
    /// Which ``currentDetailFormat`` that import read. Nil for a copy imported
    /// before the app numbered them.
    var detailFormat: Int? = nil

    /// The zone an event's times are read in until its hall says otherwise.
    ///
    /// Eventernote is a Japanese site and nearly every night it publishes is in
    /// Japan, which is one zone from 与那国 to 稚内. It carries the odd night
    /// abroad as well — a dome in Taipei, a hall in Shanghai — and its members
    /// write those in the hall's own clock, with nothing on the page to say so.
    /// So this is where every import starts, and ``published(in:)`` is what
    /// reads it again once ``VenuePlaces`` has placed the hall somewhere that
    /// keeps a different one.
    static let publishedZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt

    /// How much of an event's own page an import reads, as a number that goes
    /// up whenever it starts reading more.
    ///
    /// 1: the description, the related links, the hashtags and the edit history.
    static let currentDetailFormat = 1

    /// Whether this copy holds everything the event's page publishes *as this
    /// build reads it*.
    ///
    /// ``isDetailed`` answers the older question — whether the page was read at
    /// all — and cannot answer this one. A library imported before the
    /// description was read carries it true and no description, and nothing
    /// would ever go back for the rest. So a sheet opened on one of those reads
    /// the page once more; a bulk refresh deliberately does not, since that
    /// would be nine hundred requests for pages nobody is looking at.
    var isFullyDetailed: Bool {
        isDetailed && (detailFormat ?? 0) >= Event.currentDetailFormat
    }

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

    /// "Sun, Oct 12, 2025" in US English, "2025年10月12日(日)" in Japanese —
    /// formatted for the reader's locale, and always carrying the year.
    ///
    /// The year on every row rather than only on the rows that need one. Most
    /// of what these rows are is history: the Passport is nothing else, My
    /// Events keeps every night that has been alongside the ones ahead, a
    /// performer's listing runs from next spring back to whenever the site
    /// first carried them, and the Following tab is as likely to be showing
    /// next year as this one. A row that printed only a day and a month left
    /// the reader to work the year out from whatever card or header the row
    /// happened to sit under, and the cards that group nothing by month —
    /// every one on the Passport — gave them nothing to work it out from.
    ///
    /// Printing it only where it differs from this year would be the tidier
    /// rule and the worse one: a bare row would then mean something, and the
    /// reader would have to know it did.
    var dayLine: String {
        formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
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

    /// "GMT+9" — what `zone` is set to on the night of this event.
    ///
    /// The offset and no place beside it, though Foundation will gladly name
    /// one. **A zone identifier is the map provider's reading of where the
    /// hall stands, and the provider is chosen by where the *reader* stands:**
    /// a phone served from mainland China files a hall in Taipei under
    /// `Asia/Shanghai`, which Foundation then names "China mainland Time"
    /// under a Taipei address on the same screen. Seoul reads GMT+9 and is not
    /// "Japan Time" either. The offset is the part this app is actually sure
    /// of, and it is the part that moves the times.
    ///
    /// Read at the night itself rather than at today, so a summer date abroad
    /// says the offset that night keeps rather than the one it keeps now.
    func offsetLine(in zone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted)
        style.timeZone = zone
        return sortDate.formatted(style.timeZone(.localizedGMT(.short)))
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

    /// The written date this is published on, as an instant the reader's own
    /// calendar puts on that day.
    ///
    /// A date picker deals in the reader's calendar and Eventernote publishes
    /// in the venue's, so the two are compared as *written dates* rather than
    /// as instants: midnight in Kobe is the evening before in London, and
    /// handing either one the other's midnight puts a show on the wrong day.
    var localDay: Date {
        let fields = calendar.dateComponents([.year, .month, .day], from: date)
        return Calendar.current.date(from: fields) ?? date
    }

    /// Whether this falls on or between the two days the reader picked, both
    /// ends included. Compared day against day — see ``localDay`` — so the hour
    /// either end happens to carry never decides it.
    func falls(in days: ClosedRange<Date>) -> Bool {
        let calendar = Calendar.current
        return localDay >= calendar.startOfDay(for: days.lowerBound)
            && localDay <= calendar.startOfDay(for: days.upperBound)
    }
}

nonisolated extension Event {
    /// The same published day and times, read on `zone`'s clock instead of on
    /// the one this copy carries.
    ///
    /// An Eventernote page prints a wall clock and no zone: 開演 18:00 is
    /// 18:00 at the hall, and a hall in Taipei means 18:00 in Taipei. The
    /// instants here are that clock read in a zone, so a night abroad is not a
    /// different fact to import but the same one read again — which is all
    /// this does, once ``VenuePlaces`` has said which clock the hall keeps.
    ///
    /// Nothing the reader sees moves: every line on a screen is formatted in
    /// the event's own zone, so the sheet goes on saying 18:00. What moves is
    /// the instant behind it, which is what the calendar entry, its alert and
    /// the ordering of the library are all made of.
    func published(in zone: TimeZone) -> Event {
        guard zone != timeZone else { return self }

        var printed = Calendar(identifier: .gregorian)
        printed.timeZone = timeZone
        var there = printed
        there.timeZone = zone

        /// The clock this instant reads on the page, read again at the hall.
        func reread(_ instant: Date?) -> Date? {
            guard let instant else { return nil }
            let clock = printed.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: instant)
            // A clock the zone does not have — the hour a country skips going
            // into summer time — leaves the instant where it was rather than
            // dropping a time the site did publish.
            return there.date(from: clock) ?? instant
        }

        var event = self
        event.timeZone = zone
        event.date = reread(date) ?? date
        event.doorsOpen = reread(doorsOpen)
        event.startsAt = reread(startsAt)
        event.endsAt = reread(endsAt)
        return event
    }

    /// Replaces the imported fields with a freshly imported copy, keeping this
    /// event's identity. The reader's ``Tracking`` lives outside the event and
    /// is untouched by any import.
    func merging(_ imported: Event) -> Event {
        // Which zone the clock on the page is read in is this device's answer
        // rather than the site's — every import reads ``publishedZone`` and
        // knows no better — so a re-import must not quietly put a hall abroad
        // back on Tokyo time between one placing and the next.
        let imported = imported.timeZone == Event.publishedZone && timeZone != Event.publishedZone
            ? imported.published(in: timeZone)
            : imported

        return Event(
            id: id,
            title: imported.title,
            artist: imported.artist,
            venue: imported.venue,
            // A list row has no venue detail; a re-import of one must not blank
            // out what the venue's page already supplied.
            venueDetail: imported.venueDetail ?? venueDetail,
            venueAddress: imported.venueAddress ?? venueAddress,
            placeID: imported.placeID ?? placeID,
            date: imported.date,
            doorsOpen: imported.doorsOpen ?? doorsOpen,
            startsAt: imported.startsAt ?? startsAt,
            endsAt: imported.endsAt ?? endsAt,
            timeZone: imported.timeZone,
            listedAttendees: imported.listedAttendees ?? listedAttendees,
            performers: imported.performers.isEmpty ? performers : imported.performers,
            summary: imported.summary ?? summary,
            relatedLinks: imported.relatedLinks ?? relatedLinks,
            hashtags: imported.hashtags ?? hashtags,
            editedBy: imported.editedBy ?? editedBy,
            editedAt: imported.editedAt ?? editedAt,
            imageURL: imported.imageURL ?? imageURL,
            sourceURL: imported.sourceURL,
            isDetailed: imported.isDetailed || isDetailed,
            detailFormat: imported.detailFormat ?? detailFormat
        )
    }
}
