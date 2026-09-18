import SwiftUI
import UniformTypeIdentifiers

/// The four cards Eventrail opens with the first time it is launched.
///
/// It asks only what the app cannot work out on its own, and the three
/// questions are the arc of the reader's own records: where they come *in*
/// from (an Eventernote account, or a backup file they kept), where they live
/// *across* their devices (iCloud), and what Eventrail writes *out* to
/// something else of theirs (their calendar). Everything else the app can
/// decide for itself, so it is not asked here — an onboarding that collects
/// settings the reader has no opinion about yet is a form, not a welcome.
///
/// Every answer is optional. Skipping the account leaves the library empty
/// rather than wrong, and both switches start off — the calendar one for the
/// reason ``EventStore/calendarSyncEnabled`` gives: writing to someone's diary
/// is not something to start doing on their behalf, and a switch they tapped
/// past without reading is not their consent. The screens sell them instead.
///
/// Shown from ``RootView`` over everything, once per device, and reachable
/// again from Settings. Nothing here is a one-way door: both answers are the
/// same two rows Settings and the Me tab already carry.
struct WelcomeView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The key ``RootView`` reads to decide whether this has been seen.
    ///
    /// Per-device, in `UserDefaults` and deliberately not synced, for the same
    /// reason ``EventStore/iCloudSyncEnabled`` is not: a fresh install on an
    /// iPad is a first launch on the iPad, whatever the phone has already been
    /// through.
    ///
    /// Written by ``finish()`` and nowhere else, so it means the reader reached
    /// the end rather than that the screen was on the glass at some point.
    static let seenKey = "hasSeenWelcome"

    /// Records before calendar on purpose: the first two bring the reader's
    /// library in, and there is nothing worth mirroring to a diary until they
    /// have. A reader who restores a backup on step three lands on step four
    /// with the events that switch is about already in front of them.
    private enum Step: Int, CaseIterable {
        case hello, account, records, calendar
    }

    @State private var step: Step = .hello

    // What step two is holding: what was typed, who it turned out to be, and
    // whether the reader has said yes to them.
    @State private var typed = ""
    @State private var found: EventernoteProfile?
    @State private var picked = false
    @State private var isLooking = false
    /// A handle nobody goes by, as opposed to a page that would not load.
    @State private var missed = false
    @State private var failure: String?
    @FocusState private var isFocused: Bool

    // Step three: where the reader's own records live.
    @State private var wantsCloud = false
    @State private var isChoosingBackup = false
    /// The file they picked, handed to ``BackupRestore`` to read.
    @State private var pickedBackup: URL?

    /// Step four's answer. Both switches are seeded from the store so a second
    /// visit shows them where the reader left them rather than where they start.
    @State private var wantsCalendar = false

    private var query: String { typed.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .padding(.horizontal, 16)
                    .padding(.top, 22)
                    .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .washBackground()
        .onAppear {
            typed = store.eventernoteHandle ?? ""
            wantsCloud = store.iCloudSyncEnabled
            wantsCalendar = store.calendarSyncEnabled
        }
        .task(id: query) { await look() }
        // JSON beside the app's own type for the reason Settings gives: a
        // `library.json` lifted off a device is still readable here.
        .fileImporter(isPresented: $isChoosingBackup,
                      allowedContentTypes: [.eventrailBackup, .json]) { result in
            pickedBackup = try? result.get()
        }
        // No second question: they picked this out of a picker they opened
        // from a row that says Restore.
        .restoringBackup($pickedBackup, asking: false)
        .animation(.snappy(duration: 0.28), value: step)
    }

    // MARK: - Where in the three the reader is

    private var header: some View {
        HStack(spacing: 8) {
            if step != .hello {
                Button {
                    step = Step(rawValue: step.rawValue - 1) ?? .hello
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.brandTint)
                        .frame(width: 36, height: 36)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassCircle(interactive: true)
                .accessibilityLabel("Back")
                .transition(.opacity)
            }
            Spacer(minLength: 0)
            progress
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .frame(height: 46)
    }

    /// Three capsules, the one being read stretched. A step count rather than
    /// a title: the card underneath is already saying what this step is.
    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { each in
                Capsule()
                    .fill(each == step ? Color.brandTint : Color.primary.opacity(0.2))
                    .frame(width: each == step ? 20 : 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .hello: hello
        case .account: account
        case .records: records
        case .calendar: calendar
        }
    }

    // MARK: - One: what this is

    private var hello: some View {
        VStack(spacing: 28) {
            AppIconBadge(width: 104)
            VStack(spacing: 12) {
                Text("Welcome to\nEventrail")
                    .font(.system(size: 36, weight: .bold))
                    .kerning(-1.2)
                    .lineSpacing(-2)
                    .multilineTextAlignment(.center)
                Text("Your Eventernote live history and the shows still ahead — kept on this device, in your hands.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 288)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 54)
    }

    // MARK: - Two: whose record this is

    /// Named, not searched. Eventernote publishes no member search, so the one
    /// honest question here is "is there an account by this name" — which is
    /// the same confirmation ``EventernoteAccountSheet`` does, because a
    /// mistyped handle would import a stranger's history into their library.
    private var account: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("Find your account",
                    "Name your Eventernote account to bring in the events you have already been to. Read only — no password, and nothing is written back.")

            field

            VStack(alignment: .leading, spacing: 9) {
                if let label = resultLabel {
                    Text(label)
                        .font(.system(size: 11.5, weight: .semibold))
                        .kerning(0.35)
                        .textCase(.uppercase)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                }
                if let found {
                    result(found)
                } else if missed {
                    note(Text("No Eventernote user goes by that name. Check the spelling, or skip — you can name an account any time from Me."))
                } else if let failure {
                    note(Text(verbatim: failure))
                }
            }
        }
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

    /// Who the name turned out to be, and a tap to say yes or change their
    /// mind — the reader confirms the account before anything is linked.
    ///
    /// The same row ``EventernoteAccountSheet`` shows, down to the tick.
    private func result(_ profile: EventernoteProfile) -> some View {
        Button {
            picked.toggle()
            isFocused = false
        } label: {
            FoundAccount(profile: profile, isChosen: picked)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassPanel(interactive: true)
        .accessibilityAddTraits(picked ? [.isSelected] : [])
    }

    // MARK: - Three: where the reader's own records live

    /// Two halves of one question, which is why they share a screen and a
    /// heading. iCloud keeps this device and the next one agreeing, so a
    /// removal travels between them; a backup file is the one copy nothing
    /// done in the app afterwards can reach. A reader arriving on a second
    /// device wants the first; a reader arriving after a reinstall wants the
    /// second, and neither of them should have to go looking in Settings for
    /// it on the day they have the least to lose by not finding it.
    private var records: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("Pick up where you left off",
                    "If you have used Eventrail before, this is how what you kept gets here — from your other devices, or from a file you saved.")

            Toggle(isOn: $wantsCloud) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("iCloud Sync")
                        .font(.system(size: 14, weight: .semibold))
                    cloudDetail
                        .font(.system(size: 11.5))
                        .foregroundStyle(cloudNeedsAttention ? Color.favorite : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            // A switch that cannot do anything is worse than no switch: this
            // build has no iCloud capability, and the line underneath says so.
            .disabled(store.syncStatus == .notConfigured)
            .glassPanel()

            Button {
                isChoosingBackup = true
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Restore from Backup")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Read an .eventrail file you exported before, or a library.json lifted off an old device")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .glassPanel(interactive: true)

            Text("A restore only ever adds: it puts back what the file holds and this device does not, and erases nothing you already have. Read it now or later — Settings keeps the same two rows.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
    }

    /// The same promise Settings makes, and the same refusal to make it when
    /// iCloud cannot keep it: a build without the capability, or a device
    /// signed out, says so rather than showing a switch that does nothing.
    private var cloudDetail: Text {
        switch store.syncStatus {
        case .notConfigured:
            Text("This build cannot use iCloud yet — it needs the iCloud capability enabled for the app")
        case .signedOut:
            Text("Sign in to iCloud in Settings to sync this library")
        case .failed(let reason):
            Text(verbatim: reason)
        default:
            wantsCloud
                ? Text("Your events, notes and tracking travel privately between your devices")
                : Text("This device only — nothing leaves it")
        }
    }

    private var cloudNeedsAttention: Bool {
        switch store.syncStatus {
        case .notConfigured, .signedOut, .failed: true
        default: false
        }
    }

    // MARK: - Three: whether it reaches their calendar

    private var calendar: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("Keep it in your calendar",
                    "Every event in your library can be mirrored into your own calendar, with doors and start time. Your call — and reversible in Settings.")

            VStack(spacing: 0) {
                Toggle(isOn: $wantsCalendar) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Calendar Sync")
                            .font(.system(size: 14, weight: .semibold))
                        Text(wantsCalendar
                             ? "Events in your library are added to your calendar"
                             : "Nothing is written to your calendar")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)

                if wantsCalendar {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        promise("Doors and start time, venue and floor, on the right day")
                        promise("Edits and cancellations follow your library")
                        promise("Past events you attended are filled in too")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 13)
                    .padding(.bottom, 15)
                }
            }
            .glassPanel()

            Text("A calendar named Eventrail is created on this device. Nothing else in your calendar is touched.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
        // Nothing here asks for calendar access on the way in. The system's
        // permission sheet is the answer to the switch and to nothing else,
        // so it is only reached once the reader has finished this screen.
        .animation(.snappy(duration: 0.24), value: wantsCalendar)
    }

    private func promise(_ label: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.trackAttended)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Shared furniture

    private func heading(_ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .kerning(-0.84)
            Text(detail)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 6)
    }

    /// Takes a `Text` rather than a key: one of the two things said here is a
    /// message the client already localized, and looking it up a second time
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

    // MARK: - What carries on

    private var footer: some View {
        VStack(spacing: 2) {
            if step == .account {
                Button("Skip for now") {
                    typed = ""
                    isFocused = false
                    step = .calendar
                }
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(Color.brandTint)
                .padding(.top, 6)
                .padding(.bottom, 8)
            }

            // The system's own prominent glass rather than a flat fill: it is
            // the one thing on this screen that is always tappable, and on iOS
            // 26 that is what a primary action is made of. The tint carries the
            // app's colour through it instead of painting over it.
            Button(action: advance) {
                callToAction
                    .font(.system(size: 16.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .tint(Color.brandTint)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    private var callToAction: Text {
        switch step {
        case .hello:
            Text("Get Started")
        case .account:
            if picked, let found {
                Text("Continue as @\(found.handle)")
            } else {
                Text("Continue")
            }
        case .records:
            Text("Continue")
        case .calendar:
            Text("Done")
        }
    }

    private func advance() {
        isFocused = false
        guard step == .calendar else {
            step = Step(rawValue: step.rawValue + 1) ?? .calendar
            return
        }
        finish()
    }

    /// The only place this screen writes anything.
    ///
    /// Both answers are applied at the end rather than as they are given, so a
    /// reader who backs out of a step has not already changed the app by
    /// visiting it.
    private func finish() {
        if picked, let found {
            // A fresh link is a library waiting to be filled, and the screen
            // has just promised to fill it. Re-naming the account already held
            // is not: there is nothing new to read until the reader asks.
            let isNewAccount = found.handle != store.eventernoteHandle
            store.link(found)
            if isNewAccount {
                Task { await store.refresh() }
            }
        }
        store.iCloudSyncEnabled = wantsCloud
        store.calendarSyncEnabled = wantsCalendar
        // Recorded here rather than by whoever presented this, so that only
        // reaching the end counts as having been welcomed. A reader shown this
        // again from Settings is writing the same true a second time.
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        dismiss()
    }

    /// Confirms the typed name against the live page, a pause after the last
    /// keystroke rather than on every one. `task(id:)` cancels the previous
    /// look on each change, so only the name they stopped on is ever asked for.
    private func look() async {
        found = nil
        picked = false
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
            // One exact match and nothing to choose between: it is taken as
            // the answer, and the row is still there to take it back.
            picked = true
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

#Preview {
    WelcomeView()
        .environment(EventStore.preview)
}
