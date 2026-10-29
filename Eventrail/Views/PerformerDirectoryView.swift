import SwiftUI

/// The way into the site's directory of performers, from the Search tab
/// before anything is typed.
nonisolated enum PerformerDirectory: Hashable {
    /// Its three lists: the most followed, the newest, and the kana.
    case browse
    /// Every performer whose reading starts with one kana.
    case initial(KanaInitial)
}

/// The site's directory of performers: the hundred with the most fans, the
/// ones added last, and every kana a reading starts with, each opening the
/// performers filed under it — the site's own `/actors` pages, read as Search
/// reads any of the site's lists. Nothing is written back.
struct PerformerDirectoryView: View {
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?

    enum DirectoryList: CaseIterable, Hashable {
        case popular, newest, kana

        var label: LocalizedStringKey {
            switch self {
            case .popular: "Popular"
            case .newest: "New"
            case .kana: "By Kana"
            }
        }
    }

    /// Opens on the most followed: the list worth browsing without a name in
    /// mind. Not remembered between visits.
    @State private var list: DirectoryList = .popular
    @State private var popular = DirectoryPage(key: "directory/popular", read: Self.readPopular)
    /// The directory's own page, which holds both the newest and the kana.
    @State private var index = DirectoryPage(key: "directory/index", read: Self.readIndex)

    nonisolated private static func readPopular() async throws -> CachedDirectory {
        CachedDirectory(performers: try await EventernoteClient.shared.popularPerformers())
    }

    nonisolated private static func readIndex() async throws -> CachedDirectory {
        let index = try await EventernoteClient.shared.performerIndex()
        return CachedDirectory(performers: index.newest, initials: index.initials)
    }

    private var page: DirectoryPage { list == .popular ? popular : index }

    var body: some View {
        let page = self.page
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 9) {
                Picker("List", selection: $list) {
                    ForEach(DirectoryList.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.bottom, 6)

                DirectoryContent(page: page) { content in
                    switch list {
                    case .popular:
                        SectionLabel(label: "The \(content.performers.count) with the most fans")
                        ForEach(Array(content.performers.enumerated()), id: \.element.id) { rank, performer in
                            PerformerRow(performer: performer, rank: rank + 1)
                        }
                    case .newest:
                        SectionLabel(label: "Added to Eventernote last")
                        ForEach(content.performers) { PerformerRow(performer: $0) }
                    case .kana:
                        KanaGrid(initials: content.initials)
                    }
                    Footnote(footnote, updated: content.readAt)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .washBackground()
        .navigationTitle("Performers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    EventernotePageItems(page: pageURL, isRefreshing: page.isReading) {
                        Task { notices?.report(await page.refresh(), byHand: true) }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .menuOrder(.fixed)
            }
        }
        .task(id: list) {
            if let notice = await page.open() { notices?.report(notice, byHand: false) }
        }
    }

    private var pageURL: URL? {
        list == .popular ? EventernoteClient.popularPerformersURL : EventernoteClient.performerDirectoryURL
    }

    private var footnote: Text {
        switch list {
        case .popular: Text("Eventernote's ranking by fans, from its public pages.")
        case .newest: Text("The performers most recently added to Eventernote, from its public pages.")
        case .kana: Text("Every performer on Eventernote, filed by the kana their reading starts with.")
        }
    }
}

/// Every performer whose reading starts with one kana, in the order of their
/// readings — the whole of it on one page, as the site prints it.
struct PerformerInitialView: View {
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?

    let initial: KanaInitial
    @State private var page: DirectoryPage

    init(initial: KanaInitial) {
        self.initial = initial
        _page = State(initialValue: DirectoryPage(key: "directory/initial/\(initial.kana)",
                                                  read: Self.reader(of: initial.kana)))
    }

    nonisolated private static func reader(of kana: String) -> @Sendable () async throws -> CachedDirectory {
        { CachedDirectory(performers: try await EventernoteClient.shared.performers(underInitial: kana)) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 9) {
                DirectoryContent(page: page) { content in
                    SectionLabel(label: "^[\(content.performers.count) performer](inflect: true)")
                    ForEach(content.performers) { PerformerRow(performer: $0) }
                    Footnote(Text("Every performer on Eventernote whose reading starts with \(initial.kana), from its public pages."),
                             updated: content.readAt)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .washBackground()
        .navigationTitle(Text(verbatim: "「\(initial.kana)」"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    EventernotePageItems(page: EventernoteClient.performersURL(underInitial: initial.kana),
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

/// The kana, laid out as the syllabary is — a row for each consonant, its
/// five vowels across — each with how many readings start with it.
private struct KanaGrid: View {
    let initials: [KanaInitial]

    /// The rows of the syllabary, a gap where a row has no kana for a vowel.
    private static let rows: [[String?]] = [
        ["あ", "い", "う", "え", "お"], ["か", "き", "く", "け", "こ"], ["さ", "し", "す", "せ", "そ"],
        ["た", "ち", "つ", "て", "と"], ["な", "に", "ぬ", "ね", "の"], ["は", "ひ", "ふ", "へ", "ほ"],
        ["ま", "み", "む", "め", "も"], ["や", nil, "ゆ", nil, "よ"], ["ら", "り", "る", "れ", "ろ"],
        ["わ", nil, "を", nil, "ん"],
    ]

    var body: some View {
        let byKana = Dictionary(initials.map { ($0.kana, $0) }) { first, _ in first }
        // Any kana the site lists that the syllabary above has no place for,
        // after it — so nothing the site files is out of reach.
        let placed = Set(Self.rows.joined().compactMap { $0 })
        let others = initials.filter { !placed.contains($0.kana) }
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Self.rows.indices, id: \.self) { row in
                GridRow {
                    ForEach(Self.rows[row].indices, id: \.self) { column in
                        if let kana = Self.rows[row][column], let initial = byKana[kana] {
                            tile(initial)
                        } else {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
            }
            ForEach(others.chunked(into: 5).indices, id: \.self) { row in
                GridRow {
                    ForEach(others.chunked(into: 5)[row], id: \.kana) { tile($0) }
                }
            }
        }
    }

    private func tile(_ initial: KanaInitial) -> some View {
        NavigationLink(value: PerformerDirectory.initial(initial)) {
            VStack(spacing: 3) {
                Text(verbatim: initial.kana)
                    .font(.system(size: 20, weight: .semibold))
                Text(initial.count, format: .number)
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .panel(cornerRadius: 16)
        .accessibilityLabel(Text("\(initial.kana), ^[\(initial.count) performer](inflect: true)"))
    }
}

private extension Array {
    /// The elements `size` at a time, the last run shorter where they do not
    /// divide evenly.
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}

#Preview {
    NavigationStack {
        PerformerDirectoryView()
    }
    .library(EventStore.preview)
}
