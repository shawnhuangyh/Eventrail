import Foundation

/// A paged Eventernote listing, loaded a page at a time as the reader scrolls.
///
/// The listing it reads is swappable, so one feed follows a search term as the
/// reader retypes it instead of a new one being built per query.
@Observable
final class Feed<Item: Identifiable & Sendable> {
    private(set) var items: [Item] = []
    /// How many rows the site says match in total, across every page.
    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    /// Why the last load stopped, in words the reader can act on.
    private(set) var failure: String?
    /// Why the page after the ones on screen did not arrive. The pages already
    /// read stay, and so does ``hasMore``: the listing is not finished, it is
    /// waiting on a Try Again — see ``retryMore()``.
    private(set) var moreFailure: String?

    /// How many pages have been read — what a cached copy records, so a
    /// restored listing pages on from where the read it came from stopped.
    private(set) var page = 0
    /// Whether the site says there are pages after the ones already read.
    /// Read by a screen that has to keep paging until it has the whole of
    /// something, rather than only until the reader scrolls.
    private(set) var hasMore = false
    // The listing itself is not something a view observes, only its results.
    @ObservationIgnored private var source: Source?

    typealias Source = @Sendable (Int) async throws -> EventernotePage<Item>

    /// True once a load has finished and turned up nothing.
    var isEmptyResult: Bool { !isLoading && failure == nil && items.isEmpty && page > 0 }

    /// Points the feed at a listing and loads its first page, replacing whatever
    /// was on screen.
    func load(from source: @escaping Source) async {
        self.source = source
        page = 0
        hasMore = false
        failure = nil
        moreFailure = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await source(1)
            items = result.items
            total = result.total
            hasMore = result.hasMore
            page = 1
        } catch is CancellationError {
            // A retyped query supersedes this one; the newer load owns the state.
        } catch {
            guard !Task.isCancelled else { return }
            items = []
            total = 0
            page = 1
            failure = error.localizedDescription
        }
    }

    /// Puts a listing read earlier back on screen, pointed at the listing it
    /// came from so scrolling pages on from where that read stopped.
    ///
    /// What ``ListingCache`` hands a performer's or a hall's page as it opens:
    /// the copy is shown at once, whether or not it is then read again.
    func restore(_ items: [Item], total: Int, pagesRead: Int, hasMore: Bool,
                 from source: @escaping Source) {
        self.source = source
        self.items = items
        self.total = total
        page = pagesRead
        self.hasMore = hasMore
        failure = nil
        moreFailure = nil
    }

    /// Loads the page after the one on screen. Safe to call from a row that
    /// appears more than once.
    ///
    /// Does nothing once a page has failed, until the reader asks again: a row
    /// scrolled back into view is not somebody asking, and a site refusing
    /// the app would only be asked again for nothing.
    func loadMore() async {
        guard let source, hasMore, moreFailure == nil, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await source(page + 1)
            let known = Set(items.map(\.id))
            items += result.items.filter { !known.contains($0.id) }
            total = result.total
            hasMore = result.hasMore
            page += 1
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            // Keep the pages already shown, and keep the listing open: a
            // failed page is not the last one.
            moreFailure = error.localizedDescription
        }
    }

    /// The reader's Try Again on a page that failed.
    func retryMore() async {
        moreFailure = nil
        await loadMore()
    }

    func clear() {
        source = nil
        items = []
        total = 0
        page = 0
        hasMore = false
        failure = nil
        moreFailure = nil
    }

    /// True when `item` is close enough to the end of the loaded pages that the
    /// next one should start now.
    func isNearEnd(_ item: Item) -> Bool {
        hasMore && items.suffix(4).contains { $0.id == item.id }
    }
}
