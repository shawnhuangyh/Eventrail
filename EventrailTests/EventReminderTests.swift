import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import Eventrail

/// The times a reader writes down for an event, the notifications they come
/// with and the queue tickets beside them — see ``EventReminder``,
/// ``EventReminders``, ``QueueTicket``, ``GoodsNotice`` and ``SetList``.
@MainActor
struct EventReminderTests {
    /// The goods sale of a Bushiroad night, as its notice prints it:
    /// ランダム整理券 until 11:30, 最後尾整理券 from 11:31, the sale from 12:00.
    let notice = CalendarDay(year: 2026, month: 11, day: 14)

    func reminder(_ kind: ReminderKind = .queueTime, on day: CalendarDay? = nil, at minute: Int = 12 * 60,
                  lead: Int? = 30) -> EventReminder {
        EventReminder(title: kind.rawValue, day: day ?? notice, minute: minute, lead: lead)
    }

    /// `days` from today, at midnight in Tokyo.
    func event(_ id: String = "1", inDays days: Int = 3, timeZone: TimeZone = Fixtures.tokyo) -> Event {
        Fixtures.event(id: id, date: Fixtures.day(fromToday: days), timeZone: timeZone)
    }

    /// A reminder on the event's own day.
    func reminder(on event: Event, at minute: Int = 12 * 60, lead: Int? = 30) -> EventReminder {
        EventReminder(title: ReminderKind.queueTime.rawValue,
                      day: CalendarDay(event.date, in: .gregorian(in: event.timeZone)), minute: minute, lead: lead)
    }

    func store() -> EventStore {
        EventStore(database: LibraryDatabase(at: .memory, syncing: false), libraryFile: nil,
                   calendar: nil, venues: nil, pageReads: nil, readCopies: nil)
    }

    // MARK: - The hall's clock

    /// As the notice prints it, whichever hall's clock it is read on.
    @Test func aTimeIsAWallClockAtTheHall() {
        let written = reminder(at: 11 * 60 + 30)
        #expect(written.date(in: Fixtures.tokyo) == Fixtures.date(2026, 11, 14, 11, 30))
        #expect(written.date(in: Fixtures.taipei) == Fixtures.date(2026, 11, 14, 11, 30, in: Fixtures.taipei))
    }

    @Test func movingWritesTheHallsDayAndMinute() {
        var written = reminder()
        written.move(to: Fixtures.date(2026, 11, 15, 12, 31), in: Fixtures.tokyo)
        #expect(written.day == CalendarDay(year: 2026, month: 11, day: 15))
        #expect(written.minute == 12 * 60 + 31)
        // 23:30 in Tokyo is still the 15th there, wherever the picker's date
        // was made.
        written.move(to: Fixtures.date(2026, 11, 15, 23, 30), in: Fixtures.tokyo)
        #expect(written.date(in: Fixtures.tokyo) == Fixtures.date(2026, 11, 15, 23, 30))
    }

    /// On the event's own day, in the morning, with no alert of its own:
    /// Settings says.
    @Test func aNewTimeOpensOnTheEventsDay() {
        let show = Fixtures.event(date: Fixtures.date(2026, 11, 14))
        let queue = EventReminder(kind: .queueTime, for: show)
        #expect(queue.day == notice)
        #expect(queue.minute == 10 * 60)
        #expect(queue.lead == nil)
        #expect(queue.title == "整理券配布")
    }

    @Test func aListReadsByWhen() {
        let queue = reminder(at: 12 * 60)
        let close = reminder(.randomTicketsClose, at: 11 * 60 + 30)
        let dayBefore = reminder(on: CalendarDay(year: 2026, month: 11, day: 13), at: 15 * 60)
        #expect(EventReminder.inOrder([queue, close, dayBefore]).map(\.id) == [dayBefore.id, close.id, queue.id])
    }

    // MARK: - The goods sale's time

    /// The sale's opening an older build wrote (物販開始) is no time the card
    /// asks any more.
    func saleOpening(at minute: Int = 12 * 60) -> EventReminder {
        EventReminder(title: "物販開始", day: notice, minute: minute, lead: 30)
    }

    /// The three queue times an older build named apart are the one time a
    /// notice nearly always sets them at.
    @Test func theOlderQueueTimesAreOne() {
        for kind in [ReminderKind.priorityCheckIn, .randomTicketsClose, .lastTicketsOpen, .queueTime] {
            #expect(kind.goodsTime == .queueTime)
            #expect(ReminderKind.label(of: kind.rawValue) == ReminderKind.queueTime.label)
        }
        #expect(ReminderKind.goods == [.queueTime])
        #expect(saleOpening().goodsKind == nil)
    }

    /// Of several an older build wrote, the earliest; the sale's opening, a
    /// time of the ticket sale, or one the reader named, is no time of the
    /// goods sale at all.
    @Test func theEarliestQueueTimeStands() {
        let random = reminder(.randomTicketsClose, at: 11 * 60 + 30)
        let last = reminder(.lastTicketsOpen, at: 11 * 60 + 31)
        let priority = reminder(.priorityCheckIn, at: 10 * 60)
        let sale = saleOpening()
        let payment = EventReminder(title: "入金締切", day: notice, minute: 23 * 60 + 59, lead: 24 * 60)
        let typed = EventReminder(title: "ブシロードカード優先", day: notice, minute: 9 * 60, lead: 30)
        let record = Tracking(reminders: [random, last, priority, sale, payment, typed])
        #expect(record.goodsReminder(.queueTime) == priority)
        #expect(sale.goodsKind == nil)
        #expect(payment.goodsKind == nil)
        #expect(typed.goodsKind == nil)
    }

