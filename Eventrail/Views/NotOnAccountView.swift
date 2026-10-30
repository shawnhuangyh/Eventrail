import SwiftData
import SwiftUI

/// The library's events the linked account did not list when last read whole
/// — see ``EventStore/notOnAccount(_:)``.
///
/// Eventrail never writes to Eventernote, so this is a list to work through
/// on the site: each row's round button opens the event's page in the
/// browser, where the reader is signed in and marks it themselves, and the
/// event leaves the list once a read of the account finds it there — the
/// app's own once stale, or this screen's Refresh. Opened from the account
/// card on Me, and only while there is something on it.
struct NotOnAccountView: View {
    @Environment(EventStore.self) private var store
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?
    /// Declared to be drawn again as the day turns — see ``EnvironmentValues/today``.
    @Environment(\.today) private var today
    @Query(LibraryEntry.library) private var kept: [LibraryEntry]

    @State private var filter: LibraryFilter = .upcoming
    @State private var openEvent: Event?
    /// Whether the screen has chosen the half it opens on — see ``body``.
    @State private var hasChosenHalf = false

    private var missing: [Event] {
        store.notOnAccount(store.events(of: kept, where: \.inLibrary)) ?? []
    }

    var body: some View {
        // Worked out once a drawing, as My Events works its own out.
        let missing = self.missing
        let groups = EventGroup.groups(of: missing, filter: filter, grouping: .date)
        let subtitle = Text("^[\(missing.count) event](inflect: true)")
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !missing.isEmpty {
                    LibraryHalfPicker(filter: $filter)
                        .padding(.horizontal, 4)
                }
                if missing.isEmpty {
                    // Reachable by a Refresh that finds the last of them on
                    // the account, or by taking it out of the library.
                    note("Everything in your library is on your Eventernote account.")
                } else if groups.isEmpty {
                    note(filter == .upcoming
                         ? "Nothing still to come is missing from Eventernote."
                         : "Nothing in the past is missing from Eventernote.")
                } else {
                    ForEach(groups) { group in
                        section(group)
                    }
                }

                Footnote(Text("Eventrail never writes to Eventernote. Open each event there and tap 参加する; it leaves this list the next time your account is read."),
                         updated: store.accountListingRead)
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .washBackground()
        .navigationTitle("Not on Your Account")
        .navigationSubtitle(subtitle)
        .largeTitleOnMac(Text("Not on Your Account"), subtitle: subtitle)
        .toolbar { menu }
        .eventPane($openEvent)
        // Opened on the past where nothing still to come is missing, rather
        // than on an empty Upcoming under a count saying there is something.
        // Once, so coming back from an event leaves the half the reader chose.
        .onAppear {
            guard !hasChosenHalf else { return }
            hasChosenHalf = true
            let missing = self.missing
            if !missing.isEmpty, !missing.contains(where: \.isUpcoming) { filter = .past }
        }
    }

    private func section(_ group: EventGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupHeader(label: Text(group.label), count: group.events.count)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(group.events.enumerated()), id: \.element.id) { index, event in
                    CompactEventRow(event: event, showsDivider: index > 0,
                                    open: { openEvent = event }) {
                        Link(destination: event.sourceURL) {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.brandTint)
                                .frame(width: 38, height: 38)
                        }
                        .buttonStyle(.plain)
                        .circlePanel()
                        .accessibilityLabel("Add on Eventernote")
                    }
                }
            }
            .padding(.vertical, 6)
            .panel()
        }
    }

    private func note(_ line: LocalizedStringKey) -> some View {
        Text(line)
            .scalingFont(size: 12)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .panel()
    }

    /// The account's page on the site, and reading it again — the group a
    /// site page's ⋯ menu ends on.
    @ToolbarContentBuilder
    private var menu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                EventernotePageItems(page: accountPage, isRefreshing: store.isRefreshing) {
                    Task { await refresh() }
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .menuOrder(.fixed)
        }
    }

    private var accountPage: URL? {
        store.eventernoteHandle.map {
            EventernoteClient.site.appending(path: "users/\($0)/events")
        }
    }

    /// The account read again, held to no window — see
    /// ``EventStore/readAccountNow()`` — and then said how it went.
    private func refresh() async {
        guard await store.readAccountNow() else { return }
        notices?.report(.library(failure: store.refreshFailure), byHand: true)
    }
}

#Preview {
    NavigationStack {
        NotOnAccountView()
    }
    .library(EventStore.preview)
}
