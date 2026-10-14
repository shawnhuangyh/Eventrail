import EventKit
import Foundation
import Testing
@testable import Eventrail

struct CalendarSyncTests {
    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    /// Tokyo's midnight is 23:00 the evening before in Shanghai; an all-day
    /// entry handed that instant would sit on the wrong day.
    @Test func anUntimedEventKeepsItsHallsDayWestOfTokyo() {
        let event = Fixtures.event(date: Fixtures.date(2027, 5, 9))
        let shanghai = calendar("Asia/Shanghai")
        let day = CalendarSync.floatingDay(of: event, in: shanghai)
        #expect(shanghai.dateComponents([.year, .month, .day, .hour], from: day)
            == DateComponents(year: 2027, month: 5, day: 9, hour: 0))
    }

    @Test func anUntimedEventAbroadKeepsItsOwnHallsDay() {
        let event = Fixtures.event(date: Fixtures.date(2027, 5, 9, in: Fixtures.taipei), timeZone: Fixtures.taipei)
        let angeles = calendar("America/Los_Angeles")
        let day = CalendarSync.floatingDay(of: event, in: angeles)
        #expect(angeles.dateComponents([.year, .month, .day, .hour], from: day)
            == DateComponents(year: 2027, month: 5, day: 9, hour: 0))
    }

    /// A new entry's dates are nil until written; an untimed event was
    /// compared by its day against them and crashed the mirror.
    @Test func aDateNotYetWrittenIsNoDay() {
        let shanghai = calendar("Asia/Shanghai")
        let day = CalendarSync.floatingDay(of: Fixtures.event(date: Fixtures.date(2027, 5, 9)), in: shanghai)
        #expect(!CalendarSync.isDate(nil, inSameDayAs: day, in: shanghai))
        #expect(CalendarSync.isDate(day.addingTimeInterval(23 * 60 * 60), inSameDayAs: day, in: shanghai))
        #expect(!CalendarSync.isDate(day.addingTimeInterval(24 * 60 * 60), inSameDayAs: day, in: shanghai))
    }

    // MARK: - Which entries go

    private func page(_ id: String) -> URL {
        URL(string: "https://www.eventernote.com/events/\(id)")!
    }

    /// The calendar is shared with the reader's other devices: an entry this
    /// device's library lacks goes only where this device knows its event
    /// left. A device set up afresh, its library not yet arrived, took every
    /// other device's entries out of the calendar.
    @Test func anEntryGoesOnlyWhereItsEventIsKnownToHaveLeft() {
        let library: Set<URL> = [page("1")]
        // Another device's, never held here.
        #expect(!CalendarSync.goes(page("2"), library: library, departed: []))
        // Taken out of the library, here or synced in.
        #expect(CalendarSync.goes(page("2"), library: library, departed: ["2"]))
        // A second entry for an event already written.
        #expect(CalendarSync.goes(page("1"), library: library, departed: []))
        // Nothing this mirror writes.
        #expect(CalendarSync.goes(nil, library: library, departed: []))
        #expect(CalendarSync.goes(URL(string: "https://www.eventernote.com/actors/1"), library: library, departed: []))
        #expect(CalendarSync.goes(URL(string: "https://example.com/events/2"), library: library, departed: []))
    }

    // MARK: - Whose placing an entry keeps

    /// Where Apple Maps puts Zepp Haneda, and the block the register puts it on.
    private static let byMaps = (35.5503, 139.7547)
    private static let byRegister = (35.5512, 139.7531)

    /// A placing this device holds, as the mirror is handed one.
    private func found(at spot: (Double, Double), maps: Bool, uncertainty: Double = 0,
                       other: (Double, Double)? = nil) -> CalendarSync.Place {
        CalendarSync.Place(name: nil, address: nil, latitude: spot.0, longitude: spot.1,
                           uncertainty: uncertainty, otherLatitude: other?.0, otherLongitude: other?.1,
                           isFromMaps: maps)
    }

    /// An entry's location as the mirror writes one for `place`, or as it
    /// finds one already there.
    private func location(_ title: String = "Zepp Haneda(TOKYO)", at spot: (Double, Double)?, radius: Double) -> EKStructuredLocation {
        let location = EKStructuredLocation(title: title)
        if let spot { location.geoLocation = CLLocation(latitude: spot.0, longitude: spot.1) }
        location.radius = radius
        return location
    }

    private func wanted(_ place: CalendarSync.Place?) -> EKStructuredLocation {
        location(at: place.map { ($0.latitude, $0.longitude) }, radius: place?.radius ?? 0)
    }

    /// Apple Maps' placing says so by its radius, and no other answer's does.
    @Test func onlyMapsPlacingCarriesNoRadius() {
        #expect(found(at: Self.byMaps, maps: true).radius == 0)
        #expect(found(at: Self.byMaps, maps: false).radius == CalendarSync.Place.notMapsRadius)
        #expect(found(at: Self.byRegister, maps: false, uncertainty: 300).radius == 300)
    }

    /// A device placing the hall otherwise — the register, OpenStreetMap, or
    /// not at all — leaves Maps' placing where another device wrote it.
    @Test func mapsPlacingIsKeptByADeviceWithout() {
        let existing = location(at: Self.byMaps, radius: 0)
        let register = found(at: Self.byRegister, maps: false, uncertainty: 300)
        #expect(CalendarSync.keepsLocation(existing, over: wanted(register), found: register))
        let building = found(at: Self.byRegister, maps: false)
        #expect(CalendarSync.keepsLocation(existing, over: wanted(building), found: building))
        #expect(CalendarSync.keepsLocation(existing, over: location(at: nil, radius: 0), found: nil))
    }

    /// The device holding Maps' placing writes it over anything else.
    @Test func mapsPlacingIsWrittenOverAnyOther() {
        let maps = found(at: Self.byMaps, maps: true)
        for existing in [location(at: Self.byRegister, radius: 300),
                         location(at: Self.byRegister, radius: CalendarSync.Place.notMapsRadius),
                         location(at: nil, radius: 0)] {
            #expect(!CalendarSync.keepsLocation(existing, over: wanted(maps), found: maps))
        }
        // Maps' own answer, moved since: the newer is written.
        let moved = location(at: (35.5600, 139.7600), radius: 0)
        #expect(!CalendarSync.keepsLocation(moved, over: wanted(maps), found: maps))
    }

    /// Two answers neither of them Maps' go as they always went: this
    /// device's is written.
    @Test func anotherAnswerNotMapsIsWrittenOver() {
        let building = found(at: Self.byMaps, maps: false)
        let existing = location(at: Self.byRegister, radius: 300)
        #expect(!CalendarSync.keepsLocation(existing, over: wanted(building), found: building))
    }

    /// The same answer is left alone: where this device draws it, where a
    /// device on the other map provider draws it, and a metre's rounding off.
    @Test func theSameAnswerIsLeftAlone() {
        let shifted = (22.3020, 114.1772)
        let osm = found(at: (22.2995, 114.1720), maps: false, other: shifted)
        let own = location(at: (22.2995, 114.1720), radius: CalendarSync.Place.notMapsRadius)
        #expect(CalendarSync.keepsLocation(own, over: wanted(osm), found: osm))
        let theirs = location(at: shifted, radius: CalendarSync.Place.notMapsRadius)
        #expect(CalendarSync.keepsLocation(theirs, over: wanted(osm), found: osm))
        let rounded = location(at: (22.299504, 114.172004), radius: CalendarSync.Place.notMapsRadius)
        #expect(CalendarSync.keepsLocation(rounded, over: wanted(osm), found: osm))
    }

    /// A different hall is a different place, Maps' or not.
    @Test func aDifferentHallIsWrittenOver() {
        let existing = location("Zepp DiverCity(TOKYO)", at: Self.byMaps, radius: 0)
        let register = found(at: Self.byRegister, maps: false, uncertainty: 300)
        #expect(!CalendarSync.keepsLocation(existing, over: wanted(register), found: register))
    }
}
