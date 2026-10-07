import SwiftData
import SwiftUI

/// Every lottery round entered for an event still ahead, in one list — the
/// screen behind the Lotteries card on the Me tab, as `Eventrail v4.dc.html`
/// §8a draws it.
///
/// A round's result is given from the list itself — from the menu on its
/// pill, or by a swipe: Won from the leading edge, Lost from the trailing one
/// — and written down at once: the same record the ticket sheet keeps
/// (``TicketDetailsView``), which Edit Entry in that menu opens on the round's
/// own page. The rest of the card opens the event.
///
/// Two halves at the head, as My Events keeps its two — the rounds awaiting a
/// result and the ones with one — because a result given moves a round from
/// one to the other, and the half awaiting is the one to work through. The
/// order is the capsule's at the foot. A `List` rather than a scroll view of
/// cards, for the swipes.
///
/// Decided can show events that are over too, from Show Past in the same
/// capsule — off as the screen opens. Those rounds are there to be looked
/// back on: their tile opens no menu and their card no swipe, so nothing here
/// gives an event that is over a result (``LotteryRow/isOver``). One still
/// pending is No Result.
struct LotteriesView: View {
    @Environment(EventStore.self) private var store
    @Query(LibraryEntry.library) private var kept: [LibraryEntry]

    @State private var half: LotteryHalf = .awaiting
    @State private var order: LotteryOrder = .resultsDay
    /// Whether Decided shows the rounds of events that are over too — not
    /// remembered between visits, as the Passport's year is not.
    @State private var showsPast = false
    @State private var openEvent: Event?
    /// The round whose page the ticket sheet is open on.
    @State private var editing: LotteryRow?
    /// A result given that took the ticket away with a seat or a cost still
    /// written — waiting on whether to clear them too.
    @State private var held: HeldResult?
    /// The round whose Won swipe is asking which of its choices was won.
    @State private var pickingWin: LotteryRow.ID?

    private var list: LotteryList {
        LotteryList(events: store.events(of: kept, where: \.inLibrary), includingPast: true) { store.tracking(for: $0) }
    }

