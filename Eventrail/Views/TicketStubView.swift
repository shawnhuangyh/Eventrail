import SwiftUI

// MARK: - What the ticket prints

/// What a ticket stub prints for one event — the day, what the event is and
/// where, its times and price, the seat and how the reader came by it — read
/// off the event and the reader's record as they stand. Nothing here is kept.
///
/// As `Eventrail v4.dc.html` §9a draws it. The ticket's own printing — its
/// labels, the day's figures, the stamp — is a ticket's, the same in every
/// language, as a Japanese ticket prints OPEN and START; the seat class is
/// printed as the ticket prints it (一般席), not in the reader's language.
nonisolated struct TicketStubFace: Hashable, Sendable {
    /// "06.14", "SAT" and "2025": the day, on the clock the times are on.
    let monthDay: String
    let weekday: String
    let year: String
    let title: String
    let venue: String
    let doors: Date?
    let starts: Date?
    /// The clock ``doors`` and ``starts`` are printed on.
    let timeZone: TimeZone
    /// What the ticket cost, as paid; nil where nothing is written.
    let price: String?
    /// The class the ticket is (``Tracking/ticketClass``), empty for none.
    let seatClass: String
    let seat: String
    /// The rubber stamp over the seat, where the record earns one.
    let stamp: Stamp?

    /// The stamp's word: 使用済 once the reader has been — the day over with
    /// a ticket held, which is what attending is (``EventStore/hasAttended(_:)``)
    /// — as e+, the official ticket platform, stamps a ticket the gate has
    /// taken; and 当選 for a lottery won for an event still ahead. A seat got
    /// first come is no win, and an event ahead with no lottery won has no
    /// stamp.
    enum Stamp: String, Sendable {
        case used = "使用済"
        case won = "当選"
    }

    /// The face for `event`, its day and times on `display`'s clock — the one
    /// Settings › Time Zone names, as the Live Activity prints on.
    init(event: Event, tracking: Tracking, on display: TimeDisplay, at now: Date = .now) {
        let shown = event.shown(on: display)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shown.timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let day = calendar.dateComponents([.year, .month, .day, .weekday], from: shown.date)
        let year = day.year ?? 0, month = day.month ?? 0, date = day.day ?? 0
        monthDay = String(format: "%02d.%02d", month, date)
        weekday = day.weekday.map { calendar.shortWeekdaySymbols[$0 - 1].uppercased() } ?? ""
        self.year = String(year)

        title = event.title
        venue = event.venue
        doors = shown.doorsOpen
        starts = shown.startsAt
        timeZone = shown.timeZone
        price = tracking.price?.formatted
        seatClass = tracking.ticketClass
        seat = tracking.seat.trimmingCharacters(in: .whitespacesAndNewlines)
        // Whether the day is over on the hall's own clock, as every list in
        // the app draws that line — never on the copy shown on another.
        if event.dayEnds <= now {
            stamp = tracking.hasTicket ? .used : nil
        } else {
            stamp = tracking.lotteries.contains { $0.isLottery && $0.isWon } ? .won : nil
        }
    }

    /// Whether a seat is written down. Without one the stub prints none — the
    /// class alone where one is known — and there is nothing to mask.
    var hasSeat: Bool { !seat.isEmpty }

    /// Whether the event sheet offers a stub: only where the reader holds a
    /// ticket (``Tracking/hasTicket`` — a lottery won or a first-come round
    /// got), ahead or past alike. Without one there is no ticket to keep.
    static func offered(for tracking: Tracking) -> Bool {
        tracking.hasTicket
    }

    var hasTimes: Bool { doors != nil || starts != nil }

    /// How wide `seat` prints, in ems, as the design measures it for its mask:
    /// a full-width character one, a space under a third, anything else
    /// about two thirds. The mask is drawn this long, so it reads as a seat
    /// without saying which.
    static func maskWidth(of seat: String) -> CGFloat {
        seat.unicodeScalars.reduce(0) { width, scalar in
            if scalar.properties.isWhitespace { return width + 0.3 }
            switch scalar.value {
            case 0x3000...0x9FFF, 0xFF00...0xFFEF: return width + 1
            default: return width + 0.62
            }
        }
    }
}

