import SwiftUI

/// Names the Eventernote account the reader imports their history from.
///
/// Nothing here signs in. Eventernote publishes every member's attended events
/// on a page anyone can load, so the app only needs to be told *which* member —
/// it never holds a password, a session or a cookie of theirs, and it still only
/// ever reads. The handle is confirmed against the live page before it is kept,
/// because a mistyped one would import a stranger's history into their library.
struct EventernoteAccountSheet: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var typed = ""
    @State private var found: EventernoteProfile?
    @State private var isLooking = false
    @State private var failure: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    entryCard
                    if let found {
                        foundCard(found)
                    }
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
                        guard let found else { return }
                        store.link(found)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .disabled(found == nil)
                }
            }
        }
        .onAppear {
            typed = store.eventernoteHandle ?? ""
            isFocused = typed.isEmpty
        }
    }

    private var entryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your account name")
                .font(.system(size: 14, weight: .semibold))

            HStack(spacing: 8) {
                Text(verbatim: "@")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.tertiary)
                // The handle is a login name, so none of the keyboard's help
                // applies to it — every correction it makes here is a wrong one.
                TextField("account", text: $typed)
                    .font(.system(size: 16))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isFocused)
                    .onSubmit { Task { await look() } }
                    .onChange(of: typed) { found = nil; failure = nil }

                Button {
                    Task { await look() }
                } label: {
                    Text(isLooking ? "Checking" : "Find")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.brandTint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .glassCapsule(interactive: true)
                .disabled(isLooking || typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let failure {
                Text(verbatim: failure)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.favorite)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("It is the name in your Eventernote profile's address, after /users/.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .glassPanel()
    }

    /// What the reader is about to link, shown before the app commits to it.
    private func foundCard(_ profile: EventernoteProfile) -> some View {
        HStack(spacing: 14) {
            AccountAvatar(url: profile.avatarURL, width: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: profile.name)
                    .font(.system(size: 16, weight: .semibold))
                Text(verbatim: "@\(profile.handle)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                profile.holdings
                    .font(.system(size: 12))
                    .foregroundStyle(Color.trackTicket)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .glassPanel()
    }

    private var explanation: some View {
        Text("Eventrail reads the same public page anyone visiting your profile would see. It does not sign in, and it never writes anything back to Eventernote. Events you have already removed here stay removed. The first import marks the events you have been to as attended and the ones still to come as planned, wherever you have not answered for yourself; later imports only rule on the events they add.")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 4)
    }

    private func look() async {
        guard !isLooking else { return }
        isLooking = true
        failure = nil
        found = nil
        defer { isLooking = false }

        do {
            found = try await store.lookUpAccount(typed)
            isFocused = false
        } catch let error as EventernoteClient.Failure {
            failure = error.errorDescription
        } catch {
            failure = String(localized: "Could not reach Eventernote. Try again in a moment.")
        }
    }
}

extension EventernoteProfile {
    /// What the account is carrying, as the line under its name.
    ///
    /// Shared by the two screens that confirm an account before linking it —
    /// ``EventernoteAccountSheet`` and ``WelcomeView`` — because it is the
    /// same question in both: is this the record the reader meant. A count
    /// that disagrees with what they remember is how a mistyped handle gives
    /// itself away.
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
                AsyncImage(url: url) { image in
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
