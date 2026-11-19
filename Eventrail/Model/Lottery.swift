import SwiftUI

/// One round of a ticket sale the reader tried for: which round it was, how
/// many times they applied in it, the day its results come out, what they
/// asked for in order of preference, and how it went.
///
/// Most rounds are lotteries, and in most of those one person can apply more
/// than once — every CD or Blu-ray carrying a 申込券 is another application
/// in the 最速先行抽選 — so an entry carries how many (``applications``). The
/// last rounds of a sale are first come, first served (一般発売, 見切れ席):
/// nothing is applied for and nothing is announced, and the reader writes one
/// down only for a seat they got — so an entry for one keeps the seat alone,
/// and is got by being written (``isFirstCome``, ``outcome``).
///
/// What ``Tracking`` kept as a bare count before. A count said how hard the
/// reader tried and nothing about how it went; an entry says both, and the
/// count is the applications added up (``Tracking/lotteryApplications``).
///
/// Decoded one key at a time, for the reason ``Tracking`` is: a key a later
/// build adds must not make every record before it unreadable.
nonisolated struct LotteryEntry: Hashable, Identifiable, Sendable {
    var id = UUID()
    /// One of ``LotteryRound``'s, written as the site prints it — 最速先行抽選 —
    /// and empty where none was chosen, as on an entry carried over from a
    /// count. Text rather than the case, so a round a later build adds reads
    /// back as itself.
    var round: String = ""
    /// How many times the reader applied in this round — one for every 申込券
    /// or serial code they put in — up to ``mostApplications``. Zero is "not
    /// written down", as an emptied field and a ticket carried over from
    /// before entries say it (``Tracking/foldLegacyTicket()``), and adds
    /// nothing to any count. Meaningless for a round that is first come,
    /// first served, where it stays as it was.
    var applications: Int = 1
    /// The day the results are announced; nil where not written down. A
    /// first-come round asks for none and shows none, but keeps one written
    /// while it was a lottery, so moving it back gives it back.
    var day: CalendarDay?
    /// The time on ``day`` the results come out, in minutes past midnight on
    /// the hall's clock, as a play guide prints it (18:00頃) — nil where only
    /// the day was written, and meaningless without one. Read through
    /// ``resultsDate(in:)``.
    var minute: Int?
    /// When the round stops taking applications — for one more 申込券
    /// before it closes. Nil where none was written. A first-come round
    /// keeps one written while it was a lottery, as it keeps ``day``.
    var deadline: LotteryDeadline?
    /// For a round won, when it has to be paid for (入金締切), and from when
    /// its ticket can be issued (発券開始) — the steps between a win and a
    /// ticket in hand that Ticket To-Dos follows (``TicketTodo``). Asked on
    /// the round's page once it is won; kept, as ``day`` is, should its
    /// result change back.
    var payment: TicketMoment?
    var pickup: TicketMoment?
    /// What was applied for, the most wanted first.
    var choices: [LotteryChoice] = []
    /// How a lottery went, as the reader gave it. Read through ``outcome``,
    /// which a first-come round answers for itself; kept as it was when the
    /// round is changed to one, so changing it back gives it back.
    var result: LotteryResult = .pending

    /// How many choices one application takes: most lotteries stop at a
    /// second or a third.
    static let mostChoices = 3

    /// Four digits: past that the reader is leaning on a key rather than
    /// counting CDs.
    static let mostApplications = 9999

    /// Whether the round sells first come, first served rather than by
    /// lottery — see ``LotteryRound/isFirstCome``.
    var isFirstCome: Bool { LotteryRound(rawValue: round)?.isFirstCome ?? false }

    /// How it went: as the reader gave it for a lottery, and got — with its
    /// seat — for a first-come round, which nobody writes down unless they
    /// got one. Everything that reads how a round went reads this.
    var outcome: LotteryResult {
        isFirstCome ? .won(choices.first?.id) : result
    }

    /// The choice the round was won with, where it was won with one still
    /// listed.
    var wonChoice: LotteryChoice? {
        guard case .won(let id) = outcome, let id else { return nil }
        return choices.first { $0.id == id }
    }

    var isWon: Bool {
        if case .won = outcome { return true }
        return false
    }

    var isPending: Bool { outcome == .pending }

    /// Whether this is a lottery the reader applied in, which every lottery
    /// figure counts: not a first-come round, and not a ticket carried over
    /// from before entries (``Tracking/foldLegacyTicket()``), which names no
    /// round and no applications — a seat held, not a draw anybody wrote
    /// down, and counted as one it would put a win into every win rate.
    var isLottery: Bool { !isFirstCome && !(round.isEmpty && applications == 0) }

    /// The moment the results come out, where a time is written beside the
    /// day: on `zone`'s clock — the hall's.
    func resultsDate(in zone: TimeZone) -> Date? {
        guard let day, let minute else { return nil }
        return day.date(at: minute, in: zone)
    }

    /// The last day its deadline can fall on: the day before the results
    /// come out, since applications close before anything is drawn. Nil
    /// with no results day.
    var lastDeadlineDay: CalendarDay? { day?.adding(days: -1) }

    /// The first day its results can come out on: the day after its
    /// applications close. Nil with no deadline.
    var firstResultsDay: CalendarDay? { deadline?.day.adding(days: 1) }

    /// The payment or the pickup.
    subscript(stage: TicketStage) -> TicketMoment? {
        get {
            switch stage {
            case .payment: payment
            case .pickup: pickup
            }
        }
        set {
            switch stage {
            case .payment: payment = newValue
            case .pickup: pickup = newValue
            }
        }
    }

    /// The moment `stage` falls on, on `zone`'s clock — the hall's.
    func date(of stage: TicketStage, in zone: TimeZone) -> Date? {
        self[stage].map { $0.day.date(at: $0.minute ?? stage.dayAloneMinute, in: zone) }
    }

    /// Takes one choice out, and the result with it where the lottery was
    /// won with that choice: a win with nothing left to say what was won is
    /// a result nobody gave.
    mutating func removeChoice(_ id: LotteryChoice.ID) {
        choices.removeAll { $0.id == id }
        if result == .won(id) { result = .pending }
    }
}

