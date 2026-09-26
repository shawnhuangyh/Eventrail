import Foundation
import Testing
@testable import Eventrail

struct FollowingReadTests {
    /// A night far enough ahead that pruning never reaches it.
    private static let ahead = Date.now.addingTimeInterval(30 * 24 * 60 * 60)

    private func event(_ id: String = "1", startsAt: Date? = nil) -> Event {
        Fixtures.event(id: id, date: Self.ahead, startsAt: startsAt, performers: ["A"])
    }

    private func archive(_ reads: [Event.ID: Stamped<FollowingRead>]) -> LibraryArchive {
        var archive = LibraryArchive()
        archive.followingReads = reads
        return archive
    }

    private func read(_ event: Event, at date: Date) -> Stamped<FollowingRead> {
        Stamped(FollowingRead(fingerprint: event.listingFingerprint, day: event.date), at: date)
    }

    private func unread(_ event: Event, at date: Date) -> Stamped<FollowingRead> {
        Stamped(FollowingRead(fingerprint: nil, day: event.date), at: date)
    }

    // MARK: - What counts as a change

    @Test func sameRowGivesTheSameFingerprint() {
        let event = Fixtures.event(performers: ["A", "B"])
        #expect(event.listingFingerprint == Fixtures.event(performers: ["A", "B"]).listingFingerprint)
    }

