import Foundation

/// A voice actor or artist, as Eventernote's performer search lists them.
nonisolated struct PerformerProfile: Identifiable, Hashable, Codable, Sendable {
    /// Eventernote's actor id.
    let id: Int
    let name: String
    /// The kana reading the site prints beside the name.
    let reading: String?
    /// How many Eventernote users list the performer as a favourite. The site
    /// prints this beside the name in search results; it is not a count of
    /// their events.
    let fanCount: Int?
    /// The already-escaped path segment the site uses for them. Names contain
    /// "!", "(" and spaces, so it is carried verbatim rather than re-encoded.
    let slug: String
}

nonisolated extension PerformerProfile {
    /// The performer's own page on Eventernote.
    ///
    /// The slug arrives already percent-encoded, so it is set as the encoded
    /// path rather than through `path`, which would escape the escapes and
    /// break every name containing "!", "(" or a space.
    var pageURL: URL {
        var components = URLComponents(url: EventernoteClient.site, resolvingAgainstBaseURL: false)
        components?.percentEncodedPath = "/actors/\(slug)/\(id)"
        return components?.url ?? EventernoteClient.site
    }
}

/// An Eventernote member's public page.
///
/// Anyone can load this logged out — it is how the app imports a reader's own
/// history without ever holding their password or a session of theirs.
nonisolated struct EventernoteProfile: Hashable, Sendable {
    /// The account name in the site's URLs, without the "@".
    let handle: String
    /// The display name printed above the handle, which need not match it.
    let name: String
    let bio: String?
    /// How many events the site says the account has attended, if it printed it.
    let eventCount: Int?
    /// The performers the account lists as favourites. Shown as a count before
    /// a link is confirmed, and seeded into the reader's own follows by an
    /// import — see ``EventStore/adoptFollows(_:)`` for the rules that keeps it
    /// from talking over them.
    ///
    /// Still Eventernote's list rather than the reader's: the app only ever
    /// reads it, and following or unfollowing here never writes back.
    let favoritePerformers: [PerformerProfile]
    let avatarURL: URL?
}

/// One hall, as the site's venue search lists it.
///
/// Name and id and nothing else: the search rows publish no address, which is
/// why placing a venue takes the hall's own page as well.
nonisolated struct PlaceListing: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let name: String
}

/// One kana a performer's reading can start with, as the site's directory
/// lists it: 「あ」 and how many it files there.
nonisolated struct KanaInitial: Hashable, Codable, Sendable {
    let kana: String
    let count: Int
}

/// One prefecture the site files halls under, as its directory of venues
/// (`/places`) lists it: 東京都, its number on the site, and how many halls.
/// The site's 海外 is one of them, numbered 90.
nonisolated struct PrefectureListing: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let name: String
    let count: Int

    /// The site's number for the halls abroad.
    static let abroadID = 90
}

/// The site's performer directory, `/actors`: the performers most recently
/// added, and the kana their readings start with.
nonisolated struct PerformerIndex: Codable, Sendable {
    var newest: [PerformerProfile]
    var initials: [KanaInitial]
}

/// One hall's own page: what Eventernote publishes about the place itself,
/// rather than about anything held there.
///
/// Every field but the name is optional, and most halls leave several of them
/// empty — the pages are written by the site's own members, so a small live
/// house has a name and an address and nothing more, while an arena carries its
/// seating breakdown and the walk from the station.
///
/// **There is no picture here**, for the reason a performer has none: the venue
/// template publishes a map canvas and no photograph of the hall. The map on
/// ``VenueView`` is drawn from the address by ``VenuePlaces``, which is a
/// likeness of the place rather than a stand-in for one.
nonisolated struct VenueProfile: Identifiable, Hashable, Codable, Sendable {
    /// Eventernote's place id, as it appears in the page's path.
    let id: Int
    let name: String
    /// 所在地, with the postal code dropped — the same line an event carries as
    /// ``Event/venueAddress``, so a hall placed from one is placed from either.
    let address: String?
    /// 収容人数 verbatim. The site prints a total and often the breakdown
    /// behind it, and the breakdown is the half a reader picking a seat wants.
    let capacity: String?
    let phone: String?
    /// 公式サイト: the hall's own site, which is where a floor plan, an access
    /// map and the cloakroom rules actually live.
    let website: URL?
    /// 座席情報, which the site publishes as a link to the hall's own chart
    /// rather than as words.
    let seatingChart: URL?
    /// 会場TIPS: how to get there and what to know on the day, written by the
    /// site's members. Kept with its line breaks — it is a list of exits and
    /// walking times, and run together it is unreadable.
    let tips: String?
}

