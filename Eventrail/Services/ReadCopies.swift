import Foundation

/// The copy of each date the reader last read, as this device saw it — what
/// lets an Updated row say what changed (``ListingChanges``).
///
/// A mark (``FollowingRead``) keeps only a fingerprint of the copy it was
/// taken of; this keeps the copy itself beside it. Written as the reader marks
/// a date read, and whenever a copy on screen turns out to be the one marked
/// (``EventStore/unread(_:)``) — so a date read before this was kept, or read
/// on another device, is held too, from the first time this device draws it
/// unchanged. Each copy is kept with the fingerprint of the mark it answers
/// for, and spoken for only while the mark still says it.
///
/// Per device rather than in the mark, which syncs: a mark is written every
/// time a row is opened, and is kept a short string on purpose, where a bill
/// can run to a festival's worth of names. What that costs is a date read on
/// another device and changed before this one drew it unchanged — which says
/// Updated and no more, as every date did before this was kept.
///
/// In Caches: losing it loses only what the next change can say. Not reached
/// by Clear Cache, which leaves the marks alone too.
final class ReadCopies {
    static let shared = ReadCopies()

    /// A copy and the fingerprint of the mark it was the copy for.
    private nonisolated struct Kept: Codable, Hashable, Sendable {
        var mark: String
        var copy: ListingCopy
    }

    /// How many days past its own a copy is kept: the marks go three days
    /// after their event (``LibraryDatabase/pruneReads(in:asOf:)``), and with
    /// them anything a copy could answer for.
    private static let keep = 3

    private var copies: [Event.ID: Kept]
    /// Nil in previews and tests that pass `persists: false`.
    private let file: KeptFile<Event.ID, Kept>?
    /// Whether a write is already on its way: a launch finds hundreds of
    /// copies at once, as the tab's badge reads every date.
    private var owesWrite = false

    init(persists: Bool = true) {
        let file = persists
            ? KeptFile<Event.ID, Kept>(named: "readCopies.json", in: .caches, formerKey: "followingReadCopies")
            : nil
        self.file = file
        // Pruned on the way in, as ``PageReads`` is.
        copies = (file?.read() ?? [:]).filter { $0.value.copy.day.daysAway() >= -Self.keep }
    }

    /// The copy the mark `fingerprint` was taken of, where this device holds it.
    func copy(of id: Event.ID, markedAs fingerprint: String) -> ListingCopy? {
        guard let kept = copies[id], kept.mark == fingerprint else { return nil }
        return kept.copy
    }

    /// Holds `event` as the copy the mark `fingerprint` was taken of.
    ///
    /// The same copy on another clock — Following's on Tokyo time, the
    /// library's on its hall's — is the one already held, and replaces it
    /// only to put it on a hall's own clock abroad: the two tabs each drawing
    /// theirs would otherwise write the file over at every redraw.
    func keep(_ event: Event, markedAs fingerprint: String) {
        let kept = Kept(mark: fingerprint, copy: ListingCopy(event))
        if let held = copies[event.id], held.mark == fingerprint, held.copy.printsTheSame(as: kept.copy) {
            let movesAbroad = held.copy.zone == Event.publishedZone && kept.copy.zone != Event.publishedZone
            guard held.copy.zone == nil || movesAbroad else { return }
        }
        copies[event.id] = kept
        save()
    }

    /// Forgets every copy — with Delete All, which turns every date back to
    /// unread.
    func clear() {
        guard !copies.isEmpty else { return }
        copies = [:]
        file?.remove()
    }

    /// Written once the copies found in this pass are all in.
    private func save() {
        guard file != nil, !owesWrite else { return }
        owesWrite = true
        Task {
            owesWrite = false
            file?.write(&copies)
        }
    }
}
