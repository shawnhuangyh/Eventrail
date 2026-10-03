import ActivityKit
import SwiftUI
import WidgetKit

/// The event's Live Activity: on the Lock Screen and in the Dynamic Island,
/// as `Eventrail v3.dc.html` draws them.
///
/// An activity is an archived picture, drawn again only when the app sends it
/// something or its stale date passes, and the app is rarely running during a
/// concert. So nothing here waits to be told the stage has changed: every
/// stage still to come is drawn at once, and each is shown only inside its own
/// stretch of the event (``Stretch``), switched by the system as the event runs
/// on. Everything that moves within a stage is a view the system runs by
/// itself too: the countdowns are timers, held at zero once they run out, and
/// the fill is a timer progress bar.
///
/// Only what changes with the stage is drawn more than once — the words, the
/// seat's colour, the two times and the fill. The flyer, the title and the
/// hall are drawn once. The watch's card is drawn for one stage only — see
/// ``SmartStackView``.
///
/// **Both the Lock Screen card and the expanded island stop at 160 points
/// tall**, and the design's run to nearer 185. The system fits what is taller
/// by eating the margins — the card's content ended up against its edges and
/// the island's cut off in its corners — so each is laid out to come in under
/// it: on the Lock Screen the times carry their labels beside them rather than
/// under them, and the island's gaps are a little tighter than the design's.
///
/// The island is laid out the way its regions are: only the top row — the two
/// times — is split either side of the camera, in the leading and trailing
/// regions; the event, and the stage beside the seat, sit below it in the
/// bottom one. Anything more spread around the camera went wrong: the
/// centre region stays centred at its own width whatever is beside it, and the
/// top corners are rounded far enough to cut into what sits in them.
///
/// A paired Apple Watch draws a card of its own in the Smart Stack, as
/// `Eventrail Watch.dc.html` draws it (``SmartStackView``) — the small
/// family, which CarPlay draws too. The mark at the top of the watch face,
/// and the alerts, are the compact island's.
struct EventLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EventActivityAttributes.self) { context in
            Group {
                #if DEBUG
                if context.attributes.eventID.hasPrefix(GateDiagnostics.prefix) {
                    GateDiagnostics(since: context.attributes.opens)
                        .activityBackgroundTint(EventMoment.platter)
                } else {
                    ActivityCard(moment: EventMoment(context))
                }
                #else
                ActivityCard(moment: EventMoment(context))
                #endif
            }
                .activitySystemActionForegroundColor(.white)
                .widgetURL(context.attributes.link)
        } dynamicIsland: { context in
            let moment = EventMoment(context)
            return DynamicIsland {
                // The top row splits around the camera: the time counted from
                // on one side, the time counted to on the other.
                DynamicIslandExpandedRegion(.leading) {
                    moment.eachStage(alignment: .leading) { moment in
                        moment.stopColumn(moment.stops.from, alignment: .leading)
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    moment.eachStage(alignment: .trailing) { moment in
                        moment.stopColumn(moment.stops.to, alignment: .trailing)
                    }
                    .padding(.trailing, 6)
                }
                // Everything else below it: the event, and where the event
                // stands beside the seat. The design sets a rule between the
                // two; the island has no height to spare for one.
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        HStack(spacing: 10) {
                            moment.poster(width: 22, height: 31, radius: 5)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: moment.attributes.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.92))
                                Text(verbatim: moment.attributes.venue)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        moment.eachStage { moment in
                            HStack(spacing: 12) {
                                moment.headline
                                    .font(.system(size: 17, weight: .bold))
                                    .kerning(-0.17)
                                    .monospacedDigit()
                                    .foregroundStyle(moment.tint)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                moment.seatCapsule(height: 24)
                            }
                        }
                    }
                    // In from the sides as far as the top row, and clear of the
                    // island's lower corners, which are rounded far enough to
                    // cut into a line along its bottom edge.
                    .padding(.horizontal, 6)
                    // Room of its own under the stage and the seat. The region
                    // is cut off at its own frame, whatever margin the island
                    // leaves below it — on a device the seat capsule's rounded
                    // bottom was cut flat with space to spare beneath — so the
                    // cut has to fall on this rather than on the capsule.
                    .padding(.bottom, 6)
                }
            } compactLeading: {
                moment.poster(width: 20, height: 26, radius: 6)
            } compactTrailing: {
                // A timer takes all the width it is offered, and the island
                // is as wide on the poster's side as on this one, so each is
                // laid over a copy of its longest reading, hidden — and
                // counts down only through the last hour, since the width is
                // fixed as the island is drawn and a "1:59:59" left it that
                // wide long after the hours had gone.
                let template = moment.longestGlanceCountdown
                moment.eachStage(alignment: .trailing) { moment in
                    moment.glanceStatus(sizedFor: template)
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(moment.tint)
                        .lineLimit(1)
                }
            } minimal: {
                // Only the largest unit left — "1h", "40m", "40s": the
                // smallest view has room for three characters, not a clock.
                moment.eachStage { moment in
                    moment.minimalStatus
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(moment.tint)
                }
            }
            // The margins are left as the system has them. Taken in to 10 at
            // the top, the two times rose into the top corners and were cut
            // off there, and the bottom region started no higher for it; set
            // to 14 at the bottom, the seat capsule was still cut along the
            // region's lower edge.
            //
            // The outline takes one colour, not one per stretch: the stage's
            // as the app last saw it.
            .keylineTint(moment.tint)
            .widgetURL(moment.attributes.link)
        }
        .supplementalActivityFamilies([.small])
    }
}

