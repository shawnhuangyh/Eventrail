import AppIntents
import CoreLocation
import CoreSpotlight
import MapKit
import UniformTypeIdentifiers

/// One event as Spotlight, Siri and Shortcuts know it: an event in the
/// library, or a followed performer's date that is not in it.
///
/// **Only what Eventernote publishes** — the title, the day, the hall and its
/// address, the bill, the hashtags — and nothing of the reader's own record:
/// no ticket, seat, cost, lottery or note, on Shawn's word. Whatever is
/// indexed is offered wherever the system searches, and those are not.
///
/// A plain copy rather than the event: an entity is handed to the system and
/// back, and is fingerprinted to tell whether Spotlight's copy is still right
/// (``SpotlightIndex``), so everything Spotlight shows is worked out as it is
/// made — the day already printed on the clock Settings › Time Zone names, in
/// the app's language — and a change to any of it is a change to the copy.
nonisolated struct EventEntity: IndexedEntity, Codable, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("entity.event", defaultValue: "Event"))
    static let defaultQuery = EventQuery()

    /// Eventernote's event id, as the page's path carries it.
    let id: String
    let title: String
    /// The day, printed on the clock Settings › Time Zone names.
    let day: String
    let venue: String
    let address: String?
    /// Everyone billed, as the page prints them.
    let performers: [String]
    /// How the followed performers on the bill sound — their kana readings
    /// and the romaji of those — so a name typed as it is said finds the
    /// event as well as one typed as it is written (``PerformerEntity/soundings(of:)``).
    let readings: [String]
    let hashtags: [String]
    let starts: Date
    let ends: Date?
    /// No start published yet: the day alone.
    let isAllDay: Bool
    /// Where the hall stands, wherever a placing already found it — never
    /// asked for here (see ``VenuePlaces/mapItems(for:)``).
    let latitude: Double?
    let longitude: Double?
    let flyer: URL?
    /// In the library, rather than only on a followed performer's listing.
    let isKept: Bool
    /// When Spotlight lets a date nobody kept go: once its day is over
    /// everywhere, as the Following tab lets it go. Nil for a kept event,
    /// which stays for as long as it is kept.
    let expires: Date?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(place)", image: .init(systemName: "calendar"))
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .calendarEvent)
        set.title = title
        set.displayName = title
        set.contentDescription = caption
        set.keywords = keywords
        set.performers = performers
        set.startDate = starts
        set.endDate = ends
        set.allDay = NSNumber(value: isAllDay)
        if Event.namesHall(venue) { set.namedLocation = venue }
        set.fullyFormattedAddress = address
        if let latitude, let longitude {
            set.latitude = NSNumber(value: latitude)
            set.longitude = NSNumber(value: longitude)
            set.supportsNavigation = true
        }
        // Above a date that is only on somebody's listing.
        set.rankingHint = NSNumber(value: isKept ? 2 : 1)
        return set
    }

    /// The day and the hall, as a row prints them.
    private var place: String {
        [day, venue].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// What Spotlight prints under the title: the day and the hall, then the
    /// head of the bill.
    private var caption: String {
        let bill = Array(performers.prefix(6)).formatted(.list(type: .and, width: .narrow))
        return bill.isEmpty ? place : "\(place)\n\(bill)"
    }

    /// Every other word the event can be found by. The hall goes in only where
    /// it is one: `!_東京都内某所` is the site's placeholder, not a name.
    private var keywords: [String] {
        let hall = Event.namesHall(venue) ? [venue] : []
        var seen = Set<String>()
        return (hall + [address ?? ""] + performers + readings + hashtags)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Whether `text` is in anything the event is found by — for Shortcuts'
    /// own search of the events, which does not go through Spotlight.
    func matches(_ text: String) -> Bool {
        ([title, venue] + performers + readings + hashtags).contains { $0.localizedStandardContains(text) }
    }
}

nonisolated extension EventEntity {
    init(_ event: Event, isKept: Bool, display: TimeDisplay, coordinate: CLLocationCoordinate2D?,
         readings: [String: [String]]) {
        let names = event.performers.map(\.name)
        self.init(
            id: event.id,
            title: event.title,
            day: event.shown(on: display).dayLine,
            venue: event.venue,
            address: event.publishedAddress,
            performers: names,
            readings: names.flatMap { readings[$0] ?? [] },
            hashtags: event.hashtags?.map(\.tag) ?? [],
            starts: event.startsAt ?? event.date,
            ends: event.endsAt,
            isAllDay: event.startsAt == nil,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            flyer: event.imageURL,
            isKept: isKept,
            expires: isKept ? nil : event.dayEndsEverywhere ?? event.dayEnds
        )
    }
}

// MARK: - Where the events come from

@MainActor
extension EventEntity {
    /// Every event worth finding: the library's, ahead and past, and every
    /// followed performer's date still to come that the library does not hold.
    static func all(in store: EventStore, followed: FollowedDates) -> [EventEntity] {
        let kept = store.library
        let keptIDs = Set(kept.map(\.id))
        let dates = followed.events(for: store.followedProfiles).filter { !keptIDs.contains($0.id) }
        let making = EntityMaking(store: store)
        return making.entities(for: kept, isKept: true) + making.entities(for: dates, isKept: false)
    }

    /// The events these ids name, wherever this device holds one.
    static func find(_ ids: [ID]) -> [EventEntity] {
        let store = Launch.shared.store
        let followed = Launch.shared.followed
        let making = EntityMaking(store: store)
        return ids.compactMap { id in
            if let event = store.event(id: id) {
                return making.entities(for: [event], isKept: store.isInLibrary(event)).first
            }
            return followed.event(id: id).flatMap { making.entities(for: [$0], isKept: false).first }
        }
    }

    static func matching(_ text: String) -> [EventEntity] {
        all(in: Launch.shared.store, followed: Launch.shared.followed).filter { $0.matches(text) }
    }

    /// What Shortcuts and Siri offer first: the library's events still to
    /// come, soonest first.
    static func suggested() -> [EventEntity] {
        let store = Launch.shared.store
        return EntityMaking(store: store).entities(for: store.upcoming, isKept: true)
    }
}

/// What every event's entity is made with: the clock Settings › Time Zone
/// names, how the followed performers sound, and where each hall has been
/// placed.
@MainActor
private struct EntityMaking {
    let display: TimeDisplay
    let readings: [String: [String]]

    init(store: EventStore) {
        display = UserDefaults.standard.string(forKey: TimeDisplay.storageKey)
            .flatMap(TimeDisplay.init(rawValue:)) ?? .venue
        readings = Dictionary(
            store.followedProfiles.map { ($0.name, PerformerEntity.soundings(of: $0.reading)) },
            uniquingKeysWith: { first, _ in first })
    }

    func entities(for events: [Event], isKept: Bool) -> [EventEntity] {
        let placings = VenuePlaces.shared.mapItems(for: events)
        return events.map {
            EventEntity($0, isKept: isKept, display: display,
                        coordinate: placings[$0.id]?.item.location.coordinate, readings: readings)
        }
    }
}

nonisolated struct EventQuery: EntityStringQuery {
    func entities(for identifiers: [EventEntity.ID]) async throws -> [EventEntity] {
        await EventEntity.find(identifiers)
    }

    func entities(matching string: String) async throws -> [EventEntity] {
        await EventEntity.matching(string)
    }

    func suggestedEntities() async throws -> [EventEntity] {
        await EventEntity.suggested()
    }
}
