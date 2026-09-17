import SwiftUI

/// Everyone the reader follows, in full.
///
/// The Me tab shows the first few and sends the rest here, for the reason
/// ``FavoriteEventsView`` gives. This is the list as a list; the Following tab
/// is what the same people have coming.
///
/// It carries the pencil the event lists do, and nothing beside it: the list is
/// already in the one order that means anything for a settled list, so there is
/// nothing for a sort or a filter to say.
struct FollowedPerformersView: View {
    @Environment(EventStore.self) private var store

    @State private var isSelecting = false
    @State private var selection: Set<PerformerProfile.ID> = []
    @State private var isConfirmingUnfollow = false

    private var performers: [PerformerProfile] { store.followedPerformers }

    private var chosen: [PerformerProfile] {
        performers.filter { selection.contains($0.id) }
    }

    private var allIDs: Set<PerformerProfile.ID> {
        Set(performers.map(\.id))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if performers.isEmpty {
                    // Reachable by unfollowing the last one from this screen.
                    Text("Follow a performer from their page to keep them here. It stays in your library and is never written back to Eventernote.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    ForEach(Array(performers.enumerated()), id: \.element.id) { index, performer in
                        FollowedPerformerRow(performer: performer, showsDivider: index > 0,
                                             isSelecting: isSelecting,
                                             isSelected: selection.contains(performer.id)) {
                            toggle(performer)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .glassPanel()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .washBackground()
        .navigationTitle("Following Performers")
        .navigationSubtitle(subtitle)
        .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
        .toolbar {
            PerformerListToolbar(isSelecting: $isSelecting,
                                 canSelect: !performers.isEmpty)
            if isSelecting {
                SelectionToolbar(
                    isEverythingSelected: selection == allIDs,
                    selectAll: { selection = selection == allIDs ? [] : allIDs },
                    removeTitle: "Unfollow",
                    canRemove: !selection.isEmpty,
                    confirmation: RemovalConfirmation(
                        isPresented: $isConfirmingUnfollow,
                        title: unfollowTitle,
                        message: Text("Their dates stop appearing in Following, on this device and on your other devices. Anyone your Eventernote account still favorites comes back on the next refresh."),
                        confirmTitle: "Unfollow",
                        cancelTitle: "Keep following",
                        confirm: unfollowChosen
                    ),
                    remove: { isConfirmingUnfollow = true }
                )
            }
        }
        .onChange(of: isSelecting) { selection.removeAll() }
    }

    private var subtitle: Text {
        if isSelecting {
            selection.isEmpty
                ? Text("Select performers to unfollow")
                : Text("^[\(selection.count) performer](inflect: true) selected")
        } else {
            Text("^[\(performers.count) performer](inflect: true)")
        }
    }

    private func toggle(_ performer: PerformerProfile) {
        if selection.contains(performer.id) {
            selection.remove(performer.id)
        } else {
            selection.insert(performer.id)
        }
    }

    /// Spelled out rather than inflected, for the reason ``EventsView``'s own
    /// removal gives.
    private var unfollowTitle: Text {
        selection.count == 1
            ? Text("Stop following them?")
            : Text("Stop following \(selection.count) performers?")
    }

    /// Unfollowing is tombstoned rather than deleted, so a later import cannot
    /// bring them back — which is exactly why it is asked about first.
    private func unfollowChosen() {
        let performers = chosen
        withAnimation(.snappy) {
            for performer in performers { store.unfollow(performer) }
        }
        isSelecting = false
    }
}

#Preview {
    NavigationStack {
        FollowedPerformersView()
    }
    .environment(EventStore.preview)
    .environment(FollowedDates.preview)
}
