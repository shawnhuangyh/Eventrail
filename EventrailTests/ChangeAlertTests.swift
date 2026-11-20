import Foundation
import Testing
import UserNotifications
@testable import Eventrail

/// What counts as a kept event having moved, what the alert says, and which
/// reads of the library say it — see ``ChangeAlerts``.
@MainActor
struct ChangeAlertTests {
    let held = Fixtures.event(id: "5", title: "Tour Final", venue: "日本武道館",
                              date: Fixtures.date(2027, 5, 9), startsAt: Fixtures.date(2027, 5, 9, 18),
                              performers: ["A"], isDetailed: true)

    // MARK: - What moved

    @Test func anotherDayIsAMove() {
        var moved = held
        moved.date = Fixtures.date(2027, 5, 10)
        moved.startsAt = Fixtures.date(2027, 5, 10, 18)
        #expect(EventMove.kinds(from: ListingCopy(held), to: moved) == [.day])
    }

    @Test func anotherStartIsAMove() {
        var moved = held
        moved.startsAt = Fixtures.date(2027, 5, 9, 18, 30)
        #expect(EventMove.kinds(from: ListingCopy(held), to: moved) == [.start])
    }

    /// Every event is announced before its times are: the first start
    /// printed is not a move.
    @Test func aStartPrintedForTheFirstTimeIsNoMove() {
        var unprinted = held
        unprinted.startsAt = nil
        #expect(EventMove.kinds(from: ListingCopy(unprinted), to: held).isEmpty)
        #expect(ChangeAlert(from: ListingCopy(unprinted), to: held, clock: .venue) == nil)
    }

    @Test func anotherHallIsAMoveAndTheSameOneRespelledIsNot() {
        let zepp = Fixtures.event(id: "5", venue: "Zepp DiverCity (TOKYO)", date: held.date)
        let respelled = Fixtures.event(id: "5", venue: "Ｚｅｐｐ DiverCity（TOKYO）", date: held.date)
        let elsewhere = Fixtures.event(id: "5", venue: "有明アリーナ", date: held.date)
        #expect(EventMove.kinds(from: ListingCopy(zepp), to: respelled).isEmpty)
        #expect(EventMove.kinds(from: ListingCopy(zepp), to: elsewhere) == [.venue])
    }

    /// A hall named where a placeholder stood is news of another kind.
    @Test func aHallNamedForThePlaceholderIsNoMove() {
        let somewhere = Fixtures.event(id: "5", venue: "!_東京都内某所", date: held.date)
        #expect(EventMove.kinds(from: ListingCopy(somewhere), to: held).isEmpty)
    }

    /// The bill, the title and the doors make a date Updated, and none of
    /// them moves it.
    @Test func aBillTitleOrDoorsChangedIsNoMove() {
        let billed = Fixtures.event(id: "5", title: "Tour Final 追加公演", venue: held.venue, date: held.date,
                                    doorsOpen: Fixtures.date(2027, 5, 9, 17), startsAt: held.startsAt,
                                    performers: ["A", "B"], isDetailed: true)
        #expect(EventMove.kinds(from: ListingCopy(held), to: billed).isEmpty)
    }

    // MARK: - What it says

