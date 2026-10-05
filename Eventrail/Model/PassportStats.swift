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

/// How the Events card cuts the reader's events up.
///
/// Three cuts because three are worth reading off a library of a few hundred
/// events: which years they went out in, which months of the year they go out
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
/// **What counts is what the reader's record already says.** An event they
/// went to is one they held a ticket for once its date had gone by
/// (``EventStore/hasAttended(_:)``) — a lottery won or a first-come round got
/// — which is why ``Tracking`` has no attendance field for this to read. So
/// the Passport is a reading of the library's own past and nothing else:
/// nothing here asks Eventernote anything, and nothing here is a second record
/// the reader has to maintain. The lotteries are read over the whole of that
/// past rather than only what was attended, since a round lost is as much a
/// part of how they went as a round won.
///
/// Computed rather than stored, and cheap enough to be: it is a handful of
/// passes over a few hundred events, and storing it would mean keeping it in
/// step with every edit to a note, every import and every merge from another
/// device. A `let` on the screen that shows it cannot go stale.
nonisolated struct PassportStats {
    /// One row of a ranked list: who or where, and how many of the reader's
    /// events it accounts for.
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
    /// axis prints under it, and how many events it holds.
    struct Tally: Identifiable, Hashable {
        /// A year, a month of the year, or a day of the week — the number
        /// the axis is ordered by rather than the name it prints, so a chart
        /// is never sorted alphabetically by "Apr".
        let value: Int
        let label: String
        let count: Int

        var id: Int { value }
    }

    /// One event with both ends published, and how long it ran.
    struct Span: Identifiable, Hashable {
        let event: Event
        let duration: TimeInterval

        var id: Event.ID { event.id }
    }

    /// One event the reader applied for: how many times, and how each round
    /// of its sale went.
    struct Lottery: Identifiable, Hashable {
        let event: Event
        /// The applications over its lottery rounds.
        let entries: Int
        /// How each lottery round went, in the order the sale ran them.
        let outcomes: [LotteryResult]
        /// The same rounds choice by choice, for the dots on the card
        /// (``PassportStats/choiceMarks(of:)``).
        let choices: [[RoundOutcome]]

        var id: Event.ID { event.id }

        /// How many rounds it took to win: every round up to and including
        /// the first one won, nil where none was. A round tried after the win
        /// — a second seat — is not part of getting the first.
        var roundsToWin: Int? {
            outcomes.firstIndex { if case .won = $0 { true } else { false } }.map { $0 + 1 }
        }
    }

    /// How a run of lottery rounds went.
    ///
    /// A round nobody wrote a result on is counted apart rather than as a
    /// loss: every event here is over, so it is not waiting on anything — the
    /// ticket sheet says No Result — but nor did anybody say it was lost.
    struct LotteryTally: Hashable {
        var won = 0
        var lost = 0
        var unknown = 0

        var rounds: Int { won + lost + unknown }
        /// The rounds whose result was written down — what a win rate is out
        /// of.
        var drawn: Int { won + lost }
        /// Nil where nothing was drawn, rather than a 0% nobody earned.
        var winRate: Double? { drawn > 0 ? Double(won) / Double(drawn) : nil }

        mutating func count(_ outcome: LotteryResult) {
            switch outcome {
            case .won: won += 1
            case .lost: lost += 1
            case .pending: unknown += 1
            }
        }
    }

    /// How one lottery round went, as By Round and By Seat count it. Other
    /// seat is By Seat's alone: the round won with a lower class it asked
    /// for (``SeatTally``).
    enum RoundOutcome: Hashable {
        case won, otherSeat, lost, noResult

        init(_ result: LotteryResult) {
            switch result {
            case .won: self = .won
            case .lost: self = .lost
            case .pending: self = .noResult
            }
        }
    }

    /// One event behind a row of By Round or By Seat: the applications over
    /// the rounds of its the row counted, and how each of them went, in the
    /// order the sale ran them.
    struct LotteryEvent: Identifiable, Hashable {
        let event: Event
        let entries: Int
        let outcomes: [RoundOutcome]
        /// The same rounds choice by choice (``PassportStats/choiceMarks(of:)``).
        let choices: [[RoundOutcome]]

        var id: Event.ID { event.id }
    }

    /// One round of a sale, over every event it was tried in.
    struct RoundTally: Identifiable, Hashable {
        /// As written — 最速先行抽選 — and empty for the rounds that name none,
        /// as a lottery count carried over from before entries does.
        let round: String
        let tally: LotteryTally

        var id: String { round }
    }

    /// One class of seat, over every lottery round that asked for it.
    ///
    /// A round won in another class it asked for is no win for this one, and
    /// which way the other class lies decides what it is instead. Won higher
    /// — an S seat on a round that also asked for A and General — it is not
    /// counted here at all: the round was never this class's to win. Won
    /// lower, it is an other seat: this class was not won, but the round was.
    /// So General, the lowest class, is only ever won or lost. The win rate is
    /// the wins *in this class* out of the drawn rounds counted for it.
    struct SeatTally: Identifiable, Hashable {
        /// As written, trimmed — S席 as the chip wrote it, or whatever was
        /// typed.
        let seatClass: String
        var won = 0
        /// Won with a lower class the same round asked for.
        var otherSeat = 0
        var lost = 0
        var unknown = 0

        var id: String { seatClass }

        var rounds: Int { won + otherSeat + lost + unknown }
        var drawn: Int { rounds - unknown }
        var winRate: Double? { drawn > 0 ? Double(won) / Double(drawn) : nil }

        mutating func count(_ outcome: RoundOutcome) {
            switch outcome {
            case .won: won += 1
            case .otherSeat: otherSeat += 1
            case .lost: lost += 1
            case .noResult: unknown += 1
            }
        }
    }

    /// One event the reader wrote a price on, and the class of seat it bought.
    struct Ticket: Identifiable, Hashable {
        let event: Event
        /// What it cost in ``PassportStats/currency`` — exactly what was
        /// paid where it was paid in that, converted where it was not.
        let price: Double
        /// What was paid, as the reader wrote it.
        let paid: Money
        /// ``Tracking/seatClass`` as written, trimmed; empty where it was not.
        let seatClass: String

        var id: Event.ID { event.id }
    }

    /// The tickets of one class of seat, and what they cost.
    struct TicketType: Identifiable, Hashable {
        /// The class as the reader wrote it — S席 as the chip wrote it, or
        /// whatever they typed — and empty for the tickets that name none.
        let seatClass: String
        let count: Int
        /// In ``PassportStats/currency``, like every figure here.
        let spent: Double
        let lowest: Double
        let highest: Double
        /// The cheapest and the dearest of the class as they were paid — the
        /// range the card offers in the currency the tickets were bought in.
        let lowestPaid: Money
        let highestPaid: Money
        /// ``spent`` as it was paid, where the class was all paid in one
        /// currency; nil where it was paid in several.
        let paidSpent: Money?

        var id: String { seatClass }

        var average: Double { spent / Double(count) }

        /// ``average`` as it was paid, where the class was all paid in one
        /// currency.
        var paidAverage: Money? {
            paidSpent.map { Money(amount: $0.amount / Decimal(count), currency: $0.currency) }
        }
    }

    /// The scoped events themselves, most recent first.
    let events: [Event]
    let totalEvents: Int

    /// How long the reader has spent at events, over the events that can say.
    let totalDuration: TimeInterval
    /// How many events that total was measured over.
    ///
    /// Eventernote routinely announces a date months before it publishes a
    /// time, and publishes a finish time for fewer events still. So the total
    /// above is always a total over *part* of the library, and the screen says
    /// which part rather than implying it read every event.
    let timedEvents: Int

    let venues: Int
    let performers: Int
    /// The reader's own number — the one thing on this screen they fill in by
    /// hand — summed over the events they wrote it on.
    let lotteryEntries: Int
    /// How many of the 47 prefectures the reader has been to, counted from the
    /// prefecture at the head of each hall's published address.
    let prefectures: Int

    let topPerformers: [Ranking]
    let topVenues: [Ranking]
    /// Every event with a lottery round on it, most applications first.
    let topLotteries: [Lottery]
    /// How every lottery round on those events went.
    let lotteryTally: LotteryTally
    /// The same rounds by the round of the sale they were, in the order a
    /// sale runs them.
    let lotteryRounds: [RoundTally]
    /// The same rounds by each class of seat they asked for: the three the
    /// chips offer in their order, then any typed, most rounds first. A
    /// round asking for no class is in none of them, and so is one won with
    /// no choice named, which says nothing about any class.
    let lotterySeats: [SeatTally]
    /// The events behind each of ``lotteryRounds`` and of ``lotterySeats``,
    /// newest first, by the round and by the class as written: each with only
    /// the rounds its row counted, so an event whose S seat was won higher
    /// is not among A's.
    let roundEvents: [String: [LotteryEvent]]
    let seatEvents: [String: [LotteryEvent]]
    /// The rounds won with a choice named, and how many of those were won
    /// with the first.
    let namedWins: Int
    let firstChoiceWins: Int
    /// Whether any round asked for more than one choice — without one, every
    /// win is a first choice's and saying so says nothing.
    let hasRankedChoices: Bool
    /// The currency every price below is in: the reader's default, or the one
    /// chosen on the spending card.
    let currency: String
    /// Every event with a price written on it that could be put into
    /// ``currency``, dearest first.
    let tickets: [Ticket]
    /// The one currency every ticket in ``tickets`` was paid in, or nil where
    /// they were paid in several.
    ///
    /// Where it is not ``currency``, the card can print each figure as it was
    /// paid under the one converted — a total of yen and Taiwan dollars has no
    /// such figure, so it prints none.
    let paidCurrency: String?
    /// How many tickets were paid in a currency the rates could not put into
    /// ``currency`` — none held yet on this device, or one the rates do not
    /// carry — and so are in no figure here. The card says so rather than
    /// letting a total read as the whole of it.
    let unconvertedTickets: Int
    /// Those tickets by the class of seat they bought, most tickets first and
    /// the ones that name no class last.
    let ticketTypes: [TicketType]
    /// The briefest events, briefest first, and the longest, longest first.
    let shortest: [Span]
    let longest: [Span]

    /// The first and last event in this slice, for the line under the title.
    let firstEvent: Date?
    let lastEvent: Date?

    // MARK: - Reading the lotteries back

    /// How many events the reader wrote a lottery entry on.
    ///
    /// What every other lottery figure is counted over: ``lotteryEntries`` is
    /// a total over the events they answered for, not over the slice, and the
    /// screen says so rather than letting a part-filled column read as a whole.
    var lotteryEvents: Int { topLotteries.count }

    /// How many rounds a win took on average, over the events one was won
    /// at — see ``Lottery/roundsToWin``. Nil where none was.
    var roundsToWin: Double? {
        let wins = topLotteries.compactMap(\.roundsToWin)
        return wins.isEmpty ? nil : Double(wins.reduce(0, +)) / Double(wins.count)
    }

    // MARK: - Reading the cost back

    /// What the reader paid, over the events they wrote a price on.
    ///
    /// Every figure on the spending card is over ``tickets`` rather than over
    /// the slice, for the reason the lottery figures are: an event with no
    /// price written is not a free event — ``Tracking/cost`` keeps zero for
    /// that — but an event nobody answered for.
    var ticketSpending: Double { tickets.reduce(0) { $0 + $1.price } }

    var averageTicketPrice: Double {
        tickets.isEmpty ? 0 : ticketSpending / Double(tickets.count)
    }

    /// Read off the two ends of ``tickets``, which is already sorted by price.
    var highestTicketPrice: Double? { tickets.first?.price }
    var lowestTicketPrice: Double? { tickets.last?.price }

    /// Whether the figures are in a currency the tickets were not all paid
    /// in, so that each can be read as it was paid as well.
    var showsPaid: Bool { paidCurrency.map { $0 != currency } ?? false }

    /// ``ticketSpending`` as it was paid, exactly, where it was all paid in
    /// one currency.
    var paidSpending: Money? {
        paidCurrency.map { code in Money(amount: tickets.reduce(0) { $0 + $1.paid.amount }, currency: code) }
    }

    /// ``averageTicketPrice`` as it was paid, where it was all paid in one
    /// currency.
    var averagePaid: Double? {
        paidSpending.map { $0.amount.doubleValue / Double(tickets.count) }
    }

    /// Whether any figure here was converted — what the card says the day of
    /// the rates for.
    var isConverted: Bool { tickets.contains { $0.paid.currency != currency } }

    // MARK: - Reading the library

    /// Reads one slice of the reader's past.
    ///
    /// `tracking` is passed in rather than the store itself: everything else
    /// here is a fact about the event, and this keeps the one thing that is
    /// the reader's own at arm's length — which is what lets the whole type
    /// stay `nonisolated` and testable without an `EventStore` behind it.
    ///
    /// The prices are added up in `currency`, through `rates` wherever a
    /// ticket was paid in another; a ticket the rates cannot convert is left
    /// out and counted in ``unconvertedTickets``. With no rates at all, a
    /// library kept in one currency still adds up in that one.
    ///
    /// The lottery figures are counted over `applied` where it is given — the
    /// whole of the slice's past, every event the reader tried for whether or
    /// not they won — and over the attended events otherwise.
    init(events attended: [Event], lotteriesOf applied: [Event]? = nil,
         currency: String = Currencies.yen, rates: CurrencyRates? = nil,
         tracking: (Event) -> Tracking) {
        let events = attended.sorted { $0.sortDate > $1.sortDate }
        self.events = events
        totalEvents = events.count
        firstEvent = events.last?.date
        lastEvent = events.first?.date

        // Sorted once, read from both ends: the briefest events are the front
        // of this and the longest are the back.
        // Equal lengths fall back on the date and then the id, so a redraw
        // never swaps two of them.
        let spans = events.compactMap(Self.span(of:)).sorted {
            if $0.duration != $1.duration { return $0.duration < $1.duration }
            if $0.event.sortDate != $1.event.sortDate { return $0.event.sortDate < $1.event.sortDate }
            return $0.event.id < $1.event.id
        }
        timedEvents = spans.count
        totalDuration = spans.reduce(0) { $0 + $1.duration }
        // Five at most, which is what the sheet behind each See All shows, and
        // half the run at most on top of that, so the two lists cannot name the
        // same event twice when the library is short — an event that is both
        // the briefest and the longest is true and reads as a mistake.
        let half = max(1, min(5, spans.count / 2))
        shortest = Array(spans.prefix(half))
        longest = Array(spans.suffix(half).reversed())

        var performerCounts: [String: Int] = [:]
        var venueCounts: [String: Int] = [:]
        var venuePrefectures: [String: String] = [:]
        for event in events {
            // Counted once per event however the page bills them: a performer
            // named twice on one event is one event they were at.
            for name in Set(event.performers.map(\.name)) {
                performerCounts[name, default: 0] += 1
            }
            // An event still counts when it was a stream or the room was never
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

        var lotteryTally = LotteryTally()
        var rounds: [String: LotteryTally] = [:]
        var seats: [String: SeatTally] = [:]
        var namedWins = 0, firstChoiceWins = 0
        var hasRankedChoices = false
        var roundEvents: [String: [LotteryEvent]] = [:]
        var seatEvents: [String: [LotteryEvent]] = [:]
        let tried = applied.map { $0.sorted { $0.sortDate > $1.sortDate } } ?? events
        let lotteries = tried.compactMap { event -> Lottery? in
            // A lottery round written down at all is an event the reader
            // applied for, as many times as its applications say — see
            // ``Tracking/lotteryApplications``. So these are the events every
            // figure below is counted over; a first-come round alone is not
            // one of them.
            let entries = tracking(event).lotteryRounds
            guard !entries.isEmpty else { return nil }
            // What this event adds to each row's list, by the round and by
            // the class: the applications and each round's outcome.
            var byRound: [String: (entries: Int, outcomes: [RoundOutcome], choices: [[RoundOutcome]])] = [:]
            var bySeat: [String: (entries: Int, outcomes: [RoundOutcome], choices: [[RoundOutcome]])] = [:]
            for entry in entries {
                lotteryTally.count(entry.outcome)
                rounds[entry.round, default: LotteryTally()].count(entry.outcome)
                byRound[entry.round, default: (0, [], [])].entries += entry.applications
                byRound[entry.round, default: (0, [], [])].outcomes.append(RoundOutcome(entry.outcome))
                byRound[entry.round, default: (0, [], [])].choices.append(Self.choiceMarks(of: entry))
                hasRankedChoices = hasRankedChoices || entry.choices.count > 1
                let won = entry.wonChoice
                if let won {
                    namedWins += 1
                    if won.id == entry.choices.first?.id { firstChoiceWins += 1 }
                }
                if entry.isWon && won == nil { continue }
                // Once per class however many choices named it: a round that
                // asked for two S seats and then one is one S-seat round.
                let wonClass = won.map { Self.trimmed($0.seatClass) }
                for seatClass in Set(entry.choices.map { Self.trimmed($0.seatClass) }) where !seatClass.isEmpty {
                    let outcome: RoundOutcome
                    switch entry.outcome {
                    case .won where wonClass == seatClass: outcome = .won
                    case .won:
                        // Leaves the class out of this round altogether,
                        // made or not: a class whose only round was won
                        // higher has nothing to say.
                        if let won, Self.ranks(won, above: seatClass, in: entry.choices) { continue }
                        outcome = .otherSeat
                    case .lost: outcome = .lost
                    case .pending: outcome = .noResult
                    }
                    seats[seatClass, default: SeatTally(seatClass: seatClass)].count(outcome)
                    bySeat[seatClass, default: (0, [], [])].entries += entry.applications
                    bySeat[seatClass, default: (0, [], [])].outcomes.append(outcome)
                    bySeat[seatClass, default: (0, [], [])].choices.append(Self.choiceMarks(of: entry))
                }
            }
            for (round, row) in byRound {
                roundEvents[round, default: []].append(
                    LotteryEvent(event: event, entries: row.entries, outcomes: row.outcomes, choices: row.choices))
            }
            for (seatClass, row) in bySeat {
                seatEvents[seatClass, default: []].append(
                    LotteryEvent(event: event, entries: row.entries, outcomes: row.outcomes, choices: row.choices))
            }
            return Lottery(event: event, entries: entries.reduce(0) { $0 + $1.applications },
                           outcomes: entries.map(\.outcome), choices: entries.map(Self.choiceMarks(of:)))
        }
        topLotteries = lotteries.sorted {
            $0.entries == $1.entries ? $0.event.sortDate > $1.event.sortDate : $0.entries > $1.entries
        }
        lotteryEntries = lotteries.reduce(0) { $0 + $1.entries }
        self.lotteryTally = lotteryTally
        // A sale's rounds in its own order; one a later build names after
        // them, and the rounds that name none last, as the spending card puts
        // the tickets that name no class.
        lotteryRounds = rounds
            .map { RoundTally(round: $0.key, tally: $0.value) }
            .sorted {
                let left = (LotteryRound.order(of: $0.round), $0.round.isEmpty ? 1 : 0, -$0.tally.rounds)
                let right = (LotteryRound.order(of: $1.round), $1.round.isEmpty ? 1 : 0, -$1.tally.rounds)
                return left == right ? $0.round < $1.round : left < right
            }
        // The chips' three in the chips' order, so an S seat is where it was
        // on every slice; a class typed after them, most rounds first.
        lotterySeats = seats.values.sorted {
            let left = (SeatClass.order(of: $0.seatClass), -$0.rounds)
            let right = (SeatClass.order(of: $1.seatClass), -$1.rounds)
            return left == right ? $0.seatClass < $1.seatClass : left < right
        }
        self.roundEvents = roundEvents
        self.seatEvents = seatEvents
        self.namedWins = namedWins
        self.firstChoiceWins = firstChoiceWins
        self.hasRankedChoices = hasRankedChoices

        self.currency = currency
        var unconverted = 0
        let tickets = events.compactMap { event -> Ticket? in
            // Zero is a price — a seat won or given — and is counted; only a
            // price never written leaves the event out.
            let record = tracking(event)
            guard let paid = record.price else { return nil }
            guard let price = paid.converted(to: currency, at: rates) else {
                unconverted += 1
                return nil
            }
            return Ticket(event: event, price: price, paid: paid,
                          seatClass: record.ticketClass.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        unconvertedTickets = unconverted
        let paidCurrencies = Set(tickets.map(\.paid.currency))
        paidCurrency = paidCurrencies.count == 1 ? paidCurrencies.first : nil
        // Equal prices fall back on the date, newest first, and then the id,
        // so the dearest and the cheapest stay put across a redraw.
        self.tickets = tickets.sorted {
            if $0.price != $1.price { return $0.price > $1.price }
            if $0.event.sortDate != $1.event.sortDate { return $0.event.sortDate > $1.event.sortDate }
            return $0.event.id < $1.event.id
        }
        ticketTypes = Self.types(of: tickets)
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// How one lottery round went choice by choice, in the order the reader
    /// ranked them: every choice lost where the round was, each choice before
    /// the one won lost and that one won — nothing after it, so a round won
    /// with its first choice is one mark — and every choice without a result
    /// where none was written. A round naming no choice, or won with none
    /// named, is one mark for the round.
    static func choiceMarks(of entry: LotteryEntry) -> [RoundOutcome] {
        let tried = max(1, entry.choices.count)
        switch entry.outcome {
        case .won(let id):
            guard let id, let index = entry.choices.firstIndex(where: { $0.id == id }) else { return [.won] }
            return Array(repeating: .lost, count: index) + [.won]
        case .lost: return Array(repeating: .lost, count: tried)
        case .pending: return Array(repeating: .noResult, count: tried)
        }
    }

    /// Whether the choice a round was won with stands above `asked`, another
    /// class the round asked for: by the class where both are ones the chips
    /// offer — S above A above General — and otherwise by the order the
    /// round's choices were ranked in, since a class the reader typed has no
    /// place among them.
    private static func ranks(_ won: LotteryChoice, above asked: String, in choices: [LotteryChoice]) -> Bool {
        let wonClass = trimmed(won.seatClass)
        if SeatClass(rawValue: wonClass) != nil, SeatClass(rawValue: asked) != nil {
            return SeatClass.order(of: wonClass) < SeatClass.order(of: asked)
        }
        guard let wonIndex = choices.firstIndex(where: { $0.id == won.id }),
              let askedIndex = choices.firstIndex(where: { trimmed($0.seatClass) == asked })
        else { return false }
        return wonIndex < askedIndex
    }

    /// Tickets gathered by the class they bought.
    ///
    /// Most tickets first, the way every other ranking on the screen runs, and
    /// the dearer class first between two of a size. The tickets that name no
    /// class go last whatever their number: they are the rest of the bar, not
    /// a class of their own.
    private static func types(of tickets: [Ticket]) -> [TicketType] {
        Dictionary(grouping: tickets, by: \.seatClass)
            .map { seatClass, tickets in
                // Already dearest first, so its two ends are the class's.
                let sorted = tickets.sorted { $0.price > $1.price }
                let dearest = sorted[0], cheapest = sorted[sorted.count - 1]
                let currencies = Set(tickets.map(\.paid.currency))
                let paidSpent = currencies.count == 1
                    ? Money(amount: tickets.reduce(0) { $0 + $1.paid.amount }, currency: dearest.paid.currency)
                    : nil
                return TicketType(seatClass: seatClass, count: tickets.count,
                                  spent: tickets.reduce(0) { $0 + $1.price },
                                  lowest: cheapest.price, highest: dearest.price,
                                  lowestPaid: cheapest.paid, highestPaid: dearest.paid,
                                  paidSpent: paidSpent)
            }
            .sorted {
                if $0.seatClass.isEmpty != $1.seatClass.isEmpty { return $1.seatClass.isEmpty }
                if $0.count != $1.count { return $0.count > $1.count }
                if $0.average != $1.average { return $0.average > $1.average }
                return $0.seatClass < $1.seatClass
            }
    }

    /// The scoped events counted by year, by month of the year, or by day of
    /// the week.
    ///
    /// Empty stretches inside the run are counted rather than left out: a year
    /// the reader went to nothing is the most legible thing on the chart, and
    /// a run that stepped from 2019 straight to 2023 would say they were out
    /// in between.
    ///
    /// Months and days are named and ordered by the reader's own calendar —
    /// a week that starts on Monday starts on Monday here — but which month
    /// and which day an event *falls* on is read in the hall's zone, for the
    /// reason ``component(_:of:)`` gives.
    func tally(by cadence: PassportCadence) -> [Tally] {
        let calendar = Calendar.current
        switch cadence {
        case .year:
            var counts: [Int: Int] = [:]
            for event in events { counts[Self.year(of: event), default: 0] += 1 }
            // From the reader's first event to their last, and no further
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

    /// Which month or day of the week an event fell on, read where it was held.
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

    /// How long an event ran, for the events that can say.
    ///
    /// Both ends or nothing: an event with a start and no finish is not a
    /// short event, it is an event nobody has published the end of, and
    /// guessing a length for it would put a made-up number into every total on
    /// the screen.
    ///
    /// Nor anything past ``longestEvent``. The page prints a clock and no
    /// date, so an end earlier than the start is read as the next morning
    /// (``Event/inOrder(_:_:_:)``) — right for 22:00 to 05:00, and a finish
    /// typed as 17:30 under an 18:00 start becomes an event of twenty-three
    /// and a half hours, at the top of Longest and in every total.
    private static func span(of event: Event) -> Span? {
        guard let start = event.startsAt, let end = event.endsAt, end > start else { return nil }
        let duration = end.timeIntervalSince(start)
        guard duration <= longestEvent else { return nil }
        return Span(event: event, duration: duration)
    }

    /// The longest a published start and end are believed to be apart. Past
    /// any all-nighter or day-long festival, well short of the day a mistyped
    /// finish wraps round to.
    static let longestEvent: TimeInterval = 16 * 60 * 60

    /// Counts into rows, most first and then by name, so a screen redrawn
    /// after an edit does not reshuffle everything that happens to be tied.
    private static func ranked(
        _ counts: [String: Int], detail: (String) -> String?
    ) -> [Ranking] {
        counts
            .map { Ranking(name: $0.key, count: $0.value, detail: detail($0.key)) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    // MARK: - Where an event was, and when

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

    /// The year an event falls in, read where it was held.
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
