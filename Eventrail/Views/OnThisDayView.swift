import SwiftData
import SwiftUI

/// Every event the reader went to on today's date in an earlier year
/// (``OnThisDay``), as `Eventrail.dc.html`'s On This Day board draws it: each
/// under how long ago it was and the day it fell on, with the flyer, the
/// times, the ticket, the seat and the note the reader wrote — and the way to
/// its ticket stub and its sheet.
///
/// Reached from the Me tab's card (``OnThisDayCard``). Read off the library
/// alone, as the Passport is: nothing here asks Eventernote anything, so it
/// has no refresh.
struct OnThisDayView: View {
    @Environment(EventStore.self) private var store
    /// Declared to be drawn again as the day turns — see ``EnvironmentValues/today``.
    @Environment(\.today) private var today
    /// Which clock the days and times are printed on — see ``TimeDisplay``.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue
    @Query(LibraryEntry.library) private var kept: [LibraryEntry]

    @State private var openEvent: Event?
    /// The event whose ticket stub is being made.
    @State private var stubEvent: Event?

    private var onThisDay: OnThisDay {
        OnThisDay(events: store.events(of: kept, where: \.inLibrary)) { store.tracking(for: $0) }
    }

    var body: some View {
        let today = onThisDay
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if today.memories.isEmpty {
                    // Reachable by staying on the screen past midnight, or by
                    // taking the last of them out of the library from its sheet.
                    Text("Nothing you went to fell on this day in an earlier year.")
                        .scalingFont(size: 12)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .panel()
                } else {
                    ForEach(today.memories) { memory in
                        VStack(alignment: .leading, spacing: 10) {
                            GroupHeader(label: memory.agoText,
                                        count: Text(verbatim: memory.event.shown(on: timeDisplay).dayLine),
                                        tint: .trackAttended)
                                .padding(.leading, 4)
                            card(memory.event)
                        }
                    }
                }

                Footnote(Text("Events you went to on \(today.dayText) in earlier years, from your own library. Nothing here is read from Eventernote."))
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .washBackground()
        .navigationTitle("On This Day")
        .navigationSubtitle(subtitle(of: today))
        .largeTitleOnMac(Text("On This Day"), subtitle: subtitle(of: today))
        .eventPane($openEvent)
        .sheet(item: $stubEvent) { TicketStubView(event: $0).macSheetSize(.form) }
    }

    /// Today, and how much there is under it.
    private func subtitle(of today: OnThisDay) -> Text {
        let day = today.date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        return Text("\(day) · ^[\(today.memories.count) event](inflect: true) across ^[\(today.years) year](inflect: true)")
    }

    // MARK: - One event

    /// The event as the reader went to it: what and where it was, the ticket
    /// and the seat, the note, and the two ways on.
    private func card(_ event: Event) -> some View {
        let tracking = store.tracking(for: event)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Button { openEvent = event } label: {
                    FlyerThumbnail(url: event.imageURL, width: 92, cornerRadius: 13)
                }
                .buttonStyle(.plain)
                .shadow(color: .black.opacity(0.1), radius: 9, y: 8)

                VStack(alignment: .leading, spacing: 6) {
                    Button { openEvent = event } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            AttendedTag()
                            Text(event.title)
                                .scalingFont(size: 16, weight: .bold)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)

                    if !event.venue.isEmpty {
                        NavigationLink(value: event.venueLink) {
                            HStack(spacing: 4) {
                                Text(event.venue)
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .scalingFont(size: 8, weight: .bold)
                            }
                            .scalingFont(size: 12.5, weight: .medium)
                            .foregroundStyle(Color.brandTint)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the venue")
                    }

                    if let times = timesLine(of: event) {
                        times
                            .scalingFont(size: 12)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                tile(symbol: "ticket", tint: .trackTicket,
                     value: ticketValue(tracking), isWritten: true,
                     detail: ticketDetail(tracking))
                let seat = tracking.seat.trimmingCharacters(in: .whitespacesAndNewlines)
                tile(symbol: "sofa", tint: .primary,
                     value: seat.isEmpty ? Text("No seat written down") : Text(verbatim: seat),
                     isWritten: !seat.isEmpty,
                     detail: LotteryText.seatClass(tracking.ticketClass))
            }
            .fixedSize(horizontal: false, vertical: true)

            if !tracking.note.isEmpty {
                OnThisDayNote(note: tracking.note)
            }

            HStack(spacing: 8) {
                if TicketStubFace.offered(for: tracking) {
                    pill { stubEvent = event } label: {
                        Label("Ticket Stub", systemImage: "ticket")
                            .foregroundStyle(.primary)
                    }
                }
                pill { openEvent = event } label: {
                    HStack(spacing: 5) {
                        Text("Open Event")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Color.brandTint)
                }
            }
        }
        .padding(16)
        .marksEventBeside(event.id, cornerRadius: 28)
        .panel(cornerRadius: 28)
    }

    /// "Doors 17:30 · Start 18:30 · Ran 2h 40m" — whichever of those the
    /// page published, on Settings' clock. Nil where it published none.
    private func timesLine(of event: Event) -> Text? {
        let shown = event.shown(on: timeDisplay)
        var parts: [Text] = []
        if let doors = shown.doorsLine { parts.append(Text("Doors \(doors)")) }
        if let starts = shown.timeLine { parts.append(Text("Start \(starts)")) }
        // Read in the order an event runs, and not past what a show could be,
        // as the event sheet reads its run time.
        let times = Event.inOrder(event.doorsOpen, event.startsAt, event.endsAt)
        if let starts = times.starts, let ends = times.ends {
            let length = ends.timeIntervalSince(starts)
            if length > 0, length <= PassportStats.longestEvent {
                // Narrow, as the sheet's "Runs 1h 40m": the abbreviated
                // style lists its units with a comma, "1 hr, 40 min".
                let ran = Duration.seconds(length)
                    .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
                parts.append(Text("Ran \(ran)"))
            }
        }
        guard let first = parts.first else { return nil }
        return parts.dropFirst().reduce(first) { Text("\($0) · \($1)") }
    }

