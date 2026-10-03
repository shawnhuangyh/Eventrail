import Foundation
import Testing
@testable import Eventrail

/// The site's own lists behind the Search tab: which page each is read from,
/// and how the newest one — a page that counts nothing — reads.
struct SiteListingTests {
    private func query(of url: URL?) throws -> [String: String] {
        let url = try #require(url)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    /// 23:30 on 3 October in Los Angeles is 15:30 on the 4th in Tokyo: today's
    /// list is of the day the site is on, not the reader's.
    @Test func todayIsTheSitesDay() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let evening = try #require(losAngeles.date(from: DateComponents(year: 2026, month: 10, day: 3,
                                                                        hour: 23, minute: 30)))

        let url = EventernoteClient.pageURL(forEventsOn: evening, areaID: 2)
        #expect(url?.path() == "/events/search")
        let query = try query(of: url)
        #expect(query["year"] == "2026")
        #expect(query["month"] == "10")
        #expect(query["day"] == "4")
        #expect(query["area_id"] == "2")
        // The earliest start first, as the site's own menu asks for it.
        #expect(query["sort"] == "start_time")
        #expect(query["order"] == "ASC")
    }

    @Test func anywhereAsksForNoArea() throws {
        let query = try query(of: EventernoteClient.pageURL(forEventsOn: Fixtures.date(2026, 10, 3), areaID: nil))
        #expect(query["day"] == "3")
        #expect(query["area_id"] == nil)
    }

    @Test func theNewestListIsTheSitesOwnTab() {
        #expect(EventernoteClient.newestEventsURL?.absoluteString == "https://www.eventernote.com/events/?type=2")
    }

    /// The 新着 tab heads its rows "新着イベント一覧(100)" rather than counting
    /// them as a search does, and has no second page: the rows are the whole
    /// of it, and the feed is not sent looking for more.
    @Test func theNewestListIsOnePage() throws {
        let html = EventernotePagesTests.eventListing
            .replacingOccurrences(of: "<p class=\"t2\">689件見つかりました。</p>",
                                  with: "<h2 class=\"gb_subtitle\">新着イベント一覧(100)</h2>")
        let page = try EventernotePages.events(in: html, page: 1, pageSize: EventernoteClient.newestCount)
        #expect(page.items.map(\.id) == ["300001", "300003"])
        #expect(!page.hasMore)
    }
}
