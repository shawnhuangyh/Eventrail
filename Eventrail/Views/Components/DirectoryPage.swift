import SwiftUI

/// One page of the site's directories — of performers, of halls — read the
/// way a performer's or a hall's own page is (``ListingCache``): shown at once
/// from what this device last read, read again by itself only once that is
/// ``ListingCache/freshness`` old, and always by Refresh in the ⋯ menu. A read
/// that fails keeps what was shown.
@MainActor @Observable
final class DirectoryPage {
    let key: String
    @ObservationIgnored private let read: @Sendable () async throws -> CachedDirectory

    private(set) var content: CachedDirectory?
    /// Why the first read failed, with nothing on screen to fall back on.
    private(set) var failure: String?
    /// Why the last read did not replace what is on screen.
    private(set) var refreshFailure: String?
    private(set) var isReading = false
    @ObservationIgnored private var running: Task<RefreshNotice, Never>?

    init(key: String, read: @escaping @Sendable () async throws -> CachedDirectory) {
        self.key = key
        self.read = read
    }

    /// Shows the kept copy and reads again where there is none or it has gone
    /// stale — the app's own doing, so the notice it answers is said only
    /// where it failed.
    func open() async -> RefreshNotice? {
        if content == nil { content = ListingCache.shared.directory(for: key) }
        if content?.isFresh == true { return nil }
        return await refresh()
    }

    /// Reads the page again, whatever is held. Asked while a read is going,
    /// it waits for that one. A task of its own, so a screen left mid-read
    /// does not cancel it.
    func refresh() async -> RefreshNotice {
        if let running { return await running.value }
        let task = Task { await reading() }
        running = task
        defer { running = nil }
        return await task.value
    }

    func retry() async {
        failure = nil
        _ = await refresh()
    }

    private func reading() async -> RefreshNotice {
        isReading = true
        defer { isReading = false }
        let started = Date.now
        do {
            var page = try await read()
            page.readAt = started
            ListingCache.shared.store(page, for: key)
            content = page
            failure = nil
            refreshFailure = nil
            return .updated
        } catch {
            let reason = error.localizedDescription
            if content == nil { failure = reason } else { refreshFailure = reason }
            return .failed(reason)
        }
    }
}

/// What a directory page shows while it reads, when it could not, and once
/// it has: the rows the screen draws, with why the last read did not land
/// under them.
struct DirectoryContent<Rows: View>: View {
    let page: DirectoryPage
    @ViewBuilder let rows: (CachedDirectory) -> Rows

    var body: some View {
        if let content = page.content {
            rows(content)
            if let refreshFailure = page.refreshFailure {
                RefreshFailureNote(message: refreshFailure)
            }
        } else if let failure = page.failure {
            SearchFailure(message: failure) { await page.retry() }
        } else {
            SearchProgress()
        }
    }
}
