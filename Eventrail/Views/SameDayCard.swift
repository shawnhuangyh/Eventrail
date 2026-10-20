import SwiftUI

/// The other events the reader keeps on this event's day, on its sheet: each
/// with its hours and hall, and whether the two can both be made — they
/// overlap, there is not time to get from one hall to the other, or there is.
/// See ``SameDay``.
///
/// The journey is asked of Apple Maps here, as the card appears, and nowhere
/// else (``TravelTimes``); My Events' rows mark what was found.
struct SameDayCard: View {
    let event: Event
    let pairs: [SameDay]
    /// Where this event's hall is, as the sheet's own lookup found it — nil
    /// while it is still asking. Handed in rather than asked again, which
    /// would search for an unplaced hall twice at once.
    let lookup: VenuePlaces.Lookup?
    /// The clock the sheet prints its times on.
    let clock: TimeDisplay
    let open: (Event) -> Void

    private let travelTimes = TravelTimes.shared
    /// The journeys Maps had no answer for, this time the card asked.
    @State private var unanswered: Set<String> = []

    /// What the journeys are asked about again on: the pairs, and whether
    /// this event's hall has been found yet.
    private struct Question: Equatable {
        let pairs: [SameDay]
        let isPlaced: Bool?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            CardHeader(title: "Same Day", count: pairs.count,
                       caption: Text("From one show's end to the next one's start"))

            VStack(spacing: 3) {
                ForEach(pairs, id: \.self) { pair in
                    row(pair)
                }
            }
        }
        .padding(18)
        .panel(cornerRadius: 28)
        .padding(.horizontal, 18)
        .task(id: Question(pairs: pairs, isPlaced: lookup.map { $0.placing != nil })) {
            await askTravel()
        }
    }

    private func row(_ pair: SameDay) -> some View {
        let other = pair.other(than: event)
        return Button { open(other) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(other.title)
                        .scalingFont(size: 14, weight: .semibold)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    caption(of: other)
                        .scalingFont(size: 12)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    verdict(for: pair)
                        .scalingFont(size: 12.5, weight: .medium)
                        .monospacedDigit()
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .scalingFont(size: 11, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the event")
    }

    /// Its hours and its hall: "13:00–16:00 · 日本武道館". The end only where
    /// the page published one, as no screen prints an assumed one.
    private func caption(of other: Event) -> Text {
        let shown = other.shown(on: clock)
        let hours: Text = switch (shown.timeLine, shown.endsLine) {
        case let (starts?, ends?): Text(verbatim: "\(starts)–\(ends)")
        case let (starts?, nil): Text("From \(starts)")
        default: Text("Time to be announced")
        }
        guard !other.venue.isEmpty else { return hours }
        return Text("\(hours) · \(other.venue)")
    }

    // MARK: - Whether both can be made

    @ViewBuilder
    private func verdict(for pair: SameDay) -> some View {
        switch pair.timing {
        case .untimed:
            line("clock.badge.questionmark", Text("Not checked — times to be announced"), tint: .secondary)
        case let .overlapping(by, endIsAssumed):
            line("exclamationmark.triangle.fill",
                 endIsAssumed
                    ? Text("May overlap by \(Self.duration(by)) — no end time announced")
                    : Text("Overlaps by \(Self.duration(by))"),
                 tint: .red)
        case .sameHall(let gap):
            line("building.2", Text("Same venue · \(Self.duration(gap)) between"), tint: .secondary)
        case .apart(let gap) where !pair.needsTravel:
            line("clock", Text("\(Self.duration(gap)) between"), tint: .secondary)
        case .apart(let gap):
            if let travel = travelTimes.travel(for: pair) {
                journey(travel, gap: gap)
            } else if unanswered.contains(TravelTimes.key(for: pair)) {
                line("questionmark.circle", Text("\(Self.duration(gap)) between · couldn't work out travel time"),
                     tint: .secondary)
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("\(Self.duration(gap)) between · working out travel time…")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// How long the journey takes, said against the time there is for it.
    private func journey(_ travel: TravelTimes.Travel, gap: TimeInterval) -> some View {
        let takes = Self.duration(travel.seconds, roundingUp: true)
        let between = Self.duration(gap)
        guard travel.seconds > gap else {
            let spare = Self.duration(gap - travel.seconds)
            let words: Text = switch travel.mode {
            case .transit: Text("\(takes) by transit · \(spare) to spare")
            case .walking: Text("\(takes) on foot · \(spare) to spare")
            case .driving: Text("\(takes) by car · \(spare) to spare")
            }
            return line(Self.symbol(for: travel.mode), words, tint: Color.trackAttended)
        }
        // One ending as the other starts has no time between, rather than
        // "only 0m".
        let words: Text = switch (travel.mode, gap < 60) {
        case (.transit, false): Text("\(takes) by transit, only \(between) between")
        case (.walking, false): Text("\(takes) on foot, only \(between) between")
        case (.driving, false): Text("\(takes) by car, only \(between) between")
        case (.transit, true): Text("\(takes) by transit, with no time between")
        case (.walking, true): Text("\(takes) on foot, with no time between")
        case (.driving, true): Text("\(takes) by car, with no time between")
        }
        return line("exclamationmark.triangle.fill", words, tint: .red)
    }

    private func line(_ symbol: String, _ words: Text, tint: some ShapeStyle) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
            words
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
    }

    private static func symbol(for mode: TravelTimes.Mode) -> String {
        switch mode {
        case .transit: "tram.fill"
        case .walking: "figure.walk"
        case .driving: "car.fill"
        }
    }

    /// "1h 30m", in whole minutes — a journey rounded up, the time there is
    /// for it rounded down, so neither reads as more room than there is.
    private static func duration(_ seconds: TimeInterval, roundingUp: Bool = false) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded(roundingUp ? .up : .down))
        return Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    // MARK: - Asking Maps

    /// Each journey still to be asked about, one at a time: this hall from
    /// the sheet's own lookup, the other's from what ``VenuePlaces`` has
    /// written down — or found now, for a hall nobody had opened.
    private func askTravel() async {
        unanswered = []
        for pair in pairs where pair.needsTravel && travelTimes.needsAsking(pair) {
            // Still looking: asked again once the lookup lands.
            guard let lookup else { return }
            let key = TravelTimes.key(for: pair)
            let other = pair.other(than: event)
            guard let here = lookup.placing,
                  let there = await VenuePlaces.shared.lookUp(other).placing
            else {
                unanswered.insert(key)
                continue
            }
            guard !Task.isCancelled else { return }
            let (origin, destination) = pair.earlier.id == event.id ? (here, there) : (there, here)
            if await travelTimes.ask(pair, from: origin, to: destination) == nil {
                guard !Task.isCancelled else { return }
                unanswered.insert(key)
            }
        }
    }
}
