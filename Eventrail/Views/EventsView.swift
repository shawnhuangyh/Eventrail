import SwiftUI

/// The reader's own library: everything they have tracked, grouped and filtered.
struct EventsView: View {
    @Environment(EventStore.self) private var store

    @State private var filter: LibraryFilter = .upcoming
    @State private var grouping: Grouping = .date
    @State private var openEvent: Event?

    private var groups: [EventGroup] {
        store.groups(filter: filter, grouping: grouping)
    }

    private var eventCount: Int {
        store.events(matching: filter).count
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
            .navigationTitle(Text("^[\(eventCount) Event](inflect: true)"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) { showMenu }
            }
            .sheet(item: $openEvent) { event in
                EventDetailView(event: event)
            }
        }
    }

    private var list: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.events) { event in
                        LibraryRow(event: event) { openEvent = event }
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
        .environment(EventStore())
}
