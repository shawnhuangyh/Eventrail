import Foundation
import SwiftData
import Testing
@testable import Eventrail

/// The events a screen's rows are turned into are kept between redraws, and
/// must never be kept past a write to their row.
@MainActor
struct EventStoreEventsTests {
    func store() -> EventStore {
        EventStore(database: LibraryDatabase(at: .memory, syncing: false), libraryFile: nil,
                   calendar: nil, venues: nil, pageReads: nil)
    }

    func kept(in store: EventStore) throws -> [LibraryEvent] {
        try store.database.context.fetch(LibraryEvent.library)
    }

    @Test func aWriteToARowIsReadOnTheNextAsk() throws {
        let store = store()
        // Read from its own page, so a later copy's answers are taken over it.
        store.toggleLibraryMembership(Fixtures.event(id: "1", title: "Before", isDetailed: true))
        store.toggleLibraryMembership(Fixtures.event(id: "2", title: "Beside"))
        let rows = try kept(in: store)
        #expect(Set(store.events(of: rows).map(\.title)) == ["Before", "Beside"])

        store.setTracking(Tracking(note: "front row"), for: Fixtures.event(id: "1", title: "After", isDetailed: true))
        #expect(rows.first { $0.eventID == "1" }?.facts?.title == "After")
        #expect(Set(store.events(of: rows).map(\.title)) == ["After", "Beside"])
    }

    @Test func aRowTakenOutIsNotListed() throws {
        let store = store()
        let event = Fixtures.event(id: "1")
        store.toggleLibraryMembership(event)
        #expect(store.events(of: try kept(in: store)).map(\.id) == ["1"])

        store.toggleLibraryMembership(event)
        #expect(store.events(of: try kept(in: store)).isEmpty)
    }

    /// A read is a record apart from the event: marking one sends nothing
    /// about whether the event is in the library, so a device that has not
    /// yet heard of a removal cannot undo it by opening the event.
    @Test func markingADateReadLeavesTheEventsRowAlone() throws {
        let store = store()
        let event = Fixtures.event(id: "1", date: Date.now.addingTimeInterval(7 * 24 * 60 * 60))
        store.toggleLibraryMembership(event)
        store.saveNow()
        let row = try #require(try kept(in: store).first)

        store.markRead([event], read: true)
        #expect(!store.isUnread(event))
        #expect(!row.hasChanges)
        #expect(store.database.context.insertedModelsArray.contains { $0 is FollowingReadMark })
        store.saveNow()
        #expect(try store.database.context.fetchCount(FetchDescriptor<FollowingReadMark>()) == 1)
    }

    @Test func askingTwiceGivesTheSame() throws {
        let store = store()
        for id in ["1", "2", "3"] { store.toggleLibraryMembership(Fixtures.event(id: id)) }
        let rows = try kept(in: store)
        #expect(store.events(of: rows) == store.events(of: rows))
    }
}
