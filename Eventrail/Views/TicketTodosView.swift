import SwiftData
import SwiftUI

/// Everything a ticket still asks of the reader, in one list — the screen
/// behind the Ticket To-Dos card on the Me tab, as the design's Ticket To-Dos
/// row draws it (`TodoHub.dc.html`, `TodoDone.dc.html`).
///
/// Two halves at the head, as the Lotteries screen keeps its two: what is
/// still to do, by how soon, and what is done, by month. A card opens the
/// to-do's own sheet (``TicketTodoSheet``); its button marks the step reached
/// there and then, which stops that step's reminder, and a pill at the foot
/// takes it back. A done row swipes back to To Do, a step at a time.
///
/// A `List`, for the swipes. Nothing is kept for it: see ``TicketTodo``.
struct TicketTodosView: View {
    @Environment(EventStore.self) private var store
    /// Declared to be drawn again as the day turns — see ``EnvironmentValues/today``.
    @Environment(\.today) private var today
    @Query(LibraryEntry.library) private var kept: [LibraryEntry]
    /// Which clock the deadlines are printed on — see ``TimeDisplay``.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue

    private enum Half: CaseIterable, Identifiable {
        case toDo, done

        var id: Self { self }

        var label: LocalizedStringKey {
            switch self {
            case .toDo: "To Do"
            case .done: "Done"
            }
        }
    }

    @State private var half = Half.toDo
    /// The chip the list is held to, or nil for all of them. Not remembered.
    @State private var kind: TicketTodo.Kind?
    @State private var opened: TicketTodoLink?
    @State private var isAdding = false
    @State private var undo: TicketTodoUndo?

    private var library: [Event] { store.events(of: kept, where: \.inLibrary) }

