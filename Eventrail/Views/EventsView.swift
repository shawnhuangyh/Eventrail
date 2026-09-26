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
                        markRead: filter == .upcoming ? markButton : nil,
                        remove: { isConfirmingRemoval = true }
                    )
                }
            }
            .eventSheet($openEvent)
            // Nothing is left selected behind a filter that no longer shows it,
            // and nothing survives leaving the mode that picked it.
            .onChange(of: filter) { selection.removeAll() }
            .onChange(of: isSelecting) { selection.removeAll() }
            // Read again as the sheet closes, against the copy the sheet has
            // just read: the row was marked as it stood when tapped, and a
            // page that had changed since would otherwise come back Updated
            // from the very sheet that showed the change.
            .onChange(of: openEvent) { closed, open in
                guard open == nil, let closed, let current = store.event(id: closed.id),
                      current.isUpcoming
                else { return }
                mark(current, read: true)
            }
        }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(groups) { group in
                Section {
                    ForEach(group.events) { event in
                        // Only a night still ahead is read or unread, as on
                        // Following: a past one is history rather than news, and
                        // its record has been pruned with the night anyway.
                        let unread = event.isUpcoming ? store.unread(event) : nil
                        LibraryRow(event: event, unread: unread) {
                            if event.isUpcoming { mark(event, read: true) }
                            openEvent = event
                        }
                            // In edit mode the row belongs to the selection, not
                            // to the sheet: the row's own button would otherwise
                            // take the tap, and only the strip the List draws
                            // its mark in would pick the row.
                            .allowsHitTesting(!isSelecting)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            // Toward the tag, as on Following: a swipe from the
                            // leading edge reads the row, or unreads it.
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if event.isUpcoming {
                                    let isUnread = unread != nil
                                    Button {
                                        mark(event, read: isUnread)
                                    } label: {
                                        Label(isUnread ? "Read" : "Unread",
                                              systemImage: isUnread ? "envelope.open" : "envelope.badge")
                                    }
                                    .tint(Color.brandTint)
                                }
                            }
                            // Every row, past or ahead: the one-row form of the
                            // selection bar's trash. Not asked about first, as no
                            // swipe to delete on iOS is — what the account
                            // still lists comes back on the next refresh, and the
                            // rest is a search away.
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Remove", systemImage: "trash", role: .destructive) {
                                    withAnimation(.snappy) { store.remove([event]) }
                                }
                                // Said outright: the role alone left the button
                                // in the app's tint rather than the system red.
                                .tint(.red)
                            }
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
    /// about to be removed, rather than how many there are. Only Upcoming can
    /// mark as well, so only Upcoming says so.
    private var subtitle: Text {
        if isSelecting {
            selection.isEmpty
                ? (filter == .upcoming ? Text("Select events to mark or remove")
                                       : Text("Select events to remove"))
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

    /// Following's logic, over the picked nights still ahead: a past one has no
    /// read state, and would only write a record the next prune takes away.
    private var markButton: MarkReadButton {
        let picked = chosen.filter(\.isUpcoming)
        let marksRead = picked.isEmpty || picked.contains(where: store.isUnread)
        return MarkReadButton(marksRead: marksRead, isEnabled: !picked.isEmpty) {
            // One transaction for both. Here, unlike on Following, the tag
            // changes the row's height, and a List resizing its rows in an
            // animation left the edit-mode circles in place when edit mode was
            // ended outside it.
            withAnimation(.snappy) {
                endSelecting()
                store.markRead(picked, read: marksRead)
            }
        }
    }

    private func mark(_ event: Event, read: Bool) {
        withAnimation(.snappy) { store.markRead([event], read: read) }
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