    /// Written, it is the one time of its kind, under the kind's own name;
    /// taken out, every time of its kind goes, and nothing else.
    @Test func aTimeWrittenFoldsTheOthersOfItsKind() {
        let random = reminder(.randomTicketsClose, at: 11 * 60 + 30)
        var priority = reminder(.priorityCheckIn, at: 10 * 60)
        let sale = saleOpening()
        let payment = EventReminder(title: "入金締切", day: notice, minute: 23 * 60 + 59, lead: 24 * 60)
        let record = Tracking(reminders: [random, priority, sale, payment])

        priority.minute = 10 * 60 + 30
        let written = record.settingGoodsReminder(priority)
        #expect(written.goodsReminder(.queueTime)?.id == priority.id)
        #expect(written.goodsReminder(.queueTime)?.title == ReminderKind.queueTime.rawValue)
        #expect(written.goodsReminder(.queueTime)?.minute == 10 * 60 + 30)
        #expect(written.reminders.count == 3)
        #expect(written.reminders.contains(sale) && written.reminders.contains(payment))

        let taken = record.removingGoodsReminder(.queueTime)
        #expect(taken.goodsReminder(.queueTime) == nil)
        #expect(taken.reminders == [sale, payment])
    }

    // MARK: - Notifications

    @Test func theAlertComesTheLeadAhead() throws {
        let show = event()
        let written = reminder(on: show, at: 11 * 60 + 30)
        let alert = try #require(ReminderAlert(reminder: written, event: show, lead: 60))
        #expect(alert.date == written.date(in: show.timeZone).addingTimeInterval(-3600))
        let atTheTime = try #require(ReminderAlert(reminder: written, event: show, lead: 0))
        #expect(atTheTime.date == written.date(in: show.timeZone))
    }

    @Test func nothingIsOwedForAMomentGone() throws {
        let show = event()
        let written = reminder(on: show)
        let alert = try #require(ReminderAlert(reminder: written, event: show, lead: 30)).date
        #expect(ReminderAlert(reminder: written, event: show, lead: 30, at: alert.addingTimeInterval(-1)) != nil)
        // Its moment has gone though the time itself is still ahead.
        #expect(ReminderAlert(reminder: written, event: show, lead: 30, at: alert.addingTimeInterval(1)) == nil)
    }