    var body: some View {
        let library = library
        let list = TicketTodoList(events: library) { store.tracking(for: $0) }
        // A step is written for a round won, on an event still ahead.
        let ahead = library.filter(\.isUpcoming).sorted { $0.sortDate < $1.sortDate }
            .filter { !TicketDeadlineView.wins(in: store.tracking(for: $0)).isEmpty }
        List {
            // A section of its own with no gap after it, as the Lotteries
            // screen keeps its halves.
            Section {
                Picker("Ticket To-Dos", selection: $half.animation(.snappy)) {
                    ForEach(Half.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 20)
                .headRow(EdgeInsets(top: 8, leading: 0, bottom: 14, trailing: 0))
                if half == .toDo, !list.open.isEmpty {
                    chips(list)
                        .headRow(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                }
            }
            .listSectionSpacing(0)

            switch half {
            case .toDo: toDo(list)
            case .done: done(list)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshNotices(aboveBar: undo != nil)
        .safeAreaInset(edge: .bottom) {
            if let undo {
                TicketTodoUndoPill(undo: undo) { self.undo = nil }
                    .padding(.bottom, 8)
            }
        }
        .monthSections()
        .washBackground()
        .navigationTitle("Ticket To-Dos")
        .navigationSubtitle(subtitle(list))
        .largeTitleOnMac(Text("Ticket To-Dos"), subtitle: subtitle(list))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Deadline", systemImage: "plus") { isAdding = true }
                    .disabled(ahead.isEmpty)
            }
        }
        .sheet(item: $opened) { link in
            TicketTodoSheet(todo: link.id)
                .macSheetSize(.form)
        }
        .sheet(isPresented: $isAdding) {
            TicketDeadlineView(events: ahead) { store.tracking(for: $0) }
                .macSheetSize(.form)
        }
    }

    // MARK: - To do

    @ViewBuilder
    private func toDo(_ list: TicketTodoList) -> some View {
        let groups = list.groups(of: kind)
        if groups.isEmpty {
            emptyState.headRow()
        }
        ForEach(groups, id: \.bucket) { group in
            Section {
                ForEach(group.todos) { todo in
                    TicketTodoCard(todo: todo, clock: timeDisplay, isSoon: group.bucket != .later) {
                        opened = TicketTodoLink(id: todo.id)
                    } mark: {
                        mark(todo)
                    }
                    .cardRow()
                }
            } header: {
                GroupHeader(label: label(of: group.bucket),
                            count: Text(verbatim: group.todos.count.formatted()),
                            tint: group.bucket == .dueSoon ? .red : nil)
                    .listRowInsets(GroupHeader.insets)
            }
        }
        if !groups.isEmpty {
            note("Deadlines come from the rounds you won, on each event's Ticket Details. Marking a step done stops its notification — undo brings it back.")
        }
    }

    /// The chips the list is held to: all of them, or what is asked for next.
    /// Each says how many it holds; one that holds none is left out.
    private func chips(_ list: TicketTodoList) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(nil, count: list.open.count)
                ForEach(TicketTodo.Kind.allCases) { option in
                    let count = list.open(of: option).count
                    if count > 0 || kind == option { chip(option, count: count) }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ option: TicketTodo.Kind?, count: Int) -> some View {
        let isOn = kind == option
        return Button {
            withAnimation(.snappy) { kind = option }
        } label: {
            HStack(spacing: 6) {
                if let option {
                    Image(systemName: TicketTodoText.symbol(of: option))
                        .font(.system(size: 12, weight: .semibold))
                    Text(TicketTodoText.chip(option))
                } else {
                    Text("All")
                }
                Text(count, format: .number)
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .opacity(0.75)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isOn ? AnyShapeStyle(Color(.systemBackground))
                             : AnyShapeStyle(option.map(TicketTodoText.tint) ?? .primary))
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background {
                if isOn { Capsule().fill(Color.primary) }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .capsulePanel()
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func label(of bucket: TicketTodoList.Bucket) -> Text {
        switch bucket {
        case .dueSoon: Text("Due Soon")
        case .thisWeek: Text("This Week")
        case .later: Text("Later")
        }
    }

    private func mark(_ todo: TicketTodo) {
        withAnimation(.snappy) { undo = store.advance(todo) ?? undo }
    }

    // MARK: - Done

    @ViewBuilder
    private func done(_ list: TicketTodoList) -> some View {
        let months = list.doneByMonth()
        if months.isEmpty {
            emptyState.headRow()
        }
        ForEach(months, id: \.month) { month in
            Section {
                ForEach(month.todos) { todo in
                    TicketTodoDoneRow(todo: todo, clock: timeDisplay) {
                        opened = TicketTodoLink(id: todo.id)
                    }
                    .cardRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Back to To Do", systemImage: "arrow.uturn.backward") { stepBack(todo) }
                            .tint(Color.brandTint)
                    }
                    .contextMenuOnMac {
                        Button("Back to To Do", systemImage: "arrow.uturn.backward") { stepBack(todo) }
                    }
                }
            } header: {
                GroupHeader(label: Text(verbatim: month.month.formatted(.gregorian().month(.wide).year()).localizedUppercase),
                            count: Text(verbatim: month.todos.count.formatted()))
                    .listRowInsets(GroupHeader.insets)
            }
        }
        if !months.isEmpty {
            note("Swipe a row to move it back to To Do — its reminders come back for any time still ahead.")
        }
    }

    private func stepBack(_ todo: TicketTodo) {
        withAnimation(.snappy) { store.stepBack(todo) }
    }

    // MARK: - Around the list

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .scalingFont(size: 12.5)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .headRow(EdgeInsets(top: 10, leading: 22, bottom: 24, trailing: 22))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if half == .toDo {
                Text("Nothing to Do")
                    .scalingFont(size: 17, weight: .bold)
                if kind == nil {
                    Text("Add a deadline to pay for or pick up a ticket you won, and it waits here until you have done it.")
                } else {
                    Text("Nothing of this kind is waiting.")
                }
            } else {
                Text("Nothing Done Yet")
                    .scalingFont(size: 17, weight: .bold)
                Text("Steps you mark as paid or issued gather here.")
            }
        }
        .scalingFont(size: 13)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 56)
    }

    private func subtitle(_ list: TicketTodoList) -> Text {
        switch half {
        case .toDo:
            let open = Text("\(list.open.count) to do")
            let urgent = list.urgent().count
            return urgent > 0 ? Text("\(open) · \(Text("\(urgent) due soon"))") : open
        case .done:
            return Text("\(list.done.count) done · \(Text("^[\(list.stoppedReminders) reminder](inflect: true) stopped"))")
        }
    }
}

/// A to-do named for a sheet to open on: by id, so the sheet reads it as it
/// stands rather than as it stood when it was tapped.
struct TicketTodoLink: Identifiable, Hashable {
    let id: TicketTodo.ID
}

private extension View {
    /// A row of the list that is not a to-do: no background, no separator.
    func headRow(_ insets: EdgeInsets = EdgeInsets()) -> some View {
        listRowInsets(insets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// A row that is a card of its own.
    func cardRow() -> some View {
        listRowInsets(EdgeInsets(top: 4.5, leading: 16, bottom: 4.5, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - A to-do's card

/// One to-do still open: what it asks and how long is left, the event, the
/// deadline with its alert, where the ticket stands, and the button that
/// marks the step reached. The card above the button opens the to-do's sheet.
struct TicketTodoCard: View {
    let todo: TicketTodo
    let clock: TimeDisplay
    /// Whether its button is filled: the ones to deal with first.
    let isSoon: Bool
    let open: () -> Void
    let mark: () -> Void

    var body: some View {
        let tint = TicketTodoText.tint(of: todo.kind)
        let isUrgent = todo.isUrgent()
        VStack(alignment: .leading, spacing: 12) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TicketTodoBadge(kind: todo.kind)
                        Spacer(minLength: 8)
                        TicketTodoText.due(of: todo)
                            .font(.system(size: 13, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(isUrgent ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    }
                    HStack(spacing: 11) {
                        FlyerThumbnail(url: todo.event.imageURL, width: 34, cornerRadius: 8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(todo.event.title)
                                .scalingFont(size: 14.5, weight: .semibold)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                            Text(verbatim: "\(todo.event.shown(on: clock).dayLine) · \(todo.event.venue)")
                                .lineLimit(1)
                            if let detail = TicketTodoText.detail(of: todo) {
                                detail.lineLimit(1)
                            }
                        }
                        .scalingFont(size: 12)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if let current = todo.current {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .foregroundStyle(tint)
                    TicketTodoText.when(current, of: todo, on: clock)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let lead = TicketTodoText.lead(of: current) {
                        Image(systemName: "bell")
                        Text(verbatim: ReminderLead.label(of: lead))
                    } else {
                        Image(systemName: "bell.slash")
                            .accessibilityLabel(Text("No Alert"))
                    }
                }
                .scalingFont(size: 12.5)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(TicketForm.controlFill.opacity(0.7), in: .rect(cornerRadius: 14, style: .continuous))
            }

            TicketTodoStepper(steps: todo.steps, tint: tint)
                .padding(.top, 2)

            if let action = TicketTodoText.action(of: todo) {
                Button(action: mark) {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark").fontWeight(.bold)
                        action
                    }
                        .font(.system(size: 14.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .foregroundStyle(isSoon ? Color.white : Color.brandTint)
                        .background(isSoon ? Color.brandTint : Color.brandTint.opacity(0.12), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .panel(cornerRadius: 24)
        .overlay {
            if isUrgent {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.45), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// What a to-do asks for, as a small tinted capsule: Application, Payment,
/// Ticket Pickup.
struct TicketTodoBadge: View {
    let kind: TicketTodo.Kind

    var body: some View {
        let tint = TicketTodoText.tint(of: kind)
        HStack(spacing: 5) {
            Image(systemName: TicketTodoText.symbol(of: kind))
            Text(TicketTodoText.name(of: kind))
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(tint)
        .padding(.leading, 7)
        .padding(.trailing, 9)
        .frame(height: 24)
        .background(tint.opacity(0.12), in: .capsule)
    }
}

/// Where a ticket stands, as dots along a line: the steps behind it ticked,
/// the one it stands on ringed, the rest grey.
struct TicketTodoStepper: View {
    let steps: [TicketTodo.Step]
    /// The colour of the step it stands on.
    let tint: Color

    private static let dot: CGFloat = 18

    var body: some View {
        let reached = steps.lastIndex { $0.status != .ahead } ?? 0
        // Green behind it, whatever it is waiting on.
        let behind = Color.trackAttended
        HStack(alignment: .top, spacing: 0) {
            ForEach(steps) { step in
                VStack(spacing: 6) {
                    dot(step, behind: behind)
                    TicketTodoText.name(of: step.name)
                        .font(.system(size: 11, weight: step.status == .now ? .bold : .medium))
                        .foregroundStyle(step.status == .now ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(alignment: .top) {
            GeometryReader { proxy in
                let inset = proxy.size.width / CGFloat(max(steps.count, 1)) / 2
                let run = max(proxy.size.width - inset * 2, 0)
                let fraction = steps.count > 1 ? CGFloat(reached) / CGFloat(steps.count - 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray4)).frame(width: run)
                    Capsule().fill(behind).frame(width: run * fraction)
                }
                .frame(height: 3)
                .offset(x: inset, y: (Self.dot - 3) / 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Progress"))
        .accessibilityValue(TicketTodoText.name(of: steps.first { $0.status == .now }?.name
                                                    ?? steps.last?.name ?? .issued))
    }

    @ViewBuilder
    private func dot(_ step: TicketTodo.Step, behind: Color) -> some View {
        switch step.status {
        case .done:
            Image(systemName: step.name == .notPaid ? "xmark" : "checkmark")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: Self.dot, height: Self.dot)
                .background(step.name == .notPaid ? Color(.systemGray) : behind, in: .circle)
        case .now:
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .frame(width: Self.dot, height: Self.dot)
                .background(TicketForm.controlFill, in: .circle)
                .overlay { Circle().strokeBorder(tint, lineWidth: 2.5) }
        case .ahead:
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: Self.dot, height: Self.dot)
        }
    }
}

// MARK: - A done row

/// One to-do dealt with: how it ended and when, the event, what it was for,
/// and how many reminders that stopped.
struct TicketTodoDoneRow: View {
    let todo: TicketTodo
    let clock: TimeDisplay
    let open: () -> Void

    var body: some View {
        let state = todo.state
        let tint: Color = state == .notPaid ? Color(.systemGray) : .trackAttended
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: state == .notPaid ? "xmark" : "checkmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.13), in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    finished(state)
                        .scalingFont(size: 12, weight: .bold)
                        .foregroundStyle(tint)
                    Text(todo.event.title)
                        .scalingFont(size: 14, weight: .semibold)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    if let detail = TicketTodoText.detail(of: todo) {
                        detail
                            .scalingFont(size: 12)
                            .lineLimit(1)
                    }
                    if todo.stoppedReminders > 0 {
                        HStack(spacing: 5) {
                            Image(systemName: "bell.slash")
                            Text("^[\(todo.stoppedReminders) reminder](inflect: true) stopped")
                        }
                        .scalingFont(size: 11.5)
                    }
                }
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .scalingFont(size: 11, weight: .bold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .contentShape(.rect(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .panel(cornerRadius: 24)
    }

    /// "Issued · Nov 7".
    private func finished(_ state: TicketTodo.State) -> Text {
        guard let finished = todo.finished else { return TicketTodoText.name(of: state) }
        let zone = clock == .local ? TimeZone.current : todo.event.timeZone
        return Text("\(TicketTodoText.name(of: state)) · \(finished.formatted(.gregorian(in: zone).month(.abbreviated).day()))")
    }
}

// MARK: - The Me card's row

/// One to-do on the Ticket To-Dos card on the Me tab: the day it falls on as
/// a tile — red where a deadline is close — what it asks, the event, how long
/// is left, and a round button that marks the step reached.
struct TicketTodoCardRow: View {
    /// What stands where these rows would, when there are none.
    static let emptyNote: LocalizedStringKey = "Deadlines to pay for or pick up a ticket you won wait here until you mark them done."

    let todo: TicketTodo
    let clock: TimeDisplay
    var showsDivider = false
    let open: () -> Void
    let mark: () -> Void

    var body: some View {
        let tint = TicketTodoText.tint(of: todo.kind)
        let isUrgent = todo.isUrgent()
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    tile(tint: tint, isUrgent: isUrgent)
                    VStack(alignment: .leading, spacing: 3) {
                        TicketTodoText.headline(of: todo)
                            .scalingFont(size: 11.5, weight: .bold)
                            .foregroundStyle(tint)
                            .lineLimit(1)
                        Text(todo.event.title)
                            .scalingFont(size: 14, weight: .semibold)
                            .lineLimit(1)
                        if let current = todo.current, let clockLine = TicketTodoText.time(current, of: todo, on: clock) {
                            Text("\(TicketTodoText.due(of: todo)) · \(clockLine)")
                                .scalingFont(size: 11.5, weight: .semibold)
                                .monospacedDigit()
                                .foregroundStyle(isUrgent ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                                .lineLimit(1)
                        } else if todo.current != nil {
                            TicketTodoText.due(of: todo)
                                .scalingFont(size: 11.5, weight: .semibold)
                                .monospacedDigit()
                                .foregroundStyle(isUrgent ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)

            if let action = TicketTodoText.action(of: todo) {
                Button(action: mark) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 38, height: 38)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .circlePanel()
                .accessibilityLabel(action)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            if showsDivider { Divider().padding(.leading, 70) }
        }
    }

    /// The day as a page off a calendar, as a lottery's results day is drawn
    /// (``LotteryDayTile``), on the clock the rest is printed on.
    private func tile(tint: Color, isUrgent: Bool) -> some View {
        let zone = clock == .local ? TimeZone.current : todo.event.timeZone
        let due = todo.due ?? todo.event.date
        return VStack(spacing: 3) {
            Text(verbatim: due.formatted(.gregorian(in: zone).month(.abbreviated)))
                .font(.system(size: 9.5, weight: .bold))
                .textCase(.uppercase)
                .kerning(0.57)
                .foregroundStyle(isUrgent ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(tint.opacity(0.8)))
            Text(verbatim: due.formatted(.gregorian(in: zone).day()))
                .font(.system(size: 18, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isUrgent ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(width: LotteryDayTile.size.width, height: LotteryDayTile.size.height)
        .background(isUrgent ? AnyShapeStyle(Color.red) : AnyShapeStyle(tint.opacity(0.13)),
                    in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - On Ticket Details

/// Where one ticket stands, on Ticket Details: a step to pick, and under it
/// the deadlines the steps stand for. It only hands the pick over — the sheet
/// holds a copy, and writes it on its checkmark.
struct TicketProgressSection: View {
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue

    let todo: TicketTodo
    let pick: (TicketTodo.State) -> Void

    /// The steps that can be picked: where it was never paid, the three it
    /// would have gone through.
    private var choices: [TicketTodo.State] {
        guard todo.state != .notPaid else {
            return [.awaitingPayment, .paid] + (todo.pickup == nil ? [] : [.issued])
        }
        return todo.steps.map(\.name)
    }

    var body: some View {
        TicketForm.section("Progress") {
            if todo.state == .notPaid {
                TicketTodoText.name(of: .notPaid)
                    .scalingFont(size: 13, weight: .medium)
                    .foregroundStyle(.secondary)
            }
        } content: {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(choices, id: \.self) { state in
                        segment(state)
                    }
                }
                .padding(10)
                ForEach(todo.stages, id: \.self) { stage in
                    deadline(stage)
                        .overlay(alignment: .top) { Divider().padding(.leading, 15) }
                }
            }
            .background(TicketForm.fieldFill, in: .rect(cornerRadius: 18, style: .continuous))
            Text("Pick where the ticket stands. Each step you reach stops its notification — the same as in Ticket To-Dos.")
                .scalingFont(size: 12.5)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func segment(_ state: TicketTodo.State) -> some View {
        let isOn = todo.state == state
        let (symbol, tint): (String, Color) = switch state {
        case .paid: (TicketTodoText.symbol(of: .pay), .brandTint)
        case .issued: (TicketTodoText.symbol(of: .pickUp), .trackAttended)
        default: ("clock", .trackTicket)
        }
        return Button {
            pick(state)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                TicketTodoText.name(of: state)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 12, style: .continuous))
            .contentShape(.rect(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func deadline(_ stage: TicketStage) -> some View {
        let isStopped = todo.entry[stage]?.done != nil
        let lead = TicketTodoText.lead(of: stage)
        return HStack(spacing: 11) {
            Image(systemName: isStopped || lead == nil ? "bell.slash" : "bell")
                .scalingFont(size: 15)
                .foregroundStyle(isStopped ? AnyShapeStyle(.tertiary)
                                 : AnyShapeStyle(stage == .payment ? Color.trackTicket : Color.trackAttended))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                TicketTodoText.when(stage, of: todo, on: timeDisplay)
                    .scalingFont(size: 14.5)
                    .strikethrough(isStopped)
                    .foregroundStyle(isStopped ? .secondary : .primary)
                Group {
                    if isStopped {
                        Text("Reminder stopped")
                    } else if let lead {
                        Text(verbatim: ReminderLead.label(of: lead))
                    } else {
                        Text("No Alert")
                    }
                }
                .scalingFont(size: 12)
                .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
            if stage == .payment, let total = todo.total {
                Text(verbatim: total.formatted)
                    .scalingFont(size: 14.5, weight: .semibold)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
    }
}

// MARK: - Taking a mark back

/// A step just marked, for as long as the pill that takes it back stands.
struct TicketTodoUndo: Identifiable, Equatable {
    let id = UUID()
    let event: Event
    /// The round before the mark and after it: taking it back puts back only
    /// the marks it changed, on the round as it then stands
    /// (``LotteryEntry/takeBack(marksFrom:to:)``), so nothing written
    /// meanwhile goes with it — not a deadline or an amount changed on
    /// another device, nor the round taken out.
    let before: LotteryEntry
    let after: LotteryEntry
    /// Where the mark left the to-do.
    let state: TicketTodo.State
    /// How many reminders it stopped.
    let stopped: Int

    static func == (lhs: TicketTodoUndo, rhs: TicketTodoUndo) -> Bool { lhs.id == rhs.id }
}

extension EventStore {
    /// Marks the step `todo` is waiting on as reached, and answers how to
    /// take that back — nil where there was nothing to mark.
    @discardableResult
    func advance(_ todo: TicketTodo) -> TicketTodoUndo? {
        write(todo) { $0.advanced(in: $1) }
    }

    /// Marks `todo`'s payment as not made in time.
    @discardableResult
    func giveUp(_ todo: TicketTodo) -> TicketTodoUndo? {
        write(todo) { $0.givenUp(in: $1) }
    }

    /// Takes `todo`'s last step back.
    func stepBack(_ todo: TicketTodo) {
        write(todo) { $0.steppedBack(in: $1) }
    }

    /// Takes a mark back, over the record as it now stands.
    func take(back undo: TicketTodoUndo) {
        let record = tracking(for: undo.event)
        let restored = record.updatingLottery(undo.before.id) { $0.takeBack(marksFrom: undo.after, to: undo.before) }
        guard restored != record else { return }
        setTracking(restored, for: undo.event)
    }

    /// Over the record as it stands, and the to-do as it stands in it: the
    /// one handed over may have been drawn a moment ago.
    @discardableResult
    private func write(_ todo: TicketTodo, _ change: (TicketTodo, Tracking) -> Tracking) -> TicketTodoUndo? {
        let before = tracking(for: todo.event)
        guard let standing = TicketTodoList.todos(for: todo.event, tracking: before).first(where: { $0.id == todo.id })
        else { return nil }
        let after = change(standing, before)
        guard after != before,
              let markedRound = after.lotteries.first(where: { $0.id == standing.entry.id })
        else { return nil }
        setTracking(after, for: todo.event)
        let moved = TicketTodoList.todos(for: todo.event, tracking: after).first { $0.id == todo.id }
        return TicketTodoUndo(event: todo.event, before: standing.entry, after: markedRound,
                              state: moved?.state ?? standing.state,
                              stopped: max(0, (moved?.stoppedReminders ?? 0) - standing.stoppedReminders))
    }
}

/// What was just marked, and the button that takes it back: over the foot of
/// the list or the sheet for a few seconds, then gone.
struct TicketTodoUndoPill: View {
    @Environment(EventStore.self) private var store

    let undo: TicketTodoUndo
    let dismiss: () -> Void

    /// How long it stands.
    private static let patience: Duration = .seconds(6)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: undo.state == .notPaid ? "xmark" : "checkmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(undo.state == .notPaid ? Color.secondary : Color.trackAttended)
            words
                .font(.system(size: 13.5, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Button {
                withAnimation(.snappy) {
                    store.take(back: undo)
                    dismiss()
                }
            } label: {
                Text("Undo")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.brandTint)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Color.brandTint.opacity(0.14), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 44)
        .glassCapsule()
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: undo.id) {
            try? await Task.sleep(for: Self.patience)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { dismiss() }
        }
        .accessibilityElement(children: .contain)
    }

    private var words: Text {
        let marked: Text = switch undo.state {
        case .paid: Text("Marked as paid")
        case .issued: Text("Marked as issued")
        case .notPaid: Text("Marked as not paid")
        default: Text("Marked")
        }
        guard undo.stopped > 0 else { return marked }
        return Text("\(marked) · \(Text("^[\(undo.stopped) reminder](inflect: true) stopped"))")
    }
}

// MARK: - The words

/// How a to-do is named, tinted and timed, wherever one is drawn.
enum TicketTodoText {
    static func symbol(of kind: TicketTodo.Kind) -> String {
        switch kind {
        case .pay: "yensign"
        case .pickUp: "ticket"
        }
    }

    /// Amber to pay, green to pick up: the colours the app already gives a
    /// ticket and having been.
    static func tint(of kind: TicketTodo.Kind) -> Color {
        switch kind {
        case .pay: .trackTicket
        case .pickUp: .trackAttended
        }
    }

    /// A chip's word: what there is to do.
    static func chip(_ kind: TicketTodo.Kind) -> LocalizedStringKey {
        switch kind {
        case .pay: "Pay"
        case .pickUp: "Pick Up"
        }
    }

    /// A card's badge, and its sheet's title: what it is about.
    static func name(of kind: TicketTodo.Kind) -> LocalizedStringKey {
        switch kind {
        case .pay: "Payment"
        case .pickUp: "Ticket Pickup"
        }
    }

    static func name(of state: TicketTodo.State) -> Text {
        switch state {
        case .awaitingPayment: Text("Awaiting Payment")
        case .paid: Text("Paid")
        case .awaitingPickup: Text("Not Issued")
        case .issued: Text("Issued")
        case .notPaid: Text("Not Paid")
        }
    }

    /// What its button does, or nil once there is nothing left to mark.
    static func action(of todo: TicketTodo) -> Text? {
        switch todo.state {
        case .awaitingPayment: Text("Mark as Paid")
        case .paid where todo.pickup != nil: Text("Mark as Issued")
        case .awaitingPickup: Text("Mark as Issued")
        default: nil
        }
    }

    /// How far ahead of `stage` its notification comes, as Settings says —
    /// nil where none will (``TicketStageAlert/lead(of:paymentLead:)``).
    @MainActor
    static func lead(of stage: TicketStage) -> Int? {
        let reminders = LotteryReminders.shared
        guard reminders.isEnabled else { return nil }
        return TicketStageAlert.lead(of: stage, paymentLead: reminders.deadlineLead)
    }

    /// The Me card's line over the title: "Pay ¥17,600", "Pick Up · Paid".
    static func headline(of todo: TicketTodo) -> Text {
        let word = Text(chip(todo.kind))
        switch todo.kind {
        case .pay:
            if let total = todo.total { return Text("\(word) \(total.formatted)") }
        case .pickUp:
            if todo.state == .paid { return Text("\(word) · \(name(of: .paid))") }
        }
        return word
    }

    /// What it is for, under the event: the round, what was won, what it
    /// costs — as much of that as is written.
    static func detail(of todo: TicketTodo) -> Text? {
        var parts: [Text] = []
        if !todo.entry.round.isEmpty {
            parts.append(Text(verbatim: LotteryRound.label(of: todo.entry.round)))
        }
        if let choice = todo.entry.wonChoice { parts.append(LotteryText.won(choice)) }
        if let total = todo.total { parts.append(Text(verbatim: total.formatted)) }
        guard var line = parts.first else { return nil }
        for part in parts.dropFirst() { line = Text("\(line) · \(part)") }
        return line
    }

    /// "Fri, Nov 13 · 23:59", or the day alone where no time was written,
    /// on `clock`.
    static func moment(_ stage: TicketStage, of todo: TicketTodo, on clock: TimeDisplay) -> String {
        guard let date = todo.date(of: stage) else { return "" }
        let event = todo.event
        guard let shown = Self.time(stage, of: todo, on: clock) else {
            // A day alone is the hall's day whatever the clock.
            return date.formatted(.gregorian(in: event.timeZone).weekday(.abbreviated).month(.abbreviated).day())
        }
        let zone = clock == .local ? TimeZone.current : event.timeZone
        return "\(date.formatted(.gregorian(in: zone).weekday(.abbreviated).month(.abbreviated).day())) · \(shown)"
    }

    /// The time `stage` falls at, on `clock` — nil where only its day was
    /// written.
    static func time(_ stage: TicketStage, of todo: TicketTodo, on clock: TimeDisplay) -> String? {
        guard todo.entry[stage]?.minute != nil, let date = todo.date(of: stage) else { return nil }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = clock == .local ? TimeZone.current : todo.event.timeZone
        return date.formatted(style)
    }

    /// "Pay by Fri, Nov 13 · 23:59", on `clock`.
    static func when(_ stage: TicketStage, of todo: TicketTodo, on clock: TimeDisplay) -> Text {
        let moment = Self.moment(stage, of: todo, on: clock)
        return switch stage {
        case .payment: Text("Pay by \(moment)")
        case .pickup: Text("Pickup opens \(moment)")
        }
    }

    /// How far off the step waited on is, in whole days on the hall's
    /// calendar: "2 days left", "In 26 days", "Opens in 8 days".
    static func due(of todo: TicketTodo, at now: Date = .now) -> Text {
        guard let current = todo.current, let day = todo.entry[current]?.day, let due = todo.due
        else { return Text(verbatim: "") }
        let days = day.daysAway(from: now, in: .gregorian(in: todo.event.timeZone))
        if todo.kind == .pickUp {
            if due <= now { return Text("Open now") }
            return days <= 0 ? Text("Opens today") : Text("Opens in ^[\(days) day](inflect: true)")
        }
        if due <= now { return Text("Overdue") }
        if days <= 0 { return Text("Due today") }
        return days <= 7 ? Text("^[\(days) day](inflect: true) left") : Text("^[In \(days) day](inflect: true)")
    }

    /// The same to the hour, for the to-do's own sheet: "2 days, 6 hours
    /// left".
    static func countdown(of todo: TicketTodo, at now: Date = .now) -> Text {
        guard let due = todo.due else { return Text(verbatim: "") }
        guard due > now else { return todo.kind == .pickUp ? Text("Open now") : Text("Overdue") }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = due.timeIntervalSince(now) < 24 * 3600 ? [.hour, .minute] : [.day, .hour]
        let span = formatter.string(from: now, to: due) ?? ""
        return todo.kind == .pickUp ? Text("Opens in \(span)") : Text("\(span) left")
    }
}

#Preview {
    NavigationStack {
        TicketTodosView()
    }
    .library(EventStore.preview)
}
