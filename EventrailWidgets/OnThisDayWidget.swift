import SwiftUI
import WidgetKit

/// The events the reader went to on today's date in earlier years, as the
/// design's On This Day board draws them: the flyer first on the small
/// widget, the flyer beside the year, the hall and the reader's note on the
/// medium — taking a turn each hour where the day has several — and on a day
/// with none, when the next one comes.
///
/// Read as the app's On This Day reads them (`OnThisDay`): an event in the
/// library with a ticket held, whose day on its hall's clock has today's
/// month and day in an earlier year, the most recent first. The widget picks
/// the day's from every event gone to, so it turns over at midnight without
/// the app.
struct OnThisDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.onThisDay, provider: OnThisDayProvider()) { entry in
            OnThisDayWidgetView(entry: entry)
        }
        .configurationDisplayName("On This Day")
        .description("The events you went to on today's date in earlier years.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        // The small widget is its flyer, edge to edge; the rest pad
        // themselves by the margins they would have had.
        .contentMarginsDisabled()
    }
}

nonisolated struct OnThisDayEntry: TimelineEntry, Sendable {
    let date: Date
    /// Today on the reader's calendar, as of ``date``.
    let day: CalendarDay
    /// The day's memories, the most recent year first.
    let memories: [WidgetMemory]
    /// Which of them is shown.
    let index: Int
    /// The next day with a memory, on a day with none — within the year.
    let next: CalendarDay?
    /// The flyers, by event, as the timeline kept them.
    let flyers: [String: URL]

    var memory: WidgetMemory? { memories.isEmpty ? nil : memories[index % memories.count] }
}

