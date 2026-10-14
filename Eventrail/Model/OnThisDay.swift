import Foundation

/// The events the reader went to on today's date in earlier years — what the
/// Me tab's On This Day card samples and ``OnThisDayView`` lists whole, as
/// `Eventrail.dc.html`'s On This Day board draws them.
///
/// Read off the library alone, as the Passport is, and nothing is kept for
/// it: an event counts where its written day — the day its hall says it fell
/// on, read on the hall's clock as ``Event/localDay`` reads it, not the day
/// the reader's clock puts the instant on — has today's month and day and an
/// earlier year, and the reader went
/// (``EventStore/hasAttended(_:)``: a ticket held, which in an earlier year
/// is a ticket held for a day that is over).
///
/// Takes `tracking` as a closure rather than the store, as ``LotteryList``
/// does, so it stays `nonisolated` and testable with no store behind it.
nonisolated struct OnThisDay {
    /// One event gone to on this day.
    struct Memory: Identifiable {
        let event: Event
        /// How many years ago it was — one at the least.
        let yearsAgo: Int

        var id: Event.ID { event.id }
    }

    /// Today, on the reader's calendar.
    let day: CalendarDay
    /// The most recent year first, and two on one day in the order they ran.
    let memories: [Memory]

    init(events: some Sequence<Event>, on now: Date = .now, tracking: (Event) -> Tracking) {
        // Counted on the Gregorian calendar whatever the reader's is set to:
        // on the Japanese one a year is an era's, and Heisei 31 is not before
        // Reiwa 8. The reader's zone says which day it is here; each hall's
        // says which day its event fell on.
        let today = CalendarDay(now)
        day = today
        var halls: [TimeZone: Calendar] = [:]
        memories = events
            .compactMap { event -> Memory? in
                let hall = halls[event.timeZone] ?? .gregorian(in: event.timeZone)
                halls[event.timeZone] = hall
                let written = CalendarDay(event.date, in: hall)
                // The day first: it rules out nearly the whole library without
                // reading anybody's record.
                guard written.year < today.year, Self.falls(written, on: today),
                      tracking(event).hasTicket
                else { return nil }
                return Memory(event: event, yearsAgo: today.year - written.year)
            }
            .sorted { ($0.yearsAgo, $0.event.sortDate) < ($1.yearsAgo, $1.event.sortDate) }
    }

    /// How many different years the memories come from.
    var years: Int { Set(memories.map(\.yearsAgo)).count }

    /// The start of today, to be printed.
    var date: Date { day.date() }

    /// Whether a day in an earlier year is this one's: the same month and the
    /// same day — and the 29th of February on the 28th in a year without one,
    /// so an event on a leap day comes round every year rather than every
    /// fourth.
    static func falls(_ written: CalendarDay, on today: CalendarDay) -> Bool {
        if written.month == today.month, written.day == today.day { return true }
        return written.month == 2 && written.day == 29
            && today.month == 2 && today.day == 28 && !isLeapYear(today.year)
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
    }
}
