import CoreLocation
import CoreSpotlight
import Foundation
import Testing
@testable import Eventrail

/// What goes into Spotlight — only an event's public facts — and how a pass
/// decides what to write and what to take out.
@MainActor
struct SpotlightTests {
    // MARK: - What a pass writes

    @Test func aPassWritesWhatChangedAndTakesOutWhatWent() {
        let plan = SpotlightPlan(
            before: ["event/1": "a", "event/2": "b", "venue/Hall": "c"],
            after: ["event/1": "a", "event/2": "B", "performer/9": "d"]
        )
        #expect(plan.writes == ["event/2", "performer/9"])
        #expect(plan.deletes == ["venue/Hall"])
    }

    @Test func aPassWithNothingMovedWritesNothing() {
        let plan = SpotlightPlan(before: ["event/1": "a"], after: ["event/1": "a"])
        #expect(plan.isEmpty)
    }

    /// The client state the index keeps is how a launch knows the file it
    /// wrote still says what the index holds.
    @Test func theDigestIgnoresOrderAndFollowsEveryFingerprint() {
        let one = SpotlightIndex.digest(of: ["event/1": "a", "event/2": "b"])
        let same = SpotlightIndex.digest(of: ["event/2": "b", "event/1": "a"])
        let moved = SpotlightIndex.digest(of: ["event/1": "a", "event/2": "c"])
        #expect(one == same)
        #expect(one != moved)
        #expect(one.count < 250)
    }

    // MARK: - An event

    func entity(_ event: Event, isKept: Bool = true, readings: [String: [String]] = [:]) -> EventEntity {
        EventEntity(event, isKept: isKept, display: .venue, coordinate: nil, readings: readings)
    }

    @Test func anEventIsFoundByItsPublicFacts() {
        let event = Fixtures.event(id: "42", title: "MyGO!!!!! 9th LIVE", venue: "Kアリーナ横浜",
                                   venueAddress: "神奈川県横浜市西区みなとみらい6-2-14",
                                   startsAt: Fixtures.date(2027, 5, 9, 17),
                                   performers: ["羊宮妃那", "立石凛"])
        let found = entity(event, readings: ["羊宮妃那": ["ようみやひな", "yoomiyahina"]])
        let set = found.attributeSet
        #expect(set.title == "MyGO!!!!! 9th LIVE")
        #expect(set.namedLocation == "Kアリーナ横浜")
        #expect(set.performers == ["羊宮妃那", "立石凛"])
        #expect(set.keywords?.contains("神奈川県横浜市西区みなとみらい6-2-14") == true)
        #expect(set.keywords?.contains("ようみやひな") == true)
        #expect(set.allDay == false)
        #expect(found.day == event.dayLine)
        #expect(found.matches("yoomiya"))
        #expect(found.matches("立石"))
        #expect(!found.matches("武道館"))
    }

    /// The site's placeholder for a stream or an undisclosed room is no hall,
    /// and nobody types `!_` to find one.
    @Test func aPlaceholderVenueIsNoPlace() {
        let set = entity(Fixtures.event(venue: "!_国内外各所 (ライブビューイング等)", performers: ["羊宮妃那"])).attributeSet
        #expect(set.namedLocation == nil)
        #expect(set.keywords == ["羊宮妃那"])
    }

    @Test func anEventWithNoStartIsAllDay() {
        #expect(entity(Fixtures.event(startsAt: nil)).isAllDay)
    }

    /// A kept event stays for as long as it is kept; a followed performer's
    /// date goes once its day is over everywhere, as the Following tab lets it
    /// go, whether or not the app runs again.
    @Test func onlyADateNobodyKeptExpires() {
        let event = Fixtures.event(date: Fixtures.day(fromToday: 10))
        #expect(entity(event, isKept: true).expires == nil)
        #expect(entity(event, isKept: false).expires == event.dayEndsEverywhere)
    }

    // MARK: - A performer

    @Test func aReadingIsFoundHoweverItIsTyped() {
        #expect(PerformerEntity.soundings(of: "あいな") == ["あいな", "アイナ", "aina"])
        #expect(PerformerEntity.soundings(of: "アイナ") == ["アイナ", "あいな", "aina"])
        #expect(PerformerEntity.soundings(of: "  ") == [])
        #expect(PerformerEntity.soundings(of: nil) == [])
    }

    // MARK: - A hall

    @Test func aHallTakesWhatAnotherEventThereKnows() {
        let bare = VenueEntity(id: "日本武道館", placeID: nil, address: nil, latitude: nil, longitude: nil)
        let known = Fixtures.event(venue: "日本武道館", venueAddress: "東京都千代田区北の丸公園2-3")
        let filled = bare.filling(from: known, at: CLLocationCoordinate2D(latitude: 35.69, longitude: 139.75))
        #expect(filled.address == "東京都千代田区北の丸公園2-3")
        #expect(filled.latitude == 35.69)

        // What it already knows stands.
        let other = Fixtures.event(venue: "日本武道館", venueAddress: "somewhere else")
        #expect(filled.filling(from: other, at: nil).address == "東京都千代田区北の丸公園2-3")
        #expect(filled.link == .named("日本武道館"))
    }

    // MARK: - Opening a result

    @Test func aResultOpensWhatItsIdentifierNames() {
        let store = EventStore(database: LibraryDatabase(at: .memory, syncing: false), libraryFile: nil,
                               calendar: nil, venues: nil, pageReads: nil)
        #expect(SpotlightIndex.opening("event/123", in: store) == .event("123"))
        // Nobody followed under that id any more.
        #expect(SpotlightIndex.opening("performer/9", in: store) == nil)
        #expect(SpotlightIndex.opening("nonsense", in: store) == nil)
    }
}
