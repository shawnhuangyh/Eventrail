import Foundation
import Testing
@testable import Eventrail

@MainActor
struct FeedTests {
    private nonisolated struct Row: Identifiable, Sendable {
        let id: Int
    }

    private struct Unreachable: LocalizedError {
        var errorDescription: String? { "Unreachable" }
    }

    /// A three-page listing of two rows a page, whose second page fails while
    /// `failing` says so.
    private nonisolated final class Listing: @unchecked Sendable {
        var failing = true

        func page(_ number: Int) throws -> EventernotePage<Row> {
            if number == 2, failing { throw Unreachable() }
            let rows = (1 ... 2).map { Row(id: (number - 1) * 2 + $0) }
            return EventernotePage(items: rows, total: 6, page: number, pageSize: 2)
        }
    }

    @Test func aFailedPageKeepsTheListingOpenForATryAgain() async {
        let listing = Listing()
        let feed = Feed<Row>()
        await feed.load { try listing.page($0) }
        await feed.loadMore()

        #expect(feed.items.map(\.id) == [1, 2])
        #expect(feed.hasMore)
        #expect(feed.moreFailure == "Unreachable")
        #expect(feed.failure == nil)

        listing.failing = false
        // A row scrolled back into view is not somebody asking again.
        await feed.loadMore()
        #expect(feed.items.count == 2)

        await feed.retryMore()
        #expect(feed.items.map(\.id) == [1, 2, 3, 4])
        #expect(feed.moreFailure == nil)
        #expect(feed.hasMore)
    }

    /// The reader scrolled to the end, then searched again: the page still on
    /// its way for the search before is let go when it lands, not added to
    /// the new search's rows.
    @Test func aPageLandingForTheListingBeforeIsLetGo() async {
        let (released, release) = AsyncStream<Void>.makeStream()
        let feed = Feed<Row>()
        await feed.load { page in
            if page == 2 { for await _ in released { break } }
            return EventernotePage(items: [Row(id: 100 + page)], total: 4, page: page, pageSize: 1)
        }
        let late = Task { await feed.loadMore() }
        while !feed.isLoadingMore { await Task.yield() }

        await feed.load { page in EventernotePage(items: [Row(id: 200 + page)], total: 4, page: page, pageSize: 1) }
        release.yield()
        release.finish()
        await late.value

        #expect(feed.items.map(\.id) == [201])
        #expect(feed.page == 1)
    }

    @Test func aNewLoadForgetsTheFailedPage() async {
        let listing = Listing()
        let feed = Feed<Row>()
        await feed.load { try listing.page($0) }
        await feed.loadMore()
        #expect(feed.moreFailure != nil)

        await feed.load { try listing.page($0) }
        #expect(feed.moreFailure == nil)
    }
}
