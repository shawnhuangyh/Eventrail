import SwiftData
import SwiftUI

/// Every date Eventernote has published for the performers the reader follows.
///
/// The library tab is what the reader has decided about; this is what is coming
/// that they have not decided about yet. Nothing here is in the library until
/// they put it there, which is what the control on each row is for.
///
/// It is also read the way a mailbox is: a date the reader has not looked at
/// carries a dot until they open it, swipe it, or mark it with others — and a
/// date the listing has since changed carries one again. See
/// ``FollowingRead``.
struct FollowingView: View {
    @Environment(EventStore.self) private var store
    @Environment(FollowedDates.self) private var followed
    @Environment(VenueRegions.self) private var venues
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?
    @Environment(\.scenePhase) private var scenePhase

    /// Which followed performer the list is narrowed to, or nil for all of
    /// them. Held as an id rather than a profile so unfollowing someone while
    /// their filter is on falls back to all of them rather than to an empty
    /// list of one person who is no longer there.
    @State private var performer: PerformerProfile.ID?
    /// How far ahead and which areas the list is held to, which is a
    /// different question from whose dates they are — hence the second
    /// control.
    @State private var filter = FollowingFilter()
    @State private var openEvent: Event?
    /// When the list was last pulled down, so the flyers on it are asked about
    /// again with the rows — see ``EnvironmentValues/imagesCheckedSince``.
    @State private var imagesCheckedSince: Date?
    /// Held here rather than left to `NavigationLink`: a link inside a `List`
    /// row takes the whole row over, and the row's own tap opens the event.
    @State private var path = NavigationPath()

    /// Whether only the dates the reader has not looked at are shown.
    @State private var unreadOnly = false
    /// Dates marked read while ``unreadOnly`` is on. They stay on screen until
    /// the filter is turned off, the way Mail keeps a message it has just
    /// opened: a row vanishing under the thumb that swiped it reads as lost.
    @State private var readWhileFiltering: Set<Event.ID> = []

    /// Picking dates to mark. While this is on, a tap chooses a row rather
    /// than opening it.
    @State private var isSelecting = false
    @State private var selection: Set<Event.ID> = []

    @Query(FollowedPerformer.followed) private var followedRows: [FollowedPerformer]
    @Query(LibraryEntry.library) private var kept: [LibraryEntry]

    private var performers: [PerformerProfile] { followedRows.profiles }

    /// The performers the list is currently showing dates for.
    private var shown: [PerformerProfile] {
        guard let performer, let chosen = performers.first(where: { $0.id == performer }) else {
            return performers
        }
        return [chosen]
    }

    /// Everything published for whoever is on screen, before the filter has
    /// its say. Kept apart from ``events`` because the counts have
    /// to be able to name what they are counting out of.
    private var published: [Event] { followed.events(for: shown) }

    private var events: [Event] { narrowed(published) }

    /// Holds a list to the chosen window and areas, then to the unread ones if
    /// that is asked for. An untouched filter narrows nothing, so this is the
    /// identity until the reader asks for something.
    private func narrowed(_ events: [Event]) -> [Event] {
        let placed = filtered(events)
        guard unreadOnly else { return placed }
        return placed.filter { store.isUnread($0) || readWhileFiltering.contains($0.id) }
    }

    /// The filter alone — what tells "nothing matches" from "nothing unread"
    /// when the list comes up empty.
    private func filtered(_ events: [Event]) -> [Event] {
        guard filter.isNarrowing else { return events }
        return events.filter { filter.matches($0, in: venues.region(of: $0)) }
    }

    /// Broken into months the same way the library's own list is — ``events``
    /// is already date-ordered, which is all ``EventGroup/byMonth(_:)`` asks of
    /// its caller.
    private var groups: [EventGroup] {
        EventGroup.byMonth(events)
    }

    /// Selecting reaches what is on screen and no further, as it does in My
    /// Events.
    private var shownIDs: Set<Event.ID> { Set(events.map(\.id)) }

    private var chosen: [Event] { events.filter { selection.contains($0.id) } }

