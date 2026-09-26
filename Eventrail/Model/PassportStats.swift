import SwiftUI

/// Which slice of their own past the reader is reading the Passport over.
///
/// Only two kinds, because only two are answerable from the library: the whole
/// of it, and one year of it. A year the reader has nothing in is never
/// offered — ``PassportStats/years(of:)`` reads the list off the library rather
/// than counting up from whenever the app was installed.
///
/// Deliberately not remembered between visits. The Passport opens on
/// ``allTime`` every time, because that is what the screen is *for*; a filter
/// left on from a fortnight ago would have the reader reading one year and
/// believing it was all of them.
nonisolated enum PassportScope: Hashable, Identifiable {
    case allTime
    case year(Int)

    var id: Self { self }

    /// What the chip says. A year is written verbatim: it is a name here
    /// rather than a quantity, and `2026` formatted as a number is "2,026".
    var chipLabel: Text {
        switch self {
        case .allTime: Text("All Time")
        case .year(let year): Text(verbatim: String(year))
        }
    }

    func contains(_ event: Event) -> Bool {
        switch self {
        case .allTime: true
        case .year(let year): PassportStats.year(of: event) == year
        }
    }
}

/// How the Events card cuts the reader's nights up.
///
/// Three cuts because three are worth reading off a library of a few hundred
/// nights: which years they went out in, which months of the year they go out
/// in, and which days of the week. Anything finer — a week, a day — is a
/// calendar, and the app already has one.
nonisolated enum PassportCadence: CaseIterable, Identifiable, Hashable {
    case year
    case month
    case weekday

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .year: "Year"
        case .month: "Month"
        case .weekday: "Weekday"
        }
    }
}

