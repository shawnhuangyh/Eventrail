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

    private static let log = Logger(subsystem: "com.shawnhuang.Eventrail", category: "sync")

    /// What a push to iCloud did, in terms the Me screen can state plainly.
    enum Outcome: Sendable, Equatable {
        case synced
        /// No iCloud account on this device, so there is nowhere to sync to.
        case signedOut
        /// The library outgrew the key-value store's quota.
        case tooLarge(bytes: Int)
        case failed(String)
    }

    /// Whether this device is signed in to iCloud at all.
    var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Whatever iCloud currently holds, or nil if it holds nothing readable.
    func load() -> LibraryArchive? {
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: Self.key) else { return nil }
        do {
            return try Self.unpack(data)
        } catch {
            Self.log.error("iCloud copy could not be read: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func save(_ archive: LibraryArchive) -> Outcome {
        guard isAvailable else { return .signedOut }
        do {
            let packed = try Self.pack(archive)
            guard packed.count <= Self.quota else {
                Self.log.error("Library is \(packed.count) bytes, over the \(Self.quota) byte quota.")
                return .tooLarge(bytes: packed.count)
            }
            let store = NSUbiquitousKeyValueStore.default
            store.set(packed, forKey: Self.key)
            store.synchronize()
            return .synced
        } catch {
            Self.log.error("iCloud copy could not be written: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    /// Asks iCloud for anything newer. Changes arrive as a notification, so this
    /// only prompts the check.
    func pull() {
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    /// Roughly how much of the quota the library is using, for the Me screen.
    func usage(of archive: LibraryArchive) -> Double {
        guard let packed = try? Self.pack(archive) else { return 0 }
        return Double(packed.count) / Double(Self.quota)
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
