import SwiftUI

/// The full-width glass panel that hands the reader off to a page on the web.
///
/// A performer's page carries one; an event's sheet did too, until the way out
/// to Eventernote moved into the menu on its action bar. The arrow is the
/// system's own sign for leaving the app, and it is the whole of the
/// difference between this and a row that pushes.
///
/// The horizontal inset is the caller's: this sits in a run of cards on one
/// screen and in a narrower column on another.
struct ExternalLinkPanel: View {
    let title: LocalizedStringKey
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 9) {
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.brandTint)
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .glassPanel(interactive: true)
    }
}

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
/// being looked at.
struct LibraryToggle: View {
    @Environment(EventStore.self) private var store

    let event: Event

    private var isSaved: Bool { store.isInLibrary(event) }

    var body: some View {
        Button {
            withAnimation(.snappy) { store.toggleLibraryMembership(event) }
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
    /// that draws everybody else's — see ``refreshNotices(underSheets:showing:)``.
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
