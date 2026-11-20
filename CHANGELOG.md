# Changelog

Changes in Eventrail's TestFlight builds. Each release pull request has the full list of changes.

## 1.0

### TestFlight update ([#31](https://github.com/shawnhuangyh/Eventrail/pull/31))

#### New

- **Lottery deadlines and results times.** Record when applications close and when results are announced on each round. The application deadline can be date-only. Deadline alerts default to one day in advance, and results reminders use the saved time or 20:00 when no time is set.
- **Ticket To-Dos.** Track payment deadlines and ticket pickup for won rounds from the Me tab. Mark tickets paid or issued directly from reminders. Payments due within 72 hours appear as Due Soon and count toward the Me badge.
- **Goods Sale card.** Keep the official sale link, the queue-ticket distribution time, and your queue tickets together on the event page. Goods Sale Alert defaults to one hour in advance.
- **Set lists.** From the day of an event, save its set-list link by scanning the QR code or selecting it from Photos.
- **Change Alerts.** Get notified when an upcoming saved event changes date, start time, or venue. Tap the alert to open What Changed. Enabled by default.
- **New Date Alerts.** Get notified when a followed performer adds a date. Enable it in Settings on iPhone or iPad.

#### Fixed

- Application, payment, and pickup reminders now respect the event date when it moves earlier.
- Mark as Issued from a pickup notification also marks payment complete when needed. Undo on a Ticket To-Do reverses the status change while preserving any other edits to the round.
- Change alerts open the right event when tapped while the app is becoming active.

#### Upgrading from earlier TestFlight builds

- Re-enter application, payment, and pickup times recorded as event reminders on the relevant lottery round. Earlier ticket-sale, goods-sale opening, and custom reminders stay in your records, but they no longer appear or send notifications. The earliest saved queue time is used for Queue Tickets Out. The Goods Sale Alert setting now controls the lead time for all goods-sale reminders.
- Earlier TestFlight builds cannot open backups exported by this build. Update every device using iCloud sync before editing lottery rounds. An older build can drop the new deadline, results time, payment, and pickup fields when it saves an edited round.

### Earlier TestFlight builds

September to November 2026, release pull requests #1 to #30.
