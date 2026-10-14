import Foundation
import Testing
@testable import Eventrail

struct EventernoteClientTests {
    /// A `+` left as it is in a query is read by the site as a space, so a
    /// name carrying one — +α/あるふぁきゅん。 — was searched for as another.
    @Test func aPlusInAQueryIsSentAsAPlus() throws {
        let url = try #require(EventernoteClient.url(at: "/actors/search", query: ["keyword": "+α/あるふぁきゅん。 A&B"]))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery)
        #expect(query.hasPrefix("keyword=%2B"))
        #expect(!query.contains("+"))
        #expect(query.contains("A%26B"))
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
            == "+α/あるふぁきゅん。 A&B")
    }
}
