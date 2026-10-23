import Foundation
import OSLog
import WatchConnectivity

/// Keeps the watch app's copy of the library in step with the phone's.
///
/// The watch has no store of its own: it draws the ``WatchLibrary`` this
/// sends, the events still to come with the reader's ticket for each. Sent as
/// WatchConnectivity's application context, which keeps only the latest and
/// hands it to the watch app whenever that next runs — so the phone sends a
/// fresh copy whenever the library or the Time Zone setting changes, as the
/// app opens and comes back, and as a watch first reaches it, and the watch
/// shows whatever it was last handed.
///
/// Nothing is ever asked of the phone from the watch. A message from the
/// watch would wake this app in the background just to open the library, and
/// the copy the watch already holds is the one the phone last had.
@MainActor
final class WatchLink: NSObject {
    static let shared = WatchLink()

    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "watch")

    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    /// What was last handed over, as sent — compared before sending again, so
    /// an edit the watch never sees, such as a note, sends nothing.
    private var sent: Data?
    /// What was last made to be sent, for a session that comes up after it.
    private var latest: WatchLibrary?
    private var pending: Task<Void, Never>?

    private override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    /// Sends the library as `store` holds it a moment from now. A burst of
    /// edits — a note typed, a key at a time — reads the library once, after
    /// the last of them.
    func send(from store: EventStore) {
        pending?.cancel()
        pending = Task { [weak self, weak store] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, let store else { return }
            latest = WatchLibrary(
                events: store.upcoming.prefix(WatchLibrary.limit).map { event in
                    WatchEvent(event, tracking: store.tracking(for: event))
                },
                showsLocalTime: TimeDisplay.stored == .local
            )
            flush()
        }
    }

    private func flush() {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled,
              let latest, let data = Self.payload(for: latest), data != sent
        else { return }
        do {
            try session.updateApplicationContext([WatchLibrary.contextKey: data])
            sent = data
        } catch {
            Self.log.error("The library could not be sent to the watch: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// How large a copy is sent. WatchConnectivity refuses an application
    /// context much past 64 KB, and a refused copy left the watch on the last
    /// one it had, with nothing but a line in the log to say so; sixty events
    /// with long titles come to some 51 KB, so the room is not as wide as it
    /// looks.
    nonisolated static let budget = 60_000

    /// `library` as it is sent: within ``budget``, the events furthest off
    /// left out where it would not fit — the watch shows what is soonest —
    /// and the slashes of its links unescaped, which JSON allows and a
    /// decoder of any build reads the same.
    nonisolated static func payload(for library: WatchLibrary, within budget: Int = budget) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        var library = library
        while true {
            guard let data = try? encoder.encode(library) else { return nil }
            guard data.count > budget, !library.events.isEmpty else { return data }
            // The share of the events that the copy runs over by, and one at
            // the least, so a copy is encoded a few times rather than sixty.
            let over = Double(data.count - budget) / Double(data.count)
            let drop = max(1, Int((Double(library.events.count) * over).rounded(.up)))
            library.events.removeLast(min(drop, library.events.count))
        }
    }

    /// Sends again whatever was last made, to a session that has just come
    /// up or a watch that has just changed.
    private func resend() {
        sent = nil
        flush()
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        Task { @MainActor in self.resend() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The reader has switched to another watch: the session comes up again
    /// for that one, which has been sent nothing.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// The watch app installed, or a watch paired, since the last copy went.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.resend() }
    }
}

nonisolated extension WatchEvent {
    init(_ event: Event, tracking: Tracking) {
        let times = Event.inOrder(event.doorsOpen, event.startsAt, event.endsAt)
        self.init(
            id: event.id,
            title: event.title,
            venue: event.venue,
            link: event.sourceURL,
            flyer: event.imageURL,
            day: event.date,
            doors: times.doors,
            starts: times.starts,
            ends: times.ends,
            timeZone: event.timeZone,
            hasTicket: tracking.hasTicket,
            seat: tracking.seat.trimmingCharacters(in: .whitespacesAndNewlines),
            seatClass: tracking.ticketClass.trimmingCharacters(in: .whitespacesAndNewlines),
            cost: tracking.price?.amount,
            currency: tracking.price?.currency,
            lotteryEntries: tracking.lotteryApplications > 0 ? tracking.lotteryApplications : nil,
            lottery: tracking.lotteryStanding?.rawValue
        )
    }
}
