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
                ToolbarItem(placement: .topBarLeading) { selectButton }
                if isSelecting {
                    ToolbarItemGroup(placement: .bottomBar) { selectionBar }
                } else {
                    // Changing the filter mid-selection would move the ground
                    // under the choice, so it is put away while selecting.
                    ToolbarItem(placement: .primaryAction) { showMenu }
                }
            }
            .sheet(item: $openEvent) { event in
                EventDetailView(event: event)
            }
            .confirmationDialog(removalTitle, isPresented: $isConfirmingRemoval,
                                titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    store.remove(chosen)
                    endSelecting()
                }
                Button("Keep them", role: .cancel) {}
            } message: {
                Text("They go from this device and from your other devices. You can add them again from Search.")
            }
            // Nothing is left selected behind a filter that no longer shows it.
            .onChange(of: filter) { selection.removeAll() }
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
                    if !group.label.isEmpty {
                        GroupHeader(label: Text(group.label), count: group.events.count)
                            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                    }
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

    private var selectButton: some View {
        Button(isSelecting ? "Done" : "Select") {
            if isSelecting { endSelecting() } else { isSelecting = true }
        }
        .font(.system(size: 13.5, weight: .semibold))
        .disabled(!isSelecting && eventCount == 0)
    }

    @ViewBuilder
    private var selectionBar: some View {
        Button(selection == shownIDs ? "Deselect All" : "Select All") {
            selection = selection == shownIDs ? [] : shownIDs
        }

        Spacer()

        Button("Remove", systemImage: "trash", role: .destructive) {
            isConfirmingRemoval = true
        }
        .disabled(selection.isEmpty)
    }

    private var removalTitle: Text {
        Text("Remove ^[\(selection.count) event](inflect: true) from your library?")
    }

    private func endSelecting() {
        isSelecting = false
        selection.removeAll()
    }

    private var showMenu: some View {
        Menu {
            Picker(selection: $filter) {
                ForEach(LibraryFilter.allCases) { option in
                    Text(option.label).tag(option)
                }
            } label: {
                Text("Show")
            }
            .pickerStyle(.inline)

            Picker(selection: $grouping) {
                ForEach(Grouping.allCases) { option in
                    Text(option.label).tag(option)
                }
            } label: {
                Text("Group by")
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Text(filter.label)
                    .font(.system(size: 13.5, weight: .semibold))
                Circle()
                    .fill(.tertiary)
                    .frame(width: 3.5, height: 3.5)
                Text(grouping.byLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Show and group events")
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
