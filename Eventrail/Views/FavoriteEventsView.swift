import SwiftUI

/// Everything the reader has hearted, in full.
///
/// The Me tab shows the first few and sends the rest here rather than growing
/// without limit: a card that runs past the bottom of the screen stops being a
/// summary of the library and becomes the library.
///
/// It carries the same controls My Events does — the sort and filter capsule,
/// and the pencil that turns a tap on a row into a choice — because by the time
/// a list is long enough to need its own screen it is long enough to need them.
struct FavoriteEventsView: View {
    @Environment(EventStore.self) private var store

    @State private var filter: LibraryFilter = .upcoming
    @State private var grouping: Grouping = .date
    @State private var openEvent: Event?

    @State private var isSelecting = false
    @State private var selection: Set<Event.ID> = []
    @State private var isConfirmingRemoval = false

    private var favorites: [Event] { store.favoriteEvents }

    private var groups: [EventGroup] {
        store.groups(of: favorites, filter: filter, grouping: grouping)
    }

    /// Picking reaches what the filter is showing and no further.
    private var shownIDs: Set<Event.ID> {
        Set(groups.flatMap { $0.events.map(\.id) })
    }

    private var chosen: [Event] {
        selection.compactMap { store.event(id: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if favorites.isEmpty {
                    // Reachable by un-hearting the last one from this screen.
                    note("Tap the heart on any event to keep it here.")
                } else if groups.isEmpty {
                    note(filter == .upcoming
                         ? "Nothing you have hearted is still to come."
                         : "Nothing you have hearted has happened yet.")
                } else {
                    ForEach(groups) { group in
                        section(group)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .washBackground()
        .navigationTitle("Favorite Events")
        .navigationSubtitle(subtitle)
        .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
        .toolbar {
            EventListToolbar(filter: $filter, grouping: $grouping,
                             isSelecting: $isSelecting,
                             counts: { store.events(in: favorites, matching: $0).count },
                             canSelect: !favorites.isEmpty)
            if isSelecting {
                SelectionToolbar(
                    isEverythingSelected: selection == shownIDs,
                    selectAll: { selection = selection == shownIDs ? [] : shownIDs },
                    removeTitle: "Remove",
                    canRemove: !selection.isEmpty,
                    // Asked for the same reason My Events asks: a bar that empties
                    // a list on one tap is worth a second one, even where the act
                    // itself is mild.
                    confirmation: RemovalConfirmation(
                        isPresented: $isConfirmingRemoval,
                        title: removalTitle,
                        message: Text("Only the heart comes off — they stay in your library, and you can heart them again any time."),
                        confirmTitle: "Remove",
                        cancelTitle: "Keep them",
                        confirm: removeChosen
                    ),
                    remove: { isConfirmingRemoval = true }
                )
            }
        }
        .sheet(item: $openEvent) { event in
            EventDetailView(event: event)
        }
        .onChange(of: filter) { selection.removeAll() }
        .onChange(of: isSelecting) { selection.removeAll() }
    }

    private func section(_ group: EventGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupHeader(label: Text(group.label), count: group.events.count)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(group.events.enumerated()), id: \.element.id) { index, event in
                    FavoriteEventRow(event: event, showsDivider: index > 0,
                                     isSelecting: isSelecting,
                                     isSelected: selection.contains(event.id)) {
                        if isSelecting {
                            toggle(event)
                        } else {
                            openEvent = event
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .glassPanel()
        }
    }

    private func note(_ line: LocalizedStringKey) -> some View {
        Text(line)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .glassPanel()
    }

    /// The subtitle carries the count that matters at the moment: how many are
    /// about to go, rather than how many there are.
    private var subtitle: Text {
        if isSelecting {
            selection.isEmpty
                ? Text("Select events to remove")
                : Text("^[\(selection.count) event](inflect: true) selected")
        } else {
            Text("^[\(favorites.count) event](inflect: true)")
        }
    }

    private func toggle(_ event: Event) {
        if selection.contains(event.id) {
            selection.remove(event.id)
        } else {
            selection.insert(event.id)
        }
    }

    /// Spelled out rather than inflected: a dialog's words reach UIKit as plain
    /// text, and the `^[…](inflect:)` markup would arrive there unprocessed.
    private var removalTitle: Text {
        selection.count == 1
            ? Text("Remove this event from your favorites?")
            : Text("Remove \(selection.count) events from your favorites?")
    }

    /// Un-hearting rather than deleting: the events stay in the library.
    private func removeChosen() {
        let events = chosen
        withAnimation(.snappy) {
            for event in events { store.toggleFavorite(event) }
        }
        isSelecting = false
    }
}

#Preview {
    NavigationStack {
        FavoriteEventsView()
    }
    .environment(EventStore.preview)
}
