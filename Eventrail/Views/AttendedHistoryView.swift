import SwiftData
import SwiftUI

/// The way onto the reader's own history with a performer or a hall — from
/// the Passport's rankings, in the slice the Passport was showing, and from
/// the "You attended" count on the performer's or the hall's page.
nonisolated struct AttendedLink: Hashable {
    let subject: ListingSubject
    /// The Passport's slice the history was opened from: a year there is a
    /// year here, for the reason ``PassportRanking`` carries one.
    var scope: PassportScope = .allTime
    /// Whether the page offers the performer's or the hall's own page — not
    /// where it was opened from that page, which is underneath it already.
    var offersPage = true
}

/// What the reader went to with a performer or at a hall: how many, the first
/// and the latest, and each of them, latest first.
///
/// Read off the library alone, as the Passport is — attended is a ticket held
/// once the day is over (``EventStore/hasAttended(_:)``), and a performer or
/// a hall is matched by the name printed on the event
/// (``ListingSubject/includes(_:)``), the names the Passport ranks by — so
/// nothing here asks Eventernote anything. The page Eventernote keeps for
/// them is a row away.
struct AttendedHistoryView: View {
    @Environment(EventStore.self) private var store
    /// Declared to be drawn again as the day turns — see ``EnvironmentValues/today``.
    @Environment(\.today) private var today
    /// Which clock the days are printed on — see ``TimeDisplay``.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue
    @Query(LibraryEntry.library) private var kept: [LibraryEntry]

    let link: AttendedLink

    @State private var openEvent: Event?

    private var events: [Event] {
        store.events(of: kept, where: \.inLibrary).past
            .filter { link.scope.contains($0) && link.subject.includes($0) && store.hasAttended($0) }
            .sorted { $0.sortDate > $1.sortDate }
    }

    var body: some View {
        // Worked out once a drawing, as My Events works its own out.
        let events = self.events
        let subtitle = Text("\(link.scope.chipLabel) · ^[\(events.count) event](inflect: true) you went to")
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                tiles(events)
                if link.offersPage { pageLink }
                if events.isEmpty {
                    // Reachable by taking the ticket off the last of them, or
                    // the event out of the library, from its sheet.
                    Text("No events you went to.")
                        .scalingFont(size: 12)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .panel()
                } else {
                    ForEach(byYear(events), id: \.year) { year in
                        VStack(alignment: .leading, spacing: 8) {
                            GroupHeader(label: Text(verbatim: String(year.year)), count: year.events.count)
                                .padding(.leading, 4)
                            ForEach(year.events) { event in
                                LibraryRow(event: event) { openEvent = event }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .washBackground()
        // Inline, as the performer's and the hall's own pages are: a name is
        // as long as the site printed it.
        .navigationTitle(Text(verbatim: link.subject.name))
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(subtitle)
        .eventPane($openEvent)
    }

    // MARK: - The counts

    /// How many, over how many years, the first and the latest — each of the
    /// two a year over the day, as the Passport names a slice by its year.
    /// Every tile two lines high, so the three stand level.
    private func tiles(_ events: [Event]) -> some View {
        let years = Set(events.map(PassportStats.year(of:))).count
        return HStack(spacing: 11) {
            StatTile(tint: .trackAttended, value: events.count.formatted(),
                     sub: years > 0 ? Text("across ^[\(years) year](inflect: true)") : nil,
                     label: "Attended")
            dayTile(events.last, label: "First Time", tint: .brandTint)
            dayTile(events.first, label: "Most Recent", tint: .trackTicket)
        }
    }

    private func dayTile(_ event: Event?, label: LocalizedStringKey, tint: Color) -> some View {
        StatTile(tint: tint,
                 value: event.map { String(PassportStats.year(of: $0)) } ?? "—",
                 sub: event.map { Text(verbatim: monthAndDay(of: $0)) },
                 label: label)
    }

    /// The month and day an event was on, where it was held — a part of a
    /// date printed beside a Gregorian year, so named on that calendar.
    private func monthAndDay(of event: Event) -> String {
        let zone = event.shown(on: timeDisplay).timeZone
        return event.date.formatted(.gregorian(in: zone).month(.abbreviated).day())
    }

    // MARK: - The page on Eventernote

    private var pageLink: some View {
        Group {
            switch link.subject {
            case .performer(let name):
                NavigationLink(value: PerformerLink.billed(name: name)) { pageRow(Text("Open Performer")) }
            case .venue(let name):
                NavigationLink(value: VenueLink.named(name)) { pageRow(Text("Open Venue")) }
            }
        }
        .buttonStyle(.plain)
        .panel()
    }

    private func pageRow(_ label: Text) -> some View {
        HStack(spacing: 12) {
            label
                .scalingFont(size: 14, weight: .medium)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .scalingFont(size: 11, weight: .semibold)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(.rect)
    }

    // MARK: - The years

    private struct Year {
        let year: Int
        let events: [Event]
    }

    /// The events a year at a time, latest first — the year each was held in,
    /// as the Passport files it.
    private func byYear(_ events: [Event]) -> [Year] {
        var order: [Int] = []
        var buckets: [Int: [Event]] = [:]
        for event in events {
            let year = PassportStats.year(of: event)
            if buckets[year] == nil { order.append(year) }
            buckets[year, default: []].append(event)
        }
        return order.map { Year(year: $0, events: buckets[$0] ?? []) }
    }
}

#Preview {
    NavigationStack {
        AttendedHistoryView(link: AttendedLink(subject: .performer(PreviewData.events[0].performers.first?.name ?? "")))
    }
    .library(EventStore.preview)
}
