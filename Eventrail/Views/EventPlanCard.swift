import AVFoundation
import PhotosUI
import SwiftUI
#if !targetEnvironment(macCatalyst)
import Vision
import VisionKit
#endif

/// What the reader has planned around a kept event, on its sheet: the times
/// they want to hear about (``EventReminder``) and the queue tickets they took
/// (``QueueTicket``). On an event gone by it stays, for what is written down
/// afterwards, and nothing on it comes as a notification.
///
/// The sheets it opens are held by ``EventDetailView`` through these bindings,
/// since nothing may move the page while one is up (``EventSheetsHold``).
struct EventPlanCard: View {
    @Environment(EventStore.self) private var store
    @Environment(\.openURL) private var openURL

    let event: Event
    /// The clock the sheet prints on.
    let clock: TimeDisplay
    @Binding var editing: EventReminder?
    @Binding var isPicking: Bool
    @Binding var isScanning: Bool
    /// Lets the page move again, once the last of its sheets has gone.
    let releaseHold: () -> Void

    @State private var picture: PhotosPickerItem?
    @State private var isReading = false
    /// The links a code held, until the reader has seen where they go.
    @State private var found: [URL] = []
    @State private var isFoundNothing = false
    @State private var isAlreadyHeld = false
    @State private var isCameraRefused = false
    /// What the camera read, until it has gone: asked about while it was still
    /// going, the dialog never came.
    @State private var scanned: URL?
    /// The ticket whose number is being asked for, and what has been typed.
    @State private var numbering: QueueTicket?
    @State private var typedNumber = ""
    /// Whether that ticket was only just added: the moment it is in hand, and
    /// one that can be passed by.
    @State private var isNumberingNew = false

