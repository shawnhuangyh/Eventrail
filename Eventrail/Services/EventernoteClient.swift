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

        /// Whether the site is refusing because it has been asked too often,
        /// rather than because something is wrong with the page.
        ///
        /// 429 is the honest answer and 503 is the one a site behind a busy
        /// front end tends to give instead; either way, asking for the next
        /// page straight away only extends the refusal. So a run that meets
        /// one stops there and keeps what it already has.
        var isRateLimited: Bool {
            if case .http(let status) = self { return status == 429 || status == 503 }
            return false
        }

        var errorDescription: String? {
            switch self {
            case .http(404): String(localized: "That Eventernote page is no longer there.")
            case .http(429), .http(503):
                String(localized: "Eventernote is asking the app to slow down. Try again in a few minutes.")
            case .http: String(localized: "Eventernote did not answer. Try again in a moment.")
            case .unreadable: String(localized: "Eventernote's page could not be read.")
            }
        }
    }

    var session: URLSession = .shared

    // MARK: - Searching

    /// Events matching `keyword` in date order, in one of the site's areas
    /// where `areaID` names one — see ``SearchFilter``.
    ///
    /// The order is always asked for by name, newest first included, rather
    /// than left to the site's default: the Search tab's own narrowing leans on
    /// the listing being in date order.
    func searchEvents(keyword: String, areaID: Int? = nil, order: SearchOrder = .newestFirst,
                      page: Int = 1) async throws -> EventernotePage<Event> {
        var query = ["keyword": keyword, "limit": "\(Self.pageSize)", "page": "\(page)",
                     "sort": "event_date", "order": order.order]
        if let areaID { query["area_id"] = "\(areaID)" }
        let html = try await html(at: "/events/search", query: query)
        return try EventernotePages.events(in: html, page: page, pageSize: Self.pageSize)
    }

    func searchPerformers(keyword: String, page: Int = 1) async throws -> EventernotePage<PerformerProfile> {
        let html = try await html(
            at: "/actors/search",
            query: ["keyword": keyword, "limit": "\(Self.pageSize)", "page": "\(page)"]
        )
        return try EventernotePages.performers(in: html, page: page, pageSize: Self.pageSize)
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
        return try EventernotePages.events(in: html, page: page, pageSize: Self.pageSize)
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
        return try EventernotePages.events(in: html, page: page, pageSize: Self.importPageSize)
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
        imported.readAt = .now
        return event.merging(imported)
    }

    // MARK: - One venue

    /// Where a hall is, found by the exact name a listing row prints.
    ///
    /// A listing row publishes the hall's name and nothing else — no address
    /// and no place id — so the site's venue search is what turns the name into
    /// a page, and the hall's own page is where the address is. Two GETs, and
    /// both worth caching: see ``VenueRegions``.
    ///
    /// A name the site files no hall under, or a hall whose page prints no
    /// address, is nil — an answer, and a different thing from the request
    /// failing.
    func address(forVenue venue: String) async throws -> String? {
        guard let match = try await self.venue(named: venue) else { return nil }
        return EventernotePages.venueAddress(in: try await html(at: "/places/\(match.id)", query: [:]))
    }

    /// The hall the site files under exactly this name.
    ///
    /// The exact match is the rule ``performer(named:)`` follows and for the
    /// same reason: the search matches on part of a name, so the next-best row
    /// is a different hall in a different town. A name the site files no hall
    /// under is nil — an answer, and a different thing from the request failing.
    func venue(named venue: String) async throws -> PlaceListing? {
        let name = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let results = try await html(at: "/places/search",
                                     query: ["keyword": name, "limit": "\(Self.pageSize)"])
        return EventernotePages.places(in: results).first { $0.name == name }
    }

    /// One hall's own page: where it is, how many it holds, and the walk from
    /// the station.
    func venue(id: Int) async throws -> VenueProfile {
        let page = try await html(at: "/places/\(id)", query: [:])
        guard let venue = EventernotePages.venue(in: page, id: id) else {
            throw Failure.unreadable
        }
        return venue
    }

    /// Everything held at one hall, from the furthest published date backwards
    /// — so every date still to come sits at the front of the listing, exactly
    /// as it does for a performer.
    ///
    /// The hall's own page carries the first ten of these itself, but says no
    /// more than "372件" about the rest of them. This is the listing behind
    /// that link, which pages and prints its total the way every other listing
    /// on the site does.
    func events(atVenue id: Int, page: Int = 1) async throws -> EventernotePage<Event> {
        let html = try await html(at: "/places/\(id)/events",
                                  query: ["limit": "\(Self.pageSize)", "page": "\(page)"])
        return try EventernotePages.events(in: html, page: page, pageSize: Self.pageSize)
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