/// The last moment a lottery round takes an application (申込締切), as the
/// play guide's notice prints it: a day, and a time where one is given — a
/// wall clock at the hall, as every time written for an event is
/// (``EventReminder``), asked as the results day and its time are.
///
/// How long before it a notification comes is one answer for every round, in
/// Settings (``LotteryReminders/deadlineLead``), not the round's own
/// (``LotteryDeadlineAlert``).
///
/// The round's own, kept on its entry: it says when more can still be put
/// in. Nothing is marked done on it — the entry being written is the
/// application — so it is in no to-do (``TicketTodo`` follows a win's
/// payment and pickup).
nonisolated struct LotteryDeadline: Hashable, Sendable {
    /// The day on the hall's calendar.
    var day: CalendarDay
    /// Minutes past midnight on the hall's clock; nil where only the day was
    /// written, which closes at ``closingMinute``.
    var minute: Int?

    /// 23:59, where nearly every notice closes: what a day alone is read as,
    /// and what a time added to one opens on.
    static let closingMinute = 23 * 60 + 59

    /// The instant it falls on, on `zone`'s clock — the hall's.
    func date(in zone: TimeZone) -> Date {
        day.date(at: minute ?? Self.closingMinute, in: zone)
    }

    /// When a notification `lead` minutes ahead of it comes.
    func alertDate(in zone: TimeZone, lead: Int) -> Date {
        date(in: zone).addingTimeInterval(-Double(lead) * 60)
    }
}

