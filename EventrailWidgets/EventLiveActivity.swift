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
/// stretch of the night (``Stretch``), switched by the system as the night runs
/// on. Everything that moves within a stage is a view the system runs by
/// itself too: the countdowns are timers, held at zero once they run out, and
/// the fill is a timer progress bar.
///
/// Only what changes with the stage is drawn more than once — the words, the
/// seat's colour, the two times and the fill. The flyer, the title and the
/// hall are drawn once.
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
struct EventLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EventActivityAttributes.self) { context in
            LockScreenView(night: Night(context))
                .activityBackgroundTint(Night.platter)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(context.attributes.link)
        } dynamicIsland: { context in
            let night = Night(context)
            return DynamicIsland {
                // The top row splits around the camera: the time counted from
                // on one side, the time counted to on the other.
                DynamicIslandExpandedRegion(.leading) {
                    night.eachStage(alignment: .leading) { night in
                        night.stopColumn(night.stops.from, alignment: .leading)
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    night.eachStage(alignment: .trailing) { night in
                        night.stopColumn(night.stops.to, alignment: .trailing)
                    }
                    .padding(.trailing, 6)
                }
                // Everything else below it: the event, and where the night
                // stands beside the seat. The design sets a rule between the
                // two; the island has no height to spare for one.
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        HStack(spacing: 10) {
                            night.poster(width: 22, height: 31, radius: 5)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: night.attributes.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.92))
                                Text(verbatim: night.attributes.venue)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        night.eachStage { night in
                            HStack(spacing: 12) {
                                night.headline
                                    .font(.system(size: 17, weight: .bold))
                                    .kerning(-0.17)
                                    .monospacedDigit()
                                    .foregroundStyle(night.tint)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                night.seatCapsule(height: 24)
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
                night.poster(width: 20, height: 26, radius: 6)
            } compactTrailing: {
                // A timer takes all the width it is offered, so it is given
                // only what its longest reading needs.
                night.eachStage(alignment: .trailing) { night in
                    night.shortStatus
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(night.tint)
                }
                .frame(maxWidth: 62, alignment: .trailing)
            } minimal: {
                night.eachStage { night in
                    night.shortStatus
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .foregroundStyle(night.tint)
                        .minimumScaleFactor(0.5)
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
            .keylineTint(night.tint)
            .widgetURL(night.attributes.link)
        }
    }
}

/// The Lock Screen card: where the night stands and what comes next, the seat,
/// the event itself, and the two times the fill runs between.
struct LockScreenView: View {
    let night: Night

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            night.eachStage(alignment: .topLeading) { night in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        night.headline
                            .font(.system(size: 20, weight: .bold))
                            .kerning(-0.4)
                            .foregroundStyle(night.tint)
                        if let detail = night.detail {
                            detail
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .lineLimit(1)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    night.seatCapsule()
                }
            }

            HStack(spacing: 9) {
                night.poster(width: 26, height: 36, radius: 5)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: night.attributes.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(verbatim: night.attributes.venue)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .lineLimit(1)
            }

            night.eachStage { night in
                night.trackRow(timeSize: 18, labelSize: 11)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .environment(\.colorScheme, .dark)
    }
}

/// One activity's worth of what to draw, worked out once from its context —
/// and, through ``eachStage(alignment:_:)``, once for each stage still to come.
struct Night {
    let attributes: EventActivityAttributes
    let state: EventActivityAttributes.ContentState
    /// The rest of the night as it stands as this is drawn — see
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

    private init(_ night: Night, stage: EventActivityStage) {
        attributes = night.attributes
        state = night.state
        phases = night.phases
        self.stage = stage
    }

    /// `content` drawn once for each stage still to come, each shown only in
    /// its own stretch of the night.
    func eachStage<Content: View>(alignment: Alignment = .center,
                                  @ViewBuilder _ content: @escaping (Night) -> Content) -> some View {
        ZStack(alignment: alignment) {
            ForEach(phases, id: \.stage) { phase in
                content(Night(self, stage: phase.stage))
                    .modifier(Stretch(phase: phase))
            }
        }
    }

    /// The card behind the Lock Screen presentation: the design's smoked
    /// glass, dark on any wallpaper so the tints read the same on every one.
    static let platter = Color(red: 22 / 255, green: 20 / 255, blue: 30 / 255).opacity(0.58)

    /// Amber until the doors, green with them open, orange in the last
    /// minutes, red on stage, grey once it is over — the design's colours,
    /// set for the dark the activity is always drawn on.
    var tint: Color {
        switch stage {
        case .beforeDoors, .beforeShow: Color(red: 1, green: 0xB3 / 255, blue: 0x40 / 255)
        case .doorsOpen: Color(red: 0x4C / 255, green: 0xD9 / 255, blue: 0x64 / 255)
        case .startingSoon: Color(red: 1, green: 0x7A / 255, blue: 0x59 / 255)
        case .onNow: Color(red: 1, green: 0x4F / 255, blue: 0x6A / 255)
        case .wrapped: Color(red: 0xB9 / 255, green: 0xB6 / 255, blue: 0xC4 / 255)
        }
    }

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

    /// The seat, where the reader wrote one down: a capsule in the night's
    /// colour, as the design sets it on the Lock Screen and in the island —
    /// 28 points tall there, a little less in the island, which has none to
    /// spare.
    @ViewBuilder
    func seatCapsule(height: CGFloat = 28) -> some View {
        if !state.seat.isEmpty {
            HStack(spacing: 6) {
                Text("Seat")
                    .font(.system(size: 9.5, weight: .bold))
                    .kerning(0.76)
                    .textCase(.uppercase)
                    .opacity(0.7)
                Text(verbatim: state.seat)
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
            }
            .lineLimit(1)
            .foregroundStyle(.black)
            .padding(.horizontal, 11)
            .frame(height: height)
            .background(tint, in: .capsule)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A time the night runs between, and which one it is.
    struct Stop {
        let instant: Date?
        let label: LocalizedStringKey
    }

    /// Whether the night is still counting from the doors to the start, rather
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
    /// side away from the fill, on one line.
    func trackRow(timeSize: CGFloat, labelSize: CGFloat) -> some View {
        let stops = stops
        return HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                time(stops.from.instant, size: timeSize)
                label(stops.from.label, size: labelSize)
            }
            .fixedSize()
            fill
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                label(stops.to.label, size: labelSize)
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

    /// The line between the two times, filled by the system as the night
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
        .frame(maxWidth: .infinity)
    }

    /// The flyer, where the app left one in the shared container, or a card
    /// of the night's colour where it did not.
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
/// The bar's empty track is not clear — used as it is, it left every hidden
/// stage faintly showing through the one in front. So the bar is drawn white
/// on black and taken to its extremes, and only then made a mask: the track
/// comes out clear and the fill solid.
private struct Gate: View {
    let moment: Date?
    let opening: Bool

    init(at moment: Date?, opening: Bool) {
        self.moment = moment
        self.opening = opening
    }

    var body: some View {
        if let moment {
            ZStack {
                Color.black
                ProgressView(timerInterval: moment...moment.addingTimeInterval(1), countsDown: !opening) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(.white)
                // Run well past the view at both ends, so the rounded end of
                // the fill — which stays put however little is filled — sits
                // outside it even in the island's narrowest place; and the
                // few points of its height stretched over all of it.
                .padding(.horizontal, -60)
                // Turned round for the stage going off, so its fill gives way
                // from the side the next one's comes in from.
                .scaleEffect(x: opening ? 1 : -1, y: 200)
            }
            .compositingGroup()
            .contrast(4)
            .luminanceToAlpha()
        } else {
            Color.white
        }
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
    fileprivate static func preview(_ stage: EventActivityStage) -> Self {
        let doors = Date.now.addingTimeInterval(stage == .beforeDoors ? 87 * 60 : -10 * 60)
        let starts = doors.addingTimeInterval(stage == .startingSoon ? 12 * 60 : 60 * 60)
        return Self(stage: stage, doors: doors, starts: starts, ends: starts.addingTimeInterval(100 * 60),
                    runsTo: starts.addingTimeInterval(100 * 60), timeZone: .current, seat: "1階 L列 23番")
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
#endif
