import CloudKit
import Foundation
import SwiftData
import Testing
@testable import Eventrail

struct LibraryDatabaseTests {
    let earlier = Date.now.addingTimeInterval(-3600)
    let later = Date.now.addingTimeInterval(-60)
    /// A night far enough ahead that pruning never reaches its read.
    let ahead = Date.now.addingTimeInterval(30 * 24 * 60 * 60)

    /// Something in every part of the archive a row can carry, and one night
    /// abroad with every field its page publishes.
    func library() -> LibraryArchive {
        var archive = LibraryArchive()
        for id in ["1", "2"] {
            archive.events[id] = Fixtures.event(id: id, title: "Live \(id)")
            archive.membership[id] = Stamped(true, at: earlier)
        }
        var abroad = Fixtures.event(
            id: "4", venueDetail: "B1", venueAddress: "台北市中正區仁愛路一段17號",
            startsAt: Fixtures.date(2027, 5, 9, 18, in: Fixtures.taipei),
            endsAt: Fixtures.date(2027, 5, 9, 21, in: Fixtures.taipei),
            timeZone: Fixtures.taipei, performers: ["A", "B"], summary: "一行目\n二行目",
            isDetailed: true, detailFormat: 3)
        abroad.relatedLinks = [URL(string: "https://example.com/tickets")!]
        abroad.hashtags = [Hashtag(tag: "#live", searchURL: URL(string: "https://x.com/hashtag/live")!)]
        abroad.editedBy = "someone"
        abroad.editedAt = earlier
        abroad.readAt = later
        archive.events["4"] = abroad
        archive.membership["4"] = Stamped(true, at: later)
        archive.membership["gone"] = Stamped(false, at: later)
        archive.tracking["1"] = Stamped(Tracking(ticket: .purchased, seat: "A12", cost: 9000,
                                                 lotteryEntries: 3, note: "front row"), at: earlier)
        archive.favorites["2"] = Stamped(true, at: earlier)
        let listed = Fixtures.event(id: "3", date: ahead)
        archive.followingReads = ["3": Stamped(FollowingRead(fingerprint: listed.listingFingerprint, day: listed.date), at: earlier)]
        archive.follows = ["10": Stamped(true, at: earlier), "11": Stamped(false, at: later)]
        archive.followedPerformers = ["10": PerformerProfile(id: 10, name: "A", reading: "エー", fanCount: 12, slug: "a")]
        archive.eventernoteAccount = Stamped("reader", at: earlier)
        archive.eventernoteProfile = LinkedProfile(name: "Reader", avatarURL: URL(string: "https://example.com/a.png"))
        archive.recentSearches = Stamped(["A"], at: earlier)
        archive.lastImported = earlier
        archive.lastRefreshed = later
        return LibraryArchive().merging(archive)
    }

    func database() throws -> (LibraryDatabase, ModelContext) {
        let database = LibraryDatabase(at: .memory, syncing: false)
        return (database, database.context)
    }

    func stored(_ archive: LibraryArchive, in context: ModelContext) throws {
        try LibraryDatabase.apply(archive, to: context)
        try context.save()
    }

    @Test func anArchiveComesBackOutAsItWentIn() throws {
        let (database, context) = try database()
        try stored(library(), in: context)
        #expect(try LibraryDatabase.archive(in: context) == library())
        withExtendedLifetime(database) {}
    }

    @Test func eachRecordIsOneRow() throws {
        let (database, context) = try database()
        try stored(library(), in: context)
        #expect(try context.fetchCount(FetchDescriptor<LibraryEvent>()) == 5)
        #expect(try context.fetchCount(FetchDescriptor<FollowedPerformer>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<LibrarySettings>()) == 1)
        withExtendedLifetime(database) {}
    }

    /// Every row written is a record sent to iCloud again.
    @Test func writingTheSameArchiveAgainWritesNothing() throws {
        let (database, context) = try database()
        try stored(library(), in: context)
        #expect(try LibraryDatabase.apply(library(), to: context) == false)
        #expect(!context.hasChanges)
        withExtendedLifetime(database) {}
    }

    @Test func aRecordTheArchiveNoLongerHoldsLosesItsRow() throws {
        let (database, context) = try database()
        try stored(library(), in: context)
        var fewer = library()
        fewer.followingReads = [:]
        try stored(fewer, in: context)
        let ids = try context.fetch(FetchDescriptor<LibraryEvent>()).map(\.eventID).sorted()
        #expect(ids == ["1", "2", "4", "gone"])
        withExtendedLifetime(database) {}
    }

