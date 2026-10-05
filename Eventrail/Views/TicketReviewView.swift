import SwiftUI

/// Which of a run of past events the reader went to — offered at the head of
/// My Events' Past once an import has brought in events with no ticket
/// written down, and from the Passport while it has nothing to stamp.
///
/// Only a ticket says the reader went (``EventStore/hasAttended(_:)``), and an
/// account's history carries none, so a history imported whole is a Passport
/// of nothing until each event has one. This is the one pass over them: each
/// event picked is given a ticket held with its round left unwritten
/// (``LotteryEntry/ticketHeld``) — attended from then on, moving no lottery
/// figure, and the event's own Ticket Details there to say more.
///
/// Nothing starts picked: a pick is the reader saying they were there, and a
/// list found already ticked is not that. Select All is one tap.
struct TicketReviewView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Which clock the day and times are printed on — see ``TimeDisplay``.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue
    @AppStorage(TicketReviewView.reviewedKey) private var reviewed: Double = 0

    /// When the reader last went through the events awaiting a ticket, in
    /// seconds since the reference date, so My Events offers only what has
    /// come since (``EventStore/awaitingTickets(_:since:)``). Per device, like
    /// the switches: a second device asks once for itself.
    static let reviewedKey = "ticketsReviewed"

    /// What is offered, read once as the sheet opens: the list does not
    /// shrink under the reader's thumb as the picks are written.
    let events: [Event]

    @State private var selection: Set<Event.ID> = []
    @State private var isConfirmingDiscard = false

    private var groups: [EventGroup] { EventGroup.byMonth(LibraryFilter.past.rows(of: events)) }

    private var allIDs: Set<Event.ID> { Set(events.map(\.id)) }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                Section {
                    heading
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 16, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .selectionDisabled()
                }
                .listSectionSpacing(0)

                ForEach(groups) { group in
                    Section {
                        ForEach(group.events) { event in
                            EventRowContent(event: event, detail: event.shown(on: timeDisplay).timeDetail) {
                                EmptyView()
                            }
                            .glassPanel()
                            .listRowInsets(GroupHeader.rowInsets)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        GroupHeader(label: Text(group.label), count: group.events.count)
                            .listRowInsets(GroupHeader.insets)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .monthSections()
            // Picking is all this list is for, so it is picking from the start.
            .environment(\.editMode, .constant(.active))
            .washBackground()
            .navigationTitle("Record Tickets")
            .navigationSubtitle(subtitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Plain beside the checkmark's blue, as on the ticket sheet:
                // the X writes nothing.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        if selection.isEmpty { dismiss() } else { isConfirmingDiscard = true }
                    }
                    .tint(.primary)
                    .confirmationDialog("Discard your changes?", isPresented: $isConfirmingDiscard,
                                        titleVisibility: .visible) {
                        Button("Discard Changes", role: .destructive) { dismiss() }
                        Button("Keep Editing", role: .cancel) {}
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm, action: save)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(selection == allIDs ? "Deselect All" : "Select All") {
                        selection = selection == allIDs ? [] : allIDs
                    }
                }
            }
        }
        .interactiveDismissDisabled(!selection.isEmpty)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Which of these did you go to?")
                .font(.system(size: 20, weight: .bold))
            Text("Each one picked counts as attended. Its round can be filled in later from the event's Ticket Details.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: Text {
        selection.isEmpty
            ? Text("^[\(events.count) event](inflect: true)")
            : Text("^[\(selection.count) event](inflect: true) selected")
    }

    /// Writes the picks down and counts everything offered as gone through —
    /// picked or not, since leaving one unpicked is the answer that the reader
    /// did not go — so My Events stops offering them.
    private func save() {
        store.recordTickets(for: events.filter { selection.contains($0.id) })
        reviewed = Date.now.timeIntervalSinceReferenceDate
        dismiss()
    }
}

/// A run of events handed to ``TicketReviewView``, presented with
/// `sheet(item:)` so the sheet is built with the list it was opened for
/// rather than a copy of the screen's state from before the tap.
struct TicketReviewList: Identifiable {
    let id = UUID()
    let events: [Event]
}

/// The row at the head of My Events' Past that offers ``TicketReviewView``:
/// how many past events have arrived with no ticket since the reader last
/// went through them, and a way to put the offer away until more do.
struct TicketReviewPrompt: View {
    let count: Int
    let open: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Image(systemName: "ticket")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Color.trackTicket)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("^[\(count) past event](inflect: true) without a ticket")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Pick the ones you went to")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the list to record tickets")

            Button("Not Now", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(.circle)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassPanel(interactive: true)
    }
}

#Preview {
    TicketReviewView(events: PreviewData.events)
        .library(EventStore.preview)
}
