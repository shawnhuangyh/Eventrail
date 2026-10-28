import AVFoundation
import PhotosUI
import SwiftUI
import VisionKit

/// The reader's own record for one event — the seat, what it cost, a note and
/// the rounds of the sale they tried for — asked on a sheet of its own over
/// the event's.
///
/// The event's sheet shows these answers as two tiles and a line of note, so
/// the facts Eventernote publishes are not pushed down a screen by a form. A
/// tap on any of them opens this, where each answer is asked the way it is
/// answered: chips for a choice, a stepper for a count, a field for anything
/// written. A lottery is a card here and a page of its own behind it
/// (``LotteryEntryView``), because it is several answers about one
/// application.
///
/// Answered onto the sheet's own copy of the record: the checkmark writes
/// down what was changed on it, and the X leaves the record as it was —
/// asking first, where anything was changed. A sheet holding a change, or with
/// an entry open over it, will not be pulled away, so nothing is thrown out
/// without that question. A lottery entry's page answers onto the same copy
/// (``LotteryEntryView``), so an entry saved there is written down with the
/// rest or not at all.
///
/// A `List` rather than a scroll view of fields, for the swipe that takes an
/// entry out — each card a row of its own, every row drawn bare, so it reads
/// as the entry's page does.
struct TicketDetailsView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// What a cost typed on a ticket with none starts in, and what the hint
    /// under the field converts into — see ``Currencies/storageKey``.
    @AppStorage(Currencies.storageKey) private var defaultCurrency = Currencies.yen
    /// A currency picked before any amount was typed. Held here rather than
    /// written down: a currency is half of the answer "what it cost", and
    /// without the amount it says nothing — see ``Tracking/currency``.
    @State private var pendingCurrency: String?
    /// The lottery entry open on top of the sheet, if any — as it stood when
    /// it was opened, or a new one not in the list until its page saves it.
    @State private var path: [LotteryEntry] = []

    /// The record as it stood when the sheet opened, which the copy is held
    /// against — see ``save()``. State rather than a `let`, so a sheet redrawn
    /// with a record synced in since keeps the one it opened on.
    @State private var original: Tracking
    /// The record as the sheet has it, every answer given here included.
    @State private var draft: Tracking
    @State private var isConfirmingDiscard = false
    @State private var isConfirmingAnotherEntry = false
    @State private var isConfirmingClear = false
    /// Scanning the ticket: the picker or the camera up — or the camera not
    /// allowed — the picture picked, the reading under way, and what it found,
    /// asked about before anything is filled in (``TicketScan``), or that it
    /// found nothing.
    @State private var isPickingTicket = false
    @State private var isShootingTicket = false
    @State private var isCameraRefused = false
    @State private var ticketPicture: PhotosPickerItem?
    @State private var isReadingTicket = false
    @State private var scan: TicketScan?
    @State private var isScanEmpty = false

    let event: Event

    /// The sheet for `event`'s record — opened on one of its lottery
    /// entries where `entry` names one, as the Lotteries list opens it.
    init(event: Event, tracking: Tracking, opening entry: LotteryEntry? = nil) {
        self.event = event
        _original = State(initialValue: tracking)
        _draft = State(initialValue: tracking)
        _path = State(initialValue: entry.map { [$0] } ?? [])
    }

    private var tracking: Binding<Tracking> { $draft }

    /// Whether the X would throw anything away.
    private var hasChanges: Bool { draft != original }

    /// The copy as it would be written down: the ticket's class read off the
    /// rounds won (``Tracking/settleSeatClass(since:)``), which the sheet
    /// shows rather than asks.
    private var settled: Tracking {
        var record = draft
        record.settleSeatClass(since: original)
        return record
    }

    /// Writes down what was changed here, and puts the sheet away — asking
    /// first where the ticket went here and a seat or a cost is still written
    /// (``leavesSeatOrCostBehind``).
    private func save() {
        if leavesSeatOrCostBehind {
            isConfirmingClear = true
        } else {
            write(settled)
        }
    }

    /// Whether the ticket was taken away on this sheet — its last win taken
    /// out, or put back to Pending or Lost — with a seat or a cost still
    /// written for it. The two are asked only once there is a ticket, so
    /// kept, they would be kept out of sight.
    ///
    /// Asked only where the ticket went here: a record that had none when
    /// the sheet opened has been asked about already, or never had one.
    private var leavesSeatOrCostBehind: Bool {
        settled.leavesSeatOrCostBehind(since: original)
    }

    /// `record` written over the record as it stands now — only what was
    /// changed here (``Tracking/applying(changesFrom:to:)``) — and the sheet
    /// put away.
    private func write(_ record: Tracking) {
        store.setTracking(store.tracking(for: event).applying(changesFrom: original, to: record), for: event)
        // A results day written down here is the moment to ask whether the
        // reader wants to hear about it — see ``LotteryReminders``. On the
        // checkmark rather than on an entry's own page, which a sheet put
        // away with its X undoes: asked there, a day thrown away still asked.
        let days = Dictionary(original.lotteries.map { ($0.id, $0.day) }) { first, _ in first }
        LotteryReminders.shared.askIfNeeded(for: record.lotteries.filter { days[$0.id] != .some($0.day) })
        dismiss()
    }

    /// Whether there is a ticket to say anything about: once a lottery is won
    /// or a first-come round got — the entries say it, and nothing else asks
    /// (``Tracking/hasTicket``). Past or ahead alike: an event over is not one
    /// the reader went to until a round says they had a ticket.
    private var hasTicket: Bool { tracking.wrappedValue.hasTicket }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // First, and asked whether or not there is a ticket: the
                // applications went in long before anybody knew, an event
                // applied for six times and lost is worth having written
                // down — and a win here is what makes the ticket, fills in
                // its class and brings the seat and cost below it.
                lotteryRows
                if hasTicket {
                    seatSection
                        .formRow(top: Self.sectionGap)
                    costSection
                        .formRow(top: Self.sectionGap)
                }
                notesSection
                    .formRow(top: Self.sectionGap, bottom: 40)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // The gap between a section's own parts; a section is set further
            // off the one before it by its row's inset (``sectionGap``).
            .listRowSpacing(Self.rowGap)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Ticket Details")
            .navigationBarTitleDisplayMode(.inline)
            .padNavigationBarOnMac()
            .toolbar {
                // Plain beside the checkmark's blue: the X writes nothing.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        if hasChanges { isConfirmingDiscard = true } else { dismiss() }
                    }
                    .tint(.primary)
                    // Not while a round's page is pushed: its copy of the
                    // entry is not in `hasChanges`, so Escape would throw it
                    // away unasked. The page takes Escape itself once it has
                    // something to lose (``LotteryEntryView``).
                    .keyboardShortcut(path.isEmpty ? .cancelAction : nil)
                    // Asked from the button, so the dialog points at what
                    // opened it.
                    .confirmationDialog("Discard your changes?", isPresented: $isConfirmingDiscard,
                                        titleVisibility: .visible) {
                        Button("Discard Changes", role: .destructive) { dismiss() }
                        Button("Keep Editing", role: .cancel) {}
                    } message: {
                        Text("Your changes to this ticket will not be saved.")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm, action: save)
                        .confirmationDialog("Clear the seat and cost too?", isPresented: $isConfirmingClear,
                                            titleVisibility: .visible) {
                            Button("Clear Seat and Cost", role: .destructive) {
                                write(settled.clearingSeatAndCost)
                            }
                            Button("Keep Them") { write(settled) }
                            Button("Keep Editing", role: .cancel) {}
                        } message: {
                            Text("You no longer have a ticket for this event, so its seat and cost will not be shown.")
                        }
                }
            }
            .navigationDestination(for: LotteryEntry.self) { entry in
                LotteryEntryView(entry: entry, in: $draft)
            }
            // Photos' own picker, which runs outside the app: it asks for no
            // permission and hands over the one picture picked.
            .photosPicker(isPresented: $isPickingTicket, selection: $ticketPicture,
                          matching: .images, preferredItemEncoding: .current)
            .onChange(of: ticketPicture) { _, picture in
                guard let picture else { return }
                ticketPicture = nil
                read(picture)
            }
            .fullScreenCover(isPresented: $isShootingTicket) {
                TicketCamera { pages in
                    isShootingTicket = false
                    guard !pages.isEmpty else { return }
                    isReadingTicket = true
                    Task { await read(pages) }
                }
                .ignoresSafeArea()
            }
            .alert("No Seat or Price Found", isPresented: $isScanEmpty) {
                Button("OK") {}
            } message: {
                Text("Try again with a picture that shows the ticket's seat and price clearly.")
            }
            .alert("Couldn't Open the Camera", isPresented: $isCameraRefused) {
                Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Eventrail isn't allowed to use the camera. You can allow it in Settings.")
            }
        }
        // An entry's page asks its own question on the way back, which a
        // swipe down past it would not.
        .interactiveDismissDisabled(hasChanges || !path.isEmpty)
        .opensFromOutside()
    }

    // MARK: - Sections

    /// What a section's parts are set apart by, as ``TicketForm/section`` sets
    /// them.
    private static let rowGap: CGFloat = 10
    /// What sets a section off the one before it, over the row gap: 24 in all.
    private static let sectionGap: CGFloat = 24 - rowGap

    /// Every round of the sale tried for, a card each, in the order the sale
    /// runs them whatever order they were added in (``Tracking/lotteriesInOrder``),
    /// and a way to add one — rows of their own rather than one section, since
    /// each card swipes on its own. A card opens the entry on a page of its
    /// own, and a swipe from the trailing edge takes it out.
    @ViewBuilder
    private var lotteryRows: some View {
        let entries = tracking.wrappedValue.lotteriesInOrder
        TicketForm.header("Lotteries") {
            if let summary = lotterySummary(entries) {
                summary
                    .scalingFont(size: 13, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .formRow(top: 4)

        ForEach(entries) { entry in
            LotteryEntryCard(entry: entry, isEventAhead: event.isUpcoming) {
                path.append(entry)
            }
            // Not asked about first, as no swipe to delete on iOS is.
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("Delete", systemImage: "trash", role: .destructive) { delete(entry) }
                // Said outright, as My Events says it: the role alone left the
                // button in the app's tint rather than the system red.
                .tint(.red)
            }
            // The swipe again, from a right-click on a Mac.
            .contextMenuOnMac {
                Button("Delete", systemImage: "trash", role: .destructive) { delete(entry) }
            }
            .formRow()
        }

        // Asked first once there is a ticket: another round tried for after a
        // win or a seat got is usually a slip of the thumb, but not always —
        // a second seat for a friend is one.
        TicketForm.addButton("Add Lottery Entry") {
            if tracking.wrappedValue.hasTicket { isConfirmingAnotherEntry = true } else { addEntry() }
        }
        .confirmationDialog("Add another lottery entry?", isPresented: $isConfirmingAnotherEntry,
                            titleVisibility: .visible) {
            Button("Add Entry", action: addEntry)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You already have a ticket for this event.")
        }
        .formRow()

        if entries.isEmpty {
            Text("One entry for each lottery applied to — the choices ranked and how it went.")
                .scalingFont(size: 13)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .formRow()
        }
    }

    /// How many times the reader applied across the lottery rounds, and how
    /// many rounds were won — or, where none was, how many are still to be
    /// settled.
    private func lotterySummary(_ entries: [LotteryEntry]) -> Text? {
        var parts: [Text] = []
        let applications = tracking.wrappedValue.lotteryApplications
        if applications > 0 { parts.append(Text("^[\(applications) entry](inflect: true)")) }
        let won = entries.filter(\.isWon).count
        let pending = entries.filter(\.isPending).count
        if won > 0 {
            parts.append(Text("\(won) won"))
        } else if pending > 0, event.isUpcoming {
            parts.append(Text("\(pending) pending"))
        }
        guard let first = parts.first else { return nil }
        return parts.dropFirst().reduce(first) { Text("\($0) · \($1)") }
    }

    /// A new entry with one choice to fill in and nothing chosen — no round,
    /// no count of entries, no result — opened at once. It joins the list only
    /// once its page is saved.
    private func addEntry() {
        path.append(LotteryEntry(applications: 0, choices: [LotteryChoice()]))
    }

    /// Takes an entry out of the sheet's copy — written down only on its
    /// checkmark, as every other answer here is.
    private func delete(_ entry: LotteryEntry) {
        withAnimation(.snappy) {
            tracking.lotteries.wrappedValue.removeAll { $0.id == entry.id }
        }
    }

    /// Where the reader sat, as the ticket printed it, with the class of seat
    /// it is beside it — read from the rounds won above rather than asked
    /// here (``Tracking/ticketClass``), the highest where several were won,
    /// which a line under the field says only then.
    private var seatSection: some View {
        let record = settled
        return TicketForm.section("Seat") {
            scanButton
        } content: {
            TicketForm.field(symbol: "sofa") {
                // A block, a row and a number in three languages worth of
                // conventions: nothing the keyboard would correct here is a
                // correction.
                TextField("Seat", text: tracking.seat, prompt: Text("Seat"))
                    .autocorrectionDisabled()
                if !record.seatClass.isEmpty {
                    HStack(spacing: 7) {
                        TicketForm.seatClassBadge(record.seatClass)
                        LotteryText.seatClass(record.seatClass)
                            .scalingFont(size: 14.5, weight: .medium)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                    .accessibilityElement(children: .combine)
                }
            }

            if record.roundsWon > 1, let best = record.classOfWins {
                Text("Tickets from \(record.roundsWon) rounds — the highest class, \(LotteryText.seatClass(best)), is used.")
                    .scalingFont(size: 13)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Scanning the ticket

    /// Reads the seat, its class and the price off a picture of the ticket
    /// on the device (``TicketScanner``): a screenshot of e+'s スマチケ from
    /// Photos, or a paper ticket through the document camera, which finds the
    /// ticket's edges and squares it up. On the Seat section's head, so it is
    /// there once the seat is asked, as the seat and the cost are. Photos
    /// alone where there is no camera to scan with — the Simulator, an iPad
    /// without one.
    private var scanButton: some View {
        Group {
            if VNDocumentCameraViewController.isSupported {
                Menu {
                    Button("Choose from Photos", systemImage: "photo.on.rectangle") { isPickingTicket = true }
                    Button("Scan Paper Ticket", systemImage: "doc.viewfinder", action: openCamera)
                } label: {
                    scanLabel
                }
                .menuOrder(.fixed)
            } else {
                Button { isPickingTicket = true } label: { scanLabel }
            }
        }
        .buttonStyle(.plain)
        .disabled(isReadingTicket)
        // Asked from the button, so the dialog points at what opened it.
        .confirmationDialog(scanTitle,
                            isPresented: Binding { scan != nil } set: { if !$0 { scan = nil } },
                            titleVisibility: .visible, presenting: scan) { scan in
            Button {
                fill(from: scan)
            } label: {
                isForThisEvent(scan) ? Text("Fill In") : Text("Fill In Anyway")
            }
            Button("Cancel", role: .cancel) {}
        } message: { scan in
            Text(verbatim: scanSummary(scan))
        }
    }

    private var scanLabel: some View {
        HStack(spacing: 5) {
            if isReadingTicket {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: "text.viewfinder")
            }
            Text("Scan Ticket")
        }
        .scalingFont(size: 14, weight: .semibold)
        .foregroundStyle(Color.brandTint)
        .contentShape(.rect)
    }

    /// The document camera, once the camera is allowed: asked for the first
    /// time here, and pointed at Settings where it was refused.
    private func openCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isShootingTicket = true
        case .notDetermined:
            Task {
                if await AVCaptureDevice.requestAccess(for: .video) { isShootingTicket = true }
            }
        default:
            isCameraRefused = true
        }
    }

    /// Reads the picture picked in Photos, as the camera's pages are read.
    private func read(_ picture: PhotosPickerItem) {
        isReadingTicket = true
        Task {
            let data = try? await picture.loadTransferable(type: Data.self)
            await read(data.map { [$0] } ?? [])
        }
    }

    /// Reads the pictures, and asks about what they say — or says they said
    /// nothing the sheet asks. The pictures go as soon as they are read.
    private func read(_ pictures: [Data]) async {
        isReadingTicket = true
        defer { isReadingTicket = false }
        guard let read = try? await TicketScanner.scan(pictures, hall: event.venue), !read.isEmpty else {
            isScanEmpty = true
            return
        }
        scan = read
    }

    /// The day the event falls on at its hall, which its ticket prints.
    private var eventDay: CalendarDay {
        CalendarDay(event.date, in: .gregorian(in: event.timeZone))
    }

    /// Whether the ticket is for this event's day, where it prints one. An
    /// e+ ticket for the first night and one for the second print the same
    /// title, hall and times, and nothing else tells them apart.
    private func isForThisEvent(_ scan: TicketScan) -> Bool {
        scan.day?.isSame(as: eventDay) ?? true
    }

    private var scanTitle: Text {
        if let scan, !isForThisEvent(scan) { return Text("This ticket is for another day") }
        return Text("Fill in from this ticket?")
    }

    /// The class the scan would write: only where no round that went well
    /// names one. The rounds say what the ticket is (``Tracking/ticketClass``),
    /// and the ticket's own class is kept only where they say nothing.
    private func classToFill(from scan: TicketScan) -> String? {
        draft.classOfWins == nil ? scan.seatClass : nil
    }

    /// What would be filled in, a line each, under the day the ticket is for
    /// where that is not the event's.
    private func scanSummary(_ scan: TicketScan) -> String {
        var lines: [String] = []
        if let day = scan.day, !day.isSame(as: eventDay) {
            let printed = LotteryText.long(day.calendarDay(orIn: eventDay.year))
            lines.append(String(localized: "The ticket is dated \(printed), and this event is on \(LotteryText.long(eventDay))."))
            lines.append("")
        }
        if let seat = scan.seat { lines.append(String(localized: "Seat: \(seat)")) }
        if let seatClass = classToFill(from: scan) {
            let name = SeatClass(rawValue: seatClass)?.name ?? seatClass
            lines.append(String(localized: "Seat Type: \(name)"))
        }
        if let price = scan.price { lines.append(String(localized: "Cost: \(price.formatted)")) }
        return lines.joined(separator: "\n")
    }

    /// Fills in what the scan found, over whatever was written — onto the
    /// sheet's copy, so the reader sees it in the fields and the checkmark
    /// still writes it down, or the X throws it away.
    private func fill(from scan: TicketScan) {
        var record = draft
        if let seat = scan.seat { record.seat = seat }
        if let seatClass = classToFill(from: scan) { record.seatClass = seatClass }
        if let price = scan.price {
            record.cost = price.amount
            record.currency = price.currency
        }
        withAnimation(.snappy) { draft = record }
    }

    /// What the ticket cost, and in what: the amount typed, the currency's
    /// symbol before it and the currency chosen from a menu after it, and —
    /// where that is not the reader's default — about what it comes to there.
    private var costSection: some View {
        let currency = fieldCurrency
        return TicketForm.section("Cost") {
            TicketForm.field(trailingInset: 6) {
                Text(verbatim: Currencies.symbol(of: currency))
                    .scalingFont(size: 16, weight: .medium)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .frame(minWidth: 20)
                    .accessibilityHidden(true)
            } content: {
                TextField("Cost", value: cost, format: .money(in: currency),
                          prompt: Text(verbatim: "0"))
                    .keyboardType(Currencies.fractionDigits(of: currency) > 0 ? .decimalPad : .numberPad)
                    .monospacedDigit()
                    // A new field for a new currency, so the amount is
                    // written again with that currency's decimals.
                    .id(currency)
                currencyMenu(currency)
            }
            if let conversion {
                Text(verbatim: conversion)
                    .scalingFont(size: 13)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .task(id: needsRates) {
            if needsRates { await ExchangeRates.shared.refreshIfStale() }
        }
    }

    /// The currency the field is in: the cost's own once one is written, and
    /// otherwise the one picked for it or the reader's default.
    private var fieldCurrency: String {
        tracking.wrappedValue.price?.currency ?? pendingCurrency ?? defaultCurrency
    }

    /// The amount, written down with the currency the field shows — and an
    /// amount taken away takes its currency with it, since the two are one
    /// answer. The field stays in that currency for the next one typed.
    private var cost: Binding<Decimal?> {
        Binding(
            get: { tracking.wrappedValue.cost },
            set: { amount in
                let currency = fieldCurrency
                var record = tracking.wrappedValue
                record.cost = amount
                record.currency = amount == nil ? "" : currency
                if amount == nil { pendingCurrency = currency }
                tracking.wrappedValue = record
            }
        )
    }

    /// The currency chosen from the menu: written beside an amount already
    /// there — the reader correcting what it was paid in, so the amount is
    /// kept rather than converted — or held for the one still to be typed.
    private var currency: Binding<String> {
        Binding(
            get: { fieldCurrency },
            set: { code in
                if tracking.wrappedValue.cost != nil {
                    tracking.currency.wrappedValue = code
                } else {
                    pendingCurrency = code
                }
            }
        )
    }

    /// The menu after the amount, drawn as a stepper is — a control inside
    /// the field. The reader's default and the currency of the hall's country
    /// first, each saying which it is — see ``CurrencyChoices``.
    private func currencyMenu(_ selected: String) -> some View {
        Menu {
            CurrencyChoices(selection: currency, defaultCurrency: defaultCurrency,
                            venue: Currencies.atVenue(of: event))
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: selected)
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Color.brandTint)
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(height: 34)
            .background(TicketForm.controlFill, in: .rect(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Currency"))
        .accessibilityValue(Text(verbatim: Currencies.name(of: selected)))
        .sensoryFeedback(.selection, trigger: selected)
    }

    /// About what the cost comes to in the reader's default currency, where it
    /// was paid in another and the rates are in.
    private var conversion: String? {
        guard let price = tracking.wrappedValue.price, price.currency != defaultCurrency,
              let converted = price.converted(to: defaultCurrency, at: ExchangeRates.shared.rates)
        else { return nil }
        return "≈ " + Currencies.format(whole: converted, in: defaultCurrency)
    }

    private var needsRates: Bool {
        guard let price = tracking.wrappedValue.price else { return false }
        return price.currency != defaultCurrency
    }

    /// The one answer that is not a line at all, so it is given room to grow.
    private var notesSection: some View {
        TicketForm.section("Notes") {
            TextField("Notes", text: tracking.note,
                      prompt: Text("Something only you will see"), axis: .vertical)
                .lineLimit(3...12)
                .textFieldStyle(.plain)
                .scalingFont(size: 16)
                .labelsHidden()
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(TicketForm.fieldFill, in: TicketForm.fieldShape)
        }
    }
}

/// A row of the ticket sheet drawn bare — no background, no separator — and
/// inset only as the form is, so the list reads as the sheet's fields laid
/// one under another.
private extension View {
    func formRow(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - A lottery entry's card

/// One round on the ticket sheet: its name, when the results come out and how
/// it went, then the choices in order — the one it was won with ticked. The
/// whole card opens the entry.
private struct LotteryEntryCard: View {
    let entry: LotteryEntry
    let isEventAhead: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        LotteryText.round(of: entry)
                            .scalingFont(size: 15.5, weight: .semibold)
                            .foregroundStyle(entry.round.isEmpty ? .secondary : .primary)
                        if let when = LotteryText.when(entry, isEventAhead: isEventAhead) {
                            when
                                .scalingFont(size: 12.5)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    LotteryResultPill(entry: entry, isEventAhead: isEventAhead)
                    Image(systemName: "chevron.right")
                        .scalingFont(size: 11, weight: .bold)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 7)
                }
                if !entry.choices.isEmpty { choices }
            }
            .padding(14)
            .background(TicketForm.fieldFill, in: .rect(cornerRadius: 18, style: .continuous))
            .contentShape(.rect(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// The choices in order, one row each: the rank, the class, how many —
    /// the one it was won with in green and ticked, the rest dimmed once the
    /// result is in. A first-come round asks for what it asks for, with no
    /// order to rank, so its rows carry no rank.
    private var choices: some View {
        VStack(spacing: 0) {
            ForEach(Array(entry.choices.enumerated()), id: \.element.id) { index, choice in
                let isWon = entry.outcome == .won(choice.id)
                let isDimmed = !entry.isPending && !isWon
                HStack(spacing: 10) {
                    if !entry.isFirstCome {
                        // The design's size, in a column of a fixed width:
                        // grown with the reader's text, "2nd" broke in two.
                        Text(verbatim: LotteryChoice.ordinal(index))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)
                    }
                    HStack(spacing: 7) {
                        TicketForm.seatClassBadge(choice.seatClass)
                        LotteryText.seatClass(choice.seatClass)
                            .scalingFont(size: 14.5, weight: .medium)
                            .foregroundStyle(isWon ? Color.trackAttended
                                             : choice.seatClass.isEmpty ? .secondary : .primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: "×\(choice.quantity)")
                        .scalingFont(size: 14, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(isWon ? Color.trackAttended : .primary)
                    if isWon {
                        Image(systemName: "checkmark")
                            .scalingFont(size: 12, weight: .bold)
                            .foregroundStyle(Color.trackAttended)
                            .accessibilityLabel(Text("Won"))
                    }
                }
                .opacity(isDimmed ? 0.45 : 1)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(isWon ? Color.trackAttended.opacity(0.08) : .clear)
                .overlay(alignment: .top) {
                    if index > 0 {
                        Rectangle().fill(.quaternary).frame(height: 0.5)
                    }
                }
            }
        }
        .background(TicketForm.controlFill)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
    }
}

/// How a round went, as a small capsule in its colour: waiting in the app's
/// blue, won in green, lost in grey. A round for an event already over that
/// was never answered is not waiting on anything, so it says so.
struct LotteryResultPill: View {
    let entry: LotteryEntry
    let isEventAhead: Bool

    var body: some View {
        let (label, symbol, tint) = look
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .heavy))
            label
        }
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(tint)
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(height: 26)
        .background(tint.opacity(0.12), in: .capsule)
        .fixedSize()
    }

    private var look: (Text, String, Color) {
        let label = LotteryText.result(entry.outcome, firstCome: entry.isFirstCome)
        switch entry.outcome {
        case .won: return (label, "checkmark", .trackAttended)
        case .lost: return (label, "xmark", .secondary)
        case .pending where isEventAhead: return (label, "hourglass", .trackInterest)
        case .pending: return (Text("No Result"), "minus", .secondary)
        }
    }
}

// MARK: - Words

/// How a lottery's answers are written wherever they are shown.
enum LotteryText {
    /// The round in the reader's language, or "Lottery" where none was named.
    static func round(of entry: LotteryEntry) -> Text {
        entry.round.isEmpty ? Text("Lottery") : Text(verbatim: LotteryRound.label(of: entry.round))
    }

    /// A seat class in the reader's language where it is one of the chips, as
    /// written otherwise, and "Unspecified" where the lottery had none.
    static func seatClass(_ seatClass: String) -> Text {
        if seatClass.isEmpty { return Text("Unspecified") }
        return SeatClass(rawValue: seatClass).map { Text($0.label) } ?? Text(verbatim: seatClass)
    }

    /// How a round went: a lottery pending, won or lost — and a first-come
    /// round got, which is all one ever is (``LotteryEntry/outcome``).
    static func result(_ result: LotteryResult, firstCome: Bool) -> Text {
        switch result {
        case .pending: Text("Pending")
        case .won: firstCome ? Text("Got Tickets") : Text("Won")
        case .lost: Text("Lost")
        }
    }

    /// How many times a lottery was applied for where it was more than once,
    /// then its day — "Results Oct 12", and how far off that is while the
    /// result is still to come. Nothing for a first-come round, which is
    /// neither applied for nor announced.
    static func when(_ entry: LotteryEntry, isEventAhead: Bool) -> Text? {
        guard !entry.isFirstCome else { return nil }
        let line = day(of: entry, isEventAhead: isEventAhead)
        guard entry.applications > 1 else { return line }
        return Text("\(Text("^[\(entry.applications) entry](inflect: true)")) · \(line)")
    }

    /// The results day — "Results Oct 12", and how far off that is while
    /// the result is still to come — or that none was written down.
    static func day(of entry: LotteryEntry, isEventAhead: Bool) -> Text {
        guard let day = entry.day else { return Text("No results day") }
        let date = Text(verbatim: short(day))
        guard entry.isPending, isEventAhead else { return Text("Results \(date)") }
        return Text("Results \(date) · \(relative(day))")
    }

    /// "Oct 12", with the year only where it is not this one.
    static func short(_ day: CalendarDay) -> String {
        let date = day.date()
        // Gregorian, as the day is kept — see ``CalendarDay``.
        let thisYear = Calendar.gregorian().component(.year, from: .now) == day.year
        return thisYear
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// "Sat, Oct 12, 2026".
    static func long(_ day: CalendarDay) -> String {
        day.date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    /// "today", "tomorrow", "in 8 days", "3 days ago".
    static func relative(_ day: CalendarDay) -> String {
        relative(day, context: .unknown)
    }

    /// The same, standing on its own rather than in a sentence — "Today",
    /// "In 8 days".
    static func relativeStandalone(_ day: CalendarDay) -> String {
        relative(day, context: .beginningOfSentence)
    }

    private static func relative(_ day: CalendarDay, context: Formatter.Context) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        formatter.formattingContext = context
        return formatter.localizedString(from: DateComponents(day: day.daysAway()))
    }

    /// What a choice won: the class and how many, or how many alone where
    /// the lottery had no classes.
    static func won(_ choice: LotteryChoice) -> Text {
        if choice.seatClass.isEmpty { return Text("^[\(choice.quantity) ticket](inflect: true)") }
        return Text("\(seatClass(choice.seatClass)) × \(choice.quantity)")
    }
}

// MARK: - Pieces

/// What the ticket sheet and a lottery entry are both built from, so the two
/// pages read as one form.
enum TicketForm {
    /// Flat rather than glass: the fields sit on the sheet itself, with
    /// nothing under them for glass to refract.
    static let fieldFill = Color(.tertiarySystemFill)
    static let fieldShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
    /// A control inside a field — a stepper, a menu — or a list set into a
    /// card: white on the light sheet, a lifted grey on the dark one.
    static let controlFill = Color(.secondarySystemGroupedBackground)

    /// One question: what is being asked, and under it where it is answered.
    static func section<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        section(title, accessory: { EmptyView() }, content: content)
    }

    /// One question, with something small set on the title's baseline at the
    /// trailing edge — a count, a hint.
    static func section<Accessory: View, Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(title, accessory: accessory)
            content()
        }
    }

    /// What a section asks, on its own — for a section whose parts are rows
    /// of a list rather than one view.
    static func header<Accessory: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .scalingFont(size: 16, weight: .bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            accessory()
        }
    }

    /// A one-line field, with the symbol for what it holds at its leading edge.
    static func field<Content: View>(
        symbol: String,
        trailingInset: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) -> some View {
        field(trailingInset: trailingInset) {
            Image(systemName: symbol)
                .scalingFont(size: 15)
                .foregroundStyle(.tertiary)
                .frame(width: 20)
                .accessibilityHidden(true)
        } content: {
            content()
        }
    }

    /// A one-line field, with whatever says what it holds at its leading edge.
    static func field<Leading: View, Content: View>(
        trailingInset: CGFloat = 14,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            leading()
            content()
        }
        .textFieldStyle(.plain)
        .scalingFont(size: 16)
        .labelsHidden()
        .padding(.leading, 14)
        .padding(.trailing, trailingInset)
        .frame(minHeight: 46)
        .background(fieldFill, in: fieldShape)
    }

    /// One answer among a few, as a capsule: filled in the app's colour when
    /// it is the answer given, outlined when it is not.
    static func chip<Label: View>(
        isOn: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isOn ? Color.brandTint : Color(.systemBackground), in: .capsule)
                .overlay {
                    if !isOn { Capsule().strokeBorder(Color.primary.opacity(0.14), lineWidth: 1) }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .animation(.snappy, value: isOn)
    }

    /// A seat class chip's label: its badge, then its name.
    static func seatClassLabel(_ seatClass: SeatClass, isOn: Bool) -> some View {
        seatClassLabel(badge: seatClass.badge, name: Text(seatClass.label), isOn: isOn)
    }

    /// The same for a class the reader typed, named as typed.
    static func seatClassLabel(typed seatClass: String, isOn: Bool) -> some View {
        seatClassLabel(badge: SeatClass.badge(of: seatClass) ?? Text(verbatim: "?"),
                       name: Text(verbatim: seatClass), isOn: isOn)
    }

    private static func seatClassLabel(badge: Text, name: Text, isOn: Bool) -> some View {
        HStack(spacing: 7) {
            badge
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isOn ? Color.brandTint : Color(.systemBackground))
                .padding(.horizontal, 4)
                .frame(minWidth: 18, minHeight: 18)
                .background(isOn ? Color.white : Color.primary, in: .capsule)
            name
        }
    }

    /// A seat class's badge on its own, as a chip draws it unchosen — see
    /// ``SeatClass/badge(of:)``; nothing for none.
    @ViewBuilder
    static func seatClassBadge(_ seatClass: String) -> some View {
        if let badge = SeatClass.badge(of: seatClass) {
            badge
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 4)
                .frame(minWidth: 18, minHeight: 18)
                .background(Color.primary, in: .capsule)
                .accessibilityHidden(true)
        }
    }

    /// A full-width button that adds one more of something, in the app's
    /// colour on a wash of it.
    static func addButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        addButton(Text(title), action: action)
    }

    static func addButton(_ title: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { title } icon: { Image(systemName: "plus").font(.system(size: 13, weight: .bold)) }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.brandTint)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color.brandTint.opacity(0.09), in: fieldShape)
                .contentShape(fieldShape)
        }
        .buttonStyle(.plain)
    }

    /// A minus and a plus inside a field, stepping a count within its bounds.
    /// An end that would leave the count where it is is not offered.
    static func stepper(_ value: Binding<Int>, in range: ClosedRange<Int>,
                        fewer: Text, more: Text) -> some View {
        HStack(spacing: 0) {
            step(value, by: -1, in: range, symbol: "minus", label: fewer)
            Rectangle()
                .fill(.quaternary)
                .frame(width: 0.5)
                .padding(.vertical, 8)
            step(value, by: 1, in: range, symbol: "plus", label: more)
        }
        .frame(height: 34)
        .background(controlFill, in: .rect(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
        .sensoryFeedback(.selection, trigger: value.wrappedValue)
    }

    private static func step(_ value: Binding<Int>, by delta: Int, in range: ClosedRange<Int>,
                             symbol: String, label: Text) -> some View {
        let next = min(max(value.wrappedValue + delta, range.lowerBound), range.upperBound)
        let enabled = next != value.wrappedValue
        return Button {
            value.wrappedValue = next
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? AnyShapeStyle(Color.brandTint) : AnyShapeStyle(.quaternary))
                .frame(width: 40)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

// MARK: - The document camera

/// The system's document camera, for a paper ticket: it finds the ticket's
/// edges and squares it up — which keeps its columns straight for
/// ``TicketScan`` as a photo held at an angle would not — and hands back each
/// page taken, read like a picture from Photos and not kept.
private struct TicketCamera: UIViewControllerRepresentable {
    /// The pages taken, or none where the reader cancelled.
    let done: ([Data]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let camera = VNDocumentCameraViewController()
        camera.delegate = context.coordinator
        return camera
    }

    func updateUIViewController(_ camera: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: ([Data]) -> Void

        init(done: @escaping ([Data]) -> Void) {
            self.done = done
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            done((0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).jpegData(compressionQuality: 0.9) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            done([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: any Error) {
            done([])
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        TicketDetailsView(event: PreviewData.events[0],
                          tracking: PreviewData.tracking[PreviewData.events[0].id] ?? Tracking())
            .library(EventStore.preview)
    }
}
