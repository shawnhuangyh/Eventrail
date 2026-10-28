import Foundation
import Testing
@testable import Eventrail

/// Not on Your Account: the library held against what the linked account
/// listed at its last whole read — see ``EventStore/notOnAccount(_:)``.
@MainActor
struct AccountEventsTests {
    func store(_ listings: AccountEvents) -> EventStore {
        EventStore(database: LibraryDatabase(at: .memory, syncing: false), libraryFile: nil,
                   calendar: nil, venues: nil, pageReads: nil, accountEvents: listings)
    }

    func link(_ handle: String, in store: EventStore) {
        store.link(EventernoteProfile(handle: handle, name: handle, bio: nil, eventCount: nil,
                                      favoritePerformers: [], avatarURL: nil))
    }

    @Test func namesTheKeptEventsTheAccountDidNotList() {
        let listings = AccountEvents(persists: false)
        let store = store(listings)
        link("someone", in: store)
        let listed = Fixtures.event(id: "1")
        let addedHere = Fixtures.event(id: "2")
        store.toggleLibraryMembership(listed)
        store.toggleLibraryMembership(addedHere)
        listings.record(["1"], for: "someone")

        let missing = store.notOnAccount([listed, addedHere])

        #expect(missing?.map(\.id) == ["2"])
        #expect(store.isNotOnAccount(addedHere))
        #expect(!store.isNotOnAccount(listed))
    }

    /// With no whole read to go by, nothing is said to be missing.
    @Test func saysNothingBeforeTheAccountIsReadWhole() {
        let store = store(AccountEvents(persists: false))
        link("someone", in: store)
        let event = Fixtures.event(id: "1")
        store.toggleLibraryMembership(event)

        #expect(store.notOnAccount([event]) == nil)
        #expect(!store.isNotOnAccount(event))
    }

    /// What one account listed is not held against another.
    @Test func aListReadFromAnotherAccountIsNotUsed() {
        let listings = AccountEvents(persists: false)
        let store = store(listings)
        link("someone", in: store)
        listings.record(["1"], for: "somebody else")

        #expect(store.notOnAccount([Fixtures.event(id: "2")]) == nil)
    }

    /// An event met in Search and never kept is nothing to mark on the site.
    @Test func anEventNotKeptIsNotMissing() {
        let listings = AccountEvents(persists: false)
        let store = store(listings)
        link("someone", in: store)
        listings.record([], for: "someone")

        #expect(!store.isNotOnAccount(Fixtures.event(id: "1")))
    }

    @Test func unlinkingForgetsWhatTheAccountListed() {
        let listings = AccountEvents(persists: false)
        let store = store(listings)
        link("someone", in: store)
        listings.record(["1"], for: "someone")

        store.unlinkAccount()

        #expect(listings.listing(for: "someone") == nil)
    }

    /// A whole read is written over whatever was held for any account.
    @Test func aWholeReadReplacesEveryEarlierList() {
        let listings = AccountEvents(persists: false)
        listings.record(["1"], for: "before")
        listings.record(["2"], for: "after")

        #expect(listings.listing(for: "before") == nil)
        #expect(listings.listing(for: "after")?.events == ["2"])
    }
}
