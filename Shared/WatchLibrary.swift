import Foundation

/// What the phone tells the watch: the library's events still to come,
/// soonest first, each with the reader's ticket — everything the watch app
/// draws, and nothing it does not.
///
/// Sent whole as WatchConnectivity's application context (`WatchLink` on the
/// phone, `WatchLibraryStore` on the watch), which keeps only the latest and
/// hands it over whenever the watch app next runs. The watch reads nothing
/// else: no SwiftData, no iCloud, no Eventernote page — only the flyers, from
/// the host the phone already reads them from.
///
/// Compiled into the app, the watch app and — being in `Shared` — the widget
/// extension, which has no use for it.
nonisolated struct WatchLibrary: Codable, Equatable, Sendable {
    var events: [WatchEvent]
    /// Whether days and times are printed on the reader's own clock rather
    /// than each hall's — Settings › Time Zone, as the phone has it.
    var showsLocalTime: Bool

    /// The application context's one key.
    static let contextKey = "library"

    /// How many events are sent: the context has a ceiling, and the watch is
    /// for the next few rather than the season.
    static let limit = 60
}

/// One event in the library, as the watch draws it.
nonisolated struct WatchEvent: Codable, Hashable, Identifiable, Sendable {
    /// The Eventernote event id.
    let id: String
    let title: String
    let venue: String
    /// The event's Eventernote page — what the Live Activity opens the app
    /// with, and so what the watch app is opened with from the Smart Stack.
    let link: URL
    let flyer: URL?
    /// Midnight, on the hall's clock, of the day the event is published on.
    let day: Date
    /// Doors, start and end in the order the event runs (`Event.inOrder`).
    /// Nil wherever the page has published none.
    let doors: Date?
    let starts: Date?
    let ends: Date?
    /// The hall's clock.
    let timeZone: TimeZone

    let hasTicket: Bool
    /// As the ticket prints it — see `Tracking`. Empty where not written down.
    let seat: String
    let seatClass: String
    /// In ``currency``; nil is "not written down". A copy the watch kept
    /// from before costs had currencies holds whole yen, which reads the same.
    let cost: Decimal?
    /// The ISO 4217 code ``cost`` is in. Nil where no cost is written, and in
    /// a copy kept from before costs had currencies, which was yen.
    let currency: String?
    /// Nil is "not written down".
    let lotteryEntries: Int?
}