    /// Where there is a camera that can read a code live. An iPad without one,
    /// the Simulator and a Mac read pictures alone.
    private var canScan: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        DataScannerViewController.isSupported
        #endif
    }

    var body: some View {
        let tracking = store.tracking(for: event)
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Reminders") { addReminderMenu }
            if !tracking.reminders.isEmpty {
                // A time gone by dims without anyone touching the sheet.
                TimelineView(.everyMinute) { context in
                    VStack(spacing: 0) {
                        ForEach(tracking.reminders) { row($0, at: context.date) }
                    }
                }
            }
            Divider()
            CardHeader(title: "Queue Tickets") { addTicketControl }
            if !tracking.queueTickets.isEmpty {
                VStack(spacing: 0) {
                    ForEach(tracking.queueTickets) { ticket in
                        row(ticket, position: tracking.queueTickets.count > 1
                                ? (tracking.queueTickets.firstIndex(of: ticket) ?? 0) + 1 : nil)
                    }
                }
            }
        }
        .padding(18)
        .panel(cornerRadius: 28)
        .padding(.horizontal, 18)
        // Photos' own picker, which runs outside the app: it asks for no
        // permission and hands over the one picture picked.
        .photosPicker(isPresented: $isPicking, selection: $picture, matching: .images,
                      preferredItemEncoding: .current)
        .onChange(of: isPicking) { _, picking in
            if !picking { releaseHold() }
        }
        .onChange(of: picture) { _, picture in
            guard let picture else { return }
            self.picture = nil
            read(picture)
        }
        #if !targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $isScanning) {
            releaseHold()
            if let scanned {
                self.scanned = nil
                take([scanned])
            }
        } content: {
            QueueTicketCamera { link in
                scanned = link
                isScanning = false
            }
        }
        #endif
        .alert("No Link Found", isPresented: $isFoundNothing) {
            Button("OK") {}
        } message: {
            Text("Try again with a picture that shows the ticket's QR code clearly.")
        }
        .alert("Already Added", isPresented: $isAlreadyHeld) {
            Button("OK") {}
        } message: {
            Text("This queue ticket is already on this event.")
        }
        .alert("Couldn't Open the Camera", isPresented: $isCameraRefused) {
            Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Eventrail isn't allowed to use the camera. You can allow it in Settings.")
        }
        .alert("Queue Ticket Number",
               isPresented: Binding { numbering != nil } set: { if !$0 { numbering = nil } },
               presenting: numbering) { ticket in
            TextField("Number on Your Ticket", text: $typedNumber)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Save") { store.setQueueTicketNumber(typedNumber, of: ticket.id, on: event) }
            Button(role: .cancel) {} label: {
                isNumberingNew ? Text("Not Now") : Text("Cancel")
            }
        }
    }

    // MARK: - Reminders

    private var addReminderMenu: some View {
        Menu {
            Section("Goods Sale") {
                ForEach(ReminderKind.goods) { kind in
                    Button(kind.label) { editing = EventReminder(kind: kind, for: event) }
                }
            }
            Section("Ticket Sale") {
                ForEach(ReminderKind.tickets) { kind in
                    Button(kind.label) { editing = EventReminder(kind: kind, for: event) }
                }
            }
            Section {
                Button("Other…") { editing = EventReminder(kind: nil, for: event) }
            }
        } label: {
            addLabel(symbol: "plus")
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Add Reminder"))
    }

    private func addLabel(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.brandTint)
            .frame(width: 30, height: 30)
            .background(Color.brandTint.opacity(0.09), in: .circle)
            .contentShape(.circle)
    }

    /// The name and its alert, with the time at the trailing edge where a
    /// column of them reads as the day's running order.
    private func row(_ reminder: EventReminder, at now: Date) -> some View {
        let isEventAhead = event.dayEnds > now
        let isOver = reminder.date(in: event.timeZone) <= now
        // Dimmed against the times still to come; once the event is over there
        // are none, and the rows are a record to read.
        let isDimmed = isEventAhead && isOver
        return Button {
            editing = reminder
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: ReminderKind.label(of: reminder.title))
                        .scalingFont(size: 14.5, weight: .semibold)
                        .foregroundStyle(isDimmed ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                    if let lead = reminder.lead, event.holds(reminder), !isOver {
                        Label(ReminderLead.label(of: lead), systemImage: "bell.fill")
                            .labelStyle(.titleAndIcon)
                            .scalingFont(size: 12)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: event.printedTime(of: reminder, on: clock))
                    .scalingFont(size: 15, weight: .bold)
                    .monospacedDigit()
                    .foregroundStyle(isDimmed ? .secondary : .primary)
                Image(systemName: "chevron.right")
                    .scalingFont(size: 11, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Queue tickets

    /// Asked from the button, so the dialog points at what opened it.
    private var addTicketControl: some View {
        Group {
            if canScan {
                Menu {
                    Button("Scan QR Code", systemImage: "qrcode.viewfinder", action: openCamera)
                    Button("Choose from Photos", systemImage: "photo.on.rectangle") { isPicking = true }
                } label: {
                    addTicketLabel
                }
                .menuOrder(.fixed)
            } else {
                Button { isPicking = true } label: { addTicketLabel }
            }
        }
        .buttonStyle(.plain)
        .disabled(isReading)
        .accessibilityLabel(Text("Add Queue Ticket"))
        .confirmationDialog(found.count > 1 ? Text("Which code is your queue ticket?") : Text("Add this queue ticket?"),
                            isPresented: Binding { !found.isEmpty } set: { if !$0 { found = [] } },
                            titleVisibility: .visible) {
            ForEach(Array(zip(found, QueueTicket.labels(tellingApart: found))), id: \.0) { link, label in
                Button {
                    if let added = store.addQueueTicket(link, to: event) { askNumber(of: added, isNew: true) }
                } label: {
                    if found.count > 1 {
                        Text(verbatim: label)
                    } else {
                        Text("Add Queue Ticket")
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // Each whole, whichever is picked: a code is whatever was printed,
            // and this is where the reader sees where it goes.
            Text(verbatim: found.map(\.absoluteString).joined(separator: "\n"))
        }
    }

    @ViewBuilder
    private var addTicketLabel: some View {
        if isReading {
            ProgressView()
                .controlSize(.small)
                .frame(width: 30, height: 30)
        } else {
            addLabel(symbol: "qrcode.viewfinder")
        }
    }

    /// The page the code points at, in the reader's browser, where the queue
    /// stands, named by the number on the ticket where one is written down.
    /// Beside it, the way to write one or take the ticket out again.
    private func row(_ ticket: QueueTicket, position: Int?) -> some View {
        HStack(spacing: 10) {
            Link(destination: ticket.link) {
                HStack(spacing: 10) {
                    Image(systemName: "qrcode")
                        .scalingFont(size: 15, weight: .semibold)
                        .foregroundStyle(Color.brandTint)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Group {
                            if let number = ticket.number {
                                Text("No. \(number)")
                            } else if let position {
                                Text("Queue Ticket \(position)")
                            } else {
                                Text("Queue Ticket")
                            }
                        }
                        .scalingFont(size: 14.5, weight: .semibold)
                        .monospacedDigit()
                        Text(verbatim: "\(ticket.link.host() ?? ticket.link.absoluteString) · \(ticket.added.formatted(date: .omitted, time: .shortened))")
                            .scalingFont(size: 12)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.right")
                        .scalingFont(size: 11, weight: .semibold)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens the queue status in your browser"))

            Menu {
                Button {
                    askNumber(of: ticket, isNew: false)
                } label: {
                    Label {
                        ticket.number == nil ? Text("Add Number…") : Text("Edit Number…")
                    } icon: {
                        Image(systemName: "number")
                    }
                }
                Button("Copy Link", systemImage: "doc.on.doc") { UIPasteboard.general.url = ticket.link }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    store.removeQueueTicket(ticket.id, from: event)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .scalingFont(size: 14, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(.rect)
            }
            .menuOrder(.fixed)
            .buttonStyle(.plain)
            .accessibilityLabel(Text("More"))
        }
        .padding(.vertical, 8)
    }

    private func askNumber(of ticket: QueueTicket, isNew: Bool) {
        typedNumber = ticket.number ?? ""
        isNumberingNew = isNew
        numbering = ticket
    }

    /// The camera, once it is allowed: asked for the first time here, and
    /// pointed at Settings where it was refused.
    private func openCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isScanning = true
        case .notDetermined:
            Task {
                if await AVCaptureDevice.requestAccess(for: .video) { isScanning = true }
            }
        default:
            isCameraRefused = true
        }
    }

    /// Reads the picture picked in Photos, which goes as soon as it is read.
    private func read(_ picture: PhotosPickerItem) {
        isReading = true
        Task {
            defer { isReading = false }
            let data = try? await picture.loadTransferable(type: Data.self)
            let links = if let data { (try? await QueueTicketScanner.links(in: data)) ?? [] } else { [URL]() }
            take(links)
        }
    }

    /// Asks about what a code held — or says it held nothing to add.
    private func take(_ links: [URL]) {
        guard !links.isEmpty else {
            isFoundNothing = true
            return
        }
        let held = Set(store.tracking(for: event).queueTickets.map(\.link))
        let new = links.filter { !held.contains($0) }
        if new.isEmpty { isAlreadyHeld = true } else { found = new }
    }
}

#if !targetEnvironment(macCatalyst)
/// The camera, reading QR codes as it looks: pointed at a queue ticket in a
/// crowd, nothing has to be held still for a shutter, and a blurred frame only
/// means the next one is read. The first code holding a web page is handed
/// over; any other is passed by.
private struct QueueTicketCamera: View {
    @Environment(\.dismiss) private var dismiss
    /// Moved once the cover has come up, which asks the scanner again: asked
    /// while it was still on its way, it may not start.
    @State private var isUp = false
    let found: (URL) -> Void

    var body: some View {
        QRCodeScanner(isUp: isUp, found: found)
            .ignoresSafeArea()
            .task {
                try? await Task.sleep(for: .milliseconds(500))
                isUp = true
            }
            .overlay(alignment: .topTrailing) {
                CloseButton { dismiss() }
                    .padding(16)
            }
            .overlay(alignment: .bottom) {
                Text("Point the camera at the QR code on your queue ticket.")
                    .scalingFont(size: 14, weight: .medium)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassCapsule()
                    .padding(24)
            }
    }
}

private struct QRCodeScanner: UIViewControllerRepresentable {
    let isUp: Bool
    let found: (URL) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr, .microQR])],
                                                qualityLevel: .accurate,
                                                isHighFrameRateTrackingEnabled: false,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let found: (URL) -> Void
        private var isDone = false

        init(found: @escaping (URL) -> Void) { self.found = found }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !isDone else { return }
            for case .barcode(let code) in items {
                guard let text = code.payloadStringValue, let link = QueueTicket.link(inCode: text) else { continue }
                isDone = true
                found(link)
                return
            }
        }
    }
}
#endif
