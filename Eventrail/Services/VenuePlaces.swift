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
/// **Only the sheet does the asking**, unless the reader asks for all of it.
/// A hall is looked up when the reader opens an event at it: one question,
/// asked because somebody is waiting for the answer. The mirror reads what has
/// been found and searches for nothing itself — it is handed the whole library
/// at once, and a run of hundreds of searches is what got the app throttled
/// into placing nothing at all. ``refresh(_:onProgress:)`` is the one way to
/// ask about everything, from a button in Settings, and it is paced for
/// exactly that reason.
///
/// The answers are kept, because a hall does not move.
final class VenuePlaces {
    static let shared = VenuePlaces()

    /// How a refresh of every hall the reader holds is going, or how it ended.
    ///
    /// `asking` is the only one anything waits on: a run of hundreds of halls
    /// takes minutes, and a screen that said nothing until it finished would
    /// be indistinguishable from one that had hung.
    enum Refresh: Hashable {
        case asking(done: Int, of: Int)
        case refreshed(found: Int, of: Int)
        case failed(String)
    }

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
        /// Who answered — ``Source``'s raw value, and nil where nobody did.
        /// Kept as a string so a source added later reads back as an unknown
        /// one rather than taking the whole cache down with it.
        var source: String?

        var wasFound: Bool { latitude != nil && longitude != nil }

        var placing: Placing? {
            guard let latitude, let longitude else { return nil }
            let item = MKMapItem(
                location: CLLocation(latitude: latitude, longitude: longitude),
                address: address.flatMap { MKAddress(fullAddress: $0, shortAddress: nil) }
            )
            item.name = name
            // An answer written before there were sources reads as the blunt
            // one, which is the safe way round: it widens a frame that did not
            // need widening, rather than claiming a precision it may not have.
            let source = self.source.flatMap(Source.init(rawValue:)) ?? .register
            return Placing(item: item, uncertainty: source.uncertainty)
        }

