import Foundation
import Testing
@testable import Eventrail

/// When an event's page was last read, for the line under Refresh in its
/// sheet's menu — see ``EventStore/lastRead(of:)``.
@MainActor
struct EventLastReadTests {
    func store(reads: PageReads) -> EventStore {
        EventStore(database: LibraryDatabase(at: .memory, syncing: false), libraryFile: nil,
                   calendar: nil, venues: nil, pageReads: reads)
    }

    /// A read that found the page unchanged writes nothing to the copy, so the
    /// copy's own date still says the last change; this device's stamp says
    /// the read.
    @Test func aReadThatChangedNothingStillCounts() throws {
        let reads = PageReads(persists: false)
        let store = store(reads: reads)
        var event = Fixtures.event(id: "1")
        event.readAt = Date.now.addingTimeInterval(-3 * 24 * 60 * 60)
        #expect(store.lastRead(of: event) == event.readAt)

        reads.record(event.id, asked: .now)
        let last = try #require(store.lastRead(of: event))
        #expect(last > event.readAt!)
    }

    /// Read since on another device, the copy's own date is the later one.
    @Test func aLaterReadOfTheCopyStands() {
        let reads = PageReads(persists: false)
        let store = store(reads: reads)
        reads.record("1", asked: .now)
        var event = Fixtures.event(id: "1")
        event.readAt = Date.now.addingTimeInterval(60)
        #expect(store.lastRead(of: event) == event.readAt)
    }

    @Test func aPageNeverReadSaysNothing() {
        #expect(store(reads: PageReads(persists: false)).lastRead(of: Fixtures.event(id: "1")) == nil)
    }
}
