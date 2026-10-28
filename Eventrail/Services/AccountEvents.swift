import Foundation

/// Which events the linked account listed when this device last read its
/// history whole — what Not on Your Account holds the library against.
///
/// Nothing the reader keeps here reaches Eventernote, so an event added from
/// Search or Following stays off the account until they mark it on the site
/// themselves. This is how the app knows which ones: every read of the account
/// pages through its whole history, and one that reached the end writes down
/// every event it met. **Only a whole read is written**: one cut short would
/// name events the account does list as missing from it.
///
/// Per device, in Caches, as ``PageReads`` is: one read of public pages, owed
/// to no other device, and losing it costs only that read. Keyed by handle, so
/// what one account listed is never held against another; a whole read writes
/// over whatever was held for any account.
@Observable
final class AccountEvents {
    static let shared = AccountEvents()

    nonisolated struct Listing: Codable, Sendable {
        var events: Set<Event.ID>
        /// When the read that found them ended.
        var read: Date
    }

    private var listings: [String: Listing]
    /// Nil in previews and tests, which pass `persists: false`, so nothing
    /// they do reaches this device's cache.
    @ObservationIgnored private let file: KeptFile<String, Listing>?

    init(persists: Bool = true) {
        let file = persists
            ? KeptFile<String, Listing>(named: "accountEvents.json", in: .caches, formerKey: "accountEvents")
            : nil
        self.file = file
        listings = file?.read() ?? [:]
    }

    /// What `handle` listed at its last whole read on this device.
    func listing(for handle: String) -> Listing? {
        listings[handle]
    }

    /// Writes down a whole read of `handle`'s history.
    func record(_ events: Set<Event.ID>, for handle: String, at date: Date = .now) {
        listings = [handle: Listing(events: events, read: date)]
        file?.write(&listings)
    }

    /// Forgets every account's list — for an account let go of.
    func clear() {
        guard !listings.isEmpty else { return }
        listings = [:]
        file?.remove()
    }
}
