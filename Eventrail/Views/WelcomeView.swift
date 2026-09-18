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

    /// Step two's answer, and the whole of what it keeps. The asking is
    /// ``AccountFinder``, which the Me tab's sheet shows too.
    @State private var chosen: EventernoteProfile?

    // Step three: where the reader's own records live.
    @State private var wantsCloud = false
    @State private var isChoosingBackup = false
    /// The file they picked, handed to ``BackupRestore`` to read.
    @State private var pickedBackup: URL?

    /// Step four's answer. Both switches are seeded from the store so a second
    /// visit shows them where the reader left them rather than where they start.
    @State private var wantsCalendar = false

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
            wantsCloud = store.iCloudSyncEnabled
            wantsCalendar = store.calendarSyncEnabled
        }
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

    /// A heading over ``AccountFinder``, and nothing else. Why it looks a name
    /// up rather than searching for one, and what it does with the answer, is
    /// written where that lives — this step and the Me tab's sheet are the same
    /// question in two frames.
    private var account: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("Find your account",
                    "Name your Eventernote account to bring in the events you have already been to. Read only — no password, and nothing is written back.")

            AccountFinder(chosen: $chosen)
        }
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

    // MARK: - What carries on

    private var footer: some View {
        VStack(spacing: 2) {
            if step == .account {
                Button("Skip for now") {
                    chosen = nil
                    step = .records
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
            if let chosen {
                Text("Continue as @\(chosen.handle)")
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
        if let chosen {
            // A fresh link is a library waiting to be filled, and the screen
            // has just promised to fill it. Re-naming the account already held
            // is not: there is nothing new to read until the reader asks.
            let isNewAccount = chosen.handle != store.eventernoteHandle
            store.link(chosen)
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

}

#Preview {
    WelcomeView()
        .environment(EventStore.preview)
}
