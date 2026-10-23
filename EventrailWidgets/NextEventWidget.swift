import SwiftUI
import WidgetKit

/// The next event in the library, as the design's Next Event board draws it:
/// how many days are left, and on the day the countdown to its doors, its
/// start and its end — on the home screen (small and medium) and the Lock
/// Screen (circular, rectangular and inline).
///
/// Next is the soonest event the reader keeps that is not over — kept, not
/// only ticketed, as My Events counts down to every one — and it gives way to
/// the one after it once its show has run (``WidgetEvent/leaves``), without
/// the app having to run.
struct NextEventWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.nextEvent, provider: NextEventProvider()) { entry in
            NextEventWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Event")
        .description("Counts down to the next event in your library, and on the day to its doors and start.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

nonisolated struct NextEventEntry: TimelineEntry, Sendable {
    let date: Date
    /// The event next as of ``date``; nil with nothing ahead.
    let event: WidgetEvent?
    /// Its flyer, as the timeline kept it.
    let flyer: URL?
}

nonisolated struct NextEventProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextEventEntry {
        NextEventEntry(date: .now, event: WidgetSamples.event(), flyer: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NextEventEntry) -> Void) {
        let isPreview = context.isPreview
        let placeholder = placeholder(in: context)
        Task {
            let first = await Self.firstEntry(at: .now)
            // The gallery shows what the widget looks like, which an empty
            // library would not.
            completion(isPreview && first?.event == nil ? placeholder : first ?? placeholder)
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NextEventEntry>) -> Void) {
        Task { completion(await Self.timeline(at: .now)) }
    }

    /// An entry wherever what is drawn changes over the next two days: each
    /// midnight, which moves the day count on, and the doors, the start and
    /// the end of each event shown — then the next one, once it is over.
    static func timeline(at now: Date) async -> Timeline<NextEventEntry> {
        let plan = plan(at: now)
        let flyers = await WidgetFlyers.files(for: plan.compactMap(\.event).map { ($0.id, $0.flyer) })
        let entries = plan.map { time, event in
            NextEventEntry(date: time, event: event, flyer: event.flatMap { flyers[$0.id] })
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// The timeline's first entry alone, with its own flyer and no other
    /// fetched — what a snapshot draws, which waited on the flyer of every
    /// event of the next two days.
    static func firstEntry(at now: Date) async -> NextEventEntry? {
        guard let (time, event) = plan(at: now).first else { return nil }
        let flyers = await WidgetFlyers.files(for: event.map { [($0.id, $0.flyer)] } ?? [])
        return NextEventEntry(date: time, event: event, flyer: event.flatMap { flyers[$0.id] })
    }

    /// The moments of ``timeline(at:)``, and the event shown at each.
    private static func plan(at now: Date) -> [(time: Date, event: WidgetEvent?)] {
        let events = (WidgetLibrary.read() ?? .empty).upcoming
        let horizon = now.addingTimeInterval(2 * 24 * 60 * 60)
        var moments: Set<Date> = [now]
        moments.formUnion(Calendar.gregorian().midnights(after: now, count: 3))
        for event in events {
            moments.formUnion([event.doors, event.starts, event.runsTo, event.leaves].compactMap(\.self))
        }
        let times = moments.filter { $0 >= now && $0 <= horizon }.sorted().prefix(60)
        return times.map { time in (time, events.first { $0.leaves > time }) }
    }
}

// MARK: - Where the event stands

/// One event read at one moment: how many days are left and, on the day,
/// what the widget counts down to.
struct NextMoment {
    let event: WidgetEvent
    let now: Date

    /// Whole days from today to the day the hall says it falls on — 0 on the
    /// day, and below once a show that runs past midnight is still on.
    var days: Int { event.day.daysAway(from: now) }

    var isToday: Bool { days <= 0 }

    /// Where the show stands, on its day and where it published a start.
    var stage: EventActivityStage? {
        guard isToday, let starts = event.starts, let runsTo = event.runsTo else { return nil }
        let doors = event.doors.flatMap { $0 < starts ? $0 : nil }
        return .at(now, doors: doors, starts: starts, runsTo: runsTo)
    }

    /// What is counted down to on the day, and in which words and colour —
    /// the doors, then the start, then the end, as the event's sheet counts.
    var countdown: Countdown? {
        guard let stage, let starts = event.starts, let runsTo = event.runsTo else { return nil }
        switch stage {
        case .beforeDoors:
            return Countdown(header: "Today", label: "Doors in", target: event.doors ?? starts,
                             ink: .ticketInk, dot: .trackTicket) { Text("Doors in \($0)") }
        case .beforeShow:
            return Countdown(header: "Today", label: "Show in", target: starts,
                             ink: .ticketInk, dot: .trackTicket) { Text("Show in \($0)") }
        case .doorsOpen, .startingSoon:
            return Countdown(header: "Doors open", label: "Show in", target: starts,
                             ink: .trackAttended, dot: .trackAttended) { Text("Show in \($0)") }
        case .onNow, .wrapped:
            return Countdown(header: "On now", label: "Ends in", target: runsTo,
                             ink: .stageLive, dot: .stageLive) { Text("Ends in \($0)") }
        }
    }

    struct Countdown {
        let header: LocalizedStringKey
        let label: LocalizedStringKey
        let target: Date
        let ink: Color
        let dot: Color
        /// The label and the timer as one line — "Doors in 2:15:40".
        let line: (Text) -> Text

        /// The time left, counted by the system and held at zero once it
        /// runs out, as the Live Activity counts.
        func timer(from now: Date) -> Text {
            Text(timerInterval: min(now, target)...target, countsDown: true)
        }
    }

    /// "17:00 / 18:00" — the doors and the start, as far as they are known.
    var timesLine: String {
        [event.doors, event.starts].compactMap(\.self)
            .map { WidgetText.time($0, in: event.timeZone) }
            .joined(separator: " / ")
    }

    /// The first time the reader has to be anywhere: the doors, or the start.
    var firstTime: String? {
        (event.doors ?? event.starts).map { WidgetText.time($0, in: event.timeZone) }
    }

    /// "In 4 days", "Tomorrow", "Today".
    var relativeDay: String { WidgetText.relative(days: max(days, 0)) }

    var dayLine: String { WidgetText.day(event.shownDay, in: event.timeZone) }
}

// MARK: - The faces

struct NextEventWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextEventEntry

    var body: some View {
        NextEventFace(entry: entry, family: family)
    }
}

/// The widget for one family, handed it rather than reading it from the
/// environment, so a preview can draw every family at once.
struct NextEventFace: View {
    let entry: NextEventEntry
    let family: WidgetFamily

    var body: some View {
        content
            .containerBackground(for: .widget) { background }
            .widgetURL(entry.event?.link)
    }

    @ViewBuilder private var content: some View {
        if let event = entry.event {
            let moment = NextMoment(event: event, now: entry.date)
            switch family {
            case .accessoryCircular: circular(moment)
            case .accessoryRectangular: rectangular(moment)
            case .accessoryInline: inline(moment)
            case .systemMedium: medium(moment)
            default: small(moment)
            }
        } else {
            empty
        }
    }

    @ViewBuilder private var background: some View {
        switch family {
        case .accessoryCircular: AccessoryWidgetBackground()
        case .accessoryRectangular, .accessoryInline: Color.clear
        default:
            WidgetWash(warm: entry.event.map { NextMoment(event: $0, now: entry.date).isToday } ?? false)
        }
    }

    // MARK: Small

    @ViewBuilder private func small(_ moment: NextMoment) -> some View {
        if let countdown = moment.countdown {
            smallOnTheDay(moment, countdown)
        } else {
            smallCountdown(moment)
        }
    }

    /// The flyer and the day, the days left large, and the title.
    private func smallCountdown(_ moment: NextMoment) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                FlyerTile(file: entry.flyer)
                    .frame(width: 20, height: 28)
                    .clipShape(.rect(cornerRadius: 5, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 2.5, y: 2)
                Text(verbatim: moment.dayLine)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Group {
                if moment.isToday {
                    Text("Today")
                        .font(.system(size: 34, weight: .bold))
                        .kerning(-0.9)
                        .foregroundStyle(Color.ticketInk)
                        .widgetAccentable()
                } else {
                    BigCount(count: moment.days, unit: WidgetText.daysUnit(moment.days))
                }
            }
            .padding(.top, 8)
            Spacer(minLength: 4)
            Text(verbatim: moment.event.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// On the day: where the event stands, the countdown to its next
    /// moment, and the seat and the times.
    private func smallOnTheDay(_ moment: NextMoment, _ countdown: NextMoment.Countdown) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DotLabel(text: Text(countdown.header), tint: countdown.dot, dot: 8)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(countdown.ink)
            Text(countdown.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(countdown.ink)
                .padding(.top, 8)
            countdown.timer(from: entry.date)
                .font(.system(size: 32, weight: .bold))
                .kerning(-0.8)
                .monospacedDigit()
                .foregroundStyle(countdown.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            Spacer(minLength: 4)
            VStack(alignment: .leading, spacing: 5) {
                // The seat where one is written, which is the point of the
                // day; otherwise which event it is.
                if moment.event.seat.isEmpty {
                    Text(verbatim: moment.event.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(2)
                } else {
                    SeatCapsule(seat: moment.event.seat)
                }
                stopsLine(moment)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// "Doors 17:00 · Start 18:00".
    private func stopsLine(_ moment: NextMoment) -> Text {
        let zone = moment.event.timeZone
        let doors = moment.event.doors.map { Text("Doors \(WidgetText.time($0, in: zone))") }
        let start = moment.event.starts.map { Text("Start \(WidgetText.time($0, in: zone))") }
        switch (doors, start) {
        case let (doors?, start?): return Text("\(doors) · \(start)")
        case let (doors?, nil): return doors
        case let (nil, start?): return start
        case (nil, nil): return Text(verbatim: "")
        }
    }

    // MARK: Medium

    /// The flyer, and beside it how far off the event is, what and where it
    /// is, the seat and the times.
    private func medium(_ moment: NextMoment) -> some View {
        HStack(spacing: 13) {
            FlyerTile(file: entry.flyer)
                .frame(width: 82, height: 115)
                .clipShape(.rect(cornerRadius: 11, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 7, y: 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    mediumHeadline(moment)
                        .font(.system(size: 20, weight: .bold))
                        .kerning(-0.4)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .widgetAccentable()
                    DotLabel(text: moment.event.hasTicket ? Text("Ticketed") : Text("Planning"),
                             tint: moment.event.hasTicket ? .trackTicket : .trackInterest)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
                Text(verbatim: moment.event.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(2)
                Text(verbatim: [moment.dayLine, moment.event.venue].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if !moment.event.seat.isEmpty { SeatCapsule(seat: moment.event.seat) }
                    Spacer(minLength: 0)
                    Text(verbatim: moment.timesLine)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// "In 4 days" in the app's blue — and on the day the countdown, in the
    /// colour of where the event stands.
    private func mediumHeadline(_ moment: NextMoment) -> some View {
        Group {
            if let countdown = moment.countdown {
                countdown.line(countdown.timer(from: entry.date))
                    .foregroundStyle(countdown.ink)
            } else {
                Text(verbatim: moment.relativeDay)
                    .foregroundStyle(moment.isToday ? Color.ticketInk : Color.brandTint)
            }
        }
    }

    // MARK: Lock Screen

    /// The days left in a ring that fills over the last week — and on the
    /// day, the time it is counting to.
    private func circular(_ moment: NextMoment) -> some View {
        let fill = moment.isToday ? 1 : max(0, min(1, Double(7 - moment.days) / 7))
        return ZStack {
            LockRing(fill: fill)
            VStack(spacing: 0) {
                Image(systemName: "ticket")
                    .font(.system(size: 12, weight: .semibold))
                Group {
                    if !moment.isToday {
                        Text("\(moment.days)d")
                    } else if let stage = moment.stage {
                        switch stage {
                        case .beforeDoors:
                            Text(verbatim: WidgetText.clock(moment.event.doors ?? moment.event.starts!, in: moment.event.timeZone))
                        case .beforeShow, .doorsOpen, .startingSoon:
                            Text(verbatim: WidgetText.clock(moment.event.starts!, in: moment.event.timeZone))
                        case .onNow, .wrapped:
                            Text("LIVE")
                        }
                    } else {
                        Text("Today")
                    }
                }
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 10)
        }
        .widgetAccentable()
    }

    /// "In 4 days · 17:00", the title and the hall.
    private func rectangular(_ moment: NextMoment) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: [moment.relativeDay, moment.firstTime].compactMap(\.self).joined(separator: " · "))
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .widgetAccentable()
            Text(verbatim: moment.event.title)
                .font(.system(size: 13.5, weight: .medium))
            Text(verbatim: moment.event.venue)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Sun 18 · 水瀬いのり Autumn Live".
    private func inline(_ moment: NextMoment) -> some View {
        Label {
            Text(verbatim: "\(WidgetText.weekdayAndDay(moment.event.shownDay, in: moment.event.timeZone)) · \(moment.event.title)")
        } icon: {
            Image(systemName: "ticket")
        }
    }

    // MARK: Nothing ahead

    @ViewBuilder private var empty: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                LockRing(fill: 0)
                Image(systemName: "ticket").font(.system(size: 16, weight: .semibold))
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Next Event").font(.system(size: 15, weight: .bold))
                Text("No events ahead").font(.system(size: 13.5, weight: .medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Label("No events ahead", systemImage: "ticket")
        default:
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(title: "Next Event", symbol: "ticket")
                Spacer(minLength: 0)
                Text("No events ahead")
                    .font(.system(size: 14, weight: .bold))
                Text("Events you add to My Events count down here.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// The open ring of a round Lock Screen widget, as the design draws it: a
/// faint track two thirds of the way round, open at the foot, and the part
/// filled over it from the left.
struct LockRing: View {
    let fill: Double

    /// The track's share of the circle, and the angle it starts at, measured
    /// clockwise from three o'clock: the design's arc of about 251°, open
    /// across the bottom.
    private static let sweep = 0.698
    private static let start = Angle.degrees(144.4)

    var body: some View {
        ZStack {
            arc(to: Self.sweep).stroke(.primary.opacity(0.25), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            if fill > 0 {
                arc(to: Self.sweep * fill).stroke(.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
        }
        .padding(5.5)
    }

    private func arc(to end: Double) -> some Shape {
        Circle().trim(from: 0, to: end).rotation(Self.start)
    }
}

#Preview("Small", as: .systemSmall) {
    NextEventWidget()
} timeline: {
    NextEventEntry(date: .now, event: WidgetSamples.event(), flyer: nil)
    NextEventEntry(date: .now, event: WidgetSamples.event(today: true), flyer: nil)
}

#Preview("Medium", as: .systemMedium) {
    NextEventWidget()
} timeline: {
    NextEventEntry(date: .now, event: WidgetSamples.event(), flyer: nil)
    NextEventEntry(date: .now, event: WidgetSamples.event(today: true), flyer: nil)
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    NextEventWidget()
} timeline: {
    NextEventEntry(date: .now, event: WidgetSamples.event(), flyer: nil)
}
