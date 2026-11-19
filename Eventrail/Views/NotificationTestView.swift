#if DEBUG
import SwiftUI
import UIKit
import UserNotifications

/// How the bench's notifications are told from the app's own: the real request
/// with only its name and its moment changed.
///
/// Filed under `test-` rather than under a real prefix, so the three reminders
/// keep them as they were asked for: each takes back whatever it finds under
/// its own prefix that the library does not call for, pending or delivered. A
/// tap is routed as the real one's (``routed(_:)``).
nonisolated enum TestNotification {
    static let prefix = "test-"

    /// `real`'s words, level, stack and destination, coming in `seconds`. Each
    /// its own, so that several can be sent to watch them stack.
    static func request(standingInFor real: UNNotificationRequest, in seconds: TimeInterval) -> UNNotificationRequest {
        UNNotificationRequest(identifier: "\(prefix)\(real.identifier).\(UUID().uuidString)",
                              content: real.content,
                              trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false))
    }

    /// The name a tap is routed by: that of the notification stood in for.
    static func routed(_ identifier: String) -> String {
        identifier.hasPrefix(prefix) ? String(identifier.dropFirst(prefix.count)) : identifier
    }
}

/// A bench for the app's notifications, in debug builds only, opened from the
/// event sheet's menu as ``LiveActivityTestView`` is: sends one of the seven
/// about the event in front of it within seconds, so the banner, the Lock
/// Screen, a Focus and a tap can be looked at without waiting for somebody's
/// goods sale. Beside that, what the app has scheduled and what the system
/// allows it.
///
/// Nothing is written to the library, and an event gone by can be sent one the
/// app itself never would. The words on the bench are not localized; nobody but
/// the developer sees them. The notification's own are the real ones.
struct NotificationTestView: View {
    let event: Event
    let tracking: Tracking

    @Environment(\.dismiss) private var dismiss
    @State private var kind = Kind.eventReminder
    /// Which of the event's goods times to send; nil is a sample.
    @State private var reminderID: EventReminder.ID?
    @State private var delay = 10
    @State private var permission = Permission()
    @State private var scheduled: [Scheduled] = []
    @State private var deliveredTests: [String] = []
    @State private var failure: String?

    private var center: UNUserNotificationCenter { .current() }

