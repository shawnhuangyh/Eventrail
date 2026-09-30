import Foundation
import Testing
@testable import Eventrail

struct TrackingTests {
    // MARK: - Decoding older records

    @Test func decodesARecordMissingEveryNewerKey() throws {
        let json = #"{"ticket":"purchased","note":"最前列"}"#
        let tracking = try JSONDecoder().decode(Tracking.self, from: Data(json.utf8))
        #expect(tracking.ticket == .purchased)
        #expect(tracking.note == "最前列")
        #expect(tracking.seat == "")
        #expect(tracking.seatClass == "")
        #expect(tracking.cost == nil)
        #expect(tracking.lotteryEntries == nil)
        #expect(tracking.edits.isEmpty)
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
        #expect(tracking.lotteryEntries == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        var tracking = Tracking(ticket: .purchased, seat: "1階 L列 23番", seatClass: "A席", cost: 9900, note: "x")
        tracking.lotteryEntries = 3
        tracking.edits = [.note: Date(timeIntervalSince1970: 1_000)]
        let decoded = try JSONDecoder().decode(Tracking.self, from: JSONEncoder().encode(tracking))
        #expect(decoded == tracking)
    }

    // MARK: - The lottery count

    @Test func settingZeroLotteryEntriesEmptiesTheField() {
        var tracking = Tracking()
        tracking.lotteryEntries = 4
        tracking.lotteryEntries = 0
        #expect(tracking.lotteryEntries == nil)
        #expect(tracking.isEmpty)
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

    // MARK: - Reading typed numbers

    @Test(arguments: [
        ("¥1,234", 1234 as Int?),
        ("１２３４", 1234),
        ("0", 0),
        ("", nil),
        ("free", nil),
        ("1234567890123", 123_456_789),
    ])
    func parsesYen(typed: String, expected: Int?) {
        #expect(YenAmount().parseStrategy.parse(typed) == expected)
    }

    @Test(arguments: [
        ("12", 12 as Int?),
        ("０３", 3),
        ("0", nil),
        ("", nil),
        ("123456", 1234),
    ])
    func parsesEntryCounts(typed: String, expected: Int?) {
        #expect(EntryCount().parseStrategy.parse(typed) == expected)
    }

    @Test func formatsNothingAsAnEmptyField() {
        #expect(YenAmount().format(nil) == "")
        #expect(EntryCount().format(nil) == "")
    }

    @Test func yenFormatReadsBackAsTheSameAmount() {
        let style = YenAmount()
        #expect(style.parseStrategy.parse(style.format(9900)) == 9900)
    }
}