/// The two steps between a round won and its ticket in hand.
nonisolated enum TicketStage: String, CaseIterable, Hashable, Identifiable, Sendable {
    /// When it has to be paid for by (入金締切).
    case payment
    /// From when the ticket can be issued or picked up (発券開始).
    case pickup

    var id: Self { self }

    /// What a day written alone is read as: a payment closes at 23:59, as a
    /// deadline does; a pickup opens in the morning, when a play guide's
    /// issuing usually does.
    var dayAloneMinute: Int {
        switch self {
        case .payment: LotteryDeadline.closingMinute
        case .pickup: 10 * 60
        }
    }
}

/// When a step of a won round falls, as the play guide prints it — a day,
/// and a time where one is given, a wall clock at the hall — and what the
/// reader has said of it: reached, or given up, and for a payment what is
/// owed, where, and on which page (``TicketTodo``).
///
/// Nothing here is read or worked out: the reader copies it from the notice.
nonisolated struct TicketMoment: Hashable, Sendable {
    /// The day on the hall's calendar.
    var day: CalendarDay
    /// Minutes past midnight on the hall's clock; nil where only the day was
    /// written (``TicketStage/dayAloneMinute``).
    var minute: Int?
    /// When the reader said this step was reached — paid, issued — and nil
    /// while it is still to do. A step reached owes no notification.
    var done: Date?
    /// Whether ``done`` is the reader giving it up rather than doing it: a
    /// payment not made in time. Nil where it is not.
    var missed: Bool?
    /// What is to be paid, as the reader typed it — digits with a point, as
    /// ``LibraryEntry/price`` keeps a cost, since JSON's own numbers are read
    /// back through a `Double` — in ``currency``. Read through ``owed``.
    var amount: String?
    /// ISO 4217, beside ``amount``.
    var currency: String?
    /// Where it is paid, or the ticket issued, as the reader wrote it:
    /// セブン-イレブン, a card.
    var payAt: String?
    /// The page it is done on — a play guide's own page for the order — which
    /// opens in the reader's browser, as every other link does.
    var link: URL?

    init(day: CalendarDay, minute: Int? = nil) {
        self.day = day
        self.minute = minute
    }

    /// What is to be paid and what in, or nil where no amount is written.
    var owed: Money? {
        get {
            amount.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
                .map { Money(amount: $0, currency: currency ?? Currencies.yen) }
        }
        set {
            amount = newValue.map { "\($0.amount)" }
            currency = newValue?.currency
        }
    }

    /// As long as a place to pay is kept: a row has room for a line.
    static let longestPlace = 40

    /// A place to pay as it is kept: the ends trimmed, and nil where nothing
    /// is left.
    static func typedPlace(_ text: String) -> String? {
        let place = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return place.isEmpty ? nil : String(place.prefix(longestPlace))
    }
}

nonisolated extension CalendarDay {
    /// The day `days` on from this one, back for a negative count.
    func adding(days: Int) -> CalendarDay {
        let calendar = Calendar.gregorian(in: .gmt)
        return CalendarDay(calendar.date(byAdding: .day, value: days, to: date(in: calendar)) ?? date(in: calendar),
                           in: calendar)
    }

    /// `minute` past midnight on this day, on `zone`'s clock.
    func date(at minute: Int, in zone: TimeZone) -> Date {
        Calendar.gregorian(in: zone).date(from: DateComponents(year: year, month: month, day: day,
                                                               hour: minute / 60, minute: minute % 60))
            ?? .distantPast
    }
}

/// One line of an application: a class of seat, and how many.
nonisolated struct LotteryChoice: Hashable, Identifiable, Sendable {
    var id = UUID()
    /// As ``Tracking/seatClass`` is kept — S席, A席, 一般席 — and empty where
    /// the lottery sold one kind of seat and there was no class to choose.
    var seatClass: String = ""
    /// How many tickets, from one to ``most``.
    var quantity: Int = 1

    /// Where a lottery's own ceiling nearly always sits; past it the reader
    /// is leaning on the button rather than recording an application.
    static let most = 8
}

