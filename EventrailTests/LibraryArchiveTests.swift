import Foundation
import Testing
@testable import Eventrail

struct LibraryArchiveTests {
    /// Recent enough that nothing here is pruned as a settled tombstone.
    let earlier = Date.now.addingTimeInterval(-3600)
    let later = Date.now.addingTimeInterval(-60)

    func archive(with events: [Event], at date: Date) -> LibraryArchive {
        var archive = LibraryArchive()
        for event in events {
            archive.events[event.id] = event
            archive.membership[event.id] = Stamped(true, at: date)
        }
        return archive
    }

    // MARK: - Merging another device

    @Test func aNewerRemovalTravels() {
        let event = Fixtures.event(id: "1")
        let phone = archive(with: [event], at: earlier)
        var iPad = phone
        iPad.membership["1"] = Stamped(false, at: later)

        let merged = phone.merging(iPad)
        #expect(!merged.isInLibrary("1"))
        #expect(merged.libraryEvents.isEmpty)
        // The tombstone is kept so the next merge cannot bring it back.
        #expect(merged.membership["1"]?.value == false)
        #expect(iPad.merging(phone).membership == merged.membership)
    }

    @Test func anOlderRemovalLosesToALaterAdd() {
        var phone = archive(with: [Fixtures.event(id: "1")], at: later)
        phone.membership["1"] = Stamped(true, at: later)
        var iPad = LibraryArchive()
        iPad.membership["1"] = Stamped(false, at: earlier)
        #expect(phone.merging(iPad).isInLibrary("1"))
    }

    @Test func eventsFromBothSidesArrive() {
        let merged = archive(with: [Fixtures.event(id: "1")], at: earlier)
            .merging(archive(with: [Fixtures.event(id: "2")], at: later))
        #expect(Set(merged.libraryEvents.map(\.id)) == ["1", "2"])
    }

    @Test func theMoreDetailedImportWins() {
        let row = Fixtures.event(id: "1", title: "Row")
        let page = Fixtures.event(id: "1", title: "Page", venueAddress: "東京都千代田区", isDetailed: true)
        let mine = archive(with: [row], at: earlier)
        let theirs = archive(with: [page], at: earlier)

        #expect(mine.merging(theirs).events["1"]?.venueAddress == "東京都千代田区")
        #expect(theirs.merging(mine).events["1"]?.venueAddress == "東京都千代田区")
    }

    /// The iPad has just read a start time the phone's older copy predates.
    /// Whichever side runs the merge, the later read's time stands.
    @Test func theLaterReadOfAPageWinsEitherWay() {
        var phone = Fixtures.event(id: "1", startsAt: Fixtures.date(2027, 5, 9, 18, 0),
                                   summary: "S席 9,000円", isDetailed: true, detailFormat: 1)
        phone.readAt = earlier
        var iPad = Fixtures.event(id: "1", startsAt: Fixtures.date(2027, 5, 9, 18, 30),
                                  isDetailed: true, detailFormat: 1)
        iPad.readAt = later

        let onPhone = archive(with: [phone], at: earlier).merging(archive(with: [iPad], at: earlier))
        let onIPad = archive(with: [iPad], at: earlier).merging(archive(with: [phone], at: earlier))
        for merged in [onPhone, onIPad] {
            let event = merged.events["1"]
            #expect(event?.startsAt == Fixtures.date(2027, 5, 9, 18, 30))
            #expect(event?.readAt == later)
            // The later read found no 概要 on the page: it was taken off.
            #expect(event?.summary == nil)
        }
    }

    /// A later read by an older build did not look for what the newer one read,
    /// so what it left empty is filled from the earlier copy rather than cleared.
    @Test func aLaterReadOfFewerFieldsOnlyFillsGaps() {
        var phone = Fixtures.event(id: "1", startsAt: Fixtures.date(2027, 5, 9, 18, 0),
                                   summary: "S席 9,000円", isDetailed: true, detailFormat: 1)
        phone.readAt = earlier
        var iPad = Fixtures.event(id: "1", startsAt: Fixtures.date(2027, 5, 9, 18, 30), isDetailed: true)
        iPad.readAt = later

        for merged in [archive(with: [phone], at: earlier).merging(archive(with: [iPad], at: earlier)),
                       archive(with: [iPad], at: earlier).merging(archive(with: [phone], at: earlier))] {
            #expect(merged.events["1"]?.startsAt == Fixtures.date(2027, 5, 9, 18, 30))
            #expect(merged.events["1"]?.summary == "S席 9,000円")
        }
    }

    @Test func anUndatedCopyCountsAsTheEarlierRead() {
        let old = Fixtures.event(id: "1", startsAt: Fixtures.date(2027, 5, 9, 18, 0), isDetailed: true)
        var fresh = Fixtures.event(id: "1", startsAt: Fixtures.date(2027, 5, 9, 18, 30), isDetailed: true)
        fresh.readAt = later

        let merged = archive(with: [fresh], at: earlier).merging(archive(with: [old], at: earlier))
        #expect(merged.events["1"]?.startsAt == Fixtures.date(2027, 5, 9, 18, 30))
    }

    @Test func notesTypedOnEachDeviceBothSurvive() {
        let base = Stamped(Tracking(cost: 1000, note: "a"), at: earlier)
        var phone = archive(with: [Fixtures.event(id: "1")], at: earlier)
        var iPad = phone
        phone.tracking["1"] = base.edited(to: Tracking(cost: 1000, note: "phone"), at: later)
        iPad.tracking["1"] = base.edited(to: Tracking(cost: 3000, note: "a"),
                                         at: later.addingTimeInterval(1))

        let merged = phone.merging(iPad).tracking["1"]?.value
        #expect(merged?.note == "phone")
        #expect(merged?.cost == 3000)
    }

