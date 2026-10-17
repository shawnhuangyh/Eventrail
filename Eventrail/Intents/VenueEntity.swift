import AppIntents
import CoreLocation
import CoreSpotlight
import MapKit
import UniformTypeIdentifiers

/// A hall an event in the library is held at, as Spotlight, Siri and
/// Shortcuts know it: its name and the address Eventernote publishes, and
/// where it stands wherever a placing already found it. Opens its page.
///
/// Keyed by the name, as the site prints it on every event held there: a
/// listing row carries no place id, and the hall's page is found by the name
/// where none is known (``VenueLink/named(_:)``).
nonisolated struct VenueEntity: IndexedEntity, Codable, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("entity.venue", defaultValue: "Venue"))
    static let defaultQuery = VenueQuery()

    /// The hall's name.
    let id: String
    let placeID: Int?
    let address: String?
    let latitude: Double?
    let longitude: Double?

    var link: VenueLink {
        placeID.map { .place(PlaceListing(id: $0, name: id)) } ?? .named(id)
    }

    var displayRepresentation: DisplayRepresentation {
        if let address {
            DisplayRepresentation(title: "\(id)", subtitle: "\(address)", image: .init(systemName: "mappin.circle.fill"))
        } else {
            DisplayRepresentation(title: "\(id)", image: .init(systemName: "mappin.circle.fill"))
        }
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .content)
        set.title = id
        set.displayName = id
        set.contentDescription = address
        set.namedLocation = id
        set.fullyFormattedAddress = address
        if let latitude, let longitude {
            set.latitude = NSNumber(value: latitude)
            set.longitude = NSNumber(value: longitude)
            set.supportsNavigation = true
        }
        return set
    }

    func matches(_ text: String) -> Bool {
        [id, address ?? ""].contains { $0.localizedStandardContains(text) }
    }

    /// This hall, with whatever another event held there knows and this copy
    /// does not.
    func filling(from event: Event, at coordinate: CLLocationCoordinate2D?) -> VenueEntity {
        VenueEntity(id: id, placeID: placeID ?? event.placeID, address: address ?? event.publishedAddress,
                    latitude: latitude ?? coordinate?.latitude, longitude: longitude ?? coordinate?.longitude)
    }
}

@MainActor
extension VenueEntity {
    /// Every hall the library is held at, the most recent first, each once.
    /// A placeholder the site files streams and undisclosed rooms under is no
    /// hall (``Event/isAtHall``).
    static func all(in store: EventStore) -> [VenueEntity] {
        let events = store.library.filter(\.isAtHall).sorted { $0.sortDate > $1.sortDate }
        let placings = VenuePlaces.shared.mapItems(for: events)
        var halls: [String: VenueEntity] = [:]
        var order: [String] = []
        for event in events {
            let coordinate = placings[event.id]?.item.location.coordinate
            if let held = halls[event.venue] {
                halls[event.venue] = held.filling(from: event, at: coordinate)
            } else {
                halls[event.venue] = VenueEntity(id: event.venue, placeID: nil, address: nil,
                                                 latitude: nil, longitude: nil)
                    .filling(from: event, at: coordinate)
                order.append(event.venue)
            }
        }
        return order.compactMap { halls[$0] }
    }

    static func hall(named name: String, in store: EventStore) -> VenueEntity? {
        all(in: store).first { $0.id == name }
    }
}

nonisolated struct VenueQuery: EntityStringQuery {
    func entities(for identifiers: [VenueEntity.ID]) async throws -> [VenueEntity] {
        let wanted = Set(identifiers)
        return await VenueEntity.all(in: Launch.shared.store).filter { wanted.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [VenueEntity] {
        await VenueEntity.all(in: Launch.shared.store).filter { $0.matches(string) }
    }

    func suggestedEntities() async throws -> [VenueEntity] {
        await VenueEntity.all(in: Launch.shared.store)
    }
}
