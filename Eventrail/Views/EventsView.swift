import SwiftData
import SwiftUI

/// The reader's own library: everything they have tracked, grouped and filtered.
///
/// Which half of it is on screen is chosen at the head of the list, and how it
/// is broken up in the capsule at its foot — see ``LibraryHalfPicker`` and
/// ``EventListMenu``.
struct EventsView: View {
    @Environment(EventStore.self) private var store
    @Query(LibraryEntry.library) private var kept: [LibraryEntry]

    @State private var filter: LibraryFilter = .upcoming
    @State private var grouping: Grouping = .date
    @State private var openEvent: Event?

    /// Picking events to remove. Kept apart from `openEvent`: while this is on,
    /// a tap chooses a row rather than opening it.
    @State private var isSelecting = false
    @State private var selection: Set<Event.ID> = []
    @State private var isConfirmingRemoval = false
    /// The row a swipe asked to take out, while its question is open.
    @State private var swipedAway: Event.ID?
    /// What ``TicketReviewView`` is going through, while it is open.
    @State private var reviewing: TicketReviewList?
    @AppStorage(TicketReviewView.reviewedKey) private var ticketsReviewed: Double = 0

    private var library: [Event] { store.events(of: kept, where: \.inLibrary) }

    private var groups: [EventGroup] {
        EventGroup.groups(of: library, filter: filter, grouping: grouping)
    }

    private var eventCount: Int {
        filter.rows(of: library).count
    }

    /// Selecting reaches what the filter is showing and no further — "Upcoming"
    /// on screen must not quietly take the past with it.
    private var shownIDs: Set<Event.ID> {
        Set(groups.flatMap { $0.events.map(\.id) })
    }

    private var chosen: [Event] {
        selection.compactMap { store.event(id: $0) }
    }

    /// The past events that have arrived with no ticket since the reader last
    /// went through them — what the row at the head of Past offers.
    private var awaitingTickets: [Event] {
        store.awaitingTickets(library, since: Date(timeIntervalSinceReferenceDate: ticketsReviewed))
    }

    var body: some View {
        NavigationStack {
            list
            .washBackground()
            .navigationTitle("My Events")
            .navigationSubtitle(subtitle)
            // Selecting takes the bottom of the screen over, the way it does
            // everywhere else on iOS: the tab bar stands down so the actions for
            // what is selected can stand where the thumb already is.
            .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
            .toolbar {
                PencilToolbar(isSelecting: $isSelecting, title: "Select Events",
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
                            message: selection.count == 1 ? EventRemoval.message : EventRemoval.messageForSeveral,
                            confirmTitle: "Remove",
                            cancelTitle: "Keep them",
                            confirm: {
                                store.remove(chosen)
                                endSelecting()
                            }
                        ),
                        markRead: filter == .upcoming ? markButton : nil,
                        markAttended: filter == .past ? attendedButton : nil,
                        remove: { isConfirmingRemoval = true }
                    )
                }
            }
            .eventSheet($openEvent)
            .sheet(item: $reviewing) { TicketReviewView(events: $0.events) }
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
            // A section of its own with no gap after it, as Following's chips
            // have: the gap a month opens with is for the month before it.
            // Held still while picking, for the reason the capsule is put away.
            Section {
                LibraryHalfPicker(filter: $filter)
                    .disabled(isSelecting)
                    .padding(.horizontal, 20)
                    .headRow(EdgeInsets(top: 8, leading: 0, bottom: 14, trailing: 0))
                // Under the picker, on Past alone and not while picking: an
                // import's history arrives with no tickets, and only a ticket
                // says the reader went.
                if filter == .past, !isSelecting {
                    let awaiting = awaitingTickets
                    if !awaiting.isEmpty {
                        TicketReviewPrompt(count: awaiting.count) {
                            reviewing = TicketReviewList(events: awaiting)
                        } dismiss: {
                            withAnimation(.snappy) { ticketsReviewed = Date.now.timeIntervalSinceReferenceDate }
                        }
                        .headRow(EdgeInsets(top: 0, leading: 16, bottom: 14, trailing: 16))
                    }
                }
            }
            .listSectionSpacing(0)

            if groups.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .headRow()
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.events) { event in
                        // Only an event still ahead is read or unread, as on
                        // Following: a past one is history rather than news, and
                        // its record has been pruned with the event anyway.
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
                            .listRowInsets(GroupHeader.rowInsets)
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
                            // selection bar's trash, and asked about first like
                            // it, since what the reader wrote on the event goes
                            // with it. No destructive role: that sends the row
                            // off the screen before the answer is in.
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Remove", systemImage: "trash") { swipedAway = event.id }
                                    .tint(.red)
                            }
                            .confirmingRemoval(isPresented: Binding(
                                get: { swipedAway == event.id },
                                set: { if !$0 { swipedAway = nil } }
                            )) {
                                withAnimation(.snappy) { store.remove([event]) }
                            }
                    }
                } header: {
                    GroupHeader(label: Text(group.label), count: group.events.count)
                        .listRowInsets(GroupHeader.insets)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Drawn here rather than by the tab, inside the room the capsule
        // leaves, so a notice stands above the capsule rather than over it.
        .refreshNotices(aboveBar: true)
        // Over the tab bar, in the middle, as Following's stands. Put away
        // while picking, when the bottom of the screen is the selection's.
        .safeAreaInset(edge: .bottom) {
            if !isSelecting, !groups.isEmpty { EventListMenu(grouping: $grouping) }
        }
        .monthSections()
        .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
    }

    /// The subtitle carries the count that matters at the moment: how many are
    /// about to be acted on, rather than how many there are. Both halves mark
    /// as well as remove — Upcoming as read, Past as attended.
    private var subtitle: Text {
        if isSelecting {
            selection.isEmpty
                ? Text("Select events to mark or remove")
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

    /// Following's logic, over the picked events still ahead: a past one has no
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

    /// A ticket held for every picked event that has none, which makes each
    /// attended. One way: a ticket is taken back on the event's own Ticket
    /// Details, where what it was can be seen.
    private var attendedButton: MarkAttendedButton {
        let picked = chosen.filter { !store.tracking(for: $0).hasTicket }
        return MarkAttendedButton(isEnabled: !picked.isEmpty) {
            withAnimation(.snappy) {
                endSelecting()
                store.recordTickets(for: picked)
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

private extension View {
    /// A row of the list that is not an event: no background, no separator,
    /// and nothing to pick while events are being picked.
    func headRow(_ insets: EdgeInsets = EdgeInsets()) -> some View {
        listRowInsets(insets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .selectionDisabled()
    }
}

#Preview {
    EventsView()
        .library(EventStore.preview)
}
