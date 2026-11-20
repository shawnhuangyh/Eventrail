import SwiftUI

/// A step of a won round's ticket — when it is paid by, or from when it can
/// be picked up — written from Ticket To-Dos, as `TodoAdd.dc.html` draws it:
/// which event, which round won, which of the two, when, and what is owed,
/// where and on which page.
///
/// It writes the round's own ``LotteryEntry/payment`` or
/// ``LotteryEntry/pickup`` and nothing else, so the same step stands on the
/// round's page on Ticket Details. Holds a copy, as ``EventReminderView``
/// does: the checkmark writes it, the X asks first where that throws
/// something away. The time is asked on the hall's clock, which is the one a
/// play guide's notice prints it on; how long before it to hear is Settings'
/// to say (``LotteryReminders/deadlineLead``).
///
/// **Nothing here is read or worked out**: the reader copies it from the
/// notice — see ``TicketMoment``.
struct TicketDeadlineView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// What an amount with no currency of its own starts in — see ``Currencies/storageKey``.
    @AppStorage(Currencies.storageKey) private var defaultCurrency = Currencies.yen

    /// The events a new step can be written on, soonest first — each with a
    /// round won; empty where it is one round's step being changed.
    private let events: [Event]
    private let isNew: Bool

    @State private var event: Event
    @State private var entryID: LotteryEntry.ID?
    @State private var stage: TicketStage
    @State private var draft: TicketMoment
    @State private var amount: Decimal?
    @State private var place: String
    @State private var page: String
    @State private var isPickingDay = false
    @State private var pickedDay = Date.now
    @State private var isConfirmingDiscard = false
    /// The step as the form opened on it, to tell whether anything changed.
    private let opened: TicketMoment

    /// Where a ticket is usually paid for and issued in Japan, offered ready
    /// written, as they are printed.
    private static let places = ["セブン-イレブン", "ファミリーマート", "ローソン", "クレジットカード"]

    /// A new step, for a round won on one of `events` — which must hold one.
    init(events: [Event], tracking: (Event) -> Tracking) {
        let event = events[0]
        let entry = Self.wins(in: tracking(event)).first
        let moment = TicketMoment(day: CalendarDay(event.date, in: .gregorian(in: event.timeZone)))
        self.events = events
        isNew = true
        opened = moment
        _event = State(initialValue: event)
        _entryID = State(initialValue: entry?.id)
        _stage = State(initialValue: .payment)
        _draft = State(initialValue: moment)
        _amount = State(initialValue: nil)
        _place = State(initialValue: "")
        _page = State(initialValue: "")
    }

    /// `entry`'s `stage` on `event`, to be changed.
    init(event: Event, entry: LotteryEntry, editing stage: TicketStage) {
        let moment = entry[stage] ?? TicketMoment(day: CalendarDay(event.date, in: .gregorian(in: event.timeZone)))
        events = []
        isNew = false
        opened = moment
        _event = State(initialValue: event)
        _entryID = State(initialValue: entry.id)
        _stage = State(initialValue: stage)
        _draft = State(initialValue: moment)
        _amount = State(initialValue: moment.owed?.amount)
        _place = State(initialValue: moment.payAt ?? "")
        _page = State(initialValue: moment.link?.absoluteString ?? "")
    }

    /// The rounds a step can be written for: those won, in sale order.
    static func wins(in tracking: Tracking) -> [LotteryEntry] {
        tracking.lotteriesInOrder.filter(\.isWon)
    }

    /// A step's name, as a section and a row print it.
    static func title(of stage: TicketStage) -> Text {
        switch stage {
        case .payment: Text("Payment Deadline")
        case .pickup: Text("Ticket Pickup")
        }
    }

    private var tracking: Tracking { store.tracking(for: event) }
    private var wins: [LotteryEntry] { Self.wins(in: tracking) }

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

    private var settled: TicketMoment {
        var moment = draft
        moment.owed = stage == .payment ? amount.map { Money(amount: $0, currency: currency) } : nil
        moment.payAt = TicketMoment.typedPlace(place)
        moment.link = link
        return moment
    }

    private func save() {
        guard let entryID else { return }
        let moment = settled
        let record = tracking.updatingLottery(entryID) { entry in
            // What was said of it before — reached, given up — stays.
            var written = moment
            written.done = entry[stage]?.done
            written.missed = entry[stage]?.missed
            entry[stage] = written
        }
        store.setTracking(record, for: event)
        // The moment to ask whether the reader wants to hear about it — on
        // the checkmark, since a sheet put away with its X undoes it.
        LotteryReminders.shared.askIfNeeded(for: record.lotteries.filter { $0.id == entryID }, in: event.timeZone)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if isNew {
                        eventSection
                        roundSection
                        kindSection
                    }
                    whenSection
                    placeSection
                    pageSection
                    if !isNew { deleteButton }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isNew ? Text("New Deadline") : Self.title(of: stage))
            .navigationBarTitleDisplayMode(.inline)
            .padNavigationBarOnMac()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        if settled != opened { isConfirmingDiscard = true } else { dismiss() }
                    }
                    .tint(.primary)
                    .keyboardShortcut(isPickingDay ? nil : .cancelAction)
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
                        .disabled(isPageUnreadable || entryID == nil)
                }
            }
        }
        .interactiveDismissDisabled(settled != opened)
        .opensFromOutside()
    }

    // MARK: - Which event, which round, which step

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

    /// Another event: the round goes with it, which was one of the first
    /// event's, and the day moves to the new one's.
    private func choose(_ chosen: Event) {
        event = chosen
        entryID = Self.wins(in: store.tracking(for: chosen)).first?.id
        draft.day = CalendarDay(chosen.date, in: .gregorian(in: chosen.timeZone))
    }

    private var roundSection: some View {
        TicketForm.section("Round") {
            TicketForm.field(symbol: "ticket") {
                Text("For")
                Spacer(minLength: 8)
                Picker("For", selection: $entryID) {
                    ForEach(wins) { entry in
                        LotteryText.round(of: entry).tag(LotteryEntry.ID?.some(entry.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(.brandTint)
            }
        }
    }

    private var kindSection: some View {
        TicketForm.section("Deadline") {
            HStack(spacing: 8) {
                ForEach(TicketStage.allCases) { option in
                    kindTile(option)
                }
            }
        }
    }

    private func kindTile(_ option: TicketStage) -> some View {
        let isOn = stage == option
        let kind: TicketTodo.Kind = option == .payment ? .pay : .pickUp
        let tint = TicketTodoText.tint(of: kind)
        return Button {
            withAnimation(.snappy) { stage = option }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: TicketTodoText.symbol(of: kind))
                    .font(.system(size: 18, weight: .medium))
                Self.title(of: option)
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

    // MARK: - When

    /// The day and, beside it, the time where the notice gives one — one row,
    /// as the round's own page asks it (``LotteryEntryView``).
    private var whenSection: some View {
        let zone = event.timeZone
        let time = Binding<Date> {
            draft.day.date(at: draft.minute ?? stage.dayAloneMinute, in: zone)
        } set: { date in
            let parts = Calendar.gregorian(in: zone).dateComponents([.hour, .minute], from: date)
            draft.minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        return TicketForm.section(isNew ? "When" : "Date") {
            Text(verbatim: LotteryText.relative(draft.day))
                .scalingFont(size: 13, weight: .medium)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } content: {
            TicketForm.field(symbol: "calendar", trailingInset: draft.minute == nil ? 14 : 6) {
                Button {
                    pickedDay = draft.day.date()
                    isPickingDay = true
                } label: {
                    Text(verbatim: LotteryText.long(draft.day))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isPickingDay) { dayPicker }
                if draft.minute != nil {
                    DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, zone)
                        .tint(.brandTint)
                        .fixedSize()
                    Button {
                        draft.minute = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Remove Time"))
                } else {
                    Button {
                        draft.minute = stage.dayAloneMinute
                    } label: {
                        Text("Add Time")
                            .foregroundStyle(Color.brandTint)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(minHeight: 46)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            // Said only where it could be taken for the reader's own.
            if draft.minute != nil, zone.identifier != TimeZone.current.identifier {
                Text("Venue Time · \(event.offsetLine(in: zone))")
                    .scalingFont(size: 12.5, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    /// A calendar up to the event's own day — nothing is scheduled past it —
    /// with a checkmark under it.
    private var dayPicker: some View {
        let calendar = Calendar.gregorian()
        let last = calendar.date(byAdding: .day, value: 1, to: event.localDay)?.addingTimeInterval(-1) ?? .distantFuture
        return VStack(spacing: 0) {
            DatePicker("Date", selection: Binding(
                get: { pickedDay },
                set: { date in
                    pickedDay = date
                    draft.day = CalendarDay(date)
                }
            ), in: Date.distantPast...last, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(.brandTint)
            HStack {
                Spacer()
                Button("Done", systemImage: "checkmark") {
                    draft.day = CalendarDay(min(pickedDay, last))
                    isPickingDay = false
                }
                .labelStyle(.iconOnly)
                .fontWeight(.semibold)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .padding(12)
        .frame(width: 340)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - What is owed, where, and the page for it

    private var placeSection: some View {
        TicketForm.section(stage == .payment ? "Payment" : "Ticket Pickup") {
            if stage == .payment {
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
                          prompt: stage == .payment ? Text("Pay At") : Text("Pick Up At"))
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
            Group {
                if isPageUnreadable {
                    Text("That isn’t a web address.")
                } else {
                    Text("The play guide’s page for this order, if you want it one tap away. It opens in your browser.")
                }
            }
            .scalingFont(size: 12.5, weight: .medium)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Not asked about first, as a reminder's own delete is not.
    private var deleteButton: some View {
        Button(role: .destructive) {
            if let entryID {
                store.setTracking(tracking.updatingLottery(entryID) { $0[stage] = nil }, for: event)
            }
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
