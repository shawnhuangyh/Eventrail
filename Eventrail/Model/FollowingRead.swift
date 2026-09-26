import CryptoKit
import Foundation

/// Whether the reader has looked at one date on the Following tab — the
/// record behind the dot on its row.
///
/// The tab is a stream of things somebody else published, and the reader comes
/// back to it to see what is new — so, like a mailbox, a row carries a dot
/// until it has been opened, swiped, or marked in a batch.
///
/// **What is written down is the copy that was read, not only that it was.**
/// A mark keeps a fingerprint of the row as the listing printed it then
/// (``Event/listingFingerprint``). A refresh that brings the row back with a
/// different title, hall, day, times or bill no longer matches it, and the row
/// reads as unread again with nothing having to notice the change as it lands:
/// unread is simply "not the copy the reader saw".
///
/// The reader's own record, so it lives in ``LibraryArchive/followingReads``,
/// stamped and synced like a favourite: a date read on the phone is read on the
/// iPad. Marking a date unread — and Delete All — writes a record with no
/// fingerprint rather than dropping the key, for the reason a removal is a
/// tombstone: a dropped key would let the next merge hand the other device's
/// read straight back. Clear Cache does not reach it; it is not a copy of
/// anything Eventernote holds.
nonisolated struct FollowingRead: Codable, Hashable, Sendable {
    /// The fingerprint of the copy that was read, or nil where the date was
    /// marked unread again.
    var fingerprint: String?
    /// The night the record is about, which is what decides when it can go:
    /// see ``LibraryArchive/pruned()``.
    var day: Date

    func matches(_ event: Event) -> Bool {
        fingerprint == event.listingFingerprint
    }
}

/// Why a Following date is unread, which is what its row's tag says.
nonisolated enum FollowingUnread: Sendable {
    /// Never looked at — or marked unread again, which throws away the copy
    /// that was read and so leaves nothing to say it changed from.
    case new
    /// Looked at, and the listing has printed something different since.
    case updated
}

nonisolated extension Event {
    /// What a listing row says about the night, boiled down to something that
    /// changes exactly when the row does — see ``FollowingRead``.
    ///
    /// Only what a performer's listing prints: the title, the hall, the day,
    /// whatever times it carries and the bill. Not the head count, which moves
    /// with every member who lists the night, and not the flyer, whose URL the
    /// host keeps when the picture is replaced. Hashed so a mark is a short
    /// string rather than a copy of the row, and hashed with SHA-256 rather
    /// than `hashValue`, which is seeded afresh on every launch — and on every
    /// device, which a synced mark has to agree across.
    var listingFingerprint: String {
        let times = [date, doorsOpen, startsAt, endsAt]
            .map { $0.map { String(Int($0.timeIntervalSince1970)) } ?? "-" }
        let fields = [title, venue] + times + performers.map(\.name)
        let digest = SHA256.hash(data: Data(fields.joined(separator: "\u{1F}").utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
