import Foundation
import OSLog
import WidgetKit

/// Keeps the widgets' copy of the library in step with the store, and writes
/// down the lottery results given from them.
///
/// The widgets have no store of their own: they draw the ``WidgetLibrary``
/// this leaves in the App Group's container — the next few events, the
/// lottery rounds waiting on a result, the events gone to — and work out
/// everything that moves with the clock from it as they draw. So it is
/// written the way ``WatchLink`` sends: from ``RootView``, a second after the
/// library last changed, as the app opens and as it comes back, and only
/// where what is in it changed, since every widget asked to draw again costs
/// it some of the system's daily allowance.
///
/// The Lotteries widget's Won and Lost run in the extension, which must not
/// write to the store, so they leave their answer beside the copy
/// (``WidgetAnswer``) and this takes it in.
///
/// **The Mac has none**: the extension is the iPhone's and the iPad's alone,
/// so there this writes nothing, takes in nothing, and never reaches the App
/// Group's container.
@MainActor
final class WidgetLink {
    static let shared = WidgetLink()

    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "widgets")

    /// What was last written — read back from the file the first time, so a
    /// launch that finds the library as it left it asks no widget to draw.
    private var written: WidgetLibrary?
    private var pending: Task<Void, Never>?

    private init() {}

    /// Writes the library as `store` holds it a moment from now. A burst of
    /// edits — a note typed, a key at a time — reads the library once, after
    /// the last of them.
    func send(from store: EventStore) {
        guard !isMac else { return }
        pending?.cancel()
        pending = Task { [weak self, weak store] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, let store else { return }
            write(WidgetLibrary(store, display: .stored))
        }
    }

    private func write(_ library: WidgetLibrary) {
        guard let folder = WidgetLibrary.folder, let file = WidgetLibrary.file else { return }
        let before = written ?? WidgetLibrary.read()
        guard library != before else {
            written = library
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try encoder.encode(library).write(to: file, options: .atomic)
            written = library
        } catch {
            Self.log.error("The widgets' copy could not be written: \(error.localizedDescription, privacy: .public)")
            return
        }
        // Only the widgets whose part changed: a note typed on a past event
        // moves On This Day and nothing else.
        if library.upcoming != before?.upcoming { WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.nextEvent) }
        if library.rounds != before?.rounds { WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.lotteries) }
        if library.memories != before?.memories { WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.onThisDay) }
    }

    /// Writes down every result given from the Lotteries widget since the app
    /// last ran, and lets go of each.
    ///
    /// Only where the round is still waiting and its results day has come:
    /// the widget offered Won and Lost only then, and a result written since
    /// — on another device, or here — is the reader's later word. A win is
    /// given to the choice the widget named, or the round's only one; where
    /// the round has since come to apply with several, it is left for the
    /// reader to give here.
    func takeAnswers(into store: EventStore) {
        // Not while the library is held in memory for a file that will not
        // open yet: every answer would find no event there, and be thrown
        // away. Left for the next time the app comes back.
        guard !isMac, !store.libraryFileIsBlocked else { return }
        let waiting = WidgetAnswer.waiting()
        guard !waiting.isEmpty else { return }
        for (file, answer) in waiting.sorted(by: { $0.answer.given < $1.answer.given }) {
            give(answer, in: store)
            try? FileManager.default.removeItem(at: file)
        }
        // The widget left these rounds out until now; whatever the library
        // says of them from here on is what it draws.
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.lotteries)
    }

    /// One answer written down, where the rules above allow.
    func give(_ answer: WidgetAnswer, in store: EventStore) {
        guard let event = store.event(id: answer.eventID), store.isInLibrary(event) else { return }
        let before = store.tracking(for: event)
        guard let entry = before.lotteries.first(where: { $0.id == answer.entryID }),
              entry.isLottery, entry.isPending, entry.canBeDrawn()
        else { return }
        let result: LotteryResult
        if !answer.won {
            result = .lost
        } else if let choice = answer.choiceID, entry.choices.contains(where: { $0.id == choice }) {
            result = .won(choice)
        } else if entry.choices.count <= 1 {
            result = .won(entry.choices.first?.id)
        } else {
            return
        }
        // From waiting, a result can only give a ticket, never take one away,
        // so there is no seat or cost to ask about as the Lotteries list asks.
        store.setTracking(before.givingResult(result, toLottery: entry.id), for: event)
    }
}

extension WidgetLibrary {
    /// The library as `store` holds it, its days and times printed on the
    /// clock Settings › Time Zone names, as a Live Activity prints them.
    init(_ store: EventStore, display: TimeDisplay) {
        let upcoming = store.upcoming
        let rounds = LotteryList(events: upcoming) { store.tracking(for: $0) }.next
        self.init(
            upcoming: upcoming.prefix(Self.upcomingLimit).map {
                WidgetEvent($0, tracking: store.tracking(for: $0), display: display)
            },
            rounds: rounds.prefix(Self.roundLimit).map(WidgetRound.init),
            memories: store.attended.map { WidgetMemory($0, tracking: store.tracking(for: $0)) }
        )
    }
}

extension WidgetEvent {
    init(_ event: Event, tracking: Tracking, display: TimeDisplay) {
        let times = Event.inOrder(event.doorsOpen, event.startsAt, event.endsAt)
        let runsTo = times.starts.map { times.ends ?? $0.addingTimeInterval(Event.assumedLength) }
        let shown = event.shown(on: display)
        self.init(
            id: event.id,
            title: event.title,
            venue: event.venue,
            link: event.sourceURL,
            flyer: event.imageURL,
            day: CalendarDay(event.date, in: .gregorian(in: event.timeZone)),
            shownDay: shown.date,
            timeZone: shown.timeZone,
            doors: times.doors,
            starts: times.starts,
            ends: times.ends,
            runsTo: runsTo,
            leaves: runsTo ?? event.dayEnds,
            hasTicket: tracking.hasTicket,
            seat: tracking.seat.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

extension WidgetRound {
    init(_ row: LotteryRow) {
        let entry = row.entry
        self.init(
            eventID: row.event.id,
            entryID: entry.id,
            title: row.event.title,
            link: row.event.sourceURL,
            round: entry.round.isEmpty
                ? String(localized: "Lottery", comment: "A lottery round with no round named, as the Lotteries widget lists it.")
                : LotteryRound.label(of: entry.round),
            applications: entry.applications,
            day: entry.day,
            choices: entry.choices.count,
            onlyChoice: entry.choices.count == 1 ? entry.choices[0].id : nil,
            eventEnds: row.event.dayEnds
        )
    }
}

extension WidgetMemory {
    init(_ event: Event, tracking: Tracking) {
        let note = tracking.note
            .split(whereSeparator: \.isNewline).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        self.init(
            id: event.id,
            title: event.title,
            venue: event.venue,
            link: event.sourceURL,
            flyer: event.imageURL,
            day: CalendarDay(event.date, in: .gregorian(in: event.timeZone)),
            sortDate: event.sortDate,
            note: String(note.prefix(160))
        )
    }
}
