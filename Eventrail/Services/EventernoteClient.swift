import Foundation

/// Reads publicly accessible Eventernote pages.
///
/// The site publishes no API, so this fetches the pages any logged-out visitor
/// can load and imports the fields they render. Every request is a GET: nothing
/// the reader records in this app is ever written back to Eventernote, and no
/// account is involved. Requests stay off the main actor — a listing is roughly
/// 50KB of markup to walk — so each is `@concurrent`: a plain `nonisolated
/// async` function runs on its caller's actor under approachable concurrency,
/// and the screens and stores that ask are on the main one.
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
    @concurrent func searchEvents(keyword: String, areaID: Int? = nil, order: SearchOrder = .newestFirst,
                      page: Int = 1) async throws -> EventernotePage<Event> {
        var query = ["keyword": keyword, "limit": "\(Self.pageSize)", "page": "\(page)",
                     "sort": "event_date", "order": order.order]
        if let areaID { query["area_id"] = "\(areaID)" }
        let html = try await html(at: "/events/search", query: query)
        return try EventernotePages.events(in: html, page: page, pageSize: Self.pageSize)
    }

    @concurrent func searchPerformers(keyword: String, page: Int = 1) async throws -> EventernotePage<PerformerProfile> {
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
    @concurrent func performer(named name: String) async throws -> PerformerProfile? {
        try await searchPerformers(keyword: name).items.first { $0.name == name }
    }

    /// Everything one performer is billed on, from the furthest published date
    /// backwards — so every upcoming appearance is at the front of the listing.
    ///
    /// The slug is already escaped exactly as Eventernote escaped it, so the URL
    /// is built by hand rather than re-encoded.
    @concurrent func events(forPerformer performer: PerformerProfile, page: Int = 1) async throws -> EventernotePage<Event> {
        let path = "/actors/\(performer.slug)/\(performer.id)/events"
        let html = try await html(at: path, query: ["limit": "\(Self.pageSize)", "page": "\(page)"],
                                  isPreEncoded: true)
        return try EventernotePages.events(in: html, page: page, pageSize: Self.pageSize)
    }

    // MARK: - The performers' directory

    /// The hundred performers with the most fans, the most first — the
    /// site's ranking, one page printed as its performer search prints rows.
    @concurrent func popularPerformers() async throws -> [PerformerProfile] {
        let html = try await html(at: Self.popularPath, query: [:])
        return try EventernotePages.performers(in: html, page: 1, pageSize: Self.popularCount).items
    }

    /// The directory's own page: the performers most recently added, and the
    /// kana their readings start with — see ``EventernotePages/performerIndex(in:)``.
    @concurrent func performerIndex() async throws -> PerformerIndex {
        let html = try await html(at: Self.directoryPath, query: [:])
        guard let index = EventernotePages.performerIndex(in: html) else { throw Failure.unreadable }
        return index
    }

    /// Every performer whose reading starts with `kana`, in the order of
    /// their readings. One page however many: the site ignores paging here,
    /// and 「あ」 is six thousand rows, a megabyte — so only ever read when the
    /// reader opens it.
    @concurrent func performers(underInitial kana: String) async throws -> [PerformerProfile] {
        let html = try await html(at: Self.initialPath(kana), query: [:])
        return try EventernotePages.performers(in: html, page: 1, pageSize: .max).items
    }

    /// How many the ranking lists.
    static let popularCount = 100

    static var popularPerformersURL: URL? { url(at: popularPath, query: [:]) }
    static var performerDirectoryURL: URL? { url(at: directoryPath, query: [:]) }
    static func performersURL(underInitial kana: String) -> URL? { url(at: initialPath(kana), query: [:]) }

    private static let popularPath = "/actors/ranking"
    private static let directoryPath = "/actors"
    private static func initialPath(_ kana: String) -> String { "/actors/initial/\(kana)" }

    // MARK: - The site's own lists

    /// How many rows the site's 新着 tab holds. It has no pages: the hundred
    /// events most recently added, and nothing behind them.
    static let newestCount = 100

    /// Everything held on one day of the site's calendar, the earliest start
    /// first — the site's own 今日開催 tab, asked of its search instead.
    ///
    /// The tab prints the whole day on one page and ignores `area_id`. The
    /// search, given the day as its 開催日, lists the same events a page at a
    /// time, counts them, and narrows them to one of the site's areas the way
    /// the Search tab's results are narrowed. `start_time` is one of the
    /// orders its menu offers, and puts the events with no start published
    /// first.
    @concurrent func events(on day: Date, areaID: Int? = nil, page: Int = 1) async throws -> EventernotePage<Event> {
        var query = Self.dayQuery(day, areaID: areaID)
        query["limit"] = "\(Self.pageSize)"
        query["page"] = "\(page)"
        let html = try await html(at: "/events/search", query: query)
        return try EventernotePages.events(in: html, page: page, pageSize: Self.pageSize)
    }

    /// The hundred events most recently added to the site, the newest first —
    /// its 新着 tab. In the order they were added rather than by date, so a
    /// date already past is among them wherever somebody filed one late. The
    /// tab takes no `area_id` either.
    @concurrent func newestEvents() async throws -> EventernotePage<Event> {
        let html = try await html(at: Self.newestPath, query: Self.newestQuery)
        return try EventernotePages.events(in: html, page: 1, pageSize: Self.newestCount)
    }

    /// The page on the site listing what ``events(on:areaID:page:)`` reads,
    /// in the same order.
    static func pageURL(forEventsOn day: Date, areaID: Int?) -> URL? {
        url(at: "/events/search", query: dayQuery(day, areaID: areaID))
    }

    /// The site's own 新着 tab.
    static var newestEventsURL: URL? {
        url(at: newestPath, query: newestQuery)
    }

    private static let newestPath = "/events/"
    private static let newestQuery = ["type": "2"]

    /// The day as the search form's 開催日 asks for it — on the site's
    /// calendar, so a moment late in the evening west of Japan asks for the
    /// day Japan is already on.
    private static func dayQuery(_ day: Date, areaID: Int?) -> [String: String] {
        let parts = Event.siteCalendar.dateComponents([.year, .month, .day], from: day)
        var query = ["year": "\(parts.year ?? 0)", "month": "\(parts.month ?? 0)", "day": "\(parts.day ?? 0)",
                     "sort": "start_time", "order": "ASC"]
        if let areaID { query["area_id"] = "\(areaID)" }
        return query
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
    @concurrent func profile(forUser handle: String) async throws -> EventernoteProfile {
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
    @concurrent func events(forUser handle: String, page: Int = 1) async throws -> EventernotePage<Event> {
        let html = try await html(
            at: "/users/\(handle)/events",
            query: ["limit": "\(Self.importPageSize)", "page": "\(page)"]
        )
        return try EventernotePages.events(in: html, page: page, pageSize: Self.importPageSize)
    }

    // MARK: - One event

    /// Imports an event's own page, and the venue's page behind it for the
    /// address and capacity the detail sheet prints — read once a run where a
    /// run hands in its `halls`.
    @concurrent func detail(for event: Event, halls: HallPages? = nil) async throws -> Event {
        let page = try await html(at: "/events/\(event.id)", query: [:])
        guard var imported = EventernotePages.event(in: page, id: event.id) else {
            throw Failure.unreadable
        }

        // A venue page that will not load is not worth failing the import over:
        // the event itself has already been read. A refusal is, though: the
        // next request would be refused too, and a run going on past it went on
        // asking a site that had said to stop (``Failure/isRateLimited``).
        if let placeID = imported.placeID {
            do {
                let read = { @Sendable in
                    let venue = try await html(at: "/places/\(placeID)", query: [:])
                    return HallPage(detail: EventernotePages.venueDetail(in: venue),
                                    address: EventernotePages.venueAddress(in: venue))
                }
                let hall = if let halls { try await halls.page(placeID, read: read) } else { try await read() }
                imported.venueDetail = hall.detail
                imported.venueAddress = hall.address
            } catch let failure as Failure where failure.isRateLimited {
                throw failure
            } catch {}
        }
        imported.readAt = .now
        return event.merging(imported)
    }

    /// What an event's read takes from its hall's page.
    struct HallPage: Sendable {
        let detail: String?
        let address: String?
    }

    /// The hall pages one run of reads has asked for, by place id — so a run
    /// over a library's events, a few dozen halls between nine hundred of
    /// them, reads each hall's page once rather than once an event: the run
    /// of requests the site stops answering. A page asked for while another
    /// read of it is on its way waits for that one.
    actor HallPages {
        private var pages: [Int: Task<HallPage, any Error>] = [:]

        func page(_ id: Int, read: @escaping @Sendable () async throws -> HallPage) async throws -> HallPage {
            if let asked = pages[id] { return try await asked.value }
            let asking = Task { try await read() }
            pages[id] = asking
            return try await asking.value
        }
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
    @concurrent func address(forVenue venue: String) async throws -> String? {
        guard let match = try await self.venue(named: venue) else { return nil }
        return EventernotePages.venueAddress(in: try await html(at: "/places/\(match.id)", query: [:]))
    }

    /// The hall the site files under exactly this name.
    ///
    /// The exact match is the rule ``performer(named:)`` follows and for the
    /// same reason: the search matches on part of a name, so the next-best row
    /// is a different hall in a different town. A name the site files no hall
    /// under is nil — an answer, and a different thing from the request failing.
    @concurrent func venue(named venue: String) async throws -> PlaceListing? {
        let name = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let results = try await html(at: "/places/search",
                                     query: ["keyword": name, "limit": "\(Self.pageSize)"])
        return EventernotePages.places(in: results).first { $0.name == name }
    }

    /// The halls the site files under names matching `keyword`, a page at a
    /// time — Search's Venues. Name and id alone: the search prints no address.
    @concurrent func searchVenues(keyword: String, page: Int = 1) async throws -> EventernotePage<PlaceListing> {
        let html = try await html(at: "/places/search",
                                  query: ["keyword": keyword, "limit": "\(Self.pageSize)", "page": "\(page)"])
        return try EventernotePages.places(in: html, page: page, pageSize: Self.pageSize)
    }

    /// One hall's own page: where it is, how many it holds, and the walk from
    /// the station.
    @concurrent func venue(id: Int) async throws -> VenueProfile {
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
    @concurrent func events(atVenue id: Int, page: Int = 1) async throws -> EventernotePage<Event> {
        let html = try await html(at: "/places/\(id)/events",
                                  query: ["limit": "\(Self.pageSize)", "page": "\(page)"])
        return try EventernotePages.events(in: html, page: page, pageSize: Self.pageSize)
    }

    // MARK: - Fetching

    /// The address of one of the site's pages — what is asked for, and what a
    /// screen hands the browser to open the same page there. The query in the
    /// order of its names, so one page has one address.
    static func url(at path: String, query: [String: String], isPreEncoded: Bool = false) -> URL? {
        var components = URLComponents(url: site, resolvingAgainstBaseURL: false) ?? URLComponents()
        if isPreEncoded {
            components.percentEncodedPath = path
        } else {
            components.path = path
        }
        if !query.isEmpty {
            components.setQuery(query.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) })
        }
        return components.url
    }

    private func html(at path: String, query: [String: String], isPreEncoded: Bool = false) async throws -> String {
        guard let url = Self.url(at: path, query: query, isPreEncoded: isPreEncoded) else {
            throw Failure.unreadable
        }

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

nonisolated extension URLComponents {
    /// Sets the query to `items`, a `+` in any of them written as `%2B`.
    ///
    /// `queryItems` leaves a `+` as it is — it is allowed in a query — and a
    /// server reads one there as a space: a search for +α/あるふぁきゅん。
    /// arrived as " α/あるふぁきゅん。", and the exact match a billed name is
    /// looked up by came back with nobody.
    mutating func setQuery(_ items: [URLQueryItem]) {
        queryItems = items
        percentEncodedQuery = percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    }
}
