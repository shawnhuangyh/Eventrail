import CoreLocation
import Foundation

/// Which building at the block is the hall.
///
/// The last of the three answers to "where is this venue", and the only one
/// that is an upgrade rather than a rescue. ``JapanAddresses`` places the
/// block the published address names, which is right but blunt: the register
/// answers with the centre of a 丁目, and the hall's door is anywhere from
/// sixty to three hundred metres off it. On a map seven hundred metres across
/// that is a pin visibly beside the building rather than on it.
///
/// So where the register has placed a block and somebody is looking at it,
/// OpenStreetMap is asked which building at that block carries the hall's
/// name. The block is what makes the question safe to ask: a name on its own
/// is how a concert in Shanghai came to be pinned to a Mercedes showroom in
/// Nara, and every candidate here is held against a coordinate the register
/// already vouched for. A hall too far from it is somebody else with the same
/// name — the 至誠ホール thirteen kilometres from 大阪城ホール, the bus stop
/// called ぴあアリーナMM — and is refused.
///
/// **Only ever asked because the reader asked.** OpenStreetMap's geocoder is
/// a donated service whose usage policy allows one request a second across
/// all of an app's users, discourages bulk geocoding, and tolerates a small
/// one-off run made one request at a time with the results kept. So it is
/// reached from a sheet the reader has open, and from the refresh they start
/// in Settings — paced here, asked once per hall for good, and stopped at the
/// first refusal — and never from an import, which nobody asked for.
///
/// Crediting OpenStreetMap is a condition of use, and is done in ``AboutView``.
nonisolated struct VenueBuildings: Sendable {
    static let shared = VenueBuildings()

    struct Building: Sendable {
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    enum Failure: Error {
        case http(Int)
        case unreadable
    }

    private static let endpoint =
        URL(string: "https://nominatim.openstreetmap.org/search")!

    /// The policy asks that requests be attributable to the app making them.
    private static let userAgent =
        "Eventrail/1.0 (iOS; https://www.eventernote.com companion)"

    /// How far from the register's block a building may stand and still be the
    /// hall.
    ///
    /// Generous, because the two are measuring different things: the register
    /// answers with the centre of a 丁目 and a hall the size of 幕張メッセ
    /// covers several. It is not a precision figure — it is the distance past
    /// which an answer is a different place with the same name, and every real
    /// hall tried came back inside two hundred metres of it.
    private static let tolerance: CLLocationDistance = 800

    /// Kinds of place that are never the venue, however exactly they match its
    /// name. The bus stop outside ぴあアリーナMM is called ぴあアリーナMM, and
    /// it is a hundred and sixty metres from the hall.
    private static let notVenues: Set<String> = [
        "highway", "railway", "public_transport", "barrier", "waterway"
    ]

    /// The part of a hall's name that says which room inside it, which
    /// Eventernote appends and OpenStreetMap does not carry. Dropped one at a
    /// time on a retry: 幕張メッセ国際展示場 is 幕張メッセ on the map, and
    /// パシフィコ横浜 国立大ホール is パシフィコ横浜. The answer is then the
    /// complex rather than the room in it, which is the honest trade — the
    /// alternative is no answer at all.
    private static let rooms = [
        "メインアリーナ", "サブアリーナ", "国際展示場", "国立大ホール",
        "第一体育館", "第二体育館", "展示ホール", "シティホール",
        "大ホール", "中ホール", "小ホール"
    ]

    /// At most three questions for one hall, so a name the map has never heard
    /// of costs a bounded wait rather than a walk down every shortening of it.
    private static let attempts = 3

    var session: URLSession = .shared

    /// The hall at `reference`, if the map has a building there under `name`.
    ///
    /// A throw is the request failing. A nil is the map having nothing there,
    /// which leaves the block standing as the answer.
    func building(named name: String, near reference: CLLocationCoordinate2D) async throws -> Building? {
        var query = name.trimmingCharacters(in: .whitespaces)
        for _ in 0..<Self.attempts {
            guard !query.isEmpty else { return nil }
            await Self.pace.wait()
            if let building = try await nearest(to: reference, matching: query) {
                return building
            }
            guard let shorter = Self.withoutRoom(query) else { return nil }
            query = shorter
        }
        return nil
    }

    /// The closest candidate inside ``tolerance`` that could be a venue at all.
    private func nearest(
        to reference: CLLocationCoordinate2D, matching query: String
    ) async throws -> Building? {
        // Japan only, so a hall's namesake abroad is never even offered.
        let rows = try await rows(for: query, in: "jp")
        return Self.nearest(in: rows, to: reference, within: Self.tolerance, called: query)
    }

    private static func nearest(
        in rows: [Row], to reference: CLLocationCoordinate2D,
        within tolerance: CLLocationDistance, called query: String
    ) -> Building? {
        let origin = CLLocation(latitude: reference.latitude, longitude: reference.longitude)
        return rows
            .compactMap { row -> (away: CLLocationDistance, building: Building)? in
                guard let coordinate = row.venueCoordinate else { return nil }
                let away = origin.distance(from: CLLocation(latitude: coordinate.latitude,
                                                            longitude: coordinate.longitude))
                guard away <= tolerance else { return nil }
                return (away, Building(name: row.name ?? query, coordinate: coordinate))
            }
            .min { $0.away < $1.away }?
            .building
    }

    /// One search, in `country` where that is known — see
    /// ``VenueCountries/searchScope(for:)``.
    private func rows(for query: String, in country: String?) async throws -> [Row] {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "limit", value: "10"),
            // The country each answer is in, which is what a hall abroad is
            // dated by — see ``VenueCountries/timeZone(forCountry:)``.
            URLQueryItem(name: "addressdetails", value: "1"),
            // In Japanese, or Kアリーナ横浜 comes back as "K-Arena Yokohama"
            // — which is exactly the name this app declines to be argued into.
            URLQueryItem(name: "accept-language", value: "ja")
        ]
        if let country { items += VenueCountries.searchScope(for: country) }
        components?.queryItems = items
        guard let url = components?.url else { throw Failure.unreadable }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            throw Failure.http(status)
        }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else {
            throw Failure.unreadable
        }
        return rows
    }

    // MARK: - A hall abroad

    /// Where a hall outside Japan is, for a phone whose Maps cannot be trusted
    /// with it — see ``VenuePlaces/search(_:mayAskOpenStreetMap:)``.
    struct Place: Sendable {
        let coordinate: CLLocationCoordinate2D
        /// The ISO code OpenStreetMap files it under, lower case.
        let country: String?
        /// Whether the hall's own building was found, or only its address.
        let isBuilding: Bool
    }

    /// How far from its address a hall abroad may stand and still be the hall.
    ///
    /// Wider than ``tolerance``: an address abroad is placed by street and
    /// number rather than by a register's block, and a campus arena like the
    /// one behind 안암로 145 sits well inside its grounds.
    private static let abroadTolerance: CLLocationDistance = 2000

    /// The hall abroad at `address`, the way the register and this file place
    /// one in Japan: the address first, as the anchor, and then the building
    /// carrying the hall's name near it.
    ///
    /// Held to the address wherever the address can be placed, because a name
    /// on its own is how a concert in Shanghai came to be pinned to a Mercedes
    /// showroom in Nara. Where it cannot, a name is believed only inside the
    /// country the address plainly names (`country`) — Hangul is Korea, 香港 is
    /// Hong Kong — and not at all where it names none. Three requests at most,
    /// paced like every other.
    ///
    /// `address` may be nil — the hall's page published none, and the country
    /// was read off the event's title instead (see ``VenuePlaces``). Then the
    /// name is all there is, and it is believed only inside `country`.
    func place(named name: String, at address: String?, country: String?) async throws -> Place? {
        var anchor: Row?
        if let address, !address.isEmpty {
            await Self.pace.wait()
            anchor = try await rows(for: address, in: country).first { $0.venueCoordinate != nil }
        }
        // The country the address plainly names before the one OpenStreetMap
        // files it under: that is `cn` for Hong Kong, and a name search over
        // the whole of China is not the one meant.
        let within = country ?? anchor?.address?.countryCode

        if within != nil {
            for query in Self.shortenings(of: name) {
                await Self.pace.wait()
                let named = try await rows(for: query, in: within)
                if let anchor, let reference = anchor.venueCoordinate {
                    if let building = Self.nearest(in: named, to: reference,
                                                   within: Self.abroadTolerance, called: query) {
                        return Place(coordinate: building.coordinate, country: within, isBuilding: true)
                    }
                } else if let row = named.first(where: { $0.venueCoordinate != nil }),
                          let coordinate = row.venueCoordinate {
                    return Place(coordinate: coordinate, country: within, isBuilding: true)
                }
            }
        }
        guard let anchor, let coordinate = anchor.venueCoordinate else { return nil }
        return Place(coordinate: coordinate, country: within, isBuilding: false)
    }

    /// The name, then shorter forms of it, cut where a dash or a space says
    /// which part is which.
    ///
    /// A space usually follows whose grounds the hall stands in, so the part
    /// *after* it is tried first — 高麗大学校 化汀 体育館 is 化汀体育館 on the
    /// map, and 高麗大学校 alone is the whole campus, eight hundred metres from
    /// the arena. A dash usually comes before a room in the building, so only
    /// the part *before* it is tried — 歷山酒店-宴會廳 is 歷山酒店, and 宴會廳
    /// alone is every banquet hall in the city.
    static func shortenings(of name: String) -> [String] {
        let whole = name.trimmingCharacters(in: .whitespaces)
        guard !whole.isEmpty else { return [] }
        // Not the long-vowel ー, which is part of アリーナ rather than a break.
        guard let cut = whole.firstIndex(where: { "-－‐― 　".contains($0) }) else { return [whole] }
        let head = whole[..<cut].trimmingCharacters(in: .whitespaces)
        let tail = whole[whole.index(after: cut)...].trimmingCharacters(in: .whitespaces)
        let isSpace = whole[cut] == " " || whole[cut] == "　"
        var tried = [whole]
        for candidate in isSpace ? [tail, head] : [head]
        where !candidate.isEmpty && !tried.contains(candidate) {
            tried.append(candidate)
        }
        return tried
    }

    /// The name with one trailing room designation removed, or with its last
    /// word dropped where it carries none — nil once there is nothing left to
    /// shorten.
    private static func withoutRoom(_ name: String) -> String? {
        for room in rooms where name.hasSuffix(room) && name.count > room.count {
            return String(name.dropLast(room.count)).trimmingCharacters(in: .whitespaces)
        }
        guard let separator = name.lastIndex(where: { $0 == " " || $0 == "　" }) else { return nil }
        let shorter = String(name[name.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
        return shorter.isEmpty ? nil : shorter
    }

    /// Keeps this app to one request a second however many screens ask at
    /// once, because the policy's limit is over the whole app rather than over
    /// each screen in it.
    private static let pace = Pace(gap: .milliseconds(1100))

    private actor Pace {
        private let gap: Duration
        private var next: ContinuousClock.Instant?

        init(gap: Duration) { self.gap = gap }

        func wait() async {
            let now = ContinuousClock.now
            let due = next.map { max($0, now) } ?? now
            next = due.advanced(by: gap)
            if due > now {
                try? await Task.sleep(until: due, clock: .continuous)
            }
        }
    }

    /// One candidate. Every field optional for the reason every accessor in
    /// this app is failable: a changed shape costs a dropped row, never a
    /// wrong coordinate. `lat` and `lon` really are published as strings.
    private struct Row: Decodable {
        var lat: String?
        var lon: String?
        var name: String?
        var category: String?
        var address: Address?

        struct Address: Decodable {
            var countryCode: String?

            enum CodingKeys: String, CodingKey {
                case countryCode = "country_code"
            }
        }

        /// Where the row stands, where it could be a venue at all.
        var venueCoordinate: CLLocationCoordinate2D? {
            guard let category, !VenueBuildings.notVenues.contains(category),
                  let latitude = lat.flatMap(Double.init),
                  let longitude = lon.flatMap(Double.init)
            else { return nil }
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
        }
    }
}
