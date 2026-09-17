import SwiftUI

/// The reader's own library: everything they have tracked, grouped and filtered.
struct EventsView: View {
    @Environment(EventStore.self) private var store

    @State private var filter: LibraryFilter = .upcoming
    @State private var grouping: Grouping = .date
    @State private var openEvent: Event?

    /// Picking events to remove. Kept apart from `openEvent`: while this is on,
    /// a tap chooses a row rather than opening it.
    @State private var isSelecting = false
    @State private var selection: Set<Event.ID> = []
    @State private var isConfirmingRemoval = false

    private var groups: [EventGroup] {
        store.groups(filter: filter, grouping: grouping)
    }

    private var eventCount: Int {
        store.events(matching: filter).count
    }

    /// Selecting reaches what the filter is showing and no further — "Upcoming"
    /// on screen must not quietly take the past with it.
    private var shownIDs: Set<Event.ID> {
        Set(groups.flatMap { $0.events.map(\.id) })
    }

    private var chosen: [Event] {
        selection.compactMap { store.event(id: $0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .washBackground()
            .navigationTitle("My Events")
            .navigationSubtitle(subtitle)
            // Selecting takes the bottom of the screen over, the way it does
            // everywhere else on iOS: the tab bar stands down so the actions for
            // what is selected can stand where the thumb already is.
            .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
            .toolbar {
                EventListToolbar(filter: $filter, grouping: $grouping,
                                 isSelecting: $isSelecting,
                                 counts: { store.events(matching: $0).count },
                                 canSelect: eventCount > 0)
                if isSelecting {
                    SelectionToolbar(
                        isEverythingSelected: selection == shownIDs,
                        selectAll: { selection = selection == shownIDs ? [] : shownIDs },
                        removeTitle: "Remove",
                        canRemove: !selection.isEmpty,
                        confirmation: RemovalConfirmation(
                            isPresented: $isConfirmingRemoval,
                            title: removalTitle,
                            message: Text("This removes them from your other devices as well. Anything your Eventernote account still lists comes back on the next refresh; the rest you can add again from Search."),
                            confirmTitle: "Remove",
                            cancelTitle: "Keep them",
                            confirm: {
                                store.remove(chosen)
                                endSelecting()
                            }
                        ),
                        remove: { isConfirmingRemoval = true }
                    )
                }
            }
            .sheet(item: $openEvent) { event in
                EventDetailView(event: event)
            }
            // Nothing is left selected behind a filter that no longer shows it,
            // and nothing survives leaving the mode that picked it.
            .onChange(of: filter) { selection.removeAll() }
            .onChange(of: isSelecting) { selection.removeAll() }
        }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(groups) { group in
                Section {
                    ForEach(group.events) { event in
                        LibraryRow(event: event) {
                            // In edit mode the row belongs to the selection, not
                            // to the sheet.
                            if !isSelecting { openEvent = event }
                        }
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    GroupHeader(label: Text(group.label), count: group.events.count)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
    }

    /// The subtitle carries the count that matters at the moment: how many are
    /// about to be removed, rather than how many there are.
    private var subtitle: Text {
        if isSelecting {
            selection.isEmpty
                ? Text("Select events to remove")
                : Text("^[\(selection.count) event](inflect: true) selected")
        } else {
            Text("^[\(eventCount) event](inflect: true)")
        }
    }

    /// Spelled out rather than inflected: a confirmation's title is handed to
    /// UIKit as plain text, and the `^[…](inflect:)` markup that reads as a
    /// count everywhere else in the app arrives there unprocessed.
    private var removalTitle: Text {
        selection.count == 1
            ? Text("Remove this event from your library?")
            : Text("Remove \(selection.count) events from your library?")
    }

    private func endSelecting() {
        isSelecting = false
        selection.removeAll()
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                filter == .upcoming ? "No Upcoming Events" : "No Past Events",
                systemImage: "calendar"
            )
        } description: {
            Text("Events you track appear here. Find them in Search.")
        }
    }
}

#Preview {
    EventsView()
        .environment(EventStore.preview)
}
