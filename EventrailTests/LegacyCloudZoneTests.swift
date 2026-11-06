import CloudKit
import Foundation
import Testing
@testable import Eventrail

struct LegacyCloudZoneTests {
    /// A slice as the CKSyncEngine builds wrote one: sorted-key JSON, zlib.
    func payload(_ slice: LibraryArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try (encoder.encode(slice) as NSData).compressed(using: .zlib) as Data
    }

    func record(_ name: String, payload: Data, format: Int? = nil,
                type: String = LegacyCloudZone.recordType) -> CKRecord {
        let record = CKRecord(recordType: type, recordID: CKRecord.ID(recordName: name, zoneID: LegacyCloudZone.zoneID))
        record.encryptedValues[LegacyCloudZone.payloadField] = payload
        if let format { record[LegacyCloudZone.formatField] = format }
        return record
    }

    let written = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func slice() -> LibraryArchive {
        var archive = LibraryArchive()
        archive.events["1"] = Fixtures.event(id: "1")
        archive.membership["1"] = Stamped(true, at: written)
        archive.tracking["1"] = Stamped(Tracking(seat: "A12", note: "front row"), at: written)
        return archive
    }

    @Test func aRecordTheOldSyncWroteReadsBack() throws {
        let read = LegacyCloudZone.slice(of: record("event.1", payload: try payload(slice()), format: 1))
        #expect(read == slice())
    }

    @Test func aRecordWithNoFormatIsTheFirst() throws {
        #expect(LegacyCloudZone.slice(of: record("event.1", payload: try payload(slice()))) == slice())
    }

    /// Written by a build newer than any this one knows of: left alone rather
    /// than read with what it added dropped.
    @Test func aNewerFormatIsLeftAlone() throws {
        #expect(LegacyCloudZone.slice(of: record("event.1", payload: try payload(slice()), format: 2)) == nil)
    }

    @Test func anotherRecordTypeIsNotRead() throws {
        #expect(LegacyCloudZone.slice(of: record("event.1", payload: try payload(slice()), type: "CD_LibraryEvent")) == nil)
    }

    @Test func aPayloadThatIsNotOneIsSkipped() {
        #expect(LegacyCloudZone.slice(of: record("event.1", payload: Data("not zlib".utf8))) == nil)
    }
}

/// Asking the old zone and the account again — see ``LegacyCloudZone/Progress``
/// and ``LibraryDatabase/resumeSyncing()``.
struct LegacyZoneAskingTests {
    typealias Progress = LegacyCloudZone.Progress<Int>

    /// Read whole, the token moves on with each batch.
    @Test func theTokenFollowsAWholeRead() {
        var progress = Progress(from: nil)
        progress.read(upTo: 1, failed: false)
        progress.read(upTo: 2, failed: false)
        #expect(progress.kept == 2)
    }

    /// Past a record that failed, it would never be asked for again.
    @Test func theTokenStaysBeforeARecordThatFailed() {
        var progress = Progress(from: 1)
        progress.read(upTo: 2, failed: false)
        progress.read(upTo: 3, failed: true)
        // Nor does a whole batch after it carry the token over the gap.
        progress.read(upTo: 4, failed: false)
        #expect(progress.kept == 2)
    }

    /// Nothing read whole from the start leaves nothing to keep, or what was
    /// held to ask from again.
    @Test func aFirstBatchThatFailedKeepsWhatWasHeld() {
        var fresh = Progress(from: nil)
        fresh.read(upTo: 1, failed: true)
        #expect(fresh.kept == nil)

        var held = Progress(from: 5)
        held.read(upTo: 6, failed: true)
        #expect(held.kept == 5)
    }

    @Test func theOldZoneIsAskedAtMostSoOften() {
        let asked = Date(timeIntervalSinceReferenceDate: 1_000_000)
        #expect(LibraryDatabase.legacyZoneIsDue(asked: nil, at: asked))
        #expect(!LibraryDatabase.legacyZoneIsDue(asked: asked, at: asked.addingTimeInterval(60)))
        #expect(LibraryDatabase.legacyZoneIsDue(asked: asked, at: asked.addingTimeInterval(LibraryDatabase.legacyZonePatience)))
    }

    /// A store syncing with nothing owed has no reason to ask; told the account
    /// changed, it asks until it has an answer.
    @Test func aSyncingStoreAsksAgainOnlyWhereTheAccountChanged() {
        #expect(LibraryDatabase.asksAboutAccountAgain(isSyncing: false, owed: false))
        #expect(!LibraryDatabase.asksAboutAccountAgain(isSyncing: true, owed: false))
        #expect(LibraryDatabase.asksAboutAccountAgain(isSyncing: true, owed: true))
    }
}
