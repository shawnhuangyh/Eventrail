import CloudKit
import CoreData
import Foundation
import OSLog
import SwiftData

/// Where the reader's library is kept, and how it reaches their other devices.
///
/// A SwiftData store in Application Support, holding one row per record —
/// ``LibraryEvent``, ``FollowedPerformer`` and ``LibrarySettings``. With
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

    static let schema = Schema([LibraryEvent.self, FollowedPerformer.self, LibrarySettings.self])

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
    /// Whether the store is open with CloudKit.
    private(set) var isSyncing: Bool
    /// Whether the file would not open, so ``container`` is held in memory.
    private(set) var isBlocked = false
    /// The container this one replaced, kept until the next is opened so a
    /// screen still drawing one of its rows is not left holding a row whose
    /// store has gone.
    @ObservationIgnored private var retired: ModelContainer?

    /// Run once another device's changes have landed and been folded in.
    @ObservationIgnored var onRemoteChanges: (() -> Void)?

    @ObservationIgnored private let location: Location
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    init(at location: Location = LibraryDatabase.defaultLocation, syncing: Bool) {
        self.location = location
        isSyncing = syncing && location != .memory
        container = Self.memoryContainer()
        open()
        observeSyncEvents()
        if isSyncing { checkAccount() }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
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

    /// Opens the store with CloudKit, or without it.
    func setSyncing(_ syncing: Bool) {
        guard location != .memory, syncing != isSyncing else { return }
        try? context.save()
        isSyncing = syncing
        syncStatus = nil
        open()
        if syncing { checkAccount() }
    }

    private func open() {
        // What was written while the file would not open, to be folded in.
        let meanwhile = isBlocked ? try? Self.archive(in: context) : nil
        try? context.save()
        do {
            let opened = try Self.makeContainer(at: location, syncing: isSyncing)
            replace(with: opened)
            isBlocked = false
        } catch where isSyncing {
            Self.log.error("Library could not be opened with CloudKit: \(error.localizedDescription, privacy: .public)")
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
        guard !isBlocked else { return }
        do {
            if let meanwhile, !meanwhile.holdsNothing {
                let held = try Self.archive(in: context)
                try Self.apply(held.merging(meanwhile), to: context)
                try context.save()
            }
            try Self.deduplicate(in: context)
            try Self.prune(in: context)
        } catch {
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
        retired = container
        container = opened
        generation += 1
    }

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

    /// Says early what an import would only say by failing: no account, or
    /// one iCloud cannot reach.
    private func checkAccount() {
        Task {
            let status = try? await CKContainer(identifier: Self.containerID).accountStatus()
            guard isSyncing else { return }
            switch status {
            case .noAccount: syncStatus = .signedOut
            case .restricted, .temporarilyUnavailable: syncStatus = .unavailable
            default: break
            }
        }
    }

    private func observeSyncEvents() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  let ended = event.endDate
            else { return }
            let isImport = event.type == .import
            let succeeded = event.succeeded
            let error = event.error
            MainActor.assumeIsolated {
                self?.finished(isImport: isImport, at: ended, succeeded: succeeded, error: error)
            }
        }
    }

    private func finished(isImport: Bool, at date: Date, succeeded: Bool, error: (any Error)?) {
        guard isSyncing else { return }
        guard succeeded else {
            syncStatus = Self.status(for: error)
            return
        }
        syncStatus = .synced
        lastSynced = date
        guard isImport else { return }
        do {
            try Self.deduplicate(in: context)
        } catch {
            Self.log.error("Library could not be deduplicated: \(error.localizedDescription, privacy: .public)")
        }
        onRemoteChanges?()
    }

    static func status(for error: (any Error)?) -> SyncStatus {
        guard let error else { return .failed(String(localized: "iCloud did not say why")) }
        switch (error as? CKError)?.code {
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
        slices += try context.fetch(FetchDescriptor<LibraryEvent>()).compactMap(\.slice)
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
        let performers = Dictionary(try context.fetch(FetchDescriptor<FollowedPerformer>()).map { (String($0.actorID), $0) },
                                    uniquingKeysWith: { first, _ in first })
        let settings = try context.fetch(FetchDescriptor<LibrarySettings>()).first

        var keys = archive.recordKeys
        keys.formUnion(events.keys.map { .event($0) })
        keys.formUnion(performers.keys.map { .performer($0) })
        if settings != nil { keys.insert(.settings) }

        var changed = false
        for key in keys {
            let wanted = archive.slice(for: key)
            switch key {
            case .event(let id):
                changed = write(wanted, into: events[id], in: context) { LibraryEvent(eventID: id) } || changed
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
            context.delete(row)
            return true
        case (let wanted?, let row?):
            guard row.slice != wanted else { return false }
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
            let merged = LibraryArchive().merging(contentsOf: ordered.compactMap(\.slice))
            for extra in ordered.dropFirst() { context.delete(extra) }
            let survivor = ordered[0]
            if merged.slice(for: survivor.key) == nil {
                context.delete(survivor)
            } else {
                survivor.take(merged)
            }
            changed = true
        }
        return changed
    }

    /// Drops what the archive would prune: a Following read whose night has
    /// gone, and an event's facts once nothing keeps it. Tombstones stay, for
    /// the reason ``LibraryArchive/pruned()`` gives.
    @discardableResult
    static func prune(in context: ModelContext) throws -> Bool {
        var changed = false
        for row in try context.fetch(FetchDescriptor<LibraryEvent>()) {
            guard let slice = row.slice else { continue }
            let pruned = slice.pruned().slice(for: row.key)
            guard pruned != slice else { continue }
            if let pruned {
                row.take(pruned)
            } else {
                context.delete(row)
            }
            changed = true
        }
        for row in try context.fetch(FetchDescriptor<FollowedPerformer>()) {
            guard let slice = row.slice else { continue }
            let pruned = slice.pruned().slice(for: row.key)
            guard pruned != slice else { continue }
            if let pruned { row.take(pruned) } else { context.delete(row) }
            changed = true
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
}

extension LibraryEvent: ArchiveRow {}
extension FollowedPerformer: ArchiveRow {}
extension LibrarySettings: ArchiveRow {
    var key: LibraryArchive.RecordKey { .settings }
}