    var body: some View {
        let list = list
        let groups = list.groups(in: half, by: order, showingPast: showsPast)
        List {
            // A section of its own with no gap after it, as My Events keeps
            // its halves: the gap a group opens with is for the group before.
            Section {
                Picker("Lotteries", selection: $half.animation(.snappy)) {
                    ForEach(LotteryHalf.allCases) { option in
                        option.label(count: list.rows(in: option, showingPast: showsPast).count).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 20)
                .headRow(EdgeInsets(top: 8, leading: 0, bottom: 14, trailing: 0))
            }
            .listSectionSpacing(0)

            if groups.isEmpty {
                emptyState.headRow()
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        card(row)
                    }
                } header: {
                    GroupHeader(label: label(of: group.kind),
                                count: Text(verbatim: group.rows.count.formatted()),
                                tint: tint(of: group.kind))
                        .listRowInsets(GroupHeader.insets)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Inside the room the capsule leaves, so a notice — the Me card's
        // refresh can still be running — stands above the capsule.
        .refreshNotices(aboveBar: true)
        .safeAreaInset(edge: .bottom) {
            // Show Past on Decided alone: Awaiting holds nothing of an event
            // that is over.
            if !list.rows.isEmpty {
                LotteryListMenu(order: $order, showsPast: half == .decided ? $showsPast : nil)
            }
        }
        .monthSections()
        .washBackground()
        .navigationTitle("Lotteries")
        .navigationSubtitle(subtitle(list))
        .eventSheet($openEvent)
        .sheet(item: $editing) { row in
            TicketDetailsView(event: row.event, tracking: store.tracking(for: row.event), opening: row.entry)
        }
    }

    /// One round's card, and the swipes that give it a result: Won from the
    /// leading edge and Lost from the trailing one, neither while the results
    /// day is still ahead (``LotteryEntry/canBeDrawn(asOf:)``). One Won for
    /// every round: where it applied with several choices, it then asks which
    /// was won — a button per choice in the swipe was too narrow to read and
    /// too easy to miss. No swipe at all on a round of an event that is over.
    private func card(_ row: LotteryRow) -> some View {
        let entry = row.entry
        let drawable = !row.isOver && entry.canBeDrawn()
        return LotteryRoundCard(row: row) { result in
            give(result, to: row)
        } open: {
            openEvent = row.event
        } edit: {
            editing = row
        }
        .listRowInsets(EdgeInsets(top: 4.5, leading: 16, bottom: 4.5, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        // Not on a round already won: which choice it went to is put right
        // from the pill's menu.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if drawable, !entry.isWon {
                Button("Won", systemImage: "checkmark") {
                    if entry.choices.count > 1 {
                        pickingWin = row.id
                    } else {
                        give(.won(entry.choices.first?.id), to: row)
                    }
                }
                .tint(Color.trackAttended)
            }
        }
        .confirmationDialog("Which choice did you win?",
                            isPresented: Binding(get: { pickingWin == row.id },
                                                 set: { if !$0 { pickingWin = nil } }),
                            titleVisibility: .visible) {
            ForEach(Array(entry.choices.enumerated()), id: \.element.id) { index, choice in
                // The class and how many spelled out rather than through
                // ``LotteryText/won(_:)``, whose inflected count a dialog's
                // button would show unprocessed.
                Button {
                    give(.won(choice.id), to: row)
                } label: {
                    Text("\(Text("\(LotteryChoice.ordinal(index)) Choice")) · \(LotteryText.seatClass(choice.seatClass)) × \(choice.quantity)")
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if drawable, entry.outcome != .lost {
                Button("Lost", systemImage: "xmark") { give(.lost, to: row) }
                    .tint(.gray)
            }
        }
        .confirmationDialog("Clear the seat and cost too?",
                            isPresented: Binding(get: { held?.row == row.id },
                                                 set: { if !$0 { held = nil } }),
                            titleVisibility: .visible) {
            Button("Clear Seat and Cost", role: .destructive) {
                if let held { write(held.record.clearingSeatAndCost, for: row.event) }
            }
            Button("Keep Them") {
                if let held { write(held.record, for: row.event) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You no longer have a ticket for this event, so its seat and cost will not be shown.")
        }
    }

    /// Writes the result down over the record as it stands — asking first
    /// where it takes the ticket away and leaves a seat or a cost behind, as
    /// the ticket sheet asks on its checkmark.
    private func give(_ result: LotteryResult, to row: LotteryRow) {
        let before = store.tracking(for: row.event)
        let after = before.givingResult(result, toLottery: row.entry.id)
        guard after != before else { return }
        if after.leavesSeatOrCostBehind(since: before) {
            held = HeldResult(row: row.id, record: after)
        } else {
            write(after, for: row.event)
        }
    }

    private func write(_ record: Tracking, for event: Event) {
        withAnimation(.snappy) { store.setTracking(record, for: event) }
    }

    private func label(of kind: LotteryGroup.Kind) -> Text {
        switch kind {
        case .resultsOut: Text("Results Out")
        case .month(let month): Text(verbatim: month)
        case .noDay: Text("No Results Day")
        case .won: Text("Won")
        case .notWon: Text("Not Won")
        case .noResult: Text("No Result")
        }
    }

    /// The rounds with a result to write down in the app's colour, and the
    /// won in green.
    private func tint(of kind: LotteryGroup.Kind) -> Color? {
        switch kind {
        case .resultsOut: .brandTint
        case .won: .trackAttended
        case .month, .noDay, .notWon, .noResult: nil
        }
    }

    /// Centred under the halves, as the design draws an empty half: a title
    /// and a line under it.
    private var emptyState: some View {
        VStack(spacing: 8) {
            if half == .awaiting {
                Text("Nothing Awaiting")
                    .font(.system(size: 17, weight: .bold))
                Text("Enter a lottery from an event’s Ticket Details and it waits here for its results.")
            } else {
                Text("Nothing Decided Yet")
                    .font(.system(size: 17, weight: .bold))
                if showsPast {
                    Text("Rounds you record as won or lost gather here.")
                } else {
                    Text("Rounds you record as won or lost gather here until their event is over.")
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 56)
    }

    /// How many rounds the half on screen holds: awaiting, and how many of
    /// those have their results out; decided, and how many of those were won.
    private func subtitle(_ list: LotteryList) -> Text {
        let shown = list.rows(in: half, showingPast: showsPast)
        let rounds = Text("^[\(shown.count) round](inflect: true)")
        switch half {
        case .awaiting:
            let out = shown.filter { $0.isResultsOut() }.count
            let awaiting = Text("\(rounds) awaiting results")
            return out > 0 ? Text("\(awaiting) · \(out) out now") : awaiting
        case .decided:
            return Text("\(rounds) decided · \(shown.filter(\.entry.isWon).count) won")
        }
    }

    /// A result waiting on whether to clear the seat and cost it leaves
    /// behind.
    private struct HeldResult {
        let row: LotteryRow.ID
        let record: Tracking
    }
}

private extension View {
    /// A row of the list that is not a round: no background, no separator.
    func headRow(_ insets: EdgeInsets = EdgeInsets()) -> some View {
        listRowInsets(insets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// The capsule at the foot of the Lotteries screen: what it is in order of,
/// and on Decided whether events that are over are shown too — one switch,
/// as Reminders' Show Completed is.
private struct LotteryListMenu: View {
    @Binding var order: LotteryOrder
    /// Nil on Awaiting, which holds nothing of an event that is over.
    var showsPast: Binding<Bool>?

    var body: some View {
        ListMenu(describes: "Sort lotteries", value: Text(order.label)) {
            if let showsPast {
                Section {
                    Toggle(isOn: showsPast.animation(.snappy)) {
                        Label("Show Past", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
            Section("Sort") {
                ForEach(LotteryOrder.allCases) { option in
                    Toggle(isOn: menuChoice($order.animation(.snappy), option)) {
                        Label(option.label, systemImage: option.symbol)
                    }
                }
            }
        } face: {
            SortMenuFace(label: Text(order.label))
        }
    }
}

// MARK: - A round's card

/// One round on the Lotteries screen: the results day as a tile, how the
/// round went as a badge on the tile's corner — the tile is also the menu a
/// result is given from — then the round, the event it was entered for and,
/// under a hairline, three readings headed as the Passport heads its figures:
/// how many times it was entered, where the results stand, and the seats
/// applied for. With no pill beside it, the title has the card's whole width.
///
/// The card opens the event; the tile's menu sits over it rather than inside
/// it, a sibling of the card's button laid over the spot the tile holds, so a
/// tap on the tile opens its menu and not the event (``FavoriteEventRow``'s
/// heart, for the same reason). A round of an event that is over has no
/// menu: its tile is drawn in the card, and a tap anywhere opens the event.
struct LotteryRoundCard: View {
    /// Which clock the event's day is printed on — see ``TimeDisplay``.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue

    let row: LotteryRow
    /// Gives the round a result.
    let give: (LotteryResult) -> Void
    let open: () -> Void
    /// Opens the round's own page, on the ticket sheet.
    let edit: () -> Void

    private var entry: LotteryEntry { row.entry }

    var body: some View {
        let isOut = row.isResultsOut()
        Button(action: open) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 12) {
                    if row.isOver {
                        LotteryDayTile(row: row, showsResult: true)
                    } else {
                        // Holds the tile's room; the tile itself is the menu
                        // laid over this spot (``TileSpot``).
                        Color.clear
                            .frame(width: LotteryDayTile.size.width, height: LotteryDayTile.size.height)
                            .anchorPreference(key: TileSpot.self, value: .bounds) { $0 }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        LotteryText.round(of: entry)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(row.event.title)
                            .font(.system(size: 14.5, weight: .semibold))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                        // One line: a hall's full name is on the event's own
                        // sheet.
                        Text(verbatim: "\(row.event.shown(on: timeDisplay).dayLine) · \(row.event.venue)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .top, spacing: 14) {
                    reading("Entries") {
                        // A dash for "not written down", as the entry's own
                        // field shows it, rather than a count of none.
                        Text(verbatim: entry.applications > 0 ? entry.applications.formatted() : "—")
                            .font(.system(size: 19, weight: .bold))
                            .kerning(-0.38)
                            .monospacedDigit()
                    }
                    .frame(width: 54, alignment: .leading)

                    reading("Results") {
                        results(isOut: isOut)
                            .font(.system(size: 13.5, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(isOut ? AnyShapeStyle(Color.brandTint) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                    }
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.separator).frame(width: 0.5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Not headed where there is nothing under it: a round
                    // carried over from a count names no seats.
                    if !entry.choices.isEmpty {
                        reading("Seats", alignment: .trailing) { choiceChips }
                    }
                }
                .padding(.top, 11)
                .overlay(alignment: .top) {
                    Rectangle().fill(.separator).frame(height: 0.5)
                }
            }
            .padding(14)
            .background(isOut ? Color.brandTint.opacity(0.07) : .clear,
                        in: .rect(cornerRadius: 24, style: .continuous))
            .contentShape(.rect(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlayPreferenceValue(TileSpot.self) { spot in
            GeometryReader { proxy in
                if let spot {
                    let frame = proxy[spot]
                    resultMenu
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .glassPanel(cornerRadius: 24)
    }

    /// One reading in the card's foot: what it is, small and in capitals,
    /// over its value.
    private func reading<Value: View>(
        _ title: LocalizedStringKey,
        alignment: HorizontalAlignment = .leading,
        @ViewBuilder value: () -> Value
    ) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.57)
                .foregroundStyle(Color.primary.opacity(0.48))
            value()
                .frame(height: 20)
        }
    }

    /// Where the results stand: how far off the day is, or how long ago it
    /// was — out and waiting to be written down while nothing is — or that no
    /// day was announced. No Result for one nobody answered before its event
    /// was over.
    private func results(isOut: Bool) -> Text {
        if row.isOver, entry.isPending { return Text("No Result") }
        guard let day = entry.day else { return Text("Not announced") }
        if isOut { return Text("Out — record it") }
        return Text(verbatim: LotteryText.relativeStandalone(day))
    }

    /// The choices in order, small — the class's badge and how many — the one
    /// it was won with in green and the rest dimmed once the result is in.
    private var choiceChips: some View {
        HStack(spacing: 4) {
            ForEach(entry.choices) { choice in
                let isWon = entry.outcome == .won(choice.id)
                HStack(spacing: 2) {
                    SeatClass(rawValue: choice.seatClass)?.badge
                        ?? Text(verbatim: choice.seatClass.first.map(String.init) ?? "?")
                    Text(verbatim: "×\(choice.quantity)")
                }
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isWon ? Color.trackAttended : Color.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(isWon ? Color.trackAttended.opacity(0.14) : TicketForm.controlFill.opacity(0.6),
                            in: .rect(cornerRadius: 7, style: .continuous))
                .opacity((entry.isPending && !row.isOver) || isWon ? 1 : 0.45)
            }
        }
        .fixedSize()
    }

    /// The tile, with how the round went on its corner, opening Pending, Won —
    /// with which choice, where there was more than one — and Lost, as the
    /// round's own page offers them, then the way to that page. While the
    /// results day is still to come only Pending can be picked, and it says
    /// when that day is.
    private var resultMenu: some View {
        let drawable = entry.canBeDrawn()
        return Menu {
            Section("Result") {
                Toggle(isOn: given(.pending)) {
                    Text("Pending")
                    if !drawable { LotteryText.day(of: entry, isEventAhead: true) }
                }
                if entry.choices.isEmpty {
                    Toggle(isOn: given(.won(nil))) { Text("Won") }
                        .disabled(!drawable)
                }
                ForEach(Array(entry.choices.enumerated()), id: \.element.id) { index, choice in
                    Toggle(isOn: given(.won(choice.id))) {
                        if entry.choices.count > 1 {
                            Text("Won \(LotteryChoice.ordinal(index)) Choice")
                        } else {
                            Text("Won")
                        }
                        LotteryText.won(choice)
                    }
                    .disabled(!drawable)
                }
                Toggle(isOn: given(.lost)) { Text("Lost") }
                    .disabled(!drawable)
            }
            Section {
                Button("Edit Entry", systemImage: "square.and.pencil", action: edit)
            }
        } label: {
            LotteryDayTile(row: row, showsResult: true)
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Result"))
        .accessibilityValue(LotteryText.result(entry.outcome, firstCome: false))
        .sensoryFeedback(.selection, trigger: entry.outcome)
    }

    /// On where it is the round's result, and a tap on it gives it.
    private func given(_ result: LotteryResult) -> Binding<Bool> {
        Binding(
            get: { entry.outcome == result },
            set: { isOn in if isOn { give(result) } }
        )
    }
}

/// Where a round card's tile stands, for its menu to be laid over.
private struct TileSpot: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: - The results day

/// A round's results day as a page off a calendar: the month over the day,
/// in the colour of where the round stands — filled in the app's colour once
/// the day has come and nothing is written down, green once won, grey once
/// lost — or a dashed outline where no day was announced.
struct LotteryDayTile: View {
    let row: LotteryRow
    /// Whether how the round went sits on the tile's corner — on the
    /// Lotteries screen, where the tile is the menu a result is given from.
    var showsResult = false

    static let size = CGSize(width: 42, height: 46)

    var body: some View {
        let look = self.look
        VStack(spacing: 3) {
            Group {
                if let day = row.entry.day {
                    Text(verbatim: day.date().formatted(.dateTime.month(.abbreviated)))
                } else {
                    // A key of its own: "Day" alone is the Passport's, and reads
                    // differently there.
                    Text(String(localized: "lottery.tile.noDay", defaultValue: "Day",
                                comment: "Over a question mark, on a lottery round's tile where no results day was announced."))
                }
            }
            .font(.system(size: 9.5, weight: .bold))
            .textCase(.uppercase)
            .kerning(0.57)
            .foregroundStyle(look.sub)
            Text(verbatim: row.entry.day.map { $0.day.formatted() } ?? "?")
                .font(.system(size: 18, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(look.fill)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(look.background, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay {
            if row.entry.day == nil {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.28), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5]))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsResult { resultBadge.offset(x: 7, y: -7) }
        }
        .accessibilityHidden(true)
    }

    /// How the round went, as the pill used to say it: a hourglass in blue
    /// while it waits, a tick in green once won, a cross in grey once lost —
    /// on a disc ringed in the page's own colour, so it stands off the tile.
    /// A dash in grey for one still pending once its event is over, as the
    /// ticket sheet marks No Result.
    private var resultBadge: some View {
        let (symbol, tint): (String, Color) = switch row.entry.outcome {
        case .pending where row.isOver: ("minus", Color(.systemGray))
        case .pending: ("hourglass", .trackInterest)
        case .won: ("checkmark", .trackAttended)
        case .lost: ("xmark", Color(.systemGray))
        }
        return Image(systemName: symbol)
            .font(.system(size: 8.5, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(tint, in: .circle)
            .overlay { Circle().strokeBorder(Color.washBase, lineWidth: 2) }
            .shadow(color: Color(red: 30 / 255, green: 27 / 255, blue: 45 / 255).opacity(0.18), radius: 3, y: 2)
    }

    /// The day's colour, the month's over it, and the tile under both.
    private var look: (fill: AnyShapeStyle, sub: AnyShapeStyle, background: AnyShapeStyle) {
        if row.entry.day == nil {
            return (AnyShapeStyle(.secondary), AnyShapeStyle(.secondary), AnyShapeStyle(.clear))
        }
        if row.isResultsOut() {
            return (AnyShapeStyle(.white), AnyShapeStyle(.white.opacity(0.8)), AnyShapeStyle(Color.brandTint))
        }
        switch row.entry.outcome {
        case .won:
            return (AnyShapeStyle(Color.trackAttended), AnyShapeStyle(Color.trackAttended),
                    AnyShapeStyle(Color.trackAttended.opacity(0.14)))
        case .pending where row.isOver, .lost:
            return (AnyShapeStyle(.secondary), AnyShapeStyle(.secondary), AnyShapeStyle(Color.primary.opacity(0.06)))
        case .pending:
            return (AnyShapeStyle(.primary), AnyShapeStyle(Color.brandTint),
                    AnyShapeStyle(TicketForm.controlFill.opacity(0.55)))
        }
    }
}

// MARK: - The Me card's row

/// One round awaiting its result, on the Lotteries card on the Me tab: its
/// results day as a tile, the event and the round, and how far off the day
/// is — or that the results are out.
struct LotteryCardRow: View {
    /// What stands where these rows would, when there are none.
    static let emptyNote: LocalizedStringKey = "Rounds you enter for an upcoming event wait here for their results."

    let row: LotteryRow
    var showsDivider = false
    let open: () -> Void

    var body: some View {
        let isOut = row.isResultsOut()
        Button(action: open) {
            HStack(spacing: 12) {
                LotteryDayTile(row: row)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.event.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    LotteryText.roundLine(of: row.entry)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                when(isOut: isOut)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isOut ? AnyShapeStyle(Color.brandTint) : AnyShapeStyle(.secondary))
                    .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if showsDivider { Divider().padding(.leading, 70) }
        }
    }

    private func when(isOut: Bool) -> Text {
        guard let day = row.entry.day else { return Text("Not Set") }
        return isOut ? Text("Results out") : Text(verbatim: LotteryText.relativeStandalone(day))
    }
}

extension LotteryText {
    /// The round, and how many times it was applied for where that is
    /// written down — "Earliest Presale Lottery · 3 entries".
    static func roundLine(of entry: LotteryEntry) -> Text {
        let round = round(of: entry)
        guard entry.applications > 0 else { return round }
        return Text("\(round) · \(Text("^[\(entry.applications) entry](inflect: true)"))")
    }
}

#Preview {
    NavigationStack {
        LotteriesView()
    }
    .library(EventStore.preview)
}
