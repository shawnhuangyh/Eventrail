import SwiftUI

/// One time of the goods sale, on a sheet of its own over the event's: the
/// day and the time, nothing else. Which time it is was chosen on the card
/// (``EventPlanCard``); how long before it to hear is Settings' to say for
/// every one (``EventReminders/goodsLead``).
///
/// Holds a copy, as Ticket Details does: the checkmark writes it, the X leaves
/// the record as it was, asking first where that throws something away. The
/// time is asked on the hall's clock whatever Settings prints on, since that is
/// the clock the promoter's notice prints it on.
struct EventReminderView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let event: Event
    /// Whether the time is not on the event yet, which only the checkmark
    /// puts it.
    private let isNew: Bool
    private let opened: EventReminder

    @State private var draft: EventReminder
    @State private var isConfirmingDiscard = false

    init(event: Event, reminder: EventReminder, isNew: Bool) {
        self.event = event
        self.isNew = isNew
        opened = reminder
        _draft = State(initialValue: reminder)
    }

    private var hasChanges: Bool { isNew || draft != opened }

    private var title: String { ReminderKind.label(of: draft.title) }

    private func save() {
        store.setGoodsReminder(draft, for: event)
        // The moment to ask whether the reader wants to hear about it — on
        // the checkmark, since a sheet put away with its X undoes it.
        EventReminders.shared.askIfNeeded(for: draft, at: event)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    timeSection
                    if !isNew { deleteButton }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayMode(.inline)
            .padNavigationBarOnMac()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        if draft != opened { isConfirmingDiscard = true } else { dismiss() }
                    }
                    .tint(.primary)
                    .keyboardShortcut(.cancelAction)
                    .confirmationDialog(isNew ? Text("Discard this reminder?") : Text("Discard your changes?"),
                                        isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                        Button(role: .destructive) {
                            dismiss()
                        } label: {
                            isNew ? Text("Discard Reminder") : Text("Discard Changes")
                        }
                        Button("Keep Editing", role: .cancel) {}
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm, action: save)
                        .disabled(!hasChanges)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(draft != opened)
        .opensFromOutside()
    }

    /// The day and the time, both moving the one moment on the hall's clock.
    /// Up to the end of the event's day: nothing after that is ever scheduled
    /// (``EventStore/upcoming``), so a later day would come to nothing without
    /// a word.
    private var timeSection: some View {
        let zone = event.timeZone
        let moment = Binding<Date> {
            draft.date(in: zone)
        } set: {
            draft.move(to: $0, in: zone)
        }
        return TicketForm.section("Time") {
            // Said only where it could be taken for the reader's own.
            if zone.identifier != TimeZone.current.identifier {
                Text("Venue Time · \(event.offsetLine(in: zone))")
                    .scalingFont(size: 12.5, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } content: {
            TicketForm.field(symbol: "clock") {
                DatePicker("Date", selection: moment,
                           in: ...event.dayEnds.addingTimeInterval(-1), displayedComponents: .date)
                Spacer(minLength: 8)
                DatePicker("Time", selection: moment, displayedComponents: .hourAndMinute)
            }
            .environment(\.timeZone, zone)
            .tint(.brandTint)
        }
    }

    /// Not asked about first, as a swipe to delete is not. Takes the time off
    /// the card, with any an older build wrote for the same kind.
    private var deleteButton: some View {
        Button(role: .destructive) {
            if let kind = opened.goodsKind { store.removeGoodsReminder(kind, from: event) }
            dismiss()
        } label: {
            Label("Delete Time", systemImage: "trash")
                .scalingFont(size: 15, weight: .semibold)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 34)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }
}
