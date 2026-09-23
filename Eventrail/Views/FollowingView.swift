import SwiftUI

/// Every date Eventernote has published for the performers the reader follows.
///
/// The library tab is what the reader has decided about; this is what is coming
/// that they have not decided about yet. Nothing here is in the library until
/// they put it there, which is what the control on each row is for.
struct FollowingView: View {
    @Environment(EventStore.self) private var store
    @Environment(FollowedDates.self) private var followed
    @Environment(VenueRegions.self) private var venues
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?

    /// Which followed performer the list is narrowed to, or nil for all of
    /// them. Held as an id rather than a profile so unfollowing someone while
    /// their filter is on falls back to all of them rather than to an empty
    /// list of one person who is no longer there.
    @State private var performer: PerformerProfile.ID?
    /// The dates and the areas the list is held to, which is a different
    /// question from whose dates they are — hence the second control.
    @State private var filter = FollowingFilter()
    @State private var isFiltering = false
    @State private var openEvent: Event?

    private var performers: [PerformerProfile] { store.followedPerformers }

    /// The performers the list is currently showing dates for.
    private var shown: [PerformerProfile] {
        guard let performer, let chosen = performers.first(where: { $0.id == performer }) else {
            return performers
        }
        return [chosen]
    }

    /// Everything published for whoever is on screen, before the day and the
    /// areas have their say. Kept apart from ``events`` because the counts have
    /// to be able to name what they are counting out of.
    private var published: [Event] { followed.events(for: shown) }

    private var events: [Event] { narrowed(published) }

    /// Holds a list to the chosen dates and areas. An untouched filter narrows
    /// nothing, so this is the identity until the reader asks for something.
    private func narrowed(_ events: [Event]) -> [Event] {
        guard filter.isNarrowing else { return events }
        return events.filter { filter.matches($0, in: venues.region(of: $0)) }
    }