/// How a lottery went.
nonisolated enum LotteryResult: Hashable, Sendable {
    case pending
    /// Won with the choice named — nil where the entry lists no choices, as
    /// one carried over from a lottery count does.
    case won(LotteryChoice.ID?)
    case lost
}

/// The rounds a sale runs through, in the order it runs through them, as
/// MyGO!!!!! 9th LIVE's page on bang-dream.com names them: the 最速先行抽選,
/// the ticket agencies' lottery (プレイガイド先行) and its second round
/// (プレイガイド二次先行), then 一般発売 and the 見切れ席, both first come,
/// first served.
///
/// An entry's round is one of these, chosen from a chip — written down as the
/// site prints it and shown in the reader's language, as ``SeatClass`` is, so
/// a round chosen on a phone set to English reads back as 一般発売 on an iPad
/// set to Japanese.
nonisolated enum LotteryRound: String, CaseIterable, Identifiable {
    /// The first lottery, applied for with the 申込券 packed in a single's or
    /// a Blu-ray's first pressing — one application per 申込券.
    case earliest = "最速先行抽選"
    /// The ticket agencies' lottery, e+ or ぴあ, after that.
    case first = "プレイガイド先行"
    /// Its second round, for what the first left.
    case second = "プレイガイド二次先行"
    /// What is left, first come, first served.
    case generalSale = "一般発売"
    /// The seats the stage or the rig hides part of, released last, first
    /// come, first served.
    case restrictedView = "見切れ席"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .earliest: String(localized: "Earliest Presale Lottery",
                               comment: "A ticket sale round: the first lottery, applied for with a code packed in a CD or Blu-ray, 最速先行抽選.")
        case .first: String(localized: "First Lottery",
                            comment: "A ticket sale round: the ticket agencies' lottery after the earliest one, プレイガイド先行.")
        case .second: String(localized: "Second Lottery",
                             comment: "A ticket sale round: the ticket agencies' second lottery, プレイガイド二次先行.")
        case .generalSale: String(localized: "General Sale",
                                  comment: "A ticket sale round: the general sale, first come first served, 一般発売.")
        case .restrictedView: String(localized: "Restricted-View Sale",
                                     comment: "A ticket sale round: seats with part of the stage hidden, sold last, first come first served, 見切れ席.")
        }
    }

    /// Whether this round sells first come, first served.
    var isFirstCome: Bool {
        switch self {
        case .earliest, .first, .second: false
        case .generalSale, .restrictedView: true
        }
    }

    /// A round as the reader reads it: one of these in their language, and
    /// one a later build wrote as it was written.
    static func label(of round: String) -> String {
        LotteryRound(rawValue: round)?.label ?? round
    }

    /// Where a round falls in a sale: its place among these, and after all
    /// of them for one a later build names, or none at all.
    static func order(of round: String) -> Int {
        allCases.firstIndex { $0.rawValue == round } ?? allCases.count
    }
}

nonisolated extension LotteryChoice {
    /// A choice's place in the order as the reader's language counts it —
    /// 1st, 第1.
    static func ordinal(_ index: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: index + 1)) ?? "\(index + 1)"
    }
}

nonisolated extension LotteryEntry {
    /// The entry a count from before entries stands for: one lottery, applied
    /// for that many times, with nothing else known about it — which is what
    /// the count said.
    ///
    /// Its id is fixed, so the same count reads back as the same entry every
    /// time it is read rather than as a new one.
    static func carriedOver(count: Int?) -> [LotteryEntry] {
        guard let count, count > 0 else { return [] }
        return [LotteryEntry(id: carriedOverID, applications: min(count, mostApplications))]
    }

    static let carriedOverID = UUID(uuidString: "00000000-0000-4000-8000-000000000000")!

    /// The id of the entry a ticket held before entries stands for, where no
    /// entry carried over could take it — see ``Tracking/foldLegacyTicket()``.
    static let carriedOverTicketID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    /// A ticket held with nothing else known: no round and no applications,
    /// so it counts in no lottery figure. What a ticket from before entries
    /// is folded into, and what the reader records for an event they went to
    /// without saying how the seat was got (``Tracking/recordTicket()``).
    ///
    /// Its id is fixed, so two devices recording the same event write the
    /// same list rather than two answers to settle between.
    static var ticketHeld: LotteryEntry {
        LotteryEntry(id: carriedOverTicketID, applications: 0, result: .won(nil))
    }
}

