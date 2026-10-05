import Foundation
import Testing
@testable import Eventrail

struct CurrenciesTests {
    /// Cents where a price has them, and no row of zeroes where it has none.
    @Test func printsCentsOnlyWhereThereAreAny() {
        #expect(Currencies.format(Decimal(string: "49.99")!, in: "USD").contains("49.99"))
        #expect(!Currencies.format(3800, in: "TWD").contains("00.00"))
        #expect(Currencies.format(3800, in: "TWD").contains("3,800"))
        #expect(!Currencies.format(whole: 461.87, in: "CNY").contains(".87"))
    }

    /// The symbol and the figures come apart for the headline, and put back
    /// together they are the figure the rest of the card prints.
    @Test func splitsTheSymbolFromTheFigures() {
        let parts = Currencies.parts(whole: 124_800, in: "JPY")
        #expect(parts.figures.contains("124"))
        #expect(!parts.figures.contains("¥"))
        #expect(!(parts.before + parts.after).isEmpty)
    }

    @Test func readsTheHallsCurrencyOffItsAddress() {
        #expect(Currencies.atVenue(of: Fixtures.event(venueAddress: "東京都千代田区北の丸公園2-3")) == "JPY")
        #expect(Currencies.atVenue(of: Fixtures.event(venueAddress: "台北市中正區仁愛路一段17號")) == "TWD")
        #expect(Currencies.atVenue(of: Fixtures.event(venueAddress: "서울특별시 송파구 올림픽로 424")) == "KRW")
        #expect(Currencies.atVenue(of: Fixtures.event(venueAddress: "上海市浦东新区世博大道1200号")) == "CNY")
        #expect(Currencies.atVenue(of: Fixtures.event(venue: "!_東京都内某所")) == nil)
    }

    /// A code the list does not offer is still offered where a record holds it.
    @Test func keepsACodeTheListDoesNotHold() {
        #expect(Currencies.options(including: ["NZD", "JPY", ""]).last == "NZD")
        #expect(Currencies.options(including: ["JPY"]) == Currencies.offered)
    }
}