    @Test func theProfileFollowsTheWinningLink() {
        var phone = LibraryArchive()
        phone.eventernoteAccount = Stamped("old", at: earlier)
        phone.eventernoteProfile = LinkedProfile(name: "Old", avatarURL: nil)
        var iPad = LibraryArchive()
        iPad.eventernoteAccount = Stamped("new", at: later)
        iPad.eventernoteProfile = LinkedProfile(name: "New", avatarURL: nil)

        let merged = phone.merging(iPad)
        #expect(merged.eventernoteAccount?.value == "new")
        #expect(merged.eventernoteProfile?.name == "New")
    }

    // MARK: - Pruning

    @Test func pruningDropsSettledTombstonesAndOrphanedEvents() {
        let longAgo = Date.now.addingTimeInterval(-200 * 24 * 60 * 60)
        var archive = self.archive(with: [Fixtures.event(id: "kept")], at: earlier)
        archive.events["gone"] = Fixtures.event(id: "gone")
        archive.membership["gone"] = Stamped(false, at: longAgo)
        archive.events["favorite"] = Fixtures.event(id: "favorite")
        archive.favorites["favorite"] = Stamped(true, at: earlier)

        let pruned = archive.pruned()
        #expect(pruned.membership["gone"] == nil)
        #expect(pruned.events["gone"] == nil)
        #expect(pruned.events["kept"] != nil)
        // Not in the library, but favorited: still worth keeping.
        #expect(pruned.events["favorite"] != nil)
    }

    @Test func aNoteOutlivesItsEventLeavingTheLibrary() {
        var archive = self.archive(with: [Fixtures.event(id: "1")], at: earlier)
        archive.tracking["1"] = Stamped(Tracking(note: "keep me"), at: .distantPast)
        archive.tracking["2"] = Stamped(Tracking(), at: .distantPast)
        archive.membership["1"] = Stamped(false, at: later)

        let pruned = archive.pruned()
        #expect(pruned.tracking["1"]?.value.note == "keep me")
        #expect(pruned.tracking["2"] == nil)
    }

    // MARK: - Restoring a backup

    @Test func aRestoreOverrulesARemoval() {
        let backup = archive(with: [Fixtures.event(id: "1")], at: earlier)
        var device = LibraryArchive()
        device.membership["1"] = Stamped(false, at: later)

        // A plain merge answers with the newer removal…
        #expect(!device.merging(backup).isInLibrary("1"))
        // …and asking for the backup back is newer still.
        #expect(device.restoring(backup).isInLibrary("1"))
    }

    @Test func aRestoreNeverErases() {
        let device = archive(with: [Fixtures.event(id: "mine")], at: later)
        let backup = archive(with: [Fixtures.event(id: "theirs")], at: earlier)

        let restored = device.restoring(backup)
        #expect(restored.isInLibrary("mine"))
        #expect(restored.isInLibrary("theirs"))
    }

    @Test func aRestoreKeepsTheLaterNote() {
        var device = archive(with: [Fixtures.event(id: "1")], at: later)
        device.tracking["1"] = Stamped(Tracking(note: "newer"), at: later)
        var backup = archive(with: [Fixtures.event(id: "1")], at: earlier)
        backup.tracking["1"] = Stamped(Tracking(note: "older"), at: earlier)

        #expect(device.restoring(backup).tracking["1"]?.value.note == "newer")
    }

    @Test func aRestoreBringsBackANoteDeleteAllCleared() {
        var device = LibraryArchive()
        device.tracking["1"] = Stamped(Tracking(), at: later)
        var backup = archive(with: [Fixtures.event(id: "1")], at: earlier)
        backup.tracking["1"] = Stamped(Tracking(note: "restored"), at: earlier)

        #expect(device.restoring(backup).tracking["1"]?.value.note == "restored")
    }

    @Test func aRestoreRefollowsAnUnfollowedPerformer() {
        let profile = PerformerProfile(id: 10, name: "A", reading: nil, fanCount: nil, slug: "a")
        var device = LibraryArchive()
        device.follows = ["10": Stamped(false, at: later)]
        var backup = LibraryArchive()
        backup.follows = ["10": Stamped(true, at: earlier)]
        backup.followedPerformers = ["10": profile]

        let restored = device.restoring(backup)
        #expect(restored.isFollowing(10))
        #expect(restored.followedProfiles == [profile])
    }

    // MARK: - What the archive holds

    @Test func aFreshArchiveHoldsNothing() {
        #expect(LibraryArchive().holdsNothing)
    }

    @Test func aTombstoneIsSomething() {
        var archive = LibraryArchive()
        archive.membership["1"] = Stamped(false, at: later)
        #expect(!archive.holdsNothing)
    }

    @Test func aFollowWithNoProfileIsNotListed() {
        var archive = LibraryArchive()
        archive.follows = ["10": Stamped(true), "20": Stamped(true)]
        archive.followedPerformers = [
            "20": PerformerProfile(id: 20, name: "B", reading: nil, fanCount: nil, slug: "b"),
        ]
        #expect(archive.followedProfiles.map(\.id) == [20])
    }

    @Test func decodesAnArchiveWrittenBeforeFollowsExisted() throws {
        let json = #"{"events":{},"membership":{},"tracking":{},"favorites":{},"recentSearches":{"value":[],"modified":0}}"#
        let archive = try JSONDecoder().decode(LibraryArchive.self, from: Data(json.utf8))
        #expect(archive.follows == nil)
        #expect(archive.eventernoteAccount == nil)
        #expect(archive.holdsNothing)
    }
}
