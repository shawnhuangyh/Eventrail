import CoreLocation
import Foundation

/// Where a Japanese address is, according to the country that keeps the register.
///
/// ``VenuePlaces`` asks Maps first and this second, and that order is the whole
/// of the design. Where Maps answers, its answer is the better one: it knows
/// the building rather than the block, and it knows what the hall is called in
/// the reader's own language. This is for the case where Maps answers nothing.
///
/// That case is commoner than it sounds, and it is not always the hall's fault.
/// MapKit's search is served by whichever map provider covers wherever the
/// *device* is standing, and the provider serving mainland China carries no
/// Japanese venues at all: a reader in Shanghai gets an empty result for
/// 日本武道館 and every hall in their library goes unplaced. Nothing about the
/// hall changed — only where the reader stood. A hall too new or too small for
/// Maps to list arrives at the same place from anywhere, and is answered here
/// too.
///
/// What this is: the address search the Geospatial Information Authority of
/// Japan publishes, the same endpoint GSI's own map client calls. No key, no
/// account, and no reason to care where the reader is standing — which is the
/// point. Every device gets the same answer for the same address, so a hall
/// placed on the phone is in the same spot on the iPad.
///
/// **What this is not is a search for the venue.** It geocodes an address. No
/// venue name comes back, no category, and no Apple place behind it — what it
/// answers is the block the address names. That is enough for both things this
/// app does with a placing: the pin on the map under the venue, and the
/// coordinate on the calendar entry. It is not enough to open the hall's own
/// card in Maps, which needs an `MKMapItem.identifier` that only MapKit mints.
///
/// Crediting 国土地理院 is a condition of use, and is done in ``AboutView``.
nonisolated struct JapanAddresses: Sendable {
    static let shared = JapanAddresses()

    /// What the register says one address is.
    struct Place: Sendable {
        /// The address as the register spells it — 「東京都千代田区北の丸公園２番」
        /// for a published 北の丸公園2番3号. Kept because it is the only thing
        /// in the answer that says *what* was matched, and it is what goes on
        /// the map item in place of an address Maps would have written.
        let title: String
        let coordinate: CLLocationCoordinate2D
    }

    enum Failure: Error {
        case http(Int)
        case unreadable
    }

    private static let endpoint =
        URL(string: "https://msearch.gsi.go.jp/address-search/AddressSearch")!

    /// How precise an answer has to be before it is believed.
    ///
    /// The register grades every answer by how much of the address it actually
    /// matched: 1 is the prefecture, 3 the municipality, 5 the town, 7 and 8
    /// the block and the building number. Only 7 and up is a place; below that
    /// the service is reaching.
    ///
    /// And it does reach. Asked for an address it cannot place it answers with
    /// the nearest thing it can rather than with nothing — 上海市浦东新区世博
    /// 大道1200号 comes back as 埼玉県上尾市上, and 台北市南京東路四段2號 as
    /// 岩手県花巻市台, both graded 5. Every real hall tried came back 7 or 8.
    /// So the grade is the guard, and it is one integer rather than an argument
    /// about how two addresses are spelled.
    private static let block = 7

    /// The service's own parameters, copied from GSI's published map client:
    /// `ilvl` is what asks for the grade above, and `sort_il` puts the most
    /// precise answer first.
    private static let parameters = ["ilvl": "T", "sort_il": "1"]

    /// Japan, generously — from 沖ノ鳥島 to 南鳥島. A last guard on the answer
    /// rather than on the question: the grade says how sure the register is,
    /// and this says it is at least talking about the right country.
    private static let latitudes = 20.0...46.0
    private static let longitudes = 122.0...154.0

    /// Whether a coordinate is in Japan at all.
    ///
    /// The box above, offered because ``VenuePlaces`` holds Maps' answers to
    /// the same last guard this holds the register's: a hall the site places
    /// in Japan and a map places across the sea is the map answering about
    /// somewhere else. A box rather than a border — it is a sanity check on
    /// an answer that has already been matched against the published address,
    /// not a claim about where the coastline runs.
    static func isInJapan(_ coordinate: CLLocationCoordinate2D) -> Bool {
        CLLocationCoordinate2DIsValid(coordinate)
            && latitudes.contains(coordinate.latitude)
            && longitudes.contains(coordinate.longitude)
    }

    var session: URLSession = .shared

    /// The block the address names, or nil where the register has nothing
    /// precise enough to believe.
    ///
    /// A throw is the request itself failing — offline, or the service
    /// refusing — and leaves the hall unanswered so the next screen tries
    /// again. A nil is an answer: the register was asked and had no such
    /// place, which is worth writing down.
    func place(at address: String) async throws -> Place? {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        // The first of the two gates, and the one that matters most, because
        // of the reaching described on `block`: an address from outside Japan
        // would be answered with a Japanese place that merely shares a
        // character. A Japanese address opens with its prefecture, which is
        // exactly what `Region` already reads addresses for.
        guard !address.isEmpty, Region.containing(address: address) != nil else { return nil }

        if let place = try await asking(address) { return place }

        // The one spelling the register will not forgive. A town the register
        // writes 小松原通 is written 小松原通り by everyone who lives there,
        // Eventernote included, and the extra り costs the whole of the match:
        // the answer drops from the block (7) to the town (5), which is below
        // ``block`` and so is no answer at all. 和歌山県民文化会館 and every
        // hall on 札幌大通 went unplaced for exactly that. Asked again without
        // it — one more request, and only for an address that has already
        // failed once.
        let plain = address.replacingOccurrences(of: "通り", with: "通")
        guard plain != address else { return nil }
        return try await asking(plain)
    }

    /// One question put to the register, exactly as asked.
    private func asking(_ address: String) async throws -> Place? {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = (Self.parameters.map { URLQueryItem(name: $0.key, value: $0.value) })
            + [URLQueryItem(name: "q", value: address)]
        guard let url = components?.url else { throw Failure.unreadable }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            throw Failure.http(status)
        }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else {
            throw Failure.unreadable
        }
        return Self.place(in: rows)
    }

    /// The best-graded row, if it is graded well enough to be a place.
    ///
    /// `sort_il` already puts it first, but the rows are scanned for the
    /// highest grade rather than trusting that: the order is the service's to
    /// change, and the grade is the thing actually being asked about.
    private static func place(in rows: [Row]) -> Place? {
        let best = rows
            .compactMap { row -> (grade: Int, place: Place)? in
                guard let grade = row.properties?.ilvl.flatMap({ Int($0) }), grade >= block,
                      let title = row.properties?.title, !title.isEmpty,
                      let coordinates = row.geometry?.coordinates, coordinates.count == 2
                else { return nil }
                // GeoJSON order: longitude first.
                let coordinate = CLLocationCoordinate2D(latitude: coordinates[1], longitude: coordinates[0])
                guard isInJapan(coordinate) else { return nil }
                return (grade, Place(title: title, coordinate: coordinate))
            }
            .max { $0.grade < $1.grade }
        return best?.place
    }

    /// One row of the register's answer.
    ///
    /// Every field optional, for the same reason every accessor in the
    /// Eventernote reader is failable: a changed shape should cost a dropped
    /// row, never a wrong coordinate. `ilvl` really is published as a string.
    private struct Row: Decodable {
        struct Geometry: Decodable {
            var coordinates: [Double]?
        }

        struct Properties: Decodable {
            var title: String?
            var ilvl: String?
        }

        var geometry: Geometry?
        var properties: Properties?
    }
}
