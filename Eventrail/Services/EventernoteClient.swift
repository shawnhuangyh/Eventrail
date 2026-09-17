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

    /// Rows per page when importing a whole account. The site honours this up to
    /// at least 100, which turns a nine-hundred-event history into nine requests
    /// rather than thirty.
    static let importPageSize = 100

    /// The site serves a desktop template unless the request looks like a phone,
    /// and it is the phone template this importer reads. The product name is
    /// kept in front of it so the traffic is attributable.
    ///
    /// ASCII throughout, deliberately: a header field is bytes, and a value
    /// outside that range is left to whatever the stack decides to do with it.
    private static let userAgent =
        "Eventrail/1.0 (iPhone; iOS 26_0) Mobile - https://www.eventernote.com"

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

    /// Finds the profile page behind a name billed on an event.
    ///
    /// An event's billing publishes names, so the only way to the person's own
    /// page is to search for the name. Only an exact match is taken: the search
    /// matches on the kana reading too, so the next-best row is a different
    /// person rather than a near miss of the same one.
    func performer(named name: String) async throws -> PerformerProfile? {
        try await searchPerformers(keyword: name).items.first { $0.name == name }
    }

    /// Everything one performer is billed on, from the furthest published date
    /// backwards — so every upcoming appearance is at the front of the listing.
    ///
    /// The slug is already escaped exactly as Eventernote escaped it, so the URL
    /// is built by hand rather than re-encoded.
    func events(forPerformer performer: PerformerProfile, page: Int = 1) async throws -> EventernotePage<Event> {
        let path = "/actors/\(performer.slug)/\(performer.id)/events"
        let html = try await html(at: path, query: ["limit": "\(Self.pageSize)", "page": "\(page)"],
                                  isPreEncoded: true)
        return EventernotePages.events(in: html, page: page, pageSize: Self.pageSize)
    }

    // MARK: - A member's own history

    enum Account {
        /// The handles the site addresses accounts by. Anything else is a typo,
        /// and asking for it would send a malformed path to Eventernote.
        static func normalized(_ typed: String) -> String? {
            let handle = typed
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .drop { $0 == "@" }
            guard !handle.isEmpty, handle.count <= 64,
                  handle.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." })
            else { return nil }
            return String(handle)
        }
    }

    /// Reads one member's public page, which is what confirms a handle exists
    /// before the app records it.
    func profile(forUser handle: String) async throws -> EventernoteProfile {
        let html = try await html(at: "/users/\(handle)", query: [:])
        guard let profile = EventernotePages.profile(in: html, handle: handle) else {
            throw Failure.unreadable
        }
        return profile
    }

    /// One page of the events a member has marked themselves as attending.
    ///
    /// The listing is the same `gb_listevent` block the search results use, so
    /// the rows carry the same fields and the same `isDetailed == false`. It
    /// runs newest first and mixes dates still to come in with the past.
    func events(forUser handle: String, page: Int = 1) async throws -> EventernotePage<Event> {
        let html = try await html(
            at: "/users/\(handle)/events",
            query: ["limit": "\(Self.importPageSize)", "page": "\(page)"]
        )
        return EventernotePages.events(in: html, page: page, pageSize: Self.importPageSize)
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
            imported.venueAddress = EventernotePages.venueAddress(in: venue)
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
