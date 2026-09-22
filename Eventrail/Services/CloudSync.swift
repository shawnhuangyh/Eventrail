import Foundation
import OSLog

/// Mirrors the reader's library through their own iCloud.
///
/// The key-value store fits what this is: one small document the reader owns,
/// on their own devices, with no app-operated backend and no account to create.
/// It brings a hard 1MB quota with it, so the archive is compressed and measured
/// before it is written — a silent overflow would look exactly like syncing.
///
/// Nothing imported from Eventernote is private, but the reader's notes are, and
/// the key-value store is per-user and per-app: it is their iCloud, not a shared
/// one.
nonisolated struct CloudSync: Sendable {
    static let shared = CloudSync()

    /// One key holds the whole archive. It is merged, never replaced, so the
    /// store arbitrating by last write does not decide anything on its own.
    private static let key = "library.v1"

    /// Apple's documented ceiling is 1MB for everything this app stores. The
    /// margin leaves room for the store's own bookkeeping.
    static let quota = 900_000

    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "sync")

    /// What a push to iCloud did, in terms the Me screen can state plainly.
    enum Outcome: Sendable, Equatable {
        case synced
        /// The build carries no `ubiquity-kvstore` entitlement, so the store
        /// accepts writes and drops them. Without this case the screen would
        /// report a sync that never happened.
        case notConfigured
        /// No iCloud account on this device, so there is nowhere to sync to.
        case signedOut
        /// The store took the value and then refused to hand it on. Distinct
        /// from ``notConfigured``, which the entitlement settles before a byte
        /// is written: a refusal at this point is iCloud's, not the build's,
        /// and telling the reader to go and enable a capability would send them
        /// after something that is already there.
        case rejected
        /// This device was signed in to a different iCloud account, so what it
        /// holds is no longer this store's to hand over. Syncing stops until
        /// the reader says otherwise — see ``EventStore/cloudAccountChanged()``.
        case accountChanged
        /// The library outgrew the key-value store's quota.
        case tooLarge(bytes: Int)
        case failed(String)
    }

    /// The archive as iCloud will hold it: encoded, compressed, and measured.
    ///
    /// Made apart from the write because it is the expensive half — a JSON
    /// encode and a zlib pass over the whole library — and the write itself is
    /// a moment on the main actor. A caller with a thread to spare packs there
    /// and hands the result to ``save(_:)-(Payload)``.
    enum Payload: Sendable {
        case ready(Data)
        case failed(String)

        var bytes: Int? {
            if case .ready(let data) = self { return data.count }
            return nil
        }
    }

    /// Whether this device is signed in to iCloud at all.
    var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Whether this build may use the key-value store at all.
    ///
    /// `synchronize()` is the only signal the framework offers: it returns false
    /// when the entitlement is missing. Without the check a build signed without
    /// iCloud would look like it was syncing, because `set(_:forKey:)` neither
    /// fails nor throws — it just goes nowhere.
    var isConfigured: Bool {
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    /// Whatever iCloud currently holds, or nil if it holds nothing readable.
    func load() -> LibraryArchive? {
        guard isConfigured,
              let data = NSUbiquitousKeyValueStore.default.data(forKey: Self.key)
        else { return nil }
        do {
            return try Self.unpack(data)
        } catch {
            Self.log.error("iCloud copy could not be read: \(error.localizedDescription)")
            return nil
        }
    }

    /// Packs the archive for iCloud. Costly, and owed nothing by the main
    /// thread: a caller on it does this elsewhere and hands over the result.
    func payload(for archive: LibraryArchive) -> Payload {
        do {
            return .ready(try Self.pack(archive))
        } catch {
            Self.log.error("iCloud copy could not be written: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    /// How large the archive is once packed, or nil if it could not be.
    func size(of archive: LibraryArchive) -> Int? {
        payload(for: archive).bytes
    }

    @discardableResult
    func save(_ archive: LibraryArchive) -> Outcome {
        save(payload(for: archive))
    }

    @discardableResult
    func save(_ payload: Payload) -> Outcome {
        guard isConfigured else { return .notConfigured }
        guard isAvailable else { return .signedOut }
        switch payload {
        case .failed(let reason):
            return .failed(reason)
        case .ready(let packed):
            guard packed.count <= Self.quota else {
                Self.log.error("Library is \(packed.count) bytes, over the \(Self.quota) byte quota.")
                return .tooLarge(bytes: packed.count)
            }
            let store = NSUbiquitousKeyValueStore.default
            store.set(packed, forKey: Self.key)
            guard store.synchronize() else {
                Self.log.error("iCloud would not take the library.")
                return .rejected
            }
            return .synced
        }
    }

    /// Asks iCloud for anything newer. Changes arrive as a notification, so this
    /// only prompts the check.
    func pull() {
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    /// Roughly how much of the quota the library is using, for the Me screen.
    ///
    /// It packs the whole library to answer, so the caller holds on to what it
    /// gets rather than asking once a frame — see ``EventStore/cloudUsage``.
    func usage(of archive: LibraryArchive) -> Double {
        Double(size(of: archive) ?? 0) / Double(Self.quota)
    }

    // MARK: - Payload

    /// Event titles, venues and notes are mostly Japanese text, which is bulky
    /// as UTF-8 and compresses well — worth doing against a fixed quota.
    private static func pack(_ archive: LibraryArchive) throws -> Data {
        let json = try JSONEncoder().encode(archive)
        return try (json as NSData).compressed(using: .zlib) as Data
    }

    private static func unpack(_ data: Data) throws -> LibraryArchive {
        let json = try (data as NSData).decompressed(using: .zlib) as Data
        return try JSONDecoder().decode(LibraryArchive.self, from: json)
    }
}
