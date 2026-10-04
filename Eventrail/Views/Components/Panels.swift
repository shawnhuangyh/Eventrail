import SwiftUI

/// The circular control that puts an event in the reader's library, or takes it
/// back out.
///
/// It is the one gesture that turns something published into something the
/// reader has decided about, and it is offered in two places that are not the
/// library — a search result and a followed performer's date — so it has to
/// read the same in both. The event's own sheet carries the same plus and
/// checkmark at the head of its action bar.
///
/// Always an explicit choice: nothing found on Eventernote joins the library by
/// being looked at. Taking one out is asked first, as everywhere
/// (``SwiftUI/View/confirmingRemoval(isPresented:remove:)``).
struct LibraryToggle: View {
    @Environment(EventStore.self) private var store
    @State private var isConfirmingRemoval = false

    let event: Event

    private var isSaved: Bool { store.isInLibrary(event) }

    var body: some View {
        Button {
            if isSaved {
                isConfirmingRemoval = true
            } else {
                withAnimation(.snappy) { store.toggleLibraryMembership(event) }
            }
        } label: {
            Image(systemName: isSaved ? "checkmark" : "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isSaved ? Color.trackAttended : Color.brandTint)
                .frame(width: 38, height: 38)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .glassCircle(interactive: true)
        .accessibilityLabel(isSaved ? "Remove from my events" : "Add to my events")
        .confirmingRemoval(isPresented: $isConfirmingRemoval) {
            withAnimation(.snappy) { store.remove(CollectionOfOne(event)) }
        }
    }
}

// MARK: - Taking an event out

/// What taking events out of the library is asked as, wherever it is done:
/// the trash, a swipe, the event sheet's button and menu, the checkmark on a
/// search result or a followed date. Each says what goes with the event —
/// everything the reader wrote on it, on every device — and that the linked
/// account can bring the event back but not that.
enum EventRemoval {
    static var message: Text {
        Text("Its lottery entries, ticket details and notes are deleted too, on all your devices. If your Eventernote account still lists the event, it comes back on the next refresh, without them.")
    }

    static var messageForSeveral: Text {
        Text("Their lottery entries, ticket details and notes are deleted too, on all your devices. Anything your Eventernote account still lists comes back on the next refresh, without them; the rest you can add again from Search.")
    }
}

extension View {
    /// Asks before one event leaves the library. Hung off whatever asked, so
    /// the dialog points at it.
    func confirmingRemoval(isPresented: Binding<Bool>, remove: @escaping () -> Void) -> some View {
        confirmationDialog("Remove this event from your library?", isPresented: isPresented,
                           titleVisibility: .visible) {
            Button("Remove", role: .destructive, action: remove)
            Button("Keep it", role: .cancel) {}
        } message: {
            EventRemoval.message
        }
    }
}

// MARK: - Where a tap on a row goes

extension View {
    /// Opens an event's sheet over this screen.
    ///
    /// Every list in the app ends in the same sheet, so every list carried the
    /// same modifier written out in full. Kept as one so that a change to how
    /// an event is presented — a different detent, a different transition — is
    /// made once rather than in seven places, six of which would be found and
    /// one of which would not.
    ///
    /// The sheet draws refresh notices of its own, because it covers the root
    /// that draws everybody else's — see ``refreshNotices(aboveBar:showing:)``.
    /// It places them itself, so they stand clear of its action bar.
    func eventSheet(_ event: Binding<Event?>) -> some View {
        sheet(item: event) { EventDetailView(event: $0) }
    }

    /// Registers a performer's page on this stack.
    ///
    /// Each `NavigationStack` needs its own — a destination is not inherited
    /// across stacks, which is why the event sheet registers one too even
    /// though it was pushed from a screen that already had it.
    func performerDestination() -> some View {
        navigationDestination(for: PerformerLink.self) { PerformerView(link: $0) }
    }

    /// Registers a venue's page on this stack, with the performer's — a hall's
    /// page lists who plays there, and each of those names pushes a performer.
    func venueDestination() -> some View {
        performerDestination()
            .navigationDestination(for: VenueLink.self) { VenueView(link: $0) }
    }
}
