import SwiftUI

/// Names the Eventernote account the reader imports their history from.
///
/// Nothing here signs in. Eventernote publishes every member's attended events
/// on a page anyone can load, so the app only needs to be told *which* member —
/// it never holds a password, a session or a cookie of theirs, and it still only
/// ever reads. The handle is confirmed against the live page before it is kept,
/// because a mistyped one would import a stranger's history into their library.
///
/// The asking itself is ``AccountFinder``, shared with ``WelcomeView``. What is
/// left here is the frame around it: a sheet, an explanation, and Link.
struct EventernoteAccountSheet: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The account the reader has settled on, or nil while they have not.
    @State private var chosen: EventernoteProfile?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    masthead
                    AccountFinder(chosen: $chosen)
                    explanation
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .washBackground()
            .navigationTitle("Eventernote Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Link") {
                        guard let chosen else { return }
                        store.link(chosen)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .disabled(chosen == nil)
                }
            }
        }
    }

    /// What naming an account is about to do, which is not the same thing for
    /// a reader who has never named one as for a reader changing theirs.
    ///
    /// The second is the one worth saying out loud: a library is the reader's,
    /// and pointing the app at somebody else's page does not take it off them.
    /// Naming an account only settles where Eventrail looks next — the same
    /// promise ``EventStore/unlinkAccount()`` makes for letting one go.
    private var masthead: some View {
        ScreenHeading(
            title: store.isLinked ? "Change account" : "Your account name",
            detail: store.isLinked
                ? "Everything already imported stays in your library, whichever account you name. Only where Eventrail reads next changes."
                : "Eventrail imports what your Eventernote profile already lists — the events you have been to, and the performers you favourite."
        )
        .padding(.top, 2)
    }

    private var explanation: some View {
        Text("Eventrail reads the same public page anyone visiting your profile would see. It does not sign in, and it never writes anything back to Eventernote. Events you have already removed here stay removed. An import only ever puts events in your library — what you wrote on one is yours, and nothing here writes over it.")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 4)
    }
}

/// Naming an Eventernote account, and confirming the name against the live page.
///
/// The whole of the question, in one place: the field, the look-up, who the
/// name turned out to belong to, and what to say when it belonged to nobody.
/// Both screens that ask it — ``EventernoteAccountSheet`` and ``WelcomeView`` —
/// show this and nothing of their own, so there is no second copy of the rules
/// to drift out of step with the first. What each screen keeps is the frame
/// around it and what it does with the answer: Link on one, Continue on the
/// other.
///
/// Eventernote publishes no member search, so this looks a name up rather than
/// searching for it: the site answers for an exact name or not at all, which is
/// also what keeps a mistyped handle from importing a stranger's history.
struct AccountFinder: View {
    @Environment(EventStore.self) private var store

    /// The account the reader has settled on, and the only thing this reports.
    ///
    /// One source of truth for both the tick and the caller's own button: a
    /// screen that clears this — the welcome's Skip does — unticks the row by
    /// the same stroke, so the two can never disagree about whether an account
    /// has been chosen.
    @Binding var chosen: EventernoteProfile?

    @State private var typed = ""
    @State private var found: EventernoteProfile?
    @State private var isLooking = false
    /// A name nobody goes by, as opposed to a page that would not load.
    @State private var missed = false
    @State private var failure: String?
    @FocusState private var isFocused: Bool

