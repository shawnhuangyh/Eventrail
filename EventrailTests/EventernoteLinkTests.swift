import Foundation
import Testing
@testable import Eventrail

/// A link pasted into Search — see ``EventernoteLink``: which of the site's
/// pages it is, and what is searched for as words instead.
struct EventernoteLinkTests {
    @Test func readsTheThreeKindsOfPage() {
        #expect(EventernoteLink(in: "https://www.eventernote.com/events/478884") == .event("478884"))
        #expect(EventernoteLink(in: "https://www.eventernote.com/actors/TrySail/12566")
                == .performer(slug: "TrySail", id: 12566))
        #expect(EventernoteLink(in: "https://www.eventernote.com/places/949") == .venue(id: 949))
    }

    /// A page hanging off one of them is taken for it.
    @Test func aPageUnderOneIsThatOne() {
        #expect(EventernoteLink(in: "https://www.eventernote.com/events/478884/users") == .event("478884"))
        #expect(EventernoteLink(in: "https://www.eventernote.com/actors/TrySail/12566/events?page=2")
                == .performer(slug: "TrySail", id: 12566))
        #expect(EventernoteLink(in: "https://www.eventernote.com/places/949/events") == .venue(id: 949))
    }

    /// The slug stays escaped as the site escaped it.
    @Test func keepsTheSlugAsEscaped() {
        #expect(EventernoteLink(in: "https://www.eventernote.com/actors/%CE%BC%E2%80%99s/2809")
                == .performer(slug: "%CE%BC%E2%80%99s", id: 2809))
    }

    /// Typed bare, or shared with a title in front of it.
    @Test func findsTheAddressInWhatWasPasted() {
        #expect(EventernoteLink(in: "eventernote.com/events/1") == .event("1"))
        #expect(EventernoteLink(in: "WWW.EVENTERNOTE.COM/places/2") == .venue(id: 2))
        #expect(EventernoteLink(in: "TrySail Live 2027 https://www.eventernote.com/events/3 #TrySail")
                == .event("3"))
    }

    /// The site's other pages, and anything else, are searched for as words.
    @Test func anythingElseIsNoLink() {
        for text in ["TrySail", "eventernote", "https://example.com/events/1",
                     "https://www.eventernote.com/events/search?keyword=x",
                     "https://www.eventernote.com/actors/ranking",
                     "https://www.eventernote.com/actors/initial/%E3%81%82",
                     "https://www.eventernote.com/places/prefecture/13",
                     "https://www.eventernote.com/users/someone"] {
            #expect(EventernoteLink(in: text) == nil, "\(text)")
        }
    }
}
