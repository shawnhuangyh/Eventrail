import Charts
import MapKit
import SwiftData
import SwiftUI

/// The way onto the Passport from the Me tab.
///
/// A case of its own rather than a third ``MeList``: that enum answers "which
/// of the two cards was opened in full", and the Passport is not one of the
/// lists those cards sample.
nonisolated enum PassportLink: Hashable {
    case passport
}

/// Which ranked list the reader asked to see the whole of.
///
/// Carries the scope with it so the full list is the same slice the card
/// sampled — a See All that quietly reverted to All Time would be answering a
/// different question from the one the reader was looking at.
nonisolated enum PassportRanking: Hashable, Identifiable {
    case performers(PassportScope)
    case venues(PassportScope)

    var id: Self { self }

    var isPerformers: Bool {
        if case .performers = self { return true }
        return false
    }

    var scope: PassportScope {
        switch self {
        case .performers(let scope), .venues(let scope): scope
        }
    }

    var title: LocalizedStringKey { isPerformers ? "Top Performers" : "Top Venues" }

    func rows(of stats: PassportStats) -> [PassportStats.Ranking] {
        isPerformers ? stats.topPerformers : stats.topVenues
    }
}

/// Which end of the library the reader asked to see the whole of.
///
/// A sheet rather than a pushed screen, and rather than the run of rows the
/// card used to unfold in place: five events is a glance, not a destination,
/// and growing the card by four rows pushed everything under it off screen
/// while the reader was reading it.
nonisolated enum PassportExtreme: Identifiable, Hashable {
    case shortest
    case longest

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .shortest: "Shortest Event"
        case .longest: "Longest Event"
        }
    }

    func spans(of stats: PassportStats) -> [PassportStats.Span] {
        switch self {
        case .shortest: stats.shortest
        case .longest: stats.longest
        }
    }
}

/// The reader's own record of where they have been: a map of the country with
/// every hall they have stood in, and what the library adds up to around it.
///
/// Everything here is read off the library's own past — what was attended
/// in it (``EventStore/hasAttended(_:)``), and the lotteries over all of it —
/// and nothing on this screen asks Eventernote anything. What the
/// reader wrote themselves — the lotteries and the prices — says what it was
/// counted out of rather than presenting a part-filled column as a total.
///
/// One scrolling page with the year filter kept at the top of it, because the
/// filter governs every card below: a chip that scrolled away would leave the
/// reader looking at 2019's numbers with nothing on screen saying so.
struct EventPassportView: View {
    @Environment(EventStore.self) private var store

    @State private var scope: PassportScope = .allTime
    /// Where each hall stands, as far as anything has looked up.
    ///
    /// Held rather than read in `body`: the lookup walks every kept answer, and
    /// a redraw per scroll frame would walk it per frame.
    @State private var placings: [Event.ID: VenuePlaces.Placing] = [:]
    /// Which end of the library has its whole list open, if either.
    @State private var openExtreme: PassportExtreme?
    /// Which ranked list has its whole list open, if either.
    @State private var openRanking: PassportRanking?
    /// Whether every recorded event is open, rather than the top five.
    /// The event whose own sheet is open, if the reader tapped one.
    @State private var openEvent: Event?
    /// What the spending card adds up in, unless the reader picked another on
    /// the card — see ``Currencies/storageKey``.
    @AppStorage(Currencies.storageKey) private var defaultCurrency = Currencies.yen
    /// What ``TicketReviewView`` is going through, while it is open.
    @State private var reviewing: TicketReviewList?
    /// The currency picked on the spending card; nil follows Settings.
    /// Deliberately not remembered between visits, for the reason
    /// ``PassportScope`` is not.
    @State private var spendingCurrency: String?

    /// How much of each ranked list a card shows before sending the rest to a
    /// screen of its own — the same five the Me tab's cards show, for the same
    /// reason.
    private static let cardLimit = 5

    @Query(LibraryEntry.library) private var kept: [LibraryEntry]

    /// Every kept event whose day is over, ticket or not — what the lottery
    /// card is counted over.
    private var past: [Event] { store.events(of: kept, where: \.inLibrary).past }

    /// What the reader went to: the past they held a ticket for.
    private var attended: [Event] { past.filter(store.hasAttended) }

    private var stats: PassportStats {
        PassportStats(events: PassportStats.events(attended, in: scope),
                      lotteriesOf: PassportStats.events(past, in: scope),
                      currency: currency, rates: ExchangeRates.shared.rates) {
            store.tracking(for: $0)
        }
    }

    private var currency: String { spendingCurrency ?? defaultCurrency }

    /// Whether any ticket the reader went to was paid in a currency other
    /// than the one the card adds up in — the only time the rates are asked
    /// for. Over the whole library rather than the year, so a year chip does
    /// not set off a read.
    private var needsRates: Bool {
        attended.contains { event in
            store.tracking(for: event).price.map { $0.currency != currency } ?? false
        }
    }