/// The card outside the island, each on its own background: the Lock
/// Screen's, or the Smart Stack's where the system asks for the small family.
struct ActivityCard: View {
    let moment: EventMoment
    @Environment(\.activityFamily) private var family

    var body: some View {
        switch family {
        case .small:
            SmartStackView(moment: moment)
                .activityBackgroundTint(SmartStackView.base)
        default:
            LockScreenView(moment: moment)
                .activityBackgroundTint(EventMoment.platter)
        }
    }
}

/// The Lock Screen card: where the event stands and what comes next, the seat,
/// the event itself, and the two times the fill runs between.
struct LockScreenView: View {
    let moment: EventMoment

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            moment.eachStage(alignment: .topLeading) { moment in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        moment.headline
                            .font(.system(size: 20, weight: .bold))
                            .kerning(-0.4)
                            .foregroundStyle(moment.tint)
                        if let detail = moment.detail {
                            detail
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .lineLimit(1)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    moment.seatCapsule()
                }
            }

            HStack(spacing: 9) {
                moment.poster(width: 26, height: 36, radius: 5)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: moment.attributes.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(verbatim: moment.attributes.venue)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .lineLimit(1)
            }

            moment.eachStage { moment in
                moment.trackRow(timeSize: 18, labelSize: 11)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .environment(\.colorScheme, .dark)
    }
}

/// The card in a paired Apple Watch's Smart Stack, as `Eventrail Watch.dc.html`
/// draws it: three lines — where the event stands, the seat, and the two times
/// the fill runs between. The title is left to the phone, and the flyer beside
/// the first line says which event it is. Where no seat was written down, the
/// hall stands in its place.
///
/// The card is the event's colour washed over a dark grey, and it is drawn
/// for the stage the event is at and no other — not every stage behind a
/// ``Gate``, as the phone's are. The watch does not honour the gates: it drew
/// every stage at once, text over text. On one stage the countdown and the
/// fill still run by themselves, and the card moves on to the next stage when
/// it is next drawn — as the stage changes and the activity goes stale, or
/// when the app brings it up to date.
///
/// It is drawn at whatever size the watch gives it, the three lines spread
/// down it. The design's card is a 46 mm watch's; on a smaller one the gaps
/// close up rather than the card being cut off.
struct SmartStackView: View {
    let moment: EventMoment

