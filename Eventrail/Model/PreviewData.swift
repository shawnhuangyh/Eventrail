import Foundation

/// Fixtures for `#Preview` and the playground, imported from real Eventernote
/// pages so a preview shows the shapes the site actually publishes — including
/// an announced event it has no times for yet.
///
/// Nothing here reaches the running app: these are handed to an ``EventStore``
/// with no file behind it, so previews neither read nor write the reader's
/// own library.
enum PreviewData {
    static let events: [Event] = [
        make(id: "492650",
             title: "水瀬いのり2027年ライブツアー(仮)【東京】Day2",
             performers: ["水瀬いのり"],
             venue: "京王アリーナTOKYO(武蔵野の森総合スポーツプラザ)メインアリーナ",
             venueDetail: "東京都調布市西町290-11 武蔵野の森総合スポーツプラザ · 10,000人",
             y: 2027, m: 4, d: 25, doors: nil, start: nil, listed: 57,
             summary: """
             水瀬いのり、2027年のライブツアー開催決定！

             ■チケット
             ファンクラブ先行 2026年11月1日(日)12:00〜
             一般発売 2027年1月16日(土)10:00〜
             全席指定 8,800円(税込)
             ※未就学児入場不可。小学生以上有料。

             ■注意事項
             開場/開演時間は決まり次第、公式サイトにて発表されます。
             """,
             links: ["https://www.inoriminase.com/", "https://x.com/inoriminase"],
             hashtag: "#水瀬いのり", editedBy: "GJO_Ling", editedDaysAgo: 12),
        make(id: "492514",
             title: "『劇場版ダーウィンが来た！世界のネコのなかまたち』舞台挨拶付上映＜11:20の回＞",
             performers: ["水瀬いのり"],
             venue: "ユナイテッド・シネマ豊洲",
             venueDetail: nil,
             y: 2026, m: 10, d: 3, doors: (11, 5), start: (11, 20), listed: 12),
        make(id: "396310",
             title: "ラブライブ！スーパースター!! Liella! 6th LoveLive! Tour ～Let's be ONE～ ＜大阪公演＞ Day2",
             performers: ["Liella!", "伊達さゆり", "Liyuu(黎獄)", "ペイトン尚未", "岬なこ"],
             venue: "大阪城ホール",
             venueDetail: "大阪府大阪市中央区大阪城3-1 · 16,000人",
             y: 2025, m: 6, d: 14, doors: (14, 30), start: (15, 30), listed: 628,
             summary: "6th LoveLive! Tour ～Let's be ONE～ 大阪公演 Day2。全席指定 9,900円(税込)。",
             links: ["https://www.lovelive-anime.jp/yuigaoka/"],
             hashtag: "#Liella", editedBy: "yuumakecha", editedDaysAgo: 421),
    ]

    static let tracking: [Event.ID: Tracking] = [
        "492514": Tracking(ticket: .purchased, seat: "3階 H列 21番", cost: 8800,
                           lotteryEntries: 1,
                           note: "Doors are tight — get there by 10:45."),
        "396310": Tracking(ticket: .purchased, seat: "A5ブロック 12番", cost: 9900,
                           lotteryEntries: 4,
                           note: "Encore was worth the queue."),
    ]

    /// Two performers billed on the fixtures above, as performer search lists
    /// them — enough for a preview of Following to have somebody to follow.
    static let performers: [PerformerProfile] = [
        PerformerProfile(id: 2890, name: "水瀬いのり", reading: "みなせいのり", fanCount: 5514,
                         slug: "%E6%B0%B4%E7%80%AC%E3%81%84%E3%81%AE%E3%82%8A"),
        PerformerProfile(id: 12703, name: "伊達さゆり", reading: "だてさゆり", fanCount: 1633,
                         slug: "%E4%BC%8A%E9%81%94%E3%81%95%E3%82%86%E3%82%8A"),
    ]

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Event.publishedZone
        return calendar
    }()

    private static func make(
        id: String, title: String, performers: [String], venue: String, venueDetail: String?,
        y: Int, m: Int, d: Int, doors: (Int, Int)?, start: (Int, Int)?, listed: Int,
        summary: String? = nil, links: [String] = [], hashtag: String? = nil,
        editedBy: String? = nil, editedDaysAgo: Int? = nil
    ) -> Event {
        let day = DateComponents(year: y, month: m, day: d)
        return Event(
            id: id,
            title: title,
            artist: performers.first ?? title,
            venue: venue,
            venueDetail: venueDetail,
            placeID: nil,
            date: calendar.date(from: day) ?? .distantPast,
            doorsOpen: date(day, doors),
            startsAt: date(day, start),
            endsAt: nil,
            timeZone: Event.publishedZone,
            listedAttendees: listed,
            performers: performers.map { Performer(name: $0) },
            summary: summary,
            relatedLinks: links.compactMap(URL.init(string:)),
            hashtags: hashtag.map { [Hashtag(tag: $0, searchURL: search(for: $0))] } ?? [],
            editedBy: editedBy,
            editedAt: editedDaysAgo.flatMap { calendar.date(byAdding: .day, value: -$0, to: .now) },
            imageURL: URL(string: "https://eventernote.s3.amazonaws.com/images/events/\(id)_s.jpg"),
            sourceURL: EventernoteClient.site.appending(path: "events/\(id)"),
            isDetailed: true,
            detailFormat: Event.currentDetailFormat
        )
    }

    /// The timeline a hashtag links to, written the way the site writes it.
    private static func search(for hashtag: String) -> URL {
        let query = hashtag.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? hashtag
        return URL(string: "https://mobile.twitter.com/search/?q=\(query)&s=typd")
            ?? EventernoteClient.site
    }

    private static func date(_ day: DateComponents, _ time: (Int, Int)?) -> Date? {
        guard let time else { return nil }
        var components = day
        components.hour = time.0
        components.minute = time.1
        return calendar.date(from: components)
    }
}

extension EventStore {
    /// A store holding the preview fixtures, with no file behind it.
    @MainActor static var preview: EventStore {
        EventStore(file: nil, cloud: nil, calendar: nil, venues: nil, pageReads: nil,
                   library: PreviewData.events, tracking: PreviewData.tracking,
                   follows: PreviewData.performers)
    }
}

extension FollowedDates {
    /// The dates a preview pretends to have read, so Following and the Me card
    /// draw without reaching Eventernote.
    @MainActor static var preview: FollowedDates {
        FollowedDates(dates: PreviewData.performers.reduce(into: [:]) { dates, performer in
            dates[performer.id] = PreviewData.events.filter { event in
                event.isUpcoming && event.performers.contains { $0.name == performer.name }
            }
        })
    }
}

extension VenueRegions {
    /// The halls a preview pretends to have placed. The two fixtures that carry
    /// an address place themselves; this is the third, so the filter sheet has
    /// nothing left to look up and never reaches Eventernote.
    @MainActor static var preview: VenueRegions {
        VenueRegions(placed: ["ユナイテッド・シネマ豊洲": .kanto])
    }
}

extension Feed where Item == Event {
    /// A feed already holding the fixture listing, for a `#Preview` of a screen
    /// that is handed one rather than loading its own.
    @MainActor static var preview: Feed<Event> {
        let feed = Feed<Event>()
        let events = PreviewData.events
        Task {
            await feed.load { page in
                EventernotePage(items: events, total: events.count,
                                page: page, pageSize: events.count)
            }
        }
        return feed
    }
}
