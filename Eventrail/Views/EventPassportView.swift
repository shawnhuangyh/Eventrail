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
/// card used to unfold in place: five nights is a glance, not a destination,
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
/// Everything here is read off ``EventStore/attendedEvents`` — the library's
/// own past — and nothing on this screen asks Eventernote anything. The one
/// number the reader wrote themselves is the lottery count, and it says what it
/// was counted out of rather than presenting a part-filled column as a total.
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
    /// Whether every recorded night is open, rather than the top five.
    @State private var isShowingLotteries = false
    /// The night whose own sheet is open, if the reader tapped one.
    @State private var openEvent: Event?

    /// How much of each ranked list a card shows before sending the rest to a
    /// screen of its own — the same five the Me tab's cards show, for the same
    /// reason.
    private static let cardLimit = 5

    @Query(LibraryEvent.library) private var kept: [LibraryEvent]

    private var attended: [Event] { store.events(of: kept).attended }

    private var stats: PassportStats {
        PassportStats(events: PassportStats.events(attended, in: scope)) {
            store.tracking(for: $0)
        }
    }

    var body: some View {
        ScrollView {
            if attended.isEmpty {
                emptyState
            } else {
                let stats = self.stats
                VStack(spacing: 14) {
                    summaryCard(stats)
                    PassportEventsCard(stats: stats)
                    timeCard(stats)
                    if !stats.topLotteries.isEmpty { lotteryCard(stats) }
                    if !stats.topPerformers.isEmpty { performersCard(stats) }
                    if !stats.topVenues.isEmpty { venuesCard(stats) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .washBackground()
        .navigationTitle("Event Passport")
        // Inline rather than large: iOS 26 draws a large title in the scrolling
        // content, where the year bar inset lands on top of it.
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) { yearBar }
        .task(id: store.revision) { readPlacings() }
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
        .sheet(isPresented: $isShowingLotteries) {
            PassportLotterySheet(rows: stats.topLotteries)
        }
        // A night named on this screen is still an event, and the way to an
        // event is the same sheet every list in the app ends in.
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

    /// A hall drawn at its size: the more nights the reader has spent there,
    /// the larger and the stronger the dot.
    ///
    /// One dot per hall rather than one per night — a hundred nights at the
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
    /// The shortest and longest nights sit in this panel rather than their own:
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

    /// How long an average night runs — over the nights that can say, so the
    /// average is of the same events the total is.
    private func average(_ stats: PassportStats) -> some View {
        let seconds = stats.timedEvents > 0 ? stats.totalDuration / Double(stats.timedEvents) : 0
        return cell(DurationLabel(seconds: seconds), label: "Avg. Time", isFirst: false)
    }

    /// One of the four readings under the total. Ruled off from nothing: four
    /// figures under one number are four ways of saying it, and a rule between
    /// them reads as a boundary that isn't there.
    private func cell(_ value: some View, label: LocalizedStringKey, isFirst: Bool) -> some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, isFirst ? 0 : 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: - The briefest night and the longest

    /// One end of the library, ruled off from whatever sits above it — the
    /// breakdown for the shortest, the shortest for the longest.
    ///
    /// The night itself, and a See All to the other four behind it. One row
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
                // way a ranked row is: the whole line is the night.
                Button { openEvent = first.event } label: { PassportSpanRow(span: first) }
                    .buttonStyle(.plain)
            }
            .padding(.top, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Divider() }
        }
    }

    // MARK: - What the reader wrote down

    /// The nights the reader applied hardest for.
    ///
    /// The one card on this screen counted from something they typed rather
    /// than from something Eventernote published. A night left blank is left
    /// out; a night recorded as zero entries is a night somebody answered — a
    /// seat bought the moment it went on sale — and is shown as the answer it
    /// is.
    ///
    /// Laid out the way the time card is: the card is named for the
    /// measurement rather than for the list, the readings of it sit under
    /// that name, and the ranked nights are ruled off below them under a
    /// heading of their own. The See All belongs to that heading, because it
    /// opens the list rather than the card.
    private func lotteryCard(_ stats: PassportStats) -> some View {
        let rows = Array(stats.topLotteries.prefix(Self.cardLimit))
        let most = max(1, rows.first?.entries ?? 1)
        return VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Lottery Entries")
            // The three readings of the count, drawn as the time card draws
            // its own: the hardest night, what an average one took, and how
            // many nights either was counted over — because the total on the
            // summary above is over the nights the reader answered for rather
            // than over the slice.
            HStack(spacing: 0) {
                cell(Text(stats.mostLotteryEntries.formatted()),
                     label: "Most in One", isFirst: true)
                cell(Text(stats.averageLotteryEntries
                        .formatted(.number.precision(.fractionLength(1)))),
                     label: "Avg. Entries", isFirst: false)
                cell(Text(stats.lotteryEvents.formatted()),
                     label: "Recorded", isFirst: false)
            }

            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Top Lottery Entries")
                        .font(.system(size: 15.5, weight: .bold))
                    Spacer(minLength: 8)
                    if stats.topLotteries.count > Self.cardLimit {
                        Button { isShowingLotteries = true } label: { SeeAllLabel() }
                            .buttonStyle(.plain)
                    }
                }
                ForEach(rows) { row in
                    // A row is the night it names, the way the extremes in the
                    // time card and the ranked cards below are: the whole line
                    // is the target.
                    Button { openEvent = row.event } label: {
                        PassportLotteryRow(row: row, most: most)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Divider() }
        }
        .padding(16)
        .glassPanel(cornerRadius: 28)
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
            Text("Add the events you have been to from My Events or from Search. Once their date has passed they are counted here.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .glassPanel(cornerRadius: 28)
        .padding(.horizontal, 16)
        .padding(.top, 40)
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

/// A length of time, drawn the way the headline over it is: the figures in the
/// text colour and the units dimmed behind them.
///
/// Its own type because the card now says four durations — the total, the
/// average, and the two ends of the library — and the reader should not have
/// to work out that "2h 36m" and "23h 20m" are the same kind of thing.
///
/// "6h 40m", and "45m" for a night under the hour: the leading "0h" is dropped
/// rather than printed.
private struct DurationLabel: View {
    let seconds: TimeInterval
    var size: CGFloat = 16

    private var minutes: Int { Int(seconds / 60) }

    var body: some View {
        // A space in whatever size this is drawn at rather than a fixed
        // number of points: "24h 50m" at 30pt and the same figure at 15pt in
        // a row of nights have to read as the same gap.
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

/// How many nights the slice holds, and how they fell — across the years,
/// across the year, or across the week.
///
/// Its own card rather than another figure in the panel above, because it is
/// the one reading on this screen that is a shape rather than a number: three
/// nights every December and none in between is a fact about the reader that
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
                    // whole nights, but a tick between two of them is the
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

/// One night and how long it ran.
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

/// The whole of one end of the library — up to five nights, briefest or
/// longest first.
///
/// A drawer rather than a pushed screen: the list is short and fixed, and the
/// reader is meant to read it and put it back down where they were, not
/// navigate away from the card that raised the question.
private struct PassportExtremesSheet: View {
    let extreme: PassportExtreme
    let spans: [PassportStats.Span]

    /// A row here opens the night it names, exactly as the row on the card
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
    @Query(LibraryEvent.library) private var kept: [LibraryEvent]

    let ranking: PassportRanking

    /// Read here rather than handed in, for the reason the screen reads it:
    /// one slice, derived from the library, so nothing can be stale.
    private var stats: PassportStats {
        PassportStats(events: PassportStats.events(store.events(of: kept).attended, in: ranking.scope)) {
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
    let title: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                eyebrow
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(title)
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
    /// Shown for performers and not for halls: "18 of your 128 nights" is worth
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

/// One night the reader applied for, how many times, and how that stands
/// against the hardest they ever tried for a seat.
private struct PassportLotteryRow: View {
    /// Which clock the day and times are printed on — see ``TimeDisplay``.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue
    let row: PassportStats.Lottery
    /// The most entries in the list, which is what the bar is drawn against.
    let most: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: row.event.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        // between the bar and the date opens the night rather than nothing.
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Every night the reader wrote a lottery count on, behind the card's See All.
///
/// No stack inside this one, unlike ``PassportRankingSheet``: a row here is a
/// night rather than a name, and the card it came from does not open one
/// either.
private struct PassportLotterySheet: View {
    let rows: [PassportStats.Lottery]

    /// A row here opens the night it names, exactly as the row on the card
    /// does — a drawer over a drawer, the way ``PassportExtremesSheet`` opens
    /// one, so the reader closes the event back onto the list they tapped it
    /// from.
    @State private var openEvent: Event?

    var body: some View {
        let most = max(1, rows.first?.entries ?? 1)

        VStack(alignment: .leading, spacing: 0) {
            // "event" rather than the "night" this file calls one everywhere
            // else: the reader's word for what they applied for, and the word
            // the other two drawers head their own counts with.
            PassportSheetHeader(eyebrow: Text("^[\(rows.count) event](inflect: true) recorded"),
                                title: "Top Lottery Entries")
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
