import Foundation
import Testing
@testable import Eventrail

struct CloudRecordsTests {
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

    @Test(arguments: [CloudRecord.Key.event("123"), .performer("45"), .settings])
    func aKeySurvivesItsRecordName(_ key: CloudRecord.Key) {
        #expect(CloudRecord.Key(recordName: key.recordName) == key)
    }

    @Test func aNameThisBuildDoesNotKnowIsNoKey() {
        #expect(CloudRecord.Key(recordName: "venue.9") == nil)
    }

    /// Every record the archive holds, folded into an empty one, is the
    /// archive again — nothing lost in the cutting.
    @Test func theRecordsAddUpToTheArchive() {
        let archive = library().pruned()
        let slices = archive.cloudKeys.compactMap(archive.slice(for:))
        #expect(LibraryArchive().merging(contentsOf: slices) == archive)
    }

    @Test func eachThingIsOneRecord() {
        #expect(library().cloudKeys == [
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
        #expect(LibraryArchive().cloudKeys.isEmpty)
    }

    @Test func aPayloadReadsBack() throws {
        let slice = try #require(library().slice(for: .event("1")))
        #expect(try CloudRecord.slice(from: CloudRecord.payload(for: slice)) == slice)
    }

    /// An edit changes the fingerprint of the one record it touched, and a
    /// second pass over the same archive gives the same fingerprints.
    @Test func anEditTouchesOneRecord() {
        let before = library()
        var after = before
        after.tracking["2"] = Stamped(Tracking(note: "balcony"), at: later)

        let old = CloudRecord.digests(of: before)
        let new = CloudRecord.digests(of: after)
        #expect(CloudRecord.digests(of: before) == old)
        #expect(Set(new.keys) == Set(old.keys))
        #expect(new.filter { old[$0.key] != $0.value }.map(\.key) == ["event.2"])
    }

    /// A record arriving from another device settles against this one's copy
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

    /// What a device checks when another deletes a record: whether anything
    /// under that name outlives its own pruning. An expired Following read
    /// does not, so it is not traded back; the same night added to the library
    /// meanwhile does, so the delete does not take it off the server.
    @Test func onlyWhatOutlivesPruningAnswersADelete() {
        let past = Date.now.addingTimeInterval(-30 * 24 * 60 * 60)
        let night = Fixtures.event(id: "7", date: past)
        var archive = LibraryArchive()
        archive.followingReads = ["7": Stamped(FollowingRead(fingerprint: night.listingFingerprint, day: past), at: earlier)]
        #expect(archive.slice(for: .event("7")) != nil)
        #expect(archive.pruned().slice(for: .event("7")) == nil)

        archive.events["7"] = night
        archive.membership["7"] = Stamped(true, at: later)
        #expect(archive.pruned().slice(for: .event("7"))?.membership["7"]?.value == true)
    }

    /// A removal is a tombstone, and a tombstone is something to send back.
    @Test func aTombstoneAnswersADelete() {
        var archive = LibraryArchive()
        archive.membership["7"] = Stamped(false, at: later)
        #expect(archive.pruned().slice(for: .event("7")) != nil)
    }
}