/// Everything the Passport says about one slice of the reader's past, worked
/// out in one pass over it.
///
/// **What counts is what the library already says.** An event the reader keeps
/// once its date has gone by is one they went to — that is what keeping it
/// means, and it is why ``Tracking`` has no attendance field for this to read.
/// So the Passport is a reading of the library's own past and nothing else:
/// nothing here asks Eventernote anything, and nothing here is a second record
/// the reader has to maintain. An event they did not go to is one they take
/// out of My Events, which is the same gesture that has always meant that.
///
/// Computed rather than stored, and cheap enough to be: it is a handful of
/// passes over a few hundred events, and storing it would mean keeping it in
/// step with every edit to a note, every import and every merge from another
/// device. A `let` on the screen that shows it cannot go stale.
nonisolated struct PassportStats {
    /// One row of a ranked list: who or where, and how many of the reader's
    /// nights it accounts for.
    struct Ranking: Identifiable, Hashable {
        /// A performer as Eventernote bills them, or a hall as it names it —
        /// verbatim either way, never translated.
        let name: String
        let count: Int
        /// The prefecture the hall stands in, where an address has said so.
        /// Nil for a performer, and for a hall whose page nothing has read.
        let detail: String?

        var id: String { name }
    }

    /// One column of the Events chart: where it sits on the axis, what the
    /// axis prints under it, and how many nights it holds.
    struct Tally: Identifiable, Hashable {
        /// A year, a month of the year, or a day of the week — the number
        /// the axis is ordered by rather than the name it prints, so a chart
        /// is never sorted alphabetically by "Apr".
        let value: Int
        let label: String
        let count: Int

        var id: Int { value }
    }

    /// One night with both ends published, and how long it ran.
    struct Span: Identifiable, Hashable {
        let event: Event
        let duration: TimeInterval

        var id: Event.ID { event.id }
    }

    /// One night the reader applied for, and how many times they did.
    struct Lottery: Identifiable, Hashable {
        let event: Event
        let entries: Int

        var id: Event.ID { event.id }
    }

    /// The scoped nights themselves, most recent first.
    let events: [Event]
    let totalEvents: Int

    /// How long the reader has spent at events, over the nights that can say.
    let totalDuration: TimeInterval
    /// How many nights that total was measured over.
    ///
    /// Eventernote routinely announces a date months before it publishes a
    /// time, and publishes a finish time for fewer nights still. So the total
    /// above is always a total over *part* of the library, and the screen says
    /// which part rather than implying it read every night.
    let timedEvents: Int

    let venues: Int
    let performers: Int
    /// The reader's own number — the one thing on this screen they fill in by
    /// hand — summed over the nights they wrote it on.
    let lotteryEntries: Int
    /// How many of the 47 prefectures the reader has been to, counted from the
    /// prefecture at the head of each hall's published address.
    let prefectures: Int

    let topPerformers: [Ranking]
    let topVenues: [Ranking]
    let topLotteries: [Lottery]
    /// The briefest nights, briefest first, and the longest, longest first.
    let shortest: [Span]
    let longest: [Span]

    /// The first and last night in this slice, for the line under the title.
    let firstEvent: Date?
    let lastEvent: Date?

    // MARK: - Reading the lottery count back

    /// How many nights the reader wrote a lottery count on.
    ///
    /// What every other lottery figure is counted over: ``lotteryEntries`` is
    /// a total over the nights they answered for, not over the slice, and the
    /// screen says so rather than letting a part-filled column read as a whole.
    var lotteryEvents: Int { topLotteries.count }

    /// The most entries the reader put into any one night.
    ///
    /// Read off the front of ``topLotteries``, which is already sorted by
    /// entries: the hardest they ever tried for a seat is the first row of the
    /// list, and counting it a second way is how the two drift apart.
    var mostLotteryEntries: Int { topLotteries.first?.entries ?? 0 }

    /// How many entries an average recorded night took.
    ///
    /// Over ``lotteryEvents`` rather than over the slice, for the reason
    /// `Avg. Time` is over the timed nights: a night they never wrote a count
    /// on is not a night they entered nothing for.
    var averageLotteryEntries: Double {
        lotteryEvents > 0 ? Double(lotteryEntries) / Double(lotteryEvents) : 0
    }

    // MARK: - Reading the library

    /// Reads one slice of the reader's past.
    ///
    /// `tracking` is passed in rather than the store itself: everything else
    /// here is a fact about the event, and this keeps the one thing that is
    /// the reader's own at arm's length — which is what lets the whole type
    /// stay `nonisolated` and testable without an `EventStore` behind it.
    init(events attended: [Event], tracking: (Event) -> Tracking) {
        let events = attended.sorted { $0.sortDate > $1.sortDate }
        self.events = events
        totalEvents = events.count
        firstEvent = events.last?.date
        lastEvent = events.first?.date

        // Sorted once, read from both ends: the briefest nights are the front
        // of this and the longest are the back.
        let spans = events.compactMap(Self.span(of:)).sorted { $0.duration < $1.duration }
        timedEvents = spans.count
        totalDuration = spans.reduce(0) { $0 + $1.duration }
        // Five at most, which is what the sheet behind each See All shows, and
        // half the run at most on top of that, so the two lists cannot name the
        // same night twice when the library is short — an event that is both
        // the briefest and the longest is true and reads as a mistake.
        let half = max(1, min(5, spans.count / 2))
        shortest = Array(spans.prefix(half))
        longest = Array(spans.suffix(half).reversed())

        var performerCounts: [String: Int] = [:]
        var venueCounts: [String: Int] = [:]
        var venuePrefectures: [String: String] = [:]
        for event in events {
            // Counted once per night however the page bills them: a performer
            // named twice on one event is one event they were at.
            for name in Set(event.performers.map(\.name)) {
                performerCounts[name, default: 0] += 1
            }
            // A night still counts when it was a stream or the room was never
            // disclosed; it just adds no hall — see ``Event/isAtHall``.
            guard event.isAtHall else { continue }
            venueCounts[event.venue, default: 0] += 1
            if venuePrefectures[event.venue] == nil, let prefecture = Self.prefecture(of: event) {
                venuePrefectures[event.venue] = prefecture
            }
        }

        performers = performerCounts.count
        venues = venueCounts.count
        prefectures = Set(venuePrefectures.values).count
        topPerformers = Self.ranked(performerCounts) { _ in nil }
        topVenues = Self.ranked(venueCounts) { venuePrefectures[$0] }

        let lotteries = events.compactMap { event -> Lottery? in
            // A count written down at all is a night the reader applied for:
            // zero is "not written down" too, and never reaches this — see
            // ``Tracking/lotteryEntries``. So these are the nights every
            // figure below is counted over.
            guard let entries = tracking(event).lotteryEntries else { return nil }
            return Lottery(event: event, entries: entries)
        }
        topLotteries = lotteries.sorted {
            $0.entries == $1.entries ? $0.event.sortDate > $1.event.sortDate : $0.entries > $1.entries
        }
        lotteryEntries = lotteries.reduce(0) { $0 + $1.entries }
    }

    /// The scoped nights counted by year, by month of the year, or by day of
    /// the week.
    ///
    /// Empty stretches inside the run are counted rather than left out: a year
    /// the reader went to nothing is the most legible thing on the chart, and
    /// a run that stepped from 2019 straight to 2023 would say they were out
    /// in between.
    ///
    /// Months and days are named and ordered by the reader's own calendar —
    /// a week that starts on Monday starts on Monday here — but which month
    /// and which day a night *falls* on is read in the hall's zone, for the
    /// reason ``component(_:of:)`` gives.
    func tally(by cadence: PassportCadence) -> [Tally] {
        let calendar = Calendar.current
        switch cadence {
        case .year:
            var counts: [Int: Int] = [:]
            for event in events { counts[Self.year(of: event), default: 0] += 1 }
            // From the reader's first night to their last, and no further
            // back: a column standing in a year before the library begins is
            // a year they are being told they went to nothing in, when the
            // truth is the record does not reach it.
            guard let first = counts.keys.min(), let last = counts.keys.max() else { return [] }
            return (first ... last).map {
                Tally(value: $0, label: String($0), count: counts[$0] ?? 0)
            }
        case .month:
            var counts = Array(repeating: 0, count: 12)
            for event in events {
                counts[Self.component(.month, of: event) - 1] += 1
            }
            return (0 ..< 12).map {
                Tally(value: $0 + 1, label: calendar.shortMonthSymbols[$0], count: counts[$0])
            }
        case .weekday:
            var counts = Array(repeating: 0, count: 7)
            for event in events {
                counts[Self.component(.weekday, of: event) - 1] += 1
            }
            return (0 ..< 7).map { offset in
                let day = (offset + calendar.firstWeekday - 1) % 7
                return Tally(value: offset,
                             label: calendar.shortWeekdaySymbols[day],
                             count: counts[day])
            }
        }
    }

    /// Which month or day of the week a night fell on, read where it was held.
    ///
    /// ``Event/date`` is midnight in the *venue's* zone, and every line in the
    /// app that prints a day prints it in that zone. Read in the reader's zone
    /// instead, a Tokyo Sunday becomes Saturday for anybody west of Japan —
    /// the chart would then say nobody goes out on Sundays while every row
    /// under it says "Sun". The year is read the same way, in ``year(of:)``.
    private static func component(_ component: Calendar.Component, of event: Event) -> Int {
        var calendar = Calendar.current
        calendar.timeZone = event.timeZone
        return calendar.component(component, from: event.date)
    }

    /// How long a night ran, for the nights that can say.
    ///
    /// Both ends or nothing: an event with a start and no finish is not a
    /// short event, it is an event nobody has published the end of, and
    /// guessing a length for it would put a made-up number into every total on
    /// the screen.
    private static func span(of event: Event) -> Span? {
        guard let start = event.startsAt, let end = event.endsAt, end > start else { return nil }
        return Span(event: event, duration: end.timeIntervalSince(start))
    }

    /// Counts into rows, most first and then by name, so a screen redrawn
    /// after an edit does not reshuffle everything that happens to be tied.
    private static func ranked(
        _ counts: [String: Int], detail: (String) -> String?
    ) -> [Ranking] {
        counts
            .map { Ranking(name: $0.key, count: $0.value, detail: detail($0.key)) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    // MARK: - Where a night was, and when

    /// Every prefecture the site spells, which is also how each one is spelled
    /// at the head of the addresses it publishes. ``Region`` already writes the
    /// whole list out so nobody has to fetch the page to check it; this is the
    /// same 47 read flat.
    private static let allPrefectures = Region.allCases.flatMap(\.prefectures)

    /// The prefecture a hall stands in, read off the address Eventernote
    /// published for it.
    ///
    /// A Japanese address opens with its prefecture, so the name at the front
    /// settles it. An address naming none — a hall abroad, or a line that
    /// turned out not to be an address — places the hall nowhere rather than
    /// somewhere guessed, for the reason ``Region/containing(address:)`` gives.
    static func prefecture(of event: Event) -> String? {
        guard let address = (event.venueAddress ?? event.venueDetail)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty
        else { return nil }
        return allPrefectures.first { address.hasPrefix($0) }
    }

    /// The year a night falls in, read where it was held.
    ///
    /// The venue's calendar rather than the reader's, for the reason
    /// ``component(_:of:)`` gives: a New Year's Day show in Tokyo is still
    /// the 31st of December for a reader in Shanghai, and would otherwise be
    /// filed under the year before the one its row prints.
    static func year(of event: Event) -> Int {
        component(.year, of: event)
    }

    /// Which years the reader actually has something in, most recent first.
    ///
    /// Read off the library rather than counted between two dates, so a year
    /// they went to nothing is never offered as an empty screen.
    static func years(of events: [Event]) -> [Int] {
        Set(events.map(year(of:))).sorted(by: >)
    }

    static func events(_ events: [Event], in scope: PassportScope) -> [Event] {
        events.filter(scope.contains)
    }
}
