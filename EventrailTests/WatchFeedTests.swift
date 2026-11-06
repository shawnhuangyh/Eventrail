import Foundation
import Testing
@testable import Eventrail

/// What the watch is sent — see ``Event/isOnTheWatch(at:)``.
@MainActor
struct WatchFeedTests {
    /// Doors 23:30, on until 02:00 the next morning.
    let overnight = Fixtures.event(date: Fixtures.date(2026, 11, 14),
                                   doorsOpen: Fixtures.date(2026, 11, 14, 23, 30),
                                   startsAt: Fixtures.date(2026, 11, 14, 23, 45),
                                   endsAt: Fixtures.date(2026, 11, 15, 2))

    func store() -> EventStore {
        EventStore(database: LibraryDatabase(at: .memory, syncing: false), libraryFile: nil,
                   calendar: nil, venues: nil, pageReads: nil, readCopies: nil)
    }

    @Test func aShowStaysOnTheWatchAsLongAsItRuns() {
        #expect(overnight.isOnTheWatch(at: Fixtures.date(2026, 11, 14, 12)))
        #expect(overnight.isOnTheWatch(at: Fixtures.date(2026, 11, 15, 1)))
        #expect(!overnight.isOnTheWatch(at: Fixtures.date(2026, 11, 15, 2)))
    }

    /// The page prints a clock and no date: 00:30 after 23:30 is the next day.
    @Test func timesPrintedPastMidnightAreReadInOrder() {
        let printed = Fixtures.event(date: Fixtures.date(2026, 11, 14),
                                     doorsOpen: Fixtures.date(2026, 11, 14, 23, 30),
                                     startsAt: Fixtures.date(2026, 11, 14, 0, 30),
                                     endsAt: Fixtures.date(2026, 11, 14, 5))
        #expect(printed.isOnTheWatch(at: Fixtures.date(2026, 11, 15, 4, 59)))
        #expect(!printed.isOnTheWatch(at: Fixtures.date(2026, 11, 15, 5)))
    }

    @Test func noEndPublishedRunsItsAssumedLength() {
        let open = Fixtures.event(date: Fixtures.date(2026, 11, 14), startsAt: Fixtures.date(2026, 11, 14, 23))
        let ends = Fixtures.date(2026, 11, 14, 23).addingTimeInterval(Event.assumedLength)
        #expect(open.isOnTheWatch(at: ends.addingTimeInterval(-1)))
        #expect(!open.isOnTheWatch(at: ends))
    }

    @Test func noStartGoesAtTheEndOfItsDay() {
        let bare = Fixtures.event(date: Fixtures.date(2026, 11, 14))
        #expect(bare.isOnTheWatch(at: bare.dayEnds.addingTimeInterval(-1)))
        #expect(!bare.isOnTheWatch(at: bare.dayEnds))
    }

    /// Past its day the lists let it go; the watch's copy does not.
    @Test func theFeedHoldsAShowTheListsHaveLetGo() {
        let store = store()
        let running = Fixtures.event(id: "running", date: Fixtures.day(fromToday: -1),
                                     startsAt: Date.now.addingTimeInterval(-3600),
                                     endsAt: Date.now.addingTimeInterval(3600))
        let over = Fixtures.event(id: "over", date: Fixtures.day(fromToday: -3))
        let ahead = Fixtures.event(id: "ahead", date: Fixtures.day(fromToday: 3))
        for event in [running, over, ahead] { store.toggleLibraryMembership(event) }

        #expect(store.upcoming.map(\.id) == ["ahead"])
        #expect(store.onTheWatch.map(\.id) == ["running", "ahead"])
    }
}
