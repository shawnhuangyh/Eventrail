import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

// MARK: - The wash

/// What every home-screen widget sits on, as the design's widget boards draw
/// it: the app's three-corner wash, its ellipses sized to the widget rather
/// than to a phone's screen — and on the day of the next event, warmed with
/// the ticket's amber.
struct WidgetWash: View {
    var warm = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color.washBase
                if warm {
                    Self.blob(.washAmber, at: UnitPoint(x: 0.20, y: 0), radii: (0.90, 0.70), in: size)
                    Self.blob(Color.washThree.opacity(0.8), at: UnitPoint(x: 0.48, y: 1.05), radii: (0.80, 0.55), in: size)
                } else {
                    Self.blob(.washOne, at: UnitPoint(x: 0.12, y: 0), radii: (0.70, 0.55), in: size)
                    Self.blob(.washTwo, at: UnitPoint(x: 0.95, y: 0.08), radii: (0.60, 0.50), in: size)
                    Self.blob(.washThree, at: UnitPoint(x: 0.48, y: 1.05), radii: (0.80, 0.55), in: size)
                }
            }
        }
    }

    /// One of the design's radial gradients — `ellipse 70% 55% at 12% 0%` —
    /// its radii fractions of the widget, and clear at its edge.
    private static func blob(_ color: Color, at center: UnitPoint,
                             radii: (x: CGFloat, y: CGFloat), in size: CGSize) -> some View {
        EllipticalGradient(
            stops: [.init(color: color, location: 0), .init(color: color.opacity(0), location: 1)],
            center: .center
        )
        .frame(width: size.width * radii.x * 2, height: size.height * radii.y * 2)
        .position(x: size.width * center.x, y: size.height * center.y)
    }
}

// MARK: - Pieces

/// The seat, in the ticket's orange — "SEAT 2階 C列 14番".
struct SeatCapsule: View {
    let seat: String

    var body: some View {
        HStack(spacing: 5) {
            Text("Seat")
                .font(.system(size: 8, weight: .bold))
                .kerning(0.6)
                .textCase(.uppercase)
                .opacity(0.8)
            Text(verbatim: seat)
                .font(.system(size: 11.5, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.8)
        }
        .lineLimit(1)
        .foregroundStyle(Color.ticketInk)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Color.trackTicket.opacity(0.14), in: .capsule)
    }
}

/// An event's flyer, from the copy the timeline kept (``WidgetFlyers``) —
/// or the design's empty tile where there is none yet.
struct FlyerTile: View {
    let file: URL?

    var body: some View {
        if let file, let image = UIImage(contentsOfFile: file.path(percentEncoded: false)) {
            Image(uiImage: image)
                .resizable()
                .widgetAccentedRenderingMode(.accentedDesaturated)
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle().fill(Color.trackInterest.opacity(0.16))
        }
    }
}

/// A dot in front of a word, as the design marks a status or a stage.
struct DotLabel: View {
    let text: Text
    let tint: Color
    var dot: CGFloat = 6

    var body: some View {
        HStack(spacing: dot < 7 ? 4 : 7) {
            Circle().fill(tint).frame(width: dot, height: dot)
            text
        }
        .foregroundStyle(tint)
    }
}

/// A count, large, with its unit small beside it — "4 DAYS".
struct BigCount: View {
    let count: Int
    let unit: Text
    var size: CGFloat = 42
    var tint: Color = .brandTint

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(count, format: .number)
                .font(.system(size: size, weight: .bold))
                .kerning(-size * 0.028)
                .monospacedDigit()
            unit
                .font(.system(size: 12, weight: .heavy))
                .kerning(0.4)
                .textCase(.uppercase)
                .opacity(0.85)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(tint)
        .widgetAccentable()
    }
}

/// A widget's name over its content, with its symbol in the app's tint.
struct WidgetHeader: View {
    let title: LocalizedStringKey
    let symbol: String
    var tint: Color = .brandTint

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(tint)
                .widgetAccentable()
            Text(title)
                .font(.system(size: 12, weight: .bold))
        }
        .lineLimit(1)
    }
}

/// A round's results day as a calendar tile — the month over the day — as
/// the Lotteries widgets draw it: filled in the ticket's orange once the day
/// has come, the app's blue while it is ahead, and an outline reading DAY ?
/// where none was written down.
struct LotteryTile: View {
    let round: WidgetRound
    let now: Date

    var body: some View {
        let isOut = round.isOut(asOf: now)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(spacing: 1) {
            Group {
                if let day = round.day {
                    Text(verbatim: day.date().formatted(.gregorian().month(.abbreviated)))
                } else {
                    Text(String(localized: "lottery.tile.noDay", defaultValue: "Day",
                                comment: "Over a question mark, on a lottery round's tile where no results day was announced."))
                }
            }
            .font(.system(size: 8.5, weight: .bold))
            .kerning(0.5)
            .textCase(.uppercase)
            .opacity(0.85)
            Text(verbatim: round.day.map { $0.day.formatted() } ?? "?")
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(width: 36, height: 40)
        .foregroundStyle(isOut ? AnyShapeStyle(.white)
                         : round.day == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.brandTint))
        .background {
            if isOut {
                shape.fill(Color.solidTicket)
            } else if round.day == nil {
                shape.strokeBorder(Color.primary.opacity(0.28), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5]))
            } else {
                shape.fill(Color.trackInterest.opacity(0.14))
            }
        }
        .widgetAccentable()
    }
}

