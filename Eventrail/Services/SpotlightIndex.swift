import AppIntents
import CoreSpotlight
import CryptoKit
import Foundation
import ImageIO
import Observation
import OSLog
import UniformTypeIdentifiers

/// Keeps Spotlight's copy of what can be found in the app: every event in the
/// library, ahead and past, and every followed performer's date it does not
/// hold (``EventEntity``); the performers followed (``PerformerEntity``); and
/// the halls the library is held at (``VenueEntity``). A result tapped opens
/// its sheet over whatever is up, as a Live Activity tapped does.
///
/// Public facts only, never the reader's record — see ``EventEntity``.
///
/// Written the way ``WidgetLink`` writes the widgets' copy: from ``RootView``,
/// a second after a write that can move what the index holds
/// (``EventStore/factsRevision``: not a note, a ticket or a read, which are
/// never in it) — and here after the Following dates change too, which no
/// write to the library marks — as the app opens and comes back, and only
/// where an item changed. Every item carries a fingerprint of what
/// it shows; what was written is kept in a file, and the index's own client
/// state is a digest of that file. So a launch that finds the index as it
/// left it writes nothing, and an index the system emptied — or a file the
/// system threw out of Caches — is written whole again.
///
/// Each device keeps its own: the index is the system's, on this device, and
/// follows the library as iCloud brings it here.
@MainActor
final class SpotlightIndex {
    static let shared = SpotlightIndex()

    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "spotlight")

    /// Bumped where what an item is made of changes in a way its fingerprint
    /// cannot see — an identifier, a domain — so every device writes the
    /// index whole once.
    nonisolated private static let format = 1
    /// Every domain an item is written under — what a pass writing the index
    /// whole empties first.
    nonisolated fileprivate static let libraryDomain = "library"
    nonisolated fileprivate static let followingDomain = "following"
    nonisolated fileprivate static let performerDomain = "performers"
    nonisolated fileprivate static let venueDomain = "venues"
    nonisolated fileprivate static let domains = [libraryDomain, followingDomain, performerDomain, venueDomain]

    /// The index itself, written off the main actor — see ``SpotlightWriter``.
    private let writer = SpotlightWriter()
    /// What the index holds, by item, as fingerprints — read back from the
    /// file the first time, and nil while it is not known to be right.
    private var written: [String: String]?
    private var pending: Task<Void, Never>?
    private var running: Task<Void, Never>?
    /// Whether a change to the Following dates is being listened for — once
    /// at a time, since each is heard once.
    private var isWatching = false

    private init() {}

    /// Brings the index up to date a moment from now. A burst of edits reads
    /// the library once, after the last of them.
    func update(from store: EventStore, followed: FollowedDates) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            await write(from: store, followed: followed)
        }
    }

    /// One pass at a time: a pass making thumbnails can still be going when
    /// the next change comes.
    private func write(from store: EventStore, followed: FollowedDates) async {
        let previous = running
        let pass = Task { [weak self] in
            await previous?.value
            await self?.rewrite(from: store, followed: followed)
        }
        running = pass
        await pass.value
    }

    private func rewrite(from store: EventStore, followed: FollowedDates) async {
        watch(followed, store: store)
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let entries = Self.entries(store: store, followed: followed)
        let flyers = await ImageCache.shared.stored(entries.compactMap(\.flyer))
        var after: [String: String] = [:]
        for entry in entries where after[entry.identifier] == nil {
            after[entry.identifier] = entry.fingerprint(hasFlyer: entry.flyer.map(flyers.contains) ?? false)
        }
        let before = await indexed()
        let plan = SpotlightPlan(before: before ?? [:], after: after)
        if before != nil, plan.isEmpty { return }

        var changed: [SpotlightEntry] = []
        var thumbnails: [String: Data] = [:]
        var made: Set<String> = []
        for entry in entries where plan.writes.contains(entry.identifier) && made.insert(entry.identifier).inserted {
            changed.append(entry)
            if let flyer = entry.flyer, flyers.contains(flyer),
               let bytes = await ImageCache.shared.storedData(for: flyer) {
                thumbnails[entry.identifier] = await Self.thumbnail(of: bytes)
            }
        }

        do {
            try await writer.write(changed, thumbnails: thumbnails, deleting: plan.deletes, whole: before == nil,
                                   state: Self.digest(of: after))
            written = after
            Self.save(after)
        } catch {
            written = nil
            Self.log.error("Spotlight's copy could not be written: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// What the index holds, where the file and the index's client state agree
    /// on it, and nil where they do not — a first launch, an index the system
    /// emptied, a file thrown out of Caches.
    private func indexed() async -> [String: String]? {
        if let written { return written }
        guard let stored = Self.load(), await writer.clientState() == Self.digest(of: stored) else { return nil }
        written = stored
        return stored
    }

    /// Writes again the next time the Following dates change: a pull, a
    /// listing read as the tab opens, a date that has ended, Clear Cache.
    private func watch(_ followed: FollowedDates, store: EventStore) {
        guard !isWatching else { return }
        isWatching = true
        withObservationTracking {
            _ = followed.dates
        } onChange: { [weak self, weak store, weak followed] in
            Task { @MainActor in
                guard let self else { return }
                self.isWatching = false
                guard let store, let followed else { return }
                self.update(from: store, followed: followed)
            }
        }
    }

    // MARK: - Opening a result

    /// What a result tapped in Spotlight opens, by the identifier its item was
    /// written under — nil for a performer no longer followed.
    static func opening(_ identifier: String, in store: EventStore) -> IntentOpen? {
        let parts = identifier.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case SpotlightEntry.eventKind:
            return .event(parts[1])
        case SpotlightEntry.performerKind:
            guard let id = Int(parts[1]), let profile = store.followedProfiles.first(where: { $0.id == id }) else {
                return nil
            }
            return .performer(profile)
        case SpotlightEntry.venueKind:
            return .venue(VenueEntity.hall(named: parts[1], in: store)?.link ?? .named(parts[1]))
        default:
            return nil
        }
    }

    // MARK: - The items

    private static func entries(store: EventStore, followed: FollowedDates) -> [SpotlightEntry] {
        EventEntity.all(in: store, followed: followed).map(SpotlightEntry.event)
            + PerformerEntity.all(in: store).map(SpotlightEntry.performer)
            + VenueEntity.all(in: store).map(SpotlightEntry.venue)
    }

    /// A flyer small enough to ride in the index: Spotlight draws it at the
    /// size of an app icon.
    @concurrent
    private nonisolated static func thumbnail(of bytes: Data) async -> Data? {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 180,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    // MARK: - What was written

    /// In Caches: losing it costs one pass writing the index whole.
    private static let file = URL.cachesDirectory.appending(path: "Eventrail/Spotlight.json")

    private static func load() -> [String: String]? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    private static func save(_ written: [String: String]) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(written).write(to: file, options: .atomic)
        } catch {
            log.error("What Spotlight holds could not be written down: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated static func digest(of written: [String: String]) -> Data {
        var hash = SHA256()
        hash.update(data: Data("\(format)\n".utf8))
        for (identifier, fingerprint) in written.sorted(by: { $0.key < $1.key }) {
            hash.update(data: Data("\(identifier)\t\(fingerprint)\n".utf8))
        }
        return Data(hash.finalize())
    }
}

/// One item in the index, as plain values ``SpotlightWriter`` makes the
/// item from off the main actor.
private nonisolated enum SpotlightEntry: Sendable {
    case event(EventEntity)
    case performer(PerformerEntity)
    case venue(VenueEntity)

    static let eventKind = "event"
    static let performerKind = "performer"
    static let venueKind = "venue"

    /// The item's identifier — the kind, then the id — which is what a
    /// tapped result comes back with (``SpotlightIndex/opening(_:in:)``).
    var identifier: String {
        switch self {
        case .event(let event): "\(Self.eventKind)/\(event.id)"
        case .performer(let performer): "\(Self.performerKind)/\(performer.id)"
        case .venue(let venue): "\(Self.venueKind)/\(venue.id)"
        }
    }

    var flyer: URL? {
        if case .event(let event) = self { event.flyer } else { nil }
    }

    func fingerprint(hasFlyer: Bool) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encoded: Data? = switch self {
        case .event(let event): try? encoder.encode(event)
        case .performer(let performer): try? encoder.encode(performer)
        case .venue(let venue): try? encoder.encode(venue)
        }
        return SpotlightPlan.fingerprint(of: (encoded ?? Data()) + [hasFlyer ? 1 : 0])
    }

    func item(thumbnail: Data?) -> CSSearchableItem {
        let item: CSSearchableItem
        switch self {
        case .event(let event):
            let set = event.attributeSet
            set.thumbnailData = thumbnail
            item = CSSearchableItem(uniqueIdentifier: identifier,
                                    domainIdentifier: event.isKept ? SpotlightIndex.libraryDomain : SpotlightIndex.followingDomain,
                                    attributeSet: set)
            // A date nobody kept goes once it is over, whether or not the
            // app runs again to take it out.
            item.expirationDate = event.expires ?? .distantFuture
            item.associateAppEntity(event)
        case .performer(let performer):
            item = CSSearchableItem(uniqueIdentifier: identifier, domainIdentifier: SpotlightIndex.performerDomain,
                                    attributeSet: performer.attributeSet)
            item.expirationDate = .distantFuture
            item.associateAppEntity(performer)
        case .venue(let venue):
            item = CSSearchableItem(uniqueIdentifier: identifier, domainIdentifier: SpotlightIndex.venueDomain,
                                    attributeSet: venue.attributeSet)
            item.expirationDate = .distantFuture
            item.associateAppEntity(venue)
        }
        return item
    }
}

/// The index, written off the main actor.
///
/// Its calls can take minutes to come back: in the Simulator the index's
/// delete-all once took six and a half, and work waiting on the main actor
/// waited with it — made from there, that is a screen that stops answering.
private actor SpotlightWriter {
    /// How many items go to the index at once: an event's carries its flyer,
    /// and nine hundred of them is too much for one message to the system.
    private static let chunk = 100

    private let index = CSSearchableIndex(name: "Eventrail")

    func clientState() async -> Data? {
        await withCheckedContinuation { continuation in
            index.fetchLastClientState { state, _ in continuation.resume(returning: state) }
        }
    }

    /// Writes the items `entries` make, takes out the items `deleting` names, and records
    /// `state` as what the index now holds. `whole` empties every domain this
    /// app writes first — by domain rather than with the index's delete-all,
    /// which took minutes where this takes moments — having first marked the
    /// state as matching nothing, so a pass cut short is redone whole rather
    /// than diffed against a file that no longer says what the index holds.
    func write(_ entries: [SpotlightEntry], thumbnails: [String: Data], deleting: [String], whole: Bool,
               state: Data) async throws {
        let items = entries.map { $0.item(thumbnail: thumbnails[$0.identifier]) }
        if whole {
            try await setClientState(Data())
            try await index.deleteSearchableItems(withDomainIdentifiers: SpotlightIndex.domains)
        }
        for start in stride(from: 0, to: items.count, by: Self.chunk) {
            try await index.indexSearchableItems(Array(items[start ..< min(start + Self.chunk, items.count)]))
        }
        if !deleting.isEmpty {
            try await index.deleteSearchableItems(withIdentifiers: deleting)
        }
        try await setClientState(state)
    }

    private func setClientState(_ state: Data) async throws {
        index.beginBatch()
        try await index.endBatch(withClientState: state)
    }
}

/// What one pass writes to Spotlight and takes out of it: every item whose
/// fingerprint changed or that is new, and every item that has gone.
nonisolated struct SpotlightPlan: Equatable {
    let writes: Set<String>
    let deletes: [String]

    init(before: [String: String], after: [String: String]) {
        writes = Set(after.compactMap { before[$0.key] == $0.value ? nil : $0.key })
        deletes = before.keys.filter { after[$0] == nil }.sorted()
    }

    var isEmpty: Bool { writes.isEmpty && deletes.isEmpty }

    static func fingerprint(of data: Data) -> String {
        SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
