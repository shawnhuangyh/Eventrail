import Foundation
import SwiftData
import Testing
@testable import Eventrail

/// What the reader decides about an event goes into its entry, and the events
/// a screen's entries are turned into must never be kept past a write to them.
@MainActor
struct EventStoreEventsTests {
    func store() -> EventStore {
        EventStore(database: LibraryDatabase(at: .memory, syncing: false), libraryFile: nil,
                   calendar: nil, venues: nil, pageReads: nil)
    }

    func kept(in store: EventStore) throws -> [LibraryEntry] {
        try store.database.context.fetch(LibraryEntry.library)
    }

    func entries(in store: EventStore) throws -> [LibraryEntry] {
        try store.database.context.fetch(FetchDescriptor<LibraryEntry>())
    }

    @Test func aWriteToAnEventIsReadOnTheNextAsk() throws {
        let store = store()
        // Read from its own page, so a later copy's answers are taken over it.
        store.toggleLibraryMembership(Fixtures.event(id: "1", title: "Before", isDetailed: true))
        store.toggleLibraryMembership(Fixtures.event(id: "2", title: "Beside"))
        let rows = try kept(in: store)
        #expect(Set(store.events(of: rows, where: \.inLibrary).map(\.title)) == ["Before", "Beside"])

        store.setTracking(Tracking(note: "front row"), for: Fixtures.event(id: "1", title: "After", isDetailed: true))
        #expect(store.event(id: "1")?.title == "After")
        #expect(Set(store.events(of: rows, where: \.inLibrary).map(\.title)) == ["After", "Beside"])
    }

    @Test func anEventTakenOutIsNotListed() throws {
        let store = store()
        let event = Fixtures.event(id: "1")
        store.toggleLibraryMembership(event)
        #expect(store.events(of: try kept(in: store), where: \.inLibrary).map(\.id) == ["1"])

        store.toggleLibraryMembership(event)
        #expect(store.events(of: try kept(in: store), where: \.inLibrary).isEmpty)
    }

    /// CloudKit sends an entry and the facts beside it as two records, in
    /// whichever order it likes. An entry whose facts have not arrived was
    /// left off My Events while every other screen said it was kept.
    @Test func anEntryWhoseFactsHaveNotArrivedIsStillListed() throws {
        let store = store()
        let entry = LibraryEntry(eventID: "7")
        store.database.context.insert(entry)
        entry.inLibrary = true
        entry.modified = .now
        entry.kept = Fixtures.event(id: "7", title: "Arrived first")
        try store.database.context.save()

        #expect(store.events(of: try kept(in: store), where: \.inLibrary).map(\.title) == ["Arrived first"])
    }

    /// Between an import and its fold, two entries for one event list it once,
    /// as the one written last says.
    @Test func twoEntriesForOneEventAnswerAsTheNewerSays() throws {
        let store = store()
        let context = store.database.context
        for (inLibrary, ago) in [(true, 60.0), (false, 1.0)] {
            let entry = LibraryEntry(eventID: "1")
            context.insert(entry)
            entry.inLibrary = inLibrary
            entry.modified = .now.addingTimeInterval(-ago)
            entry.kept = Fixtures.event(id: "1")
        }
        try context.save()
        // What an import from iCloud landing tells the store.
        store.database.onRemoteChanges?()

        #expect(store.events(of: try entries(in: store), where: \.inLibrary).isEmpty)
        #expect(!store.isInLibrary(Fixtures.event(id: "1")))

        // And the fold after it keeps that one.
        try LibraryDatabase.deduplicate(in: context)
        #expect(try entries(in: store).map(\.inLibrary) == [false])
    }

