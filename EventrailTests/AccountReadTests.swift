import Foundation
import Testing
@testable import Eventrail

/// What a read of the linked account brings into the library: one the reader
/// asked for puts back what they took out, and one the app makes by itself
/// only adds — see ``EventStore/adopt(_:restoring:)``.
@MainActor
struct AccountReadTests {
    func store() -> EventStore {
        EventStore(database: LibraryDatabase(at: .memory, syncing: false), libraryFile: nil,
                   calendar: nil, venues: nil, pageReads: nil)
    }

    /// A store holding one event the reader added and then took out.
    func storeWithRemoval(of event: Event) -> EventStore {
        let store = store()
        store.toggleLibraryMembership(event)
        store.remove([event])
        return store
    }

    @Test func aReadByItselfLeavesOutAnEventTakenOutAndAddsANewOne() {
        let removed = Fixtures.event(id: "1", title: "Taken out")
        let marked = Fixtures.event(id: "2", title: "Marked since")
        let store = storeWithRemoval(of: removed)

        let added = store.adopt([removed, marked], restoring: false)

        #expect(added.map(\.id) == ["2"])
        #expect(!store.isInLibrary(removed))
        #expect(store.isInLibrary(marked))
    }

    @Test func aReadAskedForBringsBackAnEventTakenOut() {
        let removed = Fixtures.event(id: "1", title: "Taken out")
        let store = storeWithRemoval(of: removed)

        let added = store.adopt([removed], restoring: true)

        #expect(added.map(\.id) == ["1"])
        #expect(store.isInLibrary(removed))
    }

    /// An event already kept is not counted as arriving again.
    @Test func anEventAlreadyKeptIsNotAddedAgain() {
        let store = store()
        let kept = Fixtures.event(id: "1")
        store.toggleLibraryMembership(kept)

        #expect(store.adopt([kept], restoring: false).isEmpty)
        #expect(store.isInLibrary(kept))
    }

    @Test func aReadByItselfLeavesSomebodyUnfollowedUnfollowed() {
        let store = store()
        let dropped = PerformerProfile(id: 1, name: "A", reading: nil, fanCount: nil, slug: "a")
        let favourited = PerformerProfile(id: 2, name: "B", reading: nil, fanCount: nil, slug: "b")
        store.toggleFollow(dropped)
        store.toggleFollow(dropped)

        let read = store.adoptFollows([dropped, favourited], restoring: false)

        #expect(read.added == 1)
        #expect(!store.isFollowing(dropped))
        #expect(store.isFollowing(favourited))
    }

    @Test func aReadAskedForFollowsSomebodyUnfollowedAgain() {
        let store = store()
        let dropped = PerformerProfile(id: 1, name: "A", reading: nil, fanCount: nil, slug: "a")
        store.toggleFollow(dropped)
        store.toggleFollow(dropped)

        #expect(store.adoptFollows([dropped], restoring: true).added == 1)
        #expect(store.isFollowing(dropped))
    }

    // MARK: - When the app reads the account by itself

    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func anAccountNeverReadIsOwedARead() {
        #expect(EventStore.owesAccountRead(lastImported: nil, lastTried: nil, waitsOnCloud: false, at: now))
    }

    @Test func anAccountReadWithinTheWindowIsNotReadAgain() {
        let read = now.addingTimeInterval(-(Freshness.window - 60))
        #expect(!EventStore.owesAccountRead(lastImported: read, lastTried: nil, waitsOnCloud: false, at: now))
    }

    @Test func anAccountReadLongerAgoThanTheWindowIsReadAgain() {
        let read = now.addingTimeInterval(-(Freshness.window + 60))
        #expect(EventStore.owesAccountRead(lastImported: read, lastTried: nil, waitsOnCloud: false, at: now))
    }

    /// A read that did not get through is not tried again at once, so a phone
    /// offline is not told so on every return to the app.
    @Test func aReadTriedJustNowIsNotTriedAgainUntilThePatienceIsOut() {
        let tried = now.addingTimeInterval(-60)
        #expect(!EventStore.owesAccountRead(lastImported: nil, lastTried: tried, waitsOnCloud: false, at: now))
        let longAgo = now.addingTimeInterval(-(EventStore.accountRetryPatience + 60))
        #expect(EventStore.owesAccountRead(lastImported: nil, lastTried: longAgo, waitsOnCloud: false, at: now))
    }

    /// A device that syncs and has not yet heard from iCloud does not know
    /// what the reader took out on their others.
    @Test func aDeviceYetToHearFromICloudWaits() {
        #expect(!EventStore.owesAccountRead(lastImported: nil, lastTried: nil, waitsOnCloud: true, at: now))
    }

    /// Syncing, or about to — the account not yet checked — and nothing
    /// fetched: an import may still bring the reader's removals.
    @Test func aDeviceStillToHearFromICloudWaitsOnIt() {
        #expect(EventStore.awaitsFirstFetch(syncing: true, fetched: nil, status: nil))
        #expect(EventStore.awaitsFirstFetch(syncing: true, fetched: nil, status: .synced))
        #expect(EventStore.awaitsFirstFetch(syncing: true, fetched: nil, status: .offline))
        #expect(!EventStore.awaitsFirstFetch(syncing: true, fetched: now, status: nil))
        #expect(!EventStore.awaitsFirstFetch(syncing: false, fetched: nil, status: nil))
    }

    /// Where iCloud has said nothing will come — as on a simulator signed out
    /// of it, its switch on — waiting would be waiting for good.
    @Test func aDeviceICloudWillSendNothingDoesNotWaitOnIt() {
        #expect(!EventStore.awaitsFirstFetch(syncing: true, fetched: nil, status: .signedOut))
        #expect(!EventStore.awaitsFirstFetch(syncing: true, fetched: nil, status: .notConfigured))
        #expect(!EventStore.awaitsFirstFetch(syncing: true, fetched: nil, status: .accountChanged))
        #expect(!EventStore.awaitsFirstFetch(syncing: true, fetched: nil, status: .cloudDataDeleted))
        #expect(!EventStore.awaitsFirstFetch(syncing: true, fetched: nil, status: .failed("Refused")))
    }
}
