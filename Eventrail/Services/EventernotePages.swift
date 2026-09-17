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
    static func events(in html: String, page: Int, pageSize: Int) -> EventernotePage<Event> {
        var cursor = HTMLCursor(html)
        guard cursor.advance(past: #"<div class="gb_listevent">"#),
              let list = cursor.take(upTo: "</ul>")
        else {
            return EventernotePage(items: [], total: totalCount(in: html) ?? 0,
                                   page: page, pageSize: pageSize)
        }

        let rows = HTMLCursor(list).slices(startingAt: #"<li class="#)
        return EventernotePage(
            items: rows.compactMap(event(inRow:)),
            total: totalCount(in: html) ?? rows.count,
            page: page,
            pageSize: pageSize
        )
    }

    /// The performer search results.
    static func performers(in html: String, page: Int, pageSize: Int) -> EventernotePage<PerformerProfile> {
        var cursor = HTMLCursor(html)
        guard cursor.advance(past: #"<div class="gb_listview">"#),
              let list = cursor.take(upTo: "</ul>")
        else {
            return EventernotePage(items: [], total: totalCount(in: html) ?? 0,
                                   page: page, pageSize: pageSize)
        }

        var rows = HTMLCursor(list)
        var profiles: [PerformerProfile] = []
        while rows.advance(past: #"<a href="/actors/"#) {
            guard let path = rows.take(upTo: "\""), let id = Int(path.split(separator: "/").last ?? "")
            else { break }
            guard rows.advance(past: ">") else { break }
            let billed = (rows.take(upTo: "<span") ?? "").htmlText
            let count = rows.text(after: ">", upTo: "</span>").flatMap(number(in:))
            let (name, reading) = splitReading(billed)
            guard !name.isEmpty else { continue }
            profiles.append(PerformerProfile(id: id, name: name, reading: reading,
                                             fanCount: count,
                                             slug: String(path.split(separator: "/").dropLast().joined(separator: "/"))))
        }

        return EventernotePage(items: profiles, total: totalCount(in: html) ?? profiles.count,
                               page: page, pageSize: pageSize)
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

        var counts = HTMLCursor(html)
        counts.advance(past: #"<div class="gb_score_table">"#)
        let eventCount = counts.text(after: #"/events">"#, upTo: "</a>").flatMap(number(in:))

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
        cursor.advance(past: #"<div class="gb_title_cover""#)
        let image = cursor.text(after: "background-image:url(", upTo: ")").flatMap(URL.init(string:))
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

        return event(id: id, title: title, day: day, venue: venue, venueDetail: nil,
                     placeID: placeID, times: section("開場/開演/終演時間", in: html)?.htmlText,
                     performers: performers, listedAttendees: listed,
                     imageURL: image, isDetailed: true)
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
        let address = section("所在地", in: html)?.htmlText
            // The postal code adds a line's worth of digits and no information
            // the address below it does not already carry.
            .drop { $0 == "〒" || $0.isNumber || $0 == "-" }
            .trimmingCharacters(in: .whitespaces)
        return (address?.isEmpty ?? true) ? nil : address
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

        return Event(
            id: id,
            title: title,
            artist: performers.first?.name ?? title,
            venue: venue,
            venueDetail: venueDetail,
            placeID: placeID,
            date: date,
            doorsOpen: time(labelled: "開場", in: times, on: day, calendar: calendar),
            startsAt: time(labelled: "開演", in: times, on: day, calendar: calendar),
            endsAt: time(labelled: "終演", in: times, on: day, calendar: calendar),
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
