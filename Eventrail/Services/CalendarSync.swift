import EventKit
import MapKit
import os
import SwiftUI

/// Mirrors the reader's library into their calendar.
///
/// Everything written goes into one calendar Eventrail creates and owns. A
/// calendar the reader made is never touched: the mirror is one-way and
/// self-contained, so turning it off is a single deletion rather than a hunt
/// through a diary the app does not own.
///
/// Past events belong here as much as upcoming ones — a calendar is a diary as
/// well as a plan. Which events qualify is ``EventStore/calendarEvents``; this
/// type mirrors whatever it is handed.
///
/// Every entry also carries one alert, set for the moment the doors open,
/// wherever Eventernote has published a door time — past nights included, so
/// the diary records the hour the reader had to be there. No switch governs it:
/// the door time is the event's own fact rather than a preference, and a
/// reader who has asked for their events in their calendar has asked to be
/// somewhere on time. Calendar's own per-entry alert remains theirs to change.
final class CalendarSync {
    static let shared = CalendarSync()

    /// What the last mirror did, or why it could not.
    ///
    /// `denied` is kept apart from `failed` because it is the one case the
    /// reader can do something about, and the Settings screen says so.
    enum Outcome: Hashable {
        case mirrored(Int)
        case denied
        case failed(String)
    }

    private let store = EKEventStore()