        init(_ found: MKMapItem?, from source: Source?) {
            name = found?.name
            address = found?.address?.fullAddress
            latitude = found?.location.coordinate.latitude
            longitude = found?.location.coordinate.longitude
            asked = .now
            ruleset = VenuePlaces.ruleset
            self.source = source?.rawValue
        }
    }

    /// Which of the two answers placed a hall.
    ///
    /// Written down because a silent fallback is indistinguishable from a
    /// working search, and because the two are not the same kind of answer:
    /// Maps places the building, the register places the block it stands on.
    /// The log says which, and so does the kept answer.
    private enum Source: String {
        case maps
        case register
        case openStreetMap = "osm"

        /// How far the coordinate might be from the hall's door.
        ///
        /// Zero where the answer names the building; the width of a 丁目 where
        /// it names the block the building stands on. Carried so that neither
        /// screen draws a block-level answer as though it were a doorstep —
        /// see ``VenuePlaces/Placing``.
        var uncertainty: CLLocationDistance {
            switch self {
            case .maps, .openStreetMap: 0
            case .register: 300
            }
        }
    }

    /// A hall, and how precisely it is placed.
    ///
    /// The second half matters because the three answers are not equally
    /// sharp, and a sharp pin on a blunt answer is a claim this app has not
    /// earned. The map under the venue widens its frame for one, and the
    /// calendar entry carries it as the radius EventKit keeps for exactly this.
    struct Placing: Sendable {
        let item: MKMapItem
        let uncertainty: CLLocationDistance
    }

    /// Whether this device may ask OpenStreetMap which building at the block
    /// is the hall — see ``VenueBuildings``.
    ///
    /// Per-device, like every other preference here, and on by default: it is
    /// only ever reached for a hall Maps could not place at all, and without
    /// it such a hall stays pinned to the middle of its 丁目. The switch exists
    /// because the service is donated and its policy is a real constraint, so
    /// the reader gets to stop this app from using it.
    var usesOpenStreetMap: Bool {
        get {
            UserDefaults.standard.object(forKey: Self.buildingsKey) as? Bool ?? true
        }
        set {
            guard newValue != usesOpenStreetMap else { return }
            UserDefaults.standard.set(newValue, forKey: Self.buildingsKey)
        }
    }

    private static let buildingsKey = "venueBuildings"

    /// Cached per device rather than in the archive: these are facts about the
    /// world, not records the reader owns, and every device can look them up
    /// for itself.
    private static let cacheKey = "venuePlaces"

    /// Which reading of Maps' answers the kept ones were made under. Raised
    /// whenever that reading changes, and everything older is simply asked
    /// again — now that an answer is kept only where Maps files it at the
    /// address Eventernote published rather than argued out of its name, now
    /// that a hall outside Japan is looked for at all, and now that a hall
    /// Maps had nothing for is asked of the register before being given up on.
    /// That last one is why every "no such place" already written down has to
    /// be asked again: most of them were never about the hall.
    private static let ruleset = 7

    /// How long "Maps has never heard of this hall" is believed for.
    ///
    /// Not forever, which is the point: a search can come back empty because
    /// the device was offline, or because Maps had not got round to the venue
    /// yet, and a permanent no would leave that event without a map for good.
    /// A month is long enough that nothing is asked repeatedly.
    private static let patience: TimeInterval = 30 * 24 * 60 * 60

    /// How long a refresh waits between halls.
    ///
    /// The reason this file says only a sheet does the asking: Maps throttles,
    /// and the run of searches a whole library makes at once is what once got
    /// every lookup refused until the app was restarted. A refresh asks for
    /// one hall at a time with a gap between them, which is slow — a few
    /// hundred halls is a couple of minutes — and is the price of getting an
    /// answer for all of them rather than for the first few.
    private static let pace: Duration = .milliseconds(500)

    /// How many halls in a row may fail before a refresh gives up.
    ///
    /// A single failure is an ordinary hiccup and the hall keeps whatever
    /// answer it had. Three in a row is Maps refusing to talk to this device,
    /// and carrying on would only be asking to be refused for longer.
    private static let givesUpAfter = 3

    /// How long an answer is kept once nothing has asked about it.
    ///
    /// A hall the reader still goes to is asked about again a year later and
    /// found again in one search; a hall they met once in Search and never
    /// kept stops taking up room. The alternative is a cache that only grows,
    /// on a device where it lives in `UserDefaults`.
    private static let keep: TimeInterval = 365 * 24 * 60 * 60

    /// Where a search looks first. Eventernote is a Japanese site publishing
    /// Japanese venues — the same assumption ``Event/publishedZone`` makes.
    ///
    /// A hint rather than a filter, but a strong one: pointed at Japan, Maps
    /// will not offer Shanghai at all. So it is only where a search looks
    /// *first*, and a hall it does not find there is asked for again with no
    /// hint — see ``search(_:)``.
    private static let japan = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.2, longitude: 138.25),
        span: MKCoordinateSpan(latitudeDelta: 14, longitudeDelta: 18)
    )

    /// Halls that have just been placed, for anything holding a copy of where
    /// the reader's events are.
    ///
    /// The calendar mirror writes what is known when it runs, and a hall
    /// nothing has looked up yet goes in as a line of text — see
    /// ``mapItems(for:)``. When the reader opens that event and Maps answers,
    /// the entry already in their calendar is the stale one: a name and no
    /// map. Nothing would ever go back for it, because the mirror runs on the
    /// reader's own edits and opening an event is not one.
    ///
    /// So a hall that has just been placed says so here, and ``EventStore``
    /// mirrors again. Only *newly* placed halls: a hall Maps still has nothing
    /// for changes no entry, and neither does one that came back where it
    /// already was.
    ///
    /// A refresh deliberately says nothing here, though it places halls by the
    /// hundred — it is started from a screen that mirrors the calendar itself
    /// once the whole run is done, which is one mirror rather than hundreds.
    var placings: AsyncStream<Void> { placed.stream }

    /// Buffering the newest alone, because these are a nudge rather than a
    /// list: a consumer that was busy needs to know that *something* moved,
    /// and a queue of them would only make it mirror twice.
    private let placed = AsyncStream<Void>.makeStream(
        of: Void.self, bufferingPolicy: .bufferingNewest(1)
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
    func mapItems(for events: [Event]) -> [Event.ID: Placing] {
        let cache = cache
        return events.reduce(into: [:]) { placed, event in
            // Read under the same rule a sheet reads it under, so an answer
            // settled by a reading since found wrong is not still being
            // written into the reader's calendar.
            guard let venue = Venue(event),
                  let answer = cache[venue.key], !Self.isWorthAskingAgain(answer),
                  let placing = answer.placing
            else { return }
            placed[event.id] = placing
        }
    }

    // MARK: - Asking

    /// Where one event is, for a screen showing it now — the first time the
    /// reader opens an event at a hall nothing has looked up yet, this is what
    /// goes and finds it and writes the answer down for everything after, the
    /// calendar mirror included.
    func mapItem(for event: Event) async -> Placing? {
        guard let venue = Venue(event) else { return nil }
        if let answer = cache[venue.key], !Self.isWorthAskingAgain(answer) {
            return answer.placing
        }
        let known = cache[venue.key]
        do {
            // The one caller that may upgrade a block to a building: somebody
            // is looking at this hall, and it is one hall. See ``VenueBuildings``.
            let found = try await search(venue, upgrading: usesOpenStreetMap)
            let answer = Answer(found?.item, from: found?.source)
            remember(answer, for: venue.key)
            Self.log.info("venue \(venue.key, privacy: .public) → \(Self.describe(found), privacy: .public)")
            // A hall that has just arrived somewhere it was not before. The
            // calendar entry written while it was nowhere is now wrong, and
            // this is what sends anything holding one back to correct it.
            if answer.wasFound,
               answer.latitude != known?.latitude || answer.longitude != known?.longitude {
                placed.continuation.yield()
            }
            return Answer(found?.item, from: found?.source).placing
        } catch {
            // Not written down, so the next screen to ask tries again.
            Self.log.error("venue \(venue.key, privacy: .public) → search failed: \(error, privacy: .public)")
            return nil
        }
    }

    /// Asks Maps again about every hall in `events`, whatever is already
    /// known about them, and writes down what comes back.
    ///
    /// The one thing in this file that goes looking for halls nobody is
    /// waiting on, and it exists because the alternative is worse: an answer
    /// settled when a hall was too new for Maps to have it, or before this app
    /// knew to check an answer against the published address, stays wrong
    /// until the reader happens to open that event again. A refresh is the
    /// reader saying "ask about all of them now".
    ///
    /// Asked one at a time, with ``pace`` between them, and abandoned after
    /// ``givesUpAfter`` failures in a row — see those for why. `onProgress` is
    /// called after each hall, because this takes long enough that a screen
    /// has to be able to say where it has got to.
    ///
    /// A hall the site published no address for is skipped rather than asked
    /// about: nothing here places a hall by name alone, so the answer would be
    /// "no such place" and it would not be true.
    func refresh(_ events: [Event], onProgress: (Refresh) -> Void) async -> Refresh {
        var venues: [Venue] = []
        var asked: Set<String> = []
        for event in events {
            guard let venue = Venue(event), venue.address?.isEmpty == false,
                  asked.insert(venue.key).inserted
            else { continue }
            venues.append(venue)
        }
        guard !venues.isEmpty else { return .refreshed(found: 0, of: 0) }

        Self.log.info("refreshing \(venues.count, privacy: .public) venues")
        var found = 0
        var failures = 0
        for (index, venue) in venues.enumerated() {
            if index > 0 {
                try? await Task.sleep(for: Self.pace)
            }
            // Not an error to report: the app is going away, and every answer
            // written so far is already kept.
            guard !Task.isCancelled else { return .refreshed(found: found, of: index) }
            do {
                // Never upgraded here: a refresh is hundreds of halls at once,
                // which is the one thing OpenStreetMap's policy forbids. The
                // block stands until the reader opens the event.
                let placed = try await search(venue, upgrading: false)
                remember(Answer(placed?.item, from: placed?.source), for: venue.key)
                if placed != nil { found += 1 }
                failures = 0
                Self.log.info("venue \(venue.key, privacy: .public) → \(Self.describe(placed), privacy: .public)")
            } catch {
                // The hall keeps whatever answer it had; only a run of these
                // ends the refresh.
                failures += 1
                Self.log.error("venue \(venue.key, privacy: .public) → search failed: \(error, privacy: .public)")
                if failures >= Self.givesUpAfter {
                    return .failed(error.localizedDescription)
                }
            }
            onProgress(.asking(done: index + 1, of: venues.count))
        }
        return .refreshed(found: found, of: venues.count)
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
    /// Both questions are asked twice: once pointed at Japan, where nearly
    /// every hall is, and then with no hint at all. The hint is strong enough
    /// to be a filter in practice — a search pointed at Japan will not offer
    /// Shanghai whatever it is asked — and dropping it is the whole of what a
    /// hall abroad needs. There is no switching maps to be done: the phone's
    /// own Maps has 梅赛德斯-奔驰文化中心 and answers with it as soon as it is
    /// not being told to look in Japan. The second pass costs a request only
    /// on a hall the first one missed.
    ///
    /// Nothing is placed without an address to check it against. An event
    /// opened straight from a search row has only the name until its own page
    /// is imported, and it is worth the wait: a name on its own is how a
    /// concert in Shanghai came to be pinned to a Mercedes showroom in Nara.
    private func search(_ venue: Venue, upgrading: Bool) async throws -> (item: MKMapItem, source: Source)? {
        guard let address = venue.address, !address.isEmpty else { return nil }

        for region in [Self.japan, nil] {
            if !venue.plainName.isEmpty {
                let halls = try await results(for: venue.plainName, kinds: [.pointOfInterest], in: region)
                if let hall = halls.first(where: { Self.stands($0, at: address) }) {
                    return (hall, .maps)
                }
            }
            let places = try await results(for: address, kinds: [.pointOfInterest, .address], in: region)
            if let place = places.first(where: { Self.stands($0, at: address) }) {
                return (place, .maps)
            }
        }

        // Maps had nothing, which is where the register is asked — see
        // ``JapanAddresses``. Second rather than first because Maps' answer is
        // the better one wherever there is one: it places the building and
        // names it in the reader's language, and this places the block. A
        // reader whose phone can see Japan never reaches this line.
        guard let block = try await JapanAddresses.shared.place(at: address) else { return nil }

        // The block is the answer. Where somebody is waiting on this hall, it
        // is also the thing that makes it safe to ask which building at that
        // block carries the name — every candidate is held against a
        // coordinate the register already vouched for.
        if upgrading, !venue.plainName.isEmpty,
           let building = try? await VenueBuildings.shared.building(
               named: venue.plainName, near: block.coordinate) {
            let item = MKMapItem(
                location: CLLocation(latitude: building.coordinate.latitude,
                                     longitude: building.coordinate.longitude),
                address: MKAddress(fullAddress: block.title, shortAddress: nil)
            )
            // Eventernote's name, not the map's, for the reason the register's
            // answer keeps it too — see ``item(at:called:)``.
            item.name = venue.plainName
            return (item, .openStreetMap)
        }
        return (Self.item(at: block, called: venue.plainName), .register)
    }

    /// The register's block as a map item, so that everything downstream —
    /// the kept answer, the map under the venue, the calendar entry — handles
    /// it exactly as it handles one of Maps' own.
    ///
    /// The hall keeps Eventernote's name for it. There is no name in the
    /// register's answer to take instead, and the site's is the one the reader
    /// knows: it is already what the calendar entry reads, and it is what Maps
    /// drops a pin under when the reader taps through.
    private static func item(at block: JapanAddresses.Place, called name: String) -> MKMapItem {
        let item = MKMapItem(
            location: CLLocation(latitude: block.coordinate.latitude, longitude: block.coordinate.longitude),
            address: MKAddress(fullAddress: block.title, shortAddress: nil)
        )
        item.name = name.isEmpty ? block.title : name
        return item
    }

    /// One search. A hall Maps has never heard of is an empty list, not a
    /// failure: it is an answer, and it is worth writing down.
    ///
    /// A nil region leaves the hint off altogether, which is how Maps is
    /// asked about somewhere it has no reason to think of.
    private func results(
        for query: String,
        kinds: MKLocalSearch.ResultType,
        in region: MKCoordinateRegion?
    ) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let region {
            request.region = region
            request.regionPriority = .default
        }
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
        // An address Maps answers with as a place of its own carries it as its
        // name and leaves the address field empty — 上海市浦东新区世博大道
        // 1200号 comes back exactly so, and it is the best answer there is for
        // that hall.
        guard let found = (item.address?.fullAddress).flatMap({ $0.isEmpty ? nil : $0 }) ?? item.name
        else { return false }
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

    /// What the log says a lookup came back with, and who said it.
    ///
    /// The source is in the line because the two answers are not
    /// interchangeable: `maps` placed the building, `register` placed the
    /// block the address names, and a run of the second where the first used
    /// to answer is this device having lost sight of Japan rather than the
    /// halls having moved.
    private static func describe(_ found: (item: MKMapItem, source: Source)?) -> String {
        guard let found else { return "nobody has such a place" }
        let coordinate = found.item.location.coordinate
        let kind = found.item.pointOfInterestCategory.map { "\($0.rawValue)" } ?? "the address"
        return "[\(found.source.rawValue)] \(found.item.name ?? "?") (\(kind)) at \(coordinate.latitude),\(coordinate.longitude)"
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
