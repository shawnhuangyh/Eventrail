import SwiftData
import SwiftUI

/// One to-do on a sheet of its own, as `TodoPay.dc.html` and
/// `TodoPaid.dc.html` draw it: the event, how long is left, the way the ticket
/// has come and has still to go, what is to be paid and where, and the
/// notifications behind it — as long ahead as Settings says, and stopped once
/// its step is reached. The button at its foot marks the step waited on; a
/// pill over it takes that back.
///
/// **Written as answered**, as every screen but Ticket Details is: there is no
/// copy here to throw away. A step itself is changed on
/// ``TicketDeadlineView``, which holds one.
struct TicketTodoSheet: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(LibraryEntry.library) private var kept: [LibraryEntry]
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue

    /// Which to-do, read as it stands with every drawing.
    let id: TicketTodo.ID

    @State private var undo: TicketTodoUndo?
    @State private var openEvent: Event?
    @State private var editing: TicketStage?
    @State private var isConfirmingGiveUp = false

    init(todo id: TicketTodo.ID) {
        self.id = id
    }

    private var todo: TicketTodo? {
        TicketTodoList(events: store.events(of: kept, where: \.inLibrary)) { store.tracking(for: $0) }.todo(id)
    }

    var body: some View {
        let todo = todo
        NavigationStack {
            Group {
                if let todo {
                    page(todo)
                } else {
                    // Its steps were taken off the round meanwhile, or it
                    // is no longer won.
                    ContentUnavailableView("No Longer a To-Do", systemImage: "checklist")
                }
            }
            .navigationTitle(todo.map { Text(TicketTodoText.name(of: $0.kind)) } ?? Text("Ticket To-Dos"))
            .navigationBarTitleDisplayMode(.inline)
            .padNavigationBarOnMac()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .tint(.primary)
                        // Given up while a sheet of its own stands over it.
                        .keyboardShortcut(editing == nil && openEvent == nil ? .cancelAction : nil)
                }
                if let todo {
                    ToolbarItem(placement: .primaryAction) { menu(todo) }
                }
            }
        }
        .opensFromOutside()
        .refreshNoticesInSheet()
        .eventSheet($openEvent)
        .sheet(item: $editing) { stage in
            if let todo {
                TicketDeadlineView(event: todo.event, entry: todo.entry, editing: stage)
                    .macSheetSize(.form)
            }
        }
    }

    private func page(_ todo: TicketTodo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(todo)
                // The hours move without anyone touching the sheet.
                TimelineView(.everyMinute) { context in
                    status(todo, at: context.date)
                }
                TicketForm.section("Progress") { timeline(todo) }
                if todo.total != nil || todo.place != nil || todo.link != nil {
                    TicketForm.section(todo.kind == .pickUp && todo.payment == nil ? "Ticket Pickup" : "Payment") {
                        payment(todo)
                    }
                }
                TicketForm.section("Reminders") {
                    VStack(spacing: 0) {
                        ForEach(Array(todo.stages.enumerated()), id: \.element) { index, stage in
                            stageRow(stage, of: todo)
                                .overlay(alignment: .top) {
                                    if index > 0 { Divider().padding(.leading, 15) }
                                }
                        }
                    }
                    .panel(cornerRadius: 22)
                    footnote(todo)
                        .scalingFont(size: 12.5)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .washBackground()
        .safeAreaInset(edge: .bottom) { foot(todo) }
    }

    // MARK: - The event, and how long is left

    private func header(_ todo: TicketTodo) -> some View {
        Button {
            openEvent = todo.event
        } label: {
            HStack(spacing: 13) {
                FlyerThumbnail(url: todo.event.imageURL, width: 50, cornerRadius: 11)
                VStack(alignment: .leading, spacing: 4) {
                    Text(todo.event.title)
                        .scalingFont(size: 17, weight: .bold)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    HStack(spacing: 3) {
                        Text(verbatim: "\(todo.event.shown(on: timeDisplay).dayLine) · \(todo.event.venue)")
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .scalingFont(size: 13, weight: .medium)
                    .foregroundStyle(Color.brandTint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens the event"))
    }

    private func status(_ todo: TicketTodo, at now: Date) -> some View {
        let state = todo.state
        let isUrgent = todo.isUrgent(at: now)
        let tint: Color = switch state {
        case .notPaid: Color(.systemGray)
        case .paid: .brandTint
        case .issued: .trackAttended
        default: TicketTodoText.tint(of: todo.kind)
        }
        let zone = timeDisplay == .local ? TimeZone.current : todo.event.timeZone
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if todo.steps.contains(where: { $0.name == state && $0.status == .now }) {
                    Circle().fill(tint).frame(width: 7, height: 7)
                } else {
                    Image(systemName: state == .notPaid ? "xmark" : "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                }
                TicketTodoText.name(of: state)
            }
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(tint.opacity(0.12), in: .capsule)

            Group {
                if todo.isDone, let finished = todo.finished {
                    Text("\(TicketTodoText.name(of: state)) · \(finished.formatted(.gregorian(in: zone).month(.abbreviated).day().hour().minute()))")
                } else if state == .paid, let paid = todo.payment?.done {
                    Text("\(TicketTodoText.name(of: state)) · \(paid.formatted(.gregorian(in: zone).month(.abbreviated).day().hour().minute()))")
                } else {
                    TicketTodoText.countdown(of: todo, at: now)
                        .foregroundStyle(isUrgent ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                }
            }
            .scalingFont(size: 26, weight: .bold)
            .monospacedDigit()
            .minimumScaleFactor(0.7)
            .lineLimit(2)
            .padding(.top, 6)

            if let current = todo.current {
                Group {
                    if state == .paid {
                        Text("Next: \(TicketTodoText.when(current, of: todo, on: timeDisplay))")
                            .foregroundStyle(Color.trackAttended)
                    } else {
                        TicketTodoText.when(current, of: todo, on: timeDisplay)
                    }
                }
                .scalingFont(size: 14, weight: .semibold)
                .monospacedDigit()
                // Said only where it could be taken for the reader's own.
                if zone.identifier != TimeZone.current.identifier {
                    Text("Venue Time · \(todo.event.offsetLine(in: zone))")
                        .scalingFont(size: 12)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel(cornerRadius: 22)
        .overlay {
            if isUrgent {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.4), lineWidth: 1.5)
            }
        }
    }

    // MARK: - The way it has come

    /// Having applied and having won, then the to-do's own steps: each with
    /// what is known of it.
    private func timeline(_ todo: TicketTodo) -> some View {
        let entry = todo.entry
        var rows: [TimelineRow] = [
            TimelineRow(id: "applied", name: Text("Applied"), detail: LotteryText.round(of: entry),
                        status: .done, isMissed: false),
        ]
        let won = entry.wonChoice.map(LotteryText.won)
        let day = entry.day.map { Text("Results \(LotteryText.short($0))") }
        let wonDetail: Text? = switch (day, won) {
        case let (day?, won?): Text("\(day) · \(won)")
        case let (day?, nil): day
        case let (nil, won?): won
        default: nil
        }
        rows.append(TimelineRow(id: "won", name: Text("Won"), detail: wonDetail, status: .done, isMissed: false))
        for step in todo.steps {
            rows.append(TimelineRow(id: "\(step.name)", name: TicketTodoText.name(of: step.name),
                                    detail: detail(of: step, in: todo), status: step.status,
                                    isMissed: step.name == .notPaid))
        }
        let tint = TicketTodoText.tint(of: todo.kind)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        dot(row, tint: tint)
                        if index < rows.count - 1 {
                            Rectangle()
                                .fill(row.status == .done ? AnyShapeStyle(Color.trackAttended) : AnyShapeStyle(Color(.systemGray4)))
                                .frame(width: 2)
                                .frame(minHeight: 16)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        row.name
                            .scalingFont(size: 14.5, weight: row.status == .now ? .bold : .medium)
                            .foregroundStyle(row.status == .now ? AnyShapeStyle(tint)
                                             : row.status == .done ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        if let detail = row.detail {
                            detail
                                .scalingFont(size: 12)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 1)
                    .padding(.bottom, index < rows.count - 1 ? 14 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 16)
        .panel(cornerRadius: 22)
    }

    private struct TimelineRow: Identifiable {
        let id: String
        let name: Text
        let detail: Text?
        let status: TicketTodo.Step.Status
        let isMissed: Bool
    }

    @ViewBuilder
    private func dot(_ row: TimelineRow, tint: Color) -> some View {
        switch row.status {
        case .done:
            Image(systemName: row.isMissed ? "xmark" : "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(row.isMissed ? Color(.systemGray) : Color.trackAttended, in: .circle)
        case .now:
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .frame(width: 20, height: 20)
                .background(TicketForm.controlFill, in: .circle)
                .overlay { Circle().strokeBorder(tint, lineWidth: 2.5) }
        case .ahead:
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: 20, height: 20)
        }
    }

    /// When a step falls, or when it was reached.
    private func detail(of step: TicketTodo.Step, in todo: TicketTodo) -> Text? {
        let zone = timeDisplay == .local ? TimeZone.current : todo.event.timeZone
        func reached(_ moment: TicketMoment?) -> Text? {
            moment?.done.map {
                Text(verbatim: $0.formatted(.gregorian(in: zone).month(.abbreviated).day().hour().minute()))
            }
        }
        switch step.name {
        case .awaitingPayment, .awaitingPickup:
            return step.stage.map { TicketTodoText.when($0, of: todo, on: timeDisplay) }
        case .paid: return reached(todo.payment)
        case .notPaid: return reached(todo.payment ?? todo.pickup)
        case .issued:
            return reached(todo.pickup) ?? step.stage.map { TicketTodoText.when($0, of: todo, on: timeDisplay) }
        }
    }

    // MARK: - What is to be paid

    private func payment(_ todo: TicketTodo) -> some View {
        VStack(spacing: 0) {
            if let total = todo.total {
                row(first: true) {
                    Text("Amount")
                    Spacer(minLength: 8)
                    // The sum, then how it is made up where it was worked out.
                    if todo.payment?.owed == nil, let cost = todo.cost, let quantity = todo.entry.wonChoice?.quantity {
                        Text("\(Text(verbatim: total.formatted).fontWeight(.bold).foregroundStyle(.primary)) · \(cost.formatted) × \(quantity)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(verbatim: total.formatted).fontWeight(.bold)
                    }
                }
            }
            if let place = todo.place {
                row(first: todo.total == nil) {
                    todo.kind == .pickUp && todo.payment == nil ? Text("Pick Up At") : Text("Pay At")
                    Spacer(minLength: 8)
                    Text(verbatim: place).foregroundStyle(.secondary)
                }
            }
            if let link = todo.link {
                Link(destination: link) {
                    row(first: todo.total == nil && todo.place == nil) {
                        Image(systemName: "link")
                        Text("Open \(link.host() ?? link.absoluteString)")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .scalingFont(size: 11, weight: .semibold)
                    }
                    .fontWeight(.medium)
                    .foregroundStyle(Color.brandTint)
                }
                .accessibilityHint(Text("Opens in your browser"))
            }
        }
        .monospacedDigit()
        .panel(cornerRadius: 22)
    }

    private func row<Content: View>(first: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 11) { content() }
            .scalingFont(size: 14.5)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .contentShape(.rect)
            .overlay(alignment: .top) {
                if !first { Divider().padding(.leading, 15) }
            }
    }

    // MARK: - Its notifications

    /// One step: its name, when it falls and how far ahead its notification
    /// comes, as Settings says — or, once it is reached, that it was stopped.
    /// The words open it to be changed.
    private func stageRow(_ stage: TicketStage, of todo: TicketTodo) -> some View {
        let isStopped = todo.entry[stage]?.done != nil
        let tint: Color = stage == .payment ? .trackTicket : .trackAttended
        let lead = TicketTodoText.lead(of: stage)
        let moment = TicketTodoText.moment(stage, of: todo, on: timeDisplay)
        return HStack(spacing: 11) {
            Button {
                editing = stage
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: isStopped || lead == nil ? "bell.slash" : "bell")
                        .scalingFont(size: 15)
                        .foregroundStyle(isStopped ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        TicketDeadlineView.title(of: stage)
                            .scalingFont(size: 14.5)
                        Text(verbatim: lead.map { "\(moment) · \(ReminderLead.label(of: $0))" } ?? moment)
                            .scalingFont(size: 12)
                            .monospacedDigit()
                            .strikethrough(isStopped)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(isStopped ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .scalingFont(size: 11, weight: .semibold)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Edits this deadline"))

            if isStopped {
                Text("Stopped · \(stoppedBy(stage, of: todo))")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Color.primary.opacity(0.08), in: .capsule)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
    }

    /// What reached the step a stopped notification stood for.
    private func stoppedBy(_ stage: TicketStage, of todo: TicketTodo) -> Text {
        if todo.entry[stage]?.missed == true { return TicketTodoText.name(of: .notPaid) }
        return TicketTodoText.name(of: stage == .payment ? .paid : .issued)
    }

    private func footnote(_ todo: TicketTodo) -> Text {
        switch todo.state {
        case .awaitingPayment where todo.pickup != nil:
            Text("Marking it paid stops the Payment Deadline reminder. Ticket Pickup keeps its alert until the ticket is issued.")
        case .awaitingPayment: Text("Marking it paid stops the Payment Deadline reminder.")
        case .paid, .awaitingPickup: Text("Marking it issued stops the Ticket Pickup reminder too.")
        case .issued, .notPaid: Text("Nothing more will be said about this. Back to To Do brings back a reminder whose time is still ahead.")
        }
    }

    // MARK: - The foot

    /// The pill that takes the last mark back, the button for the next one,
    /// and under an unpaid ticket the way to say it never was paid.
    private func foot(_ todo: TicketTodo) -> some View {
        VStack(spacing: 10) {
            if let undo {
                TicketTodoUndoPill(undo: undo) { self.undo = nil }
            }
            if let action = TicketTodoText.action(of: todo) {
                let isLeading = todo.state != .paid
                Button {
                    withAnimation(.snappy) { undo = store.advance(todo) ?? undo }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark").fontWeight(.bold)
                        action
                    }
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundStyle(isLeading ? Color.white : Color.brandTint)
                        .background(isLeading ? AnyShapeStyle(Color.brandTint) : AnyShapeStyle(Color.washBase), in: .capsule)
                        .background(Color.brandTint.opacity(isLeading ? 0 : 0.12), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    withAnimation(.snappy) {
                        undo = nil
                        store.stepBack(todo)
                    }
                } label: {
                    Label("Back to To Do", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundStyle(Color.brandTint)
                        .background(Color.washBase, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .capsulePanel()
            }
            if todo.state == .awaitingPayment {
                Button("Didn’t Pay in Time") { isConfirmingGiveUp = true }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
                    .frame(minHeight: 30)
                    // Asked from the button, so the dialog points at it.
                    .confirmationDialog("Mark this ticket as not paid?", isPresented: $isConfirmingGiveUp,
                                        titleVisibility: .visible) {
                        Button("Mark as Not Paid", role: .destructive) {
                            withAnimation(.snappy) { undo = store.giveUp(todo) ?? undo }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Its reminders stop and it moves to Done. The lottery round stays as you recorded it.")
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 8)
        // The page fades out under it, as the design draws the foot.
        .background {
            LinearGradient(stops: [.init(color: Color.washBase.opacity(0), location: 0),
                                   .init(color: Color.washBase.opacity(0.96), location: 0.3)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    private func menu(_ todo: TicketTodo) -> some View {
        Menu {
            if let stage = todo.current ?? todo.stages.last {
                Button("Edit Deadline", systemImage: "square.and.pencil") { editing = stage }
            }
            Button("Open Event", systemImage: "calendar") { openEvent = todo.event }
            if todo.stages.contains(where: { todo.entry[$0]?.done != nil }), !todo.isDone {
                Button("Undo Last Step", systemImage: "arrow.uturn.backward") {
                    withAnimation(.snappy) {
                        undo = nil
                        store.stepBack(todo)
                    }
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .menuOrder(.fixed)
    }
}
