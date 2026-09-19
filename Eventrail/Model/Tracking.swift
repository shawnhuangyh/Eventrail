import SwiftUI

nonisolated enum TicketStatus: String, CaseIterable, Identifiable, Hashable, Codable {
    case none, purchased

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .none: "Not purchased"
        case .purchased: "Purchased"
        }
    }
}

/// The reader's private record for one event.
///
/// Every field here belongs to the reader and to this app. A refresh of the
/// public page never touches them.
///
/// There were two more once — how interested the reader was, and whether they
/// turned up. Both asked the library a question it already answers. An event is
/// in the library because the reader means to go, so "interested" was a second
/// word for being there at all; and an event in the library that has already
/// happened is one they went to, so attendance was a second word for the date.
/// What is left is the ticket: whether it is in hand, which the library cannot
/// say by itself, and once it is, the two things about it worth keeping after
/// the night is over — and whatever the reader wants to write down.
///
/// Dropping the two needed no migration: a record written before this still
/// carries `interest` and `attendance`, and a decoder ignores keys it has no
/// property for. Adding one needs none either, but only because the decoder
/// below reads every key as optional — a synthesized one treats a key an older
/// record does not carry as a corrupt file, and takes the whole library with
/// it. So an older record simply has no seat, no cost, no lottery count and no
/// ticket tier: nothing written down.
nonisolated struct Tracking: Hashable, Codable {
    var ticket: TicketStatus = .none
    /// Where the reader sat, as the ticket prints it.
    ///
    /// One free line rather than a row and a number in fields of their own: a
    /// hall prints 1階 L列 23番, an arena prints A5ブロック 12番, and a live
    /// house prints an entry number and no seat at all. Anything that insisted
    /// on a shape would be wrong for two of the three.
    var seat: String = ""
    /// What the ticket cost, in whole yen.
    ///
    /// Nil is "not written down", which is not the same as free — a lottery
    /// seat or an invite really does cost nothing, and it is worth being able
    /// to record that.
    var cost: Int?
    /// How many entries the reader put into the lottery for this night.
    ///
    /// Nil is "not written down". Zero is an answer somebody gave — a seat
    /// bought the moment it went on sale, or an invite — so clearing the field
    /// goes back to nil rather than settling on 0, and a night nobody filled in
    /// is never counted as a night with no applications.
    var lotteryEntries: Int?
    /// Which ticket this turned out to be, as whoever sold it named it: S席,
    /// 一般, 通し券.
    ///
    /// One free line with a menu of the usual answers in front of it rather
    /// than a list to pick from: every promoter names its own tiers, and
    /// anything closed would be wrong for the next event announced. Kept as the
    /// reader typed it — the statistics match spellings on their own, in
    /// ``TicketCategory/key(for:)``, rather than correcting what is shown here.
    ///
    /// Empty is "not written down", which is never 一般: that is a tier
    /// somebody chose.
    var ticketCategory: String = ""
    var note: String = ""

    var isEmpty: Bool {
        ticket == .none && seat.isEmpty && cost == nil
            && lotteryEntries == nil && ticketCategory.isEmpty && note.isEmpty
    }
}

nonisolated extension Tracking {
    /// Read one key at a time, so a record written before a field existed
    /// arrives with that field's default instead of failing.
    ///
    /// The synthesized decoder does not fall back to a property's default: a
    /// key it cannot find is an error, and an error thrown here is not one
    /// record lost but the whole archive — ``LibraryFile`` has nothing left to
    /// read and the library comes up empty. Every field added to this struct
    /// since the first release would have taken the reader's library with it,
    /// which is what the lottery count and the ticket tier did until this was
    /// written. The archive says the same thing about its own new keys, and
    /// answers it the same way: nothing here may insist on being present.
    ///
    /// Encoding stays synthesized — a record is always written whole — and so
    /// do `CodingKeys`, which is why this is an extension rather than a second
    /// init in the body: declared there it would take the memberwise init with
    /// it.
    init(from decoder: any Decoder) throws {
        let record = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            ticket: try record.decodeIfPresent(TicketStatus.self, forKey: .ticket) ?? .none,
            seat: try record.decodeIfPresent(String.self, forKey: .seat) ?? "",
            cost: try record.decodeIfPresent(Int.self, forKey: .cost),
            lotteryEntries: try record.decodeIfPresent(Int.self, forKey: .lotteryEntries),
            ticketCategory: try record.decodeIfPresent(String.self, forKey: .ticketCategory) ?? "",
            note: try record.decodeIfPresent(String.self, forKey: .note) ?? "")
    }
}

