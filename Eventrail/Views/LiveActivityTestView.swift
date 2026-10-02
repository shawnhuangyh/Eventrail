#if DEBUG
@preconcurrency import ActivityKit
import SwiftUI
import UIKit

/// A bench for the Live Activity, in debug builds only, opened from the
/// event sheet's menu: starts one for the event in front of it with its night
/// moved to just ahead of now, so every stage — and the island, the watch's
/// Smart Stack and the Mac's menu bar — can be looked at without waiting for
/// two hours before somebody's doors.
///
/// Its activities are filed under `test-` and the event's id rather than the
/// event's own, so ``EventActivities`` keeps them as they were asked for: a
/// refresh re-reads a kept event's times from the store, and ends one whose
/// event is not in the library. The words are not localized; nobody but the
/// developer sees them.
struct LiveActivityTestView: View {
    let event: Event

    @Environment(\.dismiss) private var dismiss
    @State private var seat: String
    /// Minutes from now to the start; below zero, the show began that long ago.
    @State private var startsIn = 7
    @State private var hasDoors = true
    /// Minutes the doors open before the start.
    @State private var doorsBefore = 5
    @State private var hasEnd = true
    /// Minutes the show runs.
    @State private var length = 10
    /// The Lock Screen draws ``GateDiagnostics`` in place of the card.
    @State private var showsDiagnostics = false
    @State private var isStarting = false
    @State private var failure: String?

    init(event: Event, seat: String) {
        self.event = event
        _seat = State(initialValue: seat.isEmpty ? "1階 L列 23番" : seat)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preset("Doors in 2 min, then every stage", startsIn: 7, doorsBefore: 5, length: 10)
                    preset("Doors in 61 min: island turns from the time to 59:59 in a minute",
                           startsIn: 91, doorsBefore: 30, length: 60)
                    preset("Doors open", startsIn: 20, doorsBefore: 25, length: 30)
                    preset("Starting soon", startsIn: 4, doorsBefore: 30, length: 30)
                    preset("On now, ends in 10 min", startsIn: -20, doorsBefore: 30, length: 30)
                    preset("Ends in 1 min", startsIn: -59, doorsBefore: 30, length: 60)
                    preset("Scheduled, comes on in 2 min",
                           startsIn: Int(EventActivityStage.lead / 60) + 2 + 30, doorsBefore: 30, length: 60)
                } header: {
                    Text(verbatim: "Presets")
                }

                Section {
                    Stepper(value: $startsIn, in: -600...1440) {
                        row("Start", minutes: startsIn, at: starts)
                    }
                    Toggle(isOn: $hasDoors) { Text(verbatim: "Doors published") }
                    if hasDoors {
                        Stepper(value: $doorsBefore, in: 1...300) {
                            row("Doors \(doorsBefore) min before", at: doors)
                        }
                    }
                    Toggle(isOn: $hasEnd) { Text(verbatim: "End published") }
                    if hasEnd {
                        Stepper(value: $length, in: 1...600) {
                            row("Runs \(length) min", at: ends)
                        }
                    }
                } header: {
                    Text(verbatim: "Times")
                } footer: {
                    Text(verbatim: opens > .now
                         ? "Scheduled: the system starts it at \(clock(opens)), two hours before the \(hasDoors ? "doors" : "start")."
                         : "Starts at once.")
                }

                Section {
                    TextField(text: $seat) { Text(verbatim: "Seat") }
                } header: {
                    Text(verbatim: "Seat")
                }

                Section {
                    Toggle(isOn: $showsDiagnostics) { Text(verbatim: "Gate diagnostics card") }
                } footer: {
                    Text(verbatim: "Draws test swatches on the Lock Screen in place of the card, to read off what each renderer makes of the gate's pieces.")
                }

