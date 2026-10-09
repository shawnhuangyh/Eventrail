import Foundation
import Testing
@testable import Eventrail

struct TicketStubTests {
    private let event = Fixtures.event(
        title: "Liella! 6th", venue: "大阪城ホール", date: Fixtures.date(2025, 6, 14),
        doorsOpen: Fixtures.date(2025, 6, 14, 14, 30), startsAt: Fixtures.date(2025, 6, 14, 15, 30))
    private let after = Fixtures.date(2025, 6, 20)
    private let before = Fixtures.date(2025, 6, 1)

    @Test func printsTheDayInTheHallsFigures() {
        let face = TicketStubFace(event: event, tracking: Tracking(seat: "A5ブロック 12番"), on: .venue, at: after)
        #expect(face.monthDay == "06.14")
        #expect(face.weekday == "SAT")
        #expect(face.year == "2025")
        #expect(face.hasTimes)
    }

    @Test func aDayAfterMidnightAtTheHallStaysTheHallsDay() {
        // 01:00 in Tokyo is the afternoon before in London, and the venue's
        // clock prints the hall's day whatever the reader's.
        let late = Fixtures.event(date: Fixtures.date(2025, 6, 14), startsAt: Fixtures.date(2025, 6, 14, 1))
        let face = TicketStubFace(event: late, tracking: Tracking(seat: "1"), on: .venue, at: after)
        #expect(face.monthDay == "06.14")
    }

    @Test func usedOnceTheDayIsOverWithATicket() {
        let won = LotteryEntry(round: "最速先行抽選", result: .won(nil))
        let face = TicketStubFace(event: event, tracking: Tracking(seat: "1", lotteries: [won]), on: .venue, at: after)
        #expect(face.stamp == .used)
    }

    @Test func noStampForAPastEventWithoutATicket() {
        let face = TicketStubFace(event: event, tracking: Tracking(seat: "1"), on: .venue, at: after)
        #expect(face.stamp == nil)
    }

    @Test func wonForALotteryWonAhead() {
        let won = LotteryEntry(round: "最速先行抽選", result: .won(nil))
        let face = TicketStubFace(event: event, tracking: Tracking(seat: "1", lotteries: [won]), on: .venue, at: before)
        #expect(face.stamp == .won)
    }

    @Test func aFirstComeSeatAheadIsNoWin() {
        let got = LotteryEntry(round: "一般発売", choices: [LotteryChoice(seatClass: "一般席")])
        let face = TicketStubFace(event: event, tracking: Tracking(seat: "1", lotteries: [got]), on: .venue, at: before)
        #expect(face.stamp == nil)
        #expect(face.seatClass == "一般席")
    }

    @Test func offeredOnlyWithATicket() {
        let won = LotteryEntry(round: "最速先行抽選", result: .won(nil))
        let got = LotteryEntry(round: "一般発売", choices: [LotteryChoice(seatClass: "一般席")])
        #expect(TicketStubFace.offered(for: Tracking(lotteries: [won])))
        #expect(TicketStubFace.offered(for: Tracking(lotteries: [got])))
        #expect(!TicketStubFace.offered(for: Tracking()))
        // A lottery pending or lost, or a seat written, is not a ticket.
        let pending = LotteryEntry(round: "最速先行抽選")
        let lost = LotteryEntry(round: "プレイガイド先行", result: .lost)
        #expect(!TicketStubFace.offered(for: Tracking(seat: "B-670", lotteries: [pending, lost])))
    }

    @Test func aSeatOfSpacesIsNoSeat() {
        #expect(TicketStubFace(event: event, tracking: Tracking(seat: "B-670"), on: .venue, at: after).hasSeat)
        #expect(!TicketStubFace(event: event, tracking: Tracking(seat: "  "), on: .venue, at: after).hasSeat)
        #expect(!TicketStubFace(event: event, tracking: Tracking(), on: .venue, at: after).hasSeat)
    }

    @Test func thePriceIsPrintedAsPaid() {
        let face = TicketStubFace(event: event, tracking: Tracking(seat: "1", cost: 9900), on: .venue, at: after)
        #expect(face.price == Money(amount: 9900, currency: Currencies.yen).formatted)
        #expect(TicketStubFace(event: event, tracking: Tracking(seat: "1"), on: .venue, at: after).price == nil)
    }

    @Test func theMaskIsAsLongAsTheSeatWouldPrint() {
        // Full-width one em each, a space under a third, the rest two thirds.
        let width = TicketStubFace.maskWidth(of: "A5ブロック 12番")
        #expect(abs(width - 7.78) < 0.001)
        #expect(TicketStubFace.maskWidth(of: "") == 0)
    }
}
