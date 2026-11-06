import SwiftUI

/// One time to be reminded of, on a sheet of its own over the event's: what it
/// is, when, and how long before it to hear about it.
///
/// Holds a copy, as Ticket Details does: the checkmark writes it, the X leaves
/// the record as it was, asking first where that throws something away. The
/// time is asked on the hall's clock whatever Settings prints on, since that is
/// the clock the promoter's notice prints it on.
struct EventReminderView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let event: Event
    /// Whether the reminder is not on the event yet, which only the checkmark
    /// puts it.
    private let isNew: Bool
    private let opened: EventReminder

    @State private var draft: EventReminder
    /// The name as the field holds it: one of ``ReminderKind`` in the reader's
    /// language, or what they typed. Kept through ``ReminderKind/typed(_:)``.
    @State private var name: String
    @State private var isConfirmingDiscard = false
    @FocusState private var isNaming: Bool

    init(event: Event, reminder: EventReminder, isNew: Bool) {
        self.event = event
        self.isNew = isNew
        opened = reminder
        _draft = State(initialValue: reminder)
        _name = State(initialValue: ReminderKind.label(of: reminder.title))
    }

    private var settled: EventReminder {
        var reminder = draft
        reminder.title = ReminderKind.typed(name)
        return reminder
    }

    private var hasChanges: Bool { settled != opened }

    private func save() {
        let reminder = settled
        store.setReminder(reminder, for: event)
        // The moment to ask whether the reader wants to hear about it — on
        // the checkmark, since a sheet put away with its X undoes it.
        EventReminders.shared.askIfNeeded(for: reminder, at: event)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    nameSection
                    timeSection
                    alertSection
                    if !isNew { deleteButton }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isNew ? Text("New Reminder") : Text("Reminder"))
            .navigationBarTitleDisplayMode(.inline)
            .padNavigationBarOnMac()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        if hasChanges { isConfirmingDiscard = true } else { dismiss() }
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
                        .disabled(settled.title.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(hasChanges)
        .opensFromOutside()
        .task { await LotteryReminders.shared.refreshAuthorization() }
        .onAppear { if name.isEmpty { isNaming = true } }
    }

    private var nameSection: some View {
        TicketForm.section("Name") {
            TicketForm.field(symbol: "text.cursor") {
                TextField("Name", text: $name, prompt: Text(verbatim: ReminderKind.goodsSale.label))
                    .focused($isNaming)
                    .submitLabel(.done)
            }
        }
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

    private var alertSection: some View {
        let choices = ReminderLead.choices + (draft.lead.map { ReminderLead.choices.contains($0) ? [] : [$0] } ?? [])
        return TicketForm.section("Alert") {
            VStack(alignment: .leading, spacing: 10) {
                TicketForm.field(symbol: draft.lead == nil ? "bell.slash" : "bell") {
                    Picker("Alert", selection: $draft.lead) {
                        Text("No Alert").tag(Int?.none)
                        Divider()
                        ForEach(choices, id: \.self) { lead in
                            Text(verbatim: ReminderLead.label(of: lead)).tag(Int?.some(lead))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.brandTint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                alertStatus
            }
        }
    }

    /// Why no notification will come, where one was asked for and none will.
    @ViewBuilder
    private var alertStatus: some View {
        if let date = draft.alertDate(in: event.timeZone) {
            if !EventReminders.shared.isEnabled {
                alertNote(Text("Event Reminders are off in Settings."))
            } else if LotteryReminders.shared.authorization == .denied {
                HStack(spacing: 8) {
                    alertNote(Text("Notifications are off in Settings"))
                    Link("Open Settings", destination: URL(string: UIApplication.openNotificationSettingsURLString)!)
                        .scalingFont(size: 12.5, weight: .semibold)
                        .foregroundStyle(Color.brandTint)
                }
            } else if date <= .now {
                alertNote(Text("That moment has passed, so no notification will come."))
            }
        }
    }

    private func alertNote(_ text: Text) -> some View {
        text
            .scalingFont(size: 12.5, weight: .medium)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Not asked about first, as a swipe to delete is not.
    private var deleteButton: some View {
        Button(role: .destructive) {
            store.removeReminder(opened.id, from: event)
            dismiss()
        } label: {
            Label("Delete Reminder", systemImage: "trash")
                .scalingFont(size: 15, weight: .semibold)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 34)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }
}
