import Foundation
import MapKit
import os

/// Where an event's venue actually is, as Maps knows it.
///
/// Eventernote publishes a hall's name and its address and no coordinate, and
/// both of those are facts the site has already established. So the hall is
/// asked for by name, and the address is what says whether Maps answered with
/// the right one: a place is the hall when the address Maps publishes for it
/// is the address Eventernote published. Nothing here tries to judge an answer
/// by reading its name, which is hopeless — the hall the site calls
/// Kアリーナ横浜 is "K-Arena Yokohama" on an English phone, and a search for
/// メルセデス・ベンツアリーナ comes back with a Mercedes dealer in Nara.
///
/// Two screens want the answer, and neither is the other's business: the event
/// sheet draws a map under the venue whether or not the reader syncs anything,
/// and the calendar mirror needs a place rather than a line of text for the
/// Calendar app to draw its own map beside an entry. So the lookup lives here
/// rather than in either of them.
///
/// **Only the sheet does the asking.** A hall is looked up when the reader
/// opens an event at it: one question, asked because somebody is waiting for
/// the answer. The mirror reads what has been found and searches for nothing
/// itself — it is handed the whole library at once, and a run of hundreds of
/// searches is what got the app throttled into placing nothing at all.
///
/// The answers are kept, because a hall does not move.
final class VenuePlaces {
    static let shared = VenuePlaces()

    /// Says what happened to each lookup. A silent fallback to plain text is
    /// indistinguishable from a broken search, and this is the only place that
    /// can tell the difference.
    private static let log = Logger(subsystem: "com.shawnhuang.Eventrail", category: "venues")

    /// What Eventernote knows about where an event is. Two events at the same
    /// hall ask the same question and are looked up once, which is why this and
    /// not the event is what a lookup is keyed by.
    private struct Venue: Hashable {
        let name: String
        let address: String?

        /// Nil where the site has not named a hall yet — it announces plenty of
        /// events before it has booked one.
        init?(_ event: Event) {
            let address = event.publishedAddress
            guard !event.venue.isEmpty || address != nil else { return nil }
            name = event.venue
            self.address = address
        }

        /// The hall's name without the alias Eventernote is apt to append in
        /// brackets — "ワールド記念ホール(神戸ポートアイランドホール)". Maps
        /// files a hall under one name, and the whole string finds nothing.
        var plainName: String {
            let plain = VenuePlaces.withoutBrackets(name)
            return plain.isEmpty ? name : plain
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
        /// Which reading of Maps' answers produced this one. Optional because
        /// an answer written before there were any carries none.
        var ruleset: Int?

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
            ruleset = VenuePlaces.ruleset
        }
    }

    /// Cached per device rather than in the archive: these are facts about the
    /// world, not records the reader owns, and every device can look them up
    /// for itself.
    private static let cacheKey = "venuePlaces"

    /// Which reading of Maps' answers the kept ones were made under. Raised
    /// whenever that reading changes, and everything older is simply asked
    /// again — now that an answer is kept only where Maps files it at the
    /// address Eventernote published, rather than argued out of its name.
    private static let ruleset = 5

    /// How long "Maps has never heard of this hall" is believed for.
    ///
    /// Not forever, which is the point: a search can come back empty because
    /// the device was offline, or because Maps had not got round to the venue
    /// yet, and a permanent no would leave that event without a map for good.
    /// A month is long enough that nothing is asked repeatedly.
    private static let patience: TimeInterval = 30 * 24 * 60 * 60

    /// How long an answer is kept once nothing has asked about it.
    ///
    /// A hall the reader still goes to is asked about again a year later and
    /// found again in one search; a hall they met once in Search and never
    /// kept stops taking up room. The alternative is a cache that only grows,
    /// on a device where it lives in `UserDefaults`.
    private static let keep: TimeInterval = 365 * 24 * 60 * 60

