import SwiftUI

/// One event at one moment: where it stands, in what colour, and the words and
/// times each screen prints for it.
///
/// On the day it reads the event by the Live Activity's own rules
/// (``EventActivityStage``) and in its colours, so the watch app and the card
/// in the Smart Stack never disagree about what is next. Any other day it is
/// "coming up", in the design's blue.
struct EventMoment {
    let event: WatchEvent
    let now: Date
    /// The clock the day and the times are printed on: the hall's, or the
    /// reader's where the phone's Settings › Time Zone says so.
    let zone: TimeZone
    /// The day printed — the hall's, or on the reader's clock the day of the
    /// first time the page published, as `Event.shown(on:)` has it.
    let day: Date
    /// Whole days from today to the event, counted in written dates as
    /// `Event.daysAway` counts them.
    let daysAway: Int
    /// The doors where they come before the start, and the end where it comes
    /// after it — what the Live Activity reads too.
    let doors: Date?
    let starts: Date?
    let ends: Date?
    /// The published end, or the app's assumed length after the start.
    let runsTo: Date?
    /// Where the event stands, once it is near enough to stand anywhere — nil
    /// on any day before, and on the day where no start was published.
    let stage: EventActivityStage?

    /// How long an event with no end published is given —
    /// `Event.assumedLength`.
    static let assumedLength: TimeInterval = 3 * 60 * 60

    init(_ event: WatchEvent, showsLocalTime: Bool, at now: Date) {
        self.event = event
        self.now = now
        if showsLocalTime, let anchor = event.doors ?? event.starts ?? event.ends {
            zone = .current
            day = anchor
        } else {
            zone = event.timeZone
            day = event.day
        }
        var printed = Calendar.current
        printed.timeZone = zone
        let reader = Calendar.current
        let written = reader.date(from: printed.dateComponents([.year, .month, .day], from: day)) ?? day
        daysAway = max(0, reader.dateComponents([.day], from: reader.startOfDay(for: now),
                                                to: reader.startOfDay(for: written)).day ?? 0)

        guard let starts = event.starts else {
            doors = event.doors
            self.starts = nil
            ends = event.ends
            runsTo = nil
            stage = nil
            return
        }
        let ends = event.ends.flatMap { $0 > starts ? $0 : nil }
        let doors = event.doors.flatMap { $0 < starts ? $0 : nil }
        let runsTo = ends ?? starts.addingTimeInterval(Self.assumedLength)
        self.doors = doors
        self.starts = starts
        self.ends = ends
        self.runsTo = runsTo
        // The written day decides, except for a hall whose day is still the
        // day before on the reader's calendar: its doors are what say so.
        let nearby = now >= (doors ?? starts).addingTimeInterval(-EventActivityStage.lead)
        stage = daysAway == 0 || nearby ? .at(now, doors: doors, starts: starts, runsTo: runsTo) : nil
    }

    /// Whether My Events still lists it: until its day is over on the clock it
    /// is printed on, and for as long as the show runs past that.
    var isListed: Bool {
        var printed = Calendar.current
        printed.timeZone = zone
        let dayEnds = printed.date(byAdding: .day, value: 1, to: printed.startOfDay(for: day)) ?? day
        return max(dayEnds, runsTo ?? dayEnds) > now
    }

    /// The design's blue for an event still to come.
    static let ahead = Color(red: 0x64 / 255, green: 0xA8 / 255, blue: 1)

    var tint: Color { stage?.tint ?? Self.ahead }

