import SwiftUI

/// The way into the site's directory of venues, from the Search tab before
/// anything is typed.
nonisolated enum VenueDirectory: Hashable {
    /// Every prefecture, by area.
    case browse
    /// Every hall filed under one prefecture.
    case prefecture(PrefectureListing)
}

/// The site's directory of venues: every prefecture, with how many halls it
/// files there, grouped as Search's Area filter groups them and 海外 last —
/// each opening the halls filed under it. The site's own `/places` pages,
/// read as the performers' directory is. Nothing is written back.
struct VenueDirectoryView: View {
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?

    @State private var page = DirectoryPage(key: "directory/places", read: Self.read)

    nonisolated private static func read() async throws -> CachedDirectory {
        CachedDirectory(prefectures: try await EventernoteClient.shared.prefectures())
    }

    /// One of the site's areas and the prefectures in it, in the site's
    /// order — or, last, whatever the site files outside them: 海外.
    private struct Area: Identifiable {
        let id: String
        let label: LocalizedStringKey
        let prefectures: [PrefectureListing]

        static func areas(of prefectures: [PrefectureListing]) -> [Area] {
            let placed = Set(Region.allCases.flatMap(\.prefectures))
            let areas = Region.allCases.map { region in
                Area(id: region.rawValue, label: region.label,
                     prefectures: prefectures.filter { region.prefectures.contains($0.name) })
            } + [Area(id: "overseas", label: "Overseas",
                      prefectures: prefectures.filter { !placed.contains($0.name) })]
            return areas.filter { !$0.prefectures.isEmpty }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 9) {
                DirectoryContent(page: page) { content in
                    ForEach(Area.areas(of: content.prefectures)) { area in
                        SectionLabel(label: area.label)
                            .padding(.top, area.id == Region.allCases.first?.rawValue ? 0 : 8)
                        PrefectureGrid(prefectures: area.prefectures)
                    }
                    Footnote(Text("Every venue on Eventernote, filed by the prefecture it is in."),
                             updated: content.readAt)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .washBackground()
        .navigationTitle("Venues")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    EventernotePageItems(page: EventernoteClient.venueDirectoryURL, isRefreshing: page.isReading) {
                        Task { notices?.report(await page.refresh(), byHand: true) }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .menuOrder(.fixed)
            }
        }
        .task {
            if let notice = await page.open() { notices?.report(notice, byHand: false) }
        }
    }
}

/// Every hall the site files under one prefecture, in the site's order — the
/// whole of it on one page, as the site prints it.
struct VenuePrefectureView: View {
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?

    let prefecture: PrefectureListing
    @State private var page: DirectoryPage

    init(prefecture: PrefectureListing) {
        self.prefecture = prefecture
        _page = State(initialValue: DirectoryPage(key: "directory/prefecture/\(prefecture.id)",
                                                  read: Self.reader(of: prefecture.id)))
    }

    nonisolated private static func reader(of id: Int) -> @Sendable () async throws -> CachedDirectory {
        { CachedDirectory(places: try await EventernoteClient.shared.venues(inPrefecture: id)) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 9) {
                DirectoryContent(page: page) { content in
                    SectionLabel(label: "^[\(content.places.count) venue](inflect: true)")
                    ForEach(content.places) { VenueRow(place: $0) }
                    Footnote(Text("Every venue on Eventernote in \(prefecture.name), from its public pages."),
                             updated: content.readAt)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .washBackground()
        .navigationTitle(Text(verbatim: prefecture.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    EventernotePageItems(page: EventernoteClient.venuesURL(inPrefecture: prefecture.id),
                                         isRefreshing: page.isReading) {
                        Task { notices?.report(await page.refresh(), byHand: true) }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .menuOrder(.fixed)
            }
        }
        .task {
            if let notice = await page.open() { notices?.report(notice, byHand: false) }
        }
    }
}

/// An area's prefectures as tiles, each with how many halls it holds.
private struct PrefectureGrid: View {
    let prefectures: [PrefectureListing]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
            ForEach(prefectures) { prefecture in
                NavigationLink(value: VenueDirectory.prefecture(prefecture)) {
                    VStack(spacing: 3) {
                        Text(verbatim: prefecture.name)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(prefecture.count, format: .number)
                            .font(.system(size: 10.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 6)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .panel(cornerRadius: 16)
                .accessibilityLabel(Text("\(prefecture.name), ^[\(prefecture.count) venue](inflect: true)"))
            }
        }
    }
}

#Preview {
    NavigationStack {
        VenueDirectoryView()
    }
    .library(EventStore.preview)
}
