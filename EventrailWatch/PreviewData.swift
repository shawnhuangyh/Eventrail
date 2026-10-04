#if DEBUG
import Foundation

/// The design's own events, for `#Preview` only — the first set an hour and a
/// half before its doors, so the previews show an event under way.
extension WatchLibrary {
    static var preview: WatchLibrary {
        let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo
        let now = Date.now
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) ?? now
        }
        func at(_ day: Date, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func link(_ id: String) -> URL {
            URL(string: "https://www.eventernote.com/events/\(id)")!
        }
        let doors = now.addingTimeInterval(84 * 60)
        return WatchLibrary(events: [
            WatchEvent(id: "492514", title: "『劇場版ダーウィンが来た！世界のネコのなかまたち』舞台挨拶付上映＜11:20の回＞",
                       venue: "ユナイテッド・シネマ豊洲", link: link("492514"), flyer: nil, day: day(0),
                       doors: doors, starts: doors.addingTimeInterval(15 * 60),
                       ends: doors.addingTimeInterval(119 * 60), timeZone: tokyo,
                       hasTicket: true, seat: "3階 H列 21番", seatClass: "S席", cost: 8800, currency: "JPY", lotteryEntries: nil),
            WatchEvent(id: "489120", title: "水瀬いのり LIVE TOUR 2026 \"Lantern\" 【神奈川】Day1",
                       venue: "パシフィコ横浜 国立大ホール", link: link("489120"), flyer: nil, day: day(15),
                       doors: at(day(15), 17, 0), starts: at(day(15), 18, 0), ends: nil, timeZone: tokyo,
                       hasTicket: false, seat: "", seatClass: "", cost: nil, currency: nil, lotteryEntries: 2),
            WatchEvent(id: "491006", title: "伊達さゆり 1st Live「Sincerely Yours」",
                       venue: "Zepp DiverCity(TOKYO)", link: link("491006"), flyer: nil, day: day(35),
                       doors: at(day(35), 17, 15), starts: at(day(35), 18, 0), ends: nil, timeZone: tokyo,
                       hasTicket: false, seat: "", seatClass: "", cost: nil, currency: nil, lotteryEntries: nil),
            WatchEvent(id: "492650", title: "水瀬いのり2027年ライブツアー(仮)【東京】Day2",
                       venue: "京王アリーナTOKYO", link: link("492650"), flyer: nil, day: day(204),
                       doors: nil, starts: nil, ends: nil, timeZone: tokyo,
                       hasTicket: false, seat: "", seatClass: "", cost: nil, currency: nil, lotteryEntries: nil),
        ], showsLocalTime: false)
    }
}
#endif
