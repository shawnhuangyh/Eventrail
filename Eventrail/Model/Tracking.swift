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
/// These two fields belong to the reader and to this app. A refresh of the
/// public page never touches them.
///
/// There were two more once — how interested the reader was, and whether they
/// turned up. Both asked the library a question it already answers. An event is
/// in the library because the reader means to go, so "interested" was a second
/// word for being there at all; and an event in the library that has already
/// happened is one they went to, so attendance was a second word for the date.
/// What is left is the one thing the library cannot say by itself — whether the
/// ticket is in hand — and whatever the reader wants to write down.
///
/// Dropping them needed no migration: a record written before this still
/// carries `interest` and `attendance`, and a decoder ignores keys it has no
/// property for.
nonisolated struct Tracking: Hashable, Codable {
    var ticket: TicketStatus = .none
    var note: String = ""

    var isEmpty: Bool {
        ticket == .none && note.isEmpty
    }
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