nonisolated extension Tracking {
    /// How many times the reader applied for the event across every lottery
    /// round — what the Passport's lottery figures and the watch count. A
    /// first-come round is not applied for, and adds nothing.
    var lotteryApplications: Int {
        lotteries.filter(\.isLottery).reduce(0) { $0 + $1.applications }
    }

    /// Every entry in the order the sale runs its rounds — 最速先行抽選,
    /// プレイガイド先行, プレイガイド二次先行, 一般発売, 見切れ席
    /// (``LotteryRound/order(of:)``) — whatever order they were added in. An
    /// entry with no round, or one a later build names, comes after them, and
    /// two of one round keep the order they were written in. How the ticket
    /// sheet lists them; the list itself is kept as written, so reading it in
    /// order writes nothing.
    var lotteriesInOrder: [LotteryEntry] {
        lotteries.enumerated()
            .sorted {
                (LotteryRound.order(of: $0.element.round), $0.offset)
                    < (LotteryRound.order(of: $1.element.round), $1.offset)
            }
            .map(\.element)
    }

    /// The rounds that were lotteries (``LotteryEntry/isLottery``), in the
    /// order the sale ran them (``lotteriesInOrder``). What the Passport reads
    /// how the reader's lotteries went from.
    var lotteryRounds: [LotteryEntry] {
        lotteriesInOrder.filter(\.isLottery)
    }

    /// Where the reader's lotteries stand taken together: won where any was,
    /// waiting where none was and one is still to be announced, and lost where
    /// every one was. Nil where none is written down.
    var lotteryStanding: LotteryStanding? {
        guard !lotteries.isEmpty else { return nil }
        if lotteries.contains(where: \.isWon) { return .won }
        if lotteries.contains(where: \.isPending) { return .pending }
        return .lost
    }

    /// The first entry won in the order the sale ran, for the event sheet's
    /// ticket tile.
    var wonLottery: LotteryEntry? { lotteriesInOrder.first(where: \.isWon) }

    /// The lottery still to be announced whose results come soonest: the
    /// next day from today on, or, where every day written has gone by, the
    /// latest, which is the one most likely to be in.
    func nextResults(from now: Date = .now) -> LotteryEntry? {
        let dated = lotteries.filter { $0.isPending && $0.day != nil }
        let today = CalendarDay(now)
        return dated.filter { $0.day! >= today }.min { $0.day! < $1.day! }
            ?? dated.max { $0.day! < $1.day! }
    }

    /// Whether the reader holds a ticket: a lottery won, or a first-come
    /// round got — the entries say it, and nothing else is asked. A record
    /// from before them that said so itself reads the same until it is
    /// folded in.
    var hasTicket: Bool {
        ticket == .purchased || lotteries.contains(where: \.isWon)
    }

    /// How many rounds went well: lotteries won and first-come seats got.
    var roundsWon: Int { lotteries.filter(\.isWon).count }

    /// The class the rounds that went well were won or got in — the highest
    /// of them where there are several (``SeatClass/order(of:)``). Nil where
    /// none names a class.
    var classOfWins: String? {
        lotteries
            .compactMap { entry in entry.wonChoice.map(\.seatClass).flatMap { $0.isEmpty ? nil : $0 } }
            .min { SeatClass.order(of: $0) < SeatClass.order(of: $1) }
    }

    /// The class of seat the ticket is: what the rounds that went well say,
    /// and otherwise what was written on the ticket itself — by hand, before
    /// the class was read from the rounds. Everything that shows or counts
    /// the ticket's class reads this.
    var ticketClass: String { classOfWins ?? seatClass }

    /// Keeps the class written on the ticket to what the rounds say, as the
    /// ticket sheet is saved: theirs wherever one names a class, and none
    /// where the last that did has gone since `earlier` and the class was
    /// its. A class no round ever named stays.
    mutating func settleSeatClass(since earlier: Tracking) {
        if let best = classOfWins {
            seatClass = best
        } else if let before = earlier.classOfWins, seatClass == before {
            seatClass = ""
        }
    }

    /// Writes down a ticket held where there is none — the reader saying they
    /// went, with the round left for the ticket sheet (``LotteryEntry/ticketHeld``).
    /// Where that entry is already here and was since marked otherwise, it is
    /// won again rather than added twice.
    mutating func recordTicket() {
        guard !hasTicket else { return }
        if let held = lotteries.firstIndex(where: { $0.id == LotteryEntry.carriedOverTicketID }) {
            lotteries[held].result = .won(nil)
        } else {
            lotteries.append(.ticketHeld)
        }
    }

    /// A ticket an older record says the reader held, said the way the
    /// entries say it now: the entry carried over from a lottery count won,
    /// where it is still waiting — "applied that many times, and got one" —
    /// or else an entry of its own, won with nothing else known and its
    /// applications not written down, so it counts in no lottery figure.
    /// The old answer is none from then on, so the entry is the reader's to
    /// change or take out like any other.
    ///
    /// Run wherever a record is read — the decoder and the store's columns —
    /// so the same record always folds into the same entries, ids and all.
    mutating func foldLegacyTicket() {
        guard ticket == .purchased else { return }
        ticket = .none
        if !lotteries.contains(where: \.isWon) {
            if let carried = lotteries.firstIndex(where: {
                $0.id == LotteryEntry.carriedOverID && $0.result == .pending
            }) {
                lotteries[carried].result = .won(nil)
            } else {
                lotteries.append(.ticketHeld)
            }
        }
        // The list now holds both answers, so it is as old as the newer of
        // them — and as new as the record where either was.
        if let ticketAge = edits[.ticket], let listAge = edits[.lotteries] {
            edits[.lotteries] = max(ticketAge, listAge)
        } else {
            edits[.lotteries] = nil
        }
    }
}