    init(event: Event, tracking: Tracking) {
        self.event = event
        self.tracking = tracking
        _reminderID = State(initialValue: ReminderKind.goods.compactMap(tracking.goodsReminder).first?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                sendSection
                saysSection
                testsSection
                scheduledSection
                permissionSection
            }
            .navigationTitle(Text(verbatim: "Test Notifications"))
            .navigationBarTitleDisplayMode(.inline)
            .padNavigationBarOnMac()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .alert(Text(verbatim: "Couldn't Send the Test Notification"),
                   isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } },
                   presenting: failure) { _ in
                Button("OK") {}
            } message: {
                Text(verbatim: $0)
            }
        }
        .presentationDetents([.medium, .large])
        // A tap on what this sends is what it is here to try, usually with
        // this still up.
        .opensFromOutside()
        .task {
            // The system says nothing when one is delivered.
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Sending

    private var sendSection: some View {
        Section {
            Picker(selection: $kind) {
                ForEach(Kind.offered) { Text(verbatim: $0.rawValue).tag($0) }
            } label: {
                Text(verbatim: "Notification")
            }
            if kind == .eventReminder {
                Picker(selection: $reminderID) {
                    Text(verbatim: "Sample: \(ReminderKind.queueTime.label)").tag(EventReminder.ID?.none)
                    ForEach(ReminderKind.goods.compactMap(tracking.goodsReminder)) { reminder in
                        Text(verbatim: ReminderKind.label(of: reminder.title)).tag(EventReminder.ID?.some(reminder.id))
                    }
                } label: {
                    Text(verbatim: "Reminder")
                }
            }
            Picker(selection: $delay) {
                ForEach([5, 10, 30, 60, 300], id: \.self) {
                    Text(verbatim: $0 < 60 ? "\($0) s" : "\($0 / 60) min").tag($0)
                }
            } label: {
                Text(verbatim: "Comes In")
            }
            Button(action: send) {
                Text(verbatim: "Send Test Notification")
            }
            .disabled(real == nil || !permission.canNotify)
        } footer: {
            Text(verbatim: "Lock the phone before it comes to see it on the Lock Screen. A tap goes where the real one goes: a Live Activity one also starts the event's real activity, where it can.")
        }
    }

    private var saysSection: some View {
        Section {
            if let content = real?.content {
                line("Title", content.title)
                line("Subtitle", content.subtitle)
                line("Body", content.body)
                line("Level", Self.level(of: content))
            }
        } header: {
            Text(verbatim: "It Will Say")
        } footer: {
            if kind == .resultsDay || kind == .lotteryDeadline || kind == .ticketStep, tracking.lotteries.isEmpty {
                Text(verbatim: "This event has no rounds, so a tap opens its sheet rather than Ticket Details on a round.")
            }
        }
    }

    /// The real request for what is chosen, whatever the moment: the bench
    /// keeps its content and gives it a moment of its own.
    private var real: UNNotificationRequest? {
        switch kind {
        case .eventReminder:
            let reminder = tracking.reminders.first { $0.id == reminderID } ?? EventReminder(kind: .queueTime, for: event)
            // Ahead by what Settings says — an hour where it says none, since
            // the bench sends one anyway — and from long ago, when its moment
            // and the event's day are ahead.
            let lead = EventReminders.shared.goodsLead ?? EventReminders.defaultGoodsLead
            return ReminderAlert(reminder: reminder, event: event, lead: lead, clock: .stored, at: .distantPast)?.request
        case .resultsDay:
            let entry = tracking.lotteries.first(where: \.isPending) ?? tracking.lotteries.first
            return LotteryReminder(testing: event, entry: entry).request
        case .lotteryDeadline:
            // The round's own deadline where one is written, else tonight's
            // 23:59, ahead by what Settings says — a day where it says none,
            // since the bench sends one anyway.
            let entry = tracking.lotteries.first { $0.deadline != nil }
                ?? tracking.lotteries.first(where: \.isPending)
                ?? LotteryEntry(round: LotteryRound.earliest.rawValue)
            let deadline = entry.deadline ?? LotteryDeadline(day: CalendarDay(.now, in: .gregorian(in: event.timeZone)),
                                                             minute: LotteryDeadline.closingMinute)
            let lead = LotteryReminders.shared.deadlineLead ?? LotteryReminders.defaultDeadlineLead
            return LotteryDeadlineAlert(event: event, entry: entry, deadline: deadline, lead: lead, comingAt: .now,
                                        clock: .stored).request
        case .ticketStep:
            // A won round's payment where one is written, else a sample due
            // tonight, ahead by what Settings says — a day where it says none.
            var entry = tracking.lotteries.first { $0.isWon && $0.payment != nil }
                ?? tracking.lotteries.first(where: \.isWon)
                ?? LotteryEntry(round: LotteryRound.earliest.rawValue, result: .won(nil))
            if entry.payment == nil {
                var payment = TicketMoment(day: CalendarDay(.now, in: .gregorian(in: event.timeZone)),
                                           minute: TicketStage.payment.dayAloneMinute)
                payment.owed = Money(amount: 17_600, currency: Currencies.yen)
                payment.payAt = "セブン-イレブン"
                entry.payment = payment
            }
            let lead = LotteryReminders.shared.deadlineLead ?? LotteryReminders.defaultDeadlineLead
            return TicketStageAlert(event: event, entry: entry, stage: .payment, lead: lead, comingAt: .now,
                                    clock: .stored).request
        case .liveActivity:
            return ActivityReminder(testing: event).request
        case .newDate:
            return NewDateAlert(dates: [event], names: { _ in event.performers.prefix(1).map(\.name) },
                                clock: .stored)?.request
        case .change:
            // Made up: the start an hour later than it was, or the day
            // after it, where none is printed. A tap opens the sheet on it.
            var was = event
            if let start = event.startsAt {
                was.startsAt = start.addingTimeInterval(-60 * 60)
            } else {
                was.date = event.date.addingTimeInterval(-24 * 60 * 60)
            }
            return ChangeAlert(from: ListingCopy(was), to: event, clock: .stored)?.request
        }
    }

    private func send() {
        guard let real else { return }
        let test = TestNotification.request(standingInFor: real, in: TimeInterval(delay))
        Task {
            do {
                try await center.add(test)
            } catch {
                failure = error.localizedDescription
            }
            await refresh()
        }
    }

    // MARK: - What stands

    private var tests: [Scheduled] { scheduled.filter(\.isTest) }

    private var testsSection: some View {
        Section {
            if tests.isEmpty {
                line("Waiting", "None")
            } else {
                ForEach(tests, content: row)
            }
            line("Delivered, Still Listed", "\(deliveredTests.count)")
            Button(role: .destructive) {
                center.removePendingNotificationRequests(withIdentifiers: tests.map(\.id))
                center.removeDeliveredNotifications(withIdentifiers: deliveredTests)
                Task { await refresh() }
            } label: {
                Text(verbatim: "Take Back Test Notifications")
            }
            .disabled(tests.isEmpty && deliveredTests.isEmpty)
        } header: {
            Text(verbatim: "Sent From Here")
        }
    }

    /// What the app itself has scheduled for this event, and against the
    /// limits of ``LotteryReminder``, ``ReminderAlert`` and ``ActivityReminder``.
    private var scheduledSection: some View {
        let own = scheduled.filter { !$0.isTest }
        let forEvent = own.filter { $0.eventID == event.id }
        func count(_ prefix: String) -> Int { own.filter { $0.id.hasPrefix(prefix) }.count }
        return Section {
            if forEvent.isEmpty {
                line("This Event", "None")
            } else {
                ForEach(forEvent, content: row)
            }
            line("Lotteries", "\(count(LotteryReminder.prefix) + count(LotteryDeadlineAlert.prefix) + count(TicketStageAlert.prefix)) of \(LotteryReminder.limit)")
            line("Goods Sale", "\(count(ReminderAlert.prefix)) of \(ReminderAlert.limit)")
            line("Live Activity", "\(count(ActivityReminder.prefix)) of \(ActivityReminder.limit)")
            line("All Pending", "\(scheduled.count) of 64")
        } header: {
            Text(verbatim: "Scheduled by the App")
        }
    }

    private var permissionSection: some View {
        Section {
            line("Permission", permission.statusName)
            line("Alerts", Self.name(of: permission.alerts))
            line("Time Sensitive", Self.name(of: permission.timeSensitive))
            if permission.status == .notDetermined {
                Button {
                    Task {
                        // As the app itself asks.
                        _ = try? await center.requestAuthorization(options: [.alert, .sound])
                        await refresh()
                    }
                } label: {
                    Text(verbatim: "Ask for Permission")
                }
            } else if permission.status == .denied {
                Link(destination: URL(string: UIApplication.openNotificationSettingsURLString)!) {
                    Text(verbatim: "Open Settings")
                }
            }
        } header: {
            Text(verbatim: "What the System Allows")
        } footer: {
            Text(verbatim: "Time Sensitive reads Not Supported where the build is signed without the capability. To try one through a Focus, turn the Focus on and let Eventrail's Time Sensitive notifications through, then send one with an alert under a day ahead.")
        }
    }

    private func refresh() async {
        let settings = await center.notificationSettings()
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        permission = Permission(status: settings.authorizationStatus, alerts: settings.alertSetting,
                                timeSensitive: settings.timeSensitiveSetting)
        scheduled = pending.map(Scheduled.init).sorted {
            ($0.fires ?? .distantFuture, $0.id) < ($1.fires ?? .distantFuture, $1.id)
        }
        deliveredTests = delivered.filter { $0.hasPrefix(TestNotification.prefix) }
    }

    // MARK: - Rows

    private func line(_ name: String, _ value: String) -> some View {
        LabeledContent {
            Text(verbatim: value.isEmpty ? "—" : value)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(verbatim: name)
        }
    }

    private func row(_ item: Scheduled) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.title)
                Text(verbatim: item.level)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: item.fires?.formatted(.gregorian(in: .current).month().day().hour().minute().second()) ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    fileprivate static func level(of content: UNNotificationContent) -> String {
        content.interruptionLevel == .timeSensitive ? "Time Sensitive" : "Active"
    }

    private static func name(of setting: UNNotificationSetting) -> String {
        switch setting {
        case .enabled: "On"
        case .disabled: "Off"
        case .notSupported: "Not Supported"
        @unknown default: "Unknown"
        }
    }
}