    /// The design's status wash: the colour from the top, gone by the foot.
    var wash: some View {
        LinearGradient(stops: [.init(color: tint.opacity(0.55), location: 0),
                               .init(color: tint.opacity(0.2), location: 0.58),
                               .init(color: .clear, location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .background(.black)
    }

    /// How far along the gauge has got: 0 at the doors, ½ at the start, 1 at
    /// the end, as the event's sheet fills its line.
    var fraction: Double {
        guard let stage, let starts, let runsTo else { return 0 }
        switch stage {
        case .wrapped: return 1
        case .onNow: return 0.5 + 0.5 * share(of: starts...runsTo)
        case .doorsOpen, .startingSoon: return doors.map { 0.5 * share(of: $0...starts) } ?? 0
        case .beforeDoors, .beforeShow: return 0
        }
    }

    private func share(of span: ClosedRange<Date>) -> Double {
        let length = span.upperBound.timeIntervalSince(span.lowerBound)
        guard length > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(span.lowerBound) / length))
    }

    /// The moments something drawn changes by itself — a stage giving way —
    /// for the screens to be drawn again at.
    var changes: [Date] {
        guard let starts, let runsTo else { return [] }
        return [(doors ?? starts).addingTimeInterval(-EventActivityStage.lead),
                doors, starts.addingTimeInterval(-EventActivityStage.soonBeforeStart), starts, runsTo]
            .compactMap(\.self)
            .filter { $0 > now }
    }

    // MARK: - Words

    /// A timer counting down to `date`: "1:24:13", then "24:13".
    func countdown(to date: Date) -> Text {
        Text(timerInterval: now...max(now, date), countsDown: true)
    }

    /// What the event is doing, in the words the Live Activity uses — nil
    /// before its day.
    var headline: Text? {
        guard let stage, let starts else { return nil }
        return switch stage {
        case .beforeDoors: Text("Doors in \(countdown(to: doors ?? starts))")
        case .beforeShow: Text("Starts in \(countdown(to: starts))")
        case .doorsOpen: Text("Doors open")
        case .startingSoon: Text("Starting in \(countdown(to: starts))")
        case .onNow: Text("On now")
        case .wrapped: Text("That's a wrap")
        }
    }

    /// The gauge's centre: what it counts to, the count, and the day.
    var gaugeLabel: Text {
        guard let stage else {
            return daysAway == 1 ? Text("Tomorrow") : Text("Coming up")
        }
        return switch stage {
        case .beforeDoors: Text("Doors in")
        case .beforeShow: Text("Starts in")
        case .doorsOpen: Text("Show in")
        case .startingSoon: Text("Starting in")
        case .onNow: ends == nil ? Text("On now") : Text("On now · ends in")
        case .wrapped: Text("That's a wrap")
        }
    }

    var gaugeValue: Text {
        guard let stage, let starts, let runsTo else {
            return daysAway == 0 ? Text("Today") : Text("^[\(daysAway) day](inflect: true)")
        }
        switch stage {
        case .beforeDoors: return countdown(to: doors ?? starts)
        case .beforeShow, .doorsOpen, .startingSoon: return countdown(to: starts)
        case .onNow: return ends == nil ? Text("LIVE") : countdown(to: runsTo)
        case .wrapped: return ends.map { Text(verbatim: time($0)) } ?? Text("Done")
        }
    }

    /// The pair of times the gauge runs between: the doors and the start
    /// until the doors have let everyone in, then the start and the end.
    var span: (from: (label: LocalizedStringKey, time: String), to: (label: LocalizedStringKey, time: String)) {
        let toStart: Bool = switch stage {
        case nil, .beforeDoors, .doorsOpen, .startingSoon: doors != nil || starts == nil
        case .beforeShow, .onNow, .wrapped: false
        }
        return toStart
            ? (("Doors", time(doors)), ("Start", time(starts)))
            : (("Start", time(starts)), ("End", time(ends)))
    }

    /// The Times page's heading: how far off, or what is happening.
    var timesHeading: Text {
        guard starts != nil else { return Text("Times TBA") }
        if let headline { return headline }
        return daysAway == 1 ? Text("Tomorrow") : Text("^[In \(daysAway) day](inflect: true)")
    }

    /// Whether the heading is told in the event's colour, or greyed: nothing
    /// published, or nothing left to happen.
    var timesHeadingIsLive: Bool { starts != nil && stage != .wrapped }

    /// Which of Doors, Start and End comes next, picked out in yellow.
    var nextTime: Int? {
        switch stage {
        case .beforeDoors: 0
        case .beforeShow, .doorsOpen, .startingSoon: 1
        case .onNow: 2
        case .wrapped, nil: nil
        }
    }

    /// Whether the time at `index` has gone by.
    func hasPassed(_ index: Int) -> Bool {
        stage == .wrapped || nextTime.map { index < $0 } ?? false
    }

    /// The line under the times: what is left, how long it runs, or what is
    /// still to be published.
    var timesFooter: Text {
        guard let starts else { return Text("Not announced yet") }
        if stage == .onNow, let ends { return Text("\(countdown(to: ends)) left") }
        if let ends {
            let length = Duration.seconds(ends.timeIntervalSince(starts))
            return Text("Runs \(length.formatted(.units(allowed: [.hours, .minutes], width: .narrow)))")
        }
        return Text("End time not announced")
    }

    // MARK: - The reader's ticket

    /// The seat page's headline: the class the seat was sold as, or where the
    /// reader stands with the ticket.
    var seatHeading: Text {
        switch event.seatClass {
        case "S席": Text("S Seat")
        case "A席": Text("A Seat")
        case "一般席": Text("General")
        case "": event.hasTicket ? Text("Your Seat") : isInLottery ? Text("Lottery") : Text("No Ticket")
        default: Text(verbatim: event.seatClass)
        }
    }

    private var isInLottery: Bool { (event.lotteryEntries ?? 0) > 0 }

    /// What it cost, or how many entries went into the lottery.
    var costLine: Text {
        if let cost = event.cost {
            // Cents only where there are any: ¥8,800, $49.99.
            var whole = Decimal(), value = cost
            NSDecimalRound(&whole, &value, 0, .plain)
            return Text(cost, format: .currency(code: event.currency ?? "JPY")
                .precision(.fractionLength(whole == cost ? 0 : 2)))
        }
        if let entries = event.lotteryEntries, entries > 0 {
            return Text("^[\(entries) entry](inflect: true)")
        }
        return Text(verbatim: "—")
    }

    var ticketLine: (text: Text, color: Color) {
        if event.hasTicket { return (Text("Purchased"), EventActivityStage.beforeDoors.tint) }
        if isInLottery { return (Text("Results pending"), Self.ahead) }
        return (Text("Add one on iPhone"), .white.opacity(0.55))
    }

    // MARK: - Dates and times

    /// "11:05", on the event's clock — or "--:--" where nothing was published.
    func time(_ date: Date?) -> String {
        guard let date else { return "--:--" }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone
        return date.formatted(style)
    }

    private func dated(_ style: Date.FormatStyle) -> String {
        var style = style
        style.timeZone = zone
        return day.formatted(style)
    }

    /// "Sat, Oct 3"
    var dayLine: String { dated(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
    /// "Oct 3"
    var shortDate: String { dated(.dateTime.month(.abbreviated).day()) }
    /// "Oct 3, 2026"
    var dateLine: String { dated(.dateTime.month(.abbreviated).day().year()) }
}
