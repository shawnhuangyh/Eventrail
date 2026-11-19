# Changelog

What changed in each version of Eventrail that reached TestFlight. Every build is listed in full in its release pull request into `release`.

## 1.1

### New

- **Lottery deadlines and results times.** A lottery round can hold the day applications close and, where the notice gives one, the time. It can also hold the time results are announced. Both are written on one row each on the round's page. The deadline has to fall on a day before the results.
  - A notification comes before the deadline closes. How far ahead is one setting for every round, Settings › Deadline Alert (a day by default).
  - The results-day reminder comes at the results time where one is written, and at 20:00 otherwise, as before.
- **Ticket To-Dos.** A card on the Me tab, with a screen behind it, for what a won ticket still needs: paying by a deadline and picking the ticket up.
  - The payment deadline and the pickup are written on the won round's page. What is owed, where to pay and the order's page can be added too.
  - Each to-do moves from Awaiting Payment to Paid to Issued. A step can be marked from the list, from its sheet, or from the notification's button without opening the app. Undo stands for six seconds.
  - A payment due within 72 hours is Due Soon, and the count shows on the Me tab's badge.
- **The goods sale card.** The event sheet's plan card is now Goods Sale (会場物販), with everything under one heading:
  - **Sale Info**: paste the link to the promoter's post. Tapping it opens the post, in the X app where it is installed. The row shows the address without what X adds when a post is shared.
  - **Queue Tickets Out**: when queue tickets are handed out, written on the hall's clock.
  - Your queue tickets, with Add Queue Ticket as the last row.
  - How far ahead to hear is one setting, Settings › Goods Sale Alert (an hour by default).
- **Set lists.** From the day of the event, keep the link in a set list's QR code, scanned or picked from Photos, the way a queue ticket is kept.
- **Change Alerts.** A notification when a kept event still to come moves to another day, start time or hall. Tapping it opens the event on its What Changed card. On by default, with a switch in Settings.
- **New Date Alerts.** A notification when somebody you follow has a new date, checked in the background. Off by default, with a switch in Settings. Not on the Mac.

### Changed

- The plan card no longer asks for ticket-sale times (applications closing, payment, pickup), the goods sale's opening, or times under a name of your own. A round's deadline, payment and pickup now live on the round. Times like these written in 1.0 stay in your record, but they aren't shown or notified any more.
- Priority check-in, random queue tickets closing and last-in-line tickets opening are one time now, Queue Tickets Out. Where 1.0 holds more than one of them, the earliest is shown.
- How far ahead to hear about a goods sale is now Settings › Goods Sale Alert. A lead set on a single time in 1.0 is no longer used.
- Settings › Event Reminders is now Goods Sale Reminders. Lottery Reminders now also covers deadlines, payments and pickups.

### Worth knowing

- Backups made by 1.1 can't be opened by 1.0.
- Run 1.1 on every device you sync. 1.0 keeps what 1.1 writes but doesn't show it, and a lottery round edited in 1.0 loses its deadline, results time, payment and pickup.

## 1.0

The TestFlight builds from September to November 2026, release pull requests #1 to #30.