    /// An event added on a device the entry holding its note had not reached
    /// yet: once that entry lands and the two are folded, the note, the ticket
    /// and the heart are all still there.
    @Test func anEventAddedBeforeItsNoteArrivedKeepsTheNote() throws {
        let store = store()
        let event = Fixtures.event(id: "1")
        store.toggleLibraryMembership(event)
        store.saveNow()
        let context = store.database.context
        // From a build that dated only the whole entry, written an hour ago.
        let arrived = LibraryEntry(eventID: "1")
        context.insert(arrived)
        arrived.give(LibraryEntry.Answers(inLibrary: true, isFavorite: true,
                                          tracking: Tracking(ticket: .purchased, note: "front row")),
                     dated: [:])
        arrived.modified = Date.now.addingTimeInterval(-3600).toTheMillisecond
        try context.save()

        // What an import from iCloud landing does.
        try LibraryDatabase.settle(in: context)
        store.database.onRemoteChanges?()

        #expect(try entries(in: store).count == 1)
        #expect(store.isInLibrary(event))
        #expect(store.isFavorite(event))
        #expect(store.tracking(for: event).note == "front row")
        #expect(store.tracking(for: event).ticket == .purchased)
    }

    /// Only the part given is dated: adding an event says nothing about its
    /// heart or its note.
    @Test func aWriteDatesOnlyThePartItGives() throws {
        let store = store()
        let event = Fixtures.event(id: "1")
        store.toggleLibraryMembership(event)
        let entry = try #require(try entries(in: store).first)
        #expect(entry.changed(.inLibrary) > .distantPast)
        #expect(entry.changed(.favorite) == .distantPast)
        #expect(entry.changed(.tracking) == .distantPast)
    }

    /// An entry is only sent with an answer somebody gave: the same answer
    /// again is not a write.
    @Test func theSameAnswerAgainWritesNothing() throws {
        let store = store()
        let event = Fixtures.event(id: "1")
        store.setTracking(Tracking(note: "front row"), for: event)
        store.saveNow()
        let entry = try #require(try entries(in: store).first)
        let written = entry.modified

        store.setTracking(Tracking(note: "front row"), for: event)
        #expect(!entry.hasChanges)
        #expect(entry.modified == written)
        // And an event nobody said anything about has no entry at all.
        store.setTracking(Tracking(), for: Fixtures.event(id: "2"))
        #expect(try entries(in: store).map(\.eventID) == ["1"])
    }

    /// A read is a record apart from the event: marking one writes neither
    /// the reader's entry nor the event's facts.
    @Test func markingADateReadWritesOnlyTheMark() throws {
        let store = store()
        let event = Fixtures.event(id: "1", date: Date.now.addingTimeInterval(7 * 24 * 60 * 60))
        store.toggleLibraryMembership(event)
        store.saveNow()
        let context = store.database.context
        let entry = try #require(try entries(in: store).first)
        let row = try #require(try context.fetch(FetchDescriptor<LibraryEvent>()).first)

        store.markRead([event], read: true)
        #expect(!store.isUnread(event))
        #expect(!entry.hasChanges)
        #expect(!row.hasChanges)
        #expect(context.insertedModelsArray.contains { $0 is FollowingReadMark })
        store.saveNow()
        #expect(try context.fetchCount(FetchDescriptor<FollowingReadMark>()) == 1)
    }

    /// Taken out, an event keeps its facts: a row emptied on one device lands
    /// empty on every other, and an entry arriving there has nothing to show.
    @Test func anEventTakenOutKeepsItsFacts() throws {
        let store = store()
        let event = Fixtures.event(id: "1")
        store.toggleLibraryMembership(event)
        store.toggleLibraryMembership(event)
        store.saveNow()
        let context = store.database.context
        #expect(try context.fetch(FetchDescriptor<LibraryEvent>()).map(\.facts?.id) == ["1"])
        let entry = try #require(try entries(in: store).first)
        #expect(entry.inLibrary == false)
        #expect(entry.modified > .distantPast)
    }

    /// A note outlives its event, so adding it back brings the note back.
    @Test func aRemovalKeepsTheNote() throws {
        let store = store()
        let event = Fixtures.event(id: "1")
        store.toggleLibraryMembership(event)
        store.setTracking(Tracking(note: "front row"), for: event)
        store.remove([event])
        #expect(!store.isInLibrary(event))
        #expect(store.tracking(for: event).note == "front row")
    }

    @Test func askingTwiceGivesTheSame() throws {
        let store = store()
        for id in ["1", "2", "3"] { store.toggleLibraryMembership(Fixtures.event(id: id)) }
        let rows = try kept(in: store)
        #expect(store.events(of: rows, where: \.inLibrary) == store.events(of: rows, where: \.inLibrary))
    }
}
