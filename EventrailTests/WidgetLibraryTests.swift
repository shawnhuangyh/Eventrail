import Foundation
import Testing
@testable import Eventrail

/// What the widgets are left to draw, and the lottery results given from
/// them coming back into the library.
@MainActor
struct WidgetLibraryTests {
    func store() -> EventStore {
        EventStore(database: LibraryDatabase(at: .memory, syncing: false), libraryFile: nil,
                   calendar: nil, venues: nil, pageReads: nil)
    }

    /// A results day `offset` days from the reader's today.
    static func day(_ offset: Int) -> CalendarDay {
        CalendarDay(Calendar.current.date(byAdding: .day, value: offset, to: .now)!)
    }

    static let choice = LotteryChoice(seatClass: "S席", quantity: 2)

    /// An event three weeks off, kept, with one lottery round in it.
    func keep(_ entry: LotteryEntry, in store: EventStore) -> Event {
        let event = Fixtures.event(id: "ahead", date: Fixtures.day(fromToday: 21), isDetailed: true)
        store.toggleLibraryMembership(event)
        store.setTracking(Tracking(lotteries: [entry]), for: event)
        return event
    }

    func answer(_ entry: LotteryEntry, won: Bool, choice: UUID? = nil) -> WidgetAnswer {
        WidgetAnswer(eventID: "ahead", entryID: entry.id, won: won, choiceID: choice, given: .now)
    }

    @Test func aWinFromTheWidgetIsWrittenDownWithTheTicketsClass() {
        let store = store()
        let entry = LotteryEntry(round: "最速先行抽選", applications: 2, day: Self.day(-1), choices: [Self.choice])
        let event = keep(entry, in: store)
        WidgetLink.shared.give(answer(entry, won: true, choice: Self.choice.id), in: store)
        let record = store.tracking(for: event)
        #expect(record.lotteries[0].outcome == .won(Self.choice.id))
        #expect(record.hasTicket)
        #expect(record.seatClass == "S席")
    }

    /// The widget names no choice where the round applied with one: the win
    /// goes to that one, as the Lotteries list's swipe gives it.
    @Test func aWinNamingNoChoiceGoesToTheOnlyOne() {
        let store = store()
        let entry = LotteryEntry(round: "最速先行抽選", day: Self.day(0), choices: [Self.choice])
        let event = keep(entry, in: store)
        WidgetLink.shared.give(answer(entry, won: true), in: store)
        #expect(store.tracking(for: event).lotteries[0].outcome == .won(Self.choice.id))
    }

    @Test func aLossFromTheWidgetIsWrittenDown() {
        let store = store()
        let entry = LotteryEntry(round: "プレイガイド先行", day: Self.day(-3))
        let event = keep(entry, in: store)
        WidgetLink.shared.give(answer(entry, won: false), in: store)
        #expect(store.tracking(for: event).lotteries[0].outcome == .lost)
    }

    /// A result written since — on another device, or in the app — is the
    /// reader's later word, and the widget's answer is let go.
    @Test func aResultGivenSinceStands() {
        let store = store()
        let entry = LotteryEntry(round: "最速先行抽選", day: Self.day(-1), result: .lost)
        let event = keep(entry, in: store)
        WidgetLink.shared.give(answer(entry, won: true), in: store)
        #expect(store.tracking(for: event).lotteries[0].outcome == .lost)
    }

    /// A results day moved later since cannot have been drawn yet.
    @Test func aRoundWhoseDayIsStillAheadIsNotDrawn() {
        let store = store()
        let entry = LotteryEntry(round: "最速先行抽選", day: Self.day(4))
        let event = keep(entry, in: store)
        WidgetLink.shared.give(answer(entry, won: false), in: store)
        #expect(store.tracking(for: event).lotteries[0].isPending)
    }

    /// Which of several choices was won is the reader's to say, in the app.
    @Test func aWinAmongSeveralChoicesIsLeftForTheReader() {
        let store = store()
        let entry = LotteryEntry(round: "最速先行抽選", day: Self.day(-1),
                                 choices: [Self.choice, LotteryChoice(seatClass: "A席")])
        let event = keep(entry, in: store)
        WidgetLink.shared.give(answer(entry, won: true), in: store)
        #expect(store.tracking(for: event).lotteries[0].isPending)
    }

    /// The copy holds the next events with their seats, the rounds waiting,
    /// and every event gone to — and nothing gone without a ticket.
    @Test func theCopyHoldsWhatTheWidgetsDraw() {
        let store = store()
        let entry = LotteryEntry(round: "最速先行抽選", applications: 3, day: Self.day(2), choices: [Self.choice])
        let ahead = keep(entry, in: store)
        var won = Tracking(lotteries: [.ticketHeld])
        won.seat = "2階 C列 14番"
        won.note = "Arena seats!\nSang along to every encore."
        let went = Fixtures.event(id: "went", date: Fixtures.day(fromToday: -400), isDetailed: true)
        let missed = Fixtures.event(id: "missed", date: Fixtures.day(fromToday: -300), isDetailed: true)
        for event in [went, missed] { store.toggleLibraryMembership(event) }
        store.setTracking(won, for: went)

        let library = WidgetLibrary(store, display: .venue)
        #expect(library.upcoming.map(\.id) == [ahead.id])
        #expect(library.rounds.map(\.entryID) == [entry.id])
        #expect(library.rounds[0].applications == 3)
        #expect(library.rounds[0].onlyChoice == Self.choice.id)
        #expect(library.memories.map(\.id) == ["went"])
        #expect(library.memories[0].note == "Arena seats!")
    }

    /// An element this build cannot read leaves out that one, not the rest:
    /// the copy outlives the build that wrote it until the app next runs.
    @Test func anElementThatCannotBeReadIsLeftOut() throws {
        let store = store()
        let entry = LotteryEntry(round: "最速先行抽選", day: Self.day(2))
        _ = keep(entry, in: store)
        let library = WidgetLibrary(store, display: .venue)
        var copy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as! [String: Any]
        var events = copy["upcoming"] as! [[String: Any]]
        events[0]["day"] = "soon"
        copy["upcoming"] = events
        copy["memories"] = nil

        let read = try JSONDecoder().decode(WidgetLibrary.self, from: JSONSerialization.data(withJSONObject: copy))
        #expect(read.upcoming.isEmpty)
        #expect(read.rounds == library.rounds)
        #expect(read.memories.isEmpty)
    }

    /// A widget's link to a round is still the event's page, so a Live
    /// Activity's route opens it — with the round named beside it.
    @Test func aRoundLinkNamesItsRoundOnTheEventsPage() {
        let page = URL(string: "https://www.eventernote.com/events/489531")!
        let entry = UUID()
        let link = RoundLink.url(event: page, entry: entry)
        #expect(link.host() == "www.eventernote.com")
        #expect(link.pathComponents == page.pathComponents)
        #expect(RoundLink.entry(in: link) == entry)
        #expect(RoundLink.entry(in: page) == nil)
    }

    /// The reminder a widget's answer takes back is the one that was
    /// scheduled for the round.
    @Test func anAnswerNamesTheRoundsReminder() {
        let entry = LotteryEntry(round: "最速先行抽選", day: Self.day(3))
        let row = LotteryRow(event: Fixtures.event(id: "ahead", date: Fixtures.day(fromToday: 21)), entry: entry)
        #expect(answer(entry, won: true).roundID == LotteryReminder(row)?.identifier)
    }
}
