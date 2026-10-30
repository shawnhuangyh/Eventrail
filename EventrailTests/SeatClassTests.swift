import Foundation
import Testing
@testable import Eventrail

/// A class the reader types for a lottery choice — see ``SeatClass/typed(_:)``
/// — and how it is offered again and badged.
@MainActor
struct SeatClassTests {
    @Test func aTypedClassIsKeptAsTypedTrimmedAndMadePlain() {
        #expect(SeatClass.typed("  注釈付き指定席 ") == "注釈付き指定席")
        #expect(SeatClass.typed("ＳＳ席") == "SS席")
        #expect(SeatClass.typed("   ") == "")
    }

    /// Typed as one of the chips' own, by either of its names, it is that one.
    @Test func aClassTheChipsOfferIsKeptAsTheChip() {
        #expect(SeatClass.typed("S席") == SeatClass.s.rawValue)
        #expect(SeatClass.typed(SeatClass.general.name.uppercased()) == SeatClass.general.rawValue)
    }

    /// Nothing is read into a class the chips do not offer.
    @Test func aNearClassIsNotFoldedIn() {
        #expect(SeatClass.typed("S席 (注釈付き)") == "S席 (注釈付き)")
        #expect(SeatClass.typed("一般立見") == "一般立見")
    }

    @Test func aLongClassIsCut() {
        #expect(SeatClass.typed(String(repeating: "席", count: 40)).count == SeatClass.longestTyped)
    }

    @Test func aTypedClassIsBadgedByItsOpeningLettersOrItsFirstCharacter() {
        #expect(SeatClass.badgeText(of: "SS席") == "SS")
        #expect(SeatClass.badgeText(of: "vip") == "VIP")
        #expect(SeatClass.badgeText(of: "Premium") == "PRE")
        #expect(SeatClass.badgeText(of: "注釈付き指定席") == "注")
        #expect(SeatClass.badgeText(of: "") == nil)
    }

    /// The classes typed before, most used first, the chips' own left out.
    @Test func theClassesTypedBeforeAreOfferedMostUsedFirst() {
        let store = EventStore(database: LibraryDatabase(at: .memory, syncing: false), libraryFile: nil,
                               calendar: nil, venues: nil, pageReads: nil, accountEvents: nil)
        func keep(_ id: String, choices: [String], ticketClass: String = "") {
            let event = Fixtures.event(id: id)
            store.toggleLibraryMembership(event)
            var tracking = Tracking()
            tracking.lotteries = [LotteryEntry(round: LotteryRound.allCases[0].rawValue,
                                               choices: choices.map { LotteryChoice(seatClass: $0) })]
            tracking.seatClass = ticketClass
            store.setTracking(tracking, for: event)
        }
        keep("1", choices: ["SS席", "A席"])
        keep("2", choices: ["SS席"], ticketClass: "立見")
        keep("3", choices: ["VIP", "SS席"])

        #expect(store.typedSeatClasses() == ["SS席", "VIP", "立見"])
    }
}