                Section {
                    Button(action: start) {
                        Text(verbatim: opens > .now ? "Schedule Test Activity" : "Start Test Activity")
                    }
                    .disabled(isStarting || !EventActivities.shared.isEnabled)
                    Button(role: .destructive) {
                        Task { await EventActivities.shared.endTests() }
                    } label: {
                        Text(verbatim: "End Test Activities")
                    }
                } footer: {
                    if !EventActivities.shared.isEnabled {
                        Text(verbatim: "Live Activities are off for Eventrail on this device.")
                    } else {
                        Text(verbatim: "Starting one ends any test activity already up. Lock the phone to see the Lock Screen and the island; turn the watch's crown up for its Smart Stack.")
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Test Live Activity"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(Text(verbatim: "Couldn't Start the Test Activity"),
                   isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } },
                   presenting: failure) { _ in
                Button("OK") {}
            } message: {
                Text(verbatim: $0)
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - The night asked for

    // Read as the steppers move, so the times beside them are always from now.
    private var starts: Date { Date.now.addingTimeInterval(TimeInterval(startsIn * 60)) }
    private var doors: Date? { hasDoors ? starts.addingTimeInterval(TimeInterval(-doorsBefore * 60)) : nil }
    private var ends: Date? { hasEnd ? starts.addingTimeInterval(TimeInterval(length * 60)) : nil }
    private var opens: Date { (doors ?? starts).addingTimeInterval(-EventActivityStage.lead) }

    private func start() {
        var night = event
        night.doorsOpen = doors
        night.startsAt = starts
        night.endsAt = ends
        let seat = seat
        let diagnostics = showsDiagnostics
        isStarting = true
        Task {
            defer { isStarting = false }
            do {
                try await EventActivities.shared.startTest(for: night, seat: seat, diagnostics: diagnostics)
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    // MARK: - Rows

    private func preset(_ name: String, startsIn: Int, doorsBefore: Int, length: Int) -> some View {
        Button {
            self.startsIn = startsIn
            self.doorsBefore = doorsBefore
            self.length = length
            hasDoors = true
            hasEnd = true
        } label: {
            Text(verbatim: name)
        }
    }

    private func row(_ name: String, minutes: Int? = nil, at instant: Date?) -> some View {
        HStack {
            if let minutes {
                Text(verbatim: "\(name) in \(minutes) min")
            } else {
                Text(verbatim: name)
            }
            Spacer()
            Text(verbatim: instant.map(clock) ?? "—")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func clock(_ instant: Date) -> String {
        instant.formatted(date: .omitted, time: .shortened)
    }
}

extension EventActivities {
    /// Starts — or, before its window, schedules — an activity for `event`
    /// as given, its times already moved, under a test id. Scheduling is the
    /// bench's alone now (``start(for:tracking:)`` only ever starts one, at
    /// once), kept for watching a stage come on by itself. Ends any test
    /// activity already up first, so a run of tries does not reach the
    /// system's limit. With `diagnostics`, it is filed so that the extension
    /// draws its gate swatches on the Lock Screen instead of the card.
    func startTest(for event: Event, seat: String, diagnostics: Bool = false) async throws {
        await endTests()
        let now = Date.now
        guard var state = Self.state(for: event, seat: seat, at: now) else { return }
        let id = (diagnostics ? "test-diag-" : "test-") + event.id
        await Self.keepTestPoster(for: event, as: id)
        let opens = (state.doors ?? state.starts).addingTimeInterval(-EventActivityStage.lead)
        let attributes = EventActivityAttributes(
            eventID: id, title: event.title, venue: event.venue,
            link: event.sourceURL, opens: max(opens, now))
        if opens > now {
            state.stage = state.stage(at: opens)
            var style = Date.FormatStyle(date: .omitted, time: .shortened)
            style.timeZone = state.timeZone
            let body = "Doors open at \((state.doors ?? state.starts).formatted(style))"
            let alert = AlertConfiguration(
                title: LocalizedStringResource(stringLiteral: event.title),
                body: LocalizedStringResource(stringLiteral: body),
                sound: .default)
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: state.nextChange),
                pushType: nil, style: .standard, alertConfiguration: alert, start: opens)
        } else {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: state.nextChange),
                pushType: nil)
        }
        // Picks the new one up, and sets the wake for its next stage.
        await refresh()
    }

    /// Ends every test activity, running or scheduled.
    func endTests() async {
        for activity in Activity<EventActivityAttributes>.activities
        where activity.attributes.eventID.hasPrefix("test-") {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// The event's flyer where the extension reads it, filed under the test
    /// id — sized as the real one is.
    private static func keepTestPoster(for event: Event, as id: String) async {
        guard let url = event.imageURL, let file = EventActivityAttributes.posterFile(for: id) else { return }
        var image = await ImageCache.shared.storedImage(for: url)
        if image == nil { image = await ImageCache.shared.image(for: url) }
        guard let image else { return }
        let size = CGSize(width: 108, height: 150)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let poster = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(origin: CGPoint(x: (size.width - drawn.width) / 2,
                                                  y: (size.height - drawn.height) / 2),
                                  size: drawn))
        }
        guard let data = poster.jpegData(compressionQuality: 0.8) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
#endif
