import SwiftUI

/// One round of a sale the reader tried for, on a page of its own pushed over
/// the ticket sheet: which round it was, how many times they applied in it,
/// the day its results come out, what they asked for in order of preference,
/// and how it went.
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
    @State private var isPickingDay = false
    /// The day the picker shows, held while it is open — see ``dayPicker``.
    @State private var pickedDay = Date.now
    /// The entry as the page has it, every answer given here included.
    @State private var draft: LotteryEntry
    @State private var isConfirmingDiscard = false
    /// Whether a result has been picked — on this page, or before it. A new
    /// entry opens with none of the result chips on: it is pending until one
    /// is, but nobody said so.
    @State private var isResultGiven: Bool
    /// The entry as the page opened on it.
    private let opened: LotteryEntry
    /// The ticket sheet's copy of the record — see ``TicketDetailsView``.
    @Binding private var tracking: Tracking

    /// The page for `entry` — one already in `tracking`, or a new one, which
    /// the checkmark adds to it.
    init(entry: LotteryEntry, in tracking: Binding<Tracking>) {
        _draft = State(initialValue: entry)
        _isResultGiven = State(initialValue: tracking.wrappedValue.lotteries.contains { $0.id == entry.id })
        opened = entry
        _tracking = tracking
    }

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
    /// saves (``Tracking/settleSeatClass(since:)``).
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
                    daySection(entry)
                }
                choicesSection(entry)
                // A first-come round is got by being written down, so it
                // has no result to ask.
                if !entry.isFirstCome { resultSection(entry) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
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

    // MARK: - Day

    /// The day the results are out, written out in full with how far off it
    /// is beside it. The calendar opens over the field.
    private func daySection(_ entry: LotteryEntry) -> some View {
        TicketForm.section("Results Announced") {
            Button {
                pickedDay = entry.day?.date() ?? Calendar.current.startOfDay(for: .now)
                isPickingDay = true
            } label: {
                TicketForm.field(symbol: "calendar") {
                    if let day = entry.day {
                        Text(verbatim: LotteryText.long(day))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: LotteryText.relative(day))
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not Set")
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .contentShape(TicketForm.fieldShape)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPickingDay) { dayPicker(entry) }
            .accessibilityValue(entry.day.map { Text(verbatim: LotteryText.long($0)) } ?? Text("Not Set"))
        }
    }

    /// A calendar, with Clear and a checkmark under it. A day tapped is taken
    /// at once; the checkmark takes the one shown, so a day already selected
    /// — today, on an entry with none yet — can be given too, which a tap on
    /// it would not.
    ///
    /// A lottery already won or lost was drawn by today, so its calendar ends
    /// there — the other half of a day ahead leaving only Pending to pick.
    private func dayPicker(_ entry: LotteryEntry) -> some View {
        VStack(spacing: 0) {
            DatePicker("Results Announced", selection: Binding(
                get: { pickedDay },
                set: { date in
                    pickedDay = date
                    change { $0.day = CalendarDay(date) }
                }
            ), in: selectableDays(entry), displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(.brandTint)

            HStack {
                if entry.day != nil {
                    Button("Clear", role: .destructive) {
                        change { $0.day = nil }
                        isPickingDay = false
                    }
                }
                Spacer()
                Button("Done", systemImage: "checkmark") {
                    change { $0.day = CalendarDay(pickedDay) }
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

    /// Every day, or none after today for a lottery already drawn.
    private func selectableDays(_ entry: LotteryEntry) -> ClosedRange<Date> {
        guard entry.outcome != .pending,
              let tomorrow = Calendar.current.date(byAdding: .day, value: 1,
                                                   to: Calendar.current.startOfDay(for: .now))
        else { return Date.distantPast...Date.distantFuture }
        return Date.distantPast...tomorrow.addingTimeInterval(-1)
    }

    // MARK: - Choices

    /// What was applied for, most wanted first: a card each, with the class
    /// as chips and how many as a stepper, and a way to add the next. A
    /// first-come round asks for one seat, with nothing to rank.
    private func choicesSection(_ entry: LotteryEntry) -> some View {
        TicketForm.section(entry.isFirstCome ? "Seat" : "Choices") {
            if !entry.isFirstCome {
                Text("In order of preference")
                    .font(.system(size: 13, weight: .medium))
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
                        change { entry in
                            guard let at = entry.choices.firstIndex(where: { $0.id == choice.id }) else { return }
                            entry.choices[at].seatClass = isOn ? "" : seatClass.rawValue
                        }
                    } label: {
                        TicketForm.seatClassLabel(seatClass, isOn: isOn)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: choice.seatClass)

            HStack(spacing: 10) {
                Text("^[\(choice.quantity) ticket](inflect: true)")
                    .font(.system(size: 15.5))
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

    /// A choice's rank, Won where it was won with, and the button that takes
    /// it out where there is another to keep.
    private func choiceHeader(_ choice: LotteryChoice, at index: Int, in entry: LotteryEntry,
                              isWon: Bool) -> some View {
        HStack(spacing: 8) {
            Text("\(LotteryChoice.ordinal(index)) Choice")
                .font(.system(size: 15, weight: .semibold))
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
                    .font(.system(size: 13))
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
            .font(.system(size: 15.5, weight: .semibold))
            .foregroundStyle(Color.trackAttended)
            if let subtitle = wonSubtitle(entry, choiceAt: index) {
                subtitle
                    .font(.system(size: 12.5))
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
                         in: .constant(PreviewData.tracking[PreviewData.events[0].id] ?? Tracking()))
    }
}