    var body: some View {
        ScrollView {
            let stats = self.stats
            VStack(spacing: 14) {
                if attended.isEmpty {
                    emptyState
                } else {
                    summaryCard(stats)
                    PassportEventsCard(stats: stats)
                    timeCard(stats)
                }
                // Under the empty state too: lotteries tried for and lost are
                // the reader's record before any ticket is.
                if !stats.topLotteries.isEmpty {
                    PassportLotteryCard(stats: stats, limit: Self.cardLimit) { openEvent = $0 }
                }
                if !stats.tickets.isEmpty || stats.unconvertedTickets > 0 {
                    PassportSpendingCard(
                        stats: stats,
                        currency: Binding(get: { currency }, set: { spendingCurrency = $0 }),
                        defaultCurrency: defaultCurrency
                    ) { openEvent = $0 }
                }
                if !stats.topPerformers.isEmpty { performersCard(stats) }
                if !stats.topVenues.isEmpty { venuesCard(stats) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .washBackground()
        .navigationTitle("Event Passport")
        // Inline rather than large: iOS 26 draws a large title in the scrolling
        // content, where the year bar inset lands on top of it.
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) { yearBar }
        .task(id: store.revision) { readPlacings() }
        .task(id: needsRates) {
            if needsRates { await ExchangeRates.shared.refreshIfStale() }
        }
        // A year is only ever offered while the reader has something in it, so
        // a removal here or a merge from another device can take the chosen one
        // away underneath the screen — leaving nine cards filtered to a year
        // with no chip lit to say which, or none at all once the bar drops to a
        // single year and hides itself. Either way the filter has outlived the
        // control that sets it, and the screen falls back to what it opens on.
        .onChange(of: years) { _, available in
            guard case .year(let year) = scope else { return }
            if available.count <= 1 || !available.contains(year) {
                withAnimation(.snappy) { scope = .allTime }
            }
        }
        .navigationDestination(for: VenueLink.self) { VenueView(link: $0) }
        // Both See Alls open a drawer rather than pushing a screen: every one
        // of these lists is the card it sits under, read to the end, and the
        // reader is meant to put it back down where they were.
        //
        // The spans are read off the stats again rather than carried in the
        // enum, so the drawer is always the slice the card was showing.
        .sheet(item: $openExtreme) { extreme in
            PassportExtremesSheet(extreme: extreme, spans: extreme.spans(of: stats))
        }
        .sheet(item: $openRanking) { PassportRankingSheet(ranking: $0) }
        .sheet(item: $reviewing) { TicketReviewView(events: $0.events) }
        // An event named on this screen opens the same sheet every list in
        // the app ends in.
        .eventSheet($openEvent)
    }

    // MARK: - The year the screen is read over

    /// The years the reader has something in, newest first, behind All Time.
    private var years: [Int] { PassportStats.years(of: attended) }

    /// Kept above the scroll rather than in it, because it governs every card
    /// underneath: the reader has to be able to see which year they are reading
    /// without scrolling back for it.
    ///
    /// Hidden entirely for a library that spans one year — a filter offering
    /// All Time and 2026 over the same events is a control with nothing to do.
    @ViewBuilder
    private var yearBar: some View {
        if years.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip(for: .allTime)
                    ForEach(years, id: \.self) { chip(for: .year($0)) }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            // Given an explicit height rather than left to find one: a
            // horizontal `ScrollView` accepts every point of height it is
            // offered, and inset against the top of the screen it is offered
            // the whole screen — which swallowed the navigation bar whole.
            .frame(height: 36)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    /// The chosen year is filled rather than merely tinted.
    ///
    /// Every other chip in the app tints its label and leaves the glass alone,
    /// because those filters narrow a list the reader can still see the whole
    /// of. This one silently changes nine cards at once, so it is the one
    /// filter worth reading from across the room.
    private func chip(for option: PassportScope) -> some View {
        let isOn = scope == option
        return Button {
            withAnimation(.snappy) { scope = option }
        } label: {
            option.chipLabel
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isOn ? Color.white : .secondary)
                .lineLimit(1)
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background {
                    if isOn { Capsule().fill(Color.brandTint) }
                }
        }
        .buttonStyle(.plain)
        .glassCapsule(interactive: true)
    }

    // MARK: - What it adds up to, and where

    /// What the slice comes to: the country across the top, and under it the
    /// counts that country is made of.
    ///
    /// One panel rather than three, and the map first, the way a passport
    /// opens: the picture is the thing, and the figures are what is stamped
    /// under it. The map runs to the panel's own edges rather than sitting
    /// inset inside it, so nothing is drawn around it twice.
    private func summaryCard(_ stats: PassportStats) -> some View {
        let pins = pins(stats)
        return VStack(alignment: .leading, spacing: 0) {
            map(pins)
                .aspectRatio(1 / 0.98, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    // Both in the one corner, on the map rather than under it:
                    // they are readings of the map, and the figures below are
                    // readings of the library. The corner is the right-hand
                    // one because the left is Apple's — the Maps logo sits
                    // there and is not ours to cover.
                    //
                    // The key to the dots first, then what they add up to:
                    // how to read the map, and then its reading.
                    VStack(alignment: .trailing, spacing: 6) {
                        // Only once the dots differ. "1 → 1" is a key to a
                        // scale that has one value on it.
                        if let most = pins.map(\.count).max(), most > 1 {
                            legend(most: most)
                        }
                        if stats.prefectures > 0 {
                            prefectures(stats)
                        }
                    }
                    .padding(12)
                }

            figures(stats)
                .padding(16)
        }
        // Clipped as well as glassed: the glass is only the background, and
        // the map would otherwise square off the panel's top corners.
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
        .glassPanel(cornerRadius: 28)
    }

    private func prefectures(_ stats: PassportStats) -> some View {
        Text("\(stats.prefectures) of 47 prefectures")
            .font(.system(size: 10.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .glassCapsule()
    }

    /// The country, with a dot on every hall anything has been able to place.
    ///
    /// **Eventernote publishes no coordinate**, only an address, so a hall is
    /// on this map because ``VenuePlaces`` has already been asked about it —
    /// by an event's sheet, by the hall's own page, or by the placement run
    /// behind an import. A hall nothing has asked about yet is not drawn in
    /// the middle of the sea; it is simply missing from the map, and a pull on
    /// the page asks Maps about the ones nothing has an answer for.
    ///
    /// Fixed rather than scrollable, for the reason ``VenueMap`` gives: this
    /// sits inside a page that scrolls, and a map that swallowed the drag would
    /// trap it.
    private func map(_ pins: [Pin]) -> some View {
        Map(initialPosition: .region(Self.japan), interactionModes: []) {
            ForEach(pins) { pin in
                Annotation(pin.venue, coordinate: pin.coordinate) { dot(pin) }
                    .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .accessibilityLabel("Map of the venues you have been to")
    }

    /// Hokkaidō to Okinawa. The whole country or none of it: a frame drawn
    /// around wherever the reader happens to have been would redraw itself
    /// every time they went somewhere new, and a Passport that only showed
    /// Kantō until you left it would never show you that you had not.
    private static let japan = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.2, longitude: 137.6),
        latitudinalMeters: 2_500_000,
        longitudinalMeters: 2_500_000
    )

    /// A hall drawn at its size: the more events the reader has spent there,
    /// the larger and the stronger the dot.
    ///
    /// One dot per hall rather than one per event — a hundred events at the
    /// Budōkan drawn as a hundred dots is one dot, and says a hundred times
    /// less than this does.
    private func dot(_ pin: Pin) -> some View {
        let weight = pin.weight
        let radius = 3.5 + weight * 6.5
        return ZStack {
            Circle()
                .fill(Color.brandTint.opacity(0.13))
                .frame(width: radius * 5.2, height: radius * 5.2)
            Circle()
                .fill(Color.brandTint.opacity(weight > 0.6 ? 1 : weight > 0.3 ? 0.78 : 0.5))
                .overlay { Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1) }
                .frame(width: radius * 2, height: radius * 2)
        }
    }

    /// What the sizes mean, since the dots are the only thing on the map that
    /// carries a number.
    private func legend(most: Int) -> some View {
        HStack(spacing: 6) {
            ForEach([0.0, 0.5, 1.0], id: \.self) { weight in
                let radius = 3.5 + weight * 6.5
                Circle()
                    .fill(Color.brandTint.opacity(weight > 0.6 ? 1 : weight > 0.3 ? 0.78 : 0.5))
                    .frame(width: radius, height: radius)
            }
            Text(verbatim: "1 → \(most.formatted())")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .glassCapsule()
    }

    /// What the slice adds up to, set out the way a passport sets out its
    /// holder: the two that say how much across the top, the three that say
    /// how many under them.
    ///
    /// Bare rather than five tiles of glass — a panel of glass holding tiles
    /// of glass is a box of boxes — and named over the figure rather than
    /// under it, which is the other way round from the row of four in the card
    /// below. Those four are one number said four ways, so the figure leads;
    /// these five are five different facts, so the name does.
    private func figures(_ stats: PassportStats) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 14) {
                figure("Events", size: 30) {
                    Text(stats.totalEvents.formatted())
                }
                figure("Total Time", size: 30) {
                    DurationLabel(seconds: stats.totalDuration, size: 30)
                }
            }
            HStack(alignment: .bottom, spacing: 14) {
                figure("Venues", size: 22) {
                    Text(stats.venues.formatted())
                }
                figure("Performers", size: 22) {
                    Text(stats.performers.formatted())
                }
                figure("Lottery Entries", size: 22) {
                    Text(stats.lotteryEntries.formatted())
                }
            }
        }
    }

    /// One figure and what it counts.
    ///
    /// The name is drawn exactly as the four names under the total in the card
    /// below are, because it is the same kind of thing: two rows of small
    /// labelled figures a panel apart should not be set two different ways.
    private func figure(
        _ label: LocalizedStringKey, size: CGFloat, @ViewBuilder value: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            value()
                .font(.system(size: size, weight: .bold))
                .kerning(-0.7)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Time at events

    /// The total, the three ways of reading it the design asks for, and the two
    /// ends of the library under them.
    ///
    /// Every number here is over ``PassportStats/timedEvents`` rather than over
    /// the whole slice, because Eventernote announces most dates long before it
    /// publishes a finish time.
    ///
    /// The shortest and longest events sit in this panel rather than their own:
    /// they are the same measurement read at its extremes — a forty-minute
    /// in-store and a six-hour summer festival — and they are only worth
    /// printing once there are two timed events for them to be the ends of.
    private func timeCard(_ stats: PassportStats) -> some View {
        let minutes = Int(stats.totalDuration / 60)
        return VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Time at Events")

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                unit(minutes / 60, suffix: "h")
                unit(minutes % 60, suffix: "m").padding(.leading, 8)
            }
            .accessibilityElement(children: .combine)

            let hours = stats.totalDuration / 3600
            HStack(spacing: 0) {
                breakdown(hours / 24, format: .number.precision(.fractionLength(1)),
                          label: "Days", isFirst: true)
                breakdown(hours / 720, format: .number.precision(.fractionLength(2)),
                          label: "Months", isFirst: false)
                breakdown(hours / 8760, format: .number.precision(.fractionLength(3)),
                          label: "Years", isFirst: false)
                average(stats)
            }

            if stats.timedEvents >= 2 {
                extremes(.shortest, stats.shortest)
                extremes(.longest, stats.longest)
            }
        }
        .padding(16)
        .glassPanel(cornerRadius: 28)
    }