/// What the reader chose to print, for as long as the composer is open — not
/// remembered between visits, as the design's own reset leaves it.
struct TicketStubOptions: Hashable {
    var look: TicketStubLook = .light
    var showsFlyer = false
    var masksSeat = true
    var showsTimes = true
    var showsPrice = true
}

// MARK: - The two looks

/// The ticket's two looks, each with the canvas it is laid on. Fixed colours
/// rather than the app's: the stub is a picture, and reads the same whatever
/// the phone it is saved on is set to.
enum TicketStubLook: String, CaseIterable, Identifiable {
    case light, night

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .light: "Light"
        case .night: "Night"
        }
    }

    /// What the composer's chrome over this canvas is drawn in.
    var colorScheme: ColorScheme { self == .light ? .light : .dark }

    /// The ticket's main part, top to bottom.
    var paper: LinearGradient {
        switch self {
        case .light: LinearGradient(colors: [Color(hex: 0xFDF9F1), Color(hex: 0xF8F1E3)], startPoint: .top, endPoint: .bottom)
        case .night: LinearGradient(colors: [Color(hex: 0x26222F), Color(hex: 0x1F1C28)], startPoint: .top, endPoint: .bottom)
        }
    }

    /// The part torn off, below the perforation.
    var stub: Color { self == .light ? Color(hex: 0xF1E7D3) : Color(hex: 0x2A2636) }
    var ink: Color { self == .light ? Color(hex: 0x1F1B16) : Color(hex: 0xF5F3FA) }
    var muted: Color { ink.opacity(self == .light ? 0.56 : 0.6) }
    var faint: Color { ink.opacity(0.4) }
    var rule: Color { ink.opacity(self == .light ? 0.18 : 0.16) }
    var accent: Color { self == .light ? Color(hex: 0xC2412F) : Color(hex: 0xFFB340) }
    /// The stamp's ink: e+'s red, a shade lighter on the night look so it
    /// reads on the dark paper.
    var stamp: Color { self == .light ? Color(hex: 0xD7352D) : Color(hex: 0xFF5F52) }
}

/// What the ticket is laid on: the app's wash for the light look, a night sky
/// for the other — behind the composer's preview and in the saved image.
struct TicketCanvas: View {
    let look: TicketStubLook

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                switch look {
                case .light:
                    Color(hex: 0xF3F1F6)
                    WashBackground.blob(Color(hex: 0xCCDEFF).opacity(0.95), at: UnitPoint(x: 0.12, y: 0),
                                        radii: (0.70, 0.42), fade: 0.70, in: size)
                    WashBackground.blob(Color(hex: 0xFFD5D2).opacity(0.9), at: UnitPoint(x: 0.92, y: 0.08),
                                        radii: (0.60, 0.38), fade: 0.70, in: size)
                    WashBackground.blob(Color(hex: 0xCEEED8).opacity(0.8), at: UnitPoint(x: 0.48, y: 1.02),
                                        radii: (0.70, 0.42), fade: 0.72, in: size)
                case .night:
                    Color(hex: 0x14121B)
                    WashBackground.blob(Color(hex: 0x5A70B8).opacity(0.55), at: UnitPoint(x: 0.18, y: 0),
                                        radii: (0.80, 0.48), fade: 0.70, in: size)
                    WashBackground.blob(Color(hex: 0xCE4F61).opacity(0.32), at: UnitPoint(x: 0.90, y: 1),
                                        radii: (0.70, 0.44), fade: 0.70, in: size)
                }
            }
        }
    }
}

// MARK: - The ticket

