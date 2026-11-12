import SwiftUI

/// A deadline of the ticket sale — to apply, to pay, or from when the ticket
/// can be picked up — written from Ticket To-Dos, as `TodoAdd.dc.html` draws
/// it: which event, which of the three, the round it is for, when, how long
/// before to hear about it, and for a payment or a pickup what is owed, where
/// and on which page.
///
/// It writes an ``EventReminder`` and nothing else, so the same deadline
/// stands on the event's own card. Holds a copy, as ``EventReminderView`` does:
/// the checkmark writes it, the X asks first where that throws something away.
/// The time is asked on the hall's clock, which is the one a play guide's
/// notice prints it on.
///
/// **Nothing here is read or worked out**: the reader copies it from the
/// notice — see ``EventReminder``.
struct TicketDeadlineView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// What an amount with no currency of its own starts in — see ``Currencies/storageKey``.
    @AppStorage(Currencies.storageKey) private var defaultCurrency = Currencies.yen

    /// The events a new deadline can be written on, soonest first; empty
    /// where it is one event's deadline being changed.
    private let events: [Event]
    private let isNew: Bool
    private let opened: EventReminder

    @State private var event: Event
    @State private var draft: EventReminder
    @State private var amount: Decimal?
    @State private var place: String
    @State private var page: String
    /// Whether the reader has set the time themselves: until then it follows
    /// the event and the kind.
    @State private var hasSetTime = false
    @State private var isConfirmingDiscard = false

    /// Where a ticket is usually paid for and issued in Japan, offered ready
    /// written, as they are printed.
    private static let places = ["セブン-イレブン", "ファミリーマート", "ローソン", "クレジットカード"]

    /// A new deadline, for one of `events` — which must hold one.
    init(events: [Event], kind: ReminderKind = .paymentDeadline) {
        let event = events[0]
        let reminder = EventReminder(kind: kind, for: event)
        self.events = events
        isNew = true
        opened = reminder
        _event = State(initialValue: event)
        _draft = State(initialValue: reminder)
        _amount = State(initialValue: nil)
        _place = State(initialValue: "")
        _page = State(initialValue: "")
    }

    /// One of `event`'s deadlines, to be changed.
    init(event: Event, editing reminder: EventReminder) {
        events = []
        isNew = false
        opened = reminder
        _event = State(initialValue: event)
        _draft = State(initialValue: reminder)
        _amount = State(initialValue: reminder.owed?.amount)
        _place = State(initialValue: reminder.payAt ?? "")
        _page = State(initialValue: reminder.link?.absoluteString ?? "")
        _hasSetTime = State(initialValue: true)
    }

    private var kind: ReminderKind { draft.ticketKind ?? .paymentDeadline }
    private var tracking: Tracking { store.tracking(for: event) }

    /// The currency an amount is asked in: the one it was written in, then
    /// the ticket's own, then the reader's default.
    private var currency: String {
        draft.currency ?? (tracking.currency.isEmpty ? defaultCurrency : tracking.currency)
    }

    /// The page as it would be kept: a web page, or nothing.
    private var link: URL? {
        let typed = page.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return nil }
        return QRCodeLink.link(inCode: typed.contains("://") ? typed : "https://\(typed)")
    }

    private var isPageUnreadable: Bool {
        !page.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && link == nil
    }

    private var settled: EventReminder {
        var reminder = draft
        if kind == .applicationDeadline {
            reminder.owed = nil
            reminder.payAt = nil
        } else {
            reminder.owed = amount.map { Money(amount: $0, currency: currency) }
            reminder.payAt = EventReminder.typedPlace(place)
        }
        reminder.link = link
        if reminder.round?.isEmpty == true { reminder.round = nil }
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
                    if isNew { eventSection }
                    kindSection
                    whenSection
                    if kind != .applicationDeadline { paymentSection }
                    pageSection
                    if !isNew { deleteButton }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isNew ? Text("New Deadline") : Text(verbatim: kind.label))
            .navigationBarTitleDisplayMode(.inline)
            .padNavigationBarOnMac()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        if hasChanges { isConfirmingDiscard = true } else { dismiss() }
                    }
                    .tint(.primary)
                    .keyboardShortcut(.cancelAction)
                    .confirmationDialog(isNew ? Text("Discard this deadline?") : Text("Discard your changes?"),
                                        isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                        Button(role: .destructive) {
                            dismiss()
                        } label: {
                            isNew ? Text("Discard Deadline") : Text("Discard Changes")
                        }
                        Button("Keep Editing", role: .cancel) {}
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm, action: save)
                        .disabled(isPageUnreadable)
                }
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .opensFromOutside()
        .task { await LotteryReminders.shared.refreshAuthorization() }
    }

    // MARK: - Which event, and which deadline

    private var eventSection: some View {
        TicketForm.section("Event") {
            Menu {
                Picker("Event", selection: Binding { event } set: { choose($0) }) {
                    ForEach(events) { option in
                        Text(verbatim: "\(option.title) — \(option.dayLine)").tag(option)
                    }
                }
            } label: {
                HStack(spacing: 11) {
                    FlyerThumbnail(url: event.imageURL, width: 30, cornerRadius: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .scalingFont(size: 14.5, weight: .semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(verbatim: "\(event.dayLine) · \(event.venue)")
                            .scalingFont(size: 12)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .scalingFont(size: 11, weight: .semibold)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(TicketForm.fieldFill, in: TicketForm.fieldShape)
                .contentShape(TicketForm.fieldShape)
            }
            .buttonStyle(.plain)
        }
    }

    /// Another event: the deadline goes with it, and so does the round, which
    /// was one of the first event's.
    private func choose(_ chosen: Event) {
        event = chosen
        draft.round = nil
        retime()
    }

    private var kindSection: some View {
        TicketForm.section("Deadline") {
            HStack(spacing: 8) {
                ForEach(ReminderKind.tickets) { option in
                    kindTile(option)
                }
            }
        }
    }

    private func kindTile(_ option: ReminderKind) -> some View {
        let isOn = kind == option
        let (symbol, tint): (String, Color) = switch option {
        case .applicationDeadline: (TicketTodoText.symbol(of: .apply), TicketTodoText.tint(of: .apply))
        case .paymentDeadline: (TicketTodoText.symbol(of: .pay), TicketTodoText.tint(of: .pay))
        default: (TicketTodoText.symbol(of: .pickUp), TicketTodoText.tint(of: .pickUp))
        }
        return Button {
            withAnimation(.snappy) {
                // The alert follows the kind while it is still the kind's own.
                if draft.lead == kind.defaultLead { draft.lead = option.defaultLead }
                draft.title = option.rawValue
                retime()
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                Text(verbatim: option.label)
                    .font(.system(size: 12, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 70)
            .padding(.horizontal, 4)
            .background(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(TicketForm.fieldFill),
                        in: .rect(cornerRadius: 16, style: .continuous))
            .contentShape(.rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// The time a new deadline opens on, for this event and this kind, until
    /// the reader sets one.
    private func retime() {
        guard isNew, !hasSetTime else { return }
        let fresh = EventReminder(kind: kind, for: event)
        draft.day = fresh.day
        draft.minute = fresh.minute
    }

    // MARK: - For which round, when, and the alert

    /// The rounds a deadline can be for: the ones written on the event's
    /// ticket first, then the rest of a sale's — and to apply, only those
    /// that are drawn, since a first-come round has nothing to apply by.
    private var rounds: [String] {
        let written = tracking.lotteriesInOrder.map(\.round).filter { !$0.isEmpty }
        var rounds: [String] = []
        for round in written + LotteryRound.allCases.map(\.rawValue) where !rounds.contains(round) {
            if kind == .applicationDeadline, LotteryRound(rawValue: round)?.isFirstCome == true { continue }
            rounds.append(round)
        }
        return rounds
    }

    private func roundLabel(_ round: String) -> Text {
        let name = Text(verbatim: LotteryRound.label(of: round))
        guard let entry = tracking.lotteries.first(where: { $0.round == round }), !entry.isPending else { return name }
        return Text("\(name) · \(LotteryText.result(entry.outcome, firstCome: entry.isFirstCome))")
    }

    private var whenSection: some View {
        let zone = event.timeZone
        let moment = Binding<Date> {
            draft.date(in: zone)
        } set: {
            draft.move(to: $0, in: zone)
            hasSetTime = true
        }
        let leads = ReminderLead.choices + (draft.lead.map { ReminderLead.choices.contains($0) ? [] : [$0] } ?? [])
        return VStack(alignment: .leading, spacing: 10) {
            TicketForm.field(symbol: "ticket") {
                Text("For")
                Spacer(minLength: 8)
                Picker("For", selection: Binding { draft.round ?? "" } set: { draft.round = $0.isEmpty ? nil : $0 }) {
                    Text("Any Round").tag("")
                    Divider()
                    ForEach(rounds, id: \.self) { roundLabel($0).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(.brandTint)
            }
            TicketForm.field(symbol: "clock") {
                DatePicker("Date", selection: moment,
                           in: ...event.dayEnds.addingTimeInterval(-1), displayedComponents: .date)
                Spacer(minLength: 8)
                DatePicker("Time", selection: moment, displayedComponents: .hourAndMinute)
            }
            .environment(\.timeZone, zone)
            .tint(.brandTint)
            // Said only where it could be taken for the reader's own.
            if zone.identifier != TimeZone.current.identifier {
                Text("Venue Time · \(event.offsetLine(in: zone))")
                    .scalingFont(size: 12.5, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            TicketForm.field(symbol: draft.lead == nil ? "bell.slash" : "bell") {
                Text("Alert")
                Spacer(minLength: 8)
                Picker("Alert", selection: $draft.lead) {
                    Text("No Alert").tag(Int?.none)
                    Divider()
                    ForEach(leads, id: \.self) { lead in
                        Text(verbatim: ReminderLead.label(of: lead)).tag(Int?.some(lead))
                    }
                }
                .pickerStyle(.menu)
                .tint(.brandTint)
            }
            alertStatus
        }
    }

    /// Why no notification will come, where one was asked for and none will.
    @ViewBuilder
    private var alertStatus: some View {
        if let date = draft.alertDate(in: event.timeZone) {
            if !EventReminders.shared.isEnabled {
                note(Text("Event Reminders are off in Settings."))
            } else if LotteryReminders.shared.authorization == .denied {
                note(Text("Notifications are off in Settings"))
            } else if date <= .now {
                note(Text("That moment has passed, so no notification will come."))
            }
        }
    }

    private func note(_ text: Text) -> some View {
        text
            .scalingFont(size: 12.5, weight: .medium)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - What is owed, where, and the page for it

    private var paymentSection: some View {
        TicketForm.section(kind == .paymentDeadline ? "Payment" : "Ticket Pickup") {
            if kind == .paymentDeadline {
                TicketForm.field {
                    Text(verbatim: Currencies.symbol(of: currency))
                        .scalingFont(size: 15)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                } content: {
                    TextField("Amount", value: $amount, format: .money(in: currency), prompt: Text("Amount"))
                        .keyboardType(Currencies.fractionDigits(of: currency) > 0 ? .decimalPad : .numberPad)
                        .monospacedDigit()
                    Text(verbatim: currency)
                        .scalingFont(size: 13)
                        .foregroundStyle(.secondary)
                }
            }
            TicketForm.field(symbol: "storefront", trailingInset: 6) {
                TextField("Where", text: $place,
                          prompt: kind == .paymentDeadline ? Text("Pay At") : Text("Pick Up At"))
                    .submitLabel(.done)
                Menu {
                    ForEach(Self.places, id: \.self) { option in
                        Button(option) { place = option }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .scalingFont(size: 12, weight: .semibold)
                        .foregroundStyle(Color.brandTint)
                        .frame(width: 34, height: 34)
                        .contentShape(.rect)
                }
                .accessibilityLabel(Text("Suggestions"))
            }
        }
    }

    private var pageSection: some View {
        TicketForm.section("Page") {
            TicketForm.field(symbol: "link") {
                TextField("Page", text: $page, prompt: Text(verbatim: "https://"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            }
            if isPageUnreadable {
                note(Text("That isn’t a web address."))
            } else {
                note(Text("The play guide’s page for this order, if you want it one tap away. It opens in your browser."))
            }
        }
    }

    /// Not asked about first, as a reminder's own delete is not.
    private var deleteButton: some View {
        Button(role: .destructive) {
            store.removeReminder(opened.id, from: event)
            dismiss()
        } label: {
            Label("Delete Deadline", systemImage: "trash")
                .scalingFont(size: 15, weight: .semibold)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 34)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }
}
