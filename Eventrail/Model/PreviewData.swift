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
             y: 2027, m: 4, d: 25, doors: nil, start: nil, listed: 57),
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
             y: 2025, m: 6, d: 14, doors: (14, 30), start: (15, 30), listed: 628),
    ]

    static let tracking: [Event.ID: Tracking] = [
        "492650": Tracking(interest: .interested),
        "492514": Tracking(interest: .planning, ticket: .purchased,
                           note: "Theatre 3, row H. Doors are tight — get there by 10:45."),
        "396310": Tracking(interest: .planning, ticket: .purchased, attendance: .attended,
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
        y: Int, m: Int, d: Int, doors: (Int, Int)?, start: (Int, Int)?, listed: Int
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
            imageURL: URL(string: "https://eventernote.s3.amazonaws.com/images/events/\(id)_s.jpg"),
            sourceURL: EventernoteClient.site.appending(path: "events/\(id)"),
            isDetailed: true
        )
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
        EventStore(file: nil, cloud: nil, calendar: nil, library: PreviewData.events,
                   tracking: PreviewData.tracking, follows: PreviewData.performers)
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
