import Foundation
import OSLog
import WatchConnectivity

/// The library as the phone last sent it.
///
/// Kept in a file as it arrives, so the app opens on the last copy at once —
/// with the phone out of reach, or before WatchConnectivity has handed over
/// anything newer. The copy can be days old: ``events(at:)`` drops an event
/// whose day is over without waiting for the phone to say so.
@MainActor @Observable
final class WatchLibraryStore: NSObject {
    /// Nil until the phone has sent anything at all.
    private(set) var library: WatchLibrary?

    @ObservationIgnored private let session: WCSession? = WCSession.isSupported() ? .default : nil

    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "watch")

    init(library: WatchLibrary? = WatchLibraryStore.read()) {
        self.library = library
        super.init()
        session?.delegate = self
        session?.activate()
    }

    var showsLocalTime: Bool { library?.showsLocalTime ?? false }

    /// The events still to come at `now`, soonest first.
    func events(at now: Date) -> [WatchEvent] {
        (library?.events ?? []).filter { EventMoment($0, showsLocalTime: showsLocalTime, at: now).isListed }
    }

    func event(id: WatchEvent.ID) -> WatchEvent? {
        library?.events.first { $0.id == id }
    }

    private func take(_ data: Data?) {
        guard let data else { return }
        do {
            let library = try JSONDecoder().decode(WatchLibrary.self, from: data)
            guard library != self.library else { return }
            self.library = library
            Self.write(data)
            Task { await FlyerCache.shared.keep(only: Set(library.events.map(\.id))) }
        } catch {
            Self.log.error("The phone's library could not be read: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - The copy on disk

    private static var file: URL {
        URL.applicationSupportDirectory.appending(path: "library.json", directoryHint: .notDirectory)
    }

    static func read() -> WatchLibrary? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(WatchLibrary.self, from: data)
    }

    private static func write(_ data: Data) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            log.error("The library could not be kept: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension WatchLibraryStore: WCSessionDelegate {
    /// Whatever the phone sent while the app was not running is waiting here.
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        let data = session.receivedApplicationContext[WatchLibrary.contextKey] as? Data
        Task { @MainActor in self.take(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext[WatchLibrary.contextKey] as? Data
        Task { @MainActor in self.take(data) }
    }
}