/// The ticket tiers common enough to be worth a tap.
///
/// A menu rather than the whole of the answer: ``Tracking/ticketCategory`` takes
/// anything, and these are only what saves typing the same eight words for the
/// eighth time. They are names printed on tickets, not app wording, so they are
/// shown verbatim in every language.
nonisolated enum TicketCategory: String, CaseIterable, Identifiable {
    case sSeat = "S席"
    case aSeat = "A席"
    case bSeat = "B席"
    case general = "一般"
    case reserved = "指定席"
    case unreserved = "自由席"
    case vip = "VIP"
    case pass = "通し券"
    case invited = "招待"

    var id: String { rawValue }
}

nonisolated extension TicketCategory {
    /// The key two spellings of one tier are counted under.
    ///
    /// Ｓ席 typed on a Japanese keyboard and S席 typed on an English one are the
    /// same seat, and so are "vip" and "VIP" — so the ends are trimmed, the
    /// runs of spaces inside collapsed, full width folded to half, and letters
    /// raised. Nothing beyond that: S席 and A席 are different seats, and a
    /// promoter's own 先行SS席 is its own tier rather than something to be
    /// guessed into one of these by the letters it happens to contain.
    static func key(for name: String) -> String {
        let folded = name.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? name
        return folded.uppercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

/// Writes an amount of yen into a text field, and reads one back out.
///
/// Yen because Eventernote lists Japanese events at Japanese halls and prices
/// every one of them in yen; a currency of its own per ticket would be a second
/// field to fill in for the sake of the evening somebody spends abroad.
///
/// `TextField(value:format:)` insists the value and the style agree on a type,
/// and no built-in style takes an optional — hence this one. Parsing reads the
/// digits out of whatever is in the field and ignores the rest, so the ¥ and
/// the separators the style itself wrote survive an edit, and a full-width
/// １２３４ from a Japanese keyboard is the same number as 1234.
nonisolated struct YenAmount: ParseableFormatStyle {
    var parseStrategy: Strategy { Strategy() }

    func format(_ value: Int?) -> String {
        value.map { $0.formatted(.currency(code: "JPY")) } ?? ""
    }

    nonisolated struct Strategy: ParseStrategy {
        /// Nine digits is ¥999,999,999. Past that the reader is leaning on a
        /// key rather than recording a ticket, and the arithmetic would
        /// eventually overflow.
        func parse(_ value: String) -> Int? {
            let digits = value.compactMap(\.wholeNumberValue).prefix(9)
            guard !digits.isEmpty else { return nil }
            return digits.reduce(0) { $0 * 10 + $1 }
        }
    }
}

nonisolated extension FormatStyle where Self == YenAmount {
    static var yen: YenAmount { YenAmount() }
}

/// Writes a count of lottery entries into a text field, and reads one back out.
///
/// The same shape as ``YenAmount`` and for the same two reasons: no built-in
/// style takes an optional, and an empty field has to read back as nil rather
/// than as zero, which here is the difference between a night nobody filled in
/// and a night the reader went to without applying for anything.
nonisolated struct EntryCount: ParseableFormatStyle {
    var parseStrategy: Strategy { Strategy() }

    func format(_ value: Int?) -> String {
        value.map { $0.formatted(.number) } ?? ""
    }

    nonisolated struct Strategy: ParseStrategy {
        /// Four digits is 9,999 applications for one night. Past that the
        /// reader is leaning on a key rather than recording a lottery.
        func parse(_ value: String) -> Int? {
            let digits = value.compactMap(\.wholeNumberValue).prefix(4)
            guard !digits.isEmpty else { return nil }
            return digits.reduce(0) { $0 * 10 + $1 }
        }
    }
}

nonisolated extension FormatStyle where Self == EntryCount {
    static var entries: EntryCount { EntryCount() }
}

/// The single badge shown on a row.
///
/// Read from where the event stands rather than from anything the reader filled
/// in: in the library or not, past or still to come, ticket in hand or not.
/// ``EventStore/status(for:)`` is the one place it is worked out, because it is
/// the only place that knows whether the event is in the library.
enum TrackingStatus: Hashable {
    case untracked, planned, ticketed, attended

    var label: LocalizedStringKey {
        switch self {
        case .untracked: "Untracked"
        case .planned: "Planning"
        case .ticketed: "Ticketed"
        case .attended: "Attended"
        }
    }

    var tint: Color {
        switch self {
        case .untracked: .secondary
        case .planned: .trackInterest
        case .ticketed: .trackTicket
        case .attended: .trackAttended
        }
    }
}
