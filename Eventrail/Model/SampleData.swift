import Foundation

/// Stand-in content for the screens until the Eventernote import adapter lands.
///
/// The shapes here are what the adapter is expected to produce, so the views
/// need not change when real imports replace these.
enum SampleData {
    /// Events already in the reader's library.
    static let library: [Event] = [
        make(id: "u1",
             title: "水瀬いのり LIVE TOUR 2026「Bloom in Blue」東京公演",
             artist: "水瀬いのり",
             venue: "Zepp DiverCity (TOKYO)",
             venueDetail: "Koto, Tokyo · 2,473 capacity",
             y: 2026, m: 10, d: 3, doors: (16, 15), start: (17, 0),
             listed: 1_240,
             performers: [("水瀬いのり", "Vocal"), ("岸 利至", "Keyboard / Band master"),
                          ("遠山雄也", "Guitar"), ("鈴木モモ", "Bass")]),
        make(id: "u2",
             title: "アニソンフェス 2026 -HARMONY- DAY1",
             artist: "アニソンフェス",
             venue: "幕張メッセ国際展示場",
             venueDetail: "Mihama, Chiba · 9,000 capacity",
             y: 2026, m: 10, d: 11, doors: (15, 0), start: (16, 0),
             listed: 3_480,
             performers: [("水瀬いのり", "Guest"), ("内田真礼", "Guest"),
                          ("花澤香菜", "Guest"), ("鈴木みのり", "Guest")]),
        make(id: "u3",
             title: "アニメ音楽祭 オーケストラコンサート 2026",
             artist: "アニメ音楽祭",
             venue: "東京国際フォーラム ホールA",
             venueDetail: "Chiyoda, Tokyo · 5,012 capacity",
             y: 2026, m: 10, d: 24, doors: (17, 0), start: (18, 0),
             listed: 890,
             performers: [("東京フィルハーモニー", "Orchestra"), ("佐々木 慧", "Conductor"),
                          ("花澤香菜", "Vocal guest")]),
        make(id: "u4",
             title: "内田真礼 BIRTHDAY LIVE 2026",
             artist: "内田真礼",
             venue: "横浜アリーナ",
             venueDetail: "Kohoku, Yokohama · 17,000 capacity",
             y: 2026, m: 11, d: 7, doors: (16, 0), start: (17, 0),
             listed: 2_210,
             performers: [("内田真礼", "Vocal"), ("内田雄馬", "Guest"), ("サポートバンド", "Band")]),
        make(id: "u5",
             title: "声優ラジオ 公開録音スペシャル",
             artist: "声優ラジオ",
             venue: "日本青年館ホール",
             venueDetail: "Shinjuku, Tokyo · 1,249 capacity",
             y: 2026, m: 11, d: 21, doors: (13, 15), start: (14, 0),
             listed: 410,
             performers: [("花澤香菜", "Host"), ("小野賢章", "Host")]),
        make(id: "u6",
             title: "声優グランプリ フェス 2026",
             artist: "声優グランプリ",
             venue: "豊洲PIT",
             venueDetail: "Koto, Tokyo · 3,000 capacity",
             y: 2026, m: 12, d: 13, doors: (16, 0), start: (17, 0),
             listed: 640,
             performers: [("鈴木みのり", "Vocal"), ("水瀬いのり", "Vocal")]),
        make(id: "p1",
             title: "サマーアニソンライブ 2026 DAY2",
             artist: "水瀬いのり",
             venue: "さいたまスーパーアリーナ",
             venueDetail: "Chuo, Saitama · 37,000 capacity",
             y: 2026, m: 8, d: 29, doors: (14, 0), start: (15, 0),
             listed: 5_120,
             performers: [("水瀬いのり", "Vocal"), ("内田真礼", "Vocal"), ("花澤香菜", "Vocal")]),
        make(id: "p2",
             title: "田村ゆかり LOVE♡LIVE 2026",
             artist: "田村ゆかり",
             venue: "パシフィコ横浜 国立大ホール",
             venueDetail: "Nishi, Yokohama · 5,002 capacity",
             y: 2026, m: 8, d: 9, doors: (15, 30), start: (16, 30),
             listed: 1_680,
             performers: [("田村ゆかり", "Vocal")]),
        make(id: "p3",
             title: "花澤香菜 ライブ 2026「blossom」",
             artist: "花澤香菜",
             venue: "LINE CUBE SHIBUYA",
             venueDetail: "Shibuya, Tokyo · 2,084 capacity",
             y: 2026, m: 7, d: 19, doors: (16, 0), start: (17, 0),
             listed: 960,
             performers: [("花澤香菜", "Vocal"), ("北川勝利", "Guitar / Producer")]),
    ]

