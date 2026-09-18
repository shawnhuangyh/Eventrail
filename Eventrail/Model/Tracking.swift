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
/// property for. Adding these two needs none either, for the mirror image of
/// the reason — an older record simply has no seat and no cost.
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
    var note: String = ""

    var isEmpty: Bool {
        ticket == .none && seat.isEmpty && cost == nil && note.isEmpty
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
