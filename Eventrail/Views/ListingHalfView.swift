import SwiftUI

/// Who or what a listing of events belongs to.
///
/// Eventernote publishes one listing per performer and one per hall, in the
/// same block and in the same order, and this app reads both the same way. The
/// difference is only in the words over them: a hall does not appear anywhere,
/// and a performer is not a place where events are held.
nonisolated enum ListingSubject: Hashable {
    case performer(String)
    case venue(String)

    /// The imported name, shown in the language Eventernote published it in.
    var name: String {
        switch self {
        case .performer(let name), .venue(let name): name
        }
    }
}

/// One half of a listing in full — every upcoming date, or everything already
/// behind it.
///
/// ``PerformerView`` and ``VenueView`` each show the first few of both halves
/// and send the rest here, for the reason ``FavoriteEventsView`` gives: a card
/// that grows without limit stops being a summary of the listing and becomes
/// the listing, and on a performer with years behind them — or a hall with
/// years behind it — it buries everything under it.
///
/// The feed is handed over rather than rebuilt, so opening this screen costs no
/// request — and the pages read on from here are already in the sections behind
/// it when the reader goes back.
struct ListingHalfView: View {
    /// Which side of today this screen lists. One listing to Eventernote, two
    /// different questions to the reader.
    enum Half {
        case upcoming, past

        /// Titled for whose listing it is: the same rows are a performer's
        /// appearances and a hall's bookings.
        func title(of subject: ListingSubject) -> LocalizedStringKey {
            switch (self, subject) {
            case (.upcoming, _): "Upcoming"
            case (.past, .performer): "Past appearances"
            case (.past, .venue): "Past events"
            }
        }

        /// What stands where the rows would, when this half has none.
        ///
        /// Said in two places — under the section on a subject's page and on
        /// this screen behind its See All — so it is named here rather than
        /// written out at both.
        var emptyNote: LocalizedStringKey {
            switch self {
            case .upcoming: "No dates published yet."
            case .past: "Nothing published before today."
            }
        }

        /// The listing arrives newest first and in one piece, so each half is a
        /// filter over it — in the order that half is read in.
        ///
        /// Which is the same question the library asks of itself, so it is the
        /// same answer: ``LibraryFilter/rows(of:)``.
        var filter: LibraryFilter {
            switch self {
            case .upcoming: .upcoming
            case .past: .past
            }
        }

        func rows(of events: [Event]) -> [Event] {
            filter.rows(of: events)
        }
    }

    @Environment(EventStore.self) private var store

    /// Shown as the subtitle, because the title is the half rather than the
    /// performer or the hall, and there is nothing else on the screen to say
    /// whose dates these are.
    let subject: ListingSubject
    let half: Half
    let feed: Feed<Event>

    @State private var openEvent: Event?

    private var events: [Event] { half.rows(of: feed.items) }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { Divider().opacity(0.45).padding(.leading, 17) }
                        AppearanceRow(event: event, subject: subject) { openEvent = event }
                            .padding(.horizontal, 5)
                            .task { await store.pageOn(feed, after: event) }
                    }
                    if events.isEmpty, !feed.hasMore {
                        // Only reachable for the past half: the upcoming one is
                        // whole before this screen can be opened.
                        Text(half.emptyNote)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }
                .padding(.vertical, 6)
                .glassPanel(cornerRadius: 28)

                if feed.moreFailure == nil, events.isEmpty, feed.hasMore, !feed.isLoadingMore {
                    // Still paging towards this half's first row.
                    SearchProgress(compact: true)
                }
                FeedFooter(feed: feed) { store.remember(feed.items) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            // Hung on the stack rather than on the spinner it is reading for:
            // the spinner comes and goes with `isLoadingMore`, and a task on a
            // view that leaves the screen is cancelled with it — which would
            // cancel the very load it is waiting on.
            .task(id: feed.items.count) { await readOn() }
        }
        .washBackground()
        .navigationTitle(half.title(of: subject))
        // An imported name, shown in the language Eventernote published it in.
        .navigationSubtitle(Text(verbatim: subject.name))
        .navigationBarTitleDisplayMode(.inline)
        // Pushed from a performer's or a hall's page, which put the tab bar
        // away for its own bar; it stays away until the reader is back past
        // that page, rather than coming back for one screen.
        .toolbar(.hidden, for: .tabBar)
        .eventSheet($openEvent)
    }

    /// Pages on while this half is still empty.
    ///
    /// The past half can sit entirely behind a page the page before this one
    /// never needed — it stops as soon as the upcoming half is whole — and with
    /// no row on screen there is nothing for the row-by-row paging to hang off.
    /// Keyed on the item count so it asks again for each page that turns up
    /// nothing, and does nothing at all the moment a first row of this half
    /// arrives. A page that adds no row of any kind leaves the count where it
    /// was, so this stops rather than spinning.
    private func readOn() async {
        guard events.isEmpty, feed.hasMore, !feed.isLoadingMore else { return }
        await feed.loadMore()
        store.remember(feed.items)
    }
}

#Preview {
    NavigationStack {
        ListingHalfView(subject: .performer("水瀬いのり"), half: .past, feed: .preview)
    }
    .library(EventStore.preview)
}