    /// What the last mirror wrote, in enough detail to tell an entry that
    /// carries a place from one that carries only a line of text.
    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "calendar")

    /// The calendar Eventrail made, remembered per device: a calendar
    /// identifier belongs to this device's calendar database and means nothing
    /// on another one, so it is deliberately not part of the synced archive.
    ///
    /// It is a cache rather than the answer. The calendar itself usually lives
    /// on the reader's iCloud account and so *is* shared between their devices
    /// — see ``adoptableCalendar()`` for what happens when this says nothing
    /// and one is already there.
    private static let calendarKey = "calendarSyncIdentifier"

    private var savedCalendarID: String? {
        get { UserDefaults.standard.string(forKey: Self.calendarKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.calendarKey) }
    }

    /// How long a performance runs when Eventernote has published a start but
    /// no end. Used only to give the calendar entry a length; the detail sheet
    /// still shows nothing where the site published nothing.
    private static let assumedLength: TimeInterval = 3 * 60 * 60

    /// EventKit refuses a search window longer than four years, so a wider
    /// range is read in chunks of this size.
    private static let window: TimeInterval = 4 * 365 * 24 * 60 * 60

    /// How far either side of today the app's own calendar is swept for
    /// entries to correct or remove.
    ///
    /// Deliberately not measured from the library. An entry whose event has
    /// left the library is not in the library to be measured, so a range that
    /// began at the earliest night still held could never reach it: a reader
    /// who removes the oldest night of a ten-year history — or empties the
    /// whole library — would leave everything before the cut-off sitting in
    /// their diary with nothing left that would ever remove it. A fixed sweep
    /// costs ten predicates against one calendar this app owns, and finds
    /// them.
    private static let sweepBack: TimeInterval = 30 * 365 * 24 * 60 * 60
    private static let sweepAhead: TimeInterval = 10 * 365 * 24 * 60 * 60

    // MARK: - Mirroring

    /// Brings the calendar into line with `events`, adding what is missing,
    /// correcting what moved, and deleting what has left the library.
    ///
    /// Matching is by the Eventernote page URL rather than by title: a title
    /// can be re-published, and an entry the reader dragged elsewhere is still
    /// the same event.
    func mirror(_ events: [Event]) async -> Outcome {
        guard await requestAccess() else { return .denied }
        // Whatever has been looked up already. The mirror never searches for a
        // hall itself — see ``VenuePlaces`` — so an event at a hall the reader
        // has not opened yet gets its name and waits for a later mirror.
        let places = VenuePlaces.shared.mapItems(for: events)
        do {
            let calendar = try calendar()
            var wanted = Dictionary(
                events.map { ($0.sourceURL, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            for entry in entries(in: calendar, covering: events) {
                // Anything in this calendar that no longer answers to an event
                // in the library goes: the reader took the event back out.
                guard let url = entry.url, let event = wanted.removeValue(forKey: url) else {
                    try store.remove(entry, span: .thisEvent, commit: false)
                    continue
                }
                if apply(event, to: entry, places: places) {
                    try store.save(entry, span: .thisEvent, commit: false)
                }
            }

            for event in wanted.values {
                let entry = EKEvent(eventStore: store)
                entry.calendar = calendar
                _ = apply(event, to: entry, places: places)
                try store.save(entry, span: .thisEvent, commit: false)
            }

            try store.commit()
            let located = events.filter { places[$0.id] != nil }.count
            Self.log.info("mirrored \(events.count, privacy: .public) events, \(located, privacy: .public) with a place on the map")
            return .mirrored(events.count)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Takes the whole calendar back out again.
    ///
    /// Deleting the calendar rather than emptying it is what makes "off" mean
    /// off: nothing of Eventrail's is left in the reader's diary, not even an
    /// empty calendar they would have to tidy up themselves.
    ///
    /// A calendar on an iCloud account is one object rather than one per
    /// device, so switching the mirror off on the phone takes it off the iPad
    /// too — until the iPad's next mirror, which makes it again, because that
    /// device's switch is still on and per-device. A momentary flap that
    /// settles itself is the price of the alternative being two calendars of
    /// one name, each holding the whole library; see ``adoptableCalendar()``.
    func stop() async {
        guard savedCalendarID != nil, await requestAccess() else { return }
        defer { savedCalendarID = nil }
        guard let id = savedCalendarID, let calendar = store.calendar(withIdentifier: id) else { return }
        try? store.removeCalendar(calendar, commit: true)
    }

    // MARK: - Access

    /// Full access, not write-only: the mirror has to read back what it wrote
    /// to correct and remove it, and write-only permission cannot do that. It
    /// reads nothing outside the one calendar this app created.
    private func requestAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .denied, .restricted:
            return false
        default:
            return (try? await store.requestFullAccessToEvents()) ?? false
        }
    }

    // MARK: - The app's own calendar

    private func calendar() throws -> EKCalendar {
        let kept: EKCalendar
        if let id = savedCalendarID, let existing = store.calendar(withIdentifier: id) {
            kept = existing
        } else if let adopted = adoptableCalendar() {
            savedCalendarID = adopted.calendarIdentifier
            kept = adopted
        } else {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = String(localized: "Eventrail")
            calendar.cgColor = UIColor(Color.brandTint).cgColor
            guard let source = preferredSource() else {
                throw CalendarSyncError.noCalendarSource
            }
            calendar.source = source
            try store.saveCalendar(calendar, commit: true)
            savedCalendarID = calendar.calendarIdentifier
            // Nothing to tidy behind a calendar that did not exist a moment ago.
            return calendar
        }
        discardDuplicates(of: kept)
        return kept
    }

    /// Takes out any second calendar of this app's own.
    ///
    /// Adopting stops another one from being made; it does not clear up the
    /// ones already made, and a reader whose phone and iPad each wrote their
    /// own has two of everything until something does. Only a calendar that
    /// passes the same test adoption uses is removed — this app's name, and
    /// nothing in it but entries pointing back at Eventernote — so what goes
    /// is a copy of what is being kept, never a diary of the reader's own.
    ///
    /// The other device notices in the ordinary way: its saved identifier
    /// stops resolving, so its next mirror adopts the survivor, and the two
    /// converge on one calendar without either having to be told.
    private func discardDuplicates(of kept: EKCalendar) {
        for calendar in store.calendars(for: .event)
        where calendar.calendarIdentifier != kept.calendarIdentifier && isAdoptable(calendar) {
            try? store.removeCalendar(calendar, commit: true)
        }
    }

    /// Wherever the reader's own new events go, so Eventrail's calendar lands
    /// beside them and follows them to their other devices.
    private func preferredSource() -> EKSource? {
        store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .calDAV && $0.title == "iCloud" }
            ?? store.sources.first { $0.sourceType == .local }
            ?? store.sources.first
    }

    /// The calendar this app made and then lost track of.
    ///
    /// Going by ``savedCalendarID`` alone is right about where it is kept and
    /// wrong about what it proves. The identifier is this device's, but the
    /// calendar it names is usually the reader's iCloud account's, and that
    /// syncs: an iPad with nothing in `UserDefaults` would make a second
    /// "Eventrail" beside the one the phone had already sent it, each device
    /// mirroring the whole library into its own, and the reader would see
    /// every night twice under one name. The same gap opens on a single
    /// device whenever the identifier stops resolving — a restore, or iCloud
    /// handing the calendar back under a new one — and there the entries
    /// already written are not even reachable to be corrected, since every
    /// search here is scoped to the calendar it was handed.
    ///
    /// So a calendar is adopted rather than remade when it is one this app
    /// could have written: named as this app names its own, writable, and
    /// holding nothing but entries that point back at Eventernote. **The last
    /// test is the one that matters.** This mirror removes whatever it finds
    /// that no longer answers to an event in the library, so adopting a
    /// calendar of the reader's own that happened to share the name would
    /// empty it.
    private func adoptableCalendar() -> EKCalendar? {
        store.calendars(for: .event).first(where: isAdoptable)
    }

    /// Whether this is a calendar this app could have written: named as this
    /// app names its own, writable, and holding nothing but entries pointing
    /// back at Eventernote. An empty one passes — that is a calendar made on
    /// another device and synced here before it had anything in it.
    private func isAdoptable(_ calendar: EKCalendar) -> Bool {
        Self.ownTitles.contains(calendar.title)
            && calendar.allowsContentModifications
            && entries(in: calendar, covering: []).allSatisfy(Self.isOurs)
    }

    /// What this app calls its own calendar. The title is localized, so the
    /// English name is kept beside whatever this device would write: a
    /// calendar made on a device in another language is still ours, and so is
    /// one made before a translation existed.
    private static var ownTitles: Set<String> {
        [String(localized: "Eventrail"), "Eventrail"]
    }

    /// An entry only this mirror would have written: one pointing back at the
    /// Eventernote page it was made from. The reader may have moved it, renamed
    /// it or hung their own alerts on it — none of that changes whose it is.
    private nonisolated static func isOurs(_ entry: EKEvent) -> Bool {
        entry.url?.host() == EventernoteClient.site.host()
    }

    /// Everything already in the app's calendar: the fixed sweep either side of
    /// today, widened to anything the library holds outside it.
    ///
    /// Wide on purpose — the entries worth finding are the ones whose events
    /// have *left* the library, and nothing in `events` can point at those. See
    /// ``sweepBack``.
    private func entries(in calendar: EKCalendar, covering events: [Event]) -> [EKEvent] {
        let now = Date.now
        let dates = events.map(\.sortDate)
        var start = min(dates.min() ?? now, now.addingTimeInterval(-Self.sweepBack))
        let end = max(dates.max() ?? now, now.addingTimeInterval(Self.sweepAhead))

        var found: [EKEvent] = []
        while start < end {
            let chunk = min(start.addingTimeInterval(Self.window), end)
            let predicate = store.predicateForEvents(withStart: start, end: chunk, calendars: [calendar])
            found.append(contentsOf: store.events(matching: predicate))
            start = chunk
        }
        return found
    }

    // MARK: - One entry

    /// Writes the event onto the calendar entry, and says whether anything
    /// actually changed — an unchanged entry is not saved, so a mirror that
    /// finds nothing to do touches the reader's calendar not at all.
    private func apply(_ event: Event, to entry: EKEvent, places: [Event.ID: VenuePlaces.Placing]) -> Bool {
        // Eventernote announces plenty of events months before it publishes a
        // time. Those land as all-day entries rather than at an invented hour.
        let isAllDay = event.startsAt == nil
        let start = event.startsAt ?? event.date
        let end = event.endsAt
            ?? event.startsAt?.addingTimeInterval(Self.assumedLength)
            ?? event.date

        var changed = false
        if entry.title != event.title {
            entry.title = event.title
            changed = true
        }
        // A place rather than a line of text: given the map item, Calendar
        // draws the venue on a map and can work out when to leave for it.
        let place = Self.place(for: event, found: places[event.id])
        if !isSamePlace(entry.structuredLocation, place) {
            entry.structuredLocation = place
            changed = true
        }
        if entry.isAllDay != isAllDay {
            entry.isAllDay = isAllDay
            changed = true
        }
        if entry.startDate != start {
            entry.startDate = start
            changed = true
        }
        if entry.endDate != end {
            entry.endDate = end
            changed = true
        }
        if entry.timeZone != event.timeZone {
            entry.timeZone = event.timeZone
            changed = true
        }
        // An alert when the doors open — see ``doorOffset(of:)``.
        let doors = Self.doorOffset(of: event)
        if doorOffset(of: entry) != doors {
            entry.alarms = doors.map { [EKAlarm(relativeOffset: $0)] }
            changed = true
        }
        // The URL is how the next mirror recognises this entry again, so it is
        // written whether or not anything else moved.
        if entry.url != event.sourceURL {
            entry.url = event.sourceURL
            changed = true
        }
        return changed
    }

    // MARK: - When to set off

    /// How far before the performance the doors open, as the offset an alert
    /// is hung on — negative, because it fires before the entry starts.
    ///
    /// Doors rather than the curtain because doors are the time the reader has
    /// to act on: a queue forms, goods sell out, and an alert that waits for
    /// the performance to start is an alert about something already missed.
    /// The Calendar app's own travel time would be the other half of this, but
    /// EventKit publishes no way to write it, so the alert is the whole answer
    /// rather than a second one beside it.
    ///
    /// Written for past events as much as upcoming ones, so an entry carries
    /// the door time whether the night is ahead or behind — a diary that
    /// records when the reader had to be at the hall reads the same either
    /// way, and an alert that appears on this year's entries but not last
    /// year's is a difference the reader would have to explain to themselves.
    /// The alert on a past entry is a note rather than a notification: its
    /// moment is gone, so there is nothing left for the calendar to deliver.
    ///
    /// Nil only where the site published one of the two times without the
    /// other — an event announced before its schedule was — or has them the
    /// wrong way round.
    private static func doorOffset(of event: Event) -> TimeInterval? {
        guard let doors = event.doorsOpen, let start = event.startsAt, doors < start else { return nil }
        return doors.timeIntervalSince(start)
    }

    /// The offset of the alert already on the entry, so an entry that is right
    /// is left alone and the diary stays quiet.
    ///
    /// One alarm and no absolute date, which is what this mirror writes.
    /// Anything else reads as nil, so an entry the reader has hung their own
    /// alerts on is corrected only when a door alert is owed — where none is,
    /// what they added is left where they put it.
    private func doorOffset(of entry: EKEvent) -> TimeInterval? {
        guard let alarms = entry.alarms, alarms.count == 1,
              let alarm = alarms.first, alarm.absoluteDate == nil else { return nil }
        return alarm.relativeOffset
    }

    // MARK: - Where the event is

    /// The entry's place.
    ///
    /// Built from the map item wherever Maps knew the hall, because that is
    /// what the Calendar app wants: an entry made from a map item shows the
    /// same map beside it as one the reader picked out of Calendar's own
    /// location field, and can be given a travel time. Where Maps had nothing,
    /// the hall goes on as text and the next mirror tries again for it. Nil
    /// only where there is no venue at all — Eventernote announces plenty of
    /// events before it has booked a hall.
    ///
    /// An entry reads as the hall's name alone. The coordinate is what says
    /// where the place is, and an address in the title only repeats the map
    /// back at the reader in a line the Calendar app has to truncate — and
    /// where Maps has not placed the hall yet, a name is still the thing
    /// Calendar can resolve for itself, which a street address elided at the
    /// third word is not. The address is the title only where the site has
    /// named no hall at all and it is the one thing left to go on.
    ///
    /// The name is always Eventernote's, never the one Maps came back with. A
    /// hall the site calls Kアリーナ横浜 is that in the reader's calendar even
    /// where Maps files it under something shorter or in another language: the
    /// map item is being asked where the place is, not what to call it.
    private static func place(for event: Event, found: VenuePlaces.Placing?) -> EKStructuredLocation? {
        guard let title = event.venue.isEmpty ? event.locationTitle : event.venue else { return nil }
        guard let found else { return EKStructuredLocation(title: title) }
        let place = EKStructuredLocation(mapItem: found.item)
        place.title = title
        // How sure the coordinate is, which EKStructuredLocation keeps a field
        // for. A hall placed by its address rather than by its own listing
        // sits at the middle of its block, and saying so is the difference
        // between a location and a claim — see ``VenuePlaces/Placing``.
        place.radius = found.uncertainty
        // Built from the map item, so the entry carries whatever else Calendar
        // wants of a place — but the coordinate is what makes it a point on the
        // map rather than a line of text, and an item rebuilt from the kept
        // answer has no placemark for `init(mapItem:)` to read it out of. So it
        // is set here rather than assumed.
        if place.geoLocation == nil {
            place.geoLocation = found.item.location
        }
        return place
    }

    /// Two places are the same when they read the same and sit in the same
    /// spot. Worth checking, because an entry written before Maps had been
    /// asked should be corrected once, and then left alone.
    private func isSamePlace(_ lhs: EKStructuredLocation?, _ rhs: EKStructuredLocation?) -> Bool {
        guard lhs?.title == rhs?.title else { return false }
        switch (lhs?.geoLocation?.coordinate, rhs?.geoLocation?.coordinate) {
        case (nil, nil): return true
        case let (left?, right?): return left.latitude == right.latitude && left.longitude == right.longitude
        default: return false
        }
    }
}

enum CalendarSyncError: LocalizedError {
    case noCalendarSource

    var errorDescription: String? {
        switch self {
        case .noCalendarSource:
            String(localized: "This device has no calendar account to add Eventrail's calendar to")
        }
    }
}
