import Foundation
import MapKit
import os

/// The venue a calendar entry points at, as Maps knows it.
///
/// A calendar entry whose location is only a line of text is just text. What
/// makes the Calendar app draw the little map beside an event — and work out
/// when to leave for it — is a place with a coordinate on it, which is what the
/// reader gets when they pick a hall out of Calendar's own location field. So
/// the hall is looked up in `MKLocalSearch`, the same search that field uses.
///
/// Eventernote publishes a name and an address and nothing else, so the search
/// is by name first — a hall is a point of interest in Maps, and its name is
/// what finds it — and by the published address second.
///
/// The answers are kept, because the search is a network call the reader is not
/// waiting on, and it is rate-limited per app. A hall does not move.
final class VenuePlaces {
    static let shared = VenuePlaces()

    /// Says what happened to each lookup. A silent fallback to plain text is
    /// indistinguishable from a broken search, and this is the only place that
    /// can tell the difference.
    private static let log = Logger(subsystem: "com.shawnhuang.Eventrail", category: "venues")

    /// What Eventernote knows about where an event is. Two events at the same
    /// hall ask the same question and are looked up once.
    struct Venue: Hashable {
        let name: String
        let address: String?

        /// What Maps is asked, in order: the hall by name, then the published
        /// address. Either alone may be the only thing the site gave us.
        var queries: [String] {
            var asked: [String] = []
            for query in [name, address ?? ""] where !query.isEmpty && !asked.contains(query) {
                asked.append(query)
            }
            return asked
        }

        /// The cache's key. Both parts, so a re-import that finally supplies an
        /// address is a new question rather than an old answer.
        var key: String { "\(name)\n\(address ?? "")" }
    }

    /// What Maps said about one venue, in plain fields rather than an archived
    /// `MKMapItem`: a coordinate, a name and an address survive any amount of
    /// OS churn, and they are all a calendar entry needs.
    private struct Answer: Codable {
        var name: String?
        var address: String?
        var latitude: Double?
        var longitude: Double?
        /// When Maps was asked. Kept so that "no such place" can be tried
        /// again one day — see ``VenuePlaces/patience``.
        var asked: Date

        var wasFound: Bool { latitude != nil && longitude != nil }

        var mapItem: MKMapItem? {
            guard let latitude, let longitude else { return nil }
            let item = MKMapItem(
                location: CLLocation(latitude: latitude, longitude: longitude),
                address: address.flatMap { MKAddress(fullAddress: $0, shortAddress: nil) }
            )
            item.name = name
            return item
        }

        init(_ found: MKMapItem?) {
            name = found?.name
            address = found?.address?.fullAddress
            latitude = found?.location.coordinate.latitude
            longitude = found?.location.coordinate.longitude
            asked = .now
        }
    }

    /// Cached per device rather than in the archive: these are facts about the
    /// world, not records the reader owns, and every device can look them up
    /// for itself.
    private static let cacheKey = "venuePlaces"

    /// How many venues one mirror may search for. The first mirror of a long
    /// history would otherwise fire off hundreds of requests and be throttled
    /// for its trouble; what it does not reach this time it reaches next time.
    ///
    /// A whole history's worth of halls is far fewer than its events — a
    /// regular goes back to the same rooms — so a few launches is enough to
    /// place all of them, and the ones coming up are asked about first.
    private static let lookupsPerRun = 40

    /// How long "Maps has never heard of this hall" is believed for.
    ///
    /// Not forever, which is the point: a search can come back empty because
    /// the device was in a strange state, or because Maps had not got round to
    /// the venue yet, and a permanent no would leave that event without a map
    /// for good. A month is long enough that nothing is asked repeatedly.
    private static let patience: TimeInterval = 30 * 24 * 60 * 60

    /// Where the search looks first. Eventernote is a Japanese site publishing
    /// Japanese venues — the same assumption ``Event/publishedZone`` makes. It
    /// is a hint, not a filter: a hall billed abroad is still found by name.
    private static let japan = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.2, longitude: 138.25),
        span: MKCoordinateSpan(latitudeDelta: 14, longitudeDelta: 18)
    )

    private var cache: [String: Answer] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return [:] }
            return (try? JSONDecoder().decode([String: Answer].self, from: data)) ?? [:]
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Self.cacheKey)
        }
    }

    private init() {
        // The two caches this one replaced, on a device that ran those builds.
        // Nothing reads them any more. Safe to drop once no such device is left.
        UserDefaults.standard.removeObject(forKey: "venueCoordinates")
        UserDefaults.standard.removeObject(forKey: "venueMapItems")
    }

    /// Looks up whichever of `venues` this run has room for, and returns every
    /// place known once it is done — the ones already cached included, the ones
    /// a later run will still have to search for left out.
    ///
    /// `venues` is in priority order: the soonest event's hall first, since that
    /// is the one the reader is about to need directions to.
    func mapItems(for venues: [Venue]) async -> [Venue: MKMapItem] {
        var cache = cache
        var found: [Venue: MKMapItem] = [:]
        var budget = Self.lookupsPerRun

        for venue in venues {
            if let answer = cache[venue.key], !Self.isWorthAskingAgain(answer) {
                found[venue] = answer.mapItem
                continue
            }
            guard budget > 0 else { break }
            budget -= 1
            do {
                let item = try await search(venue)
                cache[venue.key] = Answer(item)
                // The item Maps just handed back, rather than one rebuilt from
                // the cache: whatever else it carries, it carries it today.
                found[venue] = item
                Self.log.info("venue \(venue.key, privacy: .public) → \(Self.describe(item), privacy: .public)")
            } catch {
                // Offline, or asked too often. Nothing is written down, so the
                // next mirror tries again; stop pressing this one.
                Self.log.error("venue \(venue.key, privacy: .public) → search failed: \(error, privacy: .public)")
                break
            }
        }

        // Only the venues still being asked about are worth keeping: a hall no
        // event in the library is at any more costs one search to learn again,
        // and the cache stays the size of the library.
        self.cache = cache.filter { key, _ in venues.contains { $0.key == key } }

        Self.log.info("venues: \(found.count, privacy: .public) of \(venues.count, privacy: .public) placed on the map")
        return found.compactMapValues { $0 }
    }

    /// What the log says a lookup came back with.
    private static func describe(_ item: MKMapItem?) -> String {
        guard let item else { return "Maps has no such place" }
        let coordinate = item.location.coordinate
        return "\(item.name ?? "?") at \(coordinate.latitude),\(coordinate.longitude)"
    }

    /// A place found stays found. A place Maps did not have is asked about
    /// again once the month is up.
    private static func isWorthAskingAgain(_ answer: Answer) -> Bool {
        !answer.wasFound && answer.asked.timeIntervalSinceNow < -patience
    }

    /// The best match Maps has, by name and then by address. A throw is the
    /// search itself failing — offline, or throttled — and is worth stopping
    /// for; a venue Maps simply does not have returns nil.
    private func search(_ venue: Venue) async throws -> MKMapItem? {
        for query in venue.queries {
            let request = MKLocalSearch.Request(naturalLanguageQuery: query, region: Self.japan)
            request.regionPriority = .default
            request.resultTypes = [.pointOfInterest, .address]
            do {
                if let first = try await MKLocalSearch(request: request).start().mapItems.first {
                    return first
                }
            } catch let error as MKError where error.code == .placemarkNotFound {
                continue
            }
        }
        return nil
    }
}