    @Test func itSaysEachMoveFromWhatItWasToWhatItIs() throws {
        let moved = Fixtures.event(id: "5", title: "Tour Final", venue: "有明アリーナ",
                                   date: Fixtures.date(2027, 5, 10), startsAt: Fixtures.date(2027, 5, 10, 17),
                                   performers: ["A"], isDetailed: true)
        let alert = try #require(ChangeAlert(from: ListingCopy(held), to: moved, clock: .venue))
        #expect(alert.kinds == [.day, .start, .venue])
        #expect(alert.subtitle == "Tour Final")
        let lines = alert.body.split(separator: "\n")
        let (was, now) = (try #require(held.timeLine), try #require(moved.timeLine))
        #expect(lines.count == 3)
        #expect(lines[1].contains(was) && lines[1].contains(now))
        #expect(lines[2].contains("日本武道館") && lines[2].hasSuffix("有明アリーナ"))
    }

    @Test func eachMoveHasATitleOfItsOwn() throws {
        var day = held
        day.date = Fixtures.date(2027, 5, 10)
        day.startsAt = Fixtures.date(2027, 5, 10, 18)
        var start = held
        start.startsAt = Fixtures.date(2027, 5, 9, 19)
        let titles = try [day, start].map { try #require(ChangeAlert(from: ListingCopy(held), to: $0, clock: .venue)).title }
        #expect(titles[0] != titles[1])
    }

    /// Posted at once, so it takes none of the 64 pending the reminders
    /// share; filed under its event, so a second change replaces the first;
    /// and carrying what it moved from, for the sheet a tap opens.
    @Test func itComesAtOnceFiledUnderItsEventWithWhatItWas() throws {
        var moved = held
        moved.startsAt = Fixtures.date(2027, 5, 9, 18, 30)
        let request = try #require(ChangeAlert(from: ListingCopy(held), to: moved, clock: .venue)).request
        #expect(request.trigger == nil)
        #expect(request.identifier == ChangeAlert.identifier(for: "5"))
        #expect(request.identifier.hasPrefix(ChangeAlert.prefix))
        #expect(ChangeAlert.event(in: request.content.userInfo) == "5")
        #expect(ChangeAlert.before(in: request.content.userInfo) == ListingCopy(held))
        #expect(ChangeAlert.before(in: [:]) == nil)
    }

    // MARK: - Which reads say it

    func store(hearing moves: @escaping (EventMove) -> Void) -> EventStore {
        let store = EventStore(database: LibraryDatabase(at: .memory, syncing: false), libraryFile: nil,
                               calendar: nil, venues: nil, pageReads: nil, accountEvents: nil, readCopies: nil)
        store.onMoved = moves
        return store
    }

    /// The account's history, read by itself, finding a kept event on
    /// another day. Kept as its page read it: a listing row moves only such
    /// a copy, and over another row the copy held stands (``EventStore``'s
    /// `keep`).
    @Test func aHistoryReadFindingAKeptEventMovedSaysSo() throws {
        var heard: [EventMove] = []
        let store = store { heard.append($0) }
        let day = Fixtures.day(fromToday: 30)
        let kept = Fixtures.event(id: "1", venue: "日本武道館", date: day,
                                  startsAt: day.addingTimeInterval(18 * 60 * 60), isDetailed: true)
        store.toggleLibraryMembership(kept)

        store.adopt([Fixtures.event(id: "1", venue: "日本武道館", date: Fixtures.day(fromToday: 31))],
                    restoring: false)

        let move = try #require(heard.first)
        #expect(heard.count == 1)
        #expect(move.eventID == "1")
        #expect(move.found == ListingCopy(kept))
    }

    /// An event arriving with the read is no news, nor one read the same
    /// again, nor one gone by.
    @Test func anArrivalARereadOrAnEventGoneBySaysNothing() {
        var heard: [EventMove] = []
        let store = store { heard.append($0) }
        let same = Fixtures.event(id: "1", date: Fixtures.day(fromToday: 30))
        let past = Fixtures.event(id: "2", date: Fixtures.day(fromToday: -30))
        store.toggleLibraryMembership(same)
        store.toggleLibraryMembership(past)

        store.adopt([
            same,
            Fixtures.event(id: "2", date: Fixtures.day(fromToday: -29)),
            Fixtures.event(id: "3", date: Fixtures.day(fromToday: 40)),
        ], restoring: false)

        #expect(heard.isEmpty)
        #expect(store.isInLibrary(Fixtures.event(id: "3")))
    }

    /// An event the reader does not keep is not theirs to hear about.
    @Test func anEventNotKeptSaysNothing() {
        var heard: [EventMove] = []
        let store = store { heard.append($0) }
        let removed = Fixtures.event(id: "1", date: Fixtures.day(fromToday: 30))
        store.toggleLibraryMembership(removed)
        store.remove([removed])

        store.adopt([Fixtures.event(id: "1", date: Fixtures.day(fromToday: 31))], restoring: false)

        #expect(heard.isEmpty)
    }
}