    private var unreadCount: Int {
        followed.events(for: performers).count(where: store.isUnread)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List(selection: $selection) {
                if performers.isEmpty {
                    nobodyFollowed.bareRow()
                } else {
                    // A section of its own with no gap after it: the gap a
                    // month opens with is for the month before it, not for
                    // the chips.
                    Section {
                        filters
                            .disabled(isSelecting)
                            .bareRow(EdgeInsets(top: 8, leading: 0, bottom: 14, trailing: 0))
                    }
                    .listSectionSpacing(0)
                    // The whole screen goes to the failure only when there is
                    // nothing cached to fall back on. Otherwise the last copy
                    // stays up and the failure goes under it.
                    if let failure = followed.failure, !holdsAnything {
                        SearchFailure(message: failure) { await reload() }.bareRow()
                    } else if groups.isEmpty {
                        Group {
                            if followed.isLoading {
                                SearchProgress()
                            } else if filter.isNarrowing, filtered(published).isEmpty {
                                nothingMatches
                            } else if unreadOnly, !published.isEmpty {
                                allRead
                            } else {
                                noDatesPublished
                            }
                        }
                        .bareRow()
                        failureNote
                    } else {
                        months
                        if followed.isLoading { SearchProgress(compact: true).bareRow() }
                        failureNote
                        footnote
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // On the list itself, inside the destinations and the sheet below.
            // A `.refreshable` is carried down the environment into whatever is
            // pushed or presented from beneath it, and a performer's page or an
            // event's sheet opened from here answered a pull by re-reading
            // every followed listing; those read themselves again from Refresh
            // in their own menus — see ``RefreshMenuItem``.
            .refreshable { await reload() }
            // Drawn here rather than by the tab, inside the room the capsule
            // leaves, so a notice stands above the capsule rather than over it
            // — see ``refreshNotices(aboveBar:showing:)``.
            .refreshNotices(aboveBar: true)
            // Over the tab bar, in the middle, as the Search tab's stands over
            // its field: the tab's own content stops short of the bar, so the
            // capsule rests just above it, and the dates scroll clear of it.
            .safeAreaInset(edge: .bottom) {
                if !performers.isEmpty, !isSelecting { filterCapsule }
            }
            .monthSections()
            .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
            .washBackground()
            .navigationTitle("Following")
            .navigationSubtitle(subtitle)
            // Selecting takes the bottom of the screen over, as it does in My
            // Events: the tab bar stands down for the actions on what is picked.
            .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
            .toolbar { toolbar }
            .performerDestination()
            .eventSheet($openEvent)
            // The tab's own load places a ration of halls, which a list held
            // to areas can outrun: what nothing has placed is under Not Placed
            // until it is. So while the list is held to any, halls go on
            // being placed for as long as each run gets somewhere. A run that
            // placed nothing means the site stopped answering, and pressing it
            // further would only make that worse.
            .task(id: filter.holdsAreas) {
                while filter.holdsAreas, !Task.isCancelled {
                    let waiting = venues.pendingCount(published)
                    guard waiting > 0 else { return }
                    await venues.settle(published)
                    guard venues.pendingCount(published) < waiting else { return }
                }
            }
            // Following someone on their page should show their dates here on
            // the way back, so this follows the list rather than only the first
            // appearance of the screen — and the cache's generation with it,
            // so clearing it from Settings reads the dates again rather than
            // leaving this tab looking as though nobody has any.
            .task(id: followed.loadKey(for: performers)) { await load() }
            // Coming back to the app is the other moment a listing may have
            // gone stale under a screen already open; only those are read.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await load() } }
            }
            // Turning the filter off lets go of what it was keeping, and
            // turning it back on starts from what is unread now.
            .onChange(of: unreadOnly) { readWhileFiltering.removeAll() }
            .onChange(of: isSelecting) { selection.removeAll() }
            // Nothing stays picked behind a filter that no longer shows it.
            .onChange(of: shownIDs) { _, shown in selection.formIntersection(shown) }
            .environment(\.imagesCheckedSince, imagesCheckedSince)
        }
    }

    /// What the tab adds up to: how many people, and how much they have coming.
    /// While the filter is narrowing, how much of it is on screen — a count
    /// that dropped without saying what it dropped out of would read as dates
    /// having gone missing.
    private var subtitle: Text {
        guard !performers.isEmpty else { return Text("Nobody followed yet") }
        if isSelecting {
            return selection.isEmpty
                ? Text("Select events to mark")
                : Text("^[\(selection.count) event](inflect: true) selected")
        }
        let people = Text("^[\(performers.count) performer](inflect: true)")
        guard filter.isNarrowing || unreadOnly else {
            let dates = Text("^[\(followed.events(for: performers).count) event](inflect: true)")
            let unread = unreadCount
            guard unread > 0 else { return Text("\(people) · \(dates)") }
            return Text("\(people) · \(dates) · \(unread) unread")
        }
        let shown = Text("\(events.count) of \(Text("^[\(published.count) event](inflect: true)"))")
        return Text("\(people) · \(shown)")
    }

    // MARK: - The bar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if !performers.isEmpty {
            if isSelecting {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done", systemImage: "checkmark") { isSelecting = false }
                }
                // Where Mail keeps it: the pick-everything control opposite
                // the way out.
                ToolbarItem(placement: .topBarLeading) {
                    Button(selection == shownIDs ? "Deselect All" : "Select All") {
                        selection = selection == shownIDs ? [] : shownIDs
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    markButton
                    Spacer()
                }
            } else {
                // Picking rows is a different act from narrowing them, and
                // stands apart. The areas are in the capsule over the tab bar.
                ToolbarItem(placement: .primaryAction) { unreadButton }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    Button("Select Events", systemImage: "pencil") { isSelecting = true }
                        .disabled(events.isEmpty)
                }
            }
        }
    }

    private var markButton: MarkReadButton {
        let picked = chosen
        let marksRead = picked.isEmpty || picked.contains(where: store.isUnread)
        return MarkReadButton(marksRead: marksRead, isEnabled: !picked.isEmpty) {
            mark(picked, read: marksRead)
        }
    }

    /// Only the dates not looked at yet. Filled in and tinted while it is on,
    /// so a short list is never a mystery.
    private var unreadButton: some View {
        Button {
            withAnimation(.snappy) { unreadOnly.toggle() }
        } label: {
            Label(unreadOnly ? "Show All Events" : "Show Unread Only",
                  systemImage: unreadOnly ? "envelope.badge.fill" : "envelope.badge")
        }
        .tint(unreadOnly ? Color.brandTint : nil)
    }

    // MARK: - The capsule

    /// The capsule over the tab bar — see ``ListMenu`` — holding the filter,
    /// without the order the Search tab's holds: the dates here run one way,
    /// soonest first. Its face says what the list is held to.
    private var filterCapsule: some View {
        ListMenu(describes: "Filter", value: filterSummary) {
            // In each submenu the choice that holds nothing back stands above
            // a divider and the ones that do below it, as on the Search tab.
            Section("Filter") {
                Menu {
                    Toggle(isOn: menuChoice($filter.window, .any)) { Text(FollowingFilter.Window.any.label) }
                    Section {
                        ForEach(FollowingFilter.Window.allCases.filter { $0 != .any }, id: \.self) { window in
                            Toggle(isOn: menuChoice($filter.window, window)) { Text(window.label) }
                        }
                    }
                } label: {
                    Label("Date", systemImage: "calendar")
                    Text(filter.window.label)
                }
                Menu {
                    // Several can be picked, so the menu stays open while
                    // they are.
                    Toggle(isOn: Binding(get: { !filter.holdsAreas },
                                         set: { if $0 { filter.areas = []; filter.unplaced = false } })) {
                        Text("Anywhere")
                    }
                    Section {
                        ForEach(Region.allCases) { region in
                            Toggle(isOn: picking(region)) {
                                Text(region.label)
                                Text("^[\(tally[region] ?? 0) event](inflect: true)")
                            }
                            .menuActionDismissBehavior(.disabled)
                        }
                        // Only while it has anything, or is picked: it empties
                        // as the halls are read.
                        if (tally[Region?.none] ?? 0) > 0 || filter.unplaced {
                            Toggle(isOn: $filter.unplaced) {
                                Text("Not Placed")
                                Text("^[\(tally[Region?.none] ?? 0) event](inflect: true)")
                            }
                            .menuActionDismissBehavior(.disabled)
                        }
                    }
                } label: {
                    Label("Area", systemImage: "map")
                    areaSummary
                }
            }
        } face: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(filter.isNarrowing ? Color.brandTint : .secondary)
                filterSummary
                    .foregroundStyle(filter.isNarrowing ? Color.brandTint : .primary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// What the list is held to, in as few words as will say it: how far
    /// ahead, and where.
    private var filterSummary: Text {
        var parts: [Text] = []
        if filter.window != .any { parts.append(Text(filter.window.label)) }
        if filter.holdsAreas { parts.append(areaSummary) }
        guard let first = parts.first else { return Text("All") }
        return parts.dropFirst().reduce(first) { Text("\($0) · \($1)") }
    }

    /// How the dates inside the window break down by area, with the halls
    /// nothing has placed counted under nil — what each area in the menu
    /// would leave.
    private var tally: [Region?: Int] {
        venues.tally(published.filter { filter.window.contains($0) })
    }

    /// One area, picked or let go of beside the others.
    private func picking(_ region: Region) -> Binding<Bool> {
        Binding(get: { filter.areas.contains(region) },
                set: { isOn in
                    if isOn { filter.areas.insert(region) } else { filter.areas.remove(region) }
                })
    }

    /// The areas picked, in as few words as will say them.
    private var areaSummary: Text {
        var names = Region.allCases.filter(filter.areas.contains).map { Text($0.label) }
        if filter.unplaced { names.append(Text("Not Placed")) }
        switch names.count {
        case 0: return Text("Anywhere")
        case 1: return names[0]
        default: return Text("^[\(names.count) area](inflect: true)")
        }
    }

    // MARK: - Read and unread

    private func open(_ event: Event) {
        mark([event], read: true)
        openEvent = event
    }

    private func mark(_ events: [Event], read: Bool) {
        withAnimation(.snappy) {
            if read, unreadOnly { readWhileFiltering.formUnion(events.map(\.id)) }
            store.markRead(events, read: read)
        }
        if isSelecting { isSelecting = false }
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
                .bareRow(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))
        }
    }

    // MARK: - Loading

    private func load() async {
        // Only when something was stale enough to read: opening the tab on a
        // fresh copy reads nothing, and says nothing. The app started this
        // one, so only a failure is worth a notice.
        if let outcome = await followed.load(for: performers) {
            notices?.report(.following(outcome), byHand: false)
        }
        await venues.settle(arrivedDates())
    }

    private func reload() async {
        imagesCheckedSince = .now
        if let outcome = await followed.reload(for: performers) {
            notices?.report(.following(outcome), byHand: true)
        }
        // A pull can bring a hall abroad nothing has dated yet, and until its
        // clock is settled the row reads on Tokyo time. Settled as a load
        // settles them, but not inside the pull: looking halls up is paced, and
        // the spinner is for the listings the reader asked for.
        let dates = arrivedDates()
        Task { await venues.settle(dates) }
    }

    /// What the listings now hold, handed to the store and with every hall
    /// the library already knows learnt — what a load and a pull both do with
    /// what arrived before their halls are settled.
    private func arrivedDates() -> [Event] {
        let dates = followed.events(for: performers)
        store.remember(dates)
        // The library is full of halls whose pages have already been read, and
        // a hall is the same hall whichever list it turned up in.
        venues.learn(from: store.events(of: kept, where: \.inLibrary))
        return dates
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
            // The count on the name's baseline, as a count beside a title is
            // everywhere else; centred on it, the smaller figure rode high.
            HStack(alignment: .firstTextBaseline, spacing: 7) {
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

    /// Sectioned, and so pinned the way the library tab's own months are: a
    /// long list of published dates is read by month, so the month being read
    /// stays on screen while it is being read.
    @ViewBuilder private var months: some View {
        ForEach(groups) { group in
            Section {
                ForEach(group.events) { event in
                    let unread = store.unread(event)
                    let isUnread = unread != nil
                    FollowedDateRow(event: event,
                                    billing: followed.billed(on: event, among: performers),
                                    unread: unread,
                                    showPerformer: { path.append(PerformerLink.profile($0)) },
                                    open: { open(event) })
                        // In edit mode the row belongs to the selection, not to
                        // the sheet or to the controls drawn on it.
                        .allowsHitTesting(!isSelecting)
                        .listRowInsets(GroupHeader.rowInsets)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        // Toward the dot, as in Mail: a swipe from the leading
                        // edge reads the row, or unreads it.
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                mark([event], read: isUnread)
                            } label: {
                                Label(isUnread ? "Read" : "Unread",
                                      systemImage: isUnread ? "envelope.open" : "envelope.badge")
                            }
                            .tint(Color.brandTint)
                        }
                }
            } header: {
                GroupHeader(label: Text(group.label), count: group.events.count)
                    .listRowInsets(GroupHeader.insets)
            }
        }
    }

    // MARK: - When there is nothing to show

    /// Four different silences, told apart: nobody to follow dates for, nobody
    /// who has any, a filter that has left none of them on screen, and nothing
    /// left unread.
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
            Label("No Matching Events", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No published date matches the filter. Nothing has been removed — widen it to see the rest.")
        } actions: {
            Button("Clear Filter") {
                withAnimation(.snappy) { filter = FollowingFilter() }
            }
            .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var allRead: some View {
        ContentUnavailableView {
            Label("No Unread Events", systemImage: "envelope.open")
        } description: {
            Text("You have looked at every date here. New dates, and dates Eventernote changes, show up as unread.")
        } actions: {
            Button("Show All Events") {
                withAnimation(.snappy) { unreadOnly = false }
            }
            .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var footnote: some View {
        Footnote(Text("Dates come from publicly accessible Eventernote pages. Following is kept in your own library — nothing is written back."))
            .bareRow(EdgeInsets(top: 6, leading: 26, bottom: 8, trailing: 26))
    }
}

private extension View {
    /// A row of the Following list that is not a date: no background, no
    /// separator, and nothing to pick while dates are being picked.
    func bareRow(_ insets: EdgeInsets = EdgeInsets()) -> some View {
        listRowInsets(insets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .selectionDisabled()
    }
}

// MARK: - What the list is held to

/// What the Following tab is narrowed to beyond the performer chips: how far
/// ahead, and whichever parts of the country the reader picked.
///
/// It starts empty, and empty narrows nothing: the tab opens on everything
/// that is coming, which is what it is for.
struct FollowingFilter: Equatable {
    /// How far ahead the list reaches, from today. A few fixed spans rather
    /// than a range picked on a calendar, which a menu has no room for; and
    /// rolling ones rather than "this week" or "this month", which near their
    /// end hold almost nothing.
    enum Window: CaseIterable, Hashable {
        case any, week, month, threeMonths, sixMonths

        var label: LocalizedStringKey {
            switch self {
            case .any: "All"
            case .week: "Next 7 Days"
            case .month: "Next 30 Days"
            case .threeMonths: "Next 3 Months"
            case .sixMonths: "Next 6 Months"
            }
        }

        /// Whether `event` falls inside the window. Counted in written dates,
        /// as ``Event/daysAway`` counts them — today and the next six days are
        /// the next seven, whatever the hour — and the months as the calendar
        /// has them, so three months from 30 November is the end of February.
        func contains(_ event: Event, asOf now: Date = .now) -> Bool {
            let reader = Calendar.current
            let today = reader.startOfDay(for: now)
            let end: Date? = switch self {
            case .any: nil
            case .week: reader.date(byAdding: .day, value: 7, to: today)
            case .month: reader.date(byAdding: .day, value: 30, to: today)
            case .threeMonths: reader.date(byAdding: .month, value: 3, to: today)
            case .sixMonths: reader.date(byAdding: .month, value: 6, to: today)
            }
            guard let end else { return true }
            return event.localDay < end
        }
    }

    var window = Window.any
    /// The areas the list is held to. Empty means anywhere — which is not the
    /// same as every case of ``Region``, because a hall nothing has placed is
    /// in none of them.
    var areas: Set<Region> = []
    /// Whether the halls nothing has placed are shown too. Kept apart from
    /// ``areas`` because "nowhere the site names" is not an area: it is a hall
    /// whose page has not been read yet, or one abroad, and an event is never
    /// filed under an area it might not be in.
    var unplaced = false

    /// Whether the list is held to any area — the half that needs the halls
    /// placed.
    var holdsAreas: Bool { !areas.isEmpty || unplaced }

    var isNarrowing: Bool { window != .any || holdsAreas }

    /// Whether an event survives the filter, given whatever is known about
    /// where its hall is.
    func matches(_ event: Event, in region: Region?) -> Bool {
        guard window.contains(event) else { return false }
        guard holdsAreas else { return true }
        guard let region else { return unplaced }
        return areas.contains(region)
    }
}

/// One published date, captioned with whichever followed performers are billed
/// on it. Tapping the caption opens that performer; the circular control adds
/// the event to the library, or takes it out again. The tag after the names says
/// the reader has not looked at this copy of it yet — New, or Updated where the
/// listing changed after they did. A tag rather than a dot, because the
/// caption above already leads with one.
private struct FollowedDateRow: View {
    /// Which clock the day and times are printed on — see ``TimeDisplay``.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue
    let event: Event
    let billing: [PerformerProfile]
    let unread: FollowingUnread?
    let showPerformer: (PerformerProfile) -> Void
    let open: () -> Void

    var body: some View {
        EventRowContent(event: event, detail: event.shown(on: timeDisplay).timeDetail) {
            HStack(spacing: 6) {
                if let first = billing.first {
                    // The whole caption leads to the first name on it. Two
                    // followed performers sharing a bill is the uncommon case,
                    // and a row is not the place to make the reader choose
                    // between them — their own page is one tap further on
                    // either way.
                    Button {
                        showPerformer(first)
                    } label: {
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
                // After the names, as the design has it, and held at its own
                // size: a long bill is what gives way. Outside the button, so
                // a tap on the tag opens the event rather than the performer.
                if let unread { UnreadTag(unread: unread) }
            }
        } trailing: {
            LibraryToggle(event: event)
        }
        .contentShape(.rect)
        .onTapGesture(perform: open)
        .glassPanel()
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    FollowingView()
        .library(EventStore.preview)
        .environment(FollowedDates.preview)
        .environment(VenueRegions.preview)
}
