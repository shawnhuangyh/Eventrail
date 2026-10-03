import SwiftUI

/// Where an event stands, as the activity shows it. Each has its own words and
/// colour, and the fill runs over the times on either side of it.
///
/// Apart from ``EventActivityAttributes`` because the watch app reads an event
/// by the same rules and in the same colours, and watchOS has no ActivityKit:
/// the watch target compiles everything in `Shared` but that file.
nonisolated enum EventActivityStage: String, Codable, Hashable, Sendable {
    /// Before the doors, which the page published.
    case beforeDoors
    /// Before the start, where the page published no doors.
    case beforeShow
    case doorsOpen
    /// The last few minutes before the start — see ``soonBeforeStart``.
    case startingSoon
    case onNow
    /// Over. The app ends the activity as soon as it next runs.
    case wrapped

    /// Two hours before the doors: when the watch app reads an event written
    /// as tomorrow as near, and when the debug bench's scheduled test comes
    /// on. The app's own activities start when the reader turns them on —
    /// see `EventActivities`.
    static let lead: TimeInterval = 2 * 60 * 60

    /// How close to the start "Doors open" turns into "Starting in", as it
    /// does on the event's sheet.
    static let soonBeforeStart: TimeInterval = 5 * 60

    /// Where an event with these times stands at `now`.
    static func at(_ now: Date, doors: Date?, starts: Date, runsTo: Date) -> Self {
        if now >= runsTo { return .wrapped }
        if now >= starts { return .onNow }
        guard let doors, doors < starts else { return .beforeShow }
        if now < doors { return .beforeDoors }
        return starts.timeIntervalSince(now) <= soonBeforeStart ? .startingSoon : .doorsOpen
    }

    /// How far into the event the stage is, so a stage never gives way to
    /// one before it.
    var order: Int {
        switch self {
        case .beforeDoors, .beforeShow: 0
        case .doorsOpen: 1
        case .startingSoon: 2
        case .onNow: 3
        case .wrapped: 4
        }
    }
}

nonisolated extension EventActivityStage {
    /// Amber until the doors, green with them open, orange in the last
    /// minutes, red on stage, grey once it is over — the design's colours,
    /// set for the dark the activity and the watch are always drawn on.
    var tint: Color {
        switch self {
        case .beforeDoors, .beforeShow: Color(red: 1, green: 0xB3 / 255, blue: 0x40 / 255)
        case .doorsOpen: Color(red: 0x4C / 255, green: 0xD9 / 255, blue: 0x64 / 255)
        case .startingSoon: Color(red: 1, green: 0x7A / 255, blue: 0x59 / 255)
        case .onNow: Color(red: 1, green: 0x4F / 255, blue: 0x6A / 255)
        case .wrapped: Color(red: 0xB9 / 255, green: 0xB6 / 255, blue: 0xC4 / 255)
        }
    }
}
