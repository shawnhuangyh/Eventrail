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
    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "venues")

    /// What Eventernote knows about where an event is. Two events at the same
    /// hall ask the same question and are looked up once, which is why this and
    /// not the event is what a lookup is keyed by.
    private struct Venue: Hashable {
        let name: String
        let address: String?

        /// Nil where there is no hall to ask about — neither a name nor an
        /// address is something Maps can be asked for.
        init?(name: String, address: String?) {
            guard !name.isEmpty || address != nil else { return nil }
            self.name = name
            self.address = address
        }

        /// Nil where the site has not named a hall yet — it announces plenty of
        /// events before it has booked one.
        init?(_ event: Event) {
            self.init(name: event.venue, address: event.publishedAddress)
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
        /// Which clock the hall keeps, as Maps files it. An identifier rather
        /// than a `TimeZone` for the reason the source is a string: a zone the
        /// system later drops reads back as nothing rather than as an error.
        ///
        /// Nil where nobody was asked, and nil where Maps had no zone to give
        /// — ``askedZone`` is what tells those two apart.
        var timeZone: String?
        /// Whether anything ever asked which clock this hall keeps. False on
        /// every answer written before there was a question, which is what
        /// sends a hall abroad back to Maps exactly once.
        var askedZone: Bool?
        /// Whether OpenStreetMap has already been asked which building at
        /// this block is the hall, and had none to offer. A block it turned
        /// down stays a block rather than being asked about on every sheet.
        var triedBuilding: Bool?

        var wasFound: Bool { latitude != nil && longitude != nil }

        /// Which clock the hall keeps, as far as this answer settles it.
        ///
        /// Japan is one zone, so a hall the answer places inside it is on Tokyo
        /// time whatever Maps did or did not say — and that is nearly every
        /// hall Eventernote publishes. Only a hall abroad needs Maps' own
        /// answer, and only there can this be nil.
        var zone: TimeZone? {
            guard let latitude, let longitude else { return nil }
            if JapanAddresses.isInJapan(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
                return Event.publishedZone
            }
            return timeZone.flatMap(TimeZone.init(identifier:))
        }

        /// Whether this hall is worth one more search for the sake of its
        /// clock: found, found outside Japan, and never asked.
        ///
        /// The narrowest question that can be asked here. Every hall in Japan
        /// answers itself, so the halls this sends back to Maps are the handful
        /// a reader has abroad — where a whole-cache re-reading would be
        /// hundreds of searches for an answer only these few need.
        var needsZone: Bool {
            askedZone != true && wasFound && zone == nil
        }

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
            return Placing(item: item, uncertainty: source.uncertainty, timeZone: zone)
        }

        init(_ found: MKMapItem?, from source: Source?) {
            name = found?.name
            address = found?.address?.fullAddress
            latitude = found?.location.coordinate.latitude
            longitude = found?.location.coordinate.longitude
            asked = .now
            ruleset = VenuePlaces.ruleset
            self.source = source?.rawValue
            // Maps carries the zone with the place, so a hall abroad is placed
            // and dated in one search. The register and OpenStreetMap answer
            // only about Japan, where ``zone`` needs nobody's help.
            timeZone = found?.timeZone?.identifier
            askedZone = true
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
        /// Which clock the hall keeps — see ``Answer/zone``. Carried because a
        /// placing is the only thing that establishes it, and a screen showing
        /// the hall's times has to be able to tell a clock it knows from the
        /// one an import assumed.
        let timeZone: TimeZone?
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
    ///
    /// Raised again now that a hall the site places in Japan is only ever
    /// answered with somewhere in Japan. What that reading turns down is
    /// already written down on the phones it was wrong on, and a pin on the
    /// mainland for a hall in 此花区 does not correct itself.
    private static let ruleset = 8

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

    /// Which clock each of `events` is kept on, as far as anything has already
    /// found out — the venue's own, wherever the hall has been placed.
    ///
    /// Read from what the placings already wrote down rather than asked for,
    /// exactly as ``mapItems(for:)`` is, and for the same reason: this is
    /// handed the whole library at once. An event at a hall nothing has looked
    /// up yet is simply absent, and goes on being read on Tokyo time — which
    /// is right for every hall in Japan and is where an import starts every
    /// hall off. See ``Event/published(in:)``.
    func timeZones(for events: [Event]) -> [Event.ID: TimeZone] {
        let cache = cache
        return events.reduce(into: [:]) { zones, event in
            guard let venue = Venue(event),
                  let answer = cache[venue.key], !Self.isWorthAskingAgain(answer),
                  let zone = answer.zone
            else { return }
            zones[event.id] = zone
        }
    }

    /// How many of the halls behind `events` each answer placed, for the
    /// screen that explains the three of them.
    ///
    /// Counted per hall rather than per event, since that is what is asked
    /// about, and only over halls with a published address — a hall without
    /// one is never asked about at all. Read from what is written down, like
    /// ``mapItems(for:)``, so it asks nothing of anyone.
    func breakdown(for events: [Event]) -> Breakdown {
        let cache = cache
        var breakdown = Breakdown()
        for venue in questions(in: events, include: { _ in true }) {
            guard let answer = cache[venue.key], !Self.isWorthAskingAgain(answer), answer.wasFound else {
                breakdown.unplaced += 1
                continue
            }
            switch answer.source.flatMap(Source.init(rawValue:)) ?? .register {
            case .maps: breakdown.maps += 1
            case .register: breakdown.register += 1
            case .openStreetMap: breakdown.openStreetMap += 1
            }
        }
        return breakdown
    }

    /// Halls by who placed them — see ``breakdown(for:)``.
    struct Breakdown: Equatable {
        var maps = 0
        var register = 0
        var openStreetMap = 0
        /// Not asked yet, or asked and not found.
        var unplaced = 0
    }

    // MARK: - Asking

    /// Where one event is, for a screen showing it now — the first time the
    /// reader opens an event at a hall nothing has looked up yet, this is what
    /// goes and finds it and writes the answer down for everything after, the
    /// calendar mirror included.
    func mapItem(for event: Event) async -> Placing? {
        guard let venue = Venue(event) else { return nil }
        return await mapItem(for: venue)
    }

    /// The same question asked about a hall rather than about something held
    /// there, for ``VenueView`` — which knows the hall's own page and so knows
    /// its name and address without an event in front of it.
    ///
    /// Keyed on exactly what an event's lookup is keyed on, so a hall the
    /// reader has already opened an event at is answered from what that
    /// lookup wrote down rather than asked about again.
    func mapItem(forVenue name: String, address: String?) async -> Placing? {
        guard let venue = Venue(name: name, address: address) else { return nil }
        return await mapItem(for: venue)
    }

    private func mapItem(for venue: Venue) async -> Placing? {
        // A hall abroad that nothing has asked the clock of is asked again,
        // though it is placed perfectly well — see ``Answer/needsZone``. One
        // search settles it for good, and until it is settled every event held
        // there sits an hour or a day out in the reader's calendar.
        let known = cache[venue.key]
        if let known, !Self.isWorthAskingAgain(known), !known.needsZone {
            // Settled already — but a block settled by an import, which may
            // not ask OpenStreetMap, or while the switch was off, is narrowed
            // to its building here, the first time somebody opens it.
            let answer = await narrowed(known, for: venue)
            if answer.triedBuilding != known.triedBuilding {
                remember(answer, for: venue.key)
            }
            if answer.latitude != known.latitude || answer.longitude != known.longitude {
                placed.continuation.yield()
            }
            return answer.placing
        }
        do {
            let found = try await search(venue)
            Self.log.info("venue \(venue.key, privacy: .public) → \(Self.describe(found), privacy: .public)")
            // The one caller that may upgrade a block to a building: somebody
            // is looking at this hall, and it is one hall. See ``VenueBuildings``.
            let answer = await narrowed(
                Self.carrying(Answer(found?.item, from: found?.source), from: known), for: venue)
            remember(answer, for: venue.key)
            // A hall that has just arrived somewhere it was not before. The
            // calendar entry written while it was nowhere is now wrong, and
            // this is what sends anything holding one back to correct it.
            if answer.wasFound,
               answer.latitude != known?.latitude || answer.longitude != known?.longitude {
                placed.continuation.yield()
            }
            return answer.placing
        } catch {
            // Not written down, so the next screen to ask tries again.
            Self.log.error("venue \(venue.key, privacy: .public) → search failed: \(error, privacy: .public)")
            return nil
        }
    }

    /// `answer`, narrowed from the block the register placed to the building
    /// OpenStreetMap says carries the hall's name — where the reader allows
    /// that, and where it has not been asked about this hall already.
    ///
    /// Apart from the search rather than inside it, because a block is not
    /// always settled by a sheet: an import places halls by the hundred and
    /// never asks OpenStreetMap, so a block it wrote down is narrowed only
    /// when the reader later opens an event there. Kept inside the search,
    /// that never happened — the sheet found the block already written down
    /// and took it as it was.
    ///
    /// A throw is OpenStreetMap failing or refusing, and the answer is then
    /// left as it was and unmarked, so the next ask tries again; only a
    /// building OpenStreetMap does not have is written down as tried.
    private func narrow(_ answer: Answer, for venue: Venue) async throws -> Answer {
        guard usesOpenStreetMap, answer.source == Source.register.rawValue,
              answer.triedBuilding != true, !venue.plainName.isEmpty,
              let latitude = answer.latitude, let longitude = answer.longitude
        else { return answer }
        var narrowed = answer
        if let building = try await VenueBuildings.shared.building(
            named: venue.plainName,
            near: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
            narrowed.latitude = building.coordinate.latitude
            narrowed.longitude = building.coordinate.longitude
            narrowed.source = Source.openStreetMap.rawValue
            Self.log.info("venue \(venue.key, privacy: .public) → narrowed to its building by osm")
        }
        narrowed.triedBuilding = true
        return narrowed
    }

    /// ``narrow(_:for:)`` for a sheet, where a failure is the hall staying a
    /// block this once rather than anything to report.
    private func narrowed(_ answer: Answer, for venue: Venue) async -> Answer {
        do {
            return try await narrow(answer, for: venue)
        } catch {
            Self.log.error("venue \(venue.key, privacy: .public) → building search failed: \(error, privacy: .public)")
            return answer
        }
    }

    /// A fresh block from the register, carrying over what OpenStreetMap
    /// already said about it.
    ///
    /// The key is the hall's name and address, so a hall asked about again
    /// stands at the same block, and OpenStreetMap's answer about that block
    /// still holds: the building it found is kept rather than asked for
    /// again, and a building it did not have is not asked for again either.
    /// Without this, every refresh would ask about every building afresh.
    private static func carrying(_ fresh: Answer, from known: Answer?) -> Answer {
        guard fresh.source == Source.register.rawValue, let known, known.ruleset == ruleset
        else { return fresh }
        if known.source == Source.openStreetMap.rawValue {
            var kept = known
            kept.asked = fresh.asked
            return kept
        }
        var fresh = fresh
        if known.triedBuilding == true { fresh.triedBuilding = true }
        return fresh
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
    ///
    /// With `includingMaps` false, a hall Maps itself placed is left alone:
    /// that answer is the building, checked against the published address,
    /// and asking again is minutes of searches for the same pin. What is
    /// left is the halls worth another try — a block, a building from
    /// OpenStreetMap, nothing at all — which is what a reader in mainland
    /// China refreshing for the sake of the switch above wants.
    func refresh(_ events: [Event], includingMaps: Bool, onProgress: (Refresh) -> Void) async -> Refresh {
        let cache = cache
        let venues = questions(in: events) { venue in
            guard !includingMaps, let answer = cache[venue.key],
                  !Self.isWorthAskingAgain(answer), !answer.needsZone
            else { return true }
            return answer.source != Source.maps.rawValue
        }
        Self.log.info("refreshing \(venues.count, privacy: .public) venues\(includingMaps ? "" : " not placed by maps", privacy: .public)")
        return await ask(venues, narrowing: true, onProgress: onProgress)
    }

    /// Asks Maps about the halls nothing has an answer for yet, and leaves
    /// every hall it already knows alone.
    ///
    /// What an import owes the reader, and the reason it can be done without
    /// their asking where ``refresh(_:onProgress:)`` cannot: the work is the
    /// size of what has just arrived rather than the size of the library, so
    /// a re-import of a library that has not moved asks Maps nothing at all.
    /// A first import of a hundred halls is still a hundred questions, paced
    /// the same way and for the same reason, which is why it runs on its own
    /// behind the import rather than holding it open.
    ///
    /// Unlike a refresh and a sheet, it never upgrades a block to a
    /// building: nobody asked for this run, and OpenStreetMap asks that apps
    /// not geocode in bulk on their own account. The block stands
    /// until the reader opens the event. See ``VenueBuildings``.
    func placeUnplaced(_ events: [Event], onProgress: (Refresh) -> Void) async -> Refresh {
        let cache = cache
        let venues = questions(in: events) { venue in
            guard let answer = cache[venue.key] else { return true }
            return Self.isWorthAskingAgain(answer) || answer.needsZone
        }
        Self.log.info("placing \(venues.count, privacy: .public) venues nothing had yet")
        return await ask(venues, narrowing: false, onProgress: onProgress)
    }

    /// One question per hall, in the order the halls are first met, keeping
    /// only those `include` wants asked about.
    ///
    /// Keyed by the hall rather than the event for the reason ``Venue`` gives:
    /// two events in the same building are one question.
    private func questions(in events: [Event], include: (Venue) -> Bool) -> [Venue] {
        var venues: [Venue] = []
        var asked: Set<String> = []
        for event in events {
            guard let venue = Venue(event), venue.address?.isEmpty == false,
                  asked.insert(venue.key).inserted, include(venue)
            else { continue }
            venues.append(venue)
        }
        return venues
    }

    /// The paced run itself, shared by the two ways of starting one.
    ///
    /// `narrowing` is whether a block may be narrowed to its building as the
    /// run goes — true for a refresh the reader asked for, false for an
    /// import. OpenStreetMap's policy tolerates a small one-off run from one
    /// device, one request at a time and cached; the pace is kept by
    /// ``VenueBuildings``, each hall is asked about once for good (see
    /// ``carrying(_:from:)``), and the first refusal ends its part of the run.
    private func ask(_ venues: [Venue], narrowing: Bool, onProgress: (Refresh) -> Void) async -> Refresh {
        guard !venues.isEmpty else { return .refreshed(found: 0, of: 0) }
        // The count before the first answer, so a screen watching this has
        // something truthful to show for the minutes that follow.
        onProgress(.asking(done: 0, of: venues.count))

        var found = 0
        var failures = 0
        var narrowing = narrowing
        let cache = cache
        for (index, venue) in venues.enumerated() {
            if index > 0 {
                try? await Task.sleep(for: Self.pace)
            }
            // Not an error to report: the app is going away, and every answer
            // written so far is already kept.
            guard !Task.isCancelled else { return .refreshed(found: found, of: index) }
            do {
                let placed = try await search(venue)
                Self.log.info("venue \(venue.key, privacy: .public) → \(Self.describe(placed), privacy: .public)")
                var answer = Self.carrying(Answer(placed?.item, from: placed?.source), from: cache[venue.key])
                if narrowing {
                    do {
                        answer = try await narrow(answer, for: venue)
                    } catch {
                        // The block stands, and so does every block after it:
                        // a service that refused once will refuse the next.
                        narrowing = false
                        Self.log.error("venue \(venue.key, privacy: .public) → building search failed, narrowing stopped: \(error, privacy: .public)")
                    }
                }
                remember(answer, for: venue.key)
                if placed != nil { found += 1 }
                failures = 0
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
    /// A hall abroad is asked for twice: once pointed at Japan, where nearly
    /// every hall is, and then with no hint at all. Dropping the hint is the
    /// whole of what such a hall needs — there is no switching maps to be
    /// done: the phone's own Maps has 梅赛德斯-奔驰文化中心 and answers with it
    /// as soon as it is not being told to look in Japan. The second pass costs
    /// a request only on a hall the first one missed.
    ///
    /// **A hall whose address opens with a Japanese prefecture is asked for
    /// once, and only ever answered with somewhere in Japan.** The hint is a
    /// bias and not a filter, which only shows on a phone served by the map
    /// provider for mainland China: that provider has no Japanese venue to
    /// offer, so it answers a Japanese hall with whichever of its own places
    /// happens to share a number with the address — Zepp Osaka Bayside, whose
    /// 桜島1丁目1-61 needs a 1 or a 61 from anywhere to match, came back
    /// pinned on the mainland. So the answer is held against the country the
    /// address names as well as against the address itself, and a hall in
    /// Japan that Maps cannot place in Japan is left to the register below,
    /// which answers the same on every phone. A hall abroad keeps both passes
    /// and both maps, and is unaffected.
    ///
    /// Nothing is placed without an address to check it against. An event
    /// opened straight from a search row has only the name until its own page
    /// is imported, and it is worth the wait: a name on its own is how a
    /// concert in Shanghai came to be pinned to a Mercedes showroom in Nara.
    private func search(_ venue: Venue) async throws -> (item: MKMapItem, source: Source)? {
        guard let address = venue.address, !address.isEmpty else { return nil }

        // The country the site itself published, read the way every other
        // screen reads it. A hall it places in Japan is asked for with the
        // hint on and nowhere else; a hall it places nowhere — abroad, or an
        // address too odd to name a prefecture — is asked for both ways.
        let inJapan = Region.containing(address: address) != nil
        let regions: [MKCoordinateRegion?] = inJapan ? [Self.japan] : [Self.japan, nil]

        for region in regions {
            if !venue.plainName.isEmpty {
                let halls = try await results(for: venue.plainName, kinds: [.pointOfInterest], in: region)
                if let hall = halls.first(where: { Self.answers($0, for: address, inJapan: inJapan) }) {
                    return (hall, .maps)
                }
            }
            let places = try await results(for: address, kinds: [.pointOfInterest, .address], in: region)
            if let place = places.first(where: { Self.answers($0, for: address, inJapan: inJapan) }) {
                return (place, .maps)
            }
        }

        // Maps had nothing, which is where the register is asked — see
        // ``JapanAddresses``. Second rather than first because Maps' answer is
        // the better one wherever there is one: it places the building and
        // names it in the reader's language, and this places the block. A
        // reader whose phone can see Japan never reaches this line.
        guard let block = try await JapanAddresses.shared.place(at: address) else { return nil }

        // The block is the answer. Where somebody is waiting on this hall,
        // ``narrowed(_:for:)`` may then ask which building at it is the hall.
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

    /// Whether Maps' answer is one this app may keep for `address`.
    ///
    /// Two questions rather than one. The address settles which place it is,
    /// and the country settles whether it can be a place at all: a hall
    /// Eventernote files in Japan is not on the mainland, however many numbers
    /// the two addresses turn out to share. The second question only ever has
    /// anything to say on a phone whose Maps cannot see Japan — see
    /// ``search(_:)`` — and a hall it turns down is not left
    /// unplaced but handed to the register, which can.
    private static func answers(_ item: MKMapItem, for address: String, inJapan: Bool) -> Bool {
        guard stands(item, at: address) else { return false }
        return !inJapan || JapanAddresses.isInJapan(item.location.coordinate)
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