    /// Public events not in the library — what a search of Eventernote turns up.
    static let discoverable: [Event] = [
        make(id: "s1",
             title: "鈴木みのり Birthday Live 2026「Hello, Again」",
             artist: "鈴木みのり",
             venue: "Zepp Shinjuku (TOKYO)",
             venueDetail: "Shinjuku, Tokyo · 1,500 capacity",
             y: 2026, m: 12, d: 20, doors: (16, 30), start: (17, 30),
             listed: 520,
             performers: [("鈴木みのり", "Vocal")]),
        make(id: "s2",
             title: "水瀬いのり LIVE TOUR 2026「Bloom in Blue」大阪公演",
             artist: "水瀬いのり",
             venue: "Zepp Osaka Bayside",
             venueDetail: "Minato, Osaka · 2,255 capacity",
             y: 2026, m: 10, d: 17, doors: (16, 15), start: (17, 0),
             listed: 780,
             performers: [("水瀬いのり", "Vocal"), ("岸 利至", "Keyboard")]),
        make(id: "s3",
             title: "アニソンフェス 2026 -HARMONY- DAY2",
             artist: "アニソンフェス",
             venue: "幕張メッセ国際展示場",
             venueDetail: "Mihama, Chiba · 9,000 capacity",
             y: 2026, m: 10, d: 12, doors: (15, 0), start: (16, 0),
             listed: 3_980,
             performers: [("鈴木みのり", "Guest"), ("田村ゆかり", "Guest")]),
        make(id: "s4",
             title: "声優バラエティ 生配信 公開収録",
             artist: "声優バラエティ",
             venue: "品川インターシティホール",
             venueDetail: "Minato, Tokyo · 600 capacity",
             y: 2026, m: 11, d: 3, doors: (12, 30), start: (13, 30),
             listed: 230,
             performers: [("内田真礼", "Host")]),
        make(id: "s5",
             title: "花澤香菜 トーク&ミニライブ",
             artist: "花澤香菜",
             venue: "Veats Shibuya",
             venueDetail: "Shibuya, Tokyo · 700 capacity",
             y: 2026, m: 12, d: 6, doors: (17, 0), start: (18, 0),
             listed: 310,
             performers: [("花澤香菜", "Vocal")]),
    ]

    /// The tracking the reader has already recorded against library events.
    static let tracking: [Event.ID: Tracking] = [
        "u1": Tracking(interest: .planning, ticket: .purchased, attendance: .unrecorded,
                       note: "Block A right. Meeting Yuki at Daiba station 15:30."),
        "u2": Tracking(interest: .interested, ticket: .none, attendance: .unrecorded,
                       note: "Lottery result 9/28. Day 2 lineup looks stronger."),
        "u3": Tracking(interest: .planning, ticket: .purchased, attendance: .unrecorded,
                       note: "2F K-12. Programme posted two weeks before."),
        "u4": Tracking(interest: .interested),
        "u5": Tracking(interest: .planning, ticket: .purchased, attendance: .unrecorded,
                       note: "Bring the postcard question."),
        "u6": Tracking(interest: .interested),
        "p1": Tracking(interest: .planning, ticket: .purchased, attendance: .attended,
                       note: "Best set of the year. Encore was worth the queue."),
        "p2": Tracking(interest: .planning, ticket: .purchased, attendance: .attended),
        "p3": Tracking(interest: .planning, ticket: .purchased, attendance: .attended,
                       note: "Acoustic block in the middle was the highlight."),
    ]

    static let recentSearches = ["水瀬いのり", "Zepp DiverCity", "アニソンフェス", "声優 公開録音", "横浜アリーナ"]

    /// Events are published in Japan Standard Time; the views render them in the
    /// reader's locale but the wall-clock door and start times are JST.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        return calendar
    }()

    private static func make(
        id: String, title: String, artist: String, venue: String, venueDetail: String,
        y: Int, m: Int, d: Int, doors: (Int, Int), start: (Int, Int),
        listed: Int, performers: [(String, String)]
    ) -> Event {
        Event(
            id: id,
            title: title,
            artist: artist,
            venue: venue,
            venueDetail: venueDetail,
            doorsOpen: date(y, m, d, doors),
            startsAt: date(y, m, d, start),
            timeZone: calendar.timeZone,
            listedAttendees: listed,
            performers: performers.map { Performer(name: $0.0, role: $0.1) },
            // Sample identifiers are not real Eventernote event IDs, so every
            // event links to the site root rather than a fabricated page.
            sourceURL: URL(string: "https://www.eventernote.com/")!
        )
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int, _ time: (Int, Int)) -> Date {
        let components = DateComponents(year: y, month: m, day: d, hour: time.0, minute: time.1)
        return calendar.date(from: components) ?? .distantPast
    }
}