    /// How the ticket was had: the first round to go well, in the order the
    /// sale ran — Won for a lottery, Got Tickets for a seat got first come or
    /// a ticket recorded with no round to it.
    private func ticketValue(_ tracking: Tracking) -> Text {
        guard let won = tracking.wonLottery else { return Text(TrackingStatus.attended.label) }
        return LotteryText.result(won.outcome, firstCome: !won.isLottery)
    }

    /// What it cost, the round it came from and how many times that round was
    /// applied for — whatever of it was written down.
    private func ticketDetail(_ tracking: Tracking) -> Text {
        var parts: [Text] = []
        if let price = tracking.price { parts.append(Text(verbatim: price.formatted)) }
        if let won = tracking.wonLottery {
            if !won.round.isEmpty { parts.append(LotteryText.round(of: won)) }
            if won.isLottery, won.applications > 0 {
                parts.append(Text("^[\(won.applications) entry](inflect: true)"))
            }
        }
        guard let first = parts.first else { return Text("No price written down") }
        return parts.dropFirst().reduce(first) { Text("\($0) · \($1)") }
    }

    /// One of the two readings under the event, set into the card rather than
    /// on a panel of its own. Not a button: the record is answered on the
    /// event's sheet, which Open Event opens.
    private func tile(symbol: String, tint: Color, value: Text, isWritten: Bool,
                      detail: Text) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(tint)
            value
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isWritten ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            detail
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(OnThisDayNote.fill, in: .rect(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// One of the two buttons along the foot of a card.
    private func pill<Content: View>(action: @escaping () -> Void,
                                     @ViewBuilder label: () -> Content) -> some View {
        Button(action: action) {
            label()
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .capsulePanel()
    }
}

// MARK: - The Me card

/// The Me tab's On This Day card: today's memories a row each, up to `limit`,
/// and the way into ``OnThisDayView``. The whole card pushes it, as the design
/// links every part of the card there, so it pushes as readily as its See All
/// does.
///
/// Rows rather than the design's lead drawn large — a 76-point poster with
/// the seat and the note beside and under it. Among the cards around it,
/// whose rows carry a 38-point flyer or none, that one card read out of step
/// with the rest of the tab, so every memory is the row Favorite Events draws
/// (``FavoriteEventRow``'s flyer, padding and divider), and the seat and the
/// note are left to the screen behind it.
///
/// Drawn only on a day there is something to show — see ``MeView``.
struct OnThisDayCard: View {
    let onThisDay: OnThisDay
    let limit: Int
    /// How tall the panel is drawn — as tall as its row, where the Me tab
    /// lays its cards out in a grid. Nil, as tall as it needs.
    var height: CGFloat? = nil

    var body: some View {
        NavigationLink(value: MeList.onThisDay) {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "On This Day", caption: caption) { SeeAllLabel() }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                let shown = Array(onThisDay.memories.prefix(limit))
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, memory in
                    row(memory, showsDivider: index > 0)
                }
            }
            .padding(.bottom, 6)
            .frame(maxHeight: height, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .panel()
    }

    /// "October 10 · 2 events you went to".
    private var caption: Text {
        Text("\(onThisDay.dayText) · ^[\(onThisDay.memories.count) event](inflect: true) you went to")
    }

    /// One memory: how long ago, then what and where.
    private func row(_ memory: OnThisDay.Memory, showsDivider: Bool) -> some View {
        HStack(spacing: 12) {
            FlyerThumbnail(url: memory.event.imageURL, width: 38, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 3) {
                memory.whenText
                    .scalingFont(size: 11.5, weight: .bold)
                    .foregroundStyle(Color.trackAttended)
                Text(memory.event.title)
                    .scalingFont(size: 14, weight: .semibold)
                Text(memory.event.venue)
                    .scalingFont(size: 11.5)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .scalingFont(size: 11, weight: .semibold)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            if showsDivider { Divider().padding(.leading, 66) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// What the reader wrote about the event, set into its card on the screen.
private struct OnThisDayNote: View {
    /// The fill of anything set into a card here — the note, and the
    /// screen's ticket and seat — rather than a panel in a panel, which reads
    /// as a box of boxes.
    static let fill = TicketForm.controlFill.opacity(0.6)

    let note: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "text.alignleft")
                .scalingFont(size: 12, weight: .semibold)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            Text(note)
                .scalingFont(size: 13)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Self.fill, in: .rect(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Notes"))
        .accessibilityValue(Text(note))
    }
}

/// Attended, in green, as the badge on a row says it — tinted rather than on
/// a pill of its own, since it sits in a card.
private struct AttendedTag: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.trackAttended)
                .frame(width: 6, height: 6)
            Text(TrackingStatus.attended.label)
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(Color.trackAttended)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.trackAttended.opacity(0.1), in: .capsule)
    }
}

// MARK: - Words

extension OnThisDay {
    /// Today's month and day — "October 10", "10月10日".
    var dayText: String {
        date.formatted(.dateTime.month(.wide).day())
    }
}

extension OnThisDay.Memory {
    /// "1 year ago".
    var agoText: Text {
        Text("^[\(yearsAgo) year](inflect: true) ago")
    }

    /// "1 year ago · 2025" — the year as the event's own day names it.
    var whenText: Text {
        Text("\(agoText) · \(event.localDay.formatted(.gregorian().year()))")
    }
}

#Preview {
    NavigationStack {
        OnThisDayView()
    }
    .library(EventStore.preview)
}
