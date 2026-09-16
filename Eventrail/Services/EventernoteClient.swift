import Foundation

/// Reads publicly accessible Eventernote pages.
///
/// The site publishes no API, so this fetches the pages any logged-out visitor
/// can load and imports the fields they render. Every request is a GET: nothing
/// the reader records in this app is ever written back to Eventernote, and no
/// account is involved. Requests stay off the main actor — a listing is roughly
/// 50KB of markup to walk.
nonisolated struct EventernoteClient: Sendable {
    static let site = URL(string: "https://www.eventernote.com")!
    static let shared = EventernoteClient()

    /// Rows per page, passed to the site's own paging.
    static let pageSize = 30

    /// The site serves a desktop template unless the request looks like a phone,
    /// and it is the phone template this importer reads. The product name is
    /// kept in front of it so the traffic is attributable.
    private static let userAgent =
        "Eventrail/1.0 (iPhone; iOS 26_0) Mobile — https://www.eventernote.com"

    enum Failure: Error, LocalizedError {
        case http(Int)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .http(404): String(localized: "That Eventernote page is no longer there.")
            case .http: String(localized: "Eventernote did not answer. Try again in a moment.")
            case .unreadable: String(localized: "Eventernote's page could not be read.")
            }
        }
    }

    var session: URLSession = .shared

    // MARK: - Searching

    func searchEvents(keyword: String, page: Int = 1) async throws -> EventernotePage<Event> {
        let html = try await html(
            at: "/events/search",
            query: ["keyword": keyword, "limit": "\(Self.pageSize)", "page": "\(page)"]
        )
        return EventernotePages.events(in: html, page: page, pageSize: Self.pageSize)
    }

    func searchPerformers(keyword: String, page: Int = 1) async throws -> EventernotePage<PerformerProfile> {
        let html = try await html(
            at: "/actors/search",
            query: ["keyword": keyword, "limit": "\(Self.pageSize)", "page": "\(page)"]
        )
        return EventernotePages.performers(in: html, page: page, pageSize: Self.pageSize)
    }

    /// Everything one performer is billed on, newest first.
    ///
    /// The slug is already escaped exactly as Eventernote escaped it, so the URL
    /// is built by hand rather than re-encoded.
    func events(forPerformer performer: PerformerProfile, page: Int = 1) async throws -> EventernotePage<Event> {
        let path = "/actors/\(performer.slug)/\(performer.id)/events"
        let html = try await html(at: path, query: ["limit": "\(Self.pageSize)", "page": "\(page)"],
                                  isPreEncoded: true)
        return EventernotePages.events(in: html, page: page, pageSize: Self.pageSize)
    }

    // MARK: - One event

    /// Imports an event's own page, and the venue's page behind it for the
    /// address and capacity the detail sheet prints.
    func detail(for event: Event) async throws -> Event {
        let page = try await html(at: "/events/\(event.id)", query: [:])
        guard var imported = EventernotePages.event(in: page, id: event.id) else {
            throw Failure.unreadable
        }

        // A venue page that will not load is not worth failing the import over:
        // the event itself has already been read.
        if let placeID = imported.placeID,
           let venue = try? await html(at: "/places/\(placeID)", query: [:]) {
            imported.venueDetail = EventernotePages.venueDetail(in: venue)
        }
        return event.merging(imported)
    }

    // MARK: - Fetching

    private func html(at path: String, query: [String: String], isPreEncoded: Bool = false) async throws -> String {
        var components = URLComponents(url: Self.site, resolvingAgainstBaseURL: false) ?? URLComponents()
        if isPreEncoded {
            components.percentEncodedPath = path
        } else {
            components.path = path
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw Failure.unreadable }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            throw Failure.http(status)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