// MARK: - Coding

nonisolated extension LotteryEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, round, applications, day, minute, deadline, payment, pickup, choices, result, wonChoice
    }

    init(from decoder: any Decoder) throws {
        let record = try decoder.container(keyedBy: CodingKeys.self)
        id = try record.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        round = try record.decodeIfPresent(String.self, forKey: .round) ?? ""
        applications = min(max(try record.decodeIfPresent(Int.self, forKey: .applications) ?? 1, 0),
                           Self.mostApplications)
        day = try record.decodeIfPresent(CalendarDay.self, forKey: .day)
        minute = try record.decodeIfPresent(Int.self, forKey: .minute).map { min(max($0, 0), 24 * 60 - 1) }
        // A deadline this build cannot read is dropped rather than the round.
        deadline = (try? record.decodeIfPresent(LotteryDeadline.self, forKey: .deadline)) ?? nil
        payment = (try? record.decodeIfPresent(TicketMoment.self, forKey: .payment)) ?? nil
        pickup = (try? record.decodeIfPresent(TicketMoment.self, forKey: .pickup)) ?? nil
        choices = try record.decodeIfPresent([LotteryChoice].self, forKey: .choices) ?? []
        // A result a later build names is read as still to come rather than
        // as a reason to drop the record.
        switch try record.decodeIfPresent(String.self, forKey: .result) {
        case "won": result = .won(try record.decodeIfPresent(UUID.self, forKey: .wonChoice))
        case "lost": result = .lost
        default: result = .pending
        }
    }

    func encode(to encoder: any Encoder) throws {
        var record = encoder.container(keyedBy: CodingKeys.self)
        try record.encode(id, forKey: .id)
        if !round.isEmpty { try record.encode(round, forKey: .round) }
        try record.encode(applications, forKey: .applications)
        try record.encodeIfPresent(day, forKey: .day)
        // Left out where nothing is written, so a round from before them is
        // the same text and not a change to send.
        try record.encodeIfPresent(minute, forKey: .minute)
        try record.encodeIfPresent(deadline, forKey: .deadline)
        try record.encodeIfPresent(payment, forKey: .payment)
        try record.encodeIfPresent(pickup, forKey: .pickup)
        if !choices.isEmpty { try record.encode(choices, forKey: .choices) }
        switch result {
        case .pending: try record.encode("pending", forKey: .result)
        case .won(let choice):
            try record.encode("won", forKey: .result)
            try record.encodeIfPresent(choice, forKey: .wonChoice)
        case .lost: try record.encode("lost", forKey: .result)
        }
    }
}

