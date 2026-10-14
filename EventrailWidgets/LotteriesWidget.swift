import AppIntents
import SwiftUI
import UserNotifications
import WidgetKit

/// The lottery rounds waiting on their results, as the design's Lotteries
/// board draws them: the next round on the small widget — its results out,
/// or how many days until they are — two on the medium, and on the Lock
/// Screen how many are out, or the next.
///
/// Read off the same rounds the Lotteries screen lists as Awaiting (the
/// lottery rounds of events still ahead, by results day), so a round leaves
/// once it is given a result or its event is over. On the medium widget a
/// round whose results are out is given Won or Lost where it stands
/// (``GiveLotteryResult``), as the list's swipes give it — Won opens the app
/// instead where the round applied with several choices, since which one
/// was won is the reader's to say.
struct LotteriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.lotteries, provider: LotteriesProvider()) { entry in
            LotteriesWidgetView(entry: entry)
        }
        .configurationDisplayName("Lotteries")
        .description("The lottery rounds waiting on their results — and Won or Lost, once they are out.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

nonisolated struct LotteriesEntry: TimelineEntry, Sendable {
    let date: Date
    /// Waiting on a result as of ``date``: by results day, the soonest first
    /// — a day already come leading — and no day last.
    let rounds: [WidgetRound]
}

nonisolated struct LotteriesProvider: TimelineProvider {
    func placeholder(in context: Context) -> LotteriesEntry {
        LotteriesEntry(date: .now, rounds: WidgetSamples.rounds())
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (LotteriesEntry) -> Void) {
        let entry = Self.timeline(at: .now).entries.first ?? placeholder(in: context)
        completion(context.isPreview && entry.rounds.isEmpty ? placeholder(in: context) : entry)
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<LotteriesEntry>) -> Void) {
        completion(Self.timeline(at: .now))
    }

    /// An entry now and at each of the week's midnights, when a results day
    /// comes and the days left move on. A round given a result here, and not
    /// yet taken in by the app, is left out from the moment it was given.
    static func timeline(at now: Date) -> Timeline<LotteriesEntry> {
        let answered = Set(WidgetAnswer.waiting().map(\.answer.roundID))
        let rounds = (WidgetLibrary.read() ?? .empty).rounds.filter { !answered.contains($0.id) }
        let entries = ([now] + Calendar.gregorian().midnights(after: now, count: 7)).map { time in
            LotteriesEntry(date: time, rounds: rounds.filter { $0.eventEnds > time })
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

// MARK: - Giving a result

/// Won or Lost for one round, from the medium widget.
///
/// Run in the extension, which has no store and writes none: the answer is
/// left beside the library's copy (``WidgetAnswer``) for the app to write
/// down the next time it runs, and the widget leaves the round out until
/// then. The round's results-day reminder is taken back too, so it does not
/// ask at eight for a result already given.
struct GiveLotteryResult: AppIntent {
    static let title: LocalizedStringResource = "Give Lottery Result"
    static let isDiscoverable = false

    @Parameter(title: "Event") var eventID: String
    @Parameter(title: "Round") var entryID: String
    @Parameter(title: "Won") var won: Bool
    /// The choice won, where the round applied with one; empty otherwise.
    @Parameter(title: "Choice") var choiceID: String

    init() {}

    init(_ round: WidgetRound, won: Bool) {
        eventID = round.eventID
        entryID = round.entryID.uuidString
        self.won = won
        choiceID = won ? round.onlyChoice?.uuidString ?? "" : ""
    }

    func perform() async throws -> some IntentResult {
        guard let entry = UUID(uuidString: entryID) else { return .result() }
        let answer = WidgetAnswer(eventID: eventID, entryID: entry, won: won,
                                  choiceID: UUID(uuidString: choiceID), given: .now)
        try answer.save()
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [answer.roundID])
        center.removeDeliveredNotifications(withIdentifiers: [answer.roundID])
        return .result()
    }
}

// MARK: - The faces

struct LotteriesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LotteriesEntry

    var body: some View {
        LotteriesFace(entry: entry, family: family)
    }
}

struct LotteriesFace: View {
    let entry: LotteriesEntry
    let family: WidgetFamily

    private var now: Date { entry.date }
    private var outCount: Int { entry.rounds.count { $0.isOut(asOf: now) } }

    var body: some View {
        content
            .containerBackground(for: .widget) { background }
            .widgetURL(link)
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    @ViewBuilder private var background: some View {
        switch family {
        case .accessoryCircular: AccessoryWidgetBackground()
        case .accessoryRectangular: Color.clear
        default: WidgetWash()
        }
    }

    /// Where a tap anywhere opens the app: the round's own page where its
    /// results are out and it has a result to give, and otherwise its
    /// event. The medium widget's rows carry links of their own.
    private var link: URL? {
        guard family != .systemMedium, let first = entry.rounds.first else { return nil }
        return first.isOut(asOf: now) ? first.roundLink : first.link
    }

    /// "Earliest Presale Lottery · 2 entries".
    private func roundLine(_ round: WidgetRound) -> Text {
        guard round.applications > 0 else { return Text(verbatim: round.round) }
        return Text("\(Text(verbatim: round.round)) · \(Text("^[\(round.applications) entry](inflect: true)"))")
    }

    /// "4 rounds · 1 out".
    private var summary: Text {
        let rounds = Text("^[\(entry.rounds.count) round](inflect: true)")
        return outCount > 0 ? Text("\(rounds) · \(Text("\(outCount) out"))") : rounds
    }

    // MARK: Small

    @ViewBuilder private var small: some View {
        if let first = entry.rounds.first {
            if first.isOut(asOf: now) {
                smallOut(first)
            } else {
                smallWaiting(first)
            }
        } else {
            emptyPanel
        }
    }

    /// The round whose results are out: its tile, and the reader asked to
    /// write down how it went.
    private func smallOut(_ round: WidgetRound) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "Lotteries", symbol: "ticket")
            HStack(spacing: 9) {
                LotteryTile(round: round, now: now)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Results out")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.trackTicket)
                        .widgetAccentable()
                    Text("Record it")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.ticketInk)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .padding(.top, 10)
            Spacer(minLength: 4)
            Text(verbatim: round.title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(2)
            roundLine(round)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Nothing out yet: how many days until the next results, the round's
    /// event, and how many are waiting.
    private func smallWaiting(_ round: WidgetRound) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "Lotteries", symbol: "ticket")
            if let day = round.day {
                let days = day.daysAway(from: now)
                Text("Next results in")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 8)
                BigCount(count: days, unit: WidgetText.daysUnit(days), size: 38)
            } else {
                Text("No results day")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 8)
                Text("Not Set")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            Text(verbatim: round.title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
            Text("^[\(entry.rounds.count) round](inflect: true) awaiting")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Medium

    @ViewBuilder private var medium: some View {
        if entry.rounds.isEmpty {
            emptyPanel
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    WidgetHeader(title: "Lotteries", symbol: "ticket")
                    Spacer(minLength: 6)
                    summary
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                ForEach(entry.rounds.prefix(2)) { round in
                    row(round)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// One round: its tile, its event and the round — opening the event —
    /// and Won and Lost once its results are out, or how far off they are.
    private func row(_ round: WidgetRound) -> some View {
        HStack(spacing: 10) {
            Link(destination: round.link) {
                HStack(spacing: 10) {
                    LotteryTile(round: round, now: now)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: round.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        roundLine(round)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // A link draws its label in the tint, as a button would.
            .buttonStyle(.plain)
            if round.isOut(asOf: now) {
                wonButton(round)
                Button(intent: GiveLotteryResult(round, won: false)) {
                    pill(Text("Lost"), fill: Color(red: 118 / 255, green: 118 / 255, blue: 128 / 255).opacity(0.18),
                         ink: .primary)
                }
                .buttonStyle(.plain)
            } else {
                Group {
                    if let day = round.day {
                        Text(verbatim: WidgetText.relative(days: day.daysAway(from: now)))
                    } else {
                        Text("Not Set")
                    }
                }
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            }
        }
    }

    /// Won, given where it stands — or, where the round applied with several
    /// choices, the round opened in the app to say which.
    @ViewBuilder private func wonButton(_ round: WidgetRound) -> some View {
        let label = pill(Text("Won"), fill: .solidWon, ink: .white)
        if round.choices > 1 {
            Link(destination: round.roundLink) { label }
                .buttonStyle(.plain)
        } else {
            Button(intent: GiveLotteryResult(round, won: true)) { label }
                .buttonStyle(.plain)
        }
    }

    private func pill(_ text: Text, fill: Color, ink: Color) -> some View {
        text
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(fill, in: .capsule)
    }

    // MARK: Lock Screen

    /// How many rounds are out — or, with none, how many days until the next
    /// results.
    private var circular: some View {
        VStack(spacing: 1) {
            Image(systemName: "ticket")
                .font(.system(size: 13, weight: .semibold))
            if outCount > 0 {
                Text(outCount, format: .number)
                    .font(.system(size: 17, weight: .bold))
                Text("OUT")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.4)
                    .opacity(0.8)
            } else if let day = entry.rounds.lazy.compactMap(\.day).first {
                Text("\(day.daysAway(from: now))d")
                    .font(.system(size: 17, weight: .bold))
                Text("NEXT")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.4)
                    .opacity(0.8)
            } else {
                Text(verbatim: "—")
                    .font(.system(size: 17, weight: .bold))
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 8)
        .widgetAccentable()
    }

    /// The next round: its results out, or the day they come.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let round = entry.rounds.first {
                Group {
                    if round.isOut(asOf: now) {
                        Text("Results out")
                    } else if let day = round.day {
                        Text("Results \(WidgetText.short(day, asOf: now))")
                    } else {
                        Text("No results day")
                    }
                }
                .font(.system(size: 15, weight: .bold))
                .widgetAccentable()
                Text(verbatim: round.title)
                    .font(.system(size: 13.5, weight: .medium))
                Group {
                    if !round.isOut(asOf: now), let day = round.day {
                        Text("\(Text(verbatim: round.round)) · \(Text(verbatim: WidgetText.relativeInline(days: day.daysAway(from: now))))")
                    } else {
                        Text(verbatim: round.round)
                    }
                }
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.secondary)
            } else {
                Text("Lotteries")
                    .font(.system(size: 15, weight: .bold))
                Text("No rounds awaiting results.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Nothing waiting

    private var emptyPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: "Lotteries", symbol: "ticket")
            Spacer(minLength: 0)
            Text("No rounds awaiting results.")
                .font(.system(size: 13, weight: .semibold))
            Text("Rounds you enter for an upcoming event wait here for their results.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview("Small", as: .systemSmall) {
    LotteriesWidget()
} timeline: {
    LotteriesEntry(date: .now, rounds: WidgetSamples.rounds())
    LotteriesEntry(date: .now, rounds: Array(WidgetSamples.rounds().dropFirst()))
}

#Preview("Medium", as: .systemMedium) {
    LotteriesWidget()
} timeline: {
    LotteriesEntry(date: .now, rounds: WidgetSamples.rounds())
}
