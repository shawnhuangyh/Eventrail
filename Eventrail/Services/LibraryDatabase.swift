import CloudKit
import CoreData
import Foundation
import OSLog
import SwiftData

/// Where the reader's library is kept, and how it reaches their other devices.
///
/// A SwiftData store in Application Support, holding one row per record —
/// ``LibraryEvent``, ``LibraryMembership``, ``FollowingReadMark``,
/// ``FollowedPerformer`` and ``LibrarySettings``. With
/// iCloud Sync on, SwiftData mirrors it into the reader's private CloudKit
/// database by itself; off, the same store is opened with no CloudKit at all.
/// The switch is per device, so turning it opens the store again the other
/// way (``setSyncing(_:)``), and the screens reading it are rebuilt on the new
/// container (``generation``).
///
/// **Two devices write two rows for one event**, and nothing can stop them:
/// each moves its own library in, and each imports the same Eventernote
/// account. CloudKit has no unique constraint to refuse the second, so
/// ``deduplicate(in:)`` folds every such pair back into one after each import
/// from iCloud, through ``LibraryArchive/merging(contentsOf:)`` — the same
/// merge two devices' records always went through — and keeps the row with the
/// lowest `uid`, which every device picks alike.
///
/// **A file that will not open is never written over.** The store is created
/// with the system's default protection, so before a device's first unlock it
/// will not open at all. The library is then kept in memory instead
/// (``isBlocked``), where the reader can go on using it, and ``reopen()``
/// tries the file again — folding whatever was written meanwhile into what
/// the file holds, by the ordinary merge, once it opens.
@Observable
final class LibraryDatabase {
    static let containerID = "iCloud.moe.shawn.Eventrail"

    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "library")

    static let schema = Schema([LibraryEvent.self, LibraryMembership.self, FollowingReadMark.self,
                                FollowedPerformer.self, LibrarySettings.self])

    /// How syncing stands, in terms the Settings row can state plainly.
    enum SyncStatus: Equatable, Sendable {
        case synced
        /// This build carries no CloudKit entitlement, or the container is not
        /// set up for it.
        case notConfigured
        /// No iCloud account on this device, so there is nowhere to sync to.
        case signedOut
        /// Signed in, but iCloud cannot be reached for the moment.
        case unavailable
        /// No connection. SwiftData sends what is waiting once there is one.
        case offline
        /// The reader's iCloud storage is full.
        case iCloudFull
        /// The iCloud account the library synced with signed out or was
        /// swapped for another, so syncing stopped — see
        /// ``checkAccount()``. Said while the switch is off, since it is why.
        case accountChanged
        /// The reader deleted Eventrail's data from iCloud (Settings › iCloud ›
        /// Manage Storage), so syncing stopped rather than send the library
        /// straight back. Said while the switch is off, like ``accountChanged``.
        case cloudDataDeleted
        case failed(String)
    }

    enum Location: Equatable {
        case file(URL)
        /// A store that lives and dies with this value — previews and tests.
        case memory
    }

    static var defaultLocation: Location {
        let directory = URL.applicationSupportDirectory.appending(path: "Eventrail", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return .file(directory.appending(path: "Library.store"))
    }

    /// The store, or one held in memory while the file will not open — see
    /// ``isBlocked``.
    private(set) var container: ModelContainer
    /// Bumped whenever ``container`` is replaced, so a screen built on the old
    /// one is built again.
    private(set) var generation = 0
    private(set) var syncStatus: SyncStatus?
    private(set) var lastSynced: Date?
    /// Whether the store is open with CloudKit. Not the switch: with the
    /// switch on, the store is opened without CloudKit until the iCloud user
    /// has been checked (``checkAccount()``).
    private(set) var isSyncing = false
    /// Whether the file would not open, so ``container`` is held in memory.
    private(set) var isBlocked = false
    /// The container this one replaced, kept for a moment so a screen still
    /// drawing one of its rows is not left holding a row whose store has gone
    /// — and only for a moment, since a CloudKit container kept alive goes on
    /// mirroring the file the new one writes to (``replace(with:)``).
    @ObservationIgnored private var retired: ModelContainer?

    /// Run once another device's changes have landed and been folded in.
    @ObservationIgnored var onRemoteChanges: (() -> Void)?
    /// Run when iCloud stops the library syncing — the account changed, or
    /// the reader deleted its data there — to turn the switch off, which
    /// opens the store without CloudKit. Without it the store is simply
    /// opened that way.
    @ObservationIgnored var onSyncStopped: (() -> Void)?
    /// Run whenever the store has been opened again, on a new container —
    /// which can be a while after the switch is turned, since syncing starts
    /// only once the account has been checked.
    @ObservationIgnored var onReopened: (() -> Void)?

    @ObservationIgnored private let location: Location
    /// Whether the switch is on: the store is to be synced once the iCloud
    /// user is known to be the one it synced with.
    @ObservationIgnored private var wantsSyncing: Bool
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    /// The library as it stood when the import running now began — what
    /// ``reconcile(_:in:)`` holds the import up against.
    @ObservationIgnored private var beforeImport: LibraryArchive?

    /// Which iCloud user this device's library syncs with (the container's
    /// user record name), written the first time syncing finds one. Per
    /// device, like the switch, and cleared when the switch goes off.
    private static let accountKey = "iCloudSyncAccount"
    /// Where this device last read the old sync's zone up to — see
    /// ``LegacyCloudZone``. Cleared with the account, since it belongs to one.
    private static let legacyTokenKey = "iCloudLegacyZoneToken"

    init(at location: Location = LibraryDatabase.defaultLocation, syncing: Bool) {
        self.location = location
        wantsSyncing = syncing && location != .memory
        container = Self.memoryContainer()
        // Without CloudKit even with the switch on: the account may have
        // changed while the app was not running, and a store opened with
        // CloudKit starts sending before any check could answer.
        open()
        observeSyncEvents()
        if wantsSyncing { checkAccount() }
    }

    isolated deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        if isSyncing { releaseFile() }
    }

    /// The context everything reads and writes through.
    var context: ModelContext { container.mainContext }

    /// Tries the file again after it would not open. Answers whether it is
    /// open now.
    @discardableResult
    func reopen() -> Bool {
        guard isBlocked else { return true }
        open()
        return !isBlocked
    }

    /// Turns syncing on or off. On, the store is opened with CloudKit once
    /// the account has been checked; off, at once without it.
    func setSyncing(_ syncing: Bool) {
        guard location != .memory, syncing != wantsSyncing else { return }
        wantsSyncing = syncing
        syncStatus = nil
        beforeImport = nil
        retry?.cancel()
        // Turned on, it is whichever account is signed in now that the reader
        // said yes to, so the record is written afresh.
        UserDefaults.standard.removeObject(forKey: Self.accountKey)
        UserDefaults.standard.removeObject(forKey: Self.legacyTokenKey)
        if syncing {
            checkAccount()
        } else if isSyncing {
            isSyncing = false
            releaseFile()
            open()
        }
    }

    /// Which files a database in this process is mirroring to CloudKit.
    private static var syncingFiles: Set<URL> = []

    private func releaseFile() {
        if case .file(let url) = location { Self.syncingFiles.remove(url) }
    }

    /// Asks again whether syncing can start, where the switch is on and the
    /// last check could not tell — offline, say. Run on coming back to the app.
    func resumeSyncing() {
        guard wantsSyncing, !isSyncing, syncStatus != .notConfigured else { return }
        checkAccount()
    }

    /// Opens the store with CloudKit, now that the account is the one the
    /// reader said yes to.
    private func startSyncing() {
        guard wantsSyncing, !isSyncing, !isBlocked else { return }
        // Core Data refuses a second CloudKit mirror of one file in a process,
        // and goes on retrying it.
        if case .file(let url) = location {
            guard Self.syncingFiles.insert(url).inserted else {
                Self.log.fault("The library is already syncing in this process; not mirroring it twice.")
                return
            }
        }
        isSyncing = true
        syncStatus = nil
        open()
        if isSyncing { readLegacyZone() }
    }

    /// Merges in what the sync before SwiftData left in iCloud, or what a
    /// device still on it has written there since — see ``LegacyCloudZone``.
    private func readLegacyZone() {
        Task {
            let defaults = UserDefaults.standard
            let token = defaults.data(forKey: Self.legacyTokenKey).flatMap {
                try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
            }
            let database = CKContainer(identifier: Self.containerID).privateCloudDatabase
            do {
                guard let (legacy, next) = try await LegacyCloudZone.changes(in: database, since: token),
                      isSyncing
                else { return }
                if !legacy.holdsNothing {
                    let held = try Self.archive(in: context)
                    if try Self.apply(held.merging(legacy), to: context) {
                        try context.save()
                        Self.log.notice("Merged in what the old iCloud zone held.")
                        onRemoteChanges?()
                    }
                }
                let saved = try NSKeyedArchiver.archivedData(withRootObject: next, requiringSecureCoding: true)
                defaults.set(saved, forKey: Self.legacyTokenKey)
            } catch {
                Self.log.error("The old iCloud zone could not be read: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func open() {
        // What the old container holds and has not written, folded into the
        // new one below so a swap never drops an edit: all of it while the
        // file would not open, and otherwise whatever a failed save left.
        var meanwhile: LibraryArchive?
        if isBlocked {
            meanwhile = try? Self.archive(in: context)
        } else if context.hasChanges {
            do {
                try context.save()
            } catch {
                Self.log.error("Library could not be saved before reopening: \(error.localizedDescription, privacy: .public)")
                meanwhile = try? Self.archive(in: context)
            }
        }
        do {
            let opened = try Self.makeContainer(at: location, syncing: isSyncing)
            replace(with: opened)
            isBlocked = false
        } catch where isSyncing {
            Self.log.error("Library could not be opened with CloudKit: \(error.localizedDescription, privacy: .public)")
            isSyncing = false
            releaseFile()
            syncStatus = .notConfigured
            if let opened = try? Self.makeContainer(at: location, syncing: false) {
                replace(with: opened)
                isBlocked = false
            } else {
                block()
            }
        } catch {
            Self.log.error("Library could not be opened: \(error.localizedDescription, privacy: .public)")
            block()
        }
        defer { onReopened?() }
        guard !isBlocked else { return }
        do {
            if let meanwhile, !meanwhile.holdsNothing {
                let held = try Self.archive(in: context)
                try Self.apply(held.merging(meanwhile), to: context)
                try context.save()
            }
            try Self.adoptLegacyRecords(in: context)
            try Self.deduplicate(in: context)
            try Self.prune(in: context)
        } catch {
            // A merge that would not save stays in the context, to be written
            // with the next edit.
            Self.log.error("Library could not be tidied: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Keeps the library in memory until the file will open. Only the first
    /// refusal swaps the container: a second leaves what the reader wrote
    /// meanwhile where it is.
    private func block() {
        guard !isBlocked else { return }
        isBlocked = true
        replace(with: Self.memoryContainer())
    }

    private func replace(with opened: ModelContainer) {
        let outgoing = container
        retired = outgoing
        container = opened
        generation += 1
        // Let go once the screens have drawn on the new one. The store keeps
        // its rows and the screens re-read it at once, but a container opened
        // with CloudKit and held after sync is turned off goes on importing
        // pushes and exporting whatever the new one writes to the same file —
        // so the off switch would not keep the library out of iCloud.
        Task { [weak self] in
            try? await Task.sleep(for: Self.retiredHold)
            guard let self, retired === outgoing else { return }
            retired = nil
        }
    }

    /// How long a replaced container is held: past the redraw that moves the
    /// screens onto the new one, and no longer.
    private static let retiredHold = Duration.seconds(1)

    private static func memoryContainer() -> ModelContainer {
        do {
            return try makeContainer(at: .memory, syncing: false)
        } catch {
            fatalError("A library held in memory could not be made: \(error)")
        }
    }

    private static func makeContainer(at location: Location, syncing: Bool) throws -> ModelContainer {
        let configuration: ModelConfiguration = switch location {
        case .memory:
            // Named afresh each time, so two stores in one test run are two.
            ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true,
                               cloudKitDatabase: .none)
        case .file(let url):
            // Always named explicitly: left alone, SwiftData picks `.automatic`
            // and syncs the moment the entitlement is there, switch or not.
            ModelConfiguration("Library", schema: schema, url: url,
                               cloudKitDatabase: syncing ? .private(containerID) : .none)
        }
        return try ModelContainer(for: schema, configurations: configuration)
    }

    // MARK: - Syncing

    /// Checks the iCloud user before the store is synced, and again whenever
    /// CloudKit says the account changed.
    ///
    /// A store synced with one person's iCloud holds that person's library;
    /// handed on to whoever signs in next it would be uploaded into their
    /// private database. So the store is opened with CloudKit only once the
    /// signed-in user is the one it first synced with — or, the first time,
    /// once there is a user to write down — and a sign-out or a different
    /// user turns the switch off, to wait for the reader to say yes to the new
    /// account. What the build before SwiftData did on the same news.
    ///
    /// Also says early what an import would only say by failing: no account,
    /// or one iCloud cannot reach.
    private func checkAccount() {
        Task {
            let container = CKContainer(identifier: Self.containerID)
            let status: CKAccountStatus
            do {
                status = try await container.accountStatus()
            } catch {
                // Said rather than left blank: the switch has just cleared the
                // status, and blank reads as syncing fine.
                couldNotCheck(error)
                return
            }
            guard wantsSyncing else { return }
            let syncedWith = UserDefaults.standard.string(forKey: Self.accountKey)
            switch status {
            case .available:
                let user: String
                do {
                    user = try await container.userRecordID().recordName
                } catch {
                    couldNotCheck(error)
                    return
                }
                guard wantsSyncing else { return }
                if let syncedWith, syncedWith != user {
                    stopSyncing(.accountChanged)
                } else {
                    if syncedWith == nil { UserDefaults.standard.set(user, forKey: Self.accountKey) }
                    startSyncing()
                }
            case .noAccount:
                if syncedWith != nil { stopSyncing(.accountChanged) } else { syncStatus = .signedOut }
            case .restricted, .temporarilyUnavailable, .couldNotDetermine:
                syncStatus = .unavailable
            @unknown default:
                syncStatus = .unavailable
            }
        }
    }

    /// The account could not be checked. A store already syncing goes on; one
    /// waiting to start stays unsynced — nothing is sent to a user nobody has
    /// named — and asks again in a minute, and on coming back to the app.
    private func couldNotCheck(_ error: any Error) {
        guard wantsSyncing else { return }
        syncStatus = Self.status(for: error)
        guard !isSyncing else { return }
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self else { return }
            self.resumeSyncing()
        }
    }

    /// Turns syncing off because iCloud said to, and says why until the reader
    /// turns it on again.
    private func stopSyncing(_ reason: SyncStatus) {
        Self.log.notice("Syncing stopped: \(String(describing: reason), privacy: .public)")
        if let onSyncStopped { onSyncStopped() } else { setSyncing(false) }
        // After the switch, which clears the status on its way down.
        syncStatus = reason
    }

    private func observeSyncEvents() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event
            else { return }
            let isImport = event.type == .import
            let ended = event.endDate
            let succeeded = event.succeeded
            let error = event.error
            MainActor.assumeIsolated {
                guard let self else { return }
                if let ended {
                    self.finished(isImport: isImport, at: ended, succeeded: succeeded, error: error)
                } else if isImport {
                    self.importStarted()
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.wantsSyncing else { return }
                self.checkAccount()
            }
        })
    }

    /// Takes down the library as it stands before an import lands in it, so
    /// the import can be held up against it when it ends.
    private func importStarted() {
        guard isSyncing else { return }
        do {
            beforeImport = try Self.archive(in: context)
        } catch {
            Self.log.error("Library could not be read before an import: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func finished(isImport: Bool, at date: Date, succeeded: Bool, error: (any Error)?) {
        guard isSyncing else { return }
        let before = isImport ? beforeImport : nil
        if isImport { beforeImport = nil }
        guard succeeded else {
            let status = Self.status(for: error)
            // Left syncing, SwiftData would make the zone again and send the
            // whole library back into it, undoing what the reader just did.
            if status == .cloudDataDeleted { stopSyncing(status) } else { syncStatus = status }
            // Part of a failed import may still have landed.
            if isImport { onRemoteChanges?() }
            return
        }
        syncStatus = .synced
        lastSynced = date
        guard isImport else { return }
        do {
            // First, so what an older build wrote on a row is in its own
            // record before that row can be folded away.
            let adopted = try Self.adoptLegacyRecords(in: context)
            let folded = try Self.deduplicate(in: context)
            let outcome = try before.map { try Self.settleImport(against: $0, in: context) }
            // This device's own records coming back, cut to the millisecond:
            // nothing to read again, redraw or mirror. Left to go on, every save
            // cost a pass over the whole library a few seconds after it.
            if !adopted, !folded, let outcome, !outcome.wrote, !outcome.landed { return }
        } catch {
            Self.log.error("Library could not be settled after an import: \(error.localizedDescription, privacy: .public)")
        }
        onRemoteChanges?()
    }

    static func status(for error: (any Error)?) -> SyncStatus {
        guard let error else { return .failed(String(localized: "iCloud did not say why")) }
        let ckError = error as? CKError
        // Usually one record's answer inside a partial failure, not the whole.
        let partial = ckError?.partialErrorsByItemID?.values.compactMap { ($0 as? CKError)?.code } ?? []
        if ckError?.code == .userDeletedZone || partial.contains(.userDeletedZone) { return .cloudDataDeleted }
        switch ckError?.code {
        case .notAuthenticated: return .signedOut
        case .quotaExceeded: return .iCloudFull
        case .networkUnavailable, .networkFailure: return .offline
        case .serviceUnavailable, .requestRateLimited, .zoneBusy, .accountTemporarilyUnavailable:
            return .unavailable
        default: return .failed(error.localizedDescription)
        }
    }

    // MARK: - Rows and the archive

    /// The whole store as one archive — for a backup, a restore, and anything
    /// else that settles the library by ``LibraryArchive``'s rules.
    static func archive(in context: ModelContext) throws -> LibraryArchive {
        var slices: [LibraryArchive] = []
        let events = try context.fetch(FetchDescriptor<LibraryEvent>())
        slices += events.compactMap(\.slice)
        slices += try context.fetch(FetchDescriptor<LibraryMembership>()).compactMap(\.slice)
        slices += try context.fetch(FetchDescriptor<FollowingReadMark>()).compactMap(\.slice)
        // After the records, so a record and the copy an older build reads,
        // alike to the moment, settle on the record — and a copy that is
        // older, sent by a device that had not heard of a later change, loses.
        slices += events.compactMap(\.legacyMembership)
        slices += events.compactMap(\.legacyRead)
        slices += try context.fetch(FetchDescriptor<FollowedPerformer>()).compactMap(\.slice)
        slices += try context.fetch(FetchDescriptor<LibrarySettings>()).compactMap(\.slice)
        return LibraryArchive().merging(contentsOf: slices)
    }

    /// Makes the store say what `archive` says: a row for every record it
    /// holds, and none for anything it does not. Only a row whose record
    /// actually changed is written, since every one written is sent again.
    ///
    /// Not saved; the caller saves.
    @discardableResult
    static func apply(_ archive: LibraryArchive, to context: ModelContext) throws -> Bool {
        let events = Dictionary(try context.fetch(FetchDescriptor<LibraryEvent>()).map { ($0.eventID, $0) },
                                uniquingKeysWith: { first, _ in first })
        let memberships = Dictionary(try context.fetch(FetchDescriptor<LibraryMembership>()).map { ($0.eventID, $0) },
                                     uniquingKeysWith: { first, _ in first })
        let marks = Dictionary(try context.fetch(FetchDescriptor<FollowingReadMark>()).map { ($0.eventID, $0) },
                               uniquingKeysWith: { first, _ in first })
        let performers = Dictionary(try context.fetch(FetchDescriptor<FollowedPerformer>()).map { (String($0.actorID), $0) },
                                    uniquingKeysWith: { first, _ in first })
        let settings = try context.fetch(FetchDescriptor<LibrarySettings>()).first

        var keys = archive.recordKeys
        keys.formUnion(events.keys.map { .event($0) })
        keys.formUnion(memberships.keys.map { .membership($0) })
        keys.formUnion(marks.keys.map { .read($0) })
        keys.formUnion(performers.keys.map { .performer($0) })
        if settings != nil { keys.insert(.settings) }

        var changed = false
        for key in keys {
            let wanted = archive.slice(for: key)
            switch key {
            case .event(let id):
                changed = write(wanted, into: events[id], in: context) { LibraryEvent(eventID: id) } || changed
            case .membership(let id):
                changed = write(wanted, into: memberships[id], in: context) { LibraryMembership(eventID: id) } || changed
            case .read(let id):
                changed = write(wanted, into: marks[id], in: context) { FollowingReadMark(eventID: id) } || changed
            case .performer(let id):
                guard let actorID = Int(id) else {
                    log.error("A follow under \(id, privacy: .public) is no actor id; left out.")
                    continue
                }
                changed = write(wanted, into: performers[id], in: context) { FollowedPerformer(actorID: actorID) } || changed
            case .settings:
                changed = write(wanted, into: settings, in: context) { LibrarySettings() } || changed
            }
        }
        return changed
    }

    private static func write<Row: ArchiveRow>(
        _ wanted: LibraryArchive?, into row: Row?, in context: ModelContext, making: () -> Row
    ) -> Bool {
        switch (wanted, row) {
        case (nil, nil):
            return false
        case (nil, let row?):
            guard row.holdsLegacyRecord else {
                context.delete(row)
                return true
            }
            guard row.slice != nil else { return false }
            row.take(LibraryArchive())
            return true
        case (let wanted?, let row?):
            guard row.slice?.toTheMillisecond != wanted.toTheMillisecond else { return false }
            row.take(wanted)
            return true
        case (let wanted?, nil):
            let row = making()
            context.insert(row)
            row.take(wanted)
            return true
        }
    }

    /// Folds every set of rows about one thing into one.
    ///
    /// Their records are merged by the rules two devices' copies always were,
    /// and written into the row with the lowest `uid`; the others go. Every
    /// device picks the same survivor, so two of them folding the same pair at
    /// once end in the same row rather than deleting each other's.
    @discardableResult
    static func deduplicate(in context: ModelContext) throws -> Bool {
        var changed = try fold(LibraryEvent.self, by: \.eventID, in: context)
        changed = try fold(LibraryMembership.self, by: \.eventID, in: context) || changed
        changed = try fold(FollowingReadMark.self, by: \.eventID, in: context) || changed
        changed = try fold(FollowedPerformer.self, by: \.actorID, in: context) || changed
        changed = try fold(LibrarySettings.self, by: { _ in 0 }, in: context) || changed
        if changed { try context.save() }
        return changed
    }

    private static func fold<Row: ArchiveRow, Key: Hashable>(
        _ type: Row.Type, by key: (Row) -> Key, in context: ModelContext
    ) throws -> Bool {
        let rows = try context.fetch(FetchDescriptor<Row>())
        var changed = false
        for group in Dictionary(grouping: rows, by: key).values where group.count > 1 {
            let ordered = group.sorted { $0.uid.uuidString < $1.uid.uuidString }
            let merged = LibraryArchive().merging(records: ordered.compactMap(\.slice))
            let survivor = ordered[0]
            survivor.keepLegacyRecords(of: Array(ordered.dropFirst()))
            for extra in ordered.dropFirst() { context.delete(extra) }
            if merged.slice(for: survivor.key) == nil, !survivor.holdsLegacyRecord {
                context.delete(survivor)
            } else {
                survivor.take(merged)
            }
            changed = true
        }
        return changed
    }

    /// Puts back what an import overwrote with something older.
    ///
    /// CloudKit settles two devices' edits to one record by which reached it
    /// last, not by when they were made: a note typed offline yesterday and
    /// sent today lands over one typed this morning, and a removal can lose to
    /// the yes it replaced. Every row still carries its stamps, so each one the
    /// import touched is merged with what this device held before it —
    /// `before` — by ``LibraryArchive``'s own rules, the import's copy kept
    /// wherever the two tie. Only a row the merge changes is written, and that
    /// write is sent on like any other, so the device that sent the older copy
    /// takes the newer back and every device settles on the same answers.
    ///
    /// A row the import deleted comes back where this device still holds
    /// something in it that pruning keeps. CloudKit's delete is unconditional:
    /// a device pruning a row whose Following read had gone deletes it even
    /// when another device has just put the same event in its library, and
    /// the removal would otherwise reach every device. Another device deletes
    /// a row only when pruning leaves it nothing, or when folding it into a
    /// twin whose key is still here — so what survives pruning in `before`
    /// (already pruned, as ``archive(in:)`` makes it) is what was lost to the
    /// race. The row made for it is sent like any other.
    @discardableResult
    static func reconcile(_ before: LibraryArchive, in context: ModelContext) throws -> Bool {
        try settleImport(against: before, in: context).wrote
    }

    /// What an import came to: whether this device wrote anything back, and
    /// whether anything landed at all — an import can be nothing but this
    /// device's own records coming back cut to the millisecond.
    struct ImportOutcome {
        var wrote = false
        var landed = false
    }

    /// ``reconcile(_:in:)``, saying as well whether the import changed anything.
    static func settleImport(against before: LibraryArchive, in context: ModelContext) throws -> ImportOutcome {
        var present = Set<LibraryArchive.RecordKey>()
        var outcome = ImportOutcome()
        try reconcile(LibraryEvent.self, with: before, present: &present, outcome: &outcome, in: context)
        try reconcile(LibraryMembership.self, with: before, present: &present, outcome: &outcome, in: context)
        try reconcile(FollowingReadMark.self, with: before, present: &present, outcome: &outcome, in: context)
        try reconcile(FollowedPerformer.self, with: before, present: &present, outcome: &outcome, in: context)
        try reconcile(LibrarySettings.self, with: before, present: &present, outcome: &outcome, in: context)
        var changed = outcome.wrote
        for key in before.recordKeys.subtracting(present) {
            outcome.landed = true
            guard let held = before.slice(for: key) else { continue }
            switch key {
            case .event(let id):
                let row = LibraryEvent(eventID: id)
                context.insert(row)
                row.take(held)
            case .membership(let id):
                let row = LibraryMembership(eventID: id)
                context.insert(row)
                row.take(held)
            case .read(let id):
                let row = FollowingReadMark(eventID: id)
                context.insert(row)
                row.take(held)
            case .performer(let id):
                guard let actorID = Int(id) else { continue }
                let row = FollowedPerformer(actorID: actorID)
                context.insert(row)
                row.take(held)
            case .settings:
                let row = LibrarySettings()
                context.insert(row)
                row.take(held)
            }
            changed = true
        }
        if changed { try context.save() }
        outcome.wrote = changed
        return outcome
    }

    private static func reconcile<Row: ArchiveRow>(
        _ type: Row.Type, with before: LibraryArchive,
        present: inout Set<LibraryArchive.RecordKey>, outcome: inout ImportOutcome, in context: ModelContext
    ) throws {
        for row in try context.fetch(FetchDescriptor<Row>()) {
            present.insert(row.key)
            let held = before.slice(for: row.key)
            let arrived = row.slice
            guard let held, let arrived else {
                if held != nil || arrived != nil { outcome.landed = true }
                continue
            }
            guard arrived != held else { continue }
            if arrived.toTheMillisecond != held.toTheMillisecond { outcome.landed = true }
            guard var merged = arrived.merging(records: [held]).slice(for: row.key) else { continue }
            // The facts this device held stand only where its read of the page
            // is the later one. A tie left to the merge kept each device's own
            // copy, and two devices holding different ones sent them back and
            // forth for good.
            if case .event(let id) = row.key, merged.events[id] != nil,
               let landed = arrived.events[id], let mine = held.events[id],
               !isLaterRead(mine, than: landed) {
                merged.events[id] = landed
            }
            // Nothing but what CloudKit rounds away is no change at all.
            guard merged.toTheMillisecond != arrived.toTheMillisecond else { continue }
            row.take(merged)
            outcome.wrote = true
        }
    }

    /// Whether `mine` was read from the event's page after `theirs`, by more
    /// than the millisecond CloudKit keeps.
    private static func isLaterRead(_ mine: Event, than theirs: Event) -> Bool {
        guard mine.isDetailed else { return false }
        guard theirs.isDetailed else { return true }
        return (mine.readAt ?? .distantPast).toTheMillisecond > (theirs.readAt ?? .distantPast).toTheMillisecond
    }

    /// Drops what the archive would prune: a Following read whose night has
    /// gone, an event's facts once nothing keeps it, who a performer is once
    /// nobody follows them. Tombstones stay, for the reason
    /// ``LibraryArchive/pruned()`` gives.
    ///
    /// Pruned with the whole library in view — the archive the rows make,
    /// written back through ``apply(_:to:)``, which touches only the rows it
    /// changes — because no record can be pruned on its own: whether an
    /// event's facts are kept is up to its ``LibraryMembership``.
    @discardableResult
    static func prune(in context: ModelContext) throws -> Bool {
        let changed = try apply(archive(in: context), to: context)
        if changed { try context.save() }
        return changed
    }

    /// Takes what builds before ``LibraryMembership`` and ``FollowingReadMark``
    /// kept on an event's row — whether it is in the library, and whether its
    /// date was read — into those records, wherever the row's copy is the newer.
    ///
    /// The row's copy is newer only where a device still on such a build
    /// wrote it: this build mirrors each change it makes there with the
    /// record's own date, and a copy sent by a device that had not yet heard
    /// of a later change is older. Run as the store opens and after every
    /// import from iCloud. Newer means by more than the millisecond CloudKit
    /// keeps, so a copy taken in once is not taken in again.
    @discardableResult
    static func adoptLegacyRecords(in context: ModelContext) throws -> Bool {
        let rows = try context.fetch(FetchDescriptor<LibraryEvent>(
            predicate: #Predicate { $0.inLibraryChanged != nil || $0.readChanged != nil }))
        guard !rows.isEmpty else { return false }
        var memberships = Dictionary(try context.fetch(FetchDescriptor<LibraryMembership>()).map { ($0.eventID, $0) },
                                     uniquingKeysWith: { first, _ in first })
        var marks = Dictionary(try context.fetch(FetchDescriptor<FollowingReadMark>()).map { ($0.eventID, $0) },
                               uniquingKeysWith: { first, _ in first })
        var changed = false
        for row in rows {
            let id = row.eventID
            if let record = row.legacyMembership?.membership[id],
               !(memberships[id]?.membership.map { $0.modified.toTheMillisecond >= record.modified.toTheMillisecond } ?? false) {
                let membership = memberships[id] ?? LibraryMembership(eventID: id)
                if memberships[id] == nil {
                    context.insert(membership)
                    memberships[id] = membership
                }
                membership.membership = record
                changed = true
            }
            if let read = row.legacyRead?.pruned().followingReads?[id],
               !(marks[id]?.read.map { $0.modified.toTheMillisecond >= read.modified.toTheMillisecond } ?? false) {
                let mark = marks[id] ?? FollowingReadMark(eventID: id)
                if marks[id] == nil {
                    context.insert(mark)
                    marks[id] = mark
                }
                mark.read = read
                changed = true
            }
        }
        if changed { try context.save() }
        return changed
    }

    // MARK: - The library file this replaced

    /// Folds what the JSON library file still holds into the store, and moves
    /// the file aside once the store has it.
    ///
    /// Run every launch: the first time it moves the whole library in; after
    /// that there is no file, and it only folds back a copy an older build set
    /// aside unread (``LibraryFile/load()``). A merge rather than a copy, so a
    /// store that already holds records — synced in from another device —
    /// keeps whichever copy of each is newer.
    ///
    /// Answers what the read found, or nil while the file will not open.
    @discardableResult
    func moveIn(from file: LibraryFile) -> LibraryFile.Contents? {
        guard !isBlocked else { return nil }
        let contents = file.load()
        if !contents.archive.holdsNothing {
            do {
                let held = try Self.archive(in: context)
                try Self.apply(held.merging(contents.archive), to: context)
                try context.save()
            } catch {
                Self.log.error("Library file could not be moved in: \(error.localizedDescription, privacy: .public)")
                return contents
            }
            Self.log.notice("Moved the library file into the store.")
        }
        if !contents.isBlocked { file.retire() }
        file.discard(contents.recoveredCopies)
        Self.discardSyncEngineMemory()
        return contents
    }

    /// What the CloudKit sync this replaced kept between launches, which
    /// nothing reads any more.
    private static func discardSyncEngineMemory() {
        let url = URL.applicationSupportDirectory.appending(path: "Eventrail/cloudkit.json")
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// A row that stands for one record of the archive.
protocol ArchiveRow: PersistentModel {
    var uid: UUID { get }
    var key: LibraryArchive.RecordKey { get }
    var slice: LibraryArchive? { get }
    func take(_ archive: LibraryArchive)
    /// Whether the row stays though its record says nothing — see
    /// ``LibraryEvent/holdsLegacyRecord``.
    var holdsLegacyRecord: Bool { get }
    /// Takes what its twins keep for an older build before they are folded
    /// away — see ``LibraryEvent/keepLegacyRecords(of:)``.
    func keepLegacyRecords(of twins: [Self])
}

extension ArchiveRow {
    var holdsLegacyRecord: Bool { false }
    func keepLegacyRecords(of twins: [Self]) {}
}

extension LibraryEvent: ArchiveRow {}
extension LibraryMembership: ArchiveRow {}
extension FollowingReadMark: ArchiveRow {}
extension FollowedPerformer: ArchiveRow {}
extension LibrarySettings: ArchiveRow {
    var key: LibraryArchive.RecordKey { .settings }
}