    private func unit(_ value: Int, suffix: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value.formatted())
                .font(.system(size: 40, weight: .bold))
                .kerning(-1.4)
                .monospacedDigit()
            Text(verbatim: suffix)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.tertiary)
        }
    }

    private func breakdown(
        _ value: Double, format: FloatingPointFormatStyle<Double>,
        label: LocalizedStringKey, isFirst: Bool
    ) -> some View {
        cell(Text(value.formatted(format)), label: label, isFirst: isFirst)
    }

    /// How long an average event runs — over the events that can say, so the
    /// average is of the same events the total is.
    private func average(_ stats: PassportStats) -> some View {
        let seconds = stats.timedEvents > 0 ? stats.totalDuration / Double(stats.timedEvents) : 0
        return cell(DurationLabel(seconds: seconds), label: "Avg. Time", isFirst: false)
    }

    /// An equal share of the row: the time card's four readings are one
    /// figure said four ways at much the same width, and columns line them up.
    private func cell(_ value: some View, label: LocalizedStringKey, isFirst: Bool) -> some View {
        passportReading(value, label: label)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, isFirst ? 0 : 14)
    }

    // MARK: - The briefest event and the longest

    /// One end of the library, ruled off from whatever sits above it — the
    /// breakdown for the shortest, the shortest for the longest.
    ///
    /// The event itself, and a See All to the other four behind it. One row
    /// rather than five, because these two sit inside the time card now: the
    /// card is about the total, and ten rows of extremes under it would be the
    /// larger half of a panel that is not about them.
    @ViewBuilder
    private func extremes(
        _ extreme: PassportExtreme, _ spans: [PassportStats.Span]
    ) -> some View {
        if let first = spans.first {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(extreme.title)
                        .font(.system(size: 15.5, weight: .bold))
                    Spacer(minLength: 8)
                    if spans.count > 1 {
                        Button { openExtreme = extreme } label: { SeeAllLabel() }
                            .buttonStyle(.plain)
                    }
                }
                // The row itself is the target, with no chevron on it, the
                // way a ranked row is: the whole line is the event.
                Button { openEvent = first.event } label: { PassportSpanRow(span: first) }
                    .buttonStyle(.plain)
            }
            .padding(.top, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Divider() }
        }
    }

    // MARK: - Who, and where

    private func performersCard(_ stats: PassportStats) -> some View {
        rankCard(title: "Top Performers", rows: stats.topPerformers, total: stats.totalEvents,
                 tint: .trackAttended, showsShare: true,
                 seeAll: stats.topPerformers.count > Self.cardLimit
                     ? .performers(scope) : nil) { PerformerLink.billed(name: $0.name) }
    }

    private func venuesCard(_ stats: PassportStats) -> some View {
        rankCard(title: "Top Venues", rows: stats.topVenues, total: stats.totalEvents,
                 tint: .brandTint, showsShare: false,
                 seeAll: stats.topVenues.count > Self.cardLimit
                     ? .venues(scope) : nil) { VenueLink.named($0.name) }
    }

    /// The two ranked cards are one card: the same rows, the same bar, the same
    /// way into the whole list. Only the tint and what a row pushes differ, and
    /// writing them twice is how the two drift apart.
    private func rankCard<Value: Hashable>(
        title: LocalizedStringKey, rows: [PassportStats.Ranking], total: Int,
        tint: Color, showsShare: Bool, seeAll: PassportRanking?,
        destination: @escaping (PassportStats.Ranking) -> Value
    ) -> some View {
        let shown = Array(rows.prefix(Self.cardLimit))
        let most = max(1, shown.first?.count ?? 1)
        return VStack(alignment: .leading, spacing: 13) {
            CardHeader(title: title) {
                if let seeAll {
                    Button { openRanking = seeAll } label: { SeeAllLabel() }
                        .buttonStyle(.plain)
                }
            }
            ForEach(shown) { row in
                NavigationLink(value: destination(row)) {
                    PassportRankRow(row: row, most: most, total: total,
                                    tint: tint, showsShare: showsShare)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .glassPanel(cornerRadius: 28)
    }

    // MARK: - The empty screen

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Nothing to stamp yet")
                .font(.system(size: 17, weight: .bold))
            Text("Record your ticket for each event you go to — a lottery won or a seat got — in its Ticket Details. Once its date has passed it is counted here.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // Every past event with none, not only what has come since the
            // last pass: an empty Passport is the reader asking where it went.
            let unticketed = past.filter { !store.tracking(for: $0).hasTicket }
            if !unticketed.isEmpty {
                Button("Record Tickets") {
                    reviewing = TicketReviewList(events: unticketed)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.brandTint)
                .padding(.top, 6)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .glassPanel(cornerRadius: 28)
        .padding(.top, 30)
    }

    // MARK: - Placing the halls

    /// A hall on the map, and how much of the reader's past it holds.
    private struct Pin: Identifiable {
        let venue: String
        let count: Int
        let coordinate: CLLocationCoordinate2D
        /// Where this hall stands between the least visited and the most, which
        /// is what sizes and shades the dot.
        let weight: Double

        var id: String { venue }
    }

    private func pins(_ stats: PassportStats) -> [Pin] {
        var coordinates: [String: CLLocationCoordinate2D] = [:]
        for event in stats.events where coordinates[event.venue] == nil {
            if let placing = placings[event.id] {
                coordinates[event.venue] = placing.item.location.coordinate
            }
        }
        let most = Double(max(1, stats.topVenues.first?.count ?? 1))
        return stats.topVenues.compactMap { ranking in
            coordinates[ranking.name].map {
                Pin(venue: ranking.name, count: ranking.count, coordinate: $0,
                    weight: Double(ranking.count) / most)
            }
        }
    }

    /// What has already been looked up, and nothing more.
    ///
    /// Asks the network nothing: this is the answers an event's sheet, a hall's
    /// page and the placement run behind an import have written down between
    /// them. A hall none of those has reached is simply absent until one of
    /// them does — or until Settings' Refresh Venue Locations, the one place
    /// that asks about every hall. The Passport itself refreshes nothing: it
    /// is the reader's record read back, not a view of the site.
    private func readPlacings() {
        placings = VenuePlaces.shared.mapItems(for: attended)
    }

}

/// One of the readings under a card's total, at its own width. Ruled off from
/// nothing: four figures under one number are four ways of saying it, and a
/// rule between them reads as a boundary that isn't there.
///
/// How the readings share a row is the card's to say — see
/// ``EventPassportView`` `cell` and ``PassportSpendingCard``.
private func passportReading(_ value: some View, label: LocalizedStringKey) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        value
            .font(.system(size: 16, weight: .bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        // No shrink-to-fit: all four labels are a word or two, and a
        // label drawn a point smaller than the three beside it reads as a
        // mistake rather than as a fit.
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
    .accessibilityElement(children: .combine)
}

/// A length of time, drawn the way the headline over it is: the figures in the
/// text colour and the units dimmed behind them.
///
/// Its own type because the card now says four durations — the total, the
/// average, and the two ends of the library — and the reader should not have
/// to work out that "2h 36m" and "23h 20m" are the same kind of thing.
///
/// "6h 40m", and "45m" for an event under the hour: the leading "0h" is dropped
/// rather than printed.
private struct DurationLabel: View {
    let seconds: TimeInterval
    var size: CGFloat = 16

    private var minutes: Int { Int(seconds / 60) }

    var body: some View {
        // A space in whatever size this is drawn at rather than a fixed
        // number of points: "24h 50m" at 30pt and the same figure at 15pt in
        // a row of events have to read as the same gap.
        HStack(spacing: size * 0.3) {
            if minutes >= 60 { part(minutes / 60, unit: "h") }
            part(minutes % 60, unit: "m")
        }
        .font(.system(size: size, weight: .bold))
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    /// The unit sits tight against its figure — "24h", not "24 h" — so the
    /// gap in the line is the one between the hours and the minutes.
    private func part(_ value: Int, unit: String) -> some View {
        HStack(spacing: 0) {
            Text(value.formatted())
            Text(verbatim: unit).foregroundStyle(.tertiary)
        }
    }
}

/// How many events the slice holds, and how they fell — across the years,
/// across the year, or across the week.
///
/// Its own card rather than another figure in the panel above, because it is
/// the one reading on this screen that is a shape rather than a number: three
/// events every December and none in between is a fact about the reader that
/// no total can print.
///
/// The cut is the reader's to choose and is deliberately not remembered
/// between visits, for the reason ``PassportScope`` is not: a chart opened on
/// a cut chosen a fortnight ago is a chart that answers a question nobody
/// asked.
private struct PassportEventsCard: View {
    let stats: PassportStats

    @State private var cadence: PassportCadence = .year

    /// Which cuts are on offer. A slice inside one year has nothing to say by
    /// year, so the chip is not offered rather than drawn over a single point.
    private var cadences: [PassportCadence] {
        stats.tally(by: .year).count > 1 ? PassportCadence.allCases : [.month, .weekday]
    }

    /// The cut actually drawn, which is the chosen one unless the year filter
    /// has just taken it away underneath the reader.
    private var shown: PassportCadence {
        cadences.contains(cadence) ? cadence : .month
    }

    private var tallies: [PassportStats.Tally] { stats.tally(by: shown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Events")

            Text(stats.totalEvents.formatted())
                .font(.system(size: 40, weight: .bold))
                .kerning(-1.4)
                .monospacedDigit()

            picker
            chart
                .frame(height: 148)
                .accessibilityLabel(Text("Events per \(Text(shown.label))"))
        }
        .padding(16)
        .glassPanel(cornerRadius: 28)
    }

    /// Tinted rather than filled, and flat rather than glass: the year filter
    /// over the whole screen is the one control worth reading from across the
    /// room, and a second capsule of glass inside a panel of glass would both
    /// outshout it and box the card.
    private var picker: some View {
        HStack(spacing: 6) {
            Text("Events Per")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.trailing, 2)
            ForEach(cadences) { option in
                Button {
                    withAnimation(.snappy) { cadence = option }
                } label: {
                    Text(option.label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(shown == option ? Color.brandTint : .secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background {
                            if shown == option {
                                Capsule().fill(Color.brandTint.opacity(0.15))
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Bars for all three cuts, years included.
    ///
    /// A line read better over the years — one follows the other, which is
    /// what a line is for — but it has to be drawn on a scale of its own,
    /// and a point on that scale never quite lands on the name printed under
    /// it. Bars stand *in* their year, so a column and its label cannot come
    /// apart.
    private var chart: some View {
        Chart(tallies) { tally in
            BarMark(
                x: .value("When", tally.label),
                y: .value("Events", tally.count),
                width: barWidth
            )
            .clipShape(.rect(cornerRadius: 4, style: .continuous))
        }
        .foregroundStyle(Color.brandTint)
        .chartXScale(domain: tallies.map(\.label))
        .modifier(PassportChartStyle())
        .chartXAxis {
            AxisMarks(values: axisLabels) { when in
                axisName(when.as(String.self), centered: true)
            }
        }
    }

    /// A share of the space each column is given, except where there are so
    /// few columns that the share is a slab: a library two years old should
    /// read as two bars rather than as two walls.
    private var barWidth: MarkDimension {
        tallies.count > 4 ? .ratio(0.55) : .fixed(44)
    }

    /// Every month and every weekday is named. Years are thinned to five or
    /// six, counted back from the last one so the year the reader is in is
    /// always one of the ones printed — a decade of them named in full is a
    /// smear.
    private var axisLabels: [String] {
        guard shown == .year else { return tallies.map(\.label) }
        let step = max(1, (tallies.count + 4) / 5)
        return tallies.enumerated()
            .filter { (tallies.count - 1 - $0.offset) % step == 0 }
            .map(\.element.label)
    }
}

/// What both charts share: a quiet grid, small labels, and no frame around
/// the plot — it is already inside one.
private struct PassportChartStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    // Read as a Double as well as an Int: the counts are
                    // whole events, but a tick between two of them is the
                    // axis's own to place and comes back as one.
                    AxisValueLabel {
                        if let count = value.as(Int.self) ?? value.as(Double.self).map(Int.init) {
                            Text(count.formatted())
                                .font(.system(size: 9.5, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
    }
}

/// One name under the axis, in the small dimmed type both charts label
/// themselves with. Nothing is drawn for a tick whose value is not the kind
/// the chart is scaled by.
///
/// Centred rather than left to find its own place: a label given its own view
/// is hung from its leading edge by default, and the tick under a band — a
/// year, a month, a weekday — is the line between two of them rather than
/// the middle of one, so the name walked half a word off its own column.
private func axisName(_ label: String?, centered: Bool = false) -> some AxisMark {
    AxisValueLabel(centered: centered, anchor: .top) {
        if let label {
            Text(verbatim: label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }
}

/// One event and how long it ran.
///
/// Its own type rather than a method on the screen for the reason
/// ``PassportRankRow`` is: the card shows one of these and the sheet behind
/// its See All shows five, and they are the two things most likely to drift.
private struct PassportSpanRow: View {
    /// Which clock the day and times are printed on — see ``TimeDisplay``.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue
    let span: PassportStats.Span

    var body: some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: span.event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                // Day then hall, the way ``PassportLotteryRow`` reads it: two
                // cards of rows a screen apart should not put the same two
                // facts in a different order.
                Text(verbatim: "\(span.event.shown(on: timeDisplay).dayLine) · \(span.event.venue)")
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DurationLabel(seconds: span.duration, size: 15)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The whole of one end of the library — up to five events, briefest or
/// longest first.
///
/// A drawer rather than a pushed screen: the list is short and fixed, and the
/// reader is meant to read it and put it back down where they were, not
/// navigate away from the card that raised the question.
private struct PassportExtremesSheet: View {
    let extreme: PassportExtreme
    let spans: [PassportStats.Span]

    /// A row here opens the event it names, exactly as the row on the card
    /// does — a drawer over a drawer rather than a push, because an event's
    /// own sheet is what every list in the app opens, and the reader closes it
    /// back onto the list they tapped it from.
    @State private var openEvent: Event?

    /// Tall enough for the rows it has and no taller. Five is the ceiling and
    /// a short library gets fewer, so a fixed detent would leave a drawer
    /// mostly empty under two rows.
    private var height: CGFloat {
        90 + CGFloat(spans.count) * 58 + 24
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(spans.enumerated()), id: \.element.id) { index, span in
                        if index > 0 { Divider() }
                        Button { openEvent = span.event } label: {
                            PassportSpanRow(span: span)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .washBackground()
        // The measured height first, with .large behind it for the accessibility
        // text sizes that wrap a row onto a second line.
        .presentationDetents([.height(height), .large])
        .eventSheet($openEvent)
    }

    private var header: some View {
        PassportSheetHeader(
            eyebrow: Text("Top ^[\(spans.count) event](inflect: true)"),
            title: extreme.title)
    }
}

/// The whole of one ranked list, behind a card's See All.
///
/// A drawer like the extremes, and a stack inside it, because a row here still
/// opens a performer or a hall: the sheet carries its own navigation so the
/// push lands inside the drawer rather than on a screen the reader can no
/// longer see behind it.
private struct PassportRankingSheet: View {
    @Environment(EventStore.self) private var store
    @Query(LibraryEntry.library) private var kept: [LibraryEntry]

    let ranking: PassportRanking

    /// Read here rather than handed in, for the reason the screen reads it:
    /// one slice, derived from the library, so nothing can be stale.
    private var stats: PassportStats {
        PassportStats(events: PassportStats.events(store.events(of: kept, where: \.inLibrary).filter(store.hasAttended),
                                                  in: ranking.scope)) {
            store.tracking(for: $0)
        }
    }

    var body: some View {
        let stats = self.stats
        let rows = ranking.rows(of: stats)
        let most = max(1, rows.first?.count ?? 1)

        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                PassportSheetHeader(eyebrow: eyebrow(rows.count), title: ranking.title)
                ScrollView {
                    VStack(spacing: 13) {
                        ForEach(rows) { row in
                            let label = PassportRankRow(
                                row: row, most: most, total: stats.totalEvents,
                                tint: tint, showsShare: ranking.isPerformers)
                            // Two links rather than one over an erased value: a
                            // push is matched to its destination by the *type*
                            // of what was pushed, and `AnyHashable` matches
                            // neither.
                            if ranking.isPerformers {
                                NavigationLink(value: PerformerLink.billed(name: row.name)) { label }
                                    .buttonStyle(.plain)
                            } else {
                                NavigationLink(value: VenueLink.named(row.name)) { label }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(16)
                    .glassPanel(cornerRadius: 28)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            // Hidden on the root only, so the drawer opens on its own header
            // and a pushed performer or hall still gets a bar with a way back.
            .toolbar(.hidden, for: .navigationBar)
            .washBackground()
            .venueDestination()
        }
        // Opens half-height like the extremes and pulls up to full: these two
        // lists run to as many names as the reader has been to.
        .presentationDetents([.medium, .large])
    }

    private func eyebrow(_ count: Int) -> Text {
        ranking.isPerformers
            ? Text("^[\(count) performer](inflect: true)")
            : Text("^[\(count) venue](inflect: true)")
    }

    private var tint: Color { ranking.isPerformers ? .trackAttended : .brandTint }
}

/// The top of a passport drawer: what it is counting, what it is, and the way
/// back out.
///
/// Shared so the two drawers open the same way — an X in the corner rather
/// than a Done in a toolbar, because neither of them is asking the reader to
/// decide anything.
private struct PassportSheetHeader: View {
    @Environment(\.dismiss) private var dismiss

    let eyebrow: Text
    let title: Text

    init(eyebrow: Text, title: Text) {
        self.eyebrow = eyebrow
        self.title = title
    }

    init(eyebrow: Text, title: LocalizedStringKey) {
        self.init(eyebrow: eyebrow, title: Text(title))
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                eyebrow
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                title
                    .font(.system(size: 24, weight: .bold))
            }
            Spacer(minLength: 12)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .glassBackground(in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }
}

/// One row of a ranked list: who or where, how many, and how much of the
/// library that is.
///
/// Its own type rather than a method on the screen because the card and the
/// full list behind its See All both draw it, and they are the two things most
/// likely to drift.
private struct PassportRankRow: View {
    let row: PassportStats.Ranking
    /// The highest count in the list, which is what the bar is drawn against.
    let most: Int
    /// The whole slice, which is what the share is taken of.
    let total: Int
    let tint: Color
    /// Shown for performers and not for halls: "18 of your 128 events" is worth
    /// saying about somebody the reader follows, where a hall's share of the
    /// library is not a thing anybody asks.
    let showsShare: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: row.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(row.count.formatted())
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                if showsShare, total > 0 {
                    Text((Double(row.count) / Double(total)).formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
            PassportBar(fraction: Double(row.count) / Double(most), tint: tint)
            if let detail = row.detail {
                Text(verbatim: detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// One event the reader applied for: how each round went, a dot each in the
/// order the sale ran them, how many times, and how that stands against the
/// hardest they ever tried for a seat.
private struct PassportLotteryRow: View {
    /// Which clock the day and times are printed on — see ``TimeDisplay``.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue
    let row: LotteryListRow
    /// The most entries in the list, which is what the bar is drawn against.
    let most: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(verbatim: row.event.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LotteryDots(outcomes: row.outcomes)
                Text(row.entries.formatted())
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.trackTicket)
            }
            PassportBar(fraction: Double(row.entries) / Double(most), tint: .trackTicket)
            Text(verbatim: "\(row.event.shown(on: timeDisplay).dayLine) · \(row.event.venue)")
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        // The gaps between the three lines are part of the row, so a tap
        // between the bar and the date opens the event rather than nothing.
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// One event in a list of the lottery card's: how many times it was applied
/// for and how each round went — every round, under Top Lottery Entries, or
/// the rounds a row of By Round or By Seat counted, behind that row.
private struct LotteryListRow: Identifiable {
    let event: Event
    let entries: Int
    let outcomes: [LotteryOutcome]

    var id: Event.ID { event.id }

    /// Marked choice by choice (``PassportStats/choiceMarks(of:)``).
    init(_ lottery: PassportStats.Lottery) {
        event = lottery.event
        entries = lottery.entries
        outcomes = lottery.choices.joined().map(LotteryOutcome.init)
    }

    /// One of the events behind a row of By Round or By Seat, marked choice
    /// by choice as that row counts them.
    init(_ counted: PassportStats.LotteryEvent) {
        event = counted.event
        entries = counted.entries
        outcomes = counted.choices.joined().map(LotteryOutcome.init)
    }
}

/// How an event's lotteries went, a dot each in the order the sale ran them,
/// drawn as `Eventrail v4.dc.html` draws them: filled, in the colours of the
/// legend over them.
///
/// A dot is a choice. Under Top Lottery Entries and By Round: each choice
/// before the one won grey, the one won orange, nothing after it, so a seat
/// won with the first choice is one orange dot. Under By Seat: every choice
/// up to the one that asked for that class, the last in the colour of how
/// it went for the class — orange, or tan where a lower one was won.
private struct LotteryDots: View {
    let outcomes: [LotteryOutcome]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(outcomes.indices, id: \.self) { index in
                Circle()
                    .fill(outcomes[index].color)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(LotteryOutcome.summary(of: outcomes))
    }
}

/// A list of the card's events: every event the reader wrote a lottery round
/// on, behind Top Lottery Entries' See All, most applications first — or the
/// events behind one row of By Round or By Seat, newest first, each with only
/// the rounds that row counted.
///
/// No stack inside this one, unlike ``PassportRankingSheet``: a row here is a
/// event rather than a name, and the card it came from does not open one
/// either.
private struct PassportLotterySheet: View {
    let title: Text
    let eyebrow: Text
    let rows: [LotteryListRow]

    /// A row here opens the event it names, exactly as the row on the card
    /// does — a drawer over a drawer, the way ``PassportExtremesSheet`` opens
    /// one, so the reader closes the event back onto the list they tapped it
    /// from.
    @State private var openEvent: Event?

    var body: some View {
        let most = max(1, rows.map(\.entries).max() ?? 1)

        VStack(alignment: .leading, spacing: 0) {
            PassportSheetHeader(eyebrow: eyebrow, title: title)
            ScrollView {
                VStack(spacing: 13) {
                    ForEach(rows) { row in
                        Button { openEvent = row.event } label: {
                            PassportLotteryRow(row: row, most: most)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .glassPanel(cornerRadius: 28)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .washBackground()
        .presentationDetents([.medium, .large])
        .eventSheet($openEvent)
    }
}

// MARK: - How the lotteries went

/// How the reader's lotteries went, as `Eventrail v4.dc.html` draws the card:
/// the win rate over every round drawn and how the rounds went, how many
/// rounds and applications that was and how many rounds a win took — then the
/// same rounds by the round of the sale and by the class of seat asked for,
/// and the events applied for hardest.
///
/// Counted from what the reader wrote on each event's rounds, and over the
/// lotteries alone (``LotteryEntry/isLottery``): a first-come round is a seat
/// got, not a draw. Every rate is out of the rounds whose result was written
/// down, and says so; a round left without one is No Result, the ticket
/// sheet's own word for a lottery still pending once its event is over, and
/// is drawn apart from a loss rather than read as one.
private struct PassportLotteryCard: View {
    let stats: PassportStats
    /// How many of the events applied for hardest the card shows.
    let limit: Int
    let open: (Event) -> Void

    /// The list of events open over the card, if any.
    @State private var openList: LotteryList?

    /// What a list of events behind the card holds.
    private enum LotteryList: Identifiable, Hashable {
        /// Every event applied for, behind Top Lottery Entries' See All.
        case top
        /// The events behind a row of By Round, by the round as written.
        case round(String)
        /// The events behind a row of By Seat, by the class as written.
        case seat(String)

        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Lottery Entries")
            headline
            outcomes
            readings
            if !stats.lotteryRounds.isEmpty { byRound }
            if !stats.lotterySeats.isEmpty { bySeat }
            topEntries
        }
        .padding(16)
        .glassPanel(cornerRadius: 28)
        .sheet(item: $openList) { list in
            switch list {
            case .top:
                PassportLotterySheet(title: Text("Top Lottery Entries"),
                                     eyebrow: Text("^[\(stats.topLotteries.count) event](inflect: true) recorded"),
                                     rows: stats.topLotteries.map(LotteryListRow.init))
            case .round(let round):
                let rows = (stats.roundEvents[round] ?? []).map(LotteryListRow.init)
                PassportLotterySheet(title: Self.roundName(round),
                                     eyebrow: Text("^[\(rows.count) event](inflect: true)"), rows: rows)
            case .seat(let seatClass):
                let rows = (stats.seatEvents[seatClass] ?? []).map(LotteryListRow.init)
                PassportLotterySheet(title: SeatStyle.styles(for: stats)[seatClass].label,
                                     eyebrow: Text("^[\(rows.count) event](inflect: true)"), rows: rows)
            }
        }
    }

    /// A round of the sale as the reader reads it, and Unspecified for the
    /// rounds that name none.
    private static func roundName(_ round: String) -> Text {
        round.isEmpty ? Text("Unspecified") : Text(verbatim: LotteryRound.label(of: round))
    }

    /// A row of By Round or By Seat, opening the events it counted.
    private func listing(_ list: LotteryList, @ViewBuilder row: () -> some View) -> some View {
        Button { openList = list } label: { row().contentShape(.rect) }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Shows the events counted here"))
    }

    /// The win rate, large, and what it was out of beside it.
    private var headline: some View {
        let tally = stats.lotteryTally
        return HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Win Rate")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                LotteryRate(rate: tally.winRate, size: 36)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                Text("of ^[\(tally.drawn) drawn round](inflect: true)")
                Text("across ^[\(stats.lotteryEvents) event](inflect: true)")
            }
            .font(.system(size: 11.5))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    /// Every round in one bar, won against lost, and the count of each.
    private var outcomes: some View {
        let tally = stats.lotteryTally
        var kinds: [(LotteryOutcome, Int)] = [(.won, tally.won), (.lost, tally.lost)]
        if tally.unknown > 0 { kinds.append((.unknown, tally.unknown)) }
        return VStack(alignment: .leading, spacing: 10) {
            PassportSplitBar(parts: kinds.map { .init(count: $0.1, color: $0.0.color) }, height: 10)
            FlowLayout(spacing: 16, lineSpacing: 6) {
                ForEach(kinds, id: \.0) { kind, count in
                    LotteryLegendItem(kind: kind, label: kind.label, count: count)
                }
            }
        }
    }

    /// The three readings under the rate, at the time card's widths.
    private var readings: some View {
        HStack(spacing: 0) {
            reading(Text(stats.lotteryTally.rounds.formatted()), label: "Rounds", isFirst: true)
            reading(Text(stats.lotteryEntries.formatted()), label: "Entries", isFirst: false)
            reading(stats.roundsToWin.map { Text($0.formatted(.number.precision(.fractionLength(1)))) }
                        ?? Text(verbatim: "–"),
                    label: "Rounds to Win", isFirst: false)
        }
        .padding(.top, 14)
        .overlay(alignment: .top) { Divider() }
    }

    private func reading(_ value: Text, label: LocalizedStringKey, isFirst: Bool) -> some View {
        passportReading(value, label: label)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, isFirst ? 0 : 14)
    }

    /// Each round of a sale, in the order a sale runs them.
    private var byRound: some View {
        section(spacing: 13) {
            Text("By Round")
                .font(.system(size: 15.5, weight: .bold))
            ForEach(stats.lotteryRounds) { round in
                let tally = round.tally
                listing(.round(round.round)) {
                    LotteryTallyRow(
                        rate: tally.winRate,
                        parts: [(.won, tally.won), (.lost, tally.lost), (.unknown, tally.unknown)]
                    ) {
                        Self.roundName(round.round)
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(1)
                    } line: {
                        LotteryLine.join([
                            Text("^[\(tally.rounds) round](inflect: true)"),
                            Text("\(tally.won) won"),
                        ] + (tally.unknown > 0 ? [Text("\(tally.unknown) no result")] : []))
                    }
                }
            }
        }
    }

    /// Each class of seat asked for, won in it against won in another.
    private var bySeat: some View {
        // Each kind only where a seat has some: General is never an other
        // seat, and a library that won only the classes it asked for has none.
        let hasOther = stats.lotterySeats.contains { $0.otherSeat > 0 }
        let hasUnknown = stats.lotterySeats.contains { $0.unknown > 0 }
        let kinds: [LotteryOutcome] = [.won] + (hasOther ? [.otherSeat] : []) + [.lost]
            + (hasUnknown ? [.unknown] : [])
        return section(spacing: 13) {
            VStack(alignment: .leading, spacing: 4) {
                Text("By Seat")
                    .font(.system(size: 15.5, weight: .bold))
                if stats.hasRankedChoices && stats.namedWins > 0 {
                    Text("First choice won \(stats.firstChoiceWins) of ^[\(stats.namedWins) win](inflect: true)")
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                FlowLayout(spacing: 14, lineSpacing: 6) {
                    ForEach(kinds, id: \.self) { kind in
                        LotteryLegendItem(kind: kind, label: kind == .won ? "This seat" : kind.label, count: nil)
                    }
                }
                .padding(.top, 4)
            }
            // Badged and named as the spending card's classes are, from the
            // same styles, so an S seat is the same red letter on both.
            let styles = SeatStyle.styles(for: stats)
            ForEach(stats.lotterySeats) { seat in
                let style = styles[seat.seatClass]
                listing(.seat(seat.seatClass)) {
                    LotteryTallyRow(
                        rate: seat.winRate,
                        parts: [(.won, seat.won), (.otherSeat, seat.otherSeat), (.lost, seat.lost),
                                (.unknown, seat.unknown)],
                        badge: SeatBadge(style: style)
                    ) {
                        style.label
                            .font(Font(SeatBadge.nameFont))
                            .lineLimit(1)
                    } line: {
                        LotteryLine.join([
                            Text("^[\(seat.rounds) round](inflect: true)"),
                            Text("\(seat.won) won"),
                        ] + (seat.otherSeat > 0 ? [Text("\(seat.otherSeat) other seat")] : [])
                          + (seat.unknown > 0 ? [Text("\(seat.unknown) no result")] : []))
                    }
                }
            }
        }
    }

    /// The events applied for hardest, and a See All to the rest.
    private var topEntries: some View {
        let rows = Array(stats.topLotteries.prefix(limit))
        let most = max(1, rows.first?.entries ?? 1)
        return section(spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Top Lottery Entries")
                    .font(.system(size: 15.5, weight: .bold))
                Spacer(minLength: 8)
                if stats.topLotteries.count > limit {
                    Button { openList = .top } label: { SeeAllLabel() }
                        .buttonStyle(.plain)
                }
            }
            ForEach(rows) { row in
                // A row is the event it names, the way the extremes in the
                // time card and the ranked cards below are: the whole line is
                // the target.
                Button { open(row.event) } label: { PassportLotteryRow(row: LotteryListRow(row), most: most) }
                    .buttonStyle(.plain)
            }
        }
    }

    /// A part of the card ruled off from the one above it.
    private func section(spacing: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: spacing, content: content)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Divider() }
    }
}

/// What a lottery round came to, as the lottery card counts it, and the
/// colour it is drawn in: the ticket's orange for a win, grey for a loss, and
/// next to nothing for a round nobody wrote a result on.
private enum LotteryOutcome: Hashable {
    case won
    /// Won, in a lower class the round asked for — only By Seat says this.
    case otherSeat
    case lost
    case unknown

    init(_ result: LotteryResult) {
        self.init(PassportStats.RoundOutcome(result))
    }

    init(_ outcome: PassportStats.RoundOutcome) {
        switch outcome {
        case .won: self = .won
        case .otherSeat: self = .otherSeat
        case .lost: self = .lost
        case .noResult: self = .unknown
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .won: "Won"
        case .otherSeat: "Other seat"
        case .lost: "Lost"
        case .unknown: "No Result"
        }
    }

    var color: Color {
        switch self {
        case .won: .trackTicket
        case .otherSeat: .trackTicket.opacity(0.3)
        case .lost: Color(.systemGray3)
        case .unknown: .primary.opacity(0.12)
        }
    }

    /// The dots of ``LotteryDots`` said aloud: how many of each.
    static func summary(of outcomes: [LotteryOutcome]) -> Text {
        func count(_ kind: LotteryOutcome) -> Int { outcomes.filter { $0 == kind }.count }
        let won = count(.won), other = count(.otherSeat), lost = count(.lost), unknown = count(.unknown)
        return LotteryLine.join([
            won > 0 ? Text("\(won) won") : nil,
            other > 0 ? Text("\(other) other seat") : nil,
            lost > 0 ? Text("\(lost) lost") : nil,
            unknown > 0 ? Text("\(unknown) no result") : nil,
        ].compactMap { $0 })
    }
}

/// The lines under a lottery card's rows, run together.
private enum LotteryLine {
    static func join(_ parts: [Text]) -> Text {
        guard let first = parts.first else { return Text(verbatim: "") }
        return parts.dropFirst().reduce(first) { Text("\($0) · \($1)") }
    }
}

/// A win rate, in the ticket's orange — a dash where nothing was drawn.
private struct LotteryRate: View {
    let rate: Double?
    let size: CGFloat

    var body: some View {
        Group {
            if let rate {
                Text(rate.formatted(.percent.precision(.fractionLength(0))))
            } else {
                Text(verbatim: "–")
            }
        }
        .font(.system(size: size, weight: .bold))
        .kerning(-size * 0.03)
        .monospacedDigit()
        .foregroundStyle(Color.trackTicket)
        .lineLimit(1)
        .fixedSize()
    }
}

/// One colour of a lottery bar named: its dot, its name and, where the bar
/// is the card's own, how many.
private struct LotteryLegendItem: View {
    let kind: LotteryOutcome
    let label: LocalizedStringKey
    let count: Int?

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(kind.color)
                .frame(width: 7, height: 7)
            Text(label)
                .foregroundStyle(.secondary)
            if let count {
                Text(count.formatted())
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
        }
        .font(.system(size: count == nil ? 11 : 11.5, weight: .medium))
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// One round of a sale or one class of seat: its name and what it came to,
/// the rate beside them, and the rounds as one bar under them.
private struct LotteryTallyRow<Badge: View, Name: View>: View {
    let rate: Double?
    let parts: [(LotteryOutcome, Int)]
    let badge: Badge
    let name: Name
    let line: Text

    init(rate: Double?, parts: [(LotteryOutcome, Int)], badge: Badge,
         @ViewBuilder name: () -> Name, line: () -> Text) {
        self.rate = rate
        self.parts = parts
        self.badge = badge
        self.name = name()
        self.line = line()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Centred on the name and the line under it, which it heads
            // together, as the spending card centres its own.
            HStack(spacing: 8) {
                badge
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        name
                        line
                            .font(.system(size: 11.5))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    LotteryRate(rate: rate, size: 15)
                }
            }
            PassportSplitBar(parts: parts.map { .init(count: $0.1, color: $0.0.color) }, height: 6)
        }
        .accessibilityElement(children: .combine)
    }
}

extension LotteryTallyRow where Badge == EmptyView {
    init(rate: Double?, parts: [(LotteryOutcome, Int)],
         @ViewBuilder name: () -> Name, line: () -> Text) {
        self.init(rate: rate, parts: parts, badge: EmptyView(), name: name, line: line)
    }
}

/// A count split into its parts, each a capsule of its own two points from
/// the next, as the lottery card draws how its rounds went. A part with
/// nothing in it is left out, and every other one is at least a dot wide.
private struct PassportSplitBar: View {
    struct Part {
        let count: Int
        let color: Color
    }

    let parts: [Part]
    let height: CGFloat

    var body: some View {
        let shown = parts.filter { $0.count > 0 }
        GeometryReader { proxy in
            let gaps = CGFloat(max(0, shown.count - 1)) * 2
            let free = max(0, proxy.size.width - gaps - CGFloat(shown.count) * 4)
            let total = CGFloat(max(1, shown.reduce(0) { $0 + $1.count }))
            HStack(spacing: 2) {
                ForEach(shown.indices, id: \.self) { index in
                    Capsule()
                        .fill(shown[index].color)
                        .frame(width: 4 + free * CGFloat(shown[index].count) / total)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - What the reader paid

/// What the reader paid for the events they went to, and for which seats.
///
/// Counted, like the lottery card, from something they typed: every figure is
/// over the events a price was written on — ``PassportStats/tickets`` — and a
/// event left blank is left out rather than read as free.
///
/// In one currency, chosen from the menu in its corner: the reader's default
/// as it opens, and any other for as long as the screen is up. A ticket paid
/// in another is converted at today's rates, and the card says which day's;
/// where every ticket was paid in one currency, each figure also says what it
/// was in that one, small under it.
///
/// Its own type, as the events card is, because the seat-type filter over its
/// two ends is state of its own — and, like the cadence there, deliberately
/// not remembered between visits.
private struct PassportSpendingCard: View {
    let stats: PassportStats
    /// The currency the card adds up in.
    @Binding var currency: String
    /// Settings' — marked Default in the menu.
    let defaultCurrency: String
    /// Opens an event on the screen's own event sheet.
    let open: (Event) -> Void

    /// The class the dearest and cheapest are read over; nil for every ticket.
    @State private var seatFilter: String?
    /// The list of tickets open over the card, if any.
    @State private var openList: TicketList?

    /// What a list of tickets behind the card holds, and the order it runs in.
    private enum TicketList: Identifiable, Hashable {
        /// Every ticket under the chips, from the end whose See All opened
        /// it: dearest first under Highest, cheapest first under Lowest.
        case highest, lowest
        /// Every ticket of one class, dearest first — a row under By Ticket
        /// Type, tapped.
        case seatClass(String)

        var id: Self { self }
    }

    /// The chosen class, unless the year filter has just taken it away
    /// underneath the reader.
    private var filter: String? {
        stats.ticketTypes.contains { $0.seatClass == seatFilter } ? seatFilter : nil
    }

    /// The tickets the two ends are read off, dearest first.
    private var filtered: [PassportStats.Ticket] {
        guard let filter else { return stats.tickets }
        return stats.tickets.filter { $0.seatClass == filter }
    }

    var body: some View {
        let styles = SeatStyle.styles(for: stats)
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Ticket Spending", caption: caption) { currencyMenu }

            if !stats.tickets.isEmpty {
                headline

                // Each at its own width with equal gaps between, rather than
                // in quarters: a count of tickets is a digit or two and a
                // price is seven characters, so equal columns left a hole
                // after the count and the three prices all but touching.
                HStack(alignment: .top, spacing: 0) {
                    passportReading(Text(stats.tickets.count.formatted()), label: "Tickets")
                    Spacer(minLength: 12)
                    PassportPriceReading(value: money(stats.averageTicketPrice),
                                         paid: paid(stats.averagePaid), label: "Avg. Price")
                    Spacer(minLength: 12)
                    PassportPriceReading(value: money(stats.highestTicketPrice),
                                         paid: paid(stats.tickets.first?.paid), label: "Highest")
                    Spacer(minLength: 12)
                    PassportPriceReading(value: money(stats.lowestTicketPrice),
                                         paid: paid(stats.tickets.last?.paid), label: "Lowest")
                }

                types(styles)
                // Two tickets before there are two ends, for the reason the
                // time card waits for two timed events.
                if stats.tickets.count >= 2 { extremes(styles) }
            }
        }
        .padding(16)
        .glassPanel(cornerRadius: 28)
        .sheet(item: $openList) { list in
            switch list {
            case .highest:
                PassportTicketSheet(tickets: filtered, title: Text("Highest Price"),
                                    currency: stats.currency, styles: styles,
                                    seatType: filter.map { styles[$0].label })
            case .lowest:
                // Reversed rather than sorted again, so the first row is the
                // one the card shows as the cheapest, ties and all.
                PassportTicketSheet(tickets: filtered.reversed(), title: Text("Lowest Price"),
                                    currency: stats.currency, styles: styles,
                                    seatType: filter.map { styles[$0].label })
            case .seatClass(let seatClass):
                // Every ticket of the class whatever the chips say: the row
                // tapped is the slice's, not the filtered ends'.
                PassportTicketSheet(tickets: stats.tickets.filter { $0.seatClass == seatClass },
                                    title: styles[seatClass].label,
                                    currency: stats.currency, styles: styles, seatType: nil)
            }
        }
    }

    /// What the figures were counted over, where that is not simply every
    /// ticket in the currency they were paid in: the tickets left out for
    /// want of a rate, or else, where the tickets were paid in several
    /// currencies, the day of the rates they were converted at.
    ///
    /// Not that day where they were all paid in one: there the card converts
    /// in every currency but that one, and a line that came and went with the
    /// menu would move everything under it. Paid in several, the card converts
    /// whichever currency it is read in, so the line stays put.
    private var caption: Text? {
        if stats.unconvertedTickets > 0 {
            if ExchangeRates.shared.isReading { return Text("Getting exchange rates…") }
            return Text("^[\(stats.unconvertedTickets) ticket](inflect: true) not counted — no exchange rate yet")
        }
        guard stats.isConverted, stats.paidCurrency == nil else { return nil }
        return exchangeRatesLine()
    }

    /// The currency the card adds up in, as a capsule in the header's corner
    /// that opens the menu of them — see ``CurrencyChoices``.
    private var currencyMenu: some View {
        Menu {
            CurrencyChoices(selection: $currency, defaultCurrency: defaultCurrency)
        } label: {
            HStack(spacing: 5) {
                Text(verbatim: currency)
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Color.brandTint)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color(.secondarySystemGroupedBackground), in: .capsule)
            .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Currency"))
        .accessibilityValue(Text(verbatim: Currencies.name(of: currency)))
        .sensoryFeedback(.selection, trigger: currency)
    }

    /// The total, its symbol dimmed beside it the way the time card dims its
    /// units after — and, where it was all paid in another currency, what it
    /// came to there.
    private var headline: some View {
        let parts = Currencies.parts(whole: stats.ticketSpending, in: stats.currency)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if !parts.before.isEmpty { symbol(parts.before) }
                Text(verbatim: parts.figures)
                    .font(.system(size: 40, weight: .bold))
                    .kerning(-1.4)
                    .monospacedDigit()
                if !parts.after.isEmpty { symbol(parts.after) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .layoutPriority(1)
            if stats.showsPaid, let paid = stats.paidSpending {
                Text(verbatim: paid.formatted)
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: money(stats.ticketSpending)))
    }

    private func symbol(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(.tertiary)
    }

    private func money(_ amount: Double?) -> String {
        amount.map { Currencies.format(whole: $0, in: stats.currency) } ?? "—"
    }

    /// A figure as it was paid, where the card offers those at all.
    private func paid(_ money: Money?) -> String? {
        guard stats.showsPaid, let money else { return nil }
        return money.formatted
    }

    private func paid(_ amount: Double?) -> String? {
        guard stats.showsPaid, let amount, let code = stats.paidCurrency else { return nil }
        return Currencies.format(whole: amount, in: code)
    }

    // MARK: By the class of seat

    /// Where the money went: one bar split by how many tickets each class
    /// took, then each class with what it cost on one scale, so an S seat and
    /// a general seat can be read against each other.
    private func types(_ styles: SeatStyles) -> some View {
        let axis = priceAxis
        return VStack(alignment: .leading, spacing: 14) {
            Text("By Ticket Type")
                .font(.system(size: 15.5, weight: .bold))

            PassportShareBar(parts: stats.ticketTypes.map {
                PassportShareBar.Part(count: $0.count, color: styles[$0.seatClass].color)
            })

            // Each opens its own tickets. The range's ⓘ inside a row is a
            // button of its own and keeps its tap.
            ForEach(stats.ticketTypes) { type in
                Button { openList = .seatClass(type.seatClass) } label: {
                    PassportTicketTypeRow(type: type, style: styles[type.seatClass],
                                          total: stats.tickets.count, axis: axis,
                                          currency: stats.currency, showsPaid: stats.showsPaid)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Shows the tickets of this type"))
            }

            if let axis {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: money(axis.lowerBound))
                    if let cheapest = paid(stats.tickets.last?.paid) {
                        Text(verbatim: cheapest).foregroundStyle(.quaternary)
                    }
                    Spacer(minLength: 8)
                    if let dearest = paid(stats.tickets.first?.paid) {
                        Text(verbatim: dearest).foregroundStyle(.quaternary)
                    }
                    Text(verbatim: money(axis.upperBound))
                }
                .font(.system(size: 9.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
                .overlay(alignment: .top) {
                    HorizontalRule()
                        .stroke(.quaternary, style: StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
                        .frame(height: 0.5)
                }
                .padding(.leading, 30)
                .padding(.top, -4)
            }
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
    }

    /// The cheapest ticket to the dearest, which every class's range is drawn
    /// on. Nil where every ticket cost the same: a scale with one point on it
    /// puts every dot in one place and says nothing the averages do not.
    private var priceAxis: ClosedRange<Double>? {
        guard let lowest = stats.lowestTicketPrice, let highest = stats.highestTicketPrice,
              highest > lowest else { return nil }
        return lowest ... highest
    }

    // MARK: The dearest and the cheapest

    private func extremes(_ styles: SeatStyles) -> some View {
        let tickets = filtered
        return VStack(alignment: .leading, spacing: 14) {
            if stats.ticketTypes.count > 1 { chips(styles) }

            if let dearest = tickets.first {
                end(tickets.count > 1 ? "Highest Price" : "Price", opening: .highest,
                    ticket: dearest, of: tickets, styles: styles)
            }
            if tickets.count > 1, let cheapest = tickets.last {
                end("Lowest Price", opening: .lowest, ticket: cheapest, of: tickets, styles: styles)
                    .padding(.top, 14)
                    .overlay(alignment: .top) { Divider() }
            }
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
    }

    /// Tinted rather than filled, as the cadence chips on the events card are,
    /// and each with its class's dot so a chip reads as the row above it.
    ///
    /// On one line whatever it holds: headed "Seat Type" where that fits, the
    /// chips alone where it does not — their dots already tie them to the bar
    /// above — and scrolling sideways where even they do not. Wrapped onto a
    /// second line, as it was, one chip sat alone under the others.
    private func chips(_ styles: SeatStyles) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                Text("Seat Type")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 2)
                chipRow(styles)
            }
            HStack(spacing: 6) { chipRow(styles) }
            ScrollView(.horizontal) {
                HStack(spacing: 6) { chipRow(styles) }
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func chipRow(_ styles: SeatStyles) -> some View {
        chip(nil, label: Text("All"), color: .brandTint)
        ForEach(stats.ticketTypes) { type in
            let style = styles[type.seatClass]
            chip(type.seatClass, label: style.label, color: style.color)
        }
    }

    private func chip(_ seatClass: String?, label: Text, color: Color) -> some View {
        let isOn = filter == seatClass
        return Button {
            withAnimation(.snappy) { seatFilter = seatClass }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                label
                    .lineLimit(1)
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(isOn ? color : .secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                if isOn { Capsule().fill(color.opacity(0.15)) }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// One end of the filtered tickets, with a See All to the rest of them
    /// once there are more than the two ends show.
    private func end(
        _ title: LocalizedStringKey, opening list: TicketList, ticket: PassportStats.Ticket,
        of tickets: [PassportStats.Ticket], styles: SeatStyles
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 15.5, weight: .bold))
                Spacer(minLength: 8)
                if tickets.count > 2 {
                    Button { openList = list } label: { SeeAllLabel() }
                        .buttonStyle(.plain)
                }
            }
            Button { open(ticket.event) } label: {
                PassportTicketRow(ticket: ticket, currency: stats.currency,
                                  style: styles[ticket.seatClass])
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One of the spending card's three prices, converted into the card's
/// currency — and, where every ticket was paid in one other currency, an ⓘ
/// beside it that opens what it was there.
///
/// A popover rather than a second line under the figure, so the card is the
/// same height in every currency it is read in: a line that came and went
/// with the menu moved everything below it.
private struct PassportPriceReading: View {
    let value: String
    /// As it was paid; nil where the card offers no such figure.
    let paid: String?
    let label: LocalizedStringKey

    @State private var isShowingPaid = false

    var body: some View {
        if let paid {
            Button { isShowingPaid = true } label: {
                passportReading(
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(verbatim: value)
                        Image(systemName: "info.circle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    },
                    label: label)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingPaid) {
                PassportPaidPopover(paid: paid)
            }
            .accessibilityHint(Text("Shows the price as it was paid"))
        } else {
            passportReading(Text(verbatim: value), label: label)
        }
    }
}

/// What a converted figure was as it was paid, opened from the ⓘ beside a
/// price or a range — the figure and nothing else, since the ⓘ it hangs
/// off already says what it is.
private struct PassportPaidPopover: View {
    let paid: String

    var body: some View {
        Text(verbatim: paid)
            .font(.system(size: 15, weight: .bold))
            .monospacedDigit()
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .presentationCompactAdaptation(.popover)
    }
}

/// "At exchange rates of Oct 3" — the day of the rates every conversion on
/// the card was made at, or nil before any are held.
///
/// The day as Frankfurter names it, which is a date and not an instant: read
/// in the reader's own zone, the 3rd is the 2nd west of Greenwich.
private func exchangeRatesLine() -> Text? {
    guard let rates = ExchangeRates.shared.rates else { return nil }
    var day = Date.FormatStyle.dateTime.month(.abbreviated).day()
    day.timeZone = .gmt
    return Text("At exchange rates of \(rates.published.formatted(day))")
}

/// How the card draws one class of seat: its name in the reader's language,
/// the letter on its badge and its colour.
private struct SeatStyle {
    let label: Text
    let badge: Text
    let color: Color

    /// The tickets that name no class: a dash rather than a letter, and grey,
    /// since what they share is that nothing was written.
    static let unspecified = SeatStyle(label: Text("Unspecified"),
                                       badge: Text(verbatim: "–"),
                                       color: Color(.systemGray2))

    /// A style for every class in the slice — the spending card's and the
    /// lottery card's alike, so the two draw a class the same way.
    ///
    /// The three classes the ticket sheet offers keep one colour each whatever
    /// the year, so an S seat is the same red on every slice. A class the
    /// reader typed is named as typed, badged with its first letter, and given
    /// the next of the spare colours: the spending card's classes in the order
    /// it lists them first, so its colours do not move for the lottery card's,
    /// and then the classes only a lottery asked for.
    static func styles(for stats: PassportStats) -> SeatStyles {
        var styles: [String: SeatStyle] = [:]
        var spare = 0
        let classes = stats.ticketTypes.map(\.seatClass) + stats.lotterySeats.map(\.seatClass)
        for seatClass in classes where !seatClass.isEmpty && styles[seatClass] == nil {
            if let listed = SeatClass(rawValue: seatClass) {
                styles[seatClass] = SeatStyle(label: Text(listed.label), badge: listed.badge,
                                              color: color(of: listed))
            } else {
                styles[seatClass] = SeatStyle(
                    label: Text(verbatim: seatClass),
                    badge: Text(verbatim: seatClass.prefix(1).uppercased()),
                    color: spareColors[spare % spareColors.count])
                spare += 1
            }
        }
        return SeatStyles(styles: styles)
    }

    private static func color(of seatClass: SeatClass) -> Color {
        switch seatClass {
        case .s: .favorite
        case .a: .trackTicket
        case .general: .brandTint
        }
    }

    private static let spareColors: [Color] = [.trackAttended, .indigo, .teal, .brown]
}

/// The styles of one slice's classes, read by the class as written.
private struct SeatStyles {
    let styles: [String: SeatStyle]

    subscript(seatClass: String) -> SeatStyle { styles[seatClass] ?? .unspecified }
}

/// A class of seat's badge: its letter on its colour.
private struct SeatBadge: View {
    let style: SeatStyle

    /// The name it stands beside.
    static let nameFont = UIFont.systemFont(ofSize: 13.5, weight: .semibold)

    var body: some View {
        style.badge
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 22, height: 22)
            .background(style.color, in: .circle)
            .accessibilityHidden(true)
    }
}

/// How many tickets each class took, as one bar split between them.
private struct PassportShareBar: View {
    struct Part {
        let count: Int
        let color: Color
    }

    let parts: [Part]

    var body: some View {
        GeometryReader { proxy in
            // Every part gets a sliver first and shares the rest by count,
            // so a class with one ticket in a hundred is still in the bar.
            let gaps = CGFloat(max(0, parts.count - 1)) * 2
            let free = max(0, proxy.size.width - gaps - CGFloat(parts.count) * 4)
            let total = CGFloat(max(1, parts.reduce(0) { $0 + $1.count }))
            HStack(spacing: 2) {
                ForEach(parts.indices, id: \.self) { index in
                    Rectangle()
                        .fill(parts[index].color)
                        .frame(width: 4 + free * CGFloat(parts[index].count) / total)
                }
            }
        }
        .frame(height: 10)
        .clipShape(.capsule)
        .accessibilityHidden(true)
    }
}

/// One class of seat: how many tickets, their share, and what they cost —
/// the spread on the card's one scale, with the average marked on it.
private struct PassportTicketTypeRow: View {
    let type: PassportStats.TicketType
    let style: SeatStyle
    /// Every ticket in the slice, which the share is taken of.
    let total: Int
    /// The scale the spread is drawn on; nil where there is none.
    let axis: ClosedRange<Double>?
    /// The currency the figures are in.
    let currency: String
    /// Whether every ticket was paid in one other currency, so the average
    /// can say what it was there and the range can open onto it.
    let showsPaid: Bool

    /// Whether the range as it was paid is open over the row.
    @State private var isShowingPaidRange = false

    var body: some View {
        // The badge centred on everything it heads — the name, the spread
        // and the average — as the lottery card centres its own on the two
        // lines beside it.
        HStack(spacing: 8) {
            SeatBadge(style: style)
            details
        }
        .accessibilityElement(children: .combine)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The name, the count and the share on one baseline, as a ranking
            // row sets them.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                style.label
                    .font(Font(SeatBadge.nameFont))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(type.count.formatted())
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                Text((Double(type.count) / Double(max(1, total)))
                        .formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: 34, alignment: .trailing)
            }

            if let axis {
                PassportPriceRange(type: type, axis: axis, color: style.color)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("Avg. \(Text(verbatim: money(type.average)).fontWeight(.semibold).foregroundStyle(.primary))")
                    if showsPaid, let paid = type.paidAverage {
                        Text(verbatim: Currencies.format(whole: paid.amount.doubleValue, in: paid.currency))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Always, so the corner is never empty: a class whose tickets
                // all cost one price shows that price, which is its range.
                if showsPaid { paidRangeButton } else { Text(verbatim: range) }
            }
            .font(.system(size: 11.5))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    /// The cheapest to the dearest, or the one price where they are one.
    private var range: String {
        type.highest > type.lowest ? "\(money(type.lowest))–\(money(type.highest))" : money(type.lowest)
    }

    private var paidRange: String {
        type.highest > type.lowest ? "\(type.lowestPaid.formatted)–\(type.highestPaid.formatted)"
                                   : type.lowestPaid.formatted
    }

    /// The range, with a tap that shows it as it was paid — too long a line
    /// to print beside the converted one in a row this narrow.
    private var paidRangeButton: some View {
        Button { isShowingPaidRange = true } label: {
            // On the text's baseline, as the prices' ⓘ is: centred, the
            // symbol hung below the line and the row grew in every currency
            // but the one its tickets were paid in.
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: range)
                Image(systemName: "info.circle")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingPaidRange) {
            PassportPaidPopover(paid: paidRange)
        }
        .accessibilityLabel(Text(verbatim: range))
        .accessibilityHint(Text("Shows the range as it was paid"))
    }

    private func money(_ amount: Double) -> String {
        Currencies.format(whole: amount, in: currency)
    }
}

/// A class's cheapest ticket to its dearest, as a span on the card's scale,
/// and a dot at what an average one cost.
private struct PassportPriceRange: View {
    let type: PassportStats.TicketType
    let axis: ClosedRange<Double>
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            // Inset by the dot's radius at both ends, so the cheapest ticket
            // and the dearest sit inside the track rather than half off it.
            let inner = max(0, proxy.size.width - 10)
            let low = fraction(type.lowest) * inner
            let high = fraction(type.highest) * inner
            let middle = proxy.size.height / 2
            Capsule()
                .fill(color.opacity(0.35))
                .frame(width: high - low, height: proxy.size.height)
                .position(x: 5 + (low + high) / 2, y: middle)
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .background {
                    Circle()
                        .fill(Color(.systemBackground).opacity(0.95))
                        .frame(width: 14, height: 14)
                }
                .position(x: 5 + fraction(type.average) * inner, y: middle)
        }
        .frame(height: 6)
        .background(Capsule().fill(.quaternary))
        .accessibilityHidden(true)
    }

    private func fraction(_ price: Double) -> CGFloat {
        CGFloat((price - axis.lowerBound) / (axis.upperBound - axis.lowerBound))
    }
}

/// A line along the middle of its frame, for the dashed rule over the scale.
nonisolated private struct HorizontalRule: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// One ticket: its class, the event, and what it cost.
///
/// Its own type for the reason ``PassportSpanRow`` is: the card shows two and
/// the sheet behind its See All shows the rest.
private struct PassportTicketRow: View {
    /// Which clock the day and times are printed on — see ``TimeDisplay``.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue
    let ticket: PassportStats.Ticket
    /// The currency the card adds up in.
    let currency: String
    let style: SeatStyle

    var body: some View {
        HStack(spacing: 11) {
            SeatBadge(style: style)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: ticket.event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(verbatim: "\(ticket.event.shown(on: timeDisplay).dayLine) · \(ticket.event.venue)")
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Exactly as paid where it was paid in the card's currency; else
            // converted, with what was paid under it.
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: isConverted
                     ? Currencies.format(whole: ticket.price, in: currency)
                     : ticket.paid.formatted)
                    .font(.system(size: 15, weight: .bold))
                    .kerning(-0.3)
                if isConverted {
                    Text(verbatim: ticket.paid.formatted)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var isConverted: Bool { ticket.paid.currency != currency }
}

/// A list of the card's tickets: every ticket under its seat-type filter,
/// behind either See All — dearest first behind Highest Price and cheapest
/// first behind Lowest, each titled for the end it was opened from, as
/// ``PassportExtremesSheet`` is — or every ticket of one class, dearest
/// first, behind its row under By Ticket Type and titled with its name.
///
/// A drawer with the rows ruled off, as ``PassportExtremesSheet`` draws its
/// own: these are events with a figure each, not a ranking with a bar.
private struct PassportTicketSheet: View {
    /// In the order they are listed.
    let tickets: [PassportStats.Ticket]
    let title: Text
    /// The currency the card adds up in.
    let currency: String
    let styles: SeatStyles
    /// The class the card was filtered to, named in the eyebrow; nil for all.
    let seatType: Text?

    @State private var openEvent: Event?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PassportSheetHeader(eyebrow: eyebrow, title: title)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(tickets.enumerated()), id: \.element.id) { index, ticket in
                        if index > 0 { Divider() }
                        Button { openEvent = ticket.event } label: {
                            PassportTicketRow(ticket: ticket, currency: currency,
                                              style: styles[ticket.seatClass])
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .washBackground()
        .presentationDetents([.medium, .large])
        .eventSheet($openEvent)
    }

    private var eyebrow: Text {
        if let seatType {
            Text("^[\(tickets.count) ticket](inflect: true) · \(seatType)")
        } else {
            Text("^[\(tickets.count) ticket](inflect: true)")
        }
    }
}

/// The bar under a ranked row, drawn against the longest in its own list.
///
/// Against the list's own maximum rather than against the library, so the
/// shape of the ranking is legible whether the reader has been to four events
/// or four hundred.
private struct PassportBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(tint.gradient)
                // Never nothing: a row that is in the list has a bar, however
                // far down the ranking it sits.
                .frame(width: max(4, proxy.size.width * min(1, max(0, fraction))))
        }
        .frame(height: 8)
        .background(Capsule().fill(.quaternary))
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        EventPassportView()
    }
    .library(EventStore.preview)
}
