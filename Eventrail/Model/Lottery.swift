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

    /// Takes one choice out, and the result with it where the lottery was
    /// won with that choice: a win with nothing left to say what was won is
    /// a result nobody gave.
    mutating func removeChoice(_ id: LotteryChoice.ID) {
        choices.removeAll { $0.id == id }
        if result == .won(id) { result = .pending }
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

/// A day on the calendar, with no time and no clock: the day a ticket site
/// says results are out, which is the same day wherever the reader is.
///
/// Kept as `2026-10-12`, so a record reads the same in every zone and in the
/// CloudKit Console.
nonisolated struct CalendarDay: Hashable, Comparable, Sendable {
    var year: Int
    var month: Int
    var day: Int

    /// The day a moment falls on in a calendar — the reader's, by default.
    init(_ date: Date, in calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 1970
        month = parts.month ?? 1
        day = parts.day ?? 1
    }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Midnight starting the day, in a calendar.
    func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    /// Whole days from today to this one: 0 today, negative once it is past.
    func daysAway(from now: Date = .now, in calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: date(in: calendar)).day ?? 0
    }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    var text: String { String(format: "%04d-%02d-%02d", year, month, day) }

    init?(text: String) {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }
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

    /// The rounds that were lotteries (``LotteryEntry/isLottery``), in the
    /// order the sale ran them — rounds the list holds out of order, or two
    /// of one round, keep the order they were written in among themselves.
    /// What the Passport reads how the reader's lotteries went from.
    var lotteryRounds: [LotteryEntry] {
        lotteries.enumerated()
            .filter { $0.element.isLottery }
            .sorted {
                (LotteryRound.order(of: $0.element.round), $0.offset)
                    < (LotteryRound.order(of: $1.element.round), $1.offset)
            }
            .map(\.element)
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

    /// The first entry won, for the event sheet's ticket tile.
    var wonLottery: LotteryEntry? { lotteries.first(where: \.isWon) }

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
        case id, round, applications, day, choices, result, wonChoice
    }

    init(from decoder: any Decoder) throws {
        let record = try decoder.container(keyedBy: CodingKeys.self)
        id = try record.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        round = try record.decodeIfPresent(String.self, forKey: .round) ?? ""
        applications = min(max(try record.decodeIfPresent(Int.self, forKey: .applications) ?? 1, 0),
                           Self.mostApplications)
        day = try record.decodeIfPresent(CalendarDay.self, forKey: .day)
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
    static func entries(inColumn text: String) -> [LotteryEntry]? {
        guard !text.isEmpty else { return nil }
        return try? JSONDecoder().decode([LotteryEntry].self, from: Data(text.utf8))
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