extension Color {
    /// The design's orange and green at full strength in either appearance,
    /// for what is filled behind white type — the out tile, the Won button.
    /// The palette's own lighten in dark mode, and white on them did not read.
    static let solidTicket = Color(red: 0xBE / 255, green: 0x71 / 255, blue: 0)
    static let solidWon = Color(red: 0x1D / 255, green: 0x87 / 255, blue: 0x42 / 255)
}

// MARK: - Words

/// The days and times the widgets print, each on the clock it is handed.
enum WidgetText {
    /// The unit beside a large count of days — "DAY" or "DAYS", the count
    /// drawn apart from it. Two words rather than a plural, which the
    /// catalog will not keep without the number in it.
    static func daysUnit(_ count: Int) -> Text {
        count == 1 ? Text("DAY") : Text("DAYS")
    }

    /// "In 4 days", "Tomorrow", "Today" — standing on its own.
    static func relative(days: Int) -> String {
        relative(days: days, context: .beginningOfSentence)
    }

    /// "in 4 days", "tomorrow" — inside a sentence.
    static func relativeInline(days: Int) -> String {
        relative(days: days, context: .middleOfSentence)
    }

    private static func relative(days: Int, context: Formatter.Context) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        formatter.formattingContext = context
        return formatter.localizedString(from: DateComponents(day: days))
    }

    /// "Sun, Oct 18".
    static func day(_ date: Date, in zone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        style.timeZone = zone
        return date.formatted(style)
    }

    /// "Sun 18" — the weekday and the day alone, for the one line of an
    /// inline accessory.
    static func weekdayAndDay(_ date: Date, in zone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day()
        style.timeZone = zone
        return date.formatted(style)
    }

    /// "17:00", "5:00 PM".
    static func time(_ date: Date, in zone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone
        return date.formatted(style)
    }

    /// "17:00", "5:00" — the AM or PM left off, as the compact island leaves
    /// it, for the round accessory, which has room for five characters.
    static func clock(_ date: Date, in zone: TimeZone) -> String {
        var style = Date.FormatStyle().hour(.defaultDigits(amPM: .omitted)).minute()
        style.timeZone = zone
        return date.formatted(style)
    }

    /// "Oct 20", with the year only where it is not this one.
    static func short(_ day: CalendarDay, asOf now: Date) -> String {
        let thisYear = Calendar.gregorian().component(.year, from: now) == day.year
        return thisYear
            ? day.date().formatted(.dateTime.month(.abbreviated).day())
            : day.date().formatted(.dateTime.month(.abbreviated).day().year())
    }
}

// MARK: - Flyers

/// The flyers the widgets draw, fetched by the extension itself from the host
/// the app reads them from — the one thing it asks anything of — and kept
/// small, as the watch keeps its own.
///
/// Fetched as a timeline is made, never as a widget is drawn, which cannot
/// wait on anything; a widget is drawn from the file. Kept per event in the
/// extension's Caches and fetched again after a week, since the host files a
/// replaced flyer under the same address; a copy the host fails to answer for
/// stands.
nonisolated enum WidgetFlyers {
    private static let window: TimeInterval = 7 * 24 * 60 * 60
    /// The longest side kept, in pixels: the small On This Day widget filled
    /// edge to edge, at 3×. A widget's picture is archived with it, and the
    /// system refuses to draw one whose images are much larger than it is.
    private static let side = 540

    private static var folder: URL {
        URL.cachesDirectory.appending(path: "Flyers", directoryHint: .isDirectory)
    }

    private static func file(for id: String) -> URL {
        folder.appending(path: "\(id).jpg", directoryHint: .notDirectory)
    }

    /// The kept copy of each flyer named, by event — fetched where none is
    /// kept or the one kept is over a week old.
    static func files(for flyers: [(id: String, url: URL?)]) async -> [String: URL] {
        var wanted: [String: URL] = [:]
        for flyer in flyers { if let url = flyer.url { wanted[flyer.id] = url } }
        prune()
        return await withTaskGroup(of: (String, URL?).self) { group in
            for (id, url) in wanted {
                group.addTask { (id, await file(for: id, at: url)) }
            }
            var files: [String: URL] = [:]
            for await (id, file) in group {
                if let file { files[id] = file }
            }
            return files
        }
    }

    private static func file(for id: String, at url: URL) async -> URL? {
        let file = file(for: id)
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let modified, -modified.timeIntervalSinceNow < window { return file }
        let request = URLRequest(url: url, timeoutInterval: 10)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let small = downsized(data)
        else { return modified == nil ? nil : file }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? small.write(to: file, options: .atomic)
        return file
    }

    /// Throws away the copies nothing has fetched again for a month — the
    /// flyers of events that are no longer next, or no longer remembered
    /// today.
    private static func prune() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, -modified.timeIntervalSinceNow > 4 * window {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private static func downsized(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: side,
              ] as CFDictionary)
        else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}

// MARK: - Midnights

nonisolated extension Calendar {
    /// The next `count` midnights after `now` on this calendar's clock — when
    /// a widget's day count moves on.
    func midnights(after now: Date, count: Int) -> [Date] {
        var midnight = startOfDay(for: now)
        return (0 ..< count).compactMap { _ in
            guard let next = date(byAdding: .day, value: 1, to: midnight) else { return nil }
            midnight = next
            return next
        }
    }
}
