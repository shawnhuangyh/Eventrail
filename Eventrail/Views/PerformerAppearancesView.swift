import SwiftUI

/// One half of a performer's listing in full — every upcoming date, or every
/// past appearance.
///
/// ``PerformerView`` shows the first few of each half and sends the rest here,
/// for the reason ``FavoriteEventsView`` gives: a card that grows without limit
/// stops being a summary of the listing and becomes the listing, and on a
/// performer with years behind them it buries everything under it.
///
/// The feed is handed over rather than rebuilt, so opening this screen costs no
/// request — and the pages read on from here are already in the sections behind
/// it when the reader goes back.
struct PerformerAppearancesView: View {
    /// Which side of today this screen lists. One listing to Eventernote, two
    /// different questions to the reader.
    enum Half {
        case upcoming, past

        var title: LocalizedStringKey {
            switch self {
            case .upcoming: "Upcoming"
            case .past: "Past appearances"
            }
        }

        /// What stands where the rows would, when this half has none.
        ///
        /// Said in two places — under the section on a performer's page and on
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
    /// person and there is nothing else on the screen to say whose dates these
    /// are.
    let performer: String
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
                        AppearanceRow(event: event) { openEvent = event }
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

                if feed.isLoadingMore || (events.isEmpty && feed.hasMore) {
                    SearchProgress(compact: true)
                }
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
        .navigationTitle(half.title)
        // An imported name, shown in the language Eventernote published it in.
        .navigationSubtitle(Text(verbatim: performer))
        .navigationBarTitleDisplayMode(.inline)
        .eventSheet($openEvent)
    }

    /// Pages on while this half is still empty.
    ///
    /// Past appearances can sit entirely behind a page ``PerformerView`` never
    /// needed — it stops as soon as the upcoming half is whole — and with no row
    /// on screen there is nothing for the row-by-row paging to hang off. Keyed
    /// on the item count so it asks again for each page that turns up nothing,
    /// and does nothing at all the moment a first row of this half arrives. A
    /// page that adds no row of any kind leaves the count where it was, so this
    /// stops rather than spinning.
    private func readOn() async {
        guard events.isEmpty, feed.hasMore, !feed.isLoadingMore else { return }
        await feed.loadMore()
        store.remember(feed.items)
    }
}

#Preview {
    NavigationStack {
        PerformerAppearancesView(performer: "水瀬いのり", half: .past, feed: .preview)
    }
    .environment(EventStore.preview)
}
