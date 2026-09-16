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

    private var page = 0
    private var hasMore = false
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

    /// Loads the page after the one on screen. Safe to call from a row that
    /// appears more than once.
    func loadMore() async {
        guard let source, hasMore, !isLoading, !isLoadingMore else { return }
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
            // Keep the pages already shown; the reader can scroll again to retry.
            hasMore = false
        }
    }

    func clear() {
        source = nil
        items = []
        total = 0
        page = 0
        hasMore = false
        failure = nil
    }

    /// True when `item` is close enough to the end of the loaded pages that the
    /// next one should start now.
    func isNearEnd(_ item: Item) -> Bool {
        hasMore && items.suffix(4).contains { $0.id == item.id }
    }
}