private extension NotificationTestView {
    enum Kind: String, CaseIterable, Identifiable {
        case eventReminder = "Event Reminder"
        case resultsDay = "Results Day"
        case lotteryDeadline = "Lottery Deadline"
        case ticketStep = "Payment Deadline"
        case liveActivity = "Live Activity"
        case newDate = "New Date"
        case change = "Change"

        var id: String { rawValue }

        /// A Live Activity reminder is the iPhone's alone.
        static var offered: [Kind] {
            UIDevice.current.userInterfaceIdiom == .phone ? allCases : allCases.filter { $0 != .liveActivity }
        }
    }

    /// What the system says this device may do, read off its settings.
    struct Permission: Equatable {
        var status = UNAuthorizationStatus.notDetermined
        var alerts = UNNotificationSetting.notSupported
        var timeSensitive = UNNotificationSetting.notSupported

        var canNotify: Bool { status == .authorized || status == .provisional || status == .ephemeral }

        var statusName: String {
            switch status {
            case .notDetermined: "Not Asked"
            case .denied: "Denied"
            case .authorized: "Authorized"
            case .provisional: "Provisional"
            case .ephemeral: "Ephemeral"
            @unknown default: "Unknown"
            }
        }
    }

    /// One pending notification, as this screen lists it.
    struct Scheduled: Identifiable, Equatable {
        let id: String
        let title: String
        let level: String
        let eventID: String?
        let fires: Date?

        var isTest: Bool { id.hasPrefix(TestNotification.prefix) }

        init(_ request: UNNotificationRequest) {
            id = request.identifier
            title = request.content.title
            level = NotificationTestView.level(of: request.content)
            // Every one of the three names its event under this key.
            eventID = request.content.userInfo[ReminderAlert.eventKey] as? String
            fires = switch request.trigger {
            case let trigger as UNTimeIntervalNotificationTrigger: trigger.nextTriggerDate()
            case let trigger as UNCalendarNotificationTrigger: trigger.nextTriggerDate()
            default: nil
            }
        }
    }
}

extension LotteryReminder {
    /// The reminder of `entry`, or of a round the event does not have, whatever
    /// its results day says.
    init(testing event: Event, entry: LotteryEntry?) {
        eventID = event.id
        entryID = entry?.id ?? UUID()
        eventTitle = event.title
        round = entry?.round ?? LotteryRound.earliest.rawValue
        day = CalendarDay(.now, in: .gregorian())
        announced = nil
    }
}

extension ActivityReminder {
    /// The reminder of `event`, whether or not it has a ticket or a start.
    init(testing event: Event) {
        eventID = event.id
        eventTitle = event.title
        date = .now
    }
}
#endif