    private var query: String { typed.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            field

            if let label = resultLabel {
                SectionLabel(label: label)
            }

            if let found {
                FoundAccount(profile: found, isChosen: isChosen) { isFocused = false }
            } else if missed {
                note(Text("No Eventernote user goes by that name. Check the spelling, or skip — you can name an account any time from Me."))
            } else if let failure {
                note(Text(verbatim: failure))
            } else {
                Text("It is the name in your Eventernote profile's address, after /users/.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
        }
        .onAppear { typed = store.eventernoteHandle ?? "" }
        .task(id: query) { await look() }
    }

    /// Derived rather than stored, so ``chosen`` is the only thing that says
    /// whether an account has been settled on.
    private var isChosen: Binding<Bool> {
        Binding { chosen != nil } set: { chosen = $0 ? found : nil }
    }

    private var resultLabel: LocalizedStringKey? {
        if found != nil { return "Match" }
        if missed { return "No match" }
        return nil
    }

    private var field: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tertiary)
            // A login name, so none of the keyboard's help applies to it: every
            // correction it would make here is a wrong one.
            TextField("Eventernote username", text: $typed)
                .font(.system(size: 16))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFocused)
            if isLooking {
                ProgressView().controlSize(.small)
            } else if !query.isEmpty {
                Button {
                    typed = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassPanel(cornerRadius: 14)
    }

    /// Takes a `Text` rather than a key: one of the two things said this way is
    /// a message the client already localized, and looking it up a second time
    /// would find nothing.
    private func note(_ text: Text) -> some View {
        text
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .glassPanel(cornerRadius: 24)
    }

    /// Confirms the typed name against the live page, a pause after the last
    /// keystroke rather than on every one. `task(id:)` cancels the previous
    /// look on each change, so only the name they stopped on is ever asked for.
    private func look() async {
        found = nil
        chosen = nil
        missed = false
        failure = nil
        guard !query.isEmpty else { return }

        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }

        isLooking = true
        defer { isLooking = false }
        do {
            let profile = try await store.lookUpAccount(query)
            found = profile
            // One exact match and nothing to choose between: it is taken as the
            // answer, and the row is still there to take it back.
            chosen = profile
        } catch let error as EventernoteClient.Failure {
            switch error {
            case .http(404), .unreadable: missed = true
            case .http: failure = error.errorDescription
            }
        } catch {
            failure = String(localized: "Could not reach Eventernote. Try again in a moment.")
        }
    }
}

/// The account a typed name turned out to belong to, offered before anything is
/// linked to it.
///
/// A control, not a caption. A name is confirmed against the live page, but the
/// app still has no business deciding that the account it found is the one the
/// reader meant, so the tick is theirs to take back. It comes already ticked,
/// because one exact match is not a choice between several.
struct FoundAccount: View {
    let profile: EventernoteProfile
    /// Whether this is the account the screen will act on.
    @Binding var isChosen: Bool
    /// Run beside the toggle, for whatever the screen wants to put away once
    /// the reader has answered — a keyboard, so far.
    var onChoose: () -> Void = {}

    var body: some View {
        Button {
            isChosen.toggle()
            onChoose()
        } label: {
            row.contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassPanel(interactive: true)
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
    }

    private var row: some View {
        HStack(spacing: 14) {
            AccountAvatar(url: profile.avatarURL, width: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: profile.name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Text(verbatim: "@\(profile.handle)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                profile.holdings
                    .font(.system(size: 12))
                    .foregroundStyle(Color.trackTicket)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(isChosen ? AnyShapeStyle(Color.trackAttended)
                                          : AnyShapeStyle(.tertiary))
        }
        .padding(16)
    }
}

extension EventernoteProfile {
    /// What the account is carrying, as the line under its name.
    ///
    /// A count that disagrees with what the reader remembers is how a mistyped
    /// handle gives itself away.
    var holdings: Text {
        let events = eventCount.map {
            Text("^[\($0) event](inflect: true)")
        } ?? Text("Events")
        guard !favoritePerformers.isEmpty else { return events }
        return events + Text(verbatim: " · ")
            + Text("^[\(favoritePerformers.count) favorite performer](inflect: true)")
    }
}

/// A member's Eventernote picture, or the placeholder for an account without one.
struct AccountAvatar: View {
    var url: URL?
    var width: CGFloat = 52

    var body: some View {
        Circle()
            .fill(.quaternary)
            .overlay {
                CachedImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.fill")
                        .font(.system(size: width * 0.42))
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(.circle)
            .frame(width: width, height: width)
            .accessibilityHidden(true)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            EventernoteAccountSheet()
                .environment(EventStore.preview)
        }
}