/// The ticket itself, 300 points wide: the flyer where it is asked for, the
/// day, the event and its hall, the times and the price — then, below a
/// perforation, the seat and the stamp.
///
/// What is saved and shared, and what the composer previews. A masked seat is
/// not drawn under its mask: the mask stands in its place, so the picture
/// holds no seat to unblur or crop back.
struct TicketStub: View {
    let face: TicketStubFace
    let options: TicketStubOptions
    /// The event's flyer, printed across the top where ``TicketStubOptions/showsFlyer``.
    let flyer: UIImage?

    static let width: CGFloat = 300
    private static let seatSize: CGFloat = 22

    private var look: TicketStubLook { options.look }

    var body: some View {
        VStack(spacing: 0) {
            main
                .background(look.paper)
                .clipShape(TicketHalf(perforation: .bottom))
            stub
                .background(look.stub)
                .clipShape(TicketHalf(perforation: .top))
        }
        .frame(width: Self.width)
        .foregroundStyle(look.ink)
        .compositingGroup()
        .shadow(color: Color(hex: 0x14121E).opacity(0.26), radius: 15, y: 18)
    }

    /// The design's Barlow Condensed, as the system draws a condensed face.
    private static func condensed(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            if options.showsFlyer, let flyer {
                Image(uiImage: flyer)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.width, height: 170)
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Text(verbatim: "EVENTRAIL")
                        .font(Self.condensed(11, .bold))
                        .tracking(11 * 0.28)
                        .foregroundStyle(look.accent)
                    Rectangle()
                        .fill(look.rule)
                        .frame(height: 1)
                }
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(verbatim: face.monthDay)
                        .font(Self.condensed(56, .bold))
                        .tracking(-0.56)
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: face.weekday)
                            .font(Self.condensed(14, .bold))
                            .tracking(14 * 0.16)
                            .foregroundStyle(look.accent)
                        Text(verbatim: face.year)
                            .font(Self.condensed(14, .semibold))
                            .tracking(14 * 0.1)
                            .foregroundStyle(look.muted)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: face.title)
                        .font(.system(size: 17, weight: .black))
                        .lineSpacing(3)
                        .lineLimit(4)
                    if !face.venue.isEmpty {
                        Text(verbatim: face.venue)
                            .font(.system(size: 12.5, weight: .bold))
                            .lineSpacing(2)
                            .foregroundStyle(look.muted)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                if !facts.isEmpty { factsRow }
            }
            .padding(EdgeInsets(top: 20, leading: 22, bottom: 22, trailing: 22))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct Fact: Identifiable {
        let label: String
        let value: Text
        var id: String { label }
    }

    /// The doors and the start where the page published them, and the price
    /// where one is written — each only where the reader asked for it.
    private var facts: [Fact] {
        var facts: [Fact] = []
        if options.showsTimes {
            if let doors = face.doors { facts.append(Fact(label: "OPEN", value: time(doors))) }
            if let starts = face.starts { facts.append(Fact(label: "START", value: time(starts))) }
        }
        if options.showsPrice, let price = face.price {
            facts.append(Fact(label: "PRICE", value: Text(verbatim: price)))
        }
        return facts
    }

    private var factsRow: some View {
        HStack(alignment: .top, spacing: 26) {
            ForEach(facts) { fact in
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: fact.label)
                        .font(Self.condensed(10, .semibold))
                        .tracking(10 * 0.2)
                        .foregroundStyle(look.muted)
                    fact.value
                        .font(Self.condensed(22, .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(look.rule)
                .frame(height: 1)
        }
    }

    /// A time as the reader's locale writes it, with the AM or PM a
    /// twelve-hour clock carries set small beside the digits — as the event
    /// sheet prints its times.
    private func time(_ instant: Date) -> Text {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = face.timeZone
        var time = instant.formatted(style.attributedStyle)
        let periods = time.runs[\.dateField].compactMap { field, range in
            field == .amPM ? range : nil
        }
        for range in periods {
            time[range].font = Self.condensed(13, .bold)
        }
        return Text(time)
    }

    /// The seat and its class, as far as either is written down, over the
    /// fine print — and the stamp beside them.
    private var stub: some View {
        VStack(alignment: .leading, spacing: 10) {
            if face.hasSeat || !face.seatClass.isEmpty { seatLabel }
            if face.hasSeat {
                seat
                    // Clear of the stamp, which takes some 65 points of the
                    // line once tilted.
                    .padding(.trailing, 68)
            }
            Text(verbatim: "KEEPSAKE · NOT VALID FOR ENTRY")
                .font(Self.condensed(9, .semibold))
                .tracking(9 * 0.22)
                .foregroundStyle(look.faint)
        }
        .padding(EdgeInsets(top: 20, leading: 22, bottom: 16, trailing: 22))
        // Tall enough for the stamp however little is printed above the fine
        // print, which keeps to the foot.
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .bottomLeading)
        .overlay(alignment: .top) {
            Perforation()
                .stroke(look.rule, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(height: 1.5)
                .padding(.horizontal, 16)
        }
        .overlay(alignment: .trailing) {
            // Always, where the record earns one: it is what the ticket went
            // on to be, not a detail to leave off.
            if let stamp = face.stamp {
                stampMark(stamp)
                    .padding(.trailing, 14)
            }
        }
    }

    /// SEAT, and the class beside it as the ticket prints it.
    private var seatLabel: some View {
        HStack(spacing: 8) {
            Text(verbatim: "SEAT")
                .font(Self.condensed(10, .semibold))
                .tracking(10 * 0.2)
                .foregroundStyle(look.muted)
            if !face.seatClass.isEmpty {
                Text(verbatim: face.seatClass)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(look.accent)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(look.accent, lineWidth: 1.2)
                    }
            }
        }
    }

    /// The seat, or a mosaic as long as it would print in its place.
    @ViewBuilder
    private var seat: some View {
        let font = Font.system(size: Self.seatSize, weight: .black)
        if options.masksSeat {
            // A line of the seat's own type, unseen, so a masked stub is as
            // tall as one with its seat showing.
            Text(verbatim: " ")
                .font(font)
                .hidden()
                .frame(maxWidth: TicketStubFace.maskWidth(of: face.seat) * Self.seatSize, alignment: .leading)
                .overlay {
                    SeatMask(color: look.ink)
                        .frame(height: Self.seatSize * 0.82)
                }
                .accessibilityElement()
                .accessibilityLabel(Text("Masked"))
        } else {
            Text(verbatim: face.seat)
                .font(font)
                .monospacedDigit()
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A rubber stamp, a little crooked, as e+ stamps a ticket the gate has
    /// taken: the word alone in heavy type, inside one thick rounded frame.
    private func stampMark(_ stamp: TicketStubFace.Stamp) -> some View {
        Text(verbatim: stamp.rawValue)
            .font(.system(size: 17, weight: .black))
            .foregroundStyle(look.stamp)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(look.stamp, lineWidth: 3)
            }
            .rotationEffect(.degrees(-12))
            .opacity(0.9)
    }
}

/// One part of the ticket either side of the perforation: its far corners
/// rounded, and a half circle bitten out of each end of the perforation.
nonisolated private struct TicketHalf: Shape {
    /// Which edge of this part the perforation runs along.
    let perforation: VerticalEdge

    func path(in rect: CGRect) -> Path {
        let corner: CGFloat = 16, notch: CGFloat = 12
        let body = UnevenRoundedRectangle(
            topLeadingRadius: perforation == .bottom ? corner : 0,
            bottomLeadingRadius: perforation == .top ? corner : 0,
            bottomTrailingRadius: perforation == .top ? corner : 0,
            topTrailingRadius: perforation == .bottom ? corner : 0,
            style: .continuous
        ).path(in: rect)
        let y = perforation == .top ? rect.minY : rect.maxY
        var notches = Path()
        notches.addEllipse(in: CGRect(x: rect.minX - notch, y: y - notch, width: notch * 2, height: notch * 2))
        notches.addEllipse(in: CGRect(x: rect.maxX - notch, y: y - notch, width: notch * 2, height: notch * 2))
        return body.subtracting(notches)
    }
}

/// The line the stub tears along.
nonisolated private struct Perforation: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// Six-point cells of ink at uneven strengths, three rows deep, the design's
/// strip of eight repeated along the width.
private struct SeatMask: View {
    let color: Color

    private static let cell: CGFloat = 6
    private static let strengths: [Double] = [
        0.90, 0.55, 0.78, 0.40, 0.86, 0.62, 0.95, 0.50,
        0.60, 0.82, 0.45, 0.92, 0.52, 0.74, 0.66, 0.88,
        0.80, 0.48, 0.70, 0.96, 0.42, 0.62, 0.90, 0.56,
    ]

    var body: some View {
        Canvas { context, size in
            let cell = size.height / 3
            let columns = Int((size.width / cell).rounded(.up))
            for row in 0..<3 {
                for column in 0..<columns {
                    let square = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    context.fill(Path(square), with: .color(color.opacity(Self.strengths[row * 8 + column % 8])))
                }
            }
        }
        .clipShape(.rect(cornerRadius: 2))
    }
}

// MARK: - The saved image

/// The ticket as a picture: on its canvas, 1080 × 1920 — the shape of a story,
/// so it is posted whole rather than cropped — and as a PNG file for Photos
/// and the share sheet.
enum TicketStubImage {
    /// The canvas in points, drawn at 3×.
    static let canvas = CGSize(width: 360, height: 640)

    /// Draws `ticket` on its canvas, at 95 % of its size — less where the flyer
    /// makes it too tall to leave a margin over and under it.
    static func render(_ ticket: TicketStub) -> UIImage? {
        let content = ticket
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.colorScheme, .light)
            .environment(\.legibilityWeight, .regular)
        var height: CGFloat = 0
        ImageRenderer(content: content).render { size, _ in height = size.height }
        guard height > 0 else { return nil }
        let scale = min(0.95, 580 / height)
        let renderer = ImageRenderer(content: content
            .scaleEffect(scale)
            .frame(width: canvas.width, height: canvas.height)
            .background { TicketCanvas(look: ticket.options.look) })
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Writes `image` as a PNG named for the event, in a folder of its own in
    /// the temporary directory — a file the share sheet can compose its own
    /// preview of, and Photos can be handed as it is.
    @concurrent
    nonisolated static func write(_ image: UIImage, named name: String) async throws -> URL {
        guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        let folder = folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "\(name).png", directoryHint: .notDirectory)
        try data.write(to: file, options: .atomic)
        return file
    }

    /// Throws away a file ``write(_:named:)`` made, with its folder.
    nonisolated static func discard(_ file: URL) {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    /// Throws away every file ``write(_:named:)`` has made — what a composer
    /// closed by the app being quit left behind.
    nonisolated static func discardAll() {
        try? FileManager.default.removeItem(at: folder)
    }

    nonisolated private static var folder: URL {
        URL.temporaryDirectory.appending(path: "Ticket Stubs", directoryHint: .isDirectory)
    }
}

// MARK: - The composer

/// A keepsake image of the reader's ticket for one event, opened from the
/// event's sheet once a seat is on record: the ticket on its canvas, a look
/// for it, whether the flyer is printed, whether the seat is masked, which
/// details are printed — and Save Image and Share.
///
/// As `Eventrail v4.dc.html` §9a draws it. The preview and its chrome take
/// the look's own scheme, since the preview is the picture that will be saved;
/// the controls under it follow the phone's.
///
/// The image is drawn again a moment after each change and written to a file,
/// and nothing is shared or saved until the file matches what is on screen —
/// a seat masked a second ago is never sent unmasked.
struct TicketStubView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Which clock the day and times are printed on — see ``TimeDisplay``.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue

    let event: Event

    @State private var options = TicketStubOptions()
    /// The event's flyer, once the cache has handed it over; the Flyer switch
    /// is offered only then.
    @State private var flyer: UIImage?
    /// How tall the ticket is unscaled, so the preview can fit it.
    @State private var ticketHeight: CGFloat = 0
    /// The image as last drawn, and what it was drawn from.
    @State private var drawn: Drawn?
    /// Counted up as each save lands, for the tap and the word that say so.
    @State private var saves = 0
    @State private var showsSaved = false
    @State private var saveFailure: PhotoSaveFailure?

    /// What the image is drawn from: when any of it changes, it is drawn again.
    private struct Drawing: Hashable {
        let face: TicketStubFace
        let options: TicketStubOptions
        let hasFlyer: Bool
    }

    private struct Drawn {
        let drawing: Drawing
        let file: URL
    }

    private var face: TicketStubFace {
        let event = store.event(id: event.id) ?? event
        return TicketStubFace(event: event, tracking: store.tracking(for: event), on: timeDisplay)
    }

    var body: some View {
        let face = face
        let drawing = Drawing(face: face, options: options, hasFlyer: flyer != nil)
        let file = drawn?.drawing == drawing ? drawn?.file : nil
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                preview(face)
            }
            .environment(\.colorScheme, options.look.colorScheme)
            controls(face, file: file)
        }
        .background { TicketCanvas(look: options.look).ignoresSafeArea() }
        .animation(.snappy, value: options)
        .task(id: event.imageURL) { await loadFlyer() }
        .task(id: drawing) {
            // A moment after the last change, so a run of taps draws once.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await draw(drawing)
        }
        .task(id: saves) {
            guard saves > 0 else { return }
            showsSaved = true
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            showsSaved = false
        }
        .animation(.snappy, value: showsSaved)
        .sensoryFeedback(.success, trigger: saves)
        .sensoryFeedback(.selection, trigger: options)
        .photoSaveFailureAlert("Couldn't Save the Image", failure: $saveFailure)
        // Before the first image is written, so only this composer's is kept.
        .onAppear { TicketStubImage.discardAll() }
        .onDisappear {
            if let drawn { TicketStubImage.discard(drawn.file) }
        }
    }

    /// The flyer as the cache holds it — at once where this device has it,
    /// as the sheet behind this one almost always does.
    private func loadFlyer() async {
        guard let url = event.imageURL else { return }
        if let stored = await ImageCache.shared.storedImage(for: url) {
            flyer = stored
        } else if let fetched = await ImageCache.shared.image(for: url) {
            flyer = fetched
        }
    }

    /// Draws the image for `drawing` and writes it to a file, throwing away
    /// the one it replaces.
    private func draw(_ drawing: Drawing) async {
        let ticket = TicketStub(face: drawing.face, options: drawing.options, flyer: drawing.hasFlyer ? flyer : nil)
        guard let image = TicketStubImage.render(ticket),
              let file = try? await TicketStubImage.write(image, named: ImageCache.fileName(drawing.face.title))
        else { return }
        guard !Task.isCancelled else {
            TicketStubImage.discard(file)
            return
        }
        if let drawn { TicketStubImage.discard(drawn.file) }
        drawn = Drawn(drawing: drawing, file: file)
    }

    // MARK: Chrome

    private var header: some View {
        ZStack {
            Text("Ticket Stub")
                .font(.system(size: 17, weight: .bold))
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassCircle(interactive: true)
                .accessibilityLabel("Close")
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
    }

    /// The ticket as it will be saved, scaled down only where the room left
    /// over the controls is too short for it.
    private func preview(_ face: TicketStubFace) -> some View {
        GeometryReader { proxy in
            let room = CGSize(width: proxy.size.width - 32, height: proxy.size.height - 24)
            let scale = ticketHeight > 0
                ? max(0.1, min(1, room.height / ticketHeight, room.width / TicketStub.width))
                : 1
            TicketStub(face: face, options: options, flyer: flyer)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { ticketHeight = $0 }
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .combine)
        .overlay(alignment: .top) {
            if showsSaved { savedNote }
        }
    }

    /// "Saved to Photos", over the top of the preview for a moment.
    private var savedNote: some View {
        Label("Saved to Photos", systemImage: "checkmark")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(Color(hex: 0x1C1A22).opacity(0.86), in: .capsule)
            .shadow(color: Color(hex: 0x14121E).opacity(0.2), radius: 10, y: 8)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: Controls

    /// Three rows, one kind of control each: the look, what the ticket
    /// prints, and what to do with it.
    private func controls(_ face: TicketStubFace, file: URL?) -> some View {
        VStack(spacing: 16) {
            Picker("Style", selection: $options.look) {
                ForEach(TicketStubLook.allCases) { look in
                    Text(look.label).tag(look)
                }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 6) {
                optionTiles(face)
            }
            HStack(spacing: 10) {
                Button {
                    Task { await save(file) }
                } label: {
                    Label("Save Image", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .tint(.primary)
                .disabled(file == nil)
                shareButton(file)
            }
            .font(.system(size: 16, weight: .semibold))
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
        }
        .padding(18)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                .fill(.background)
                .shadow(color: Color(hex: 0x1E1B2D).opacity(0.08), radius: 12, y: -8)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Everything the ticket can print or leave off, as one row of tiles that
    /// all work the same way — the seat's mask first, since it is the one to
    /// think about before sharing, then only what this event has to print.
    @ViewBuilder
    private func optionTiles(_ face: TicketStubFace) -> some View {
        if face.hasSeat {
            optionTile("Mask Seat", systemImage: "eye.slash", isOn: $options.masksSeat)
        }
        if flyer != nil {
            optionTile("Flyer", systemImage: "photo", isOn: $options.showsFlyer)
        }
        if face.hasTimes {
            optionTile("Times", systemImage: "clock", isOn: $options.showsTimes)
        }
        if face.price != nil {
            optionTile("Price", systemImage: "banknote", isOn: $options.showsPrice)
        }
    }

    /// One option: its symbol over its name, filled and tinted in the app's
    /// blue while it is on, outlined and grey while it is off. VoiceOver is
    /// handed the switch it stands for.
    private func optionTile(_ title: LocalizedStringKey, systemImage: String, isOn: Binding<Bool>) -> some View {
        let on = isOn.wrappedValue
        return Button {
            isOn.wrappedValue.toggle()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .symbolVariant(on ? .fill : .none)
                    .font(.system(size: 17, weight: .medium))
                    .frame(height: 22)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(on ? Color.brandTint : Color.secondary)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(on ? Color.brandTint.opacity(0.14) : Color.primary.opacity(0.06),
                        in: .rect(cornerRadius: 14, style: .continuous))
            .contentShape(.rect(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(title, isOn: isOn)
        }
    }

    /// The share sheet, handed the image file — once it is drawn for what is
    /// on screen, and greyed until then.
    @ViewBuilder
    private func shareButton(_ file: URL?) -> some View {
        let label = Label("Share", systemImage: "square.and.arrow.up")
            .frame(maxWidth: .infinity)
        Group {
            if let file {
                ShareLink(item: file) { label }
            } else {
                Button {} label: { label }
                    .disabled(true)
            }
        }
        .buttonStyle(.glassProminent)
        .tint(Color.brandTint)
    }

    /// Adds the image to the reader's photos — see ``PhotoSaving``.
    private func save(_ file: URL?) async {
        guard let file else { return }
        do {
            try await PhotoSaving.add(file)
            saves += 1
        } catch {
            saveFailure = error
        }
    }
}

fileprivate extension Color {
    /// A colour the design names in hex.
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255,
                  green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
