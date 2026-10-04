import CloudKit
import Foundation
import SwiftData
import Testing
@testable import Eventrail

struct LibraryDatabaseTests {
    let earlier = Date.now.addingTimeInterval(-3600)
    let later = Date.now.addingTimeInterval(-60)
    /// An event far enough ahead that pruning never reaches its read.
    let ahead = Date.now.addingTimeInterval(30 * 24 * 60 * 60)

    /// Something in every part of the archive the store keeps, and one event
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
        archive.tracking["4"] = Stamped(Tracking(ticket: .purchased, cost: Decimal(string: "1280.5"),
                                                 currency: "TWD"), at: later)
        archive.membership["gone"] = Stamped(false, at: later)
        archive.tracking["1"] = Stamped(Tracking(ticket: .purchased, seat: "A12", seatClass: "S席", cost: 9000,
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

    /// What an archive says, leaving out when: an entry keeps one date for
    /// its three answers, so the dates do not come back as they went in.
    struct Answers: Equatable {
        var events: [Event.ID: Event]
        var library: Set<Event.ID>
        var favorites: Set<Event.ID>
        var tracking: [Event.ID: Tracking]
        var reads: [Event.ID: FollowingRead]
        var follows: [String: Bool]
        var performers: [String: PerformerProfile]
        var account: String?
        var profile: LinkedProfile?
        var searches: [String]

        init(_ archive: LibraryArchive) {
            events = archive.events
            library = Set(archive.membership.filter(\.value.value).keys)
            favorites = Set(archive.favorites.filter(\.value.value).keys)
            tracking = archive.tracking.compactMapValues { record in
                var tracking = record.value
                tracking.edits = [:]
                return tracking.isEmpty ? nil : tracking
            }
            reads = (archive.followingReads ?? [:]).mapValues(\.value)
            follows = (archive.follows ?? [:]).mapValues(\.value)
            performers = archive.followedPerformers ?? [:]
            account = archive.eventernoteAccount?.value ?? nil
            profile = archive.eventernoteProfile
            searches = archive.recentSearches.value
        }
    }

    func database() throws -> (LibraryDatabase, ModelContext) {
        let database = LibraryDatabase(at: .memory, syncing: false)
        return (database, database.context)
    }

    func stored(_ archive: LibraryArchive, in context: ModelContext) throws {
        try LibraryDatabase.apply(archive, to: context)
        try context.save()
    }

    func entries(_ id: Event.ID, in context: ModelContext) throws -> [LibraryEntry] {
        try context.fetch(FetchDescriptor<LibraryEntry>(predicate: #Predicate { $0.eventID == id }))
    }

    // MARK: - Rows and the archive

    @Test func anArchiveComesBackOutSayingWhatItSaid() throws {
        let (database, context) = try database()
        try stored(library(), in: context)
        #expect(Answers(try LibraryDatabase.archive(in: context)) == Answers(library()))
        withExtendedLifetime(database) {}
    }

    /// What the reader said about an event is one record, and what Eventernote
    /// says about it another. An event the archive only says is out — "gone" —
    /// needs no entry to say so.
    @Test func eachEventIsOneEntryAndOneRowOfFacts() throws {
        let (database, context) = try database()
        try stored(library(), in: context)
        #expect(try context.fetchCount(FetchDescriptor<LibraryEntry>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<LibraryEvent>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<FollowingReadMark>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<FollowedPerformer>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<LibrarySettings>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<LibraryMembership>()) == 0)
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

    /// A restore adds: a row the archive says nothing about is left alone.
    @Test func applyingLessDeletesNothing() throws {
        let (database, context) = try database()
        try stored(library(), in: context)
        var fewer = library()
        fewer.followingReads = [:]
        fewer.membership["2"] = nil
        try stored(fewer, in: context)
        #expect(try context.fetchCount(FetchDescriptor<FollowingReadMark>()) == 1)
        #expect(try LibraryDatabase.archive(in: context).isInLibrary("2"))
        withExtendedLifetime(database) {}
    }

    /// An entry written from an archive takes the newest of its dates, so a
    /// restore raised as of now outranks every device's older copy.
    @Test func anEntryTakesTheNewestOfItsDates() throws {
        let (database, context) = try database()
        var archive = LibraryArchive()
        archive.membership["1"] = Stamped(true, at: earlier)
        archive.tracking["1"] = Stamped(Tracking(note: "front row"), at: later)
        try stored(archive, in: context)
        #expect(try entries("1", in: context).map(\.modified) == [later.toTheMillisecond])
        withExtendedLifetime(database) {}
    }

    /// An archive giving an answer the entry already holds, but later — an
    /// older build's file, its zone, a restore — dates the entry then. Left at
    /// the entry's older date, a second entry written in between by a device
    /// that had not heard outranked it in the fold.
    @Test func anAnswerGivenAgainLaterIsDatedThen() throws {
        let (database, context) = try database()
        let between = earlier.addingTimeInterval(30 * 60)
        entry("1", LibraryEntry.Answers(inLibrary: true), dated: [.inLibrary: earlier], in: context)
        try context.save()

        var older = LibraryArchive()
        older.membership["1"] = Stamped(true, at: earlier.addingTimeInterval(-60))
        #expect(try LibraryDatabase.apply(older, to: context) == false)

        var again = LibraryArchive()
        again.membership["1"] = Stamped(true, at: later)
        #expect(try LibraryDatabase.apply(again, to: context))
        try context.save()
        let held = try #require(try entries("1", in: context).first)
        #expect(held.changed(.inLibrary) == later.toTheMillisecond)
        #expect(held.modified == later.toTheMillisecond)

        entry("1", LibraryEntry.Answers(inLibrary: false), dated: [.inLibrary: between], in: context)
        try context.save()
        try LibraryDatabase.deduplicate(in: context)
        #expect(try entries("1", in: context).map(\.inLibrary) == [true])
        withExtendedLifetime(database) {}
    }

    // MARK: - Two rows for one thing

    /// Two devices each wrote an entry for the same event before hearing of
    /// the other's, on a build that dated only the whole entry: the one
    /// written last is the reader's answer, as it always was.
    @Test func twoEntriesForOneEventKeepTheOneWrittenLast() throws {
        let (database, context) = try database()
        for (inLibrary, when) in [(true, earlier), (false, later)] {
            let entry = LibraryEntry(eventID: "1")
            context.insert(entry)
            entry.inLibrary = inLibrary
            entry.modified = when
        }
        try context.save()

        #expect(try LibraryDatabase.deduplicate(in: context))
        #expect(try entries("1", in: context).map(\.inLibrary) == [false])
        withExtendedLifetime(database) {}
    }

    /// Written in the same instant, every device keeps the same one, so none
    /// deletes the entry another kept.
    @Test func twoEntriesWrittenAtOnceKeepTheLowerUID() throws {
        let (database, context) = try database()
        let made = (0 ..< 2).map { _ in
            let entry = LibraryEntry(eventID: "1")
            context.insert(entry)
            entry.modified = later
            return entry.uid
        }
        try context.save()

        try LibraryDatabase.deduplicate(in: context)
        #expect(try entries("1", in: context).map(\.uid) == [made.min { $0.uuidString < $1.uuidString }])
        withExtendedLifetime(database) {}
    }

    /// An entry giving the parts `dates` names, as this build writes one.
    @discardableResult
    func entry(_ id: Event.ID, _ answers: LibraryEntry.Answers, dated dates: [LibraryEntry.Part: Date],
               in context: ModelContext) -> LibraryEntry {
        let entry = LibraryEntry(eventID: id)
        context.insert(entry)
        entry.give(answers, dated: dates)
        entry.modified = (dates.values.max() ?? .distantPast).toTheMillisecond
        return entry
    }

    /// Everything the reader wrote on an event.
    let written = LibraryEntry.Answers(
        inLibrary: true, isFavorite: true,
        tracking: Tracking(ticket: .purchased, seat: "A12", cost: 9000, note: "front row"))

    /// A device set up afresh imports the linked account before iCloud has
    /// brought it the entry holding the reader's note: its own entry says
    /// only "in the library", and is the newer. Kept whole, it deleted the
    /// note, the ticket and the heart on every device.
    @Test func anImportAheadOfTheEntryWithTheNoteKeepsTheNote() throws {
        let (database, context) = try database()
        // Written by the build before parts were dated.
        let held = LibraryEntry(eventID: "1")
        context.insert(held)
        held.give(written, dated: [:])
        held.modified = earlier.toTheMillisecond
        entry("1", LibraryEntry.Answers(inLibrary: true), dated: [.inLibrary: later], in: context)
        try context.save()

        #expect(try LibraryDatabase.deduplicate(in: context))
        let kept = try entries("1", in: context)
        #expect(kept.map(\.answers) == [written])
        withExtendedLifetime(database) {}
    }

    @Test func anImportAheadOfADatedEntryKeepsItsAnswersToo() throws {
        let (database, context) = try database()
        entry("1", written, dated: [.inLibrary: earlier, .favorite: earlier, .tracking: earlier], in: context)
        entry("1", LibraryEntry.Answers(inLibrary: true), dated: [.inLibrary: later], in: context)
        try context.save()

        try LibraryDatabase.deduplicate(in: context)
        let kept = try #require(try entries("1", in: context).first)
        #expect(kept.answers == written)
        #expect(kept.changed(.inLibrary) == later.toTheMillisecond)
        #expect(kept.changed(.tracking) == earlier.toTheMillisecond)
        withExtendedLifetime(database) {}
    }

    /// Two devices answering different parts of one event on entries of their
    /// own: both answers stand.
    @Test func aRemovalOnOneEntryAndANoteOnAnotherBothStand() throws {
        let (database, context) = try database()
        entry("1", LibraryEntry.Answers(inLibrary: false), dated: [.inLibrary: later], in: context)
        entry("1", LibraryEntry.Answers(inLibrary: true, tracking: Tracking(note: "front row")),
              dated: [.inLibrary: earlier, .tracking: earlier], in: context)
        try context.save()

        try LibraryDatabase.deduplicate(in: context)
        let kept = try #require(try entries("1", in: context).first)
        #expect(!kept.inLibrary)
        #expect(kept.tracking.note == "front row")
        withExtendedLifetime(database) {}
    }

    /// A cost an older build wrote is whole yen in the old column. It reads
    /// back as yen, and the next write moves it into the two new columns
    /// rather than leaving it to be read back over an emptied cost.
    @Test func aCostInTheOldColumnIsYenAndMovesOnTheNextWrite() throws {
        let (database, context) = try database()
        let entry = LibraryEntry(eventID: "1")
        context.insert(entry)
        entry.cost = 9900
        #expect(entry.tracking.price == Money(amount: 9900, currency: "JPY"))

        entry.tracking = entry.tracking
        #expect(entry.cost == nil)
        #expect(entry.costHundredths == 990_000)
        #expect(entry.tracking.price == Money(amount: 9900, currency: "JPY"))

        var emptied = entry.tracking
        emptied.cost = nil
        entry.tracking = emptied
        #expect(entry.tracking.price == nil)
        withExtendedLifetime(database) {}
    }

    @Test func aHeartOnOneEntryAndACostOnAnotherBothStand() throws {
        let (database, context) = try database()
        entry("1", LibraryEntry.Answers(isFavorite: true), dated: [.favorite: earlier], in: context)
        entry("1", LibraryEntry.Answers(tracking: Tracking(cost: 9000)), dated: [.tracking: later], in: context)
        try context.save()

        try LibraryDatabase.deduplicate(in: context)
        let kept = try #require(try entries("1", in: context).first)
        #expect(kept.isFavorite)
        #expect(kept.tracking.cost == 9000)
        withExtendedLifetime(database) {}
    }

    /// The tracking record is one part: a ticket on one entry and a seat on
    /// another are two copies of it, and the later copy stands.
    @Test func twoTrackingRecordsKeepTheLaterOne() throws {
        let (database, context) = try database()
        entry("1", LibraryEntry.Answers(tracking: Tracking(ticket: .purchased)), dated: [.tracking: earlier], in: context)
        entry("1", LibraryEntry.Answers(tracking: Tracking(seat: "A12")), dated: [.tracking: later], in: context)
        try context.save()

        try LibraryDatabase.deduplicate(in: context)
        #expect(try entries("1", in: context).map(\.tracking) == [Tracking(seat: "A12")])
        withExtendedLifetime(database) {}
    }

    /// Delete All dates every part, so an older answer on an entry it never
    /// saw goes too — and one given after it stays.
    @Test func deleteAllOutranksOlderAnswersOnAnotherEntry() throws {
        let (database, context) = try database()
        // Between ``earlier`` and ``later``.
        let emptied = Date.now.addingTimeInterval(-120)
        entry("1", LibraryEntry.Answers(), dated: [.inLibrary: emptied, .favorite: emptied, .tracking: emptied],
              in: context)
        entry("1", written, dated: [.inLibrary: earlier, .favorite: earlier, .tracking: earlier], in: context)
        entry("2", LibraryEntry.Answers(), dated: [.inLibrary: emptied, .favorite: emptied, .tracking: emptied],
              in: context)
        entry("2", LibraryEntry.Answers(tracking: Tracking(note: "after")), dated: [.tracking: later], in: context)
        try context.save()

        try LibraryDatabase.deduplicate(in: context)
        #expect(try entries("1", in: context).map(\.answers) == [LibraryEntry.Answers()])
        #expect(try entries("2", in: context).map(\.tracking.note) == ["after"])
        withExtendedLifetime(database) {}
    }

    /// An entry an older build wrote keeps its date for the parts left alone
    /// once another part is given.
    @Test func anUndatedEntryKeepsItsDateForThePartsLeftAlone() throws {
        let (database, context) = try database()
        let held = LibraryEntry(eventID: "1")
        context.insert(held)
        held.give(LibraryEntry.Answers(inLibrary: true, tracking: Tracking(note: "front row")), dated: [:])
        held.modified = earlier.toTheMillisecond
        #expect(held.changed(.favorite) == earlier.toTheMillisecond)

        var hearted = held.answers
        hearted.isFavorite = true
        held.give(hearted, dated: [.favorite: later])
        #expect(held.changed(.favorite) == later.toTheMillisecond)
        #expect(held.changed(.tracking) == earlier.toTheMillisecond)
        #expect(held.changed(.inLibrary) == earlier.toTheMillisecond)
        withExtendedLifetime(database) {}
    }

    /// Each record an archive holds dates its own part, and a part it holds
    /// nothing for was never given.
    @Test func anArchiveDatesEachPartOfAnEntry() throws {
        let (database, context) = try database()
        var archive = LibraryArchive()
        archive.membership["1"] = Stamped(true, at: earlier)
        archive.tracking["1"] = Stamped(Tracking(note: "front row"), at: later)
        try stored(archive, in: context)
        let entry = try #require(try entries("1", in: context).first)
        #expect(entry.changed(.inLibrary) == earlier.toTheMillisecond)
        #expect(entry.changed(.tracking) == later.toTheMillisecond)
        #expect(entry.changed(.favorite) == .distantPast)

        let out = try LibraryDatabase.archive(in: context)
        #expect(out.membership["1"]?.modified == earlier.toTheMillisecond)
        #expect(out.tracking["1"]?.modified == later.toTheMillisecond)
        withExtendedLifetime(database) {}
    }

    @Test func twoRowsOfFactsKeepTheLaterReadOfThePage() throws {
        let (database, context) = try database()
        for (title, read) in [("Moved to the big hall", later), ("Live", earlier)] {
            var event = Fixtures.event(id: "1", title: title, isDetailed: true)
            event.readAt = read
            let row = LibraryEvent(eventID: "1")
            context.insert(row)
            row.write(event)
        }
        try context.save()

        try LibraryDatabase.deduplicate(in: context)
        let rows = try context.fetch(FetchDescriptor<LibraryEvent>())
        #expect(rows.map(\.facts?.title) == ["Moved to the big hall"])
        withExtendedLifetime(database) {}
    }

    /// A device writes its settings row the first time the reader searches,
    /// whether or not the other device's has reached it: neither the link nor
    /// the searches may be lost to the fold.
    @Test func twoSettingsRowsKeepWhatEachWroteLast() throws {
        let (database, context) = try database()
        let linked = LibrarySettings()
        context.insert(linked)
        linked.eventernoteAccount = Stamped("reader", at: earlier)
        linked.eventernoteProfile = LinkedProfile(name: "Reader")
        let searched = LibrarySettings()
        context.insert(searched)
        searched.searches = Stamped(["MyGO"], at: later)
        try context.save()

        #expect(try LibraryDatabase.deduplicate(in: context))
        let rows = try context.fetch(FetchDescriptor<LibrarySettings>())
        #expect(rows.count == 1)
        #expect(rows.first?.account == "reader")
        #expect(rows.first?.eventernoteProfile?.name == "Reader")
        #expect(rows.first?.recentSearches == ["MyGO"])
        withExtendedLifetime(database) {}
    }

    @Test func aReadWhoseEventHasGoneIsDeleted() throws {
        let (database, context) = try database()
        let past = Date.now.addingTimeInterval(-30 * 24 * 60 * 60)
        for (id, day) in [("gone", past), ("ahead", ahead)] {
            let mark = FollowingReadMark(eventID: id)
            context.insert(mark)
            mark.read = Stamped(FollowingRead(fingerprint: "x", day: day), at: earlier)
        }
        try context.save()

        #expect(try LibraryDatabase.pruneReads(in: context))
        #expect(try context.fetch(FetchDescriptor<FollowingReadMark>()).map(\.eventID) == ["ahead"])
        withExtendedLifetime(database) {}
    }

    // MARK: - What older builds kept

    /// A row as the builds before entries left it: the heart and the tracking
    /// record on the event's own row.
    private func legacyRow(_ id: Event.ID, in context: ModelContext) -> LibraryEvent {
        let row = LibraryEvent(eventID: id)
        context.insert(row)
        row.write(Fixtures.event(id: id))
        row.isFavorite = true
        row.favoriteChanged = earlier
        row.note = "front row"
        row.trackingChanged = earlier
        return row
    }

    @Test func whatAnOlderBuildKeptBecomesAnEntry() throws {
        let (database, context) = try database()
        let row = legacyRow("1", in: context)
        // On the row as the first builds kept it, and newer in its own record.
        row.inLibrary = true
        row.inLibraryChanged = earlier
        let membership = LibraryMembership(eventID: "1")
        context.insert(membership)
        membership.inLibrary = false
        membership.changed = later
        try context.save()

        #expect(try LibraryDatabase.adoptLegacyRecords(in: context))
        let entry = try #require(try entries("1", in: context).first)
        #expect(entry.inLibrary == false)
        #expect(entry.isFavorite)
        #expect(entry.tracking.note == "front row")
        #expect(entry.modified == later.toTheMillisecond)
        #expect(entry.kept?.title == "Live")
        withExtendedLifetime(database) {}
    }

    /// A device reinstalled, or newly set up, opens its store empty and only
    /// then hears from iCloud what an older build left there. Taken in once
    /// per device, on that first empty open, it was never taken in at all.
    @Test func whatAnOlderBuildLeftIsTakenInWhenItLandsLater() throws {
        let (database, context) = try database()
        let row = legacyRow("1", in: context)
        row.inLibrary = true
        row.inLibraryChanged = earlier
        let membership = LibraryMembership(eventID: "2")
        context.insert(membership)
        membership.inLibrary = true
        membership.changed = earlier
        try context.save()

        // What every import from iCloud is followed by.
        try LibraryDatabase.settle(in: context)
        let entry = try #require(try entries("1", in: context).first)
        #expect(entry.inLibrary)
        #expect(entry.tracking.note == "front row")
        #expect(try entries("2", in: context).map(\.inLibrary) == [true])

        // And the next import finds nothing more to do.
        #expect(try LibraryDatabase.adoptLegacyRecords(in: context) == false)
        withExtendedLifetime(database) {}
    }

    /// An entry already there is the reader's answer, whatever an older build
    /// left beside it.
    @Test func anEntryAlreadyThereIsLeftAlone() throws {
        let (database, context) = try database()
        _ = legacyRow("1", in: context)
        let entry = LibraryEntry(eventID: "1")
        context.insert(entry)
        entry.inLibrary = true
        entry.modified = earlier
        try context.save()

        #expect(try LibraryDatabase.adoptLegacyRecords(in: context) == false)
        #expect(try entries("1", in: context).map(\.isFavorite) == [false])
        withExtendedLifetime(database) {}
    }

    @Test func aReadAnOlderBuildKeptOnTheRowBecomesAMark() throws {
        let (database, context) = try database()
        let row = LibraryEvent(eventID: "3")
        context.insert(row)
        row.readFingerprint = "x"
        row.readDay = ahead
        row.readChanged = earlier
        try context.save()

        #expect(try LibraryDatabase.adoptLegacyRecords(in: context))
        let marks = try context.fetch(FetchDescriptor<FollowingReadMark>())
        #expect(marks.map(\.read?.value.fingerprint) == ["x"])
        withExtendedLifetime(database) {}
    }

    /// The builds before entries dropped the facts of an event nothing kept by
    /// clearing a flag, and left the columns: an event taken out there and
    /// kept again here still has something to show.
    @Test func factsAnOlderBuildDroppedAreReadBack() throws {
        let (database, context) = try database()
        let row = LibraryEvent(eventID: "1")
        context.insert(row)
        row.write(Fixtures.event(id: "1", title: "Live"))
        row.hasFacts = false
        #expect(row.facts?.title == "Live")
        #expect(LibraryEvent(eventID: "2").facts == nil)
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

    typealias Outcomes = LibraryDatabase.SyncOutcomes

    /// An export that succeeds says nothing about the import that failed.
    @Test func anImportThatFailedStaysSaidPastAnExport() {
        var outcomes = Outcomes()
        outcomes.record(.import, failure: .failed("refused"))
        outcomes.record(.export, failure: nil)
        #expect(outcomes.status == .failed("refused"))
        outcomes.record(.import, failure: nil)
        #expect(outcomes.status == .synced)
    }

    /// The other device's writes keep arriving while this one's are refused:
    /// iCloud Full stays said until an export gets through.
    @Test func iCloudFullStaysSaidPastAnImport() {
        var outcomes = Outcomes()
        outcomes.record(.export, failure: .iCloudFull)
        outcomes.record(.import, failure: nil)
        #expect(outcomes.status == .iCloudFull)
        outcomes.record(.export, failure: nil)
        #expect(outcomes.status == .synced)
    }

    /// Offline is over once anything gets through.
    @Test func beingOfflineEndsWithAnySuccess() {
        var outcomes = Outcomes()
        outcomes.record(.import, failure: .offline)
        #expect(outcomes.status == .offline)
        outcomes.record(.export, failure: nil)
        #expect(outcomes.status == .synced)
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
        #expect(Answers(try LibraryDatabase.archive(in: context)) == Answers(library()))
        #expect(!exists(file.url))
        #expect(exists(file.retiredURL))

        let again = database.moveIn(from: file)
        #expect(again?.archive.holdsNothing == true)
        #expect(Answers(try LibraryDatabase.archive(in: context)) == Answers(library()))
    }

    /// A store that already holds a newer answer — synced in from another
    /// device — keeps it.
    @Test func movingInMergesWithWhatTheStoreHolds() throws {
        let file = try file()
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        file.save(library())
        let (database, context) = try database()
        var kept = LibraryArchive()
        kept.membership["1"] = Stamped(true, at: earlier)
        try stored(kept, in: context)
        let entry = try #require(try entries("1", in: context).first)
        let now = Date.now
        entry.give(LibraryEntry.Answers(inLibrary: false), dated: [.inLibrary: now])
        entry.modified = now.toTheMillisecond
        try context.save()

        database.moveIn(from: file)
        let archive = try LibraryDatabase.archive(in: context)
        #expect(!archive.isInLibrary("1"))
        #expect(archive.isInLibrary("2"))
    }
}