nonisolated extension LotteryDeadline: Codable {
    private enum CodingKeys: String, CodingKey {
        case day, minute
    }

    init(from decoder: any Decoder) throws {
        let record = try decoder.container(keyedBy: CodingKeys.self)
        day = try record.decode(CalendarDay.self, forKey: .day)
        minute = try record.decodeIfPresent(Int.self, forKey: .minute).map { min(max($0, 0), 24 * 60 - 1) }
    }

    func encode(to encoder: any Encoder) throws {
        var record = encoder.container(keyedBy: CodingKeys.self)
        try record.encode(day, forKey: .day)
        try record.encodeIfPresent(minute, forKey: .minute)
    }
}

nonisolated extension TicketMoment: Codable {
    private enum CodingKeys: String, CodingKey {
        case day, minute, done, missed, amount, currency, payAt, link
    }

    init(from decoder: any Decoder) throws {
        let record = try decoder.container(keyedBy: CodingKeys.self)
        day = try record.decode(CalendarDay.self, forKey: .day)
        minute = try record.decodeIfPresent(Int.self, forKey: .minute).map { min(max($0, 0), 24 * 60 - 1) }
        done = try? record.decodeIfPresent(Date.self, forKey: .done)
        missed = try? record.decodeIfPresent(Bool.self, forKey: .missed)
        amount = try? record.decodeIfPresent(String.self, forKey: .amount)
        currency = try? record.decodeIfPresent(String.self, forKey: .currency)
        payAt = try? record.decodeIfPresent(String.self, forKey: .payAt)
        link = try? record.decodeIfPresent(URL.self, forKey: .link)
    }

    func encode(to encoder: any Encoder) throws {
        var record = encoder.container(keyedBy: CodingKeys.self)
        try record.encode(day, forKey: .day)
        try record.encodeIfPresent(minute, forKey: .minute)
        try record.encodeIfPresent(done, forKey: .done)
        try record.encodeIfPresent(missed, forKey: .missed)
        try record.encodeIfPresent(amount, forKey: .amount)
        try record.encodeIfPresent(currency, forKey: .currency)
        try record.encodeIfPresent(payAt, forKey: .payAt)
        try record.encodeIfPresent(link, forKey: .link)
    }
}

nonisolated extension LotteryChoice: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, seatClass, quantity
    }

    init(from decoder: any Decoder) throws {
        let record = try decoder.container(keyedBy: CodingKeys.self)
        id = try record.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        seatClass = try record.decodeIfPresent(String.self, forKey: .seatClass) ?? ""
        quantity = min(max(try record.decodeIfPresent(Int.self, forKey: .quantity) ?? 1, 1), Self.most)
    }

    func encode(to encoder: any Encoder) throws {
        var record = encoder.container(keyedBy: CodingKeys.self)
        try record.encode(id, forKey: .id)
        if !seatClass.isEmpty { try record.encode(seatClass, forKey: .seatClass) }
        try record.encode(quantity, forKey: .quantity)
    }
}

