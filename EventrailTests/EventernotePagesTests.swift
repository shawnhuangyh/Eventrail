import Foundation
import Testing
@testable import Eventrail

/// The adapter against hand-written pages in the shape of Eventernote's
/// smartphone templates — the markers here are the ones the adapter scans for,
/// not a copy of a real page.
struct EventernotePagesTests {
    // MARK: - Listings

    static let eventListing = """
        <p class="t2">並び替え: 新しい順</p>
        <p class="t2">689件見つかりました。</p>
        <div class="gb_listevent"><ul>
        <li class="clearfix"><a href="/events/300001">
          <div class="image"><img src="https://eventernote.s3.amazonaws.com/images/events/300001_s.jpg" /></div>
          <div class="event"><p>水瀬いのり LIVE TOUR 2027</p></div>
          <div class="date"><p>2027-05-09(日)</p></div>
          <div class="actor">水瀬いのり
        小倉唯</div>
          <div class="time">開場 17:00 開演 18:00 終演 20:30</div>
          <div class="place">Kアリーナ横浜</div>
        </a></li>
        <li class="clearfix"><a href="/events/300002">
          <div class="event"><p>A row with no date</p></div>
        </a></li>
        <li class="clearfix"><a href="/events/300003">
          <div class="event"><p>Rock &amp; Roll</p></div>
          <div class="date"><p>2027-04-25 (日)</p></div>
          <div class="place">日本武道館</div>
        </a></li>
        </ul></div>
        """

    @Test func readsListingRows() throws {
        let page = try EventernotePages.events(in: Self.eventListing, page: 1, pageSize: 30)

        // The row with no date is dropped rather than imported half-read.
        #expect(page.items.map(\.id) == ["300001", "300003"])
        #expect(page.total == 689)
        #expect(page.hasMore)

        let first = try #require(page.items.first)
        #expect(first.title == "水瀬いのり LIVE TOUR 2027")
        #expect(first.venue == "Kアリーナ横浜")
        #expect(first.performers.map(\.name) == ["水瀬いのり", "小倉唯"])
        #expect(first.artist == "水瀬いのり")
        #expect(first.imageURL?.absoluteString == "https://eventernote.s3.amazonaws.com/images/events/300001_s.jpg")
        #expect(first.date == Fixtures.date(2027, 5, 9))
        #expect(first.doorsOpen == Fixtures.date(2027, 5, 9, 17, 0))
        #expect(first.startsAt == Fixtures.date(2027, 5, 9, 18, 0))
        #expect(first.endsAt == Fixtures.date(2027, 5, 9, 20, 30))
        #expect(first.timeZone == Event.publishedZone)
        #expect(!first.isDetailed)
        #expect(first.sourceURL.absoluteString == "https://www.eventernote.com/events/300001")

        let second = try #require(page.items.last)
        #expect(second.title == "Rock & Roll")
        #expect(second.startsAt == nil)
        // A row billing nobody is grouped under its own title.
        #expect(second.artist == "Rock & Roll")
    }

    @Test func anEndPastMidnightIsReadAsTheNextMorning() throws {
        let html = Self.eventListing.replacingOccurrences(
            of: "開場 17:00 開演 18:00 終演 20:30", with: "開場 22:30 開演 23:00 終演 05:00")
        let first = try #require(try EventernotePages.events(in: html, page: 1, pageSize: 30).items.first)
        #expect(first.startsAt == Fixtures.date(2027, 5, 9, 23, 0))
        #expect(first.endsAt == Fixtures.date(2027, 5, 10, 5, 0))
    }

    @Test func aMemberListingTakesItsTotalFromTheHeading() throws {
        let html = """
            <h2 class="gb_subtitle">参加イベント一覧(879)</h2>
            <div class="gb_listevent"><ul></ul></div>
            """
        let page = try EventernotePages.events(in: html, page: 1, pageSize: 30)
        #expect(page.items.isEmpty)
        #expect(page.total == 879)
    }

    /// What the site sends for a search that matches nothing: the form, and
    /// no list under it.
    @Test func theSitesOwnPageWithoutTheListReadsAsEmpty() throws {
        let html = #"<div class="gb_form"></div><ul class="gb_foot_menu"></ul>"#
        let events = try EventernotePages.events(in: html, page: 1, pageSize: 30)
        #expect(events.items.isEmpty)
        #expect(events.total == 0)
        #expect(!events.hasMore)
        let performers = try EventernotePages.performers(in: html, page: 1, pageSize: 20)
        #expect(performers.items.isEmpty)
    }

