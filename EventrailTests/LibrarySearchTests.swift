import Foundation
import Testing
@testable import Eventrail

/// My Events' search — see ``LibrarySearch``: what a typed word finds in the
/// reader's own events.
struct LibrarySearchTests {
    let show = Fixtures.event(title: "TrySail Live 2027 “Sail on”", venue: "日本武道館",
                              performers: ["TrySail", "麻倉もも"])

    @Test func everyWordHasToTurnUpSomewhere() {
        #expect(LibrarySearch("trysail 武道館").matches(show, note: ""))
        #expect(LibrarySearch("麻倉").matches(show, note: ""))
        #expect(!LibrarySearch("TrySail 横浜").matches(show, note: ""))
    }

    @Test func theReadersNoteIsSearchedToo() {
        #expect(LibrarySearch("アリーナ席").matches(show, note: "アリーナ席、最前"))
        #expect(!LibrarySearch("アリーナ席").matches(show, note: ""))
    }

    /// Full- and half-width alike, either case, hiragana as katakana — but a
    /// voiced mark is not dropped.
    @Test func readsTheWayTheSiteIsTyped() {
        let kana = Fixtures.event(title: "トライセイル ファンミーティング")
        #expect(LibrarySearch("ＴＲＹＳＡＩＬ").matches(show, note: ""))
        #expect(LibrarySearch("とらいせいる").matches(kana, note: ""))
        #expect(LibrarySearch("ﾄﾗｲｾｲﾙ").matches(kana, note: ""))
        #expect(LibrarySearch("ふぁんみーてぃんぐ").matches(kana, note: ""))
        #expect(!LibrarySearch("ぜい").matches(kana, note: ""))
    }

    /// No word reaches across from one field into the next.
    @Test func aWordDoesNotStraddleTwoFields() {
        let event = Fixtures.event(title: "Day", venue: "Light Hall")
        #expect(!LibrarySearch("daylight").matches(event, note: ""))
    }

    @Test func nothingTypedIsEverything() {
        #expect(LibrarySearch("   ").isEmpty)
        #expect(LibrarySearch("").matches(show, note: ""))
    }
}