nonisolated extension LotteryEntry {
    /// A list of entries as one column holds it: JSON, its keys sorted so the
    /// same list is always the same text and an unchanged list is not a
    /// change to send. Empty for none.
    static func columnText(of entries: [LotteryEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(entries)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// The list a column holds, or nil where it holds none — or none this
    /// build can read.
    ///
    /// Read once per text and kept (``reads``): every screen that badges a
    /// row or adds up the Passport reads the record of each event it shows,
    /// several times a redraw, and decoding the same JSON each time cost the
    /// Passport some 17 ms a redraw on a library of nine hundred ticketed
    /// events. Keyed by the text itself, so an edited list is a new key and
    /// nothing has to be told it changed.
    static func entries(inColumn text: String) -> [LotteryEntry]? {
        guard !text.isEmpty else { return nil }
        let key = text as NSString
        if let read = reads.object(forKey: key) { return read.entries }
        let entries = try? JSONDecoder().decode([LotteryEntry].self, from: Data(text.utf8))
        reads.setObject(ColumnRead(entries: entries), forKey: key)
        return entries
    }

    /// One entry as its own row holds it (``LibraryLottery``): JSON, its keys
    /// sorted, so an unchanged entry is the same text and not a change to send.
    static func rowText(of entry: LotteryEntry) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(entry)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// The entry a row holds, or nil where it holds none this build can read.
    /// Read once per text and kept, for the reason a column is
    /// (``entries(inColumn:)``).
    static func entry(inRow text: String) -> LotteryEntry? {
        guard !text.isEmpty else { return nil }
        let key = "row:\(text)" as NSString
        if let read = reads.object(forKey: key) { return read.entries?.first }
        let entry = try? JSONDecoder().decode(LotteryEntry.self, from: Data(text.utf8))
        reads.setObject(ColumnRead(entries: entry.map { [$0] }), forKey: key)
        return entry
    }

    /// `NSCache` is safe to use from any thread, and lets go of what it holds
    /// when memory runs short.
    nonisolated(unsafe) private static let reads: NSCache<NSString, ColumnRead> = {
        let cache = NSCache<NSString, ColumnRead>()
        cache.countLimit = 4000
        return cache
    }()

    /// One column's text read, readable or not.
    private final class ColumnRead: Sendable {
        let entries: [LotteryEntry]?
        init(entries: [LotteryEntry]?) { self.entries = entries }
    }
}

/// Writes a count into a text field, and reads one back out — how many times
/// a lottery round was applied for.
///
/// The same shape as ``MoneyAmount`` and for one of the same two reasons: no
/// built-in style takes an optional, and the field has to be able to hold
/// nothing while it is being typed into. It reads the digits out of whatever
/// was typed, so the separator it wrote survives an edit and a full-width ３
/// from a Japanese keyboard is the same as 3. Zero and nothing both read as
/// nil, which the field writes as zero — "not written down", as
/// ``LotteryEntry/applications`` has it.
nonisolated struct EntryCount: ParseableFormatStyle {
    var parseStrategy: Strategy { Strategy() }

    func format(_ value: Int?) -> String {
        value.map { $0.formatted(.number) } ?? ""
    }

    nonisolated struct Strategy: ParseStrategy {
        func parse(_ value: String) -> Int? {
            let digits = value.compactMap(\.wholeNumberValue).prefix(4)
            guard !digits.isEmpty else { return nil }
            let count = digits.reduce(0) { $0 * 10 + $1 }
            return count == 0 ? nil : count
        }
    }
}

nonisolated extension FormatStyle where Self == EntryCount {
    static var entries: EntryCount { EntryCount() }
}