    /// The card under the wash.
    static let base = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1F / 255)

    private static let margins = EdgeInsets(top: 10, leading: 11, bottom: 11, trailing: 11)
    private static let poster = CGSize(width: 15, height: 21)

    var body: some View {
        card
            .overlay(alignment: .topTrailing) {
                moment.poster(width: Self.poster.width, height: Self.poster.height, radius: 3)
                    .padding(.top, Self.margins.top)
                    .padding(.trailing, Self.margins.trailing)
            }
            .environment(\.colorScheme, .dark)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            moment.headline
                .font(.system(size: 16.5, weight: .bold))
                .kerning(-0.165)
                .monospacedDigit()
                .foregroundStyle(moment.tint)
                .lineLimit(1)
                // "まもなく開演・あと3:30" is half as long again as the
                // English, and the card has no second line to give it.
                .minimumScaleFactor(0.7)
                // Clear of the flyer, and as tall as it: the row they share.
                .padding(.trailing, Self.poster.width + 6)
                .frame(maxWidth: .infinity, minHeight: Self.poster.height, alignment: .topLeading)
            Spacer(minLength: 4)
            if moment.state.seat.isEmpty {
                Text(verbatim: moment.attributes.venue)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            } else {
                moment.seatCapsule(height: 21, value: 12.5, label: 7.5, padding: 8, spacing: 4.5)
            }
            Spacer(minLength: 4)
            // "16:18 Doors" and "Start 16:33" leave the fill a couple of
            // points short of its least on a 42 mm watch, and a twelve-hour
            // clock leaves it nothing: a size down first, then the labels go
            // before the fill does.
            ViewThatFits(in: .horizontal) {
                moment.trackRow(timeSize: 13, labelSize: 9, spacing: 5)
                moment.trackRow(timeSize: 12, labelSize: 8.5, spacing: 4)
                moment.trackRow(timeSize: 13, labelSize: 9, spacing: 5, labelled: false)
            }
        }
        .padding(Self.margins)
        .background {
            LinearGradient(colors: [moment.tint.opacity(0.3), moment.tint.opacity(0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// One activity's worth of what to draw, worked out once from its context —
/// and, through ``eachStage(alignment:_:)``, once for each stage still to come.
struct EventMoment {
    let attributes: EventActivityAttributes
    let state: EventActivityAttributes.ContentState
    /// The rest of the event as it stands as this is drawn — see
    /// ``EventActivityAttributes/ContentState/phases(at:)``.
    let phases: [EventActivityPhase]
    /// The stage this copy draws: the first of ``phases``, or the one it was
    /// made for.
    let stage: EventActivityStage

    init(_ context: ActivityViewContext<EventActivityAttributes>) {
        self.init(attributes: context.attributes, state: context.state, at: .now)
    }

    init(attributes: EventActivityAttributes, state: EventActivityAttributes.ContentState, at now: Date) {
        self.attributes = attributes
        self.state = state
        phases = state.phases(at: now)
        stage = phases[0].stage
    }

    private init(_ moment: EventMoment, stage: EventActivityStage) {
        attributes = moment.attributes
        state = moment.state
        phases = moment.phases
        self.stage = stage
    }

    /// `content` drawn once for each stage still to come, each shown only in
    /// its own stretch of the event.
    func eachStage<Content: View>(alignment: Alignment = .center,
                                  @ViewBuilder _ content: @escaping (EventMoment) -> Content) -> some View {
        ZStack(alignment: alignment) {
            ForEach(phases, id: \.stage) { phase in
                content(EventMoment(self, stage: phase.stage))
                    .modifier(Stretch(phase: phase))
            }
        }
    }

    /// The card behind the Lock Screen presentation: the design's smoked
    /// glass, dark on any wallpaper so the tints read the same on every one.
    static let platter = Color(red: 22 / 255, green: 20 / 255, blue: 30 / 255).opacity(0.58)

    /// The stage's colour — see ``EventActivityStage/tint``.
    var tint: Color { stage.tint }

    var headline: Text {
        switch stage {
        case .beforeDoors: Text("Doors in \(countdown(to: state.doors ?? state.starts))")
        case .beforeShow: Text("Starts in \(countdown(to: state.starts))")
        case .doorsOpen: Text("Doors open")
        case .startingSoon: Text("Starting in \(countdown(to: state.starts))")
        case .onNow: Text("On now")
        case .wrapped: Text("That's a wrap")
        }
    }

    /// The line under the headline: what comes next, and when.
    var detail: Text? {
        switch stage {
        case .beforeDoors, .beforeShow:
            return Text("Show starts at \(time(state.starts))")
        case .doorsOpen:
            return Text("Show in \(countdown(to: state.starts))")
        case .startingSoon:
            return Text("Find your seat")
        case .onNow:
            guard let ends = state.ends else { return Text("Started at \(time(state.starts))") }
            return Text("\(countdown(to: state.runsTo)) left · ends \(time(ends))")
        case .wrapped:
            return state.ends.map { Text("Ended at \(time($0))") }
        }
    }

    /// The one thing the island has room for: the next number that matters
    /// — time to the doors, time to the show — then LIVE.
    var shortStatus: Text {
        switch stage {
        case .beforeDoors: countdown(to: state.doors ?? state.starts)
        case .beforeShow, .doorsOpen, .startingSoon: countdown(to: state.starts)
        case .onNow: Text("LIVE")
        case .wrapped: Text("Done")
        }
    }

    /// The longest a countdown runs in the island before the time it counts
    /// to gives way to it — just under an hour, so it reads "59:59" as it
    /// comes on rather than "1:00:00".
    static let glanceCountdown: TimeInterval = 3599

    /// What ``shortStatus`` counts down to at `stage`, if it counts.
    private func countdownTarget(at stage: EventActivityStage) -> Date? {
        switch stage {
        case .beforeDoors: state.doors ?? state.starts
        case .beforeShow, .doorsOpen, .startingSoon: state.starts
        case .onNow, .wrapped: nil
        }
    }

    /// ``shortStatus`` as the compact island draws it: while what it counts
    /// to is more than an hour off, the time of it — "18:00", the AM or PM
    /// left off — and only then the countdown, switched by a ``Gate`` with
    /// nothing sent. The island's width is fixed as it is drawn, and the two
    /// are the same width, so it never has to be as wide as a count with
    /// hours in it. Laid over `template`, since a timer takes all the width
    /// it is offered.
    ///
    /// The countdown's own interval is only the last hour, not from now: a
    /// timer is set for the longest reading its interval holds, and one
    /// running from more than an hour off was set for "1:00:59", shrunk to
    /// fit beside the poster, and stayed small after it had come down to
    /// "59:58".
    @ViewBuilder
    func glanceStatus(sizedFor template: String) -> some View {
        if let target = countdownTarget(at: stage) {
            let switchover = target.addingTimeInterval(-Self.glanceCountdown)
            let later = switchover > .now
            let countdown = Text(timerInterval: max(switchover, .now)...max(target, .now), countsDown: true)
            ZStack(alignment: .trailing) {
                if later {
                    Text(verbatim: glanceTime(target))
                        .mask { Gate(at: switchover, opening: false) }
                }
                Text(verbatim: template)
                    .hidden()
                    .overlay(alignment: .trailing) { countdown }
                    .mask { Gate(at: later ? switchover : nil, opening: true) }
            }
        } else {
            shortStatus
        }
    }

    /// ``shortStatus`` as the minimal island draws it: only the largest unit
    /// left, rounded down — "1h" with an hour and twenty minutes to go, "40m"
    /// with forty minutes and forty seconds, "40s" in the last minute. The
    /// smallest view, the one the island falls back to beside another app's
    /// activity, has room for three characters rather than a clock.
    ///
    /// Nothing the system runs by itself counts like that: the formats that
    /// stop at the largest unit spell it out in words ("40 minutes"). So each
    /// way of reading it is drawn once and shown only over its own stretch of
    /// the time left, switched by a ``Gate`` — the hours as words of their
    /// own, the minutes and the seconds as the system's timer with all but
    /// those digits masked off (``digits(of:over:keeping:at:unit:)``), so
    /// "40:40" reads "40m" and still counts by itself. That is four readings
    /// a stage and a word for each hour, rather than one for every minute.
    @ViewBuilder
    var minimalStatus: some View {
        if let target = countdownTarget(at: stage), target > .now {
            ZStack {
                ForEach(minimalReadings(to: target)) { reading in
                    minimalReading(reading.shape, to: target)
                        .mask { Gate(at: reading.from, opening: true) }
                        .mask { Gate(at: reading.until, opening: false) }
                }
            }
        } else {
            shortStatus
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    /// One way the minimal island reads the time left, and when it does.
    struct MinimalReading: Identifiable {
        enum Shape: Hashable {
            /// The time it counts to, where that is too far off for hours.
            case time
            case hours(Int)
            case minutes(digits: Int)
            case seconds(digits: Int)
        }

        let shape: Shape
        /// When it comes on — nil where it is on as the stage is.
        let from: Date?
        /// When it gives way — nil where it lasts as long as the stage.
        let until: Date?

        var id: Shape { shape }
    }

    /// Past this many hours left the minimal island shows the time of the
    /// moment instead — which only an activity drawn long before its window
    /// ever sees, and which keeps the hours to a handful of readings.
    static let minimalHours = 12

    /// Each reading of the time left to `target` that falls inside this
    /// stage's stretch of the event, with the moments it comes on and gives
    /// way — nil at either end the stage's own ``Stretch`` already covers.
    func minimalReadings(to target: Date) -> [MinimalReading] {
        let phase = phases.first { $0.stage == stage }
        // How much is left as the stage comes on, and as it gives way.
        let most = target.timeIntervalSince(max(phase?.from ?? .now, .now))
        let least = target.timeIntervalSince(phase?.until ?? target)
        let hour: TimeInterval = 3600
        var readings: [(MinimalReading.Shape, Range<TimeInterval>)] = [
            (.seconds(digits: 1), 0..<10),
            (.seconds(digits: 2), 10..<60),
            (.minutes(digits: 1), 60..<600),
            (.minutes(digits: 2), 600..<hour),
        ]
        let hours = min(Int(most / hour), Self.minimalHours - 1)
        if hours >= 1 {
            for count in 1...hours {
                readings.append((.hours(count), Double(count) * hour..<Double(count + 1) * hour))
            }
        }
        readings.append((.time, Double(Self.minimalHours) * hour..<TimeInterval.infinity))
        return readings.compactMap { shape, left in
            guard left.lowerBound < most, left.upperBound > least else { return nil }
            return MinimalReading(
                shape: shape,
                from: left.upperBound < most ? target.addingTimeInterval(-left.upperBound) : nil,
                until: left.lowerBound > least ? target.addingTimeInterval(-left.lowerBound) : nil)
        }
    }

    @ViewBuilder
    private func minimalReading(_ shape: MinimalReading.Shape, to target: Date) -> some View {
        switch shape {
        case .time:
            Text(verbatim: glanceTime(target))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        case .hours(let count):
            Text("\(count)h", comment: "Whole hours left, in the Dynamic Island's smallest view: 1h. Only the largest unit is shown, so an hour and twenty minutes reads 1h.")
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        case .minutes(let digits):
            self.digits(of: target, over: digits == 2 ? 3599 : 599, keeping: digits, at: .leading,
                        unit: Text("m", comment: "Minutes, after the count of them in the Dynamic Island's smallest view: 40m."))
        case .seconds(let digits):
            self.digits(of: target, over: digits == 2 ? 59 : 9, keeping: digits, at: .trailing,
                        unit: Text("s", comment: "Seconds, after the count of them in the Dynamic Island's smallest view: 40s."))
        }
    }

    /// The system's countdown to `target` over the last `window` before it,
    /// masked down to the `digits` at its head (the minutes) or at its tail
    /// (the seconds), with `unit` after them.
    ///
    /// The timer is laid over a hidden template of its longest reading —
    /// "00:00", or "0:00" under ten minutes — set against its trailing edge,
    /// as the compact island sets it; a slot as wide as the digits kept is
    /// set against the same edge of the template, and everything outside the
    /// slot is clipped away. Digits are one width, so the slot always falls
    /// on the same digits. Each window starts at the longest reading the
    /// slot can hold — "59:59", "9:59", "0:59", "0:09" — since a timer is
    /// set for the longest reading its interval holds, and one set for more
    /// would be shrunk.
    private func digits(of target: Date, over window: TimeInterval, keeping digits: Int,
                        at edge: HorizontalEdge, unit: Text) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: String(repeating: "0", count: digits))
                .hidden()
                .overlay(alignment: edge == .leading ? .leading : .trailing) {
                    Text(verbatim: window >= 600 ? "00:00" : "0:00")
                        .hidden()
                        .overlay(alignment: .trailing) {
                            Text(timerInterval: target.addingTimeInterval(-window)...target, countsDown: true)
                                .multilineTextAlignment(.trailing)
                        }
                        .fixedSize()
                }
                .clipped()
            unit
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// The longest reading the island's countdown will show over the rest of
    /// the event, as a template of the timer's shape — "0:00" or "00:00",
    /// never more, since it counts only through the last hour — for sizing
    /// it: each stage's countdown is longest as its stretch begins.
    var longestGlanceCountdown: String {
        let now = Date.now
        let longest = phases.map { phase -> TimeInterval in
            guard let target = countdownTarget(at: phase.stage) else { return 0 }
            return min(Self.glanceCountdown, target.timeIntervalSince(max(now, phase.from ?? now)))
        }.max() ?? 0
        return longest >= 600 ? "00:00" : "0:00"
    }

    /// A time as the island prints it, without the AM or PM a twelve-hour
    /// clock carries: there is no room for one beside it.
    private func glanceTime(_ instant: Date) -> String {
        var style = Date.FormatStyle().hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)
        style.timeZone = state.timeZone
        return instant.formatted(style)
    }

    /// The seat, where the reader wrote one down: a capsule in the event's
    /// colour, as the designs set it on the Lock Screen, in the island and on
    /// the watch — 28 points tall on the Lock Screen, a little less in the
    /// island, which has none to spare, and smaller all through on the watch.
    @ViewBuilder
    func seatCapsule(height: CGFloat = 28, value: CGFloat = 14, label: CGFloat = 9.5,
                     padding: CGFloat = 11, spacing: CGFloat = 6) -> some View {
        if !state.seat.isEmpty {
            HStack(spacing: spacing) {
                Text("Seat")
                    .font(.system(size: label, weight: .bold))
                    .kerning(label * 0.08)
                    .textCase(.uppercase)
                    .opacity(0.7)
                Text(verbatim: state.seat)
                    .font(.system(size: value, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
            }
            .lineLimit(1)
            .foregroundStyle(.black)
            .padding(.horizontal, padding)
            .frame(height: height)
            .background(tint, in: .capsule)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A time the event runs between, and which one it is.
    struct Stop {
        let instant: Date?
        let label: LocalizedStringKey
    }

    /// Whether the event is still counting from the doors to the start, rather
    /// than from the start to the end.
    private var countsToStart: Bool {
        [.beforeDoors, .doorsOpen, .startingSoon].contains(stage) && state.doors != nil
    }

    /// The two times the fill runs between: the doors and the start until the
    /// show, the start and the end from then on.
    var stops: (from: Stop, to: Stop) {
        countsToStart
            ? (Stop(instant: state.doors, label: "Doors"), Stop(instant: state.starts, label: "Start"))
            : (Stop(instant: state.starts, label: "Start"), Stop(instant: state.ends, label: "End"))
    }

    /// One of the two times beside the island's camera: its label small above
    /// it, in capitals.
    func stopColumn(_ stop: Stop, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(stop.label)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.4)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.55))
            time(stop.instant, size: 20)
                .kerning(-0.4)
        }
        .lineLimit(1)
    }

    /// The two times with the fill between them — each with its label on the
    /// side away from the fill, on one line. Unlabelled, it is the two times
    /// alone, for where the labels leave the fill no room.
    func trackRow(timeSize: CGFloat, labelSize: CGFloat, spacing: CGFloat = 10,
                  labelled: Bool = true) -> some View {
        let stops = stops
        return HStack(spacing: spacing) {
            HStack(alignment: .firstTextBaseline, spacing: spacing / 2) {
                time(stops.from.instant, size: timeSize)
                if labelled { label(stops.from.label, size: labelSize) }
            }
            .fixedSize()
            fill
            HStack(alignment: .firstTextBaseline, spacing: spacing / 2) {
                if labelled { label(stops.to.label, size: labelSize) }
                time(stops.to.instant, size: timeSize)
            }
            .fixedSize()
        }
    }

    private func time(_ instant: Date?, size: CGFloat) -> some View {
        clock(instant, size: size)
            .font(.system(size: size, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
    }

    private func label(_ label: LocalizedStringKey, size: CGFloat) -> some View {
        Text(label)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            .lineLimit(1)
    }

    /// The line between the two times, filled by the system as the event
    /// runs on — nothing here has to be sent anything for it to move.
    ///
    /// No knob on the end of the fill, as the design has: the fill is the
    /// system's own timer bar, and nothing the activity can draw would keep a
    /// knob on the end of it between updates.
    private var fill: some View {
        Group {
            if stage == .wrapped {
                ProgressView(value: 1)
            } else if countsToStart, let doors = state.doors, doors < state.starts {
                ProgressView(timerInterval: doors...state.starts, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            } else {
                ProgressView(timerInterval: state.starts...max(state.runsTo, state.starts), countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            }
        }
        .progressViewStyle(.linear)
        .tint(tint)
        // Measured at the shortest the watch's design draws it, so a
        // `ViewThatFits` takes a row only where that much is left for it.
        .frame(idealWidth: 15, maxWidth: .infinity)
    }

    /// The flyer, where the app left one in the shared container, or a card
    /// of the event's colour where it did not.
    func poster(width: CGFloat, height: CGFloat, radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return Group {
            if let file = EventActivityAttributes.posterFile(for: attributes.eventID),
               let image = UIImage(contentsOfFile: file.path(percentEncoded: false)) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.white.opacity(0.12))
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
    }

    /// "1:27:13" to `moment`, counted down by the system and held at "0:00"
    /// once it is reached — so an activity nobody has updated since reads zero
    /// rather than counting back up.
    ///
    /// A timer rather than the sheet's "1h 27m". The formats that would print
    /// that are no use here: a date range in components is refused as a
    /// countdown ("The Text will not update"), a duration to the moment counts
    /// negative on the way to it, and the offset and timer styles that stop
    /// at minutes spell them out in words. The timer is the one countdown the
    /// system runs as a countdown.
    private func countdown(to moment: Date) -> Text {
        Text(timerInterval: Date.now...max(moment, .now), countsDown: true)
    }

    private func time(_ instant: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = state.timeZone
        return instant.formatted(style)
    }

    /// A time with the AM or PM a twelve-hour clock carries set small beside
    /// the digits, as the event's sheet sets it.
    private func clock(_ instant: Date?, size: CGFloat) -> Text {
        guard let instant else { return Text(verbatim: "—") }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = state.timeZone
        var time = instant.formatted(style.attributedStyle)
        let periods = time.runs[\.dateField].compactMap { field, range in
            field == .amPM ? range : nil
        }
        for range in periods {
            time[range].font = .system(size: size * 0.6, weight: .bold)
        }
        return Text(time)
    }
}

/// Shows what it is given only from its phase's start until its end —
/// switched by the system at those moments, with nobody sending the activity
/// anything.
///
/// The one thing an activity draws that changes by itself at a set time is
/// the system's own timer bar, so that is what each end is: a bar that fills
/// over a second from the moment, stretched over the whole view and used as
/// its mask (``Gate``). The stage coming on is wiped in from the leading side
/// as the one before it is wiped out towards the trailing side.
private struct Stretch: ViewModifier {
    let phase: EventActivityPhase

    func body(content: Content) -> some View {
        content
            .mask { Gate(at: phase.from, opening: true) }
            .mask { Gate(at: phase.until, opening: false) }
    }
}

/// Clear before `moment` and solid after it where it is `opening`, the other
/// way round where it is not — solid throughout where there is no moment.
///
/// The bar's empty track is not clear, and it is not the same grey wherever
/// the activity is drawn. On the phone it is a faint see-through grey, and
/// the bar used as a mask as it is left every hidden stage faintly showing
/// through the one in front. In the Mac's menu bar it is an opaque grey about
/// two-thirds of the way to white, which a mask lets through whole. Only the
/// fill is the same everywhere: white, as the tint asks. So the bar is drawn
/// on black and cut at a level only the fill reaches — brightness taken down
/// by 0.35 and contrast taken up sixteenfold, so everything under 0.82 of
/// white goes black and everything over 0.88 white — and only then made a
/// mask: the track comes out clear and the fill solid. Cut at the midpoint,
/// as `contrast(4)` alone cuts, the Mac's track still came out 90 % solid,
/// and every stage showed at once.
struct Gate: View {
    let moment: Date?
    let opening: Bool

    init(at moment: Date?, opening: Bool) {
        self.moment = moment
        self.opening = opening
    }

    var body: some View {
        if let moment {
            exact(at: moment)
        } else {
            Color.white
        }
    }

    /// The system's timer bar, filling over a second from `moment`, stretched
    /// over the whole view.
    func bar(at moment: Date) -> some View {
        ProgressView(timerInterval: moment...moment.addingTimeInterval(1), countsDown: !opening) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(.white)
        // Run well past the view at both ends, so the rounded end of the
        // fill — which stays put however little is filled — sits outside it
        // even in the island's narrowest place; and the few points of its
        // height stretched over all of it.
        .padding(.horizontal, -60)
        // Turned round for the stage going off, so its fill gives way from
        // the side the next one's comes in from.
        .scaleEffect(x: opening ? 1 : -1, y: 200)
    }

    /// The bar with its track cleared, whatever grey it is drawn in.
    func exact(at moment: Date) -> some View {
        ZStack {
            Color.black
            bar(at: moment)
        }
        .compositingGroup()
        .brightness(-0.35)
        .contrast(16)
        .luminanceToAlpha()
    }
}

#if DEBUG
extension EventActivityAttributes {
    fileprivate static let preview = EventActivityAttributes(
        eventID: "492514",
        title: "Liella! 6th LoveLive! Tour ～Twinkle Trail～",
        venue: "Kアリーナ横浜",
        link: URL(string: "https://www.eventernote.com/events/492514")!,
        opens: .now)
}

extension EventActivityAttributes.ContentState {
    fileprivate static func preview(_ stage: EventActivityStage, seat: String = "1階 L列 23番") -> Self {
        let doors = Date.now.addingTimeInterval(stage == .beforeDoors ? 87 * 60 : -10 * 60)
        let starts = doors.addingTimeInterval(stage == .startingSoon ? 12 * 60 : 60 * 60)
        return Self(stage: stage, doors: doors, starts: starts, ends: starts.addingTimeInterval(100 * 60),
                    runsTo: starts.addingTimeInterval(100 * 60), timeZone: .current, seat: seat)
    }
}

#Preview("Lock Screen", as: .content, using: EventActivityAttributes.preview) {
    EventLiveActivity()
} contentStates: {
    EventActivityAttributes.ContentState.preview(.beforeDoors)
    EventActivityAttributes.ContentState.preview(.doorsOpen)
    EventActivityAttributes.ContentState.preview(.onNow)
    EventActivityAttributes.ContentState.preview(.wrapped)
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: EventActivityAttributes.preview) {
    EventLiveActivity()
} contentStates: {
    EventActivityAttributes.ContentState.preview(.beforeDoors)
    EventActivityAttributes.ContentState.preview(.onNow)
}

#Preview("Compact", as: .dynamicIsland(.compact), using: EventActivityAttributes.preview) {
    EventLiveActivity()
} contentStates: {
    EventActivityAttributes.ContentState.preview(.beforeDoors)
    EventActivityAttributes.ContentState.preview(.onNow)
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: EventActivityAttributes.preview) {
    EventLiveActivity()
} contentStates: {
    EventActivityAttributes.ContentState.preview(.beforeDoors)
    EventActivityAttributes.ContentState.preview(.doorsOpen)
    EventActivityAttributes.ContentState.preview(.startingSoon)
    EventActivityAttributes.ContentState.preview(.onNow)
}

/// The Smart Stack card at the design's size, a 46 mm watch's: the canvas has
/// no small family to preview the activity in.
#Preview("Smart Stack") {
    let states: [EventActivityAttributes.ContentState] = [
        .preview(.beforeDoors), .preview(.doorsOpen, seat: ""), .preview(.onNow), .preview(.wrapped),
    ]
    VStack(spacing: 8) {
        ForEach(states, id: \.stage) { state in
            SmartStackView(moment: EventMoment(attributes: .preview, state: state, at: .now))
                .frame(width: 194, height: 89)
                .background(SmartStackView.base)
                .clipShape(.rect(cornerRadius: 20))
        }
    }
    .padding()
    .background(.black)
}
#endif
