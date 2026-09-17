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
    private static let log = Logger(subsystem: "com.shawnhuang.Eventrail", category: "calendar")

    /// The calendar Eventrail made, remembered per device: a calendar
    /// identifier belongs to this device's calendar database and means nothing
    /// on another one, so it is deliberately not part of the synced archive.
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

    // MARK: - Mirroring

    /// Brings the calendar into line with `events`, adding what is missing,
    /// correcting what moved, and deleting what has left the library.
    ///
    /// Matching is by the Eventernote page URL rather than by title: a title
    /// can be re-published, and an entry the reader dragged elsewhere is still
    /// the same event.
    func mirror(_ events: [Event]) async -> Outcome {
        guard await requestAccess() else { return .denied }
        let places = await VenuePlaces.shared.mapItems(for: venuesToLookUp(in: events))
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
            let located = events.filter { $0.venueQuery.flatMap { places[$0] } != nil }.count
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
        if let id = savedCalendarID, let existing = store.calendar(withIdentifier: id) {
            return existing
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = String(localized: "Eventrail")
        calendar.cgColor = UIColor(Color.brandTint).cgColor
        guard let source = preferredSource() else {
            throw CalendarSyncError.noCalendarSource
        }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        savedCalendarID = calendar.calendarIdentifier
        return calendar
    }

    /// Wherever the reader's own new events go, so Eventrail's calendar lands
    /// beside them and follows them to their other devices.
    private func preferredSource() -> EKSource? {
        store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .calDAV && $0.title == "iCloud" }
            ?? store.sources.first { $0.sourceType == .local }
            ?? store.sources.first
    }

    /// Everything already in the app's calendar across the span the library
    /// covers, widened around today so entries for events that have since been
    /// dropped are still found and removed.
    private func entries(in calendar: EKCalendar, covering events: [Event]) -> [EKEvent] {
        let now = Date.now
        let dates = events.map(\.sortDate)
        var start = min(dates.min() ?? now, now.addingTimeInterval(-Self.window))
        let end = max(dates.max() ?? now, now.addingTimeInterval(Self.window))

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
    private func apply(_ event: Event, to entry: EKEvent, places: [VenuePlaces.Venue: MKMapItem]) -> Bool {
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
        let place = Self.place(for: event, found: event.venueQuery.flatMap { places[$0] })
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
        // The URL is how the next mirror recognises this entry again, so it is
        // written whether or not anything else moved.
        if entry.url != event.sourceURL {
            entry.url = event.sourceURL
            changed = true
        }
        return changed
    }

    // MARK: - Where the event is

    /// The entry's place.
    ///
    /// Built from the map item wherever Maps knew the hall, because that is
    /// what the Calendar app wants: an entry made from a map item shows the
    /// same map beside it as one the reader picked out of Calendar's own
    /// location field, and can be given a travel time. Where Maps had nothing,
    /// the published name and address still go on as text, which is no worse
    /// than what was written before. Nil only where there is no venue at all —
    /// Eventernote announces plenty of events before it has booked a hall.
    private static func place(for event: Event, found: MKMapItem?) -> EKStructuredLocation? {
        if let found { return EKStructuredLocation(mapItem: found) }
        guard let title = event.locationTitle else { return nil }
        return EKStructuredLocation(title: title)
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

    /// Every venue in the library, in the order they are worth asking about.
    ///
    /// The whole library, past included: a calendar is a diary as well as a
    /// plan, and a night the reader was at should show where they were on the
    /// map just as much as one they are going to.
    ///
    /// Order is what matters, because one mirror only has room for so many
    /// searches. Upcoming events come first, soonest first, since those are the
    /// ones about to be needed for directions; the past follows, most recent
    /// first, and the rest is picked up by later mirrors.
    private func venuesToLookUp(in events: [Event]) -> [VenuePlaces.Venue] {
        let upcoming = events.filter(\.isUpcoming).sorted { $0.sortDate < $1.sortDate }
        let past = events.filter { !$0.isUpcoming }.sorted { $0.sortDate > $1.sortDate }

        var seen: Set<VenuePlaces.Venue> = []
        return (upcoming + past)
            .compactMap(\.venueQuery)
            .filter { seen.insert($0).inserted }
    }
}

nonisolated extension Event {
    /// What Maps is asked about this event's hall, or nil where the site has
    /// not named one yet.
    var venueQuery: VenuePlaces.Venue? {
        let address = (venueAddress?.isEmpty ?? true) ? nil : venueAddress
        guard !venue.isEmpty || address != nil else { return nil }
        return VenuePlaces.Venue(name: venue, address: address)
    }

    /// What the calendar entry calls its place when Maps could not find one.
    ///
    /// The address goes first, as Japanese addresses are written and as
    /// Eventernote itself prints them, with the hall's name after it — unless
    /// the published address already ends in that name, which it often does.
    var locationTitle: String? {
        guard let address = venueAddress, !address.isEmpty else {
            return venue.isEmpty ? nil : venue
        }
        guard !venue.isEmpty, !address.contains(venue) else { return address }
        return "\(address) \(venue)"
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