    /// What an older build wrote that is no time of the goods sale is kept,
    /// and says nothing.
    @Test func anOlderBuildsOtherTimesAreOwedNothing() {
        let show = event()
        let day = CalendarDay(show.date, in: .gregorian(in: show.timeZone))
        let payment = EventReminder(title: "入金締切", day: day, minute: 12 * 60, lead: 30)
        let typed = EventReminder(title: "ブシロードカード優先", day: day, minute: 12 * 60, lead: 30)
        let opening = EventReminder(title: "物販開始", day: day, minute: 12 * 60, lead: 30)
        #expect(ReminderAlert(reminder: payment, event: show, lead: 30) == nil)
        #expect(ReminderAlert(reminder: typed, event: show, lead: 30) == nil)
        #expect(ReminderAlert(reminder: opening, event: show, lead: 30) == nil)
        #expect(ReminderAlert.due(in: [show], tracking: { _ in Tracking(reminders: [payment, typed, opening]) },
                                  lead: 30).isEmpty)
    }

    /// Nothing comes for an event gone by, not even for a time still ahead on
    /// it, which is what an event moved to an earlier day leaves behind.
    @Test func anEventGoneByIsOwedNothing() {
        let over = event(inDays: -2)
        let stillAhead = reminder(on: event(inDays: 3))
        #expect(ReminderAlert(reminder: stillAhead, event: over, lead: 30) == nil)
        #expect(ReminderAlert.due(in: [over], tracking: { _ in Tracking(reminders: [stillAhead]) }, lead: 30).isEmpty)
    }

    /// Scheduled, it would come after the event is over, whether or not the app
    /// is opened again to take it back.
    @Test func aTimePastAnEventMovedEarlierIsOwedNothing() {
        let moved = event(inDays: 1)
        let written = reminder(on: event(inDays: 8))
        #expect(!moved.holds(written))
        #expect(ReminderAlert(reminder: written, event: moved, lead: 30) == nil)
        #expect(ReminderAlert.due(in: [moved], tracking: { _ in Tracking(reminders: [written]) }, lead: 30).isEmpty)
    }

    /// As late as the sheet writes one, and earlier days for what comes ahead.
    @Test func anEventHoldsWhatFallsByTheEndOfItsDay() {
        let show = event(inDays: 3)
        #expect(show.holds(reminder(on: show, at: 23 * 60 + 59)))
        #expect(show.holds(reminder(on: event(inDays: 1))))
        #expect(!show.holds(reminder(on: event(inDays: 4), at: 0)))
    }

    @Test func theSoonestAreScheduled() {
        let events = (0..<(ReminderAlert.limit + 5)).map { event("\($0)", inDays: 30 - $0) }
        let due = ReminderAlert.due(in: events, tracking: { Tracking(reminders: [reminder(on: $0)]) }, lead: 30)
        #expect(due.count == ReminderAlert.limit)
        #expect(due.map(\.date) == due.map(\.date).sorted())
        #expect(due.first?.eventID == events.last?.id)
    }

    /// iOS keeps an app's 64 soonest and drops the rest without a word.
    @Test func theKindsTogetherFitWhatIOSKeeps() {
        #expect(LotteryReminder.limit + ActivityReminder.limit + ReminderAlert.limit <= 64)
    }

    /// The queue once: the three queue times an older build wrote come as
    /// the earliest of them, and the sale's opening it wrote not at all.
    @Test func eachTimeOfTheSaleIsOneNotification() throws {
        let show = event()
        let day = CalendarDay(show.date, in: .gregorian(in: show.timeZone))
        let priority = reminder(.priorityCheckIn, on: day, at: 10 * 60)
        let random = reminder(.randomTicketsClose, on: day, at: 11 * 60 + 30)
        var sale = saleOpening()
        sale.day = day
        let due = ReminderAlert.due(in: [show], tracking: { _ in Tracking(reminders: [random, sale, priority]) },
                                    lead: 30)
        #expect(due.map(\.reminderID) == [priority.id])
        #expect(due.allSatisfy { $0.identifier.hasPrefix(ReminderAlert.prefix) })
        #expect(due.first?.title == ReminderKind.queueTime.label)
    }

    /// Its words say what, for which event, and when — on the hall's clock.
    @Test func theNotificationSaysWhatAndWhen() throws {
        let show = Fixtures.event(title: "9th LIVE", date: Fixtures.day(fromToday: 3))
        let written = reminder(on: show, at: 11 * 60 + 30)
        let alert = try #require(ReminderAlert(reminder: written, event: show, lead: 60))
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = Fixtures.tokyo
        let time = written.date(in: Fixtures.tokyo).formatted(style)

        #expect(alert.title == ReminderKind.queueTime.label)
        #expect(alert.eventTitle == "9th LIVE")
        #expect(alert.body == "\(time) · \(ReminderLead.label(of: 60))")
        #expect(try #require(ReminderAlert(reminder: written, event: show, lead: 0)).body.contains("·") == false)
        #expect(alert.request.content.userInfo[ReminderAlert.eventKey] as? String == show.id)
        #expect(alert.request.content.categoryIdentifier.isEmpty)
    }

    @Test func aDayOtherThanTheEventsIsPrintedWithIt() {
        let show = Fixtures.event(date: Fixtures.date(2026, 11, 14))
        let onTheDay = show.printedTime(of: reminder(at: 12 * 60), on: .venue)
        let before = show.printedTime(of: reminder(on: CalendarDay(year: 2026, month: 11, day: 13), at: 12 * 60),
                                      on: .venue)
        #expect(before != onTheDay)
        #expect(before.count > onTheDay.count)
    }

    /// A scheduled copy is left alone; a moved time, another lead or changed
    /// words are not.
    @Test func aScheduledCopyIsKnownByItsMomentAndWords() throws {
        let show = event()
        let alert = try #require(ReminderAlert(reminder: reminder(on: show), event: show, lead: 30))
        #expect(alert.isScheduled(as: alert.request))
        #expect(!alert.isScheduled(as: nil))

        let moved = try #require(ReminderAlert(reminder: reminder(on: show, at: 13 * 60), event: show, lead: 30))
        #expect(!moved.isScheduled(as: alert.request))
        let sooner = try #require(ReminderAlert(reminder: reminder(on: show), event: show, lead: 15))
        #expect(!sooner.isScheduled(as: alert.request))
    }

    /// What is about to close comes through a Focus; what is a day off waits.
    @Test func onlyWhatCannotWaitIsTimeSensitive() throws {
        let show = event()
        for lead in EventReminders.goodsLeads {
            let alert = try #require(ReminderAlert(reminder: reminder(on: show), event: show, lead: lead))
            #expect(alert.request.content.interruptionLevel == (lead < ReminderAlert.calmLead ? .timeSensitive : .active),
                    "\(lead)")
        }
    }

    /// A copy scheduled before it was urgent is scheduled again.
    @Test func aCopyLessUrgentIsScheduledAgain() throws {
        let show = event()
        let alert = try #require(ReminderAlert(reminder: reminder(on: show), event: show, lead: 30))
        let older = try #require(alert.request.content.mutableCopy() as? UNMutableNotificationContent)
        older.interruptionLevel = .active
        #expect(!alert.isScheduled(as: UNNotificationRequest(identifier: alert.identifier, content: older,
                                                             trigger: alert.request.trigger)))
    }

    // MARK: - The queue ticket's link

    @Test func onlyAWebPageIsALink() {
        #expect(QRCodeLink.link(inCode: "https://q.example.jp/t/abc?x=1")?.host() == "q.example.jp")
        #expect(QRCodeLink.link(inCode: "  http://q.example.jp/abc\n") != nil)
        #expect(QRCodeLink.link(inCode: "HTTPS://Q.EXAMPLE.JP/abc") != nil)

        for code in ["", "整理券 123", "tel:0312345678", "javascript:alert(1)", "file:///etc/passwd",
                     "eventrail://event/1", "https://", "q.example.jp/abc", "see https://q.example.jp"] {
            #expect(QRCodeLink.link(inCode: code) == nil, "\(code)")
        }
    }

    @Test func aPictureOfTwoOfOneCodeIsOneLink() {
        let links = QRCodeLink.links(inCodes: ["https://q.example.jp/a", "not a link", "https://q.example.jp/a",
                                                "https://q.example.jp/b"])
        #expect(links.map(\.lastPathComponent) == ["a", "b"])
    }

    /// Two tickets of one queue differ only towards the end, and a button
    /// has to show that part or the reader cannot tell which they are picking.
    @Test func severalLinksAreToldApartOnTheirButtons() {
        func labels(_ links: String...) -> [String] {
            QRCodeLink.labels(tellingApart: links.map { URL(string: $0)! })
        }
        #expect(labels("https://q.example.jp/t/8f3a21?from=qr", "https://q.example.jp/t/77c0de?from=qr")
            == ["…8f3a21?from=qr", "…77c0de?from=qr"])
        #expect(labels("https://q.example.jp/?t=abc", "https://q.example.jp/?t=def") == ["…abc", "…def"])
        #expect(labels("https://q.example.jp/a", "https://q.example.jp/a?x=1") == ["…a", "…a?x=1"])
        // A third that parts sooner moves where the others are cut.
        #expect(labels("https://q.example.jp/t/1", "https://q.example.jp/t/2", "https://q.example.jp/u/3")
            == ["…t/1", "…t/2", "…u/3"])

        // Another host is part of what tells them apart.
        #expect(labels("https://a.example.jp/t/1", "https://b.example.jp/t/1")
            == ["a.example.jp/t/1", "b.example.jp/t/1"])
        // Nothing left to show after the shared part: whole, without the scheme.
        #expect(labels("https://q.example.jp", "https://q.example.jp/x") == ["q.example.jp", "q.example.jp/x"])
        #expect(labels("https://q.example.jp/", "https://q.example.jp/x") == ["q.example.jp/", "q.example.jp/x"])
        // Only the scheme differs, so it stays.
        #expect(labels("http://q.example.jp/a", "https://q.example.jp/a")
            == ["http://q.example.jp/a", "https://q.example.jp/a"])
    }

    // MARK: - The record

    /// A record from before them, as a backup or a file holds it.
    @Test func anOlderRecordHasNone() throws {
        let record = try JSONDecoder().decode(Tracking.self, from: Data(#"{"seat":"A12"}"#.utf8))
        #expect(record.seat == "A12")
        #expect(record.reminders.isEmpty)
        #expect(record.queueTickets.isEmpty)
    }

    /// A round trip, and a field a later build added passed over.
    @Test func anItemReadsBackAsWritten() throws {
        let written = reminder(lead: nil)
        let text = try JSONEncoder().encode(written)
        #expect(try JSONDecoder().decode(EventReminder.self, from: text) == written)

        var object = try #require(JSONSerialization.jsonObject(with: text) as? [String: Any])
        object["later"] = true
        let later = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(EventReminder.self, from: later) == written)
    }

    /// Goods planned for say nothing about getting in.
    @Test func aPlanSaysNothingOfTheTicket() {
        var record = Tracking()
        #expect(record.isEmpty && record.isTicketBlank)
        record.reminders = [reminder()]
        #expect(!record.isEmpty)
        #expect(record.isTicketBlank)
        record.reminders = []
        record.queueTickets = [QueueTicket(link: URL(string: "https://q.example.jp/a")!, added: .now)]
        #expect(!record.isEmpty)
        #expect(record.isTicketBlank)
        record.note = "front row"
        #expect(!record.isTicketBlank)
    }

    /// Ticket Details holds a copy: what arrived while it was open stays.
    @Test func aSheetsCopyLeavesAReminderAddedMeanwhile() {
        var original = Tracking()
        original.seat = "A12"
        var edited = original
        edited.note = "front row"
        var current = original
        current.reminders = [reminder()]
        let written = current.applying(changesFrom: original, to: edited)
        #expect(written.reminders == current.reminders)
        #expect(written.note == "front row")
    }

    // MARK: - The store

    @Test func aTimeIsWrittenInPlaceAndTakenOut() {
        let store = store()
        let show = event()
        store.toggleLibraryMembership(show)
        var written = reminder(on: show)
        store.setGoodsReminder(written, for: show)
        #expect(store.tracking(for: show).reminders == [written])

        written.minute = 13 * 60
        store.setGoodsReminder(written, for: show)
        #expect(store.tracking(for: show).reminders == [written])

        store.removeGoodsReminder(.queueTime, from: show)
        #expect(store.tracking(for: show).reminders.isEmpty)
    }

    @Test func oneLinkIsOneQueueTicket() throws {
        let store = store()
        let show = event()
        let link = try #require(URL(string: "https://q.example.jp/a"))
        store.toggleLibraryMembership(show)
        store.addQueueTicket(link, to: show)
        store.addQueueTicket(link, to: show)
        #expect(store.tracking(for: show).queueTickets.map(\.link) == [link])

        store.addQueueTicket(try #require(URL(string: "https://q.example.jp/b")), to: show)
        #expect(store.tracking(for: show).queueTickets.count == 2)

        store.removeQueueTicket(store.tracking(for: show).queueTickets[0].id, from: show)
        #expect(store.tracking(for: show).queueTickets.map(\.link.lastPathComponent) == ["b"])
    }

    @Test func oneLinkIsOneSetList() throws {
        let store = store()
        let show = event(inDays: -3)
        let link = try #require(URL(string: "https://example.jp/setlist/a"))
        store.toggleLibraryMembership(show)
        store.addSetList(link, to: show)
        store.addSetList(link, to: show)
        #expect(store.tracking(for: show).setLists.map(\.link) == [link])

        store.addSetList(try #require(URL(string: "https://example.jp/setlist/b")), to: show)
        #expect(store.tracking(for: show).setLists.count == 2)

        store.removeSetList(store.tracking(for: show).setLists[0].id, from: show)
        #expect(store.tracking(for: show).setLists.map(\.link.lastPathComponent) == ["b"])
    }

    /// The same link can be a queue ticket and a set list: each list is its
    /// own, and neither answers for the other.
    @Test func aSetListAndAQueueTicketKeepTheirOwnLists() throws {
        let store = store()
        let show = event(inDays: -3)
        let link = try #require(URL(string: "https://example.jp/a"))
        store.toggleLibraryMembership(show)
        store.addQueueTicket(link, to: show)
        store.addSetList(link, to: show)
        #expect(store.tracking(for: show).queueTickets.map(\.link) == [link])
        #expect(store.tracking(for: show).setLists.map(\.link) == [link])

        store.removeQueueTicket(store.tracking(for: show).queueTickets[0].id, from: show)
        #expect(store.tracking(for: show).queueTickets.isEmpty)
        #expect(store.tracking(for: show).setLists.map(\.link) == [link])
    }

    // MARK: - The goods sale's notice

    /// As copied from a post, or with the scheme left off; anything else is
    /// no link.
    @Test func aLinkIsReadAsTypedOrPasted() throws {
        let post = try #require(URL(string: "https://x.com/bang_dream_info/status/1"))
        #expect(QRCodeLink.link(typed: " https://x.com/bang_dream_info/status/1\n") == post)
        #expect(QRCodeLink.link(typed: "x.com/bang_dream_info/status/1") == post)
        #expect(QRCodeLink.link(typed: "http://example.jp/goods")?.scheme == "http")
        for text in ["", "物販情報", "see x.com", "localhost", "ftp://example.jp/a", "mailto:goods@example.jp", "x."] {
            #expect(QRCodeLink.link(typed: text) == nil, "\(text)")
        }
    }

    /// One to an event: written again it takes the place of the one before,
    /// and of two that two devices wrote, the later is the one read.
    @Test func oneNoticeStands() throws {
        let first = try #require(URL(string: "https://x.com/a/status/1"))
        let second = try #require(URL(string: "https://x.com/a/status/2"))
        let written = Tracking().settingGoodsNotice(first, at: Fixtures.date(2026, 11, 1))
        let notice = try #require(written.goodsNotice)
        #expect(notice.link == first)
        #expect(written.settingGoodsNotice(first, at: Fixtures.date(2026, 11, 2)) == written)

        let rewritten = written.settingGoodsNotice(second, at: Fixtures.date(2026, 11, 2))
        #expect(rewritten.goodsNotices.map(\.link) == [second])
        #expect(rewritten.goodsNotice?.id == notice.id)

        let other = GoodsNotice(link: second, added: Fixtures.date(2026, 11, 3))
        let both = Tracking(goodsNotices: [other, notice])
        #expect(both.goodsNotice == other)
        #expect(both.settingGoodsNotice(second, at: Fixtures.date(2026, 11, 4)).goodsNotices.count == 1)
    }

    @Test func aNoticeIsWrittenAndTakenOut() throws {
        let store = store()
        let show = event()
        store.toggleLibraryMembership(show)
        let post = try #require(URL(string: "https://x.com/a/status/1"))
        store.setGoodsNotice(post, for: show)
        #expect(store.tracking(for: show).goodsNotice?.link == post)
        // Not a ticket, so the event still asks about one once it is over.
        #expect(store.tracking(for: show).isTicketBlank)
        #expect(!store.tracking(for: show).isEmpty)

        let page = try #require(URL(string: "https://example.jp/goods"))
        store.setGoodsNotice(page, for: show)
        #expect(store.tracking(for: show).goodsNotices.map(\.link) == [page])

        store.removeGoodsNotice(from: show)
        #expect(store.tracking(for: show).goodsNotices.isEmpty)
    }

    /// A set list kept says nothing about a ticket: the event still asks.
    @Test func aSetListLeavesTicketDetailsBlank() throws {
        let store = store()
        let show = event(inDays: -3)
        store.toggleLibraryMembership(show)
        store.addSetList(try #require(URL(string: "https://example.jp/setlist")), to: show)
        #expect(store.tracking(for: show).isTicketBlank)
        #expect(!store.tracking(for: show).isEmpty)
        #expect(store.awaitsTicket(show))
        #expect(!store.hasAttended(show))
    }

    /// Offered from the morning of the event's day at the hall: a set list
    /// comes out as the show ends, which no printed end time can be trusted for.
    @Test func theDayHasComeFromItsMorningAtTheHall() {
        let show = event()
        #expect(!show.dayHasCome(at: show.date.addingTimeInterval(-60)))
        #expect(show.dayHasCome(at: show.date))
        #expect(show.dayHasCome(at: show.dayEnds.addingTimeInterval(365 * 24 * 60 * 60)))
        #expect(!event().dayHasCome())
        #expect(event(inDays: -1).dayHasCome())
    }

    /// The ticket added is handed back to be numbered, and a link already held
    /// adds nothing to number.
    @Test func aNumberIsWrittenOnItsOwnTicket() throws {
        let store = store()
        let show = event()
        store.toggleLibraryMembership(show)
        let linkA = try #require(URL(string: "https://q.example.jp/a"))
        let linkB = try #require(URL(string: "https://q.example.jp/b"))
        let first = try #require(store.addQueueTicket(linkA, to: show))
        let second = try #require(store.addQueueTicket(linkB, to: show))
        #expect(store.addQueueTicket(first.link, to: show) == nil)

        store.setQueueTicketNumber(" Ａ－１２３ ", of: second.id, on: show)
        var tickets = store.tracking(for: show).queueTickets
        #expect(tickets.map(\.id) == [first.id, second.id])
        #expect(tickets.map(\.number) == [nil, "A-123"])

        store.setQueueTicketNumber("", of: second.id, on: show)
        tickets = store.tracking(for: show).queueTickets
        #expect(tickets.allSatisfy { $0.number == nil })
    }

    /// As it is printed, less the width: a ticket's １２３ is the page's 123.
    @Test func aNumberIsKeptAsPrinted() {
        #expect(QueueTicket.typedNumber("  １２３\n") == "123")
        #expect(QueueTicket.typedNumber("A-123") == "A-123")
        #expect(QueueTicket.typedNumber("B列 45番") == "B列 45番")
        #expect(QueueTicket.typedNumber("   ") == nil)
        #expect(QueueTicket.typedNumber(String(repeating: "1", count: 100))?.count == QueueTicket.longestNumber)
    }

    /// A row written before there were numbers still reads, and one with none
    /// is the same text it was, so it is not a change to send.
    @Test func aTicketWithNoNumberReadsAndWritesAsBefore() throws {
        let older = #"{"added":0,"id":"00000000-0000-0000-0000-000000000009","link":"https://q.example.jp/a"}"#
        let ticket = try JSONDecoder().decode(QueueTicket.self, from: Data(older.utf8))
        #expect(ticket.number == nil)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        #expect(String(decoding: try encoder.encode(ticket), as: UTF8.self) == older)
    }

    /// Their own rows: a change to them leaves the entry as it was, so it can
    /// never carry an older note back over another device's.
    @Test func aReminderLeavesTheEntryAlone() throws {
        let store = store()
        let show = event()
        store.toggleLibraryMembership(show)
        var record = store.tracking(for: show)
        record.note = "front row"
        store.setTracking(record, for: show)
        store.saveNow()
        let entry = try #require(try store.database.context.fetch(FetchDescriptor<LibraryEntry>()).first)
        let written = entry.modified

        store.setGoodsReminder(reminder(on: show), for: show)
        store.saveNow()
        #expect(entry.modified == written)
        #expect(store.tracking(for: show).note == "front row")
        #expect(try store.database.context.fetch(FetchDescriptor<LibraryPlanItem>()).count == 1)
    }

    @Test func anEventFirstWrittenDownByAReminderGetsAnEntry() throws {
        let store = store()
        let show = event()
        store.setGoodsReminder(reminder(on: show), for: show)
        store.saveNow()
        #expect(try store.database.context.fetch(FetchDescriptor<LibraryEntry>()).count == 1)
    }

    /// Every way out of the library empties the record, as rows that say so.
    @Test func aRemovalTakesThePlanOut() throws {
        let store = store()
        let show = event()
        store.toggleLibraryMembership(show)
        store.setGoodsReminder(reminder(on: show), for: show)
        store.addQueueTicket(try #require(URL(string: "https://q.example.jp/a")), to: show)
        store.addSetList(try #require(URL(string: "https://example.jp/setlist")), to: show)

        store.remove(CollectionOfOne(show))
        #expect(store.tracking(for: show).isEmpty)
        let rows = try store.database.context.fetch(FetchDescriptor<LibraryPlanItem>())
        #expect(rows.count == 3)
        let removed = rows.allSatisfy { $0.isRemoved && $0.text.isEmpty }
        #expect(removed)
    }

    @Test func deleteAllTakesThePlanOut() throws {
        let store = store()
        let show = event()
        store.toggleLibraryMembership(show)
        store.setGoodsReminder(reminder(on: show), for: show)

        store.removeAllEvents()
        #expect(store.tracking(for: show).isEmpty)
        let removed = try store.database.context.fetch(FetchDescriptor<LibraryPlanItem>()).allSatisfy(\.isRemoved)
        #expect(removed)
    }

    /// An event over with goods planned for still asks about its ticket.
    @Test func aPlanLeavesTheTicketReviewAsking() {
        let store = store()
        let past = event(inDays: -3)
        store.toggleLibraryMembership(past)
        store.setGoodsReminder(reminder(on: past), for: past)
        #expect(store.awaitsTicket(past))
    }
}

/// The plan's rows, cut so that CloudKit's own rule is the right answer — see
/// ``LibraryPlanItem``.
struct LibraryPlanItemTests {
    let earlier = Date.now.addingTimeInterval(-3600)
    let later = Date.now.addingTimeInterval(-60)

    func database() -> (LibraryDatabase, ModelContext) {
        let database = LibraryDatabase(at: .memory, syncing: false)
        return (database, database.context)
    }

    func reminder(_ minute: Int = 12 * 60) -> EventReminder {
        EventReminder(title: "物販開始", day: CalendarDay(year: 2027, month: 5, day: 9), minute: minute, lead: 30)
    }

    func ticket(_ path: String = "a") -> QueueTicket {
        QueueTicket(link: URL(string: "https://q.example.jp/\(path)")!, added: earlier)
    }

    func setList(_ path: String = "a") -> SetList {
        SetList(link: URL(string: "https://example.jp/setlist/\(path)")!, added: earlier)
    }

    func notice(_ path: String = "1") -> GoodsNotice {
        GoodsNotice(link: URL(string: "https://x.com/a/status/\(path)")!, added: earlier)
    }

    func rows(in context: ModelContext) throws -> [String: [String: LibraryPlanItem]] {
        LibraryDatabase.planIndex(try context.fetch(FetchDescriptor<LibraryPlanItem>()))
    }

    /// Each device's item is a record of its own, and both stand.
    @Test func twoDevicesAddingOneEachKeepBoth() throws {
        let (database, context) = database()
        var oneDevice: [String: [String: LibraryPlanItem]] = [:]
        var otherDevice: [String: [String: LibraryPlanItem]] = [:]
        let first = reminder(11 * 60), second = reminder(12 * 60)
        LibraryDatabase.writePlan([first], for: "1", rows: &oneDevice, dated: earlier, in: context)
        LibraryDatabase.writePlan([second], for: "1", rows: &otherDevice, dated: later, in: context)
        try context.save()

        let items = LibraryDatabase.planItems(EventReminder.self, in: try rows(in: context)["1"])
        #expect(Set(items) == [first, second])
        withExtendedLifetime(database) {}
    }

    /// Taken out is a record that says so, or the other device's copy comes
    /// straight back.
    @Test func takingOneOutMarksItsRow() throws {
        let (database, context) = database()
        var held: [String: [String: LibraryPlanItem]] = [:]
        let first = reminder(11 * 60), second = reminder(12 * 60)
        LibraryDatabase.writePlan([first, second], for: "1", rows: &held, dated: earlier, in: context)
        #expect(LibraryDatabase.writePlan([second], for: "1", rows: &held, dated: later, in: context))
        try context.save()

        let row = try #require(held["1"]?[first.id.uuidString])
        #expect(row.isRemoved)
        #expect(row.text.isEmpty)
        #expect(row.modified == later.toTheMillisecond)
        #expect(LibraryDatabase.planItems(EventReminder.self, in: held["1"]) == [second])
        withExtendedLifetime(database) {}
    }

    /// Every row written is a record sent to iCloud again.
    @Test func anUnchangedListWritesNothing() throws {
        let (database, context) = database()
        var held: [String: [String: LibraryPlanItem]] = [:]
        let first = reminder()
        LibraryDatabase.writePlan([first], for: "1", rows: &held, dated: earlier, in: context)
        try context.save()
        #expect(!LibraryDatabase.writePlan([first], for: "1", rows: &held, dated: later, in: context))
        #expect(!context.hasChanges)
        withExtendedLifetime(database) {}
    }

    /// A number is a change to its own row alone.
    @Test func aNumberRewritesOnlyItsTicket() throws {
        let (database, context) = database()
        var held: [String: [String: LibraryPlanItem]] = [:]
        let first = ticket("a")
        var second = ticket("b")
        LibraryDatabase.writePlan([first, second], for: "1", rows: &held, dated: earlier, in: context)
        try context.save()

        second.number = "A-123"
        #expect(LibraryDatabase.writePlan([first, second], for: "1", rows: &held, dated: later, in: context))
        #expect(held["1"]?[first.id.uuidString]?.modified == earlier.toTheMillisecond)
        #expect(held["1"]?[second.id.uuidString]?.modified == later.toTheMillisecond)
        #expect(Set(LibraryDatabase.planItems(QueueTicket.self, in: held["1"])) == [first, second])
        withExtendedLifetime(database) {}
    }

    /// A list of one kind says nothing about the other.
    @Test func oneKindLeavesTheOtherAlone() throws {
        let (database, context) = database()
        var held: [String: [String: LibraryPlanItem]] = [:]
        let time = reminder(), code = ticket(), songs = setList()
        LibraryDatabase.writePlan([time], for: "1", rows: &held, dated: earlier, in: context)
        LibraryDatabase.writePlan([code], for: "1", rows: &held, dated: earlier, in: context)
        LibraryDatabase.writePlan([songs], for: "1", rows: &held, dated: earlier, in: context)
        LibraryDatabase.writePlan([EventReminder](), for: "1", rows: &held, dated: later, in: context)

        #expect(LibraryDatabase.planItems(EventReminder.self, in: held["1"]).isEmpty)
        #expect(LibraryDatabase.planItems(QueueTicket.self, in: held["1"]) == [code])
        #expect(LibraryDatabase.planItems(SetList.self, in: held["1"]) == [songs])

        LibraryDatabase.writePlan([SetList](), for: "1", rows: &held, dated: later, in: context)
        #expect(LibraryDatabase.planItems(SetList.self, in: held["1"]).isEmpty)
        #expect(LibraryDatabase.planItems(QueueTicket.self, in: held["1"]) == [code])

        let post = notice()
        LibraryDatabase.writePlan([post], for: "1", rows: &held, dated: later, in: context)
        LibraryDatabase.writePlan([QueueTicket](), for: "1", rows: &held, dated: later, in: context)
        #expect(LibraryDatabase.planItems(GoodsNotice.self, in: held["1"]) == [post])
        #expect(LibraryDatabase.planItems(QueueTicket.self, in: held["1"]).isEmpty)
        withExtendedLifetime(database) {}
    }

    /// Written by a later build, an item this one cannot read is the reader's
    /// on every device that can, and only clearing the record takes it out.
    @Test func anItemThisBuildCannotReadIsNotARemoval() throws {
        let (database, context) = database()
        var held: [String: [String: LibraryPlanItem]] = [:]
        let later = LibraryPlanItem(eventID: "1", itemID: "A", kind: EventReminder.rowKind)
        later.text = #"{"shape":"a later build's"}"#
        let unknown = LibraryPlanItem(eventID: "1", itemID: "B", kind: "shoppingList")
        unknown.text = #"{"goods":["法被"]}"#
        context.insert(later)
        context.insert(unknown)
        try context.save()
        held = try rows(in: context)

        LibraryDatabase.writePlan([EventReminder](), for: "1", rows: &held, dated: .now, in: context)
        #expect(!later.isRemoved)
        #expect(!unknown.isRemoved)

        #expect(LibraryDatabase.clearPlan(for: "1", rows: held, dated: .now))
        #expect(later.isRemoved)
        #expect(unknown.isRemoved)
        withExtendedLifetime(database) {}
    }

    /// A field a later build added to an item stays until the reader changes
    /// that item: its decoded form is what is compared.
    @Test func whatALaterBuildAddedStaysUntilTheItemChanges() throws {
        let (database, context) = database()
        var held: [String: [String: LibraryPlanItem]] = [:]
        var written = reminder()
        LibraryDatabase.writePlan([written], for: "1", rows: &held, dated: earlier, in: context)
        let row = try #require(held["1"]?[written.id.uuidString])
        var object = try #require(JSONSerialization.jsonObject(with: Data(row.text.utf8)) as? [String: Any])
        object["later"] = true
        let text = try #require(String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8))
        row.text = text

        #expect(!LibraryDatabase.writePlan([written], for: "1", rows: &held, dated: later, in: context))
        #expect(row.text == text)

        written.minute += 1
        #expect(LibraryDatabase.writePlan([written], for: "1", rows: &held, dated: later, in: context))
        #expect(row.text != text)
        withExtendedLifetime(database) {}
    }

    /// Two rows for one item are one record that arrived twice: the later
    /// stands, on every device.
    @Test func twoRowsForOneItemFoldIntoTheLater() throws {
        let (database, context) = database()
        var oneDevice: [String: [String: LibraryPlanItem]] = [:]
        var otherDevice: [String: [String: LibraryPlanItem]] = [:]
        var written = reminder()
        LibraryDatabase.writePlan([written], for: "1", rows: &oneDevice, dated: earlier, in: context)
        written.minute = 13 * 60
        LibraryDatabase.writePlan([written], for: "1", rows: &otherDevice, dated: later, in: context)
        try context.save()

        try LibraryDatabase.deduplicate(in: context)
        let items = LibraryDatabase.planItems(EventReminder.self, in: try rows(in: context)["1"])
        #expect(items == [written])
        #expect(try context.fetchCount(FetchDescriptor<LibraryPlanItem>()) == 1)
        withExtendedLifetime(database) {}
    }

    /// A backup says what the rows said, each list dated by its newest row;
    /// written back as it stands it sends nothing again.
    @Test func anArchiveCarriesThePlanAndSendsNothingBack() throws {
        let (database, context) = database()
        var archive = LibraryArchive()
        archive.events["1"] = Fixtures.event(id: "1")
        archive.membership["1"] = Stamped(true, at: earlier)
        let time = reminder(), code = ticket(), songs = setList(), post = notice()
        archive.tracking["1"] = Stamped(Tracking(note: "front row", reminders: [time], queueTickets: [code],
                                                 setLists: [songs], goodsNotices: [post]), at: later)
        try LibraryDatabase.apply(archive, to: context)
        try context.save()

        let read = try LibraryDatabase.archive(in: context)
        let record = try #require(read.tracking["1"])
        #expect(record.value.reminders == [time])
        #expect(record.value.queueTickets == [code])
        #expect(record.value.setLists == [songs])
        #expect(record.value.goodsNotices == [post])
        #expect(record.value.note == "front row")
        #expect(record.modified == later.toTheMillisecond)

        #expect(try LibraryDatabase.apply(read, to: context) == false)
        #expect(!context.hasChanges)
        withExtendedLifetime(database) {}
    }

    /// The newest row dates the list, and the record is as new as that —
    /// the note beside it dated older within it.
    @Test func aListNewerThanTheEntryDatesTheRecord() throws {
        let (database, context) = database()
        let entry = LibraryEntry(eventID: "1")
        entry.give(LibraryEntry.Answers(inLibrary: true, tracking: Tracking(note: "front row")),
                   dated: [.inLibrary: earlier, .tracking: earlier])
        entry.modified = earlier
        context.insert(entry)
        var held: [String: [String: LibraryPlanItem]] = [:]
        LibraryDatabase.writePlan([reminder()], for: "1", rows: &held, dated: later, in: context)

        let record = LibraryDatabase.stampedTracking(of: entry, rows: nil, plan: held["1"])
        #expect(record.modified == later.toTheMillisecond)
        #expect(record.value.edits[.note] == earlier.toTheMillisecond)
        #expect(record.value.edits[.reminders] == nil)
        // No row of a kind says nothing of it, however new the record.
        #expect(record.value.edits[.queueTickets] == Tracking.unsaid)
        #expect(record.value.edits[.setLists] == Tracking.unsaid)
        #expect(record.value.edits[.goodsNotices] == Tracking.unsaid)
        withExtendedLifetime(database) {}
    }

    /// What a device still on an older build sends after a note is edited
    /// holds neither list. The reader only changed a note.
    @Test func aRecordFromBeforeThePlanLeavesItAlone() throws {
        let (database, context) = database()
        let time = reminder(), link = ticket(), songs = setList(), post = notice()
        var archive = LibraryArchive()
        archive.membership["1"] = Stamped(true, at: earlier)
        archive.tracking["1"] = Stamped(Tracking(reminders: [time], queueTickets: [link], setLists: [songs],
                                                 goodsNotices: [post]), at: earlier)
        try LibraryDatabase.apply(archive, to: context)
        try context.save()

        let older = try JSONDecoder().decode(Tracking.self, from: Data(#"{"note":"front row"}"#.utf8))
        var legacy = LibraryArchive()
        legacy.tracking["1"] = Stamped(older, at: later)
        let held = try LibraryDatabase.archive(in: context)
        try LibraryDatabase.apply(held.merging(legacy), to: context)
        try context.save()

        let plan = try #require(try rows(in: context)["1"])
        #expect(plan.values.allSatisfy { !$0.isRemoved })
        #expect(LibraryDatabase.planItems(EventReminder.self, in: plan) == [time])
        #expect(LibraryDatabase.planItems(QueueTicket.self, in: plan) == [link])
        #expect(LibraryDatabase.planItems(SetList.self, in: plan) == [songs])
        #expect(LibraryDatabase.planItems(GoodsNotice.self, in: plan) == [post])
        #expect(plan.values.allSatisfy { $0.modified == earlier.toTheMillisecond })
        let entries = try context.fetch(FetchDescriptor<LibraryEntry>())
        #expect(entries.map(\.tracking.note) == ["front row"])
        withExtendedLifetime(database) {}
    }

    /// Written out and read back, it still says nothing.
    @Test func whatARecordDoesNotSayStaysUnsaid() throws {
        let older = try JSONDecoder().decode(Tracking.self, from: Data(#"{"seat":"A12"}"#.utf8))
        #expect(!older.says(.reminders))
        #expect(!older.says(.queueTickets))
        #expect(!older.says(.setLists))
        #expect(!older.says(.goodsNotices))
        let again = try JSONDecoder().decode(Tracking.self, from: JSONEncoder().encode(older))
        #expect(!again.says(.reminders))
        #expect(!again.says(.queueTickets))
        #expect(!again.says(.setLists))
        #expect(!again.says(.goodsNotices))
        #expect(again.says(.note))

        // Settled against one that has, whichever is newer.
        let time = reminder()
        let merged = Stamped(older, at: later).merging(Stamped(Tracking(reminders: [time]), at: earlier))
        #expect(merged.value.reminders == [time])
        #expect(merged.value.seat == "A12")
    }

    /// A list emptied on this build is an answer, and still takes the rows out.
    @Test func aListEmptiedIsStillAnAnswer() throws {
        let (database, context) = database()
        let time = reminder()
        var archive = LibraryArchive()
        archive.membership["1"] = Stamped(true, at: earlier)
        archive.tracking["1"] = Stamped(Tracking(reminders: [time]), at: earlier)
        try LibraryDatabase.apply(archive, to: context)
        try context.save()

        archive.tracking["1"] = Stamped(Tracking(), at: later)
        try LibraryDatabase.apply(archive, to: context)
        try context.save()
        #expect(try rows(in: context)["1"]?[time.id.uuidString]?.isRemoved == true)
        withExtendedLifetime(database) {}
    }

    /// A backup written before a reminder was added on another device says
    /// nothing of it, however newly its note was typed.
    @Test func aBackupWithNoRowOfAKindLeavesThatKindAlone() throws {
        let (database, context) = database()
        let time = reminder()
        var archive = LibraryArchive()
        archive.membership["1"] = Stamped(true, at: earlier)
        archive.tracking["1"] = Stamped(Tracking(reminders: [time]), at: earlier)
        try LibraryDatabase.apply(archive, to: context)
        try context.save()

        let entry = LibraryEntry(eventID: "1")
        entry.give(LibraryEntry.Answers(inLibrary: true, tracking: Tracking(note: "front row")),
                   dated: [.inLibrary: later, .tracking: later])
        entry.modified = later
        var backup = LibraryArchive()
        backup.tracking["1"] = LibraryDatabase.stampedTracking(of: entry, rows: nil, plan: nil)

        let held = try LibraryDatabase.archive(in: context)
        for merged in [held.merging(backup), held.restoring(backup)] {
            try LibraryDatabase.apply(merged, to: context)
            try context.save()
            #expect(try rows(in: context)["1"]?[time.id.uuidString]?.isRemoved == false)
        }
        withExtendedLifetime(database) {}
    }

    /// Restoring a backup raises an unchanged list past what its rows say, so
    /// it outranks every device's older copy.
    @Test func aRestoreRaisesAnUnchangedList() throws {
        let (database, context) = database()
        var archive = LibraryArchive()
        archive.membership["1"] = Stamped(true, at: earlier)
        let time = reminder()
        archive.tracking["1"] = Stamped(Tracking(reminders: [time]), at: earlier)
        try LibraryDatabase.apply(archive, to: context)
        try context.save()

        archive.tracking["1"] = Stamped(Tracking(reminders: [time]), at: later)
        #expect(try LibraryDatabase.apply(archive, to: context))
        let row = try #require(try rows(in: context)["1"]?[time.id.uuidString])
        #expect(row.modified == later.toTheMillisecond)
        withExtendedLifetime(database) {}
    }
}
