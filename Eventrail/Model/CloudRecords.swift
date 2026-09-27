import CryptoKit
import Foundation

/// How the archive is cut into CloudKit records, and put back together.
///
/// One record per thing the reader keeps a record *about*: an event (whether
/// it is in the library, its tracking, the favourite, the Following read, and
/// the facts that go with it), a performer (the follow and who they are), and
/// one for the settings that belong to the whole library. Each record carries
/// a slice of the archive — an ordinary ``LibraryArchive`` holding only that
/// one thing — so a record arriving from another device is folded in by the
/// same ``LibraryArchive/merging(_:)`` a whole archive always was, and every
/// rule written there (per-answer tracking, the later page read, tombstones)
/// holds record by record without being written a second time.
///
/// Pure and `nonisolated`, so it is testable with no CloudKit behind it; the
/// engine that moves the records is ``CloudSync``.
nonisolated enum CloudRecord {
    /// The one record type. What a record is about is in its name.
    static let recordType = "LibraryRecord"

    /// The field holding the slice, compressed JSON. Written to
    /// `encryptedValues`: the reader's notes are theirs, and with Advanced
    /// Data Protection on, this keeps them out of Apple's reach too.
    static let payloadField = "payload"

    /// The field saying which shape the payload is in — see ``currentFormat``.
    static let formatField = "format"

    /// Bumped whenever a slice is written in a shape an older build could not
    /// read back without losing something. A record whose format is newer
    /// than this build's is left alone rather than decoded — see
    /// ``CloudSync``.
    static let currentFormat = 1

    /// What one record is about.
    enum Key: Hashable, Sendable {
        case event(Event.ID)
        case performer(String)
        case settings

        var recordName: String {
            switch self {
            case .event(let id): "event.\(id)"
            case .performer(let id): "performer.\(id)"
            case .settings: "settings"
            }
        }

        init?(recordName: String) {
            if recordName == "settings" {
                self = .settings
            } else if recordName.hasPrefix("event.") {
                self = .event(String(recordName.dropFirst("event.".count)))
            } else if recordName.hasPrefix("performer.") {
                self = .performer(String(recordName.dropFirst("performer.".count)))
            } else {
                return nil
            }
        }
    }

    /// A slice as a record carries it.
    static func payload(for slice: LibraryArchive) throws -> Data {
        try (canonicalJSON(slice) as NSData).compressed(using: .zlib) as Data
    }

    static func slice(from payload: Data) throws -> LibraryArchive {
        let json = try (payload as NSData).decompressed(using: .zlib) as Data
        return try JSONDecoder().decode(LibraryArchive.self, from: json)
    }

    /// A fingerprint of every record the archive holds, keyed by record name.
    ///
    /// What tells a save apart from nothing: a slice whose fingerprint is the
    /// one last sent, or last received, is not sent again. Stable across
    /// launches — sorted keys, and SHA-256 rather than `hashValue`, which is
    /// seeded afresh every run.
    static func digests(of archive: LibraryArchive) -> [String: Data] {
        var digests: [String: Data] = [:]
        for key in archive.cloudKeys {
            guard let slice = archive.slice(for: key), let digest = digest(of: slice) else { continue }
            digests[key.recordName] = digest
        }
        return digests
    }

    static func digest(of slice: LibraryArchive) -> Data? {
        guard let json = try? canonicalJSON(slice) else { return nil }
        return Data(SHA256.hash(data: json))
    }

    private static func canonicalJSON(_ slice: LibraryArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(slice)
    }
}

extension LibraryArchive {
    /// Every record this archive has something to say in.
    var cloudKeys: Set<CloudRecord.Key> {
        var keys = Set<CloudRecord.Key>()
        for id in events.keys { keys.insert(.event(id)) }
        for id in membership.keys { keys.insert(.event(id)) }
        for id in tracking.keys { keys.insert(.event(id)) }
        for id in favorites.keys { keys.insert(.event(id)) }
        for id in (followingReads ?? [:]).keys { keys.insert(.event(id)) }
        for id in (follows ?? [:]).keys { keys.insert(.performer(id)) }
        if slice(for: .settings) != nil { keys.insert(.settings) }
        return keys
    }

    /// The part of this archive one record carries, or nil where it holds
    /// nothing about that key — which is a record to delete rather than one
    /// to save empty.
    func slice(for key: CloudRecord.Key) -> LibraryArchive? {
        var slice = LibraryArchive()
        switch key {
        case .event(let id):
            slice.events[id] = events[id]
            slice.membership[id] = membership[id]
            slice.tracking[id] = tracking[id]
            slice.favorites[id] = favorites[id]
            if let read = followingReads?[id] { slice.followingReads = [id: read] }
            let holdsSomething = slice.events[id] != nil || slice.membership[id] != nil
                || slice.tracking[id] != nil || slice.favorites[id] != nil
                || slice.followingReads != nil
            return holdsSomething ? slice : nil
        case .performer(let id):
            guard let follow = follows?[id] else { return nil }
            slice.follows = [id: follow]
            if let profile = followedPerformers?[id] { slice.followedPerformers = [id: profile] }
            return slice
        case .settings:
            slice.recentSearches = recentSearches
            slice.eventernoteAccount = eventernoteAccount
            slice.eventernoteProfile = eventernoteProfile
            slice.lastRefreshed = lastRefreshed
            slice.lastImported = lastImported
            // A fresh install's defaults are not a setting anybody made.
            let holdsSomething = recentSearches.modified != .distantPast
                || eventernoteAccount != nil || eventernoteProfile != nil
                || lastRefreshed != nil || lastImported != nil
            return holdsSomething ? slice : nil
        }
    }
}
