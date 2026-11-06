import Foundation
import Testing
@testable import Eventrail

struct FollowingReadTests {
    /// An event far enough ahead that pruning never reaches it.
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

    @Test func anEventRetimedAtItsHallGivesTheSameFingerprint() throws {
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

    @Test func aMarkTakenOnTokyoTimeStillCountsOnceTheRowIsOnItsHallsClock() throws {
        let listed = event(startsAt: Self.ahead.addingTimeInterval(18 * 60 * 60))
        let old = Stamped(FollowingRead(fingerprint: listed.instantFingerprint, day: listed.date), at: .now)
        let taipei = try #require(TimeZone(identifier: "Asia/Taipei"))
        #expect(!archive([listed.id: old]).isUnread(listed.published(in: taipei)))
    }

    @Test func readingAnEndAsTheNextMorningLeavesTheFingerprintAlone() {
        let sameDay = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 23), endsAt: Fixtures.date(2027, 5, 9, 1))
        let nextMorning = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 23), endsAt: Fixtures.date(2027, 5, 10, 1))
        #expect(sameDay.listingFingerprint == nextMorning.listingFingerprint)
    }

    @Test func aMarkTakenBeforeTheEndMovedToTheNextMorningStillCounts() {
        // A day as the page gives one, a midnight, with 23:00 on it and an
        // end printed 01:00 — read once onto that day, now onto the next.
        let sameDay = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 23), endsAt: Fixtures.date(2027, 5, 9, 1))
        var nextMorning = sameDay
        nextMorning.endsAt = Fixtures.date(2027, 5, 10, 1)
        let old = Stamped(FollowingRead(fingerprint: sameDay.instantFingerprint, day: sameDay.date), at: .now)
        #expect(!archive([sameDay.id: old]).isUnread(nextMorning))
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
        #expect(reads.unread(changed) == .updated(nil))
        #expect(archive([one.id: unread(one, at: .now)]).unread(one) == .new)
    }

    @Test func aDateMarkedUnreadIsUnread() {
        let one = event()
        #expect(archive([one.id: unread(one, at: .now)]).isUnread(one))
    }

    // MARK: - What changed

    @Test func theFingerprintIsSpelledAsItAlwaysWas() {
        // Taken before the fingerprint was read off a kept copy: every mark
        // already written is one of these.
        #expect(Fixtures.event().listingFingerprint == "3ead1cecf4a16173ee13c2e4")
        let timed = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 18, 30), endsAt: Fixtures.date(2027, 5, 10, 1, 5),
                                   performers: ["A", "B"])
        #expect(timed.listingFingerprint == "12b3ea1a6ca8fd2412b7aadc")
    }

    @Test func aCopyAndTheEventItWasTakenOfHaveNothingBetweenThem() {
        let one = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 18), performers: ["A"])
        #expect(ListingChanges(from: ListingCopy(one), to: one) == nil)
    }

    @Test func aMovedTimeSaysWhatItWasAndIs() throws {
        let read = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 18), performers: ["A"])
        let now = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 18, 30), performers: ["A"])
        let changes = try #require(ListingChanges(from: ListingCopy(read), to: now))
        #expect(changes.changes == [.time(.startsAt)])
        let shown = changes.shown(on: .venue)
        #expect(shown.was.timeLine == read.timeLine)
        #expect(shown.now.timeLine == now.timeLine)
    }

    @Test func aTimePublishedAtLastWasNoneBefore() throws {
        let read = Fixtures.event(performers: ["A"])
        let now = Fixtures.event(doorsOpen: Fixtures.date(2027, 5, 9, 17), performers: ["A"])
        let changes = try #require(ListingChanges(from: ListingCopy(read), to: now))
        #expect(changes.changes == [.time(.doorsOpen)])
        #expect(changes.shown(on: .venue).was.doorsLine == nil)
    }

    @Test func theBillSaysWhoCameAndWhoWent() throws {
        let read = Fixtures.event(performers: ["A", "B", "C"])
        let now = Fixtures.event(performers: ["B", "D", "C", "E"])
        let changes = try #require(ListingChanges(from: ListingCopy(read), to: now))
        #expect(changes.changes == [.performers(added: ["D", "E"], removed: ["A"])])
    }

    @Test func theSameNamesInAnotherOrderSaySo() throws {
        let changes = try #require(ListingChanges(from: ListingCopy(Fixtures.event(performers: ["A", "B"])),
                                                  to: Fixtures.event(performers: ["B", "A"])))
        #expect(changes.changes == [.billingOrder])
    }

    @Test func everyChangeIsListedDayFirstAndTitleLast() throws {
        let read = Fixtures.event(title: "Live", venue: "Hall", date: Fixtures.date(2027, 5, 9),
                                  doorsOpen: Fixtures.date(2027, 5, 9, 17), performers: ["A"])
        let now = Fixtures.event(title: "Live (追加公演)", venue: "Arena", date: Fixtures.date(2027, 5, 10),
                                 doorsOpen: Fixtures.date(2027, 5, 10, 16), performers: ["A", "B"])
        let changes = try #require(ListingChanges(from: ListingCopy(read), to: now))
        #expect(changes.changes == [
            .day, .time(.doorsOpen), .venue(was: "Hall", now: "Arena"),
            .performers(added: ["B"], removed: []), .title(was: "Live", now: "Live (追加公演)"),
        ])
        let shown = changes.shown(on: .venue)
        #expect(shown.was.dayLine == read.dayLine)
        #expect(shown.was.doorsLine == read.doorsLine)
        #expect(shown.now.dayLine == now.dayLine)
        #expect(changes.changed(.day) && changes.changed(.time(.doorsOpen)) && !changes.changed(.time(.startsAt)))
        #expect(changes.venueChanged && changes.titleChanged)
        #expect(changes.added == ["B"])
    }

    @Test func aTimeAfterMidnightIsReadBackOnTheNextMorning() throws {
        let read = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 23), endsAt: Fixtures.date(2027, 5, 10, 1))
        let now = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 23), endsAt: Fixtures.date(2027, 5, 10, 2))
        let changes = try #require(ListingChanges(from: ListingCopy(read), to: now))
        #expect(changes.changes == [.time(.endsAt)])
        #expect(changes.shown(on: .venue).was.endsAt == read.endsAt)
    }

    @Test func aCopyReadOnTokyoTimeIsComparedWithItsHallsClock() throws {
        // Read on Following, on Tokyo time; drawn again in My Events, re-read
        // at the hall abroad with its start moved half an hour.
        let listed = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 18), performers: ["A"])
        let kept = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 18, 30), performers: ["A"])
            .published(in: Fixtures.taipei)
        let changes = try #require(ListingChanges(from: ListingCopy(listed), to: kept))
        #expect(changes.changes == [.time(.startsAt)])
        #expect(changes.shown(on: .venue).was.startsAt == listed.published(in: Fixtures.taipei).startsAt)
    }

    @Test func aHallReplacedAbroadKeepsTheClockItWasReadOn() throws {
        // Tokyo 18:00 replaced by Taipei 19:00: on a Shanghai reader's clock
        // 17:00 became 19:00, which only the instants can say.
        let read = Fixtures.event(venue: "Hall", startsAt: Fixtures.date(2027, 5, 9, 18), performers: ["A"])
        let now = Fixtures.event(venue: "Arena", date: Fixtures.date(2027, 5, 9, in: Fixtures.taipei),
                                 startsAt: Fixtures.date(2027, 5, 9, 19, in: Fixtures.taipei),
                                 timeZone: Fixtures.taipei, performers: ["A"])
        let changes = try #require(ListingChanges(from: ListingCopy(read), to: now))
        #expect(changes.changes == [.time(.startsAt), .venue(was: "Hall", now: "Arena")])
        let shown = changes.shown(on: .venue)
        #expect(shown.was.startsAt == read.startsAt)
        #expect(shown.was.timeLine == read.timeLine)
        #expect(shown.now.timeLine == now.timeLine)
    }

    @Test func theSameHallIsReadBackOnTheClockTheEventKeepsNow() throws {
        // Read on Following on Tokyo time, before the hall was placed; the
        // copy since retimed to Taipei moved its start, and the start read
        // is Taipei's 18:00, not Tokyo's.
        let listed = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 18), performers: ["A"])
        let placed = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 19), performers: ["A"])
            .published(in: Fixtures.taipei)
        let changes = try #require(ListingChanges(from: ListingCopy(listed), to: placed))
        #expect(changes.shown(on: .venue).was.startsAt == listed.published(in: Fixtures.taipei).startsAt)
    }

    @Test func aCopyComesBackOutAsItWentIn() throws {
        let one = Fixtures.event(doorsOpen: Fixtures.date(2027, 5, 9, 17), startsAt: Fixtures.date(2027, 5, 9, 18),
                                 performers: ["A", "B"])
        let copy = ListingCopy(one)
        #expect(try JSONDecoder().decode(ListingCopy.self, from: JSONEncoder().encode(copy)) == copy)
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

    @Test func anEventThatHasBeenIsPruned() {
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
        #expect(restored.unread(changed) == .updated(nil))
    }

    // MARK: - Through the store

    /// A store with nothing behind it — a store in memory, no iCloud, no
    /// calendar — the way the previews build one.
    @MainActor private func store(
        database: LibraryDatabase = LibraryDatabase(at: .memory, syncing: false),
        copies: ReadCopies = ReadCopies(persists: false)
    ) -> EventStore {
        EventStore(database: database, libraryFile: nil, calendar: nil, venues: nil, pageReads: nil,
                   readCopies: copies)
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
        let changed = store.unread(event(startsAt: Self.ahead.addingTimeInterval(3600)))
        #expect(changed?.changes?.changes == [.time(.startsAt)])
    }

    @MainActor @Test func aCopyDrawnUnchangedIsHeldForTheNextChange() {
        // Read on another device — or by a build that kept no copy — so this
        // one holds nothing to say what changed, until it draws the row as
        // it was read.
        let database = LibraryDatabase(at: .memory, syncing: false)
        let one = event(), changed = event(startsAt: Self.ahead.addingTimeInterval(3600))
        let elsewhere = store(database: database)
        elsewhere.markRead([one], read: true)
        elsewhere.saveNow()

        let here = store(database: database)
        #expect(here.unread(changed) == .updated(nil))
        #expect(here.unread(one) == nil)
        #expect(here.unread(changed)?.changes?.changes == [.time(.startsAt)])
    }

    @MainActor @Test func readingAnUpdatedDateKeepsWhatChangedForItsSheet() {
        let store = store()
        let one = event(), changed = event(startsAt: Self.ahead.addingTimeInterval(3600))
        store.markRead([one], read: true)
        #expect(store.changesRead(in: one) == nil)
        store.markRead([changed], read: true)
        #expect(store.changesRead(in: changed)?.changes == [.time(.startsAt)])
        #expect(store.unread(changed) == nil)
        store.markRead([changed], read: false)
        #expect(store.changesRead(in: changed) == nil)
    }

    @MainActor @Test func theSheetsCardFollowsTheEventAsItStands() throws {
        // Read at 18:00, opened at 19:00; the sheet's page read then brings
        // 20:00, and the hall is placed in Taipei.
        let store = store()
        let one = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 18), performers: ["A"])
        let opened = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 19), performers: ["A"])
        let reread = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 20), performers: ["A"])
        store.markRead([one], read: true)
        store.markRead([opened], read: true)

        let later = try #require(store.changesRead(in: reread)).shown(on: .venue)
        #expect(later.was.timeLine == one.timeLine)
        #expect(later.now.timeLine == reread.timeLine)

        let placed = reread.published(in: Fixtures.taipei)
        let abroad = try #require(store.changesRead(in: placed)).shown(on: .venue)
        #expect(abroad.was.startsAt == one.published(in: Fixtures.taipei).startsAt)
        #expect(abroad.now.startsAt == placed.startsAt)
    }

    @MainActor @Test func theSameCopyOnAnotherClockIsKeptOnTheHalls() {
        let copies = ReadCopies(persists: false)
        let listed = event(startsAt: Self.ahead.addingTimeInterval(3600))
        let kept = listed.published(in: Fixtures.taipei)
        copies.keep(listed, markedAs: "a")
        copies.keep(kept, markedAs: "a")
        #expect(copies.copy(of: listed.id, markedAs: "a")?.zone == Fixtures.taipei)
        copies.keep(listed, markedAs: "a")
        #expect(copies.copy(of: listed.id, markedAs: "a")?.zone == Fixtures.taipei)
    }

    @MainActor @Test func aCopyAnswersOnlyForTheMarkItWasTakenFor() {
        let copies = ReadCopies(persists: false)
        let one = event()
        copies.keep(one, markedAs: "a")
        #expect(copies.copy(of: one.id, markedAs: "a") == ListingCopy(one))
        #expect(copies.copy(of: one.id, markedAs: "b") == nil)
    }

    @MainActor @Test func deleteAllTurnsEveryDateBackToUnread() {
        let store = store()
        let one = event("1"), two = event("2")
        store.markRead([one, two], read: true)
        store.markRead([event("1", startsAt: Self.ahead.addingTimeInterval(3600))], read: true)
        store.removeAllEvents()
        #expect(store.unread(one) == .new)
        #expect(store.unread(two) == .new)
        #expect(store.changesRead(in: event("1", startsAt: Self.ahead.addingTimeInterval(3600))) == nil)
    }

    @MainActor @Test func deleteAllUnfollowsEveryoneAndUnlinksTheAccount() {
        let store = store()
        let performer = PerformerProfile(id: 1, name: "A", reading: nil, fanCount: nil, slug: "a")
        store.toggleFollow(performer)
        store.link(EventernoteProfile(handle: "someone", name: "Someone", bio: nil, eventCount: nil,
                                      favoritePerformers: [], avatarURL: nil))
        store.removeAllEvents()
        #expect(!store.isFollowing(performer))
        #expect(store.eventernoteHandle == nil)
    }
}
