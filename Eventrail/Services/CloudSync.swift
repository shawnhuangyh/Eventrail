import CloudKit
import Foundation
import OSLog

/// What ``CloudSync`` needs from the library it keeps in step.
@MainActor
protocol CloudSyncHost: AnyObject {
    /// The archive as it stands, for the records about to be sent.
    var archiveForCloud: LibraryArchive { get }
    /// Records another device wrote, each a slice of an archive, to be folded
    /// in by the ordinary merge.
    func cloudDelivered(_ slices: [LibraryArchive])
    /// How the last exchange with iCloud went.
    func cloudReported(_ outcome: CloudSync.Outcome)
    /// iCloud is no longer somewhere this device's library may go — a
    /// different account, or the reader deleting the app's data from iCloud —
    /// and syncing has to stop until they say otherwise.
    func cloudStopped(_ outcome: CloudSync.Outcome)
}

/// Keeps the reader's library in step across their devices through the
/// private database of their own iCloud.
///
/// Built on `CKSyncEngine`, which owns the change tokens, the queue, the
/// retries and the pushes. What this adds is the library's side of it: which
/// records the archive holds (``CloudRecord``), what changed since they were
/// last sent, and folding what arrives back through
/// ``LibraryArchive/merging(_:)``.
///
/// **One record per thing, merged, never overwritten.** A save that lands on
/// a record another device changed first comes back refused with the
/// server's copy; that copy is merged in and the result sent again. A write
/// can only ever say something about the record it names, and a fresh install
/// names nothing, so there is no library to overwrite.
///
/// **A deleted record says nothing about the library.** Every record the
/// reader owns carries its own tombstone, so a removal is a save, not a
/// delete; a record is only deleted once its slice has pruned to nothing —
/// a Following read whose night has gone — and every device prunes the same
/// way on its own. A delete is unconditional, so it can land on another
/// device's save of the same record; a device that finds a record deleted
/// while it still holds something there once pruned sends it again.
///
/// Nothing imported from Eventernote is private, but the reader's notes are:
/// the private database is theirs alone, and the payload goes in
/// `encryptedValues`.
@MainActor
final class CloudSync: CKSyncEngineDelegate {
    static let shared = CloudSync()

