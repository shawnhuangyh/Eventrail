import Foundation
import Testing
@testable import Eventrail

/// How an archive is cut into the records the store keeps one row for each
/// of — see ``LibraryArchive/RecordKey``.
struct RecordSliceTests {
    let earlier = Date.now.addingTimeInterval(-3600)
    let later = Date.now.addingTimeInterval(-60)
    /// A night far enough ahead that pruning never reaches its read.
    let ahead = Date.now.addingTimeInterval(30 * 24 * 60 * 60)

    /// Something in every part of the archive a record can carry.
    func library() -> LibraryArchive {
        var archive = LibraryArchive()
        for id in ["1", "2"] {
            archive.events[id] = Fixtures.event(id: id, title: "Live \(id)")
            archive.membership[id] = Stamped(true, at: earlier)
        }
        archive.membership["gone"] = Stamped(false, at: later)
        archive.tracking["1"] = Stamped(Tracking(note: "front row"), at: earlier)
        archive.favorites["2"] = Stamped(true, at: earlier)
        let listed = Fixtures.event(id: "3", date: ahead)
        archive.followingReads = ["3": Stamped(FollowingRead(fingerprint: listed.listingFingerprint, day: listed.date), at: earlier)]
        archive.follows = ["10": Stamped(true, at: earlier), "11": Stamped(false, at: later)]
        archive.followedPerformers = ["10": PerformerProfile(id: 10, name: "A", reading: nil, fanCount: nil, slug: "a")]
        archive.eventernoteAccount = Stamped("reader", at: earlier)
        archive.recentSearches = Stamped(["A"], at: earlier)
        archive.lastImported = earlier
        return archive
    }

    /// Every record the archive holds, folded into an empty one, is the
    /// archive again — nothing lost in the cutting.
    @Test func theRecordsAddUpToTheArchive() {
        let archive = library().pruned()
        let slices = archive.recordKeys.compactMap(archive.slice(for:))
        #expect(LibraryArchive().merging(contentsOf: slices) == archive)
    }

    @Test func eachThingIsOneRecord() {
        #expect(library().recordKeys == [
            .event("1"), .event("2"), .event("3"), .event("gone"),
            .performer("10"), .performer("11"), .settings,
        ])
    }

    @Test func aRecordCarriesOnlyItsOwnThing() throws {
        let slice = try #require(library().slice(for: .event("1")))
        #expect(slice.events.keys.sorted() == ["1"])
        #expect(slice.tracking["1"]?.value.note == "front row")
        #expect(slice.favorites.isEmpty)
        #expect(slice.follows == nil)
        #expect(slice.eventernoteAccount == nil)
    }

    @Test func nothingToSayIsNoRecord() {
        #expect(library().slice(for: .event("unknown")) == nil)
        #expect(library().slice(for: .performer("99")) == nil)
        // A fresh install's defaults are not a setting anybody made.
        #expect(LibraryArchive().slice(for: .settings) == nil)
        #expect(LibraryArchive().recordKeys.isEmpty)
    }

    /// Another device's row for the same event settles against this one's
    /// by the ordinary merge — here, one answer each.
    @Test func anArrivingRecordMergesAnswerByAnswer() throws {
        var phone = library()
        phone.tracking["1"] = Stamped(phone.tracking["1"]!.value, at: earlier)
            .edited(to: Tracking(seat: "A12", note: "front row"), at: later)
        var iPad = library()
        iPad.tracking["1"] = Stamped(iPad.tracking["1"]!.value, at: earlier)
            .edited(to: Tracking(cost: 9000, note: "front row"), at: later)

        let arriving = try #require(iPad.slice(for: .event("1")))
        let merged = phone.merging(contentsOf: [arriving]).tracking["1"]?.value
        #expect(merged?.seat == "A12")
        #expect(merged?.cost == 9000)
    }
}
