import Foundation
import MapKit
import os

/// Where an event's venue actually is, as Maps knows it.
///
/// Eventernote publishes a hall's name and its address and no coordinate, so
/// the hall is looked up in `MKLocalSearch` — the same search Calendar's own
/// location field uses. Two screens want the answer, and neither is the other's
/// business: the event sheet draws a map under the venue whether or not the
/// reader syncs anything, and the calendar mirror needs a place rather than a
/// line of text for the Calendar app to draw its own map beside an entry.
///
/// So the lookup lives here rather than in either of them. Whichever asks first
/// pays for the search; the other has it for nothing.
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

        /// What Maps is asked in order to *identify the hall*: its name as the
        /// site prints it, the name without its alias, and then the name pinned
        /// down by the address — which is what separates a hall from the town it
        /// shares a word with.
        var queries: [String] {
            guard !name.isEmpty else { return [] }
            var asked = [name]
            if plainName != name { asked.append(plainName) }
            if let address, !address.isEmpty { asked.append("\(plainName) \(address)") }
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

    /// How many venues one mirror may search for. The first mirror of a long
    /// history would otherwise fire off hundreds of requests and be throttled
    /// for its trouble; what it does not reach this time it reaches next time.
    ///
    /// A whole history's worth of halls is far fewer than its events — a
    /// regular goes back to the same rooms — so a few launches is enough to
    /// place all of them, and the ones coming up are asked about first.
    private static let lookupsPerRun = 40

    /// Which reading of Maps' answers the kept ones were made under. Raised
    /// whenever that reading changes — first when a search for a hall was found
    /// to come back with the town it is in, and again when reading a hall's
    /// name turned out to throw away every hall Maps names in the reader's
    /// language rather than the site's. Everything older is simply asked again.
    private static let ruleset = 2

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

    // MARK: - Asking

    /// Where each of `events` is, for as many of them as this run has room to
    /// look up. An event whose hall is not placed is simply absent.
    ///
    /// Rationed, because this is handed the whole library: see
    /// ``lookupsPerRun``. What it does not reach, a later call does.
    func mapItems(for events: [Event]) async -> [Event.ID: MKMapItem] {
        let found = await mapItems(forVenues: venues(in: events))
        return events.reduce(into: [:]) { placed, event in
            guard let venue = Venue(event), let item = found[venue] else { return }
            placed[event.id] = item
        }
    }

    /// Every venue in `events`, in the order they are worth asking about.
    ///
    /// The whole library, past included: a calendar is a diary as well as a
    /// plan, and the sheet for a night the reader was at draws the same map as
    /// one they are going to.
    ///
    /// Order is what matters, because one run only has room for so many
    /// searches. Upcoming events come first, soonest first, since those are the
    /// ones about to be needed for directions; the past follows, most recent
    /// first, and the rest is picked up next time.
    private func venues(in events: [Event]) -> [Venue] {
        let upcoming = events.filter(\.isUpcoming).sorted { $0.sortDate < $1.sortDate }
        let past = events.filter { !$0.isUpcoming }.sorted { $0.sortDate > $1.sortDate }

        var seen: Set<Venue> = []
        return (upcoming + past)
            .compactMap(Venue.init)
            .filter { seen.insert($0).inserted }
    }

    /// Looks up whichever of `venues` this run has room for, and returns every
    /// place known once it is done — the ones already cached included, the ones
    /// a later run will still have to search for left out.
    private func mapItems(forVenues venues: [Venue]) async -> [Venue: MKMapItem] {
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

        // Read afresh and merged, rather than written over: a sheet showing a
        // venue may have looked one up while this run was working through the
        // library, and that answer is as good as any of these.
        //
        // What is pruned is what nothing asks about any more and nothing has
        // asked about lately — a hall met in Search and never kept is held on
        // to as long as a hall Maps could not find, because the reader may be
        // about to add that event.
        let wanted = Set(venues.map(\.key))
        self.cache = self.cache
            .merging(cache) { mine, run in mine.asked > run.asked ? mine : run }
            .filter { key, answer in
                wanted.contains(key) || answer.asked.timeIntervalSinceNow > -Self.patience
            }

        Self.log.info("venues: \(found.count, privacy: .public) of \(venues.count, privacy: .public) placed on the map")
        return found.compactMapValues { $0 }
    }

    /// What the log says a lookup came back with.
    private static func describe(_ item: MKMapItem?) -> String {
        guard let item else { return "Maps has no such place" }
        let coordinate = item.location.coordinate
        let kind = item.pointOfInterestCategory.map { "\($0.rawValue)" } ?? "an area"
        return "\(item.name ?? "?") (\(kind)) at \(coordinate.latitude),\(coordinate.longitude)"
    }

    /// Where one event is, for a screen showing it now — the first time the
    /// reader opens an event at a hall nothing has looked up yet, this is what
    /// searches for it and writes the answer down for everything after.
    ///
    /// Not rationed, unlike the run over the whole library: it is one hall,
    /// asked about because the reader is looking straight at it.
    func mapItem(for event: Event) async -> MKMapItem? {
        guard let venue = Venue(event) else { return nil }
        if let answer = cache[venue.key], !Self.isWorthAskingAgain(answer) {
            return answer.mapItem
        }
        do {
            let item = try await search(venue)
            var updated = cache
            updated[venue.key] = Answer(item)
            cache = updated
            Self.log.info("venue \(venue.key, privacy: .public) → \(Self.describe(item), privacy: .public)")
            return item
        } catch {
            // Not written down, so the next screen to ask tries again.
            Self.log.error("venue \(venue.key, privacy: .public) → search failed: \(error, privacy: .public)")
            return nil
        }
    }

    /// A place found stays found. A place Maps did not have is asked about
    /// again once the month is up, and anything settled under an older reading
    /// of Maps' answers is asked again now.
    private static func isWorthAskingAgain(_ answer: Answer) -> Bool {
        guard answer.ruleset == ruleset else { return true }
        return !answer.wasFound && answer.asked.timeIntervalSinceNow < -patience
    }

    /// The hall, as Maps has it. A throw is the search itself failing —
    /// offline, or throttled — and is worth stopping for; a venue Maps does
    /// not have returns nil.
    ///
    /// The hall is looked for by name first, and only once nothing answers to
    /// that name is the published address used to put the event in the right
    /// part of town. The order matters: an address places a pin sensibly but
    /// names nothing, while the hall itself is the thing being asked for.
    private func search(_ venue: Venue) async throws -> MKMapItem? {
        for query in venue.queries {
            let found = try await results(for: query)
            if let match = found.first(where: { Self.isPlausible($0, as: venue.name) }) {
                return match
            }
            if let loose = found.first?.name {
                Self.log.debug("venue \(venue.key, privacy: .public): \(query, privacy: .public) matched only \(loose, privacy: .public)")
            }
        }

        guard let address = venue.address, !address.isEmpty else { return nil }
        return try await results(for: address).first
    }

    /// One search. A venue Maps has never heard of is an empty list, not a
    /// failure: it is an answer, and it is worth writing down.
    private func results(for query: String) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request(naturalLanguageQuery: query, region: Self.japan)
        request.regionPriority = .default
        request.resultTypes = [.pointOfInterest, .address]
        do {
            return try await MKLocalSearch(request: request).start().mapItems
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        }
    }

    /// Whether a result really is the hall that was asked for.
    ///
    /// Maps answers a search it cannot place with something broader — ask it
    /// for Kアリーナ横浜 and it may offer 横浜, the city. Taking that would put
    /// the pin downtown, which is worse than drawing no map at all.
    ///
    /// What tells the two apart is not the name but the *kind* of answer. A
    /// point of interest is a place — a hall, a theatre, a park, something a
    /// person can stand in. A city is not one, and neither is a ward or a
    /// street: those come back as plain areas, and that is what a search Maps
    /// could not place falls back to.
    ///
    /// The name cannot be the test, because Maps answers in the reader's
    /// language and the site publishes in its own: the place Eventernote calls
    /// Kアリーナ横浜 is "K-Arena Yokohama" on a phone set to English, and the
    /// two have not a character in common. So a name is only asked for when
    /// the result is *not* a place — when it is, matching names merely confirm
    /// what the kind of answer already settled.
    private static func isPlausible(_ item: MKMapItem, as venue: String) -> Bool {
        guard !venue.isEmpty else { return true }
        if item.pointOfInterestCategory != nil { return true }
        guard let found = item.name.map(normalized), !found.isEmpty else { return false }
        if found.contains(normalized(venue)) { return true }
        return found == complex(of: venue)
    }

    /// The first word of a hall's name, where the name is more than one word.
    /// Nil for a name written as a single word, which has no complex to fall
    /// back to — only a city it might be confused with.
    private static func complex(of venue: String) -> String? {
        let words = withoutBrackets(venue).split(whereSeparator: \.isWhitespace)
        guard words.count > 1, let first = words.first else { return nil }
        return normalized(String(first))
    }

    /// Enough of a levelling to compare two spellings of one hall: case,
    /// spacing, punctuation, a bracketed alias and the full-width forms a
    /// Japanese page is apt to use all stop mattering. Both sides go through
    /// it, so it never has to be right about which form is canonical.
    private static func normalized(_ text: String) -> String {
        let plain = withoutBrackets(text)
        let folded = (plain.isEmpty ? text : plain)
            .applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return folded.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
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
    /// needs the address most: it is the only way to place a hall whose name
    /// Maps does not answer to.
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