    /// Two devices each moved their own library in, so each wrote a row for
    /// the same event: one answer each survives the fold.
    @Test func twoRowsForOneEventFoldIntoOneAnswerByAnswer() throws {
        let (database, context) = try database()
        let base = Stamped(Tracking(note: "front row"), at: earlier)
        var phone = LibraryArchive()
        phone.tracking["1"] = base.edited(to: Tracking(seat: "A12", note: "front row"), at: later)
        var iPad = LibraryArchive()
        iPad.tracking["1"] = base.edited(to: Tracking(cost: 9000, note: "front row"), at: later)

        let rows = [phone, iPad].map { archive in
            let row = LibraryEvent(eventID: "1")
            context.insert(row)
            row.take(archive)
            return row
        }
        let survivor = rows.map(\.uid).min { $0.uuidString < $1.uuidString }
        try context.save()

        #expect(try LibraryDatabase.deduplicate(in: context))
        let left = try context.fetch(FetchDescriptor<LibraryEvent>())
        #expect(left.map(\.uid) == [survivor])
        #expect(left.first?.tracking?.value.seat == "A12")
        #expect(left.first?.tracking?.value.cost == 9000)
        #expect(left.first?.tracking?.value.note == "front row")
        withExtendedLifetime(database) {}
    }

    @Test func aRemovalOnOneRowOutranksAnOlderYesOnTheOther() throws {
        let (database, context) = try database()
        for membership in [Stamped(true, at: earlier), Stamped(false, at: later)] {
            var archive = LibraryArchive()
            archive.events["1"] = Fixtures.event(id: "1")
            archive.membership["1"] = membership
            let row = LibraryEvent(eventID: "1")
            context.insert(row)
            row.take(archive)
        }
        try context.save()

        try LibraryDatabase.deduplicate(in: context)
        #expect(try LibraryDatabase.archive(in: context).isInLibrary("1") == false)
        withExtendedLifetime(database) {}
    }

    @Test func twoSettingsRowsFoldIntoTheNewerLink() throws {
        let (database, context) = try database()
        for (handle, when) in [("old", earlier), ("new", later)] {
            var archive = LibraryArchive()
            archive.eventernoteAccount = Stamped(handle, at: when)
            let row = LibrarySettings()
            context.insert(row)
            row.take(archive)
        }
        try context.save()

        try LibraryDatabase.deduplicate(in: context)
        let rows = try context.fetch(FetchDescriptor<LibrarySettings>())
        #expect(rows.count == 1)
        #expect(rows.first?.account == "new")
        withExtendedLifetime(database) {}
    }

    @Test func aReadWhoseNightHasGoneLeavesNoRow() throws {
        let (database, context) = try database()
        let past = Date.now.addingTimeInterval(-30 * 24 * 60 * 60)
        var archive = LibraryArchive()
        archive.followingReads = ["7": Stamped(FollowingRead(fingerprint: "x", day: past), at: earlier)]
        let row = LibraryEvent(eventID: "7")
        context.insert(row)
        row.take(archive)
        try context.save()

        #expect(try LibraryDatabase.prune(in: context))
        #expect(try context.fetchCount(FetchDescriptor<LibraryEvent>()) == 0)
        withExtendedLifetime(database) {}
    }

    @Test func aTombstoneKeepsItsRowAndDropsItsFacts() throws {
        let (database, context) = try database()
        var archive = LibraryArchive()
        archive.events["7"] = Fixtures.event(id: "7")
        archive.membership["7"] = Stamped(false, at: later)
        let row = LibraryEvent(eventID: "7")
        context.insert(row)
        row.take(archive)
        try context.save()

        try LibraryDatabase.prune(in: context)
        let left = try context.fetch(FetchDescriptor<LibraryEvent>())
        #expect(left.count == 1)
        #expect(left.first?.membership?.value == false)
        #expect(left.first?.hasFacts == false)
        withExtendedLifetime(database) {}
    }

    // MARK: - An import