    static let containerID = "iCloud.moe.shawn.Eventrail"
    static let zoneID = CKRecordZone.ID(zoneName: "Library", ownerName: CKCurrentUserDefaultName)

    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "sync")

    /// How syncing stands, in terms the Settings row can state plainly.
    enum Outcome: Sendable, Equatable {
        case synced
        /// This build carries no CloudKit entitlement, or the container is not
        /// set up for it.
        case notConfigured
        /// No iCloud account on this device, so there is nowhere to sync to.
        case signedOut
        /// Signed in, but iCloud cannot be reached for the moment — the account
        /// is being set up, or its terms need accepting.
        case unavailable
        /// No connection. The engine sends what is waiting once there is one.
        case offline
        /// iCloud refused the records, and not for any reason above.
        case rejected
        /// This device was signed in to a different iCloud account, so what it
        /// holds is no longer this store's to hand over. Syncing stops until
        /// the reader says otherwise — see ``EventStore/cloudStopped(_:)``.
        case accountChanged
        /// The reader deleted Eventrail's data from iCloud (Settings › iCloud ›
        /// Manage Storage). Sending the library straight back would undo what
        /// they just did, so syncing stops here as well.
        case cloudDataDeleted
        /// iCloud holds records this build cannot read — most likely written
        /// by a newer version. They are left as they are, never overwritten.
        case unreadableCopy
        /// The reader's iCloud storage is full.
        case iCloudFull
        case failed(String)
    }

    /// What this device remembers about iCloud between launches.
    private nonisolated struct Memory: Codable {
        /// The engine's own state: change tokens and what is waiting to go.
        var engineState: CKSyncEngine.State.Serialization?
        /// Each record's system fields as last seen, so a save is an update of
        /// that record rather than a create that collides with it.
        var systemFields: [String: Data] = [:]
        /// A fingerprint of each record as last sent or received — see
        /// ``CloudRecord/digests(of:)``.
        var digests: [String: Data] = [:]
        /// Records that arrived in a shape this build cannot read, kept
        /// verbatim and tried again each launch, so an update of the app reads
        /// them without their having to be fetched again. Never sent over.
        var held: [String: Held] = [:]
    }

    private nonisolated struct Held: Codable {
        var payload: Data
        var format: Int
    }

    private weak var host: CloudSyncHost?
    private var engine: CKSyncEngine?
    private var memory: Memory
    /// Bumped by ``stop()``, so a start still waiting on iCloud's account
    /// status knows it has been overtaken.
    private var generation = 0
    private var diffing: Task<Void, Never>?
    private var pendingWrite: Task<Void, Never>?
    /// What went wrong in the exchange under way, reported when it finishes
    /// in place of "synced".
    private var problem: Outcome?

    private let memoryURL: URL = {
        let directory = URL.applicationSupportDirectory.appending(path: "Eventrail", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "cloudkit.json")
    }()

    private init() {
        memory = (try? Data(contentsOf: memoryURL))
            .flatMap { try? JSONDecoder().decode(Memory.self, from: $0) } ?? Memory()
    }

    // MARK: - Starting and stopping

    /// Starts syncing for `host`, or — already running — asks iCloud for
    /// anything new and sends anything waiting.
    func sync(for host: CloudSyncHost) async {
        self.host = host
        if let engine {
            do {
                try await engine.fetchChanges()
                try await engine.sendChanges()
            } catch {
                report(Self.outcome(for: error))
            }
            return
        }

        let generation = generation
        let container = CKContainer(identifier: Self.containerID)
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            report(Self.outcome(for: error))
            return
        }
        guard generation == self.generation, engine == nil else { return }
        switch status {
        case .available:
            break
        case .noAccount:
            report(.signedOut)
            return
        case .temporarilyUnavailable, .couldNotDetermine:
            report(.unavailable)
            return
        default:
            report(.rejected)
            return
        }

        let engine = CKSyncEngine(CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: memory.engineState,
            delegate: self
        ))
        self.engine = engine
        if memory.engineState == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        }
        deliverHeld()
        // What iCloud holds is read before anything is sent, so a second
        // device's first sync updates the records it finds rather than
        // colliding with every one of them.
        do {
            try await engine.fetchChanges()
        } catch {
            report(Self.outcome(for: error))
        }
        await noteChanges()
    }

    /// Stops syncing on this device and forgets everything it knew about
    /// iCloud, so turning it back on reads the whole store afresh — the
    /// account behind it may not be the same one.
    func stop() async {
        generation += 1
        let engine = self.engine
        self.engine = nil
        diffing?.cancel()
        diffing = nil
        problem = nil
        await engine?.cancelOperations()
        memory = Memory()
        pendingWrite?.cancel()
        try? FileManager.default.removeItem(at: memoryURL)
    }

    // MARK: - Sending

    /// Compares the archive with what iCloud was last told and queues a save
    /// for every record that differs. Calls are taken one at a time.
    func noteChanges() async {
        let previous = diffing
        let task = Task { [weak self] in
            await previous?.value
            await self?.queueChanges()
        }
        diffing = task
        await task.value
    }

    private func queueChanges() async {
        guard let engine, let archive = host?.archiveForCloud else { return }
        // Encoding every record is the expensive half, and owes the main
        // thread nothing.
        let digests = await Task.detached(priority: .utility) {
            CloudRecord.digests(of: archive)
        }.value
        guard self.engine === engine, let current = host?.archiveForCloud else { return }

        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for (name, digest) in digests where memory.digests[name] != digest && memory.held[name] == nil {
            memory.digests[name] = digest
            changes.append(.saveRecord(Self.recordID(name)))
        }
        for name in memory.digests.keys where digests[name] == nil && memory.held[name] == nil {
            // Checked against the archive as it is now, not as it was when the
            // digests were taken: a record may have arrived in between.
            guard let key = CloudRecord.Key(recordName: name), current.slice(for: key) == nil else { continue }
            memory.digests[name] = nil
            changes.append(.deleteRecord(Self.recordID(name)))
        }
        guard !changes.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: changes)
        writeMemory()
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard syncEngine === engine, let archive = host?.archiveForCloud else { return nil }
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }

        // A save for a record that has since pruned to nothing, or that is
        // held unread, has nothing to send.
        let moot = pending.filter { change in
            guard case .saveRecord(let id) = change else { return false }
            guard memory.held[id.recordName] == nil,
                  let key = CloudRecord.Key(recordName: id.recordName)
            else { return true }
            return archive.slice(for: key) == nil
        }
        if !moot.isEmpty { syncEngine.state.remove(pendingRecordZoneChanges: moot) }
        let sending = pending.filter { !moot.contains($0) }
        guard !sending.isEmpty else { return nil }

        let fields = memory.systemFields
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: sending) { id in
            Self.record(for: id, in: archive, systemFields: fields[id.recordName])
        }
    }

    /// The record for one key as the archive now has it, on top of the system
    /// fields last seen for it where there are any.
    private nonisolated static func record(
        for id: CKRecord.ID, in archive: LibraryArchive, systemFields: Data?
    ) -> CKRecord? {
        guard let key = CloudRecord.Key(recordName: id.recordName),
              let slice = archive.slice(for: key),
              let payload = try? CloudRecord.payload(for: slice)
        else { return nil }
        let record = systemFields.flatMap(restoreRecord(from:))
            ?? CKRecord(recordType: CloudRecord.recordType, recordID: id)
        record.encryptedValues[CloudRecord.payloadField] = payload
        record[CloudRecord.formatField] = CloudRecord.currentFormat
        return record
    }

    // MARK: - Events

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard syncEngine === engine else { return }
        switch event {
        case .stateUpdate(let update):
            memory.engineState = update.stateSerialization
            writeMemory()

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                // Only ever the first start: a sign-out or a switch stops
                // syncing outright, so there is no later sign-in to catch up
                // on. ``sync(for:)`` sends everything once it has read what
                // iCloud already holds.
                break
            case .signOut, .switchAccounts:
                host?.cloudStopped(.accountChanged)
            @unknown default:
                host?.cloudStopped(.accountChanged)
            }

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == Self.zoneID {
                switch deletion.reason {
                case .encryptedDataReset:
                    // The keys were reset and the encrypted fields went with
                    // them. The library is still whole on this device, so it
                    // is sent again in full.
                    memory.systemFields = [:]
                    memory.digests = [:]
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                    writeMemory()
                    await noteChanges()
                default:
                    host?.cloudStopped(.cloudDataDeleted)
                }
            }

        case .fetchedRecordZoneChanges(let changes):
            receive(changes.modifications.map(\.record))
            // The record's content says nothing here — see the type's notes —
            // but its system fields are stale.
            //
            // A delete is unconditional, though, so it can land on a save it
            // never saw: one device pruning away an old Following read while
            // another adds the same night to the library leaves the server
            // with neither. Whatever this device still holds once it has
            // pruned is sent back. A slice that prunes to nothing is not, so
            // two devices do not trade an expired read back and forth.
            var resend: [CKSyncEngine.PendingRecordZoneChange] = []
            let kept = changes.deletions.isEmpty ? nil : host?.archiveForCloud.pruned()
            for deletion in changes.deletions where deletion.recordID.zoneID == Self.zoneID {
                let name = deletion.recordID.recordName
                memory.systemFields[name] = nil
                guard memory.held[name] == nil,
                      let key = CloudRecord.Key(recordName: name),
                      kept?.slice(for: key) != nil
                else { continue }
                resend.append(.saveRecord(deletion.recordID))
            }
            if !resend.isEmpty { syncEngine.state.add(pendingRecordZoneChanges: resend) }
            if !changes.deletions.isEmpty { writeMemory() }

        case .sentRecordZoneChanges(let sent):
            handleSent(sent, engine: syncEngine)

        case .sentDatabaseChanges(let sent):
            for failure in sent.failedZoneSaves {
                Self.log.error("zone save failed: \(failure.error.localizedDescription, privacy: .public)")
                problem = Self.outcome(for: failure.error)
            }

        case .willFetchChanges, .willSendChanges:
            problem = nil

        case .didFetchRecordZoneChanges(let fetched):
            if let error = fetched.error { problem = Self.outcome(for: error) }

        case .didFetchChanges, .didSendChanges:
            // Records held unread are still unread, whatever else went well.
            report(problem ?? (memory.held.isEmpty ? .synced : .unreadableCopy))

        default:
            break
        }
    }

    /// Records another device wrote, folded into the library.
    private func receive(_ records: [CKRecord]) {
        var slices: [LibraryArchive] = []
        for record in records where record.recordID.zoneID == Self.zoneID {
            let name = record.recordID.recordName
            memory.systemFields[name] = Self.systemFields(of: record)
            guard let payload = record.encryptedValues[CloudRecord.payloadField] as? Data else { continue }
            let format = record[CloudRecord.formatField] as? Int ?? CloudRecord.currentFormat
            guard format <= CloudRecord.currentFormat, let slice = try? CloudRecord.slice(from: payload) else {
                Self.log.error("record \(name, privacy: .public) is in format \(format), unreadable here")
                memory.held[name] = Held(payload: payload, format: format)
                problem = .unreadableCopy
                continue
            }
            memory.held[name] = nil
            memory.digests[name] = CloudRecord.digest(of: slice)
            slices.append(slice)
        }
        writeMemory()
        if !slices.isEmpty { host?.cloudDelivered(slices) }
    }

    /// Records held unread on an earlier launch, tried again by this build.
    private func deliverHeld() {
        var slices: [LibraryArchive] = []
        for (name, held) in memory.held where held.format <= CloudRecord.currentFormat {
            guard let slice = try? CloudRecord.slice(from: held.payload) else { continue }
            memory.held[name] = nil
            memory.digests[name] = CloudRecord.digest(of: slice)
            slices.append(slice)
        }
        if !memory.held.isEmpty { report(.unreadableCopy) }
        guard !slices.isEmpty else { return }
        writeMemory()
        host?.cloudDelivered(slices)
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) {
        for record in sent.savedRecords {
            memory.systemFields[record.recordID.recordName] = Self.systemFields(of: record)
        }
        for id in sent.deletedRecordIDs {
            memory.systemFields[id.recordName] = nil
        }

        var arrived: [CKRecord] = []
        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        for failure in sent.failedRecordSaves {
            let id = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                // Another device got there first. Its copy is merged in, and
                // what the merge makes of the two is sent in its place.
                if let server = failure.error.serverRecord { arrived.append(server) }
                retry.append(.saveRecord(id))
            case .zoneNotFound:
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                memory.systemFields[id.recordName] = nil
                retry.append(.saveRecord(id))
            case .unknownItem:
                memory.systemFields[id.recordName] = nil
                retry.append(.saveRecord(id))
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .requestRateLimited, .notAuthenticated, .operationCancelled:
                // The engine keeps these pending and tries again itself.
                break
            default:
                Self.log.error("save of \(id.recordName, privacy: .public) failed: \(failure.error.localizedDescription, privacy: .public)")
                problem = Self.outcome(for: failure.error)
            }
        }
        for (id, error) in sent.failedRecordDeletes where error.code != .unknownItem {
            Self.log.error("delete of \(id.recordName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }

        if !arrived.isEmpty { receive(arrived) }
        if !retry.isEmpty { engine.state.add(pendingRecordZoneChanges: retry) }
        writeMemory()
    }

    // MARK: - Reporting

    private func report(_ outcome: Outcome) {
        host?.cloudReported(outcome)
    }

    static func outcome(for error: Error) -> Outcome {
        guard let error = error as? CKError else { return .failed(error.localizedDescription) }
        switch error.code {
        case .notAuthenticated:
            return .signedOut
        case .quotaExceeded:
            return .iCloudFull
        case .missingEntitlement, .badContainer, .permissionFailure:
            return .notConfigured
        case .networkFailure, .networkUnavailable:
            return .offline
        case .serviceUnavailable, .requestRateLimited, .zoneBusy, .accountTemporarilyUnavailable:
            return .unavailable
        case .userDeletedZone:
            return .cloudDataDeleted
        default:
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Keeping what was learned

    /// Written a moment later rather than at once: a fetch of a whole library
    /// updates a system field per record, and the file holds them all.
    private func writeMemory() {
        pendingWrite?.cancel()
        let generation = generation
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            // A stop in between has forgotten all of this on purpose.
            guard !Task.isCancelled, let self, generation == self.generation else { return }
            let memory = self.memory
            let url = self.memoryURL
            await Task.detached(priority: .utility) {
                guard let data = try? JSONEncoder().encode(memory) else { return }
                try? data.write(to: url, options: .atomic)
            }.value
        }
    }

    private static func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    private nonisolated static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private nonisolated static func restoreRecord(from systemFields: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: systemFields) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}
