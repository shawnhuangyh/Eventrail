import SwiftUI

/// The capsule over the foot of a list, holding one menu — the ways the list
/// can be narrowed or put in order, as the system's own lists keep theirs. Over
/// the tab bar on a tab, over the search field on Search, in the middle.
///
/// The face is the caller's: it says what the list is held to now, so a short
/// list is never a mystery. Everything else — the type, the glass, the room
/// round it and the order the menu opens in — is the same on every list.
struct ListMenu<Content: View, Face: View>: View {
    /// What the reader is choosing about, for VoiceOver.
    let describes: LocalizedStringKey
    /// What the list is held to now, for VoiceOver.
    let value: Text
    @ViewBuilder var content: Content
    @ViewBuilder var face: Face

    var body: some View {
        Menu {
            content
        } label: {
            face
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        // In the order written, whichever way the menu opens: it opens upwards
        // from here, and would otherwise turn its sections over.
        .menuOrder(.fixed)
        .glassCapsule(interactive: true)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityLabel(describes)
        .accessibilityValue(value)
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

/// Which half of a list of events is on screen: the events still ahead, or the
/// ones gone.
///
/// At the head of the list rather than in the capsule at its foot, because it
/// is not a narrowing of one list but a choice between two — each read in its
/// own order, and only the first counting down and carrying a read state — and
/// it is always one or the other, so it has no All to set apart. The head of a
/// list is where every screen keeps the choice of which list it is: Search its
/// scopes, Following its performers.
///
/// Shared by My Events and by the full Favorite Events list behind the Me card,
/// so that the two cannot drift apart.
struct LibraryHalfPicker: View {
    @Binding var filter: LibraryFilter

    var body: some View {
        Picker("Events", selection: $filter.animation(.snappy)) {
            ForEach(LibraryFilter.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// The capsule at the foot of a list of events: how the list is broken up.
///
/// Sort only, for now: which half is on screen is chosen at the head of the
/// list — see ``LibraryHalfPicker``.
struct EventListMenu: View {
    @Binding var grouping: Grouping

    var body: some View {
        ListMenu(describes: "Sort events", value: Text(grouping.label)) {
            Section("Sort") {
                ForEach(Grouping.allCases) { option in
                    Toggle(isOn: menuChoice($grouping, option)) {
                        Label(option.label, systemImage: option.symbol)
                    }
                }
            }
        } face: {
            SortMenuFace(label: Text(grouping.label))
        }
    }
}

/// The face of a ``ListMenu`` that only puts its list in order: the sort
/// arrows, the order it is in, and the menu's chevron — My Events' and the
/// Lotteries screen's alike.
struct SortMenuFace: View {
    let label: Text

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(.secondary)
            label
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
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
    /// Set where the rows have a read state — the events still ahead on My
    /// Events — and drawn opposite the trash, where Following keeps its own.
    var markRead: MarkReadButton?
    /// Set where the rows are past events on My Events, in the same place.
    var markAttended: MarkAttendedButton?
    let remove: () -> Void

    var body: some ToolbarContent {
        // Where Mail keeps it, and Following with it: the pick-everything
        // control opposite the way out.
        ToolbarItem(placement: .topBarLeading) {
            Button(isEverythingSelected ? "Deselect All" : "Select All", action: selectAll)
        }

        ToolbarItemGroup(placement: .bottomBar) {
            if let markRead { markRead }
            if let markAttended { markAttended }

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

/// The bottom-left control while dates are being picked, on Following and My
/// Events alike. One button rather than Mail's menu, doing whichever of the two
/// the picked rows call for: read if any of them is still unread, unread only
/// once every one of them has been read.
struct MarkReadButton: View {
    let marksRead: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(marksRead ? "Mark as Read" : "Mark as Unread",
               systemImage: marksRead ? "envelope.open" : "envelope.badge",
               action: action)
            .labelStyle(.iconOnly)
            .contentTransition(.symbolEffect(.replace))
            .disabled(!isEnabled)
    }
}

/// The bottom-left control while past events are being picked on My Events,
/// where the Upcoming half keeps ``MarkReadButton``: a ticket held for every
/// picked event that has none (``EventStore/recordTickets(for:)``), which is
/// what makes each attended.
struct MarkAttendedButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button("Mark as Attended", systemImage: "ticket", action: action)
            .labelStyle(.iconOnly)
            .disabled(!isEnabled)
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

/// The one control a list carries in its navigation bar: the pencil that turns
/// a tap on a row into a choice, and the mark that ends it.
///
/// Alone up there: what a list is narrowed to and how it is ordered is in the
/// capsule at its foot (``ListMenu``), and which half of it is on screen at its
/// head (``LibraryHalfPicker``). Changing either mid-selection would move the
/// ground under the choice, so both are put away or held still while picking.
struct PencilToolbar: ToolbarContent {
    @Binding var isSelecting: Bool
    /// What the pencil is for, as VoiceOver says it.
    let title: LocalizedStringKey
    /// Nothing to pick from leaves the pencil in place but dimmed, rather than
    /// letting the bar rearrange itself as the list fills.
    var canSelect = true

    var body: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .primaryAction) {
                Button("Done", systemImage: "checkmark") { isSelecting = false }
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Button(title, systemImage: "pencil") { isSelecting = true }
                    .disabled(!canSelect)
            }
        }
    }
}