    /// What CloudKit does to a row another device sent last: its copy lands
    /// over this one's whole, whenever each was written.
    private func imported(_ archive: LibraryArchive, over id: Event.ID, in context: ModelContext) throws {
        let row = try #require(try context.fetch(FetchDescriptor<LibraryEvent>()).first { $0.eventID == id })
        row.take(try #require(archive.slice(for: .event(id))))
        try context.save()
    }

    private func tracked(_ tracking: Stamped<Tracking>) -> LibraryArchive {
        var archive = LibraryArchive()
        archive.events["1"] = Fixtures.event(id: "1")
        archive.membership["1"] = Stamped(true, at: earlier)
        archive.tracking["1"] = tracking
        return archive
    }

    /// A note typed this morning, then yesterday's offline edit arriving
    /// after it: the morning's stands.
    @Test func anOlderAnswerAnImportLandsOverIsPutBack() throws {
        let (database, context) = try database()
        let base = Stamped(Tracking(note: "draft"), at: earlier.addingTimeInterval(-3600))
        try stored(tracked(base.edited(to: Tracking(note: "this morning"), at: later)), in: context)
        let before = try LibraryDatabase.archive(in: context)

        try imported(tracked(base.edited(to: Tracking(note: "yesterday"), at: earlier)), over: "1", in: context)
        #expect(try LibraryDatabase.reconcile(before, in: context))
        #expect(try LibraryDatabase.archive(in: context).tracking["1"]?.value.note == "this morning")
        withExtendedLifetime(database) {}
    }

    @Test func aNewerAnswerAnImportBringsStands() throws {
        let (database, context) = try database()
        let base = Stamped(Tracking(note: "draft"), at: earlier.addingTimeInterval(-3600))
        try stored(tracked(base.edited(to: Tracking(note: "yesterday"), at: earlier)), in: context)
        let before = try LibraryDatabase.archive(in: context)

        try imported(tracked(base.edited(to: Tracking(note: "this morning"), at: later)), over: "1", in: context)
        #expect(try LibraryDatabase.reconcile(before, in: context) == false)
        #expect(!context.hasChanges)
        #expect(try LibraryDatabase.archive(in: context).tracking["1"]?.value.note == "this morning")
        withExtendedLifetime(database) {}
    }

    /// The seat written here and the cost written there are different
    /// answers, so both are kept though the import carried only the cost.
    @Test func anImportIsSettledAnswerByAnswer() throws {
        let (database, context) = try database()
        let base = Stamped(Tracking(note: "front row"), at: earlier)
        try stored(tracked(base.edited(to: Tracking(seat: "A12", note: "front row"), at: later)), in: context)
        let before = try LibraryDatabase.archive(in: context)

        try imported(tracked(base.edited(to: Tracking(cost: 9000, note: "front row"), at: later)), over: "1", in: context)
        #expect(try LibraryDatabase.reconcile(before, in: context))
        let tracking = try LibraryDatabase.archive(in: context).tracking["1"]?.value
        #expect(tracking?.seat == "A12")
        #expect(tracking?.cost == 9000)
        withExtendedLifetime(database) {}
    }

    @Test func aRemovalAnOlderYesLandsOverStaysRemoved() throws {
        let (database, context) = try database()
        var removed = tracked(Stamped(Tracking(), at: earlier))
        removed.membership["1"] = Stamped(false, at: later)
        try stored(removed, in: context)
        let before = try LibraryDatabase.archive(in: context)

        var kept = removed
        kept.events["1"] = Fixtures.event(id: "1")
        kept.membership["1"] = Stamped(true, at: earlier)
        try imported(kept, over: "1", in: context)
        #expect(try LibraryDatabase.reconcile(before, in: context))
        #expect(try LibraryDatabase.archive(in: context).isInLibrary("1") == false)
        withExtendedLifetime(database) {}
    }

    /// Another device pruned or folded it by the same rules; putting it back
    /// would only send it round again.
    @Test func aRowAnImportDeletedStaysDeleted() throws {
        let (database, context) = try database()
        try stored(library(), in: context)
        let before = try LibraryDatabase.archive(in: context)
        let row = try #require(try context.fetch(FetchDescriptor<LibraryEvent>()).first { $0.eventID == "2" })
        context.delete(row)
        try context.save()

        #expect(try LibraryDatabase.reconcile(before, in: context) == false)
        #expect(try context.fetch(FetchDescriptor<LibraryEvent>()).contains { $0.eventID == "2" } == false)
        withExtendedLifetime(database) {}
    }

    // MARK: - How sync stands

    @Test func deletingTheZoneFromICloudIsItsOwnStatus() {
        #expect(LibraryDatabase.status(for: CKError(.userDeletedZone)) == .cloudDataDeleted)
    }

    /// The deletion usually arrives as one record's answer inside a partial
    /// failure rather than as the whole error.
    @Test func aDeletedZoneInsideAPartialFailureIsFound() {
        let zone = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone")
        let error = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [zone: CKError(.userDeletedZone)]])
        #expect(LibraryDatabase.status(for: error) == .cloudDataDeleted)
    }

    @Test func otherErrorsKeepTheirStatus() {
        #expect(LibraryDatabase.status(for: CKError(.quotaExceeded)) == .iCloudFull)
        #expect(LibraryDatabase.status(for: CKError(.networkUnavailable)) == .offline)
        #expect(LibraryDatabase.status(for: CKError(.notAuthenticated)) == .signedOut)
    }

    // MARK: - The library file

    private func file() throws -> LibraryFile {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LibraryDatabaseTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var file = LibraryFile()
        file.url = directory.appending(path: "library.json")
        return file
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test func theLibraryFileMovesInOnceAndIsSetAside() throws {
        let file = try file()
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        file.save(library())
        let (database, context) = try database()

        database.moveIn(from: file)
        #expect(try LibraryDatabase.archive(in: context) == library())
        #expect(!exists(file.url))
        #expect(exists(file.retiredURL))

        let again = database.moveIn(from: file)
        #expect(again?.archive.holdsNothing == true)
        #expect(try LibraryDatabase.archive(in: context) == library())
    }

    /// A store that already holds a newer answer — synced in from another
    /// device — keeps it.
    @Test func movingInMergesWithWhatTheStoreHolds() throws {
        let file = try file()
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        file.save(library())
        let (database, context) = try database()
        var removed = LibraryArchive()
        removed.membership["1"] = Stamped(false, at: .now)
        try stored(removed, in: context)

        database.moveIn(from: file)
        let archive = try LibraryDatabase.archive(in: context)
        #expect(!archive.isInLibrary("1"))
        #expect(archive.isInLibrary("2"))
    }
}
