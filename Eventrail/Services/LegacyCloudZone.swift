import CloudKit
import Foundation
import OSLog

/// What the CKSyncEngine builds wrote to iCloud, read back into the store.
///
/// Those builds kept one `LibraryRecord` per record in a zone of their own,
/// `Library`, each carrying its slice of the archive as zlib-compressed JSON in
/// `encryptedValues["payload"]`. SwiftData mirrors into Core Data's own zone,
/// so nothing in the old one reaches the store by itself: a device reinstalled
/// since, whose only copy of the library is that zone, would start empty, and
/// a device still on an old build would never be heard from. So every time
/// syncing starts, and on coming back to the app now and then,
/// ``LibraryDatabase`` reads what changed there since it last read — the change
/// token is kept per device — and merges it in by the archive's rules. Nothing
/// is ever written there.
nonisolated enum LegacyCloudZone {
    static let zoneID = CKRecordZone.ID(zoneName: "Library", ownerName: CKCurrentUserDefaultName)
    static let recordType = "LibraryRecord"
    static let payloadField = "payload"
    static let formatField = "format"
    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "legacyZone")

    /// The newest shape those builds wrote a slice in. A record in a newer
    /// one is left alone rather than read with its unknown fields dropped.
    static let readableFormat = 1

    /// The slice one old record carries, or nil where it carries none this
    /// build can read.
    static func slice(of record: CKRecord) -> LibraryArchive? {
        guard record.recordType == recordType,
              let payload = record.encryptedValues[payloadField] as? Data
        else { return nil }
        let format = record[formatField] as? Int ?? readableFormat
        guard format <= readableFormat else { return nil }
        return try? slice(from: payload)
    }

    static func slice(from payload: Data) throws -> LibraryArchive {
        let json = try (payload as NSData).decompressed(using: .zlib) as Data
        return try JSONDecoder().decode(LibraryArchive.self, from: json)
    }

    /// How far a read of the zone has come. The token kept goes only as far as
    /// every record before it was read: past a record that failed, it would
    /// never be asked for again, and a device reinstalled since, whose only
    /// copy of that slice is here, would go without it for good. What came
    /// after the failure is still taken in and asked for again next time, which
    /// the merge makes harmless.
    struct Progress<Token> {
        private(set) var kept: Token?
        private var hasGap = false

        init(from token: Token?) { kept = token }

        mutating func read(upTo token: Token, failed: Bool) {
            hasGap = hasGap || failed
            if !hasGap { kept = token }
        }
    }

    /// Everything that changed in the old zone since `token`, as one archive,
    /// and the token to ask from next time, where there is one to keep (see
    /// ``Progress``). Nil where there is no old zone — a reader who never ran
    /// those builds, or deleted their iCloud data.
    ///
    /// Deletions are passed over: those builds deleted a record only when
    /// pruning left it nothing, and pruning here drops the same.
    @concurrent
    static func changes(
        in database: CKDatabase, since token: CKServerChangeToken?
    ) async throws -> (archive: LibraryArchive, token: CKServerChangeToken?)? {
        var slices: [LibraryArchive] = []
        var token = token
        var progress = Progress(from: token)
        while true {
            let changes: (modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>],
                          deletions: [CKDatabase.RecordZoneChange.Deletion],
                          changeToken: CKServerChangeToken, moreComing: Bool)
            do {
                changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
                return nil
            } catch let error as CKError where error.code == .changeTokenExpired && token != nil {
                // Read from the start instead; the merge makes a second read
                // of the same record harmless.
                slices = []
                token = nil
                progress = Progress(from: nil)
                continue
            }
            var failures = 0
            for result in changes.modificationResultsByID.values {
                switch result {
                case .success(let modification):
                    if let slice = slice(of: modification.record) { slices.append(slice) }
                case .failure:
                    failures += 1
                }
            }
            if failures > 0 {
                log.error("\(failures) records in the old iCloud zone could not be read; asked for again next time.")
            }
            progress.read(upTo: changes.changeToken, failed: failures > 0)
            token = changes.changeToken
            if !changes.moreComing {
                return (LibraryArchive().merging(contentsOf: slices), progress.kept)
            }
        }
    }
}