    /// Where a search looks first. Eventernote is a Japanese site publishing
    /// Japanese venues — the same assumption ``Event/publishedZone`` makes. A
    /// hint, not a filter: the address decides, and a hall billed abroad is
    /// found by name like any other.
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

    // MARK: - What is already known

    /// Where each of `events` is, as far as anything has already found out.
    ///
    /// Nothing is searched for here, which is why it asks nothing of the
    /// network and answers at once: it is the calendar mirror's view of what
    /// the sheets have looked up. An event at a hall nobody has opened yet is
    /// simply absent, and its entry carries the hall's name and no map until a
    /// later mirror, after the reader has opened it.
    func mapItems(for events: [Event]) -> [Event.ID: MKMapItem] {
        let cache = cache
        return events.reduce(into: [:]) { placed, event in
            // Read under the same rule a sheet reads it under, so an answer
            // settled by a reading since found wrong is not still being
            // written into the reader's calendar.
            guard let venue = Venue(event),
                  let answer = cache[venue.key], !Self.isWorthAskingAgain(answer),
                  let item = answer.mapItem
            else { return }
            placed[event.id] = item
        }
    }

    // MARK: - Asking

    /// Where one event is, for a screen showing it now — the first time the
    /// reader opens an event at a hall nothing has looked up yet, this is what
    /// goes and finds it and writes the answer down for everything after, the
    /// calendar mirror included.
    func mapItem(for event: Event) async -> MKMapItem? {
        guard let venue = Venue(event) else { return nil }
        if let answer = cache[venue.key], !Self.isWorthAskingAgain(answer) {
            return answer.mapItem
        }
        do {
            let item = try await search(venue)
            remember(Answer(item), for: venue.key)
            Self.log.info("venue \(venue.key, privacy: .public) → \(Self.describe(item), privacy: .public)")
            return item
        } catch {
            // Not written down, so the next screen to ask tries again.
            Self.log.error("venue \(venue.key, privacy: .public) → search failed: \(error, privacy: .public)")
            return nil
        }
    }

    /// The hall, as Maps has it. A throw is the search itself failing —
    /// offline, or throttled; a hall Maps does not have returns nil.
    ///
    /// Maps is asked for the hall by name, and every answer is held against
    /// the address Eventernote published: the hall is whichever of them Maps
    /// files at that address. That is one question in the ordinary case, and
    /// it is the address rather than any reading of the name that settles it.
    ///
    /// Where no hall Maps knows stands at the address — a hall too new or too
    /// small to be listed — the address itself is asked for, and the pin is
    /// the right block rather than the hall's own listing. That is the whole
    /// of what a map under the venue and a place on a calendar entry need.
    ///
    /// Nothing is placed without an address to check it against. An event
    /// opened straight from a search row has only the name until its own page
    /// is imported, and it is worth the wait: a name on its own is how a
    /// concert in Shanghai came to be pinned to a Mercedes showroom in Nara.
    private func search(_ venue: Venue) async throws -> MKMapItem? {
        guard let address = venue.address, !address.isEmpty else { return nil }

        if !venue.plainName.isEmpty {
            let halls = try await results(for: venue.plainName, kinds: [.pointOfInterest])
            if let hall = halls.first(where: { Self.stands($0, at: address) }) {
                return hall
            }
        }

        return try await results(for: address, kinds: [.pointOfInterest, .address])
            .first { Self.stands($0, at: address) }
    }

