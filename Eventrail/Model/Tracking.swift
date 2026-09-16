import SwiftUI

/// How interested the reader is. Distinct from anything Eventernote knows.
enum Interest: String, CaseIterable, Identifiable, Hashable {
    case none, interested, planning

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .none: "None"
        case .interested: "Interested"
        case .planning: "Planning to go"
        }
    }
}

enum TicketStatus: String, CaseIterable, Identifiable, Hashable {
    case none, purchased

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .none: "Not purchased"
        case .purchased: "Purchased"
        }
    }
}

enum Attendance: String, CaseIterable, Identifiable, Hashable {
    case unrecorded, attended

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .unrecorded: "Unrecorded"
        case .attended: "Attended"
        }
    }
}

/// The reader's private record for one event.
///
/// These four fields belong to the reader and to this app. A refresh of the
/// public page never touches them.
struct Tracking: Hashable {
    var interest: Interest = .none
    var ticket: TicketStatus = .none
    var attendance: Attendance = .unrecorded
    var note: String = ""

    var isEmpty: Bool {
        interest == .none && ticket == .none && attendance == .unrecorded && note.isEmpty
    }
}

/// The single badge shown on a row, collapsed from the three tracking fields.
enum TrackingStatus: Hashable {
    case untracked, interested, ticketed, attended

    init(_ tracking: Tracking) {
        if tracking.attendance == .attended { self = .attended }
        else if tracking.ticket == .purchased { self = .ticketed }
        else if tracking.interest != .none { self = .interested }
        else { self = .untracked }
    }

    var label: LocalizedStringKey {
        switch self {
        case .untracked: "Untracked"
        case .interested: "Interested"
        case .ticketed: "Ticketed"
        case .attended: "Attended"
        }
    }

    var tint: Color {
        switch self {
        case .untracked: .secondary
        case .interested: .trackInterest
        case .ticketed: .trackTicket
        case .attended: .trackAttended
        }
    }
}
