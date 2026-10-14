import Foundation

/// The design's own events, for what the widget gallery shows before the
/// app has written anything, the placeholder drawn while a timeline is made,
/// and the previews. Dated from now, so they read the same whenever they are
/// drawn.
nonisolated enum WidgetSamples {
    private static let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
    private static let link = URL(string: "https://www.eventernote.com/events/1")!

    /// 水瀬いのり at 東京ガーデンシアター, four days off — or today, an hour
    /// and a half before its doors.
    static func event(today: Bool = false, now: Date = .now) -> WidgetEvent {
        let calendar = Calendar.gregorian(in: tokyo)
        let doors: Date
        if today {
            doors = now.addingTimeInterval(2 * 60 * 60 + 15 * 60 + 40)
        } else {
            let day = calendar.date(byAdding: .day, value: 4, to: calendar.startOfDay(for: now)) ?? now
            doors = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: day) ?? day
        }
        let starts = doors.addingTimeInterval(60 * 60)
        let runsTo = starts.addingTimeInterval(3 * 60 * 60)
        return WidgetEvent(
            id: "sample-next", title: "水瀬いのり Autumn Live 2026 ＜東京公演＞", venue: "東京ガーデンシアター",
            // Today on the reader's own calendar, whatever hour the doors
            // fall at in Tokyo.
            link: link, flyer: nil, day: today ? CalendarDay(now) : CalendarDay(doors, in: calendar),
            shownDay: calendar.startOfDay(for: doors), timeZone: tokyo,
            doors: doors, starts: starts, ends: nil, runsTo: runsTo, leaves: runsTo,
            hasTicket: true, seat: "2階 C列 14番"
        )
    }

    /// One round out yesterday, one six days off, and one with no day.
    static func rounds(now: Date = .now) -> [WidgetRound] {
        func day(_ offset: Int) -> CalendarDay {
            CalendarDay(Calendar.gregorian().date(byAdding: .day, value: offset, to: now) ?? now)
        }
        let ends = now.addingTimeInterval(60 * 24 * 60 * 60)
        return [
            WidgetRound(eventID: "sample-1", entryID: UUID(), title: "伊達さゆり 1st Live Tour ＜大阪公演＞",
                        link: link, round: "Earliest Presale Lottery", applications: 2, day: day(-1),
                        choices: 1, onlyChoice: UUID(), eventEnds: ends),
            WidgetRound(eventID: "sample-2", entryID: UUID(), title: "Liella! Fan Meeting 2026 Winter Day2",
                        link: link, round: "First Lottery", applications: 1, day: day(6),
                        choices: 1, onlyChoice: UUID(), eventEnds: ends),
            WidgetRound(eventID: "sample-3", entryID: UUID(), title: "水瀬いのり2027年ライブツアー(仮)【東京】Day2",
                        link: link, round: "Earliest Presale Lottery", applications: 3, day: nil,
                        choices: 2, onlyChoice: nil, eventEnds: ends),
        ]
    }

    /// Two years ago today at ベルーナドーム, with a note.
    static func memories(now: Date = .now) -> [WidgetMemory] {
        let today = CalendarDay(now)
        let day = CalendarDay(year: today.year - 2, month: today.month, day: today.day)
        return [
            WidgetMemory(id: "sample-memory", title: "Liella! 5th LoveLive! Tour 埼玉公演 Day2",
                         venue: "ベルーナドーム", link: link, flyer: nil, day: day,
                         sortDate: day.date(), note: "Arena seats! Sang along to every encore."),
        ]
    }
}