    /// One search. A hall Maps has never heard of is an empty list, not a
    /// failure: it is an answer, and it is worth writing down.
    private func results(for query: String, kinds: MKLocalSearch.ResultType) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request(naturalLanguageQuery: query, region: Self.japan)
        request.regionPriority = .default
        request.resultTypes = kinds
        do {
            return try await MKLocalSearch(request: request).start().mapItems
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        }
    }

    /// Whether Maps files this place at the address Eventernote published.
    ///
    /// Compared by the numbers in the two addresses, because nothing else in
    /// them survives the crossing: Maps answers in the reader's language and
    /// its own order — 才野1622-125 for 才野1622番地125, "2-14, Minatomirai
    /// 6-Chōme" for みなとみらい6-2-14 — while the block and building numbers
    /// stay exactly what they were. A place that shares none of them is not at
    /// that address, whatever it is called: it is the Mercedes dealer Maps
    /// offers for メルセデス・ベンツアリーナ, or the street in Gilbert,
    /// Arizona it once offered for 世博大道1200号.
    private static func stands(_ item: MKMapItem, at address: String) -> Bool {
        let published = numbers(in: address)
        guard !published.isEmpty else { return true }
        guard let found = item.address?.fullAddress else { return false }
        return !published.isDisjoint(with: numbers(in: found))
    }

    /// Every run of digits in a line of text, full-width ones read as the
    /// digits they are and leading zeroes dropped, so a postcode written 0012
    /// and a block written 12 are the same number.
    private static func numbers(in text: String) -> Set<Int> {
        let halfwidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return Set(halfwidth.split { !$0.isASCII || !$0.isNumber }.compactMap { Int($0) })
    }

    // MARK: - Keeping the answers

    /// Writes one answer down, and drops whatever nothing has wanted for a
    /// year. Read afresh rather than written over: another sheet may have
    /// looked up its own hall while this one was waiting.
    private func remember(_ answer: Answer, for key: String) {
        var kept = cache.filter { $0.value.asked.timeIntervalSinceNow > -Self.keep }
        kept[key] = answer
        cache = kept
    }

    /// A place found stays found. A place Maps did not have is asked about
    /// again once the month is up, and anything settled under an older reading
    /// of Maps' answers is asked again now.
    private static func isWorthAskingAgain(_ answer: Answer) -> Bool {
        guard answer.ruleset == ruleset else { return true }
        return !answer.wasFound && answer.asked.timeIntervalSinceNow < -patience
    }

    /// What the log says a lookup came back with.
    private static func describe(_ item: MKMapItem?) -> String {
        guard let item else { return "Maps has no such place" }
        let coordinate = item.location.coordinate
        let kind = item.pointOfInterestCategory.map { "\($0.rawValue)" } ?? "the address"
        return "\(item.name ?? "?") (\(kind)) at \(coordinate.latitude),\(coordinate.longitude)"
    }

    /// Drops anything in brackets, nesting included, and what is left of the whitespace around it.
    private static func withoutBrackets(_ text: String) -> String {
        var kept = ""
        var depth = 0
        for character in text {
            if "（(【[".contains(character) {
                depth += 1
            } else if "）)】]".contains(character) {
                depth = max(0, depth - 1)
            } else if depth == 0 {
                kept.append(character)
            }
        }
        return kept.trimmingCharacters(in: .whitespaces)
    }
}

nonisolated extension Event {
    /// The venue's address, wherever it survived.
    ///
    /// Its own field on an event imported since there was one, and otherwise
    /// out of the line the sheet prints, where it was kept before that — most
    /// of a library that predates the field, which is exactly the library that
    /// needs the address most: it is the only thing a hall is placed by.
    var publishedAddress: String? {
        if let venueAddress, !venueAddress.isEmpty { return venueAddress }
        return venueDetail.flatMap(EventernotePages.address(inDetail:))
    }

    /// The event's place in one line, as the app itself would write it.
    ///
    /// The address goes first, as Japanese addresses are written and as
    /// Eventernote itself prints them, with the hall's name after it — unless
    /// the published address already ends in that name, which it often does.
    /// Nil where the site has not named a hall yet.
    var locationTitle: String? {
        guard let address = publishedAddress, !address.isEmpty else {
            return venue.isEmpty ? nil : venue
        }
        guard !venue.isEmpty, !address.contains(venue) else { return address }
        return "\(address) \(venue)"
    }
}