nonisolated extension VenueProfile {
    /// The hall's own page on Eventernote.
    var pageURL: URL { EventernoteClient.site.appending(path: "places/\(id)") }
}

/// One page of a paged Eventernote listing.
nonisolated struct EventernotePage<Item: Sendable>: Sendable {
    let items: [Item]
    /// How many rows the site says match in total, across every page.
    let total: Int
    let page: Int
    let pageSize: Int

    var hasMore: Bool { page * pageSize < total }
}

/// Turns Eventernote's smartphone templates into models.
///
/// Every field is read through ``HTMLCursor``, so a template change degrades to
/// a missing field or a dropped row rather than to wrong data.
nonisolated enum EventernotePages {
    // MARK: - Listings

    /// The `gb_listevent` block shared by the event search, the calendar and a
    /// performer's own event list.
    ///
    /// Throws where the block is missing from a page that is not the site's own
    /// smartphone template — see ``confirmsNoRows(_:)``.
    static func events(in html: String, page: Int, pageSize: Int) throws -> EventernotePage<Event> {
        var cursor = HTMLCursor(html)
        guard cursor.advance(past: #"<div class="gb_listevent">"#),
              let list = cursor.take(upTo: "</ul>")
        else {
            try confirmsNoRows(html)
            return EventernotePage(items: [], total: totalCount(in: html) ?? 0,
                                   page: page, pageSize: pageSize)
        }

        let rows = HTMLCursor(list).slices(startingAt: #"<li class="#)
        let events = rows.compactMap(event(inRow:))
        try confirmsRowsRead(events.count, of: rows.count)
        return EventernotePage(
            items: events,
            total: totalCount(in: html) ?? rows.count,
            page: page,
            pageSize: pageSize
        )
    }

    /// The performer search results.
    static func performers(in html: String, page: Int, pageSize: Int) throws -> EventernotePage<PerformerProfile> {
        var cursor = HTMLCursor(html)
        guard cursor.advance(past: #"<div class="gb_listview">"#),
              let list = cursor.take(upTo: "</ul>")
        else {
            try confirmsNoRows(html)
            return EventernotePage(items: [], total: totalCount(in: html) ?? 0,
                                   page: page, pageSize: pageSize)
        }

        var profiles: [PerformerProfile] = []
        var printed = 0
        // Each row read inside its own bounds: a row printing no count read
        // on to the next one's, and two names were stored as one performer.
        for slice in HTMLCursor(list).slices(startingAt: #"<a href="/actors/"#) {
            printed += 1
            var row = HTMLCursor(slice)
            row.advance(past: #"<a href="/actors/"#)
            guard let path = row.take(upTo: "\""), let id = Int(path.split(separator: "/").last ?? "")
            else { break }
            guard row.advance(past: ">") else { break }
            let billed = (row.take(upTo: "<span") ?? row.rest).htmlText
            let count = row.text(after: ">", upTo: "</span>").flatMap(number(in:))
            let (name, reading) = splitReading(billed)
            guard !name.isEmpty else { continue }
            profiles.append(PerformerProfile(id: id, name: name, reading: reading,
                                             fanCount: count,
                                             slug: String(path.split(separator: "/").dropLast().joined(separator: "/"))))
        }
        try confirmsRowsRead(profiles.count, of: printed)

        return EventernotePage(items: profiles, total: totalCount(in: html) ?? profiles.count,
                               page: page, pageSize: pageSize)
    }

    /// Whether a page without its list is a listing with nothing in it.
    ///
    /// The site prints no list at all where nothing matches — an event search
    /// for nothing says so with only an empty space under the form — so a
    /// missing list is only an empty one on a page that is otherwise the
    /// site's own. `gb_foot_menu` closes every page of the smartphone
    /// template and none of the desktop one, and a maintenance page, a
    /// captcha or a proxy's error page carries neither. Reading any of those
    /// as "nothing found" would have the Following tab cache a performer as
    /// having no dates for the whole freshness window.
    ///
    /// The footer alone does not settle it where the page also counts what it
    /// found: a list block renamed under an unchanged footer would otherwise
    /// read "689件見つかりました。" over nothing, and a performer with dates
    /// would be cached as having none.
    private static func confirmsNoRows(_ html: String) throws {
        guard html.contains(#"class="gb_foot_menu""#), (totalCount(in: html) ?? 0) == 0 else {
            throw EventernoteClient.Failure.unreadable
        }
    }

    /// Whether a list that printed rows gave up at least one of them.
    ///
    /// A dropped row is how a changed template is meant to degrade, one field
    /// at a time. Every row dropped is not that: it is the row markup itself
    /// gone, and an empty page from it would be cached as a performer or a
    /// search with nothing in it.
    private static func confirmsRowsRead(_ read: Int, of printed: Int) throws {
        guard printed == 0 || read > 0 else {
            throw EventernoteClient.Failure.unreadable
        }
    }

    /// The size of the whole result set, however the page in hand states it.
    private static func totalCount(in html: String) -> Int? {
        searchTotal(in: html) ?? attendedTotal(in: html)
    }

    /// "689件見つかりました。" — the count a listing prints over its rows.
    ///
    /// Read back from the phrase rather than forward from the element that
    /// carries it. A performer's own listing prints its sort control in the
    /// same `t2` class *above* the count, so anchoring on the class read the
    /// sort line, failed the length check, and left the total unknown — which
    /// made `hasMore` false on every performer listing and stopped both the
    /// Following read and a performer's page at their first page.
    ///
    /// The count still has to follow its element immediately: anything longer
    /// than a number means the phrase was matched somewhere unrelated.
    private static func searchTotal(in html: String) -> Int? {
        guard let phrase = html.range(of: "件見つかりました"),
              let opening = html[..<phrase.lowerBound].lastIndex(of: ">")
        else { return nil }
        let found = html[html.index(after: opening) ..< phrase.lowerBound]
        guard found.count <= 20 else { return nil }
        return number(in: String(found))
    }

    /// "参加イベント一覧(879)" — the heading a member's own event list carries
    /// in place of a search count.
    private static func attendedTotal(in html: String) -> Int? {
        var cursor = HTMLCursor(html)
        guard let found = cursor.text(after: #"<h2 class="gb_subtitle">参加イベント一覧("#, upTo: ")"),
              found.count <= 20
        else { return nil }
        return number(in: found)
    }

    private static func event(inRow row: Substring) -> Event? {
        var cursor = HTMLCursor(row)
        guard let id = cursor.text(after: #"<a href="/events/"#, upTo: "\""), !id.isEmpty else { return nil }

        cursor.advance(past: #"<div class="image">"#)
        let image = cursor.text(after: #"<img src=""#, upTo: "\"").flatMap(URL.init(string:))

        guard let title = cursor.text(after: #"<div class="event"><p>"#, upTo: "</p>"),
              let printedDay = cursor.text(after: #"<div class="date"><p>"#, upTo: "</p>"),
              let day = day(in: printedDay)
        else { return nil }

        let performers = (cursor.text(after: #"<div class="actor">"#, upTo: "</div>") ?? "")
            .split(whereSeparator: \.isNewline)
            .map { Performer(name: $0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.name.isEmpty }

        // Only a performer's own event list prints times in the row; the search
        // results leave the block out entirely.
        let times = cursor.text(after: #"<div class="time">"#, upTo: "</div>")
        let venue = cursor.text(after: #"<div class="place">"#, upTo: "</div>") ?? ""

        return event(id: id, title: title, day: day, venue: venue, venueDetail: nil,
                     placeID: nil, times: times, performers: performers,
                     listedAttendees: nil, imageURL: image, isDetailed: false)
    }

    /// The venue search results.
    ///
    /// The same `gb_listview` block the performer search uses, entered at its
    /// list rather than at the div: the pager above the rows links back into
    /// `/places/search`, and a scan that started at the div would read that
    /// link as its first hall and give up on the page.
    static func places(in html: String) -> [PlaceListing] {
        var cursor = HTMLCursor(html)
        guard cursor.advance(past: #"<div class="gb_listview">"#),
              cursor.advance(past: "<ul"),
              let list = cursor.take(upTo: "</ul>")
        else { return [] }

        var rows = HTMLCursor(list)
        var places: [PlaceListing] = []
        while rows.advance(past: #"<a href="/places/"#) {
            guard let path = rows.take(upTo: "\""), let id = Int(path) else { break }
            // A hall filed with no name — a prefecture's list opens on two —
            // is passed over rather than ending the list there.
            guard let name = rows.text(after: ">", upTo: "</a>") else { continue }
            places.append(PlaceListing(id: id, name: name))
        }
        return places
    }

    /// The venue search, a page of it with the count it printed — what
    /// Search's Venues lists. The rows read as ``places(in:)`` reads them.
    ///
    /// Throws, as every listing does, where the rows are missing from a page
    /// that is not the site's own empty search — see ``confirmsNoRows(_:)``.
    static func places(in html: String, page: Int, pageSize: Int) throws -> EventernotePage<PlaceListing> {
        let places = places(in: html)
        if places.isEmpty { try confirmsNoRows(html) }
        return EventernotePage(items: places, total: totalCount(in: html) ?? places.count,
                               page: page, pageSize: pageSize)
    }

    // MARK: - The venues' directory

    /// `/places`: every prefecture — 北海道 (536) — with how many halls the
    /// site files under it, in the site's order, 海外 last.
    static func prefectures(in html: String) -> [PrefectureListing] {
        var cursor = HTMLCursor(html)
        guard cursor.advance(past: #"<div class="gb_listview">"#), let list = cursor.take(upTo: "</ul>") else {
            return []
        }
        var rows = HTMLCursor(list)
        var prefectures: [PrefectureListing] = []
        while rows.advance(past: #"<a href="/places/prefecture/"#) {
            guard let path = rows.take(upTo: "\""), let id = Int(path),
                  let listed = rows.text(after: ">", upTo: "</a>")
            else { break }
            let (name, count) = splitCount(listed)
            guard !name.isEmpty, let count else { continue }
            prefectures.append(PrefectureListing(id: id, name: name, count: count))
        }
        return prefectures
    }

    // MARK: - The performers' directory

    /// `/actors`: the performers most recently added — 楠ゆい(READY TO KISS) (0),
    /// the fan count in the last parentheses — and every kana with how many
    /// readings start with it. Nil where the page carries neither.
    static func performerIndex(in html: String) -> PerformerIndex? {
        var newest: [PerformerProfile] = []
        var cursor = HTMLCursor(html)
        if cursor.advance(past: "新着声優/アーティスト</h2>"), let block = cursor.take(upTo: "</p>") {
            for slice in HTMLCursor(block).slices(startingAt: #"<a href="/actors/"#) {
                var row = HTMLCursor(slice)
                row.advance(past: #"<a href="/actors/"#)
                guard let path = row.take(upTo: "\""), let id = Int(path.split(separator: "/").last ?? ""),
                      let listed = row.text(after: ">", upTo: "</a>")
                else { continue }
                let (name, fans) = splitCount(listed)
                guard !name.isEmpty else { continue }
                newest.append(PerformerProfile(id: id, name: name, reading: nil, fanCount: fans,
                                               slug: String(path.split(separator: "/").dropLast().joined(separator: "/"))))
            }
        }

        var initials: [KanaInitial] = []
        var index = HTMLCursor(html)
        if index.advance(past: "50音別声優/アーティスト</h2>"), let block = index.take(upTo: "</ul>") {
            var rows = HTMLCursor(block)
            while rows.advance(past: #"<a href="/actors/initial/"#) {
                guard let kana = rows.text(after: "「", upTo: "」"),
                      let count = rows.text(after: ">", upTo: "</span>").flatMap(number(in:))
                else { break }
                initials.append(KanaInitial(kana: kana, count: count))
            }
        }
        guard !newest.isEmpty || !initials.isEmpty else { return nil }
        return PerformerIndex(newest: newest, initials: initials)
    }

    /// "楠ゆい(READY TO KISS) (0)", "東京都 (6151)" — a name, and the count
    /// a directory sets after it in parentheses of its own.
    private static func splitCount(_ listed: String) -> (name: String, count: Int?) {
        guard listed.hasSuffix(")"), let open = listed.range(of: " (", options: .backwards) else {
            return (listed, nil)
        }
        let figure = listed[open.upperBound ..< listed.index(before: listed.endIndex)]
        guard let count = Int(figure) else { return (listed, nil) }
        return (String(listed[..<open.lowerBound]), count)
    }

    // MARK: - A performer's own page

    /// `/actors/{slug}/{id}`: who the page is about, from its heading — the
    /// name in its `h1`, the reading under it. The page's listing is the
    /// performer's events page's to read.
    static func performer(in html: String, id: Int, slug: String) -> PerformerProfile? {
        var cursor = HTMLCursor(html)
        guard cursor.advance(past: #"<div class="mod_actors_detail">"#),
              let name = cursor.text(after: #"<div class="title"><h1>"#, upTo: "</h1>")
        else { return nil }
        let reading = cursor.text(after: #"<div class="title2"><h2>"#, upTo: "</h2>")
        return PerformerProfile(id: id, name: name, reading: reading, fanCount: nil, slug: slug)
    }

    // MARK: - A member's own page

    /// Reads `/users/{handle}`.
    ///
    /// The handle is passed in rather than read back out of the page: it is what
    /// the reader typed and what every later request is built from, and a page
    /// that fails to print it should not silently change which account is linked.
    static func profile(in html: String, handle: String) -> EventernoteProfile? {
        var cursor = HTMLCursor(html)
        guard cursor.advance(past: #"<div class="profile_box"#),
              let name = cursor.text(after: #"<h1 class="top">"#, upTo: "</h1>")
        else { return nil }

        // Everything past the name is optional: an account with no bio, no
        // avatar and no favourites is still an account worth linking.
        let bio = cursor.text(after: #"<p class="text">"#, upTo: "</p>")

        // Only inside the score table: without it, the search ran on to any
        // link to an events page and read a year in its text as the count.
        var counts = HTMLCursor(html)
        let eventCount = counts.advance(past: #"<div class="gb_score_table">"#)
            ? counts.text(after: #"/events">"#, upTo: "</a>").flatMap(number(in:))
            : nil

        return EventernoteProfile(
            handle: handle, name: name, bio: bio, eventCount: eventCount,
            favoritePerformers: favoritePerformers(in: html),
            avatarURL: avatarImage(in: html)
        )
    }

    /// The "お気に入りの声優" block, which carries each performer's id and the
    /// already-escaped slug their event list is addressed by.
    private static func favoritePerformers(in html: String) -> [PerformerProfile] {
        var cursor = HTMLCursor(html)
        guard cursor.advance(past: #"<div class="favorite_actor">"#),
              cursor.advance(past: "<ul>"),
              let list = cursor.take(upTo: "</ul>")
        else { return [] }

        var rows = HTMLCursor(list)
        var performers: [PerformerProfile] = []
        while rows.advance(past: #"<a href="/actors/"#) {
            guard let path = rows.take(upTo: "\""),
                  let id = Int(path.split(separator: "/").last ?? ""),
                  let name = rows.text(after: ">", upTo: "</a>")
            else { break }
            let slug = path.split(separator: "/").dropLast().joined(separator: "/")
            // The block prints no reading, and the number beside a name here is
            // the site's fan count, which this page does not carry at all.
            performers.append(PerformerProfile(id: id, name: name, reading: nil,
                                               fanCount: nil, slug: slug))
        }
        return performers
    }

    /// The picture in the profile's cover block, which is the only `thumb` on
    /// the page above the fold — anchored to the cover so a later one cannot be
    /// mistaken for it.
    ///
    /// An account that took its picture from Twitter still has it announced over
    /// plain HTTP, which App Transport Security refuses outright: loaded as
    /// printed, the image would simply never appear. The scheme is promoted
    /// here rather than at the view, so what the model holds is a URL that can
    /// actually be fetched. An account with no picture prints `src=""`, which
    /// reads as no picture at all.
    private static func avatarImage(in html: String) -> URL? {
        var cursor = HTMLCursor(html)
        guard cursor.advance(past: #"<div class="mod_mypage_cover"#),
              cursor.advance(past: #"<div class="thumb">"#),
              let source = cursor.text(after: #"src=""#, upTo: "\""),
              var components = URLComponents(string: source)
        else { return nil }
        if components.scheme == "http" { components.scheme = "https" }
        return components.url
    }

    // MARK: - An event's own page

    static func event(in html: String, id: String) -> Event? {
        var cursor = HTMLCursor(html)
        // The flyer, read off the cover's own tag and nowhere past it: a cover
        // drawn without one would have sent the search on to a later element's
        // background, past the title — read as missing, and the whole page as
        // unreadable.
        let image = cursor.advance(past: #"<div class="gb_title_cover""#)
            ? cursor.take(upTo: ">").flatMap { tag in
                var style = HTMLCursor(tag)
                return style.text(after: "background-image:url(", upTo: ")").flatMap(URL.init(string:))
            }
            : nil
        guard let title = cursor.text(after: #"<h1 class="gb_subtitle gb_curl_effect">"#, upTo: "</h1>"),
              let printedDay = section("開催日時", in: html)?.htmlText,
              let day = day(in: printedDay)
        else { return nil }

        var venue = ""
        var placeID: Int?
        if let place = section("開催場所", in: html) {
            var places = HTMLCursor(place)
            if let path = places.text(after: #"<a href="/places/"#, upTo: "\"") {
                placeID = Int(path)
                venue = places.text(after: ">", upTo: "</a>") ?? ""
            } else {
                venue = place.htmlText
            }
        }

        var performers: [Performer] = []
        if let billing = section("出演者", in: html) {
            var names = HTMLCursor(billing)
            while names.advance(past: #"<a href="/actors/"#) {
                guard let path = names.take(upTo: "\""),
                      let name = names.text(after: ">", upTo: "</a>")
                else { break }
                performers.append(Performer(name: name, actorID: Int(path.split(separator: "/").last ?? "")))
            }
        }

        var attendees = HTMLCursor(html)
        let listed = attendees.text(after: "このイベントに参加のイベンター(", upTo: ")").flatMap(number(in:))

        guard var event = event(id: id, title: title, day: day, venue: venue, venueDetail: nil,
                                placeID: placeID, times: section("開場/開演/終演時間", in: html)?.htmlText,
                                performers: performers, listedAttendees: listed,
                                imageURL: image, isDetailed: true)
        else { return nil }

        // Set here rather than passed through the shared factory: a listing row
        // publishes none of them, so only an event's own page has anything to
        // say. Empty is kept apart from nil for the reason ``Event/relatedLinks``
        // gives — a re-import of a row must not blank these out.
        event.summary = lines(ofSection: "概要", in: html)
        event.relatedLinks = links(inSection: "関連リンク", in: html)
        event.hashtags = hashtags(in: html)
        let edit = lastEdit(in: html)
        event.editedBy = edit?.handle
        event.editedAt = edit?.at
        event.detailFormat = Event.currentDetailFormat
        return event
    }

    /// Every link a section points at, in the order it prints them.
    ///
    /// 関連リンク is a run of anchors in one paragraph, and the site prints the
    /// href as the link's own text — so the text is no shorter than the address
    /// and it is the address that is kept.
    private static func links(inSection heading: String, in html: String) -> [URL] {
        guard let markup = section(heading, in: html) else { return [] }
        var cursor = HTMLCursor(markup)
        var links: [URL] = []
        // Read through ``HTMLCursor/text(after:upTo:)`` rather than taken raw,
        // so "&amp;" in a query is a "&" by the time it is parsed as a URL.
        while let href = cursor.text(after: #"<a href=""#, upTo: "\"") {
            guard let url = URL(string: href), url.scheme?.hasPrefix("http") == true,
                  // The same address twice is the same link, and two rows that
                  // are the same row is one identity too few for a `ForEach`.
                  !links.contains(url)
            else { continue }
            links.append(url)
        }
        return links
    }

    /// The Twitterハッシュタグ section: the tags as written, and the timeline
    /// the site links them to.
    ///
    /// An event's tags are one field and one link, even when several are
    /// written in it — "#チェンステ #チェンソーマン" is a single search for
    /// both at once. **Don't split them.** The site publishes one link because
    /// the search it points at is the one worth running: the event is tagged
    /// both ways, and either tag on its own is a wider net than the event.
    private static func hashtags(in html: String) -> [Hashtag] {
        guard let markup = section("Twitterハッシュタグ", in: html) else { return [] }
        var cursor = HTMLCursor(markup)
        var tags: [Hashtag] = []
        while let href = cursor.text(after: #"<a href=""#, upTo: "\""),
              let tag = cursor.text(after: ">", upTo: "</a>"),
              let url = URL(string: href) {
            let hashtag = Hashtag(tag: tag, searchURL: url)
            // The same tag twice is one identity too few for a `ForEach`.
            if !tags.contains(hashtag) { tags.append(hashtag) }
        }
        return tags
    }

    /// The top row of イベント登録/最終更新履歴: who touched the page last, and
    /// how long ago the site says that was.
    ///
    /// The history is printed newest first, with every row but the first
    /// carrying `class="hide"` behind a "show all" the app does not draw — so
    /// the first anchor after the list opens is the latest edit.
    ///
    /// The site prints the age as "127日前", which is a fact about the day it
    /// was served rather than about the page. It is turned into a date here so
    /// that a copy held for a year does not go on claiming the edit was 127
    /// days ago. A row printed any other way leaves the date nil and keeps the
    /// name, which is the half that cannot be wrong.
    ///
    /// Dated to the start of that day on the site's clock, since a count of
    /// days says nothing finer. Counted back from the moment of reading, every
    /// read carried its own hour and minute, so a page nobody had touched read
    /// as edited each time it was opened — and was written into the library,
    /// and sent to iCloud, for it.
    private static func lastEdit(in html: String) -> (handle: String, at: Date?)? {
        var cursor = HTMLCursor(html)
        guard cursor.advance(past: #"id="authors""#),
              let handle = cursor.text(after: #"<a class="noline" href="/users/"#, upTo: "\"")
        else { return nil }

        guard let printed = cursor.text(after: #"<span class="s color2">"#, upTo: "</span>"),
              let count = number(in: printed)
        else { return (handle, nil) }
        // An edit inside the day is printed in hours or minutes: read as the
        // day it fell on, rather than as no date — which a read of the whole
        // page writes over the date the copy held.
        let within: TimeInterval? = if printed.hasSuffix("時間前") { 60 * 60 }
            else if printed.hasSuffix("分前") { 60 }
            else if printed.hasSuffix("秒前") { 1 }
            else { nil }
        if let within {
            return (handle, Event.siteDay(of: Date.now.addingTimeInterval(-TimeInterval(count) * within)))
        }
        guard printed.hasSuffix("日前") else { return (handle, nil) }
        let days = count
        return (handle, Event.siteCalendar.date(byAdding: .day, value: -days, to: Event.siteDay(of: .now)))
    }

    /// Address and capacity from a venue's page, in the form the detail sheet
    /// prints under the venue name.
    static func venueDetail(in html: String) -> String? {
        let capacity = section("収容人数", in: html)?.htmlText

        let parts = [venueAddress(in: html), capacity].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The address alone, as a map can be asked for it. Kept separate from
    /// ``venueDetail(in:)`` because the calendar mirror geocodes this and the
    /// capacity printed beside it would only confuse the search.
    static func venueAddress(in html: String) -> String? {
        guard let printed = section("所在地", in: html)?.htmlText else { return nil }
        // The postal code adds a line's worth of digits and no information
        // the address below it does not already carry. Only the postal code,
        // though: dropping every leading figure took the street number off
        // 1600 Main St, and stopped at the space in 〒 100-0005, leaving a
        // hall in Tokyo read as abroad, with no prefecture at its head.
        let address = Region.droppingPostalCode(printed)
        return address.isEmpty ? nil : address
    }

    // MARK: - A venue's own page

    /// Reads `/places/{id}`.
    ///
    /// Anchored on `mod_places_detail` so the name is read from the hall's own
    /// block rather than from the first heading on the page, and the id is
    /// passed in rather than read back out: it is what the page was asked for
    /// by, and a template that stopped printing it should not silently change
    /// which hall is being shown.
    static func venue(in html: String, id: Int) -> VenueProfile? {
        var cursor = HTMLCursor(html)
        guard cursor.advance(past: #"<div class="mod_places_detail">"#),
              let name = cursor.text(after: #"<h1 class="gb_subtitle gb_curl_effect">"#, upTo: "</h1>")
        else { return nil }

        return VenueProfile(
            id: id,
            name: name,
            address: venueAddress(in: html),
            capacity: text(ofSection: "収容人数", in: html),
            phone: text(ofSection: "電話番号", in: html),
            website: link(inSection: "公式サイト", in: html),
            seatingChart: link(inSection: "座席情報", in: html),
            tips: lines(ofSection: "会場TIPS", in: html)
        )
    }

    /// One section's readable text, or nil where the hall left it empty — which
    /// the template prints as an empty `<p class="t">` rather than by leaving
    /// the heading out.
    private static func text(ofSection heading: String, in html: String) -> String? {
        let text = section(heading, in: html)?.htmlText
        return (text?.isEmpty ?? true) ? nil : text
    }

    /// Where a section points rather than what it says. The site labels both
    /// the official site and the seating chart with a word — "ウェブサイト",
    /// "座席情報" — and puts the whole of the answer in the href.
    private static func link(inSection heading: String, in html: String) -> URL? {
        guard let markup = section(heading, in: html) else { return nil }
        var cursor = HTMLCursor(markup)
        guard let href = cursor.text(after: #"<a href=""#, upTo: "\"") else { return nil }
        return URL(string: href)
    }

    /// A section written as lines, with the template's breaks kept as breaks.
    ///
    /// ``StringProtocol/htmlText`` drops every tag, which would run four exits
    /// and their walking times into one sentence. So the breaks become newlines
    /// before the tags go.
    private static func lines(ofSection heading: String, in html: String) -> String? {
        guard let markup = section(heading, in: html) else { return nil }
        let broken = ["<br />", "<br/>", "<br>"].reduce(String(markup)) {
            $0.replacingOccurrences(of: $1, with: "\n")
        }
        let text = broken.htmlText
        return text.isEmpty ? nil : text
    }

    /// The address back out of a line this adapter joined.
    ///
    /// ``venueDetail(in:)`` prints the address and the capacity together, and
    /// that was for a while the only place either was kept. An event imported
    /// then still carries its address in there, and re-importing a whole
    /// library to recover what is already on disk would be a poor trade.
    ///
    /// A venue page that published a capacity and no address leaves that line
    /// starting with "8,028席", which is why the answer has to name a
    /// prefecture to be believed.
    static func address(inDetail detail: String) -> String? {
        guard let first = detail.components(separatedBy: " · ").first,
              first.contains(where: { "都道府県".contains($0) })
        else { return nil }
        return first
    }

    /// The markup between one `gb_subtitle` heading and the next.
    private static func section(_ heading: String, in html: String) -> Substring? {
        var cursor = HTMLCursor(html)
        guard cursor.advance(past: #"<h2 class="gb_subtitle">"# + heading + "</h2>") else { return nil }
        return cursor.take(upTo: "<h2") ?? cursor.rest
    }

    // MARK: - Shared field parsing

    private static func event(
        id: String, title: String, day: DateComponents, venue: String, venueDetail: String?,
        placeID: Int?, times: String?, performers: [Performer], listedAttendees: Int?,
        imageURL: URL?, isDetailed: Bool
    ) -> Event? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Event.publishedZone
        guard let date = calendar.date(from: day) else { return nil }

        // A clock with no date: "終演 00:30", or an all-night show's 開演
        // 00:30 after 開場 23:30, is the next morning rather than the start of
        // the same day — which put the show over before its doors opened, in
        // the calendar entry and in ``Event/hasEnded`` alike. So each time is
        // taken as the first of its clock after the one before it, in the order
        // an event runs. (25:00 already rolls over by itself.)
        let (doorsOpen, startsAt, endsAt) = Event.inOrder(
            time(labelled: "開場", in: times, on: day, calendar: calendar),
            time(labelled: "開演", in: times, on: day, calendar: calendar),
            time(labelled: "終演", in: times, on: day, calendar: calendar)
        )

        return Event(
            id: id,
            title: title,
            artist: performers.first?.name ?? title,
            venue: venue,
            venueDetail: venueDetail,
            placeID: placeID,
            date: date,
            doorsOpen: doorsOpen,
            startsAt: startsAt,
            endsAt: endsAt,
            timeZone: Event.publishedZone,
            listedAttendees: listedAttendees,
            performers: performers,
            imageURL: imageURL,
            sourceURL: EventernoteClient.site.appending(path: "events/\(id)"),
            isDetailed: isDetailed
        )
    }

    /// "2027-05-09(日)" and "2027-04-25 (日)" both yield the day.
    private static func day(in printed: String) -> DateComponents? {
        let parts = printed.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        return DateComponents(year: year, month: month, day: day)
    }

    /// Reads one time out of "開場 14:30 開演 15:30 終演 18:50". The site prints
    /// "-" for a time it has not been told, which stays nil here.
    private static func time(
        labelled label: String, in line: String?, on day: DateComponents, calendar: Calendar
    ) -> Date? {
        guard let line else { return nil }
        var cursor = HTMLCursor(line)
        guard cursor.advance(past: label) else { return nil }

        let value = cursor.rest.drop(while: { $0 == " " || $0 == "\u{00A0}" || $0.isNewline })
        let clock = value.prefix { $0.isNumber || $0 == ":" }.split(separator: ":")
        guard clock.count == 2, let hour = Int(clock[0]), let minute = Int(clock[1]) else { return nil }

        var components = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }

    /// The first run of digits, with the site's thousands separators dropped.
    private static func number(in text: String) -> Int? {
        Int(text.filter(\.isNumber))
    }

    /// "水瀬いのり (みなせいのり)" — the reading is appended in parentheses.
    private static func splitReading(_ billed: String) -> (name: String, reading: String?) {
        guard billed.hasSuffix(")"), let open = billed.range(of: " (", options: .backwards) else {
            return (billed, nil)
        }
        let reading = billed[open.upperBound ..< billed.index(before: billed.endIndex)]
        return (String(billed[..<open.lowerBound]), reading.isEmpty ? nil : String(reading))
    }
}
