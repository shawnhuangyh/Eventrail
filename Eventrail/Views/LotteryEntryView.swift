import SwiftUI

/// One round of a sale the reader tried for, on a page of its own pushed over
/// the ticket sheet: which round it was, how many times they applied in it,
/// when it stops taking applications, the day — and time — its results come
/// out, what they asked for in order of preference, and how it went — and
/// once it is won, when it is paid by and its ticket issued from.
///
/// Those times are wall clocks at the hall, as the
/// play guide prints them, asked on the hall's clock as every time written
/// for an event is (``EventReminderView``).
///
/// A first-come round (一般発売, 見切れ席) is asked less: nothing was applied
/// for, nothing is announced, and nobody writes one down but for a seat they
/// got — so it asks for the seat alone: no applications, no day and no result
/// (``LotteryEntry/outcome``).
///
/// Answered the way the sheet answers — chips for a choice, a stepper for a
/// count — but onto the page's own copy of the entry, which only the
/// checkmark hands back to the sheet's copy of the record; the sheet's own
/// checkmark writes the two down together. Backing out leaves the entry as it
/// was, and a new one unadded — asking first, wherever that throws something
/// away: a round is several answers about one application, given together.
/// An entry is taken out by a swipe on its card on the sheet.
struct LotteryEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EventStore.self) private var store
    /// Which day the calendar is open over, if either.
    @State private var pickingDay: Moment?
    /// The day the picker shows, held while it is open — see ``dayPicker``.
    @State private var pickedDay = Date.now
    /// The entry as the page has it, every answer given here included.
    @State private var draft: LotteryEntry
    @State private var isConfirmingDiscard = false
    /// Whether a result has been picked — on this page, or before it. A new
    /// entry opens with none of the result chips on: it is pending until one
    /// is, but nobody said so.
    @State private var isResultGiven: Bool
    /// The classes the reader has typed before, offered as chips after the
    /// three — read once, as the page opens (``EventStore/typedSeatClasses()``).
    @State private var typedClasses: [String] = []
    /// Whether the field for a class the chips do not offer is up, which
    /// choice it is for, and what has been typed in it.
    @State private var isTypingClass = false
    @State private var typingClassOf: LotteryChoice.ID?
    @State private var typedClass = ""
    /// The entry as the page opened on it.
    private let opened: LotteryEntry

    /// How many of the classes typed before are offered: the ones a reader
    /// goes back to, not every one they ever wrote.
    private static let offeredTypedClasses = 4
    /// The ticket sheet's copy of the record — see ``TicketDetailsView``.
    @Binding private var tracking: Tracking
    /// The event the round is for, whose hall's clock the times are asked on.
    private let event: Event

    /// The page for `entry` on `event` — one already in `tracking`, or a new
    /// one, which the checkmark adds to it.
    init(entry: LotteryEntry, of event: Event, in tracking: Binding<Tracking>) {
        _draft = State(initialValue: entry)
        _isResultGiven = State(initialValue: tracking.wrappedValue.lotteries.contains { $0.id == entry.id })
        opened = entry
        self.event = event
        _tracking = tracking
    }

    /// 18:00, the hour many notices give (18:00頃), as a time added to a
    /// results day opens (Shawn): the reader moves it to what the notice
    /// says.
    private static let usualResultsMinute = 18 * 60

    /// Whether the entry is not in the sheet's copy yet.
    private var isNew: Bool {
        !tracking.lotteries.contains { $0.id == draft.id }
    }

    /// Whether going back would throw away anything given here. A result
    /// picked on a new entry counts, Pending included, though that is what
    /// the entry held already. A new entry left as it opened is let go
    /// without asking: nothing on it would be lost.
    private var hasChanges: Bool { draft != opened || (isNew && isResultGiven) }

    /// Makes one change to the page's copy.
    private func change(_ edit: (inout LotteryEntry) -> Void) {
        edit(&draft)
    }

    /// Puts the entry into the sheet's copy — in its place where it is
    /// already in the list, at the end where it is new — and goes back to
    /// the sheet, which reads the ticket's class off the rounds won as it
    /// saves (``Tracking/settleSeatClass(since:)``). Notifications are asked
    /// for as the sheet is saved, not here — see ``TicketDetailsView``.
    private func save() {
        var entry = draft
        // A lottery saved with its count left empty was applied for once: a
        // round written down was tried for at least that. A first-come round
        // asks no count, so it keeps what it had.
        if !entry.isFirstCome && entry.applications == 0 { entry.applications = 1 }
        if let index = tracking.lotteries.firstIndex(where: { $0.id == entry.id }) {
            tracking.lotteries[index] = entry
        } else {
            tracking.lotteries.append(entry)
        }
        dismiss()
    }

    var body: some View {
        let entry = draft
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                roundSection(entry)
                if !entry.isFirstCome {
                    applicationsSection(entry)
                    momentSection(.deadline, of: entry)
                    momentSection(.results, of: entry)
                }
                choicesSection(entry)
                // A first-come round is got by being written down, so it
                // has no result to ask.
                if !entry.isFirstCome { resultSection(entry) }
                // What a win still asks before the ticket is in hand: a
                // first-come round's seat is a win from the start.
                if entry.isWon {
                    momentSection(.payment, of: entry)
                    momentSection(.pickup, of: entry)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if typedClasses.isEmpty {
                typedClasses = Array(store.typedSeatClasses().prefix(Self.offeredTypedClasses))
            }
        }
        .alert("Seat Type", isPresented: $isTypingClass) {
            TextField("Seat Type", text: $typedClass, prompt: Text(verbatim: "SS席"))
            Button("Cancel", role: .cancel) {}
            Button("Done") {
                let seatClass = SeatClass.typed(typedClass)
                if let choice = typingClassOf, !seatClass.isEmpty { setClass(seatClass, of: choice) }
            }
        } message: {
            Text("As the ticket prints it, such as SS席 or 注釈付き指定席.")
        }
        .navigationTitle("Lottery Entry")
        .navigationBarTitleDisplayMode(.inline)
        // The system's own back button, and its swipe from the edge, while
        // going back loses nothing; one that asks first once it would.
        .navigationBarBackButtonHidden(hasChanges)
        .toolbar {
            if hasChanges {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", systemImage: "chevron.left") { isConfirmingDiscard = true }
                        .tint(.primary)
                        // Escape asks too, as the sheet's own X does.
                        .keyboardShortcut(.cancelAction)
                        .confirmationDialog(isNew ? Text("Discard this entry?") : Text("Discard your changes?"),
                                            isPresented: $isConfirmingDiscard,
                                            titleVisibility: .visible) {
                            Button(role: .destructive) {
                                dismiss()
                            } label: {
                                isNew ? Text("Discard Entry") : Text("Discard Changes")
                            }
                            Button("Keep Editing", role: .cancel) {}
                        } message: {
                            if isNew {
                                Text("This new entry will not be added.")
                            } else {
                                Text("Your changes to this entry will not be saved.")
                            }
                        }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .confirm, action: save)
            }
        }
    }

    // MARK: - Round

    /// Which round it was, one of the five a sale runs through — see
    /// ``LotteryRound``. One is always the answer once given, so a chip
    /// tapped again stays on.
    private func roundSection(_ entry: LotteryEntry) -> some View {
        TicketForm.section("Round") {
            FlowLayout(spacing: 8) {
                ForEach(LotteryRound.allCases) { round in
                    TicketForm.chip(isOn: entry.round == round.rawValue) {
                        change { $0.round = round.rawValue }
                    } label: {
                        Text(verbatim: round.label)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: entry.round)
        }
    }

    // MARK: - Applications

    /// How many times the reader applied in this round — one for each 申込券
    /// or serial code put in. Stepped, since it is usually one or two, but a
    /// field too, for the reader who bought a box of singles. Empty — as a new
    /// entry opens, or emptied, or stepped down off one — it is saved as one
    /// (``save()``).
    private func applicationsSection(_ entry: LotteryEntry) -> some View {
        let count = Binding(
            get: { entry.applications },
            set: { count in change { $0.applications = count } }
        )
        return TicketForm.section("Entries") {
            // The stepper sits nearer the field's edge than the text does, so
            // it reads as a control inside the field rather than a second one.
            TicketForm.field(symbol: "square.stack", trailingInset: 6) {
                TextField("Entries", value: Binding<Int?>(
                    get: { count.wrappedValue == 0 ? nil : count.wrappedValue },
                    set: { count.wrappedValue = $0 ?? 0 }
                ), format: .entries, prompt: Text(verbatim: "—"))
                .keyboardType(.numberPad)
                .monospacedDigit()
                TicketForm.stepper(count, in: 0...LotteryEntry.mostApplications,
                                   fewer: Text("Fewer entries"), more: Text("More entries"))
            }
        }
    }

    // MARK: - Days and times

    /// Which of the round's moments a field, or the calendar, is about.
    private enum Moment {
        /// When it stops taking applications (``LotteryEntry/deadline``).
        case deadline
        /// When its results come out (``LotteryEntry/day``,
        /// ``LotteryEntry/minute``).
        case results
        /// For a round won, when it has to be paid by
        /// (``LotteryEntry/payment``), and from when its ticket can be
        /// issued (``LotteryEntry/pickup``).
        case payment, pickup

        var title: LocalizedStringKey {
            switch self {
            case .deadline: "Application Deadline"
            case .results: "Results Announced"
            case .payment: "Payment Deadline"
            case .pickup: "Ticket Pickup"
            }
        }

        /// What a time added to the day opens on: 23:59 for a deadline or a
        /// payment, where nearly every notice closes; 18:00 for results; the
        /// morning for a pickup. The reader moves it to what the notice says.
        var openingMinute: Int {
            switch self {
            case .deadline: LotteryDeadline.closingMinute
            case .results: LotteryEntryView.usualResultsMinute
            case .payment: TicketStage.payment.dayAloneMinute
            case .pickup: TicketStage.pickup.dayAloneMinute
            }
        }

        /// The step of a won round this is, where it is one.
        var stage: TicketStage? {
            switch self {
            case .payment: .payment
            case .pickup: .pickup
            case .deadline, .results: nil
            }
        }
    }

    /// When the round stops taking applications (申込締切), when its results
    /// come out, and for a round won when it is paid by (入金締切) and its
    /// ticket issued from (発券開始), asked alike: a day, and beside it a time
    /// where the notice gives one, with how far off the day is set on the
    /// title.
    ///
    /// The deadline is for one more 申込券 before it closes
    /// (``LotteryDeadlineAlert``); the payment and the pickup are what Ticket
    /// To-Dos follows (``TicketTodo``), where what is owed and where is
    /// written. How long before a deadline or a payment the notification
    /// comes is one answer in Settings for every round
    /// (``LotteryReminders/deadlineLead``), not asked here. The deadline falls
    /// on an earlier day than the results — see ``selectableDays(_:of:)``.
    private func momentSection(_ moment: Moment, of entry: LotteryEntry) -> some View {
        TicketForm.section(moment.title) {
            if let day = writtenDay(moment, in: entry) {
                Text(verbatim: LotteryText.relative(day))
                    .scalingFont(size: 13, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } content: {
            momentField(moment, of: entry)
            if writtenMinute(moment, in: entry) != nil { venueTimeNote }
        }
    }

    /// One row: the day written out in full, the calendar opening over it,
    /// and once there is a day, its time beside it — on the hall's clock —
    /// or a button to add one. For the results, the time is what the
    /// notification comes at, where it would otherwise come at eight in the
    /// evening (``LotteryReminder``); for the deadline, when it closes, where
    /// a day alone closes at 23:59. Taken off again with the ✕ beside it,
    /// since many notices print a day alone.
    private func momentField(_ moment: Moment, of entry: LotteryEntry) -> some View {
        let day = writtenDay(moment, in: entry)
        let minute = writtenMinute(moment, in: entry)
        return TicketForm.field(symbol: "calendar", trailingInset: day != nil && minute != nil ? 6 : 14) {
            Button {
                let range = selectableDays(moment, of: entry)
                let shown = day?.date() ?? Calendar.current.startOfDay(for: .now)
                // Within what the calendar offers, so its checkmark gives a
                // day that keeps the deadline before the results.
                pickedDay = min(max(shown, range.lowerBound), range.upperBound)
                pickingDay = moment
            } label: {
                Group {
                    if let day {
                        Text(verbatim: LotteryText.long(day))
                            .monospacedDigit()
                    } else {
                        Text("Not Set")
                            .foregroundStyle(.tertiary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(get: { pickingDay == moment },
                                          set: { if !$0 { pickingDay = nil } })) {
                dayPicker(moment, of: entry)
            }
            .accessibilityLabel(Text(moment.title))
            .accessibilityValue(day.map { Text(verbatim: LotteryText.long($0)) } ?? Text("Not Set"))

            // A time means nothing without its day.
            if let day {
                timeControl(moment, on: day, at: minute)
            }
        }
    }

    /// The time beside a day, and the ✕ that takes it off — or Add Time.
    @ViewBuilder
    private func timeControl(_ moment: Moment, on day: CalendarDay, at minute: Int?) -> some View {
        let zone = event.timeZone
        if let minute {
            DatePicker("Time", selection: Binding<Date> {
                day.date(at: minute, in: zone)
            } set: { date in
                let parts = Calendar.gregorian(in: zone).dateComponents([.hour, .minute], from: date)
                setMinute((parts.hour ?? 0) * 60 + (parts.minute ?? 0), of: moment)
            }, displayedComponents: .hourAndMinute)
            .environment(\.timeZone, zone)
            .tint(.brandTint)
            .fixedSize()
            removeButton(Text("Remove Time")) { setMinute(nil, of: moment) }
        } else {
            Button {
                setMinute(moment.openingMinute, of: moment)
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

    private func writtenDay(_ moment: Moment, in entry: LotteryEntry) -> CalendarDay? {
        switch moment {
        case .deadline: entry.deadline?.day
        case .results: entry.day
        case .payment, .pickup: moment.stage.flatMap { entry[$0]?.day }
        }
    }

    private func writtenMinute(_ moment: Moment, in entry: LotteryEntry) -> Int? {
        switch moment {
        case .deadline: entry.deadline?.minute
        case .results: entry.minute
        case .payment, .pickup: moment.stage.flatMap { entry[$0]?.minute }
        }
    }

    /// Moves `moment` to `day`, keeping its time — or, given nil, takes it
    /// out, its time with it. A payment or a pickup moved keeps what else
    /// was said of it: reached, what is owed, where.
    private func setDay(_ day: CalendarDay?, of moment: Moment) {
        change { entry in
            switch moment {
            case .deadline:
                entry.deadline = day.map { LotteryDeadline(day: $0, minute: entry.deadline?.minute) }
            case .results:
                entry.day = day
                if day == nil { entry.minute = nil }
            case .payment, .pickup:
                guard let stage = moment.stage else { return }
                guard let day else {
                    entry[stage] = nil
                    return
                }
                var written = entry[stage] ?? TicketMoment(day: day)
                written.day = day
                entry[stage] = written
            }
        }
    }

    private func setMinute(_ minute: Int?, of moment: Moment) {
        change { entry in
            switch moment {
            case .deadline: entry.deadline?.minute = minute
            case .results: entry.minute = minute
            case .payment, .pickup: if let stage = moment.stage { entry[stage]?.minute = minute }
            }
        }
    }

    /// Which clock a time is asked on, said only where it could be taken for
    /// the reader's own.
    @ViewBuilder
    private var venueTimeNote: some View {
        let zone = event.timeZone
        if zone.identifier != TimeZone.current.identifier {
            Text("Venue Time · \(event.offsetLine(in: zone))")
                .scalingFont(size: 12.5, weight: .medium)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// A small round ✕ inside a field, taking out what the field holds.
    private func removeButton(_ label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 17))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// A calendar, with Clear and a checkmark under it. A day tapped is taken
    /// at once; the checkmark takes the one shown, so a day already selected
    /// — today, on an entry with none yet — can be given too, which a tap on
    /// it would not.
    private func dayPicker(_ moment: Moment, of entry: LotteryEntry) -> some View {
        VStack(spacing: 0) {
            DatePicker(moment.title, selection: Binding(
                get: { pickedDay },
                set: { date in
                    pickedDay = date
                    setDay(CalendarDay(date), of: moment)
                }
            ), in: selectableDays(moment, of: entry), displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(.brandTint)

            HStack {
                if writtenDay(moment, in: entry) != nil {
                    Button("Clear", role: .destructive) {
                        setDay(nil, of: moment)
                        pickingDay = nil
                    }
                }
                Spacer()
                Button("Done", systemImage: "checkmark") {
                    setDay(CalendarDay(pickedDay), of: moment)
                    pickingDay = nil
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

    /// The days the calendar offers. A deadline falls before the results
    /// day — applications close before anything is drawn — and no later than
    /// the event's own day, since nothing is scheduled past it, and nor does a
    /// payment or a pickup; the results
    /// fall after the deadline's day (``LotteryEntry/lastDeadlineDay``,
    /// ``LotteryEntry/firstResultsDay``). A lottery already won or lost was
    /// drawn by today, so its results day falls no later than that — the
    /// other half of a day ahead leaving only Pending to pick.
    private func selectableDays(_ moment: Moment, of entry: LotteryEntry) -> ClosedRange<Date> {
        let calendar = Calendar.gregorian()
        /// The last moment of `day`, on this device's clock, as the
        /// calendar counts it.
        func end(of day: Date) -> Date {
            calendar.date(byAdding: .day, value: 1, to: day)?.addingTimeInterval(-1) ?? .distantFuture
        }
        switch moment {
        case .deadline:
            var last = event.localDay
            if let beforeResults = entry.lastDeadlineDay?.date(in: calendar) { last = min(last, beforeResults) }
            return Date.distantPast...end(of: last)
        case .payment, .pickup:
            return Date.distantPast...end(of: event.localDay)
        case .results:
            let first = entry.firstResultsDay?.date(in: calendar) ?? .distantPast
            let last = entry.outcome == .pending ? Date.distantFuture : end(of: calendar.startOfDay(for: .now))
            // A round written as drawn with its deadline still to come has
            // no day that keeps both; the calendar still opens, on today.
            return min(first, last)...last
        }
    }

    // MARK: - Choices

    /// What was applied for, most wanted first: a card each, with the class
    /// as chips and how many as a stepper, and a way to add the next. A
    /// first-come round asks for one seat, with nothing to rank.
    ///
    /// The class chips are the three nearly every ticket prints, the ones the
    /// reader typed before, and Other… for one they have not: SS席, 注釈付き
    /// 指定席, 立見 — kept as typed (``SeatClass/typed(_:)``), and ranked after
    /// the three wherever classes are.
    private func choicesSection(_ entry: LotteryEntry) -> some View {
        TicketForm.section(entry.isFirstCome ? "Seat" : "Choices") {
            if !entry.isFirstCome {
                Text("In order of preference")
                    .scalingFont(size: 13, weight: .medium)
                    .foregroundStyle(.secondary)
            }
        } content: {
            ForEach(Array(entry.choices.enumerated()), id: \.element.id) { index, choice in
                choiceCard(choice, at: index, in: entry)
            }
            if entry.choices.count < (entry.isFirstCome ? 1 : LotteryEntry.mostChoices) {
                TicketForm.addButton(entry.isFirstCome
                                     ? Text("Add Seat")
                                     : Text("Add \(LotteryChoice.ordinal(entry.choices.count)) Choice")) {
                    change { entry in
                        // The count goes on as it was, since most lotteries
                        // are applied for in pairs all the way down.
                        entry.choices.append(LotteryChoice(quantity: entry.choices.last?.quantity ?? 1))
                    }
                }
            }
        }
    }

    private func choiceCard(_ choice: LotteryChoice, at index: Int, in entry: LotteryEntry) -> some View {
        let isWon = entry.outcome == .won(choice.id)
        return VStack(alignment: .leading, spacing: 12) {
            // A first-come round's one seat has no rank to head it, and its
            // win is said under the result. One that came over from a lottery
            // with several choices keeps them ranked, so they can be taken
            // down to one.
            if !entry.isFirstCome || entry.choices.count > 1 {
                choiceHeader(choice, at: index, in: entry, isWon: isWon)
            }

            FlowLayout(spacing: 8) {
                ForEach(SeatClass.allCases) { seatClass in
                    let isOn = choice.seatClass == seatClass.rawValue
                    // A second tap takes the class back, for a lottery that
                    // sold one kind of seat.
                    TicketForm.chip(isOn: isOn) {
                        setClass(isOn ? "" : seatClass.rawValue, of: choice.id)
                    } label: {
                        TicketForm.seatClassLabel(seatClass, isOn: isOn)
                    }
                }
                ForEach(offeredClasses(in: entry), id: \.self) { seatClass in
                    let isOn = choice.seatClass == seatClass
                    TicketForm.chip(isOn: isOn) {
                        setClass(isOn ? "" : seatClass, of: choice.id)
                    } label: {
                        TicketForm.seatClassLabel(typed: seatClass, isOn: isOn)
                    }
                }
                TicketForm.chip(isOn: false) {
                    typingClassOf = choice.id
                    typedClass = ""
                    isTypingClass = true
                } label: {
                    Text("Other…")
                }
            }
            .sensoryFeedback(.selection, trigger: choice.seatClass)

            HStack(spacing: 10) {
                Text("^[\(choice.quantity) ticket](inflect: true)")
                    .scalingFont(size: 15.5)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                TicketForm.stepper(Binding(
                    get: { choice.quantity },
                    set: { count in
                        change { entry in
                            guard let at = entry.choices.firstIndex(where: { $0.id == choice.id }) else { return }
                            entry.choices[at].quantity = count
                        }
                    }
                ), in: 1...LotteryChoice.most, fewer: Text("Fewer tickets"), more: Text("More tickets"))
            }
            .padding(.top, 12)
            .overlay(alignment: .top) {
                Rectangle().fill(.quaternary).frame(height: 0.5)
            }
        }
        .padding(.vertical, 12)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .background(TicketForm.fieldFill, in: .rect(cornerRadius: 16, style: .continuous))
    }

    /// The classes offered after the three the chips always offer: the ones
    /// the reader typed before, then any typed on this entry since, so a
    /// class typed for the first choice is a chip for the second.
    private func offeredClasses(in entry: LotteryEntry) -> [String] {
        var seen: Set<String> = []
        return (typedClasses + entry.choices.map(\.seatClass)).filter {
            !$0.isEmpty && SeatClass(rawValue: $0) == nil && seen.insert($0).inserted
        }
    }

    private func setClass(_ seatClass: String, of choice: LotteryChoice.ID) {
        change { entry in
            guard let at = entry.choices.firstIndex(where: { $0.id == choice }) else { return }
            entry.choices[at].seatClass = seatClass
        }
    }

    /// A choice's rank, Won where it was won with, and the button that takes
    /// it out where there is another to keep.
    private func choiceHeader(_ choice: LotteryChoice, at index: Int, in entry: LotteryEntry,
                              isWon: Bool) -> some View {
        HStack(spacing: 8) {
            Text("\(LotteryChoice.ordinal(index)) Choice")
                .scalingFont(size: 15, weight: .semibold)
                .foregroundStyle(isWon ? Color.trackAttended : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isWon { wonBadge }
            if entry.choices.count > 1 {
                Button {
                    change { $0.removeChoice(choice.id) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(TicketForm.controlFill, in: .circle)
                        .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.vertical, -7)
                .padding(.trailing, -7)
                .accessibilityLabel(Text("Remove \(LotteryChoice.ordinal(index)) Choice"))
            }
        }
        .frame(minHeight: 30)
    }

    private var wonBadge: some View {
        Label("Won", systemImage: "checkmark")
            .labelStyle(BadgeLabelStyle())
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.trackAttended)
            .padding(.leading, 7)
            .padding(.trailing, 9)
            .frame(height: 24)
            .background(Color.trackAttended.opacity(0.12), in: .capsule)
    }

    // MARK: - Result

    /// How a lottery went: still to come, won — with which choice, where
    /// there was more than one — or lost — and none of them on a new entry
    /// until one is picked (``isResultGiven``). A win is spelled out under the
    /// chips; it is what makes the ticket (``Tracking/hasTicket``).
    ///
    /// While the results day written down is still ahead, only Pending can be
    /// picked: nothing has been drawn to win or lose.
    private func resultSection(_ entry: LotteryEntry) -> some View {
        TicketForm.section("Result") {
            FlowLayout(spacing: 8) {
                resultChip(Text("Pending"), .pending, in: entry)
                if entry.choices.count > 1 {
                    ForEach(Array(entry.choices.enumerated()), id: \.element.id) { index, choice in
                        resultChip(Text("Won \(LotteryChoice.ordinal(index)) Choice"), .won(choice.id), in: entry)
                    }
                } else {
                    resultChip(Text("Won"), .won(entry.choices.first?.id), in: entry)
                }
                resultChip(Text("Lost"), .lost, in: entry)
            }
            .sensoryFeedback(.selection, trigger: isResultGiven ? entry.result : nil)

            if isAhead(entry.day) {
                Text("Won and Lost can be picked once the results are out.")
                    .scalingFont(size: 13)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            if entry.isWon { wonPanel(entry) }
        }
    }

    private func resultChip(_ label: Text, _ result: LotteryResult, in entry: LotteryEntry) -> some View {
        let isLocked = result != .pending && isAhead(entry.day)
        return TicketForm.chip(isOn: isResultGiven && entry.outcome == result) {
            isResultGiven = true
            change { $0.result = result }
        } label: {
            label
        }
        .disabled(isLocked)
        .opacity(isLocked ? 0.4 : 1)
    }

    /// Whether a results day is still to come — after today, since results
    /// out today can be in already.
    private func isAhead(_ day: CalendarDay?) -> Bool {
        (day?.daysAway() ?? 0) > 0
    }

    /// What was won and with which choice.
    private func wonPanel(_ entry: LotteryEntry) -> some View {
        let won = entry.wonChoice
        let index = won.flatMap { choice in entry.choices.firstIndex { $0.id == choice.id } }
        return VStack(alignment: .leading, spacing: 5) {
            Group {
                if let won { Text("Won \(LotteryText.won(won))") } else { Text("Won") }
            }
            .scalingFont(size: 15.5, weight: .semibold)
            .foregroundStyle(Color.trackAttended)
            if let subtitle = wonSubtitle(entry, choiceAt: index) {
                subtitle
                    .scalingFont(size: 12.5)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .background(Color.trackAttended.opacity(0.09), in: .rect(cornerRadius: 16, style: .continuous))
    }

    /// Which choice it was won with, and the day the result came out.
    private func wonSubtitle(_ entry: LotteryEntry, choiceAt index: Int?) -> Text? {
        let choice = index.map { Text("\(LotteryChoice.ordinal($0)) Choice") }
        let day = entry.day.map { Text(verbatim: LotteryText.short($0)) }
        switch (choice, day) {
        case let (choice?, day?): return Text("\(choice) · \(day)")
        case let (choice?, nil): return choice
        case let (nil, day?): return day
        case (nil, nil): return nil
        }
    }

}

/// A small symbol and a few words, set tight beside each other, as a badge
/// sets them.
private struct BadgeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .imageScale(.small)
                .fontWeight(.bold)
            configuration.title
        }
    }
}

#Preview {
    NavigationStack {
        LotteryEntryView(entry: PreviewData.tracking[PreviewData.events[0].id]?.lotteries.first
                             ?? LotteryEntry(choices: [LotteryChoice()]),
                         of: PreviewData.events[0],
                         in: .constant(PreviewData.tracking[PreviewData.events[0].id] ?? Tracking()))
    }
}