    /// A maintenance page, a captcha, the desktop template: none of them says
    /// nothing was found.
    @Test func aPageThatIsNotTheSitesOwnIsNotAnEmptyListing() {
        #expect(throws: EventernoteClient.Failure.self) {
            try EventernotePages.events(in: "<html>maintenance</html>", page: 1, pageSize: 30)
        }
        #expect(throws: EventernoteClient.Failure.self) {
            try EventernotePages.performers(in: "<html>maintenance</html>", page: 1, pageSize: 20)
        }
    }

    @Test func readsPerformerSearch() throws {
        let html = """
            <p>2件見つかりました。</p>
            <div class="gb_listview"><ul>
            <li><a href="/actors/%E6%B0%B4%E7%80%AC%E3%81%84%E3%81%AE%E3%82%8A/2626">水瀬いのり (みなせいのり)<span>12,345</span></a></li>
            <li><a href="/actors/Lynn/9001">Lynn<span>88</span></a></li>
            </ul></div>
            """
        let page = try EventernotePages.performers(in: html, page: 1, pageSize: 20)
        #expect(page.total == 2)
        #expect(!page.hasMore)

        let first = try #require(page.items.first)
        #expect(first.id == 2626)
        #expect(first.name == "水瀬いのり")
        #expect(first.reading == "みなせいのり")
        #expect(first.fanCount == 12345)
        // Passed through as the site encoded it, never encoded again.
        #expect(first.slug == "%E6%B0%B4%E7%80%AC%E3%81%84%E3%81%AE%E3%82%8A")

        let second = try #require(page.items.last)
        #expect(second.name == "Lynn")
        #expect(second.reading == nil)
    }

    @Test func readsPlaceSearchPastThePager() {
        let html = """
            <div class="gb_listview">
            <div class="pager"><a href="/places/search?keyword=x&page=2">2</a></div>
            <ul>
            <li><a href="/places/1234">Kアリーナ横浜</a></li>
            <li><a href="/places/5678">日本武道館</a></li>
            </ul></div>
            """
        let places = EventernotePages.places(in: html)
        #expect(places.map(\.id) == [1234, 5678])
        #expect(places.map(\.name) == ["Kアリーナ横浜", "日本武道館"])
    }

    // MARK: - An event's own page

    static let eventPage = """
        <div class="gb_title_cover" style="background-image:url(https://eventernote.s3.amazonaws.com/images/events/300001.jpg)"></div>
        <h1 class="gb_subtitle gb_curl_effect">水瀬いのり LIVE TOUR 2027</h1>
        <h2 class="gb_subtitle">開催日時</h2><p>2027-05-09 (日)</p>
        <h2 class="gb_subtitle">開催場所</h2><p><a href="/places/1234">Kアリーナ横浜</a></p>
        <h2 class="gb_subtitle">開場/開演/終演時間</h2><p>開場 16:30 開演 17:30 終演 -</p>
        <h2 class="gb_subtitle">出演者</h2><p><a href="/actors/foo/10">水瀬いのり</a> <a href="/actors/bar/20">小倉唯</a></p>
        <h2 class="gb_subtitle">概要</h2><p>チケット<br />S席 9,900円<br/>A席 8,800円</p>
        <h2 class="gb_subtitle">関連リンク</h2><p><a href="https://example.com/news?a=1&amp;b=2">https://example.com/news?a=1&amp;b=2</a> <a href="https://example.com/news?a=1&amp;b=2">again</a> <a href="javascript:void(0)">nothing</a></p>
        <h2 class="gb_subtitle">Twitterハッシュタグ</h2><p><a href="https://mobile.twitter.com/search?q=%23inori">#inori</a></p>
        <h2 class="gb_subtitle">イベント登録/最終更新履歴</h2>
        <ul id="authors"><li><a class="noline" href="/users/editor">editor</a> <span class="s color2">3日前</span></li>
        <li class="hide"><a class="noline" href="/users/older">older</a> <span class="s color2">400日前</span></li></ul>
        <p>このイベントに参加のイベンター(1,234)</p>
        """

    @Test func readsAnEventPage() throws {
        let event = try #require(EventernotePages.event(in: Self.eventPage, id: "300001"))

        #expect(event.title == "水瀬いのり LIVE TOUR 2027")
        #expect(event.imageURL?.absoluteString == "https://eventernote.s3.amazonaws.com/images/events/300001.jpg")
        #expect(event.venue == "Kアリーナ横浜")
        #expect(event.placeID == 1234)
        #expect(event.performers == [Performer(name: "水瀬いのり", actorID: 10),
                                     Performer(name: "小倉唯", actorID: 20)])
        #expect(event.doorsOpen == Fixtures.date(2027, 5, 9, 16, 30))
        #expect(event.startsAt == Fixtures.date(2027, 5, 9, 17, 30))
        // "-" is a time nobody has published yet.
        #expect(event.endsAt == nil)
        #expect(event.listedAttendees == 1234)
        #expect(event.isDetailed)
        #expect(event.isFullyDetailed)
        #expect(event.detailFormat == Event.currentDetailFormat)
    }

    @Test func keepsTheOverviewLineBreaks() throws {
        let event = try #require(EventernotePages.event(in: Self.eventPage, id: "300001"))
        #expect(event.summary == "チケット\nS席 9,900円\nA席 8,800円")
    }

    @Test func readsLinksOnceEachAndHTTPOnly() throws {
        let event = try #require(EventernotePages.event(in: Self.eventPage, id: "300001"))
        #expect(event.relatedLinks?.map(\.absoluteString) == ["https://example.com/news?a=1&b=2"])
        #expect(event.hashtags?.map(\.tag) == ["#inori"])
        #expect(event.hashtags?.first?.searchURL.absoluteString == "https://mobile.twitter.com/search?q=%23inori")
    }

    @Test func readsTheLatestEdit() throws {
        let event = try #require(EventernotePages.event(in: Self.eventPage, id: "300001"))
        #expect(event.editedBy == "editor")
        let editedAt = try #require(event.editedAt)
        let days = Calendar.current.dateComponents([.day], from: editedAt, to: .now).day
        #expect(days == 3)
    }

    @Test func anEventPageWithoutSectionsStillReads() throws {
        let html = """
            <h1 class="gb_subtitle gb_curl_effect">Announced</h1>
            <h2 class="gb_subtitle">開催日時</h2><p>2028-01-02</p>
            """
        let event = try #require(EventernotePages.event(in: html, id: "9"))
        #expect(event.startsAt == nil)
        #expect(event.performers.isEmpty)
        #expect(event.summary == nil)
        // Empty rather than nil: the page was read and published none.
        #expect(event.relatedLinks == [])
        #expect(event.hashtags == [])
        #expect(event.editedBy == nil)
    }

    @Test func anEventPageWithoutADateIsNotAnEvent() {
        let html = #"<h1 class="gb_subtitle gb_curl_effect">No day</h1>"#
        #expect(EventernotePages.event(in: html, id: "9") == nil)
    }

    // MARK: - A venue's own page

    static let venuePage = """
        <div class="mod_places_detail">
        <h1 class="gb_subtitle gb_curl_effect">Kアリーナ横浜</h1>
        <h2 class="gb_subtitle">所在地</h2><p class="t">〒220-0012 神奈川県横浜市西区みなとみらい6-2-14</p>
        <h2 class="gb_subtitle">電話番号</h2><p class="t"></p>
        <h2 class="gb_subtitle">公式サイト</h2><p class="t"><a href="https://k-arena.com/">ウェブサイト</a></p>
        <h2 class="gb_subtitle">収容人数</h2><p class="t">20,033人</p>
        <h2 class="gb_subtitle">座席情報</h2><p class="t"><a href="https://example.com/seats">座席情報</a></p>
        <h2 class="gb_subtitle">会場TIPS</h2><p class="t">みなとみらい駅 徒歩5分<br>新高島駅 徒歩7分</p>
        </div>
        """

    @Test func readsAVenuePage() throws {
        let venue = try #require(EventernotePages.venue(in: Self.venuePage, id: 1234))
        #expect(venue.id == 1234)
        #expect(venue.name == "Kアリーナ横浜")
        #expect(venue.address == "神奈川県横浜市西区みなとみらい6-2-14")
        #expect(venue.capacity == "20,033人")
        // Members leave sections empty; an empty one is nil, not "".
        #expect(venue.phone == nil)
        #expect(venue.website?.absoluteString == "https://k-arena.com/")
        #expect(venue.seatingChart?.absoluteString == "https://example.com/seats")
        #expect(venue.tips == "みなとみらい駅 徒歩5分\n新高島駅 徒歩7分")
    }

    @Test func joinsTheVenueDetailAndReadsTheAddressBack() throws {
        let detail = try #require(EventernotePages.venueDetail(in: Self.venuePage))
        #expect(detail == "神奈川県横浜市西区みなとみらい6-2-14 · 20,033人")
        #expect(EventernotePages.address(inDetail: detail) == "神奈川県横浜市西区みなとみらい6-2-14")
    }

    @Test func aCapacityAloneIsNotAnAddress() {
        #expect(EventernotePages.address(inDetail: "8,028席") == nil)
    }

    // MARK: - A member's own page

    @Test func readsAMemberProfile() throws {
        let html = """
            <div class="mod_mypage_cover"><div class="thumb"><img src="http://pbs.twimg.com/profile/a.jpg"></div></div>
            <div class="profile_box clearfix"><h1 class="top">Shawn</h1><p class="text">声優イベント</p></div>
            <div class="gb_score_table"><a href="/users/shawn/events">879</a></div>
            <div class="favorite_actor"><ul>
            <li><a href="/actors/foo/10">水瀬いのり</a></li>
            <li><a href="/actors/bar/20">小倉唯</a></li>
            </ul></div>
            """
        let profile = try #require(EventernotePages.profile(in: html, handle: "shawn"))
        #expect(profile.handle == "shawn")
        #expect(profile.name == "Shawn")
        #expect(profile.bio == "声優イベント")
        #expect(profile.eventCount == 879)
        // Announced over HTTP, which App Transport Security would refuse.
        #expect(profile.avatarURL?.absoluteString == "https://pbs.twimg.com/profile/a.jpg")
        #expect(profile.favoritePerformers.map(\.id) == [10, 20])
        #expect(profile.favoritePerformers.map(\.slug) == ["foo", "bar"])
    }

    @Test func aPageWithoutAProfileIsNotAProfile() {
        #expect(EventernotePages.profile(in: "<html></html>", handle: "x") == nil)
    }
}
