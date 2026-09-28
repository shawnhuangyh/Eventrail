import CloudKit
import CoreData
import Foundation
import OSLog
import SwiftData

/// Where the reader's library is kept, and how it reaches their other devices.
///
/// A SwiftData store in Application Support, holding one row per record —
/// ``LibraryEntry``, ``LibraryEvent``, ``FollowingReadMark``,
/// ``FollowedPerformer`` and ``LibrarySettings``. With iCloud Sync on,
/// SwiftData mirrors it into the reader's private CloudKit database by itself,
/// and nothing here second-guesses what it does: a record another device
/// wrote lands as CloudKit settled it. The rows are cut so that is always the
/// right answer — see ``LibraryEntry``. Off, the same store is opened with no
/// CloudKit at all. The switch is per device, so turning it opens the store
/// again the other way (``setSyncing(_:)``), and the screens reading it are
/// rebuilt on the new container (``generation``).
///
/// **Two devices can write two rows for one thing**, and nothing can stop
/// them: CloudKit has no unique constraint to refuse the second. So after
/// every import from iCloud, ``deduplicate(in:)`` keeps one and deletes the
/// rest — Apple's own answer to it — by a rule every device applies alike, so
/// they all keep the same one.
///
/// **A file that will not open is never written over.** The store is created
/// with the system's default protection, so before a device's first unlock it
/// will not open at all. The library is then kept in memory instead
/// (``isBlocked``), where the reader can go on using it, and ``reopen()``
/// tries the file again — folding whatever was written meanwhile into what
/// the file holds, by ``LibraryArchive``'s merge, once it opens.
@Observable
final class LibraryDatabase {
    static let containerID = "iCloud.moe.shawn.Eventrail"

    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "library")

    /// ``LibraryMembership`` is in it only so what the builds before
    /// ``LibraryEntry`` wrote can be read once and taken in.
    static let schema = Schema([LibraryEntry.self, LibraryEvent.self, FollowingReadMark.self,
                                FollowedPerformer.self, LibrarySettings.self, LibraryMembership.self])

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

        /// Whether it passes by itself once iCloud can be reached again, so any
        /// setup, import or export that succeeds has shown it over.
        var isPassing: Bool { self == .offline || self == .unavailable }
    }

    /// How the last setup, import and export each ended, and so how syncing
    /// stands.
    ///
    /// Kept apart because each answers for itself: an export that succeeds
    /// says nothing about the import that failed before it, and an import
    /// arriving from the other device says nothing about this one's changes
    /// that iCloud refused for want of space — which is how iCloud Full used
    /// to read as synced the moment the other device wrote anything.
    struct SyncOutcomes: Equatable {
        enum Kind: Hashable { case setup, `import`, export }

        private var failures: [Kind: SyncStatus] = [:]

        /// How syncing stands: what went wrong last, sending before fetching
        /// before setting up, or synced where nothing did.
        var status: SyncStatus {
            [.export, .import, .setup].lazy.compactMap { failures[$0] }.first ?? .synced
        }

        /// One setup, import or export has ended — failed with `failure`, or
        /// succeeded where that is nil.
        mutating func record(_ kind: Kind, failure: SyncStatus?) {
            if let failure {
                failures[kind] = failure
            } else {
                failures[kind] = nil
                failures = failures.filter { !$0.value.isPassing }
            }
        }
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
    /// What ``syncStatus`` is worked out from while syncing — see
    /// ``SyncOutcomes``.
    @ObservationIgnored private var outcomes = SyncOutcomes()
    /// When this device last fetched from iCloud: the end of the last import
    /// that succeeded, kept across launches.
    ///
    /// Not an export. Every launch and every return to the app sends
    /// whatever is waiting, usually nothing, and a time that moved with those
    /// said "just now" on a device that had not heard from the other one in
    /// minutes. What the reader wants to know from it is whether this device
    /// has the other one's changes, and only an import answers that.
    private(set) var lastFetched: Date? = UserDefaults.standard.object(forKey: LibraryDatabase.lastFetchedKey) as? Date {
        didSet { UserDefaults.standard.set(lastFetched, forKey: Self.lastFetchedKey) }
    }
    /// Whether the store is open with CloudKit. Not the switch: with the
    /// switch on, the store is opened without CloudKit until the iCloud user
    /// has been checked (``checkAccount()``).
    private(set) var isSyncing = false
    /// Whether the file would not open, so ``container`` is held in memory.
    private(set) var isBlocked = false
    /// The container this one replaced, kept for a moment so a screen still
    /// drawing one of its rows is not left holding a row whose store has gone
    /// — and only for a moment, since a CloudKit container kept alive goes on
    /// mirroring the file the new one writes to (``replace(with:mirroring:)``).
    @ObservationIgnored private var retired: ModelContainer?
    /// Whether ``container`` and ``retired`` were opened with CloudKit. A
    /// retired one goes on mirroring the file until it is let go, and holds
    /// this process's claim on the file until then (``syncingFiles``).
    @ObservationIgnored private var containerMirrors = false
    @ObservationIgnored private var retiredMirrors = false
    /// Whether syncing was turned on again while the container it was turned
    /// off from was still being let go, and waits for that.
    @ObservationIgnored private var startsWhenLetGo = false

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

    /// Which iCloud user this device's library syncs with (the container's
    /// user record name), written the first time syncing finds one. Per
    /// device, like the switch, and cleared when the switch goes off.
    private static let accountKey = "iCloudSyncAccount"
    /// Where this device last read the old sync's zone up to — see
    /// ``LegacyCloudZone``. Cleared with the account, since it belongs to one.
    private static let legacyTokenKey = "iCloudLegacyZoneToken"
    /// ``lastFetched``, per device. Cleared with the account, since it says
    /// when this device last heard from that account's iCloud.
    private static let lastFetchedKey = "iCloudLastFetched"

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
        if containerMirrors || retiredMirrors { releaseFile() }
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
        outcomes = SyncOutcomes()
        retry?.cancel()
        // Turned on, it is whichever account is signed in now that the reader
        // said yes to, so the record is written afresh.
        UserDefaults.standard.removeObject(forKey: Self.accountKey)
        UserDefaults.standard.removeObject(forKey: Self.legacyTokenKey)
        lastFetched = nil
        if syncing {
            checkAccount()
        } else {
            startsWhenLetGo = false
            guard isSyncing else { return }
            // The file stays claimed until the container that mirrored it is
            // let go (``replace(with:mirroring:)``), not until now.
            isSyncing = false
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
        // Turned off and on again within ``retiredHold``: the container it
        // was turned off from mirrors the file until it is let go, and a
        // second mirror now would be refused — so this waits for it.
        if retiredMirrors {
            startsWhenLetGo = true
            return
        }
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
        outcomes = SyncOutcomes()
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
            replace(with: opened, mirroring: isSyncing)
            isBlocked = false
        } catch where isSyncing {
            Self.log.error("Library could not be opened with CloudKit: \(error.localizedDescription, privacy: .public)")
            isSyncing = false
            releaseFile()
            syncStatus = .notConfigured
            if let opened = try? Self.makeContainer(at: location, syncing: false) {
                replace(with: opened, mirroring: false)
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
            try Self.settle(in: context)
            try Self.pruneReads(in: context)
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
        replace(with: Self.memoryContainer(), mirroring: false)
    }

    private func replace(with opened: ModelContainer, mirroring: Bool) {
        let outgoing = container
        // One still held from the last swap goes now.
        letGoOfRetired()
        retired = outgoing
        retiredMirrors = containerMirrors
        container = opened
        containerMirrors = mirroring
        generation += 1
        // Let go once the screens have drawn on the new one. The store keeps
        // its rows and the screens re-read it at once, but a container opened
        // with CloudKit and held after sync is turned off goes on importing
        // pushes and exporting whatever the new one writes to the same file —
        // so the off switch would not keep the library out of iCloud.
        Task { [weak self] in
            try? await Task.sleep(for: Self.retiredHold)
            guard let self, retired === outgoing else { return }
            letGoOfRetired()
        }
    }

    /// Drops the replaced container, and with a mirror its claim on the file
    /// — then starts syncing, if it was turned on again meanwhile.
    private func letGoOfRetired() {
        retired = nil
        guard retiredMirrors else { return }
        retiredMirrors = false
        if !containerMirrors { releaseFile() }
        guard startsWhenLetGo else { return }
        startsWhenLetGo = false
        // Not from here, which may be the middle of a swap.
        Task { [weak self] in self?.startSyncing() }
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
            let kind: SyncOutcomes.Kind = switch event.type {
            case .import: .import
            case .export: .export
            default: .setup
            }
            let succeeded = event.succeeded
            let error = event.error
            guard let ended = event.endDate else { return }
            MainActor.assumeIsolated {
                self?.finished(kind, at: ended, succeeded: succeeded, error: error)
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

    /// An import or an export has ended. After an import, what landed is
    /// taken as it landed: the only things done to it are taking in what an
    /// older build left there and folding two rows for one thing into one
    /// (``settle(in:)``). Then the screens and the calendar are told, whatever
    /// the import brought — even a failed one may have landed part of what it
    /// read.
    private func finished(_ kind: SyncOutcomes.Kind, at date: Date, succeeded: Bool, error: (any Error)?) {
        guard isSyncing else { return }
        let failure = succeeded ? nil : Self.status(for: error)
        if succeeded, kind == .import { lastFetched = date }
        if failure == .cloudDataDeleted {
            // Left syncing, SwiftData would make the zone again and send the
            // whole library back into it, undoing what the reader just did.
            stopSyncing(.cloudDataDeleted)
        } else {
            outcomes.record(kind, failure: failure)
            syncStatus = outcomes.status
        }
        guard kind == .import else { return }
        do {
            try Self.settle(in: context)
        } catch {
            Self.log.error("Library could not be folded after an import: \(error.localizedDescription, privacy: .public)")
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

    // MARK: - Tidying

    /// What is done to the store every time it opens and after every import
    /// from iCloud: what an older build left is taken in where nothing answers
    /// for it yet (``adoptLegacyRecords(in:)``), then two rows for one thing
    /// are folded into one (``deduplicate(in:)``).
    static func settle(in context: ModelContext) throws {
        try adoptLegacyRecords(in: context)
        try deduplicate(in: context)
    }

    /// Keeps one row of every set about one thing, and deletes the rest.
    ///
    /// Which one is kept is up to each model's `isPreferred` — the entry the
    /// reader wrote last, the fullest copy of an event's page, the mark or
    /// follow written last — with the lower `uid` breaking a tie, so every
    /// device keeps the same row and none deletes the one another kept.
    ///
    /// Two kinds are folded rather than dropped. An entry kept takes from the
    /// others every part they gave later (``LibraryEntry/absorb(_:)``): each
    /// was written by a device that had not seen the other's, so the one
    /// written last is not the reader's word on the parts it never gave — an
    /// import that added an event before the entry holding its note had
    /// arrived would otherwise have deleted the note on every device. And the
    /// settings, two rows of which are ordinary, are folded field by field
    /// (``LibrarySettings/absorb(_:)``).
    @discardableResult
    static func deduplicate(in context: ModelContext) throws -> Bool {
        var changed = try keepOne(of: LibraryEntry.self, by: \.eventID,
                                  preferring: LibraryEntry.isPreferred,
                                  folding: { $0.absorb($1) }, in: context)
        changed = try keepOne(of: LibraryEvent.self, by: \.eventID,
                              preferring: LibraryEvent.isPreferred, in: context) || changed
        changed = try keepOne(of: FollowingReadMark.self, by: \.eventID,
                              preferring: FollowingReadMark.isPreferred, in: context) || changed
        changed = try keepOne(of: FollowedPerformer.self, by: \.actorID,
                              preferring: FollowedPerformer.isPreferred, in: context) || changed
        let settings = try context.fetch(FetchDescriptor<LibrarySettings>())
            .sorted(by: LibrarySettings.isPreferred)
        if let kept = settings.first, settings.count > 1 {
            for extra in settings.dropFirst() {
                kept.absorb(extra)
                context.delete(extra)
            }
            changed = true
        }
        if changed { try context.save() }
        return changed
    }

    private static func keepOne<Row: PersistentModel, Key: Hashable>(
        of type: Row.Type, by key: (Row) -> Key, preferring: (Row, Row) -> Bool,
        folding fold: ((_ kept: Row, _ extra: Row) -> Void)? = nil, in context: ModelContext
    ) throws -> Bool {
        let rows = try context.fetch(FetchDescriptor<Row>())
        var changed = false
        for group in Dictionary(grouping: rows, by: key).values where group.count > 1 {
            let sorted = group.sorted(by: preferring)
            for extra in sorted.dropFirst() {
                fold?(sorted[0], extra)
                context.delete(extra)
                changed = true
            }
        }
        return changed
    }

    /// The row every screen and every write should use for each thing — the
    /// one ``deduplicate(in:)`` will keep, so nothing written between an
    /// import and its fold lands on a row about to go.
    static func index<Row, Key: Hashable>(
        _ rows: [Row], by key: (Row) -> Key, preferring: (Row, Row) -> Bool
    ) -> [Key: Row] {
        Dictionary(rows.map { (key($0), $0) }, uniquingKeysWith: { preferring($0, $1) ? $0 : $1 })
    }

    /// Deletes the Following reads of nights that have been — the tab no
    /// longer lists them, and nothing will read them again. By the night
    /// rather than by the stamp, so every device drops the same marks; a few
    /// days' grace covers a device whose clock or zone disagrees with the
    /// hall's.
    @discardableResult
    static func pruneReads(in context: ModelContext, asOf now: Date = .now) throws -> Bool {
        let over = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let gone = try context.fetch(FetchDescriptor<FollowingReadMark>(predicate: #Predicate { $0.day <= over }))
        guard !gone.isEmpty else { return false }
        for mark in gone { context.delete(mark) }
        try context.save()
        return true
    }

    /// Takes what the builds before ``LibraryEntry`` kept — whether an event
    /// was in the library (in a ``LibraryMembership``, or on the event's own
    /// row before that), the heart and the tracking record on the row, and
    /// the Following read on the row before ``FollowingReadMark`` — into the
    /// records this build keeps, wherever there is none yet.
    ///
    /// Run every time the store opens and after every import, not once per
    /// device: what an older build left in iCloud reaches a device reinstalled
    /// or newly set up only after the store has first opened, empty. Never
    /// over an entry or a mark already there — those are this build's answers
    /// — so after the first run it usually finds nothing to do. Each device
    /// takes in its own copy, so the entries two of them make for one event
    /// meet in ``deduplicate(in:)``.
    @discardableResult
    static func adoptLegacyRecords(in context: ModelContext) throws -> Bool {
        let entries = Set(try context.fetch(FetchDescriptor<LibraryEntry>()).map(\.eventID))
        let marks = Set(try context.fetch(FetchDescriptor<FollowingReadMark>()).map(\.eventID))
        // Only rows something here does not already answer for.
        let rows = try context.fetch(FetchDescriptor<LibraryEvent>()).filter { row in
            (!entries.contains(row.eventID)
                && (row.inLibraryChanged != nil || row.favoriteChanged != nil || row.trackingChanged != nil))
                || (!marks.contains(row.eventID) && row.readChanged != nil)
        }
        let memberships = try context.fetch(FetchDescriptor<LibraryMembership>()).compactMap { membership in
            membership.changed.flatMap { changed -> LibraryArchive? in
                guard !entries.contains(membership.eventID) else { return nil }
                var slice = LibraryArchive()
                slice.membership[membership.eventID] = Stamped(membership.inLibrary, at: changed)
                return slice
            }
        }
        guard !rows.isEmpty || !memberships.isEmpty else { return false }
        // Folded in one pass: a merge per row copies the whole archive.
        let legacy = LibraryArchive().merging(records: rows.map(\.legacyRecords) + memberships)
        // No facts: those are on the rows already, and every row written here
        // would be sent again for nothing. An entry takes its copy of the
        // event from its row (``apply(_:to:)``).
        var adopted = LibraryArchive()
        for id in Set(legacy.membership.keys).union(legacy.favorites.keys).union(legacy.tracking.keys)
        where !entries.contains(id) {
            adopted.membership[id] = legacy.membership[id]
            adopted.favorites[id] = legacy.favorites[id]
            adopted.tracking[id] = legacy.tracking[id]
        }
        adopted.followingReads = legacy.followingReads?.filter { !marks.contains($0.key) }
        // Nor the reads of nights that have been, which would only be deleted
        // again by ``pruneReads(in:asOf:)``.
        adopted = adopted.pruned()
        guard !adopted.membership.isEmpty || !adopted.favorites.isEmpty || !adopted.tracking.isEmpty
                || !(adopted.followingReads ?? [:]).isEmpty
        else { return false }
        try apply(adopted, to: context)
        try context.save()
        log.notice("Took what an older build kept into \(adopted.membership.count) entries.")
        return true
    }

    // MARK: - The library as one archive

    /// The whole store as one archive — for a backup, a restore, and the
    /// files and zones older builds left, all of which are settled by
    /// ``LibraryArchive``'s rules. Each of an entry's three records carries
    /// its own part's date (``LibraryEntry/changed(_:)``).
    static func archive(in context: ModelContext) throws -> LibraryArchive {
        var archive = LibraryArchive()
        let rows = index(try context.fetch(FetchDescriptor<LibraryEvent>()), by: \.eventID,
                         preferring: LibraryEvent.isPreferred)
        for (id, row) in rows {
            if let facts = row.facts { archive.events[id] = facts }
        }
        let entries = index(try context.fetch(FetchDescriptor<LibraryEntry>()), by: \.eventID,
                            preferring: LibraryEntry.isPreferred)
        for (id, entry) in entries {
            archive.membership[id] = Stamped(entry.inLibrary, at: entry.changed(.inLibrary))
            archive.favorites[id] = Stamped(entry.isFavorite, at: entry.changed(.favorite))
            archive.tracking[id] = Stamped(entry.tracking, at: entry.changed(.tracking))
            if archive.events[id] == nil { archive.events[id] = entry.kept }
        }
        let marks = index(try context.fetch(FetchDescriptor<FollowingReadMark>()), by: \.eventID,
                          preferring: FollowingReadMark.isPreferred)
        archive.followingReads = marks.compactMapValues(\.read)
        let performers = index(try context.fetch(FetchDescriptor<FollowedPerformer>()), by: \.actorID,
                               preferring: FollowedPerformer.isPreferred)
        archive.follows = Dictionary(uniqueKeysWithValues: performers.compactMap { id, row in
            row.follow.map { (String(id), $0) }
        })
        archive.followedPerformers = Dictionary(uniqueKeysWithValues: performers.compactMap { id, row in
            row.profile.map { (String(id), $0) }
        })
        if let settings = try context.fetch(FetchDescriptor<LibrarySettings>())
            .sorted(by: LibrarySettings.isPreferred).first {
            archive.recentSearches = settings.searches
            archive.eventernoteAccount = settings.eventernoteAccount
            archive.eventernoteProfile = settings.eventernoteProfile
            archive.lastRefreshed = settings.lastRefreshed
            archive.lastImported = settings.lastImported
        }
        return archive.pruned()
    }

    /// Writes what `archive` holds into the rows, touching only those whose
    /// answer moves. Additive: a row the archive says nothing about is left
    /// alone, since every caller hands in the library merged with what it is
    /// taking in — a restore adds, it never erases.
    ///
    /// Each part of an entry written here takes its own record's date, and
    /// the entry the newest of them, so what a restore raises as of now
    /// outranks every device's older copy.
    ///
    /// Not saved; the caller saves.
    @discardableResult
    static func apply(_ archive: LibraryArchive, to context: ModelContext) throws -> Bool {
        var rows = index(try context.fetch(FetchDescriptor<LibraryEvent>()), by: \.eventID,
                         preferring: LibraryEvent.isPreferred)
        let entries = index(try context.fetch(FetchDescriptor<LibraryEntry>()), by: \.eventID,
                            preferring: LibraryEntry.isPreferred)
        let marks = index(try context.fetch(FetchDescriptor<FollowingReadMark>()), by: \.eventID,
                          preferring: FollowingReadMark.isPreferred)
        let performers = index(try context.fetch(FetchDescriptor<FollowedPerformer>()), by: \.actorID,
                               preferring: FollowedPerformer.isPreferred)
        var changed = false

        for (id, event) in archive.events where rows[id]?.facts != event {
            let row = rows[id] ?? LibraryEvent(eventID: id)
            if rows[id] == nil {
                context.insert(row)
                rows[id] = row
            }
            row.write(event)
            changed = true
        }

        let ids = Set(archive.membership.keys).union(archive.favorites.keys).union(archive.tracking.keys)
        for id in ids {
            let held = entries[id]
            // Only what the archive holds is taken: an answer it has no record
            // of stays as this device has it.
            var answers = held?.answers ?? LibraryEntry.Answers()
            if let membership = archive.membership[id] { answers.inLibrary = membership.value }
            if let favorite = archive.favorites[id] { answers.isFavorite = favorite.value }
            if let tracking = archive.tracking[id] {
                answers.tracking = tracking.value
                answers.tracking.edits = [:]
            }
            guard held?.answers != answers else { continue }
            // An event nobody said anything about needs no entry to say so.
            guard held != nil || !answers.isEmpty else { continue }
            let entry = held ?? LibraryEntry(eventID: id)
            if held == nil { context.insert(entry) }
            let records: [LibraryEntry.Part: Date?] = [.inLibrary: archive.membership[id]?.modified,
                                                       .favorite: archive.favorites[id]?.modified,
                                                       .tracking: archive.tracking[id]?.modified]
            // A new entry is dated by every record the archive holds for it —
            // a removal is an answer too — and one already here only by the
            // parts that move.
            let moved = Set(answers.parts(differingFrom: held?.answers ?? LibraryEntry.Answers()))
            let dates = records.compactMapValues { $0 }.filter { held == nil || moved.contains($0.key) }
            entry.give(answers, dated: dates)
            let written = dates.values.max() ?? .now
            // Never older than it was, or another device's older copy would
            // outrank it in the fold.
            entry.modified = max(entry.modified, written.toTheMillisecond)
            if let event = rows[id]?.facts ?? archive.events[id] { entry.kept = event }
            changed = true
        }

        for (id, read) in archive.followingReads ?? [:] where marks[id]?.read != read {
            let mark = marks[id] ?? FollowingReadMark(eventID: id)
            if marks[id] == nil { context.insert(mark) }
            mark.read = read
            changed = true
        }

        for (key, follow) in archive.follows ?? [:] {
            guard let actorID = Int(key) else {
                log.error("A follow under \(key, privacy: .public) is no actor id; left out.")
                continue
            }
            let profile = archive.followedPerformers?[key]
            let row = performers[actorID]
            guard row?.follow != follow || (profile != nil && row?.profile != profile) else { continue }
            let written = row ?? FollowedPerformer(actorID: actorID)
            if row == nil { context.insert(written) }
            written.follow = follow
            if let profile { written.profile = profile } else if !follow.value { written.profile = nil }
            changed = true
        }

        let settingsRows = try context.fetch(FetchDescriptor<LibrarySettings>()).sorted(by: LibrarySettings.isPreferred)
        let held = settingsRows.first
        let wanted = (archive.recentSearches, archive.eventernoteAccount, archive.eventernoteProfile,
                      archive.lastRefreshed, archive.lastImported)
        let holds = held.map { ($0.searches, $0.eventernoteAccount, $0.eventernoteProfile,
                                $0.lastRefreshed, $0.lastImported) }
        let saysSomething = archive.recentSearches.modified != .distantPast || archive.eventernoteAccount != nil
            || archive.lastRefreshed != nil || archive.lastImported != nil
        if saysSomething, holds.map({ $0 != wanted }) ?? true {
            let settings = held ?? LibrarySettings()
            if held == nil { context.insert(settings) }
            settings.searches = archive.recentSearches
            settings.eventernoteAccount = archive.eventernoteAccount
            settings.eventernoteProfile = archive.eventernoteProfile
            settings.lastRefreshed = archive.lastRefreshed
            settings.lastImported = archive.lastImported
            changed = true
        }
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
