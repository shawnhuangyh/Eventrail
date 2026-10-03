import SwiftUI

/// When a screen showing events is drawn again: every `step` while the watch
/// is being looked at, once a minute with the wrist down, and in either case
/// at the very moment a stage gives way.
///
/// The countdowns are the system's own timers and count by themselves; what
/// this redraws is the rest — the stage, its colour, the gauge's fill. Left
/// to a minute's tick in Always On, a countdown that has run out would sit at
/// 0:00 for up to a minute before the next stage took over.
nonisolated struct StageSchedule: TimelineSchedule {
    /// The moments a stage gives way — ``EventMoment/changes``.
    let changes: [Date]
    let step: TimeInterval

    func entries(from start: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(tick: start, step: mode == .lowFrequency ? 60 : step,
                changes: changes.filter { $0 > start }.sorted()[...])
    }

    struct Entries: Sequence, IteratorProtocol {
        var tick: Date
        let step: TimeInterval
        var changes: ArraySlice<Date>

        mutating func next() -> Date? {
            while let change = changes.first, change <= tick {
                changes.removeFirst()
                if change < tick { return change }
            }
            defer { tick = tick.addingTimeInterval(step) }
            return tick
        }
    }
}