nonisolated struct OnThisDayProvider: TimelineProvider {
    func placeholder(in context: Context) -> OnThisDayEntry {
        OnThisDayEntry(date: .now, day: CalendarDay(.now), memories: WidgetSamples.memories(),
                       index: 0, next: nil, flyers: [:])
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (OnThisDayEntry) -> Void) {
        let isPreview = context.isPreview
        let placeholder = placeholder(in: context)
        Task {
            let entry = await Self.firstEntry(at: .now) ?? placeholder
            completion(isPreview && entry.memory == nil ? placeholder : entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<OnThisDayEntry>) -> Void) {
        Task { completion(await Self.timeline(at: .now)) }
    }

    /// Today and tomorrow: an entry as each day starts, and on a day with
    /// several memories one each hour, turning to the next.
    static func timeline(at now: Date) async -> Timeline<OnThisDayEntry> {
        let plans = plans(at: now)
        let flyers = await WidgetFlyers.files(for: plans.flatMap(\.memories).map { ($0.id, $0.flyer) })
        let entries = plans.map {
            OnThisDayEntry(date: $0.time, day: $0.day, memories: $0.memories, index: $0.index,
                           next: $0.next, flyers: flyers)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// The timeline's first entry alone, with only its own memories' flyers
    /// fetched — what a snapshot draws.
    static func firstEntry(at now: Date) async -> OnThisDayEntry? {
        guard let first = plans(at: now).first else { return nil }
        let flyers = await WidgetFlyers.files(for: first.memories.map { ($0.id, $0.flyer) })
        return OnThisDayEntry(date: first.time, day: first.day, memories: first.memories, index: first.index,
                              next: first.next, flyers: flyers)
    }

    /// The entries of ``timeline(at:)``, before their flyers are fetched.
    private static func plans(
        at now: Date
    ) -> [(time: Date, day: CalendarDay, memories: [WidgetMemory], index: Int, next: CalendarDay?)] {
        let all = (WidgetLibrary.read() ?? .empty).memories
        let calendar = Calendar.gregorian()
        let starts = [now] + calendar.midnights(after: now, count: 2)
        var plans: [(time: Date, day: CalendarDay, memories: [WidgetMemory], index: Int, next: CalendarDay?)] = []
        for (start, end) in zip(starts, starts.dropFirst()) {
            let day = CalendarDay(start, in: calendar)
            let memories = Self.memories(on: day, in: all)
            let next = memories.isEmpty ? Self.nextDay(after: day, in: all, calendar: calendar) : nil
            var time = start
            repeat {
                // By the hour of the day, so a timeline made again mid-hour
                // shows the one already up.
                let index = memories.isEmpty ? 0 : calendar.component(.hour, from: time) % memories.count
                plans.append((time, day, memories, index, next))
                guard memories.count > 1,
                      let hour = calendar.dateInterval(of: .hour, for: time)?.end else { break }
                time = hour
            } while time < end
        }
        return plans
    }

    /// The events gone to on `day`'s date in an earlier year, the most recent
    /// year first — as `OnThisDay` reads them.
    static func memories(on day: CalendarDay, in all: [WidgetMemory]) -> [WidgetMemory] {
        all.filter { $0.day.year < day.year && $0.day.comesRound(on: day) }
            .sorted { (day.year - $0.day.year, $0.sortDate) < (day.year - $1.day.year, $1.sortDate) }
    }

    /// The first day after `day`, within the year, that has a memory.
    ///
    /// The earliest year of each date anything happened on, gathered in one
    /// pass, and each day of the year looked up in it — not every memory held
    /// against each of the year's days, which for a library of nine hundred
    /// was a third of a million comparisons a day without one.
    static func nextDay(after day: CalendarDay, in all: [WidgetMemory], calendar: Calendar) -> CalendarDay? {
        guard !all.isEmpty else { return nil }
        var earliest: [Int: Int] = [:]
        for memory in all {
            let date = memory.day.month * 100 + memory.day.day
            earliest[date] = min(earliest[date] ?? .max, memory.day.year)
        }
        let start = day.date(in: calendar)
        for offset in 1 ... 366 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let candidate = CalendarDay(date, in: calendar)
            if let year = earliest[candidate.month * 100 + candidate.day], year < candidate.year {
                return candidate
            }
            // A leap day comes round on the 28th in a year without one.
            if let year = earliest[229], year < candidate.year,
               CalendarDay(year: year, month: 2, day: 29).comesRound(on: candidate) {
                return candidate
            }
        }
        return nil
    }
}

// MARK: - The faces

struct OnThisDayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var margins
    let entry: OnThisDayEntry

    var body: some View {
        OnThisDayFace(entry: entry, family: family, margins: margins)
    }
}

struct OnThisDayFace: View {
    let entry: OnThisDayEntry
    let family: WidgetFamily
    /// What the system would have kept clear round the content — the widget
    /// draws edge to edge, for the small one's flyer.
    let margins: EdgeInsets

    var body: some View {
        content
            .containerBackground(for: .widget) { background }
            .widgetURL(entry.memory?.link)
    }

    @ViewBuilder private var content: some View {
        if let memory = entry.memory {
            switch family {
            case .accessoryCircular: circular(memory)
            case .accessoryRectangular: rectangular(memory)
            case .accessoryInline: inline(memory)
            case .systemMedium: medium(memory).padding(margins)
            default: small(memory)
            }
        } else {
            switch family {
            case .accessoryCircular: circularEmpty
            case .accessoryRectangular: rectangularEmpty
            case .accessoryInline: inlineEmpty
            default: nothingToday.padding(margins)
            }
        }
    }

    @ViewBuilder private var background: some View {
        switch family {
        case .accessoryCircular: AccessoryWidgetBackground()
        case .accessoryRectangular, .accessoryInline: Color.clear
        case .systemSmall where entry.memory != nil: Color.memoryPaper
        default: WidgetWash()
        }
    }

    private func flyer(of memory: WidgetMemory) -> URL? { entry.flyers[memory.id] }

    /// "2 years ago".
    private func ago(_ memory: WidgetMemory) -> Text {
        Text("^[\(entry.day.year - memory.day.year) year](inflect: true) ago")
    }

    /// "2024", as the event's own day names its year.
    private func year(_ memory: WidgetMemory) -> String {
        memory.day.date().formatted(.gregorian().year())
    }

    /// Today — "Oct 14".
    private var today: String {
        entry.day.date().formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: Small

    /// The flyer, edge to edge, today's date over it and the memory on a
    /// panel along its foot.
    private func small(_ memory: WidgetMemory) -> some View {
        ZStack(alignment: .topLeading) {
            // Laid over a frame of the widget's own size rather than sized
            // by itself: a flyer filling the square is taller than it, and
            // would push the date and the panel off its edges.
            Color.clear
                .overlay {
                    if let file = flyer(of: memory), let image = UIImage(contentsOfFile: file.path(percentEncoded: false)) {
                        Image(uiImage: image)
                            .resizable()
                            .widgetAccentedRenderingMode(.accentedDesaturated)
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "music.mic")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(.primary.opacity(0.25))
                            .padding(.bottom, 40)
                    }
                }
                .clipped()

            Text(verbatim: today)
                .font(.system(size: 10.5, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Self.panel(0.75), in: .capsule)
                .padding(10)

            VStack(alignment: .leading, spacing: 2) {
                DotLabel(text: ago(memory), tint: .trackAttended)
                    .font(.system(size: 11.5, weight: .bold))
                    .lineLimit(1)
                    .widgetAccentable()
                Text(verbatim: memory.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Self.panel(0.82), in: .rect(cornerRadius: 16, style: .continuous))
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    /// What is laid over a flyer — the design's frosted white at its own
    /// opacity, unblurred, and the dark's in dark mode.
    private static func panel(_ opacity: Double) -> Color {
        Color(uiColor: .systemBackground).opacity(opacity)
    }

    // MARK: Medium

    /// The flyer, and beside it how long ago and the year, the event, its
    /// hall and the reader's note.
    private func medium(_ memory: WidgetMemory) -> some View {
        HStack(spacing: 13) {
            FlyerTile(file: flyer(of: memory))
                .frame(width: 92, height: 130)
                .background(Color.memoryPaper)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 7, y: 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("On This Day")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.3)
                        .textCase(.uppercase)
                    Spacer(minLength: 6)
                    if entry.memories.count > 1 {
                        Text("\(entry.index % entry.memories.count + 1) of \(entry.memories.count)")
                            .font(.system(size: 10.5, weight: .semibold))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                DotLabel(text: Text("\(ago(memory)) · \(year(memory))"), tint: .trackAttended)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .widgetAccentable()
                Text(verbatim: memory.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(2)
                Text(verbatim: memory.venue)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !memory.note.isEmpty {
                    Text("“\(memory.note)”")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.primary.opacity(0.8))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Nothing today

    /// Today's date, that nothing happened on it, and when the next memory
    /// comes.
    private var nothingToday: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "On This Day", symbol: "clock", tint: .trackAttended)
            Text(verbatim: today)
                .font(.system(size: 22, weight: .bold))
                .kerning(-0.4)
                .padding(.top, 10)
            Text("No events on this date in earlier years.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(1)
                .padding(.top, 4)
            Spacer(minLength: 4)
            if let next = entry.next {
                Text("Next memory · \(WidgetText.short(next, asOf: entry.date))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.trackAttended)
                    .lineLimit(1)
                    .widgetAccentable()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Lock Screen

    /// How long ago the one memory was — or, on a day with several, how many.
    private func circular(_ memory: WidgetMemory) -> some View {
        VStack(spacing: 1) {
            Image(systemName: "clock")
                .font(.system(size: 13, weight: .semibold))
            if entry.memories.count > 1 {
                Text(entry.memories.count, format: .number)
                    .font(.system(size: 17, weight: .bold))
                Text("MEMORIES")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.4)
                    .opacity(0.8)
            } else {
                Text("\(entry.day.year - memory.day.year)y")
                    .font(.system(size: 17, weight: .bold))
                Text("AGO")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.4)
                    .opacity(0.8)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 8)
        .widgetAccentable()
    }

    private var circularEmpty: some View {
        VStack(spacing: 1) {
            Image(systemName: "clock")
                .font(.system(size: 13, weight: .semibold))
            Text(verbatim: "—")
                .font(.system(size: 17, weight: .bold))
        }
    }

    /// "On this day · 2024", the event and its hall.
    private func rectangular(_ memory: WidgetMemory) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("On this day · \(year(memory))")
                .font(.system(size: 15, weight: .bold))
                .widgetAccentable()
            Text(verbatim: memory.title)
                .font(.system(size: 13.5, weight: .medium))
            Text(verbatim: memory.venue)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rectangularEmpty: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("On This Day")
                .font(.system(size: 15, weight: .bold))
            Text("No memories today")
                .font(.system(size: 13.5, weight: .medium))
            if let next = entry.next {
                Text("Next memory · \(WidgetText.short(next, asOf: entry.date))")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "2 years ago · Liella! 5th LoveLive! Tour".
    private func inline(_ memory: WidgetMemory) -> some View {
        Label {
            Text("\(ago(memory)) · \(Text(verbatim: memory.title))")
        } icon: {
            Image(systemName: "clock")
        }
    }

    private var inlineEmpty: some View {
        Label {
            if let next = entry.next {
                Text("Next memory · \(WidgetText.short(next, asOf: entry.date))")
            } else {
                Text("No memories today")
            }
        } icon: {
            Image(systemName: "clock")
        }
    }
}

#Preview("Small", as: .systemSmall) {
    OnThisDayWidget()
} timeline: {
    OnThisDayEntry(date: .now, day: CalendarDay(.now), memories: WidgetSamples.memories(),
                   index: 0, next: nil, flyers: [:])
    OnThisDayEntry(date: .now, day: CalendarDay(.now), memories: [], index: 0,
                   next: CalendarDay(year: 2026, month: 10, day: 20), flyers: [:])
}

#Preview("Medium", as: .systemMedium) {
    OnThisDayWidget()
} timeline: {
    OnThisDayEntry(date: .now, day: CalendarDay(.now), memories: WidgetSamples.memories(),
                   index: 0, next: nil, flyers: [:])
}
