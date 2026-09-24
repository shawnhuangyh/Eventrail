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
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "limit", value: "10"),
            // Japan only, so a hall's namesake abroad is never even offered.
            URLQueryItem(name: "countrycodes", value: "jp"),
            // In Japanese, or Kアリーナ横浜 comes back as "K-Arena Yokohama"
            // — which is exactly the name this app declines to be argued into.
            URLQueryItem(name: "accept-language", value: "ja")
        ]
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

        let origin = CLLocation(latitude: reference.latitude, longitude: reference.longitude)
        return rows
            .compactMap { row -> (away: CLLocationDistance, building: Building)? in
                guard let category = row.category, !Self.notVenues.contains(category),
                      let latitude = row.lat.flatMap(Double.init),
                      let longitude = row.lon.flatMap(Double.init)
                else { return nil }
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
                let away = origin.distance(from: CLLocation(latitude: latitude, longitude: longitude))
                guard away <= Self.tolerance else { return nil }
                return (away, Building(name: row.name ?? query, coordinate: coordinate))
            }
            .min { $0.away < $1.away }?
            .building
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
    }
}
