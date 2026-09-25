import Foundation
@testable import Eventrail

/// Builders for the values the tests are made of, so each test names only the
/// fields it is about.
enum Fixtures {
    static let tokyo = Event.publishedZone
    static let taipei = TimeZone(identifier: "Asia/Taipei")!

    /// An instant on a wall clock in `zone` — which is how Eventernote prints
    /// every time it publishes.
    static func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0,
        in zone: TimeZone = tokyo
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                  hour: hour, minute: minute))!
    }

    static func event(
        id: String = "1",
        title: String = "Live",
        venue: String = "Hall",
        venueDetail: String? = nil,
        venueAddress: String? = nil,
        date: Date = Fixtures.date(2027, 5, 9),
        doorsOpen: Date? = nil,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        timeZone: TimeZone = tokyo,
        performers: [String] = [],
        summary: String? = nil,
        isDetailed: Bool = false,
        detailFormat: Int? = nil
    ) -> Event {
        Event(
            id: id,
            title: title,
            artist: performers.first ?? title,
            venue: venue,
            venueDetail: venueDetail,
            venueAddress: venueAddress,
            placeID: nil,
            date: date,
            doorsOpen: doorsOpen,
            startsAt: startsAt,
            endsAt: endsAt,
            timeZone: timeZone,
            listedAttendees: nil,
            performers: performers.map { Performer(name: $0) },
            summary: summary,
            imageURL: nil,
            sourceURL: URL(string: "https://www.eventernote.com/events/\(id)")!,
            isDetailed: isDetailed,
            detailFormat: detailFormat
        )
    }

    /// Midnight in Tokyo on the day `offset` days from the reader's today, as
    /// an import would date it.
    static func day(fromToday offset: Int) -> Date {
        let reader = Calendar.current
        let target = reader.date(byAdding: .day, value: offset, to: reader.startOfDay(for: .now))!
        let fields = reader.dateComponents([.year, .month, .day], from: target)
        return date(fields.year!, fields.month!, fields.day!)
    }
}
