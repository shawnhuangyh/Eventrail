import Foundation
import Testing
@testable import Eventrail

/// The phone and the watch app are updated apart, so each has to read a copy
/// the other's build wrote.
struct WatchLibraryTests {
    func event(id: String = "1") -> WatchEvent {
        WatchEvent(id: id, title: "Live", venue: "Hall", link: URL(string: "https://www.eventernote.com/events/\(id)")!,
                   flyer: nil, day: Fixtures.date(2027, 5, 9), doors: nil, starts: nil, ends: nil,
                   timeZone: TimeZone(identifier: "Asia/Tokyo")!, hasTicket: true, seat: "A12",
                   seatClass: "S席", cost: 9900, currency: "JPY", lotteryEntries: 3, lottery: "won")
    }

    func json(_ library: WatchLibrary) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as! [String: Any]
    }

    @Test func aCopyReadsBackAsItWasSent() throws {
        let library = WatchLibrary(events: [event(id: "1"), event(id: "2")], showsLocalTime: true)
        let read = try JSONDecoder().decode(WatchLibrary.self, from: JSONEncoder().encode(library))
        #expect(read == library)
    }

    /// A phone a build behind sends no seat class, no currency and no
    /// standing; a phone a build ahead sends keys this watch has never heard
    /// of. Both read.
    @Test func keysMissingOrUnknownStillRead() throws {
        var copy = try json(WatchLibrary(events: [event()], showsLocalTime: false))
        var sent = (copy["events"] as! [[String: Any]])[0]
        for key in ["seatClass", "currency", "lottery", "venue", "hasTicket"] { sent[key] = nil }
        sent["paidBy"] = "2026-10-20"
        copy["events"] = [sent]
        copy["showsLocalTime"] = nil
        copy["format"] = 2

        let read = try JSONDecoder().decode(WatchLibrary.self,
                                            from: JSONSerialization.data(withJSONObject: copy))
        #expect(read.events.map(\.id) == ["1"])
        #expect(read.events[0].seat == "A12")
        #expect(read.events[0].seatClass.isEmpty)
        #expect(!read.events[0].hasTicket)
        #expect(!read.showsLocalTime)
    }

    /// One event the watch cannot read leaves out that event, not the rest.
    @Test func anEventThatCannotBeReadIsLeftOut() throws {
        var copy = try json(WatchLibrary(events: [event(id: "1"), event(id: "2")], showsLocalTime: false))
        var events = copy["events"] as! [[String: Any]]
        events[0]["day"] = "tomorrow"
        copy["events"] = events

        let read = try JSONDecoder().decode(WatchLibrary.self,
                                            from: JSONSerialization.data(withJSONObject: copy))
        #expect(read.events.map(\.id) == ["2"])
    }
}