    @Test func aChangedRowGivesADifferentFingerprint() {
        let read = Fixtures.event(performers: ["A"])
        let changes = [
            Fixtures.event(title: "Live (追加公演)", performers: ["A"]),
            Fixtures.event(venue: "Arena", performers: ["A"]),
            Fixtures.event(date: Fixtures.date(2027, 5, 10), performers: ["A"]),
            Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 18), performers: ["A"]),
            Fixtures.event(performers: ["A", "B"]),
        ]
        for changed in changes {
            #expect(changed.listingFingerprint != read.listingFingerprint)
        }
    }

    @Test func aNightRetimedAtItsHallGivesTheSameFingerprint() throws {
        let listed = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 18), performers: ["A"])
        let taipei = try #require(TimeZone(identifier: "Asia/Taipei"))
        let kept = listed.published(in: taipei)
        #expect(kept.startsAt != listed.startsAt)
        #expect(kept.listingFingerprint == listed.listingFingerprint)
    }

    @Test func aMarkTakenOverInstantsStillCounts() {
        let one = event(startsAt: Self.ahead.addingTimeInterval(18 * 60 * 60))
        let old = Stamped(FollowingRead(fingerprint: one.instantFingerprint, day: one.date), at: .now)
        #expect(!archive([one.id: old]).isUnread(one))
    }

    // MARK: - Unread

    @Test func aDateNeverMarkedIsUnread() {
        #expect(LibraryArchive().isUnread(event()))
    }

    @Test func aDateMarkedReadIsRead() {
        let one = event()
        #expect(!archive([one.id: read(one, at: .now)]).isUnread(one))
    }

    @Test func aDateTheListingChangedIsUnreadAgain() {
        let one = event()
        let changed = event(startsAt: Self.ahead.addingTimeInterval(18 * 60 * 60))
        #expect(archive([one.id: read(one, at: .now)]).isUnread(changed))
    }

    @Test func unreadSaysWhetherTheDateIsNewOrUpdated() {
        let one = event()
        let changed = event(startsAt: Self.ahead.addingTimeInterval(18 * 60 * 60))
        let reads = archive([one.id: read(one, at: .now)])
        #expect(LibraryArchive().unread(one) == .new)
        #expect(reads.unread(one) == nil)
        #expect(reads.unread(changed) == .updated)
        #expect(archive([one.id: unread(one, at: .now)]).unread(one) == .new)
    }

    @Test func aDateMarkedUnreadIsUnread() {
        let one = event()
        #expect(archive([one.id: unread(one, at: .now)]).isUnread(one))
    }

    // MARK: - Across devices

    @Test func aReadOnOneDeviceReachesTheOther() {
        let one = event()
        let merged = LibraryArchive().merging(archive([one.id: read(one, at: .now)]))
        #expect(!merged.isUnread(one))
    }

    @Test func theLaterMarkWinsEitherWay() {
        let one = event()
        let earlier = Date.now.addingTimeInterval(-60)
        let phone = archive([one.id: read(one, at: earlier)])
        let pad = archive([one.id: unread(one, at: .now)])
        #expect(phone.merging(pad).isUnread(one))
        #expect(pad.merging(phone).isUnread(one))
    }

    @Test func eachDateIsSettledOnItsOwn() {
        let one = event("1"), two = event("2")
        let phone = archive([one.id: read(one, at: .now)])
        let pad = archive([two.id: read(two, at: .now)])
        let merged = phone.merging(pad)
        #expect(!merged.isUnread(one))
        #expect(!merged.isUnread(two))
    }

    // MARK: - Pruning and restoring

    @Test func aNightThatHasBeenIsPruned() {
        let past = Fixtures.event(id: "old", date: Date.now.addingTimeInterval(-10 * 24 * 60 * 60))
        let kept = event()
        let pruned = archive([past.id: read(past, at: .now), kept.id: read(kept, at: .now)]).pruned()
        #expect(pruned.followingReads?[past.id] == nil)
        #expect(pruned.followingReads?[kept.id] != nil)
    }

    @Test func aRestoreBringsBackAReadThisDeviceSaysIsUnread() {
        let one = event()
        let here = archive([one.id: unread(one, at: .now)])
        let backup = archive([one.id: read(one, at: .now.addingTimeInterval(-3600))])
        #expect(!here.restoring(backup).isUnread(one))
    }

    @Test func readsCountAsSomethingToSync() {
        let one = event()
        #expect(!archive([one.id: read(one, at: .now)]).holdsNothing)
    }

    // MARK: - Older files and backups

    @Test func decodesAnArchiveWrittenBeforeReadsExisted() throws {
        let json = #"{"events":{},"membership":{},"tracking":{},"favorites":{},"recentSearches":{"value":[],"modified":0}}"#
        let archive = try JSONDecoder().decode(LibraryArchive.self, from: Data(json.utf8))
        #expect(archive.followingReads == nil)
        #expect(archive.isUnread(event()))
    }

    @Test func aBackupCarriesTheReads() throws {
        let one = event("400001"), changed = event("400001", startsAt: Self.ahead.addingTimeInterval(3600))
        // A creation day of its own, so its file name is unlike any other test's.
        let url = try LibraryBackup(archive: archive([one.id: read(one, at: .now)]),
                                    created: Date(timeIntervalSince1970: 978_307_200)).write()
        defer { try? FileManager.default.removeItem(at: url) }

        let restored = try LibraryBackup.read(at: url).archive
        #expect(restored.unread(one) == nil)
        #expect(restored.unread(changed) == .updated)
    }

    // MARK: - Through the store

    /// A store with nothing behind it — no file, no iCloud, no calendar — the
    /// way the previews build one.
    @MainActor private func store() -> EventStore {
        EventStore(file: nil, cloud: nil, calendar: nil, venues: nil, pageReads: nil)
    }

    @MainActor @Test func markingInBulkLeavesTheRestAlone() {
        let store = store()
        let one = event("1"), two = event("2"), three = event("3")
        store.markRead([one, two, three], read: true)
        store.markRead([two], read: false)
        #expect(store.unread(one) == nil)
        #expect(store.unread(two) == .new)
        #expect(store.unread(three) == nil)
    }

    @MainActor @Test func aDateMarkedReadAndThenChangedIsUpdated() {
        let store = store()
        store.markRead([event()], read: true)
        #expect(store.unread(event(startsAt: Self.ahead.addingTimeInterval(3600))) == .updated)
    }

    @MainActor @Test func deleteAllTurnsEveryDateBackToUnread() {
        let store = store()
        let one = event("1"), two = event("2")
        store.markRead([one, two], read: true)
        store.removeAllEvents()
        #expect(store.unread(one) == .new)
        #expect(store.unread(two) == .new)
    }
}
