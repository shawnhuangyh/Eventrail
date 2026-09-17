import SwiftUI

/// The capsule every list screen carries in its navigation bar: what the list
/// is showing, and the way into changing it.
///
/// Only one word stands in it — whichever choice names the list best — with the
/// sort arrows beside it. Naming both choices put two words in a capsule that
/// has to sit next to a button.
struct ListMenu<Content: View>: View {
    /// The choice the capsule spells out: the filter where a screen has one,
    /// the sort order where it does not.
    let label: Text
    /// What the reader is choosing about, for VoiceOver.
    let describes: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
                label
                    .font(.system(size: 13.5, weight: .semibold))
                Circle()
                    .fill(.tertiary)
                    .frame(width: 3.5, height: 3.5)
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityLabel(describes)
    }
}

/// One option of a group inside a ``ListMenu``, written as a toggle rather than
/// as a `Picker` row: a picker's own label goes unshown in a menu on iOS, and
/// the design wants each group headed. On when it is the choice, and a tap on
/// it makes it the choice — tapping the one already chosen changes nothing.
func menuChoice<Value: Equatable>(_ selection: Binding<Value>,
                                  _ option: Value) -> Binding<Bool> {
    Binding(
        get: { selection.wrappedValue == option },
        set: { isOn in if isOn { selection.wrappedValue = option } }
    )
}

/// Sort and filter for a list of events, and the pencil that turns a tap on a
/// row into a choice instead of an opening.
///
/// Shared by My Events and by the full Favorite Events list behind the Me card,
/// so that the two cannot drift apart: the same capsule, the same menu, the
/// same way in and out of picking rows.
struct EventListToolbar: ToolbarContent {
    @Binding var filter: LibraryFilter
    @Binding var grouping: Grouping
    /// Whether the screen is picking rows rather than opening them.
    @Binding var isSelecting: Bool
    /// How many events sit behind each filter, shown beside it in the menu.
    var counts: (LibraryFilter) -> Int
    /// Nothing to pick from leaves the pencil in place but dimmed, rather than
    /// letting the bar rearrange itself as the list fills.
    var canSelect = true

    var body: some ToolbarContent {
        if isSelecting {
            // Changing the filter mid-selection would move the ground under the
            // choice, so the menu is put away while selecting and the one way
            // out takes its place.
            ToolbarItem(placement: .primaryAction) {
                Button("Done", systemImage: "checkmark") { isSelecting = false }
            }
        } else {
            ToolbarItem(placement: .primaryAction) { menu }
            // Its own capsule rather than a shared one: the menu says what the
            // list shows, and this says what a tap on it does.
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button("Select Events", systemImage: "pencil") { isSelecting = true }
                    .disabled(!canSelect)
            }
        }
    }

    /// Sort stands above Filter because it is the choice the reader revisits:
    /// which half of the list is on screen changes rarely, how it is broken up
    /// changes with the task.
    private var menu: some View {
        ListMenu(label: Text(filter.label), describes: "Sort and filter events") {
            Section("Sort") {
                ForEach(Grouping.allCases) { option in
                    Toggle(isOn: menuChoice($grouping, option)) {
                        Label(option.label, systemImage: option.symbol)
                    }
                }
            }

            Section("Filter") {
                ForEach(LibraryFilter.allCases) { option in
                    Toggle(isOn: menuChoice($filter, option)) {
                        Label {
                            Text(option.label)
                            Text(counts(option).formatted())
                        } icon: {
                            Image(systemName: option.symbol)
                        }
                    }
                }
            }
        }
    }
}

/// What the trash asks before it acts, on the screens where it asks anything.
///
/// The sheet hangs off the trash rather than off the screen: iOS points a
/// confirmation at whatever presented it, and a dialog attached to the whole
/// screen arrives pointing at nothing in particular.
struct RemovalConfirmation {
    var isPresented: Binding<Bool>
    var title: Text
    var message: Text
    var confirmTitle: LocalizedStringKey
    var cancelTitle: LocalizedStringKey
    var confirm: () -> Void
}

/// The bar that takes the bottom of the screen over while rows are being
/// picked, the way it does everywhere else on iOS: the actions for what is
/// selected stand where the thumb already is.
struct SelectionToolbar: ToolbarContent {
    /// Whether everything on screen is already picked — the one label that has
    /// to say the opposite of what it does.
    let isEverythingSelected: Bool
    let selectAll: () -> Void
    /// What taking the chosen rows out of this list is called here. Removing
    /// from the library and un-hearting are not the same act, so the screen
    /// names its own.
    let removeTitle: LocalizedStringKey
    let canRemove: Bool
    /// Set where the act is worth asking about first; the trash acts at once
    /// where it is not.
    var confirmation: RemovalConfirmation?
    let remove: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Button(isEverythingSelected ? "Deselect All" : "Select All", action: selectAll)

            Spacer()

            asking(
                Button(removeTitle, systemImage: "trash", role: .destructive, action: remove)
                    .disabled(!canRemove)
            )
        }
    }

    @ViewBuilder
    private func asking(_ trash: some View) -> some View {
        if let confirmation {
            trash.confirmationDialog(confirmation.title,
                                     isPresented: confirmation.isPresented,
                                     titleVisibility: .visible) {
                Button(confirmation.confirmTitle, role: .destructive, action: confirmation.confirm)
                Button(confirmation.cancelTitle, role: .cancel) {}
            } message: {
                confirmation.message
            }
        } else {
            trash
        }
    }
}

/// The mark that stands in front of a row while a screen is picking rows.
///
/// A `List` draws its own in edit mode; the two screens behind the Me cards lay
/// their rows out themselves, so they draw this.
struct SelectionMark: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? AnyShapeStyle(Color.brandTint) : AnyShapeStyle(.tertiary))
            .accessibilityHidden(true)
    }
}

/// The one control a list of performers carries: the pencil that turns a tap on
/// a row into a choice, and the mark that ends it.
///
/// No capsule beside it. A performer has no past and no future of their own,
/// and the list is already in the one order that means anything for a settled
/// list — so there is nothing for a sort or a filter to say.
struct PerformerListToolbar: ToolbarContent {
    @Binding var isSelecting: Bool
    var canSelect = true

    var body: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .primaryAction) {
                Button("Done", systemImage: "checkmark") { isSelecting = false }
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Button("Select Performers", systemImage: "pencil") { isSelecting = true }
                    .disabled(!canSelect)
            }
        }
    }
}