    /// Broken into months the same way the library's own list is — ``events``
    /// is already date-ordered, which is all ``EventGroup/byMonth(_:)`` asks of
    /// its caller.
    private var groups: [EventGroup] {
        EventGroup.byMonth(events)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if performers.isEmpty {
                        nobodyFollowed
                    } else {
                        filters
                        // The whole screen goes to the failure only when there
                        // is nothing cached to fall back on. Otherwise the last
                        // copy stays up and the failure goes under it.
                        if let failure = followed.failure, !holdsAnything {
                            SearchFailure(message: failure) { await reload() }
                        } else if groups.isEmpty {
                            if followed.isLoading {
                                SearchProgress()
                            } else if filter.isNarrowing {
                                nothingMatches
                            } else {
                                noDatesPublished
                            }
                            failureNote
                        } else {
                            months
                            if followed.isLoading { SearchProgress(compact: true) }
                            failureNote
                            footnote
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .washBackground()
            .navigationTitle("Following")
            .navigationSubtitle(subtitle)
            .toolbar {
                if !performers.isEmpty {
                    ToolbarItem(placement: .primaryAction) { filterButton }
                }
            }
            .performerDestination()
            .eventSheet($openEvent)
            .sheet(isPresented: $isFiltering) {
                FollowingFilterSheet(filter: $filter, events: published)
            }
            .refreshable { await reload() }
            // Following someone on their page should show their dates here on
            // the way back, so this follows the list rather than only the first
            // appearance of the screen — and the cache's generation with it,
            // so clearing it from Settings reads the dates again rather than
            // leaving this tab looking as though nobody has any.
            .task(id: followed.loadKey(for: performers)) { await load() }
        }
    }

    /// What the tab adds up to: how many people, and how much they have coming.
    /// While the filter is narrowing, how much of it is on screen — a count
    /// that dropped without saying what it dropped out of would read as dates
    /// having gone missing.
    private var subtitle: Text {
        guard !performers.isEmpty else { return Text("Nobody followed yet") }
        let people = Text("^[\(performers.count) performer](inflect: true)")
        guard filter.isNarrowing else {
            let dates = Text("^[\(followed.events(for: performers).count) event](inflect: true)")
            return Text("\(people) · \(dates)")
        }
        let shown = Text("\(events.count) of \(Text("^[\(published.count) event](inflect: true)"))")
        return Text("\(people) · \(shown)")
    }

    /// The way into the dates and the areas. Filled in and tinted while it is
    /// holding something back, so a short list is never a mystery.
    private var filterButton: some View {
        Button {
            isFiltering = true
        } label: {
            Label("Filter Dates",
                  systemImage: filter.isNarrowing
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
        }
        .tint(filter.isNarrowing ? Color.brandTint : nil)
    }

    /// Whether anything at all is cached for the people followed — the line
    /// between a refresh that failed over a list the reader can still read and
    /// one that left them with nothing.
    private var holdsAnything: Bool {
        performers.contains { followed.count(for: $0) != nil }
    }

    @ViewBuilder private var failureNote: some View {
        if let failure = followed.failure, !followed.isLoading {
            RefreshFailureNote(message: failure)
                .padding(.horizontal, 16)
                .padding(.top, 4)
        }
    }

    // MARK: - Loading

    private func load() async {
        // Only when something was stale enough to read: opening the tab on a
        // fresh copy reads nothing, and says nothing.
        if let outcome = await followed.load(for: performers) {
            notices?.post(.following(outcome))
        }
        let dates = followed.events(for: performers)
        store.remember(dates)
        // The library is full of halls whose pages have already been read, and
        // a hall is the same hall whichever list it turned up in.
        venues.learn(from: store.library)
    }

    private func reload() async {
        if let outcome = await followed.reload(for: performers) {
            notices?.post(.following(outcome))
        }
        store.remember(followed.events(for: performers))
    }

    // MARK: - Narrowing to one of them

    /// One chip per followed performer, each carrying what it would leave on
    /// screen. A count that is still being read shows nothing rather than a
    /// zero it would have to take back.
    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(label: Text("All"),
                     count: narrowed(followed.events(for: performers)).count,
                     isOn: performer == nil) { performer = nil }

                ForEach(performers) { followee in
                    chip(label: Text(verbatim: followee.name),
                         count: count(for: followee),
                         isOn: performer == followee.id) { performer = followee.id }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    /// What one performer would leave on screen — which is not the same as what
    /// they have published once a day or an area is chosen. Still nil while
    /// their listing has not been read: "none of them match" and "not asked
    /// yet" are different things to say.
    private func count(for followee: PerformerProfile) -> Int? {
        guard followed.count(for: followee) != nil else { return nil }
        return narrowed(followed.events(for: [followee])).count
    }

    private func chip(
        label: Text, count: Int?, isOn: Bool, choose: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.snappy) { choose() }
        } label: {
            HStack(spacing: 7) {
                label
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? Color.brandTint : .secondary)
                    .lineLimit(1)
                if let count {
                    Text(count.formatted())
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .glassCapsule(interactive: true)
    }

    // MARK: - The dates themselves

    /// Sectioned and pinned, the way the library tab's own months are: a long
    /// list of published dates is read by month, so the month being read stays
    /// on screen while it is being read.
    private var months: some View {
        LazyVStack(alignment: .leading, spacing: 9, pinnedViews: .sectionHeaders) {
            ForEach(groups) { group in
                Section {
                    ForEach(group.events) { event in
                        FollowedDateRow(event: event,
                                        billing: followed.billed(on: event, among: performers)) {
                            openEvent = event
                        }
                        .padding(.horizontal, 16)
                    }
                } header: {
                    GroupHeader(label: Text(group.label), count: group.events.count)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - When there is nothing to show

    /// Three different silences, told apart: nobody to follow dates for, nobody
    /// who has any, and a filter that has left none of them on screen.
    private var nobodyFollowed: some View {
        ContentUnavailableView {
            Label("Nobody Followed", systemImage: "person.2")
        } description: {
            Text("Follow a performer from their page and every date Eventernote publishes for them shows up here.")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var noDatesPublished: some View {
        ContentUnavailableView {
            Label("No Dates Published", systemImage: "calendar")
        } description: {
            Text("Eventernote has published nothing upcoming for the performers you follow. New dates appear here as they are listed.")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var nothingMatches: some View {
        ContentUnavailableView {
            Label("Nothing in That Range", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No published date falls in the dates and areas you picked. Nothing has been removed — widen the filter to see the rest.")
        } actions: {
            Button("Clear Filter") {
                withAnimation(.snappy) { filter = FollowingFilter() }
            }
            .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var footnote: some View {
        Footnote(Text("Dates come from publicly accessible Eventernote pages. Following is kept in your own library — nothing is written back."))
            .padding(.horizontal, 26)
            .padding(.top, 6)
    }
}

// MARK: - What the list is held to

/// What the Following tab is narrowed to beyond the performer chips: a span of
/// days, and whichever parts of the country the reader picked.
///
/// Both start empty, and empty narrows nothing: the tab opens on everything
/// that is coming, which is what it is for.
struct FollowingFilter: Equatable {
    /// The span of days the list is held to, both ends included, or nil for
    /// every published date.
    var days: ClosedRange<Date>?
    /// The areas the list is held to. Empty means anywhere — which is not the
    /// same as every case of ``Region``, because a hall nothing has placed is
    /// in none of them.
    var areas: Set<Region> = []
    /// Whether the halls nothing has placed are shown too. Kept apart from
    /// ``areas`` because "nowhere the site names" is not an area: it is a hall
    /// whose page has not been read yet, or one abroad, and an event is never
    /// filed under an area it might not be in.
    var unplaced = false

    var isNarrowing: Bool { days != nil || !areas.isEmpty || unplaced }

    /// Whether an event survives the filter, given whatever is known about
    /// where its hall is.
    func matches(_ event: Event, in region: Region?) -> Bool {
        if let days, !event.falls(in: days) { return false }
        guard !areas.isEmpty || unplaced else { return true }
        guard let region else { return unplaced }
        return areas.contains(region)
    }
}

/// The dates and the areas, picked out of a sheet rather than a menu: a
/// calendar is the control for choosing a date, and a menu is not big enough to
/// hold one — let alone the two ends of a range.
private struct FollowingFilterSheet: View {
    @Environment(VenueRegions.self) private var venues
    @Environment(\.dismiss) private var dismiss

    @Binding var filter: FollowingFilter
    /// Everything the tab would show if this narrowed nothing — what every
    /// count in here is counted out of.
    let events: [Event]

    /// How the dates break down by area, with the halls nothing has placed
    /// counted under nil.
    private var tally: [Region?: Int] { venues.tally(events) }

    /// The span the calendars offer: the first published date to the last, as
    /// the reader's own calendar writes them — see ``Event/localDay``. There is
    /// no sense in offering a month nobody is playing in.
    /// What the range opens on: tomorrow, through to the furthest published
    /// date.
    ///
    /// Tomorrow rather than the soonest published date, so that the range opens
    /// on the same day whoever is on screen — the soonest date moves with the
    /// performer chips, and a start that shifts about as the list is narrowed
    /// is not a default the reader can hold in their head. It is clamped to the
    /// far end, because a span that has already run out would otherwise be
    /// handed a start later than its end.
    private var opening: ClosedRange<Date> {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1,
                                     to: calendar.startOfDay(for: .now)) ?? span.lowerBound
        return min(tomorrow, span.upperBound) ... span.upperBound
    }

    private var span: ClosedRange<Date> {
        let days = events.map(\.localDay)
        guard let first = days.min(), let last = days.max(), first <= last else {
            return Date.distantPast ... Date.distantFuture
        }
        return first ... last
    }

    /// The range the calendar reads and writes. Nil stands for the whole
    /// published span, so the calendar never has to draw an absent range.
    private var chosenDays: Binding<ClosedRange<Date>> {
        Binding(get: { filter.days ?? opening }, set: { filter.days = $0 })
    }

    /// What the calendar will let the reader page to: the published span,
    /// widened to hold a range they set earlier. Narrowing to one performer
    /// shortens the span, and a picker whose own selection sits outside its
    /// bounds has nothing sensible to show.
    private var reachable: Range<Date> {
        let days = filter.days ?? opening
        let first = min(span.lowerBound, days.lowerBound)
        let last = max(span.upperBound, days.upperBound)
        let calendar = Calendar.current
        // Half-open, so the last published day has to be a day short of the
        // end or it could not be picked.
        return calendar.startOfDay(for: first)
            ..< (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) ?? last)
    }

    /// The switch itself. Turning it on starts on tomorrow through to the
    /// furthest published date, so nothing ahead disappears at the moment it is
    /// switched on: the reader pulls the ends in from there.
    private var isFilteringByDate: Binding<Bool> {
        Binding(get: { filter.days != nil },
                set: { isOn in filter.days = isOn ? opening : nil })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(label: "When")
                    datesCard

                    SectionLabel(label: "Where")
                        .padding(.top, 6)
                    areaCard
                    areaFootnote
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .washBackground()
            .navigationTitle("Filter")
            .navigationSubtitle(subtitle)
            .presentationDragIndicator(.visible)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        withAnimation(.snappy) { filter = FollowingFilter() }
                    }
                    .disabled(!filter.isNarrowing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Where the halls actually get read. Asked for here rather than
            // when the tab loads, so a reader who never filters never costs the
            // site a request — and so the ones asked about are the ones on
            // screen.
            //
            // A run is rationed, so this keeps starting them for as long as the
            // sheet is open and each one gets somewhere: the counts fill in
            // while the reader watches rather than waiting on them closing the
            // sheet and opening it again, which nothing tells them to do. A run
            // that placed nothing means the site stopped answering, and pressing
            // it further would only make that worse.
            .task {
                while !Task.isCancelled {
                    let waiting = venues.pendingCount(events)
                    guard waiting > 0 else { return }
                    await venues.place(events)
                    guard venues.pendingCount(events) < waiting else { return }
                }
            }
        }
    }

    private var subtitle: Text {
        let matching = events.filter { filter.matches($0, in: venues.region(of: $0)) }.count
        return Text("\(matching) of \(Text("^[\(events.count) event](inflect: true)"))")
    }

    // MARK: - One day

    private var datesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: isFilteringByDate.animation(.snappy)) {
                Text("Date Range")
                    .font(.system(size: 14, weight: .semibold))
            }
            .tint(Color.trackAttended)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            if filter.days != nil {
                Divider()
                VStack(spacing: 12) {
                    ends
                    RangeCalendar(days: chosenDays, in: reachable)
                }
                .padding(.horizontal, 16)
                .padding(.top, 13)
                .padding(.bottom, 15)
            }
        }
        .glassPanel()
    }

    /// The two ends, written out over the calendar. The calendar says which
    /// days they are; this says which dates, because a numbered cell in a grid
    /// does not carry its month or its year.
    private var ends: some View {
        let days = chosenDays.wrappedValue
        return HStack(spacing: 9) {
            endPill(days.lowerBound)
            Text(verbatim: "–")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
            endPill(days.upperBound)
        }
        .frame(maxWidth: .infinity)
    }

    /// The month is abbreviated and the line is held to one: "September 19,
    /// 2026" does not fit beside its other half at this size, and a date broken
    /// over two lines reads as two dates. Where even the short form will not go
    /// — a long locale, or large type — it scales down rather than wrapping.
    ///
    /// A flat fill rather than a second pane of glass: this sits on the card,
    /// and glass on glass is the one thing the material is not for.
    private func endPill(_ day: Date) -> some View {
        Text(day.formatted(.dateTime.month(.abbreviated).day().year()))
            .font(.system(size: 13.5, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.fill.tertiary, in: .rect(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Where in the country

    /// Every area the site has, whether or not anything has landed in one yet.
    ///
    /// The list is ``Region/allCases`` rather than the areas the tally has
    /// found, because the halls are read while the sheet is open: a list of
    /// what is placed so far would grow a row at a time under the reader's
    /// thumb, moving whatever they were reaching for. Fixed rows and a count
    /// that climbs says the same thing without the list ever changing shape.
    private var areaCard: some View {
        VStack(spacing: 0) {
            let unplaced = tally[Region?.none] ?? 0

            ForEach(Region.allCases) { region in
                row(isOn: filter.areas.contains(region),
                    showsDivider: region != Region.allCases.first,
                    title: Text(region.label),
                    detail: Text(region.detail),
                    count: tally[region] ?? 0) {
                    if filter.areas.contains(region) {
                        filter.areas.remove(region)
                    } else {
                        filter.areas.insert(region)
                    }
                }
            }

            // The one row that is not a fixed part of the country. It starts
            // holding everything and empties as the halls are read, so it is
            // dropped only once it has nothing left to offer — and kept while
            // it is picked, so a filter in force never loses its own control.
            if unplaced > 0 || filter.unplaced {
                row(isOn: filter.unplaced,
                    showsDivider: true,
                    title: Text("Not Placed"),
                    detail: unplacedDetail,
                    count: unplaced) {
                    filter.unplaced.toggle()
                }
            }
        }
        .glassPanel()
    }

    /// Why a hall might have no area, said plainly — it is either still being
    /// read or genuinely outside the site's areas, and the reader can see which
    /// from whether the count keeps falling.
    private var unplacedDetail: Text {
        venues.isPlacing
            ? Text("Reading these venues from Eventernote…")
            : Text("Venues Eventernote files under no area, or none it published")
    }

    private func row(
        isOn: Bool, showsDivider: Bool, title: Text, detail: Text, count: Int,
        choose: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.snappy) { choose() }
        } label: {
            HStack(spacing: 12) {
                SelectionMark(isSelected: isOn)
                VStack(alignment: .leading, spacing: 3) {
                    title
                        .font(.system(size: 14, weight: .semibold))
                    detail
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(count.formatted())
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if showsDivider { Divider().padding(.leading, 48) }
        }
    }

    private var areaFootnote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Pick none and every area is shown. Areas are Eventernote's own, read from each venue's page — a venue it files under no area counts as Not Placed.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if venues.isPlacing {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
    }
}

/// The month grid the date range is pulled about on.
///
/// `MultiDatePicker` is the system's own calendar — its month paging, its
/// weekday heads, its locale and its accessibility — and it deals in a *set* of
/// days rather than a span. So the span is handed to it as every day in it, and
/// the set it hands back is only ever read for which day the reader touched.
/// Two touches then make the range, the way every calendar that picks one
/// works: see ``choose(_:)``.
private struct RangeCalendar: View {
    @Binding var days: ClosedRange<Date>
    /// The days the calendar will page to — see the sheet's `reachable`.
    let bounds: Range<Date>

    private let calendar = Calendar.current

    /// What `MultiDatePicker` matches its own days against. The calendar and
    /// the era belong in it: the picker fills both in on everything it hands
    /// back, and a set built without them matches none of it.
    private static let fields: Set<Calendar.Component> = [.calendar, .era, .year, .month, .day]

    init(days: Binding<ClosedRange<Date>>, in bounds: Range<Date>) {
        _days = days
        self.bounds = bounds
    }

    /// Whether the range is waiting on its second touch.
    private var isHalfPicked: Bool {
        calendar.isDate(days.lowerBound, inSameDayAs: days.upperBound)
    }

    var body: some View {
        MultiDatePicker("Date range", selection: picked, in: bounds)
            .labelsHidden()
    }

    private var picked: Binding<Set<DateComponents>> {
        Binding(get: { everyDay(in: days) }, set: { touched in
            let changed = touched.symmetricDifference(everyDay(in: days))
            let day = changed.compactMap(calendar.date(from:)).min()
            if let day { choose(day) }
        })
    }

    /// The span written out one day at a time, which is the only shape the
    /// system calendar takes a selection in.
    private func everyDay(in span: ClosedRange<Date>) -> Set<DateComponents> {
        var days: Set<DateComponents> = []
        var day = calendar.startOfDay(for: span.lowerBound)
        let last = calendar.startOfDay(for: span.upperBound)
        while day <= last {
            days.insert(calendar.dateComponents(Self.fields, from: day))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// Two touches make a range: the first closes it onto the day it runs
    /// from, the second opens it out to the day it runs to. A touch on a range
    /// already made starts the next one.
    ///
    /// The nearer end used to move to the day touched instead, which reads
    /// well over a fortnight and falls apart over a year — the second touch of
    /// a short range is nearly always nearer the end just set than the far one,
    /// so it moved that same end again and the range could never be closed.
    ///
    /// Whichever way round the two touches come, the earlier day is the start:
    /// the range is built from the pair rather than assigned to an end, so
    /// there is no way to hand it a start later than its end.
    private func choose(_ day: Date) {
        guard isHalfPicked else {
            days = day ... day
            return
        }
        let anchor = days.lowerBound
        days = day < anchor ? day ... anchor : anchor ... day
    }
}

/// One published date, captioned with whichever followed performers are billed
/// on it. Tapping the caption opens that performer; the circular control adds
/// the event to the library, or takes it out again.
private struct FollowedDateRow: View {
    let event: Event
    let billing: [PerformerProfile]
    let open: () -> Void

    var body: some View {
        EventRowContent(event: event, detail: event.timeDetail) {
            if let first = billing.first {
                // The whole caption leads to the first name on it. Two followed
                // performers sharing a bill is the uncommon case, and a row is
                // not the place to make the reader choose between them — their
                // own page is one tap further on either way.
                NavigationLink(value: PerformerLink.profile(first)) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.brandTint)
                            .frame(width: 6, height: 6)
                        Text(verbatim: billing.map(\.name).joined(separator: " · "))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color.brandTint)
                            .lineLimit(1)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        } trailing: {
            LibraryToggle(event: event)
        }
        .contentShape(.rect)
        .onTapGesture(perform: open)
        .glassPanel()
    }
}

#Preview {
    FollowingView()
        .environment(EventStore.preview)
        .environment(FollowedDates.preview)
        .environment(VenueRegions.preview)
}
