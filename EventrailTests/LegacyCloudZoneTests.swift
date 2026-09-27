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
