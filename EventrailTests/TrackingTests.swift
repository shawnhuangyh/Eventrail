import Foundation
import Testing
@testable import Eventrail

struct TrackingTests {
    // MARK: - Decoding older records

    @Test func decodesARecordMissingEveryNewerKey() throws {
        let json = #"{"ticket":"purchased","note":"最前列"}"#
        let tracking = try JSONDecoder().decode(Tracking.self, from: Data(json.utf8))
        #expect(tracking.hasTicket)
        #expect(tracking.note == "最前列")
        #expect(tracking.seat == "")
        #expect(tracking.seatClass == "")
        #expect(tracking.cost == nil)
        #expect(tracking.currency == "")
        #expect(tracking.edits.isEmpty)
    }

    // MARK: - A ticket marked bought before entries

    /// Marked bought beside a lottery count, the ticket is the count won:
    /// applied that many times, and got one.
    @Test func aTicketMarkedBoughtIsTheCountItWasWonWith() throws {
        let json = #"{"ticket":"purchased","lotteryEntries":3}"#
        let tracking = try JSONDecoder().decode(Tracking.self, from: Data(json.utf8))
        #expect(tracking.ticket == .none)
        #expect(tracking.hasTicket)
        #expect(tracking.lotteries == [LotteryEntry(id: LotteryEntry.carriedOverID, applications: 3,
                                                    result: .won(nil))])
        #expect(tracking.lotteryApplications == 3)
    }

    /// Marked bought alone, it is an entry of its own, won, that adds nothing
    /// to the lottery figures — and the same entry every time it is read.
    @Test func aTicketMarkedBoughtAloneIsAWonEntryOfItsOwn() throws {
        let json = #"{"ticket":"purchased"}"#
        let tracking = try JSONDecoder().decode(Tracking.self, from: Data(json.utf8))
        #expect(tracking.ticket == .none)
        #expect(tracking.lotteries == [LotteryEntry(id: LotteryEntry.carriedOverTicketID, applications: 0,
                                                    result: .won(nil))])
        #expect(tracking.lotteryApplications == 0)
        #expect(try JSONDecoder().decode(Tracking.self, from: Data(json.utf8)) == tracking)
        // Read back as written now, it stays as it is.
        let again = try JSONDecoder().decode(Tracking.self, from: JSONEncoder().encode(tracking))
        #expect(again == tracking)
    }

    /// A ticket marked bought beside a lottery already won adds nothing: the
    /// win is the ticket.
    @Test func aTicketMarkedBoughtBesideAWinAddsNothing() {
        let won = LotteryEntry(round: "最速先行抽選", result: .won(nil))
        var tracking = Tracking(ticket: .purchased, lotteries: [won])
        tracking.foldLegacyTicket()
        #expect(tracking.ticket == .none)
        #expect(tracking.lotteries == [won])
    }

    /// The list now holds both answers, so it is dated by the newer of them,
    /// and as new as the record where either was.
    @Test func aFoldedTicketDatesTheList() {
        let older = Date(timeIntervalSince1970: 1_000), newer = Date(timeIntervalSince1970: 2_000)
        var both = Tracking(ticket: .purchased, edits: [.ticket: newer, .lotteries: older])
        both.foldLegacyTicket()
        #expect(both.edits[.lotteries] == newer)
        var one = Tracking(ticket: .purchased, edits: [.lotteries: older])
        one.foldLegacyTicket()
        #expect(one.edits[.lotteries] == nil)
    }

    /// Every cost written before a ticket had a currency was whole yen.
    @Test func aCostWrittenBeforeCurrenciesIsYen() throws {
        let json = #"{"ticket":"purchased","cost":9900}"#
        let tracking = try JSONDecoder().decode(Tracking.self, from: Data(json.utf8))
        #expect(tracking.cost == 9900)
        #expect(tracking.price == Money(amount: 9900, currency: "JPY"))
    }

    /// Cents survive the trip exactly — not as 49.990000000000002.
    @Test func aCostWithCentsRoundTripsExactly() throws {
        let tracking = Tracking(cost: Decimal(string: "49.99"), currency: "USD")
        let decoded = try JSONDecoder().decode(Tracking.self, from: JSONEncoder().encode(tracking))
        #expect(decoded.cost == Decimal(string: "49.99"))
        #expect(decoded.price == Money(amount: Decimal(string: "49.99")!, currency: "USD"))
    }

    @Test func decodesAnEmptyRecordAndIgnoresDroppedKeys() throws {
        let json = #"{"interest":"high","attendance":"attended"}"#
        let tracking = try JSONDecoder().decode(Tracking.self, from: Data(json.utf8))
        #expect(tracking == Tracking())
        #expect(tracking.isEmpty)
    }

    @Test func aStoredZeroLotteryCountReadsAsNothing() throws {
        let json = #"{"lotteryEntries":0}"#
        let tracking = try JSONDecoder().decode(Tracking.self, from: Data(json.utf8))
        #expect(tracking.lotteries.isEmpty)
        #expect(tracking.isEmpty)
    }

    /// A count from before entries reads back as one entry applied for that
    /// many times, the same one every time it is read.
    @Test func aLotteryCountReadsBackAsOneEntryAppliedForThatOften() throws {
        let json = #"{"lotteryEntries":3,"edits":{"lotteryEntries":1000}}"#
        let tracking = try JSONDecoder().decode(Tracking.self, from: Data(json.utf8))
        #expect(tracking.lotteries.count == 1)
        #expect(tracking.lotteries.first?.applications == 3)
        #expect(tracking.lotteries.allSatisfy { $0.result == .pending && $0.choices.isEmpty && $0.round.isEmpty })
        #expect(tracking.lotteryApplications == 3)
        #expect(tracking.edits[.lotteries] == Date(timeIntervalSinceReferenceDate: 1000))
        let again = try JSONDecoder().decode(Tracking.self, from: Data(json.utf8))
        #expect(again == tracking)
    }

    @Test func roundTripsThroughJSON() throws {
        var tracking = Tracking(seat: "1階 L列 23番", seatClass: "A席", cost: 9900, note: "x",
                                currency: "TWD")
        let won = LotteryChoice(seatClass: "S席", quantity: 2)
        tracking.lotteries = [
            LotteryEntry(round: "最速先行抽選", applications: 6, day: CalendarDay(year: 2026, month: 10, day: 12),
                         choices: [won, LotteryChoice(seatClass: "A席", quantity: 2)], result: .won(won.id)),
            LotteryEntry(round: "プレイガイド二次先行", result: .lost),
            LotteryEntry(round: "見切れ席", choices: [LotteryChoice(seatClass: "一般席")]),
            LotteryEntry(choices: [LotteryChoice()]),
        ]
        tracking.edits = [.note: Date(timeIntervalSince1970: 1_000)]
        let decoded = try JSONDecoder().decode(Tracking.self, from: JSONEncoder().encode(tracking))
        #expect(decoded == tracking)
    }

    // MARK: - Lottery entries

    @Test func anEntryAloneIsAnAnswer() {
        #expect(!Tracking(lotteries: [LotteryEntry()]).isEmpty)
    }

    /// The applications are added up over the lottery rounds alone: a
    /// first-come round is not applied for.
    @Test func applicationsAreCountedOverTheLotteryRounds() {
        let tracking = Tracking(lotteries: [
            LotteryEntry(round: "最速先行抽選", applications: 5),
            LotteryEntry(round: "プレイガイド先行"),
            LotteryEntry(round: "プレイガイド二次先行", applications: 2),
            LotteryEntry(round: "一般発売", applications: 3),
            LotteryEntry(round: "見切れ席"),
        ])
        #expect(tracking.lotteryApplications == 8)
        #expect(Tracking(lotteries: [LotteryEntry(round: "見切れ席")]).lotteryApplications == 0)
    }

    /// A count a later build or a hand-edited file holds out of bounds is
    /// brought back inside them rather than dropping the entry.
    @Test func applicationsOutOfBoundsAreBroughtBackIn() throws {
        func applications(_ count: Int) throws -> Int {
            try JSONDecoder().decode(LotteryEntry.self, from: Data(#"{"applications":\#(count)}"#.utf8)).applications
        }
        #expect(try applications(0) == 0)
        #expect(try applications(-3) == 0)
        #expect(try applications(123456) == LotteryEntry.mostApplications)
        #expect(try JSONDecoder().decode(LotteryEntry.self, from: Data("{}".utf8)).applications == 1)
    }

    /// The two last rounds of a sale are first come, first served; the three
    /// lotteries, an entry with no round and a round a later build names are
    /// not.
    @Test func firstComeRoundsAreTheOnesSoldOverTheCounter() {
        #expect(LotteryRound.allCases.filter(\.isFirstCome) == [.generalSale, .restrictedView])
        #expect(LotteryEntry(round: "一般発売").isFirstCome)
        #expect(LotteryEntry(round: "見切れ席").isFirstCome)
        #expect(!LotteryEntry(round: "プレイガイド二次先行").isFirstCome)
        #expect(!LotteryEntry().isFirstCome)
        #expect(!LotteryEntry(round: "トリプル先行").isFirstCome)
    }

    /// A first-come round is written down only for a seat that was got, so
    /// it reads as got with its seat whatever result it holds — and moved back
    /// to a lottery, it gives back the result the lottery had.
    @Test func aFirstComeRoundIsGotWithItsSeat() {
        let seat = LotteryChoice(seatClass: "一般席")
        var entry = LotteryEntry(round: "プレイガイド先行", choices: [seat], result: .lost)
        #expect(entry.outcome == .lost)
        entry.round = "見切れ席"
        #expect(entry.outcome == .won(seat.id))
        #expect(entry.wonChoice == seat)
        #expect(!entry.isPending)
        #expect(Tracking(lotteries: [entry]).lotteryStanding == .won)
        #expect(Tracking(lotteries: [LotteryEntry(round: "一般発売", day: CalendarDay(year: 2026, month: 10, day: 9))])
            .nextResults() == nil)
        entry.round = "プレイガイド先行"
        #expect(entry.outcome == .lost)
    }

    /// A key a later build adds, or a result it names, costs nothing here.
    @Test func decodesAnEntryWithKeysItDoesNotKnow() throws {
        let json = #"{"id":"5A8F6E2C-3C1B-4C7E-9A51-0E2D4B8C9F10","result":"waitlisted","seats":"x"}"#
        let entry = try JSONDecoder().decode(LotteryEntry.self, from: Data(json.utf8))
        #expect(entry.result == .pending)
        #expect(entry.choices.isEmpty)
    }

    @Test func aWinWithNoChoiceRoundTrips() throws {
        let entry = LotteryEntry(result: .won(nil))
        let decoded = try JSONDecoder().decode(LotteryEntry.self, from: JSONEncoder().encode(entry))
        #expect(decoded == entry)
    }

    @Test func removingTheChoiceWonWithTakesTheWinBack() {
        let first = LotteryChoice(seatClass: "S席"), second = LotteryChoice(seatClass: "A席")
        var entry = LotteryEntry(choices: [first, second], result: .won(second.id))
        entry.removeChoice(first.id)
        #expect(entry.result == .won(second.id))
        entry.removeChoice(second.id)
        #expect(entry.result == .pending)
    }

    @Test func standsWonThenPendingThenLost() {
        let lost = LotteryEntry(result: .lost), pending = LotteryEntry(), won = LotteryEntry(result: .won(nil))
        #expect(Tracking().lotteryStanding == nil)
        #expect(Tracking(lotteries: [lost]).lotteryStanding == .lost)
        #expect(Tracking(lotteries: [lost, pending]).lotteryStanding == .pending)
        #expect(Tracking(lotteries: [lost, pending, won]).lotteryStanding == .won)
    }

    /// The ticket's class is read off the rounds that went well — the
    /// highest where several did — and falls back to one written by hand.
    @Test func theTicketsClassIsTheHighestWon() {
        let s = LotteryChoice(seatClass: "S席"), a = LotteryChoice(seatClass: "A席"), any = LotteryChoice()
        var record = Tracking(seatClass: "一般席", lotteries: [
            LotteryEntry(choices: [a], result: .won(a.id)),
            LotteryEntry(round: "一般発売", choices: [s]),
            LotteryEntry(choices: [s], result: .lost),
        ])
        #expect(record.roundsWon == 2)
        #expect(record.classOfWins == "S席")
        #expect(record.ticketClass == "S席")

        record.lotteries.removeAll { $0.round == "一般発売" }
        #expect(record.ticketClass == "A席")

        let classless = Tracking(seatClass: "一般席", lotteries: [LotteryEntry(choices: [any], result: .won(any.id))])
        #expect(classless.classOfWins == nil)
        #expect(classless.ticketClass == "一般席")
    }

    /// Saved, the class is written from the rounds — and goes with the last
    /// round that named it, but a class written by hand stays.
    @Test func savingSettlesTheClassFromTheRounds() {
        let a = LotteryChoice(seatClass: "A席")
        let pending = Tracking(lotteries: [LotteryEntry(choices: [a])])
        var won = pending
        won.lotteries[0].result = .won(a.id)
        won.settleSeatClass(since: pending)
        #expect(won.seatClass == "A席")
        #expect(won.seat.isEmpty && won.cost == nil)

        var lost = won
        lost.lotteries[0].result = .lost
        lost.settleSeatClass(since: won)
        #expect(lost.seatClass == "")

        var byHand = Tracking(seatClass: "S席")
        let before = byHand
        byHand.note = "x"
        byHand.settleSeatClass(since: before)
        #expect(byHand.seatClass == "S席")
    }

    /// The ticket is what the entries say: a lottery won or a first-come
    /// round got, and nothing waiting or lost.
    @Test func aTicketIsALotteryWonOrASeatGot() {
        let choice = LotteryChoice(seatClass: "A席", quantity: 2)
        #expect(Tracking(lotteries: [LotteryEntry(choices: [choice], result: .won(choice.id))]).hasTicket)
        #expect(Tracking(lotteries: [LotteryEntry(round: "一般発売", choices: [choice])]).hasTicket)
        #expect(!Tracking(lotteries: [LotteryEntry(), LotteryEntry(result: .lost)]).hasTicket)
        #expect(!Tracking(seat: "A12", cost: 9900).hasTicket)
    }

    /// Recording a ticket held adds one entry with no round and no
    /// applications — attended, and no lottery figure moved — and nothing
    /// where a ticket is already there.
    @Test func recordingATicketAddsOneThatMovesNoLotteryFigure() {
        var tracking = Tracking(lotteries: [LotteryEntry(applications: 3, result: .lost)])
        tracking.recordTicket()
        #expect(tracking.hasTicket)
        #expect(tracking.lotteries.count == 2)
        #expect(tracking.lotteryApplications == 3)
        #expect(tracking.lotteryRounds.count == 1)

        let held = tracking
        tracking.recordTicket()
        #expect(tracking == held)

        // The same entry taken to a loss since is won again, not added twice.
        var lost = Tracking(lotteries: [LotteryEntry.ticketHeld])
        lost.lotteries[0].result = .lost
        lost.recordTicket()
        #expect(lost.lotteries == [LotteryEntry.ticketHeld])
    }

    @Test func theNextResultsAreTheSoonestStillToCome() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 12))!
        func day(_ d: Int) -> CalendarDay { CalendarDay(year: 2026, month: 10, day: d) }
        let past = LotteryEntry(day: day(1)), soon = LotteryEntry(day: day(9))
        let later = LotteryEntry(day: day(20)), decided = LotteryEntry(day: day(5), result: .lost)
        #expect(Tracking(lotteries: [later, past, soon, decided]).nextResults(from: now) == soon)
        #expect(Tracking(lotteries: [past, decided]).nextResults(from: now) == past)
        #expect(Tracking(lotteries: [LotteryEntry()]).nextResults(from: now) == nil)
    }

    @Test func aDayIsWrittenAsItReads() throws {
        let day = CalendarDay(year: 2026, month: 3, day: 7)
        #expect(String(decoding: try JSONEncoder().encode(day), as: UTF8.self) == #""2026-03-07""#)
        #expect(try JSONDecoder().decode(CalendarDay.self, from: Data(#""2026-03-07""#.utf8)) == day)
        #expect(CalendarDay(text: "2026-13-01") == nil)
    }

    /// A round is written as the site prints it and read in the reader's
    /// language; one a later build wrote reads as itself.
    @Test func aRoundIsReadInTheReadersLanguage() {
        for round in LotteryRound.allCases {
            #expect(LotteryRound.label(of: round.rawValue) == round.label)
        }
        #expect(LotteryRound.label(of: "トリプル先行") == "トリプル先行")
        #expect(Set(LotteryRound.allCases.map(\.label)).count == LotteryRound.allCases.count)
    }

    /// The column a list is kept in is the same text for the same list, so
    /// an unchanged list is not a change to send.
    @Test func aListIsAlwaysTheSameColumnText() {
        let choice = LotteryChoice(seatClass: "S席", quantity: 2)
        let entries = [LotteryEntry(round: "最速先行抽選", applications: 2, day: CalendarDay(year: 2026, month: 10, day: 12),
                                    choices: [choice], result: .won(choice.id))]
        let text = LotteryEntry.columnText(of: entries)
        #expect(LotteryEntry.columnText(of: entries) == text)
        #expect(LotteryEntry.entries(inColumn: text) == entries)
        #expect(LotteryEntry.columnText(of: []) == "")
        #expect(LotteryEntry.entries(inColumn: "") == nil)
    }

    @Test func aFreeTicketIsAnAnswer() {
        #expect(!Tracking(cost: 0).isEmpty)
    }

    @Test func aSeatClassAloneIsAnAnswer() {
        #expect(!Tracking(seatClass: "一般席").isEmpty)
    }

    // MARK: - Settling a record one answer at a time

    let t0 = Date(timeIntervalSince1970: 1_000_000)
    var t1: Date { t0.addingTimeInterval(60) }
    var t2: Date { t0.addingTimeInterval(120) }

    @Test func twoDevicesEditingDifferentAnswersKeepBoth() {
        let base = Stamped(Tracking(cost: 1000, note: "a"), at: t0)
        let phone = base.edited(to: Tracking(cost: 1000, note: "b"), at: t1)
        let iPad = base.edited(to: Tracking(cost: 2000, note: "a"), at: t2)

        let merged = phone.merging(iPad)
        #expect(merged.value.note == "b")
        #expect(merged.value.cost == 2000)
        #expect(merged.modified == t2)
        // And the merge is the same from either side.
        #expect(iPad.merging(phone).value.note == "b")
        #expect(iPad.merging(phone).value.cost == 2000)
    }

    /// An amount and its currency are one answer: a merge never takes the
    /// amount from one device and the currency from the other.
    @Test func aCostAndItsCurrencyAreSettledTogether() {
        let base = Stamped(Tracking(cost: 9900, currency: "JPY"), at: t0)
        let phone = base.edited(to: Tracking(cost: 9900, currency: "TWD"), at: t1)
        let iPad = base.edited(to: Tracking(cost: 12000, currency: "JPY"), at: t2)
        #expect(phone.merging(iPad).value.price == Money(amount: 12000, currency: "JPY"))
        #expect(iPad.merging(phone).value.price == Money(amount: 12000, currency: "JPY"))
    }

    @Test func twoDevicesEditingTheSameAnswerTakeTheLaterWrite() {
        let base = Stamped(Tracking(note: "a"), at: t0)
        let phone = base.edited(to: Tracking(note: "phone"), at: t1)
        let iPad = base.edited(to: Tracking(note: "iPad"), at: t2)
        #expect(phone.merging(iPad).value.note == "iPad")
        #expect(iPad.merging(phone).value.note == "iPad")
    }

    @Test func editedKeepsTheAgeOfUntouchedAnswers() {
        let base = Stamped(Tracking(cost: 1000, note: "a"), at: t0)
        let edited = base.edited(to: Tracking(cost: 1000, note: "b"), at: t1)
        #expect(edited.modified == t1)
        #expect(edited.value.edits[.cost] == t0)
        // Changed answers are as new as the record, so they carry no date.
        #expect(edited.value.edits[.note] == nil)
    }

    @Test func tiesKeepThisDevicesAnswer() {
        let mine = Stamped(Tracking(note: "mine"), at: t0)
        let theirs = Stamped(Tracking(note: "theirs"), at: t0)
        #expect(mine.merging(theirs).value.note == "mine")
    }

    @Test func restampedClearsTheEditDates() {
        var old = Tracking(note: "x")
        old.edits = [.cost: t0]
        let raised = Stamped(old, at: t1).restamped(at: t2)
        #expect(raised.modified == t2)
        #expect(raised.value.edits.isEmpty)
        #expect(raised.value.note == "x")
    }

    // MARK: - Saving a copy

    /// The ticket sheet writes back only what was changed on it, so a note
    /// synced in while it was open is not handed back its old copy.
    @Test func aSavedCopyWritesOnlyWhatItChanged() {
        let opened = Tracking(seat: "A1", note: "a")
        var copy = opened
        copy.seat = "B2"
        let now = Tracking(seat: "A1", note: "from the iPad")
        let saved = now.applying(changesFrom: opened, to: copy)
        #expect(saved.seat == "B2")
        #expect(saved.note == "from the iPad")
    }

    @Test func aSavedCopyTakesACostWithItsCurrency() {
        let opened = Tracking(cost: 9900, currency: "JPY")
        var copy = opened
        copy.currency = "TWD"
        let saved = opened.applying(changesFrom: opened, to: copy)
        #expect(saved.price == Money(amount: 9900, currency: "TWD"))
    }

    @Test func anUnchangedCopyChangesNothing() {
        let opened = Tracking(seat: "A1")
        let now = Tracking(seat: "C3", note: "b")
        #expect(now.applying(changesFrom: opened, to: opened) == now)
    }

    // MARK: - Reading typed numbers

    @Test(arguments: [
        ("¥1,234", 1234 as Int?),
        ("１２３４", 1234),
        ("0", 0),
        ("", nil),
        ("free", nil),
        ("1234567890123", 123_456_789),
        // Yen has no decimals, so a point typed is not one.
        ("12.5", 125),
    ])
    func parsesYen(typed: String, expected: Int?) {
        let style = MoneyAmount(fractionDigits: 0, locale: Locale(identifier: "en_US"))
        #expect(style.parseStrategy.parse(typed) == expected.map { Decimal($0) })
    }

    @Test(arguments: [
        ("49.99", "49.99" as String?),
        ("1,234.5", "1234.5"),
        ("０．５", "0.5"),
        (".75", "0.75"),
        ("12.345", "12.34"),
        ("", nil),
    ])
    func parsesCents(typed: String, expected: String?) {
        let style = MoneyAmount(fractionDigits: 2, locale: Locale(identifier: "en_US"))
        #expect(style.parseStrategy.parse(typed) == expected.flatMap { Decimal(string: $0) })
    }

    /// A locale whose decimal point is a comma reads its own point.
    @Test func parsesTheLocalesOwnDecimalPoint() {
        let style = MoneyAmount(fractionDigits: 2, locale: Locale(identifier: "de_DE"))
        #expect(style.parseStrategy.parse("1.234,50") == Decimal(string: "1234.5"))
    }

    @Test func formatsNothingAsAnEmptyField() {
        #expect(MoneyAmount(fractionDigits: 0).format(nil) == "")
    }

    @Test func moneyFormatReadsBackAsTheSameAmount() {
        let yen = MoneyAmount(fractionDigits: 0)
        #expect(yen.parseStrategy.parse(yen.format(9900)) == 9900)
        let dollars = MoneyAmount(fractionDigits: 2)
        let amount = Decimal(string: "1234.56")!
        #expect(dollars.parseStrategy.parse(dollars.format(amount)) == amount)
    }
}
