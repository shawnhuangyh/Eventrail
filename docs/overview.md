# Eventrail Overview

Eventrail is a native SwiftUI app for browsing [Eventernote](https://www.eventernote.com/) events and keeping your own record of the events you are going to and the ones you have been to: the lotteries you entered, your ticket, your seat, what it cost, and whatever you want to write down. That record is stored on your device and, if you choose, synced through your private iCloud account.

[← Back to README](../README.md)

- [What it does](#what-it-does)
- [How your data is treated](#how-your-data-is-treated)
- [Refreshing](#refreshing)
- [Privacy](#privacy)
- [Languages](#languages)
- [Platforms](#platforms)
- [A note on the integration](#a-note-on-the-integration)
- [Icon](#icon)

## What it does

**Browse events natively.** Event lists, search and detail screens are drawn as a real iOS app rather than a wrapped web page, filled from publicly accessible Eventernote information. Before you type anything, Search opens on two of the site's own lists: Today, everything on the site's current day in Japan by start time, and Just Added, the hundred events most recently added to the site. Event results can be held to upcoming or past dates and to one of the site's areas, and sorted oldest or newest first. A performer you follow is marked wherever an event bills them. Every event links back to its original page.

**Track events on your own terms.** Keeping an event is itself the record: an event in your library is one you mean to go to, and one you held a ticket for once its day was over is one you went to. Nothing asks you to say so twice. What is left is how you got the ticket, and what you want to remember about the event:

| Field | Values |
| --- | --- |
| Lottery entries | Each round of the sale you tried for: which round (最速先行抽選, プレイガイド先行, プレイガイド二次先行, or 一般発売 and 見切れ席, which are first come, first served), how many times you applied, the day results come out, up to three seat choices in order of preference, and whether you won |
| Ticket | Not asked on its own: you hold one once you win a lottery or get a seat in a first-come round |
| Seat | One free line, as the ticket prints it. Its class (S, A, General) comes from the round you won |
| Price | What it cost, in any currency. Blank means "not written down", which is not the same as free |
| Notes | Free-form personal text |

These fields belong to you and to this app. They live on your device, sync through iCloud, and are never written back to Eventernote. Upcoming events in the library count down the days until they arrive. A past event you went to without writing down how you got in can be given a ticket from My Events, several at once.

**Follow your lotteries to the result.** The Lotteries card on the Me tab shows the next rounds waiting on a result, and its full list splits every round into Awaiting and Decided, each with a tile for its results day that lights up once results are out. Record Won or Lost from that tile or with a swipe, without opening the event; neither is offered before the results day. Decided can also show the rounds of events that are over, to look back on. At 8 PM on a results day, on your own clock, a notification reminds you to record the result and opens straight to that round.

**Keep the ones that matter in front of you.** Any event can be favorited from its detail sheet, separately from your library and your ticket. A favorite says "keep this where I can see it", not "I am going". Favorites gather on the Me tab.

**Follow performers and see what they have coming.** Follow anyone from their page, and the Following tab reads each of their Eventernote listings and shows every upcoming date they are billed on, grouped by month. You can narrow it to one person, to the next week, month, three months or six months, and to one or more parts of the country. A date leaves the list once it has finished. Nothing there is in your library until you put it there. Following is your own record, kept beside your library. It is not the favorite list your Eventernote account holds, which this app only ever reads.

**See what is new since you last looked.** The Following tab reads like a mailbox. A date you have not opened carries a **NEW** tag after the performers' names, and a date you have already read comes back as **UPDATED** when Eventernote later changes its title, hall, day, times or billing. Opening a date marks it read; swiping a row from its leading edge marks it read or unread; and the pencil lets you pick several and mark them at once. The envelope button at the top shows only what is unread. Upcoming events in My Events carry the same mark, and a date read on either tab is read on both. Which dates you have read is your own record, so it syncs to your other devices and goes into a backup. Clearing the cache leaves it alone; Delete All Events turns every date back to new.

**Read an event's overview in your language.** An event's 概要 is usually written in Japanese. On your tap, Apple's on-device Translation framework translates it into the app's language, or into another language you pick under Settings › Locale. The translation is shown on the sheet and never saved.

**Read your own past back.** The Event Passport, on the Me tab, puts every hall you have stood in on a map of the country — every one that has been placed, that is; a hall no map service has found yet still counts in the numbers but has no pin — with the numbers around it: how many events, how long they ran, your longest and shortest, how many venues, performers and prefectures, who you have seen most and where you go most. Ticket Spending adds up what your tickets cost, by seat class, with the dearest and the cheapest, in your default currency or any other you pick; a ticket paid in another currency is converted at today's exchange rates. Lottery Entries shows how your lotteries went: the win rate, by round and by seat class, how many rounds and entries a win took, and the events you applied hardest for. Only events you held a ticket for count as attended; the lottery card counts every past event you applied for, won or lost. Filter it to one year or read all of it. Everything on it comes from your own library, so there is no second record to keep, and nothing there asks Eventernote anything; the one thing it fetches is today's exchange rates, and only when a ticket has to be converted.

**Keep your ticket as a picture.** Once you hold a ticket, an event's sheet offers a Ticket Stub: a keepsake image the shape of a story, printed with the date, title, hall, times, price, seat and class, and stamped 使用済 once the event is over, or 当選 for a lottery won for an event still ahead. Choose Light or Night, and whether it prints the flyer, the times and the price. The seat is masked unless you say otherwise, and a masked seat is drawn as a mosaic in its place, so nothing under it can be recovered from the picture. Save it to Photos or share it.

**Follow the day as it happens.** For an event you hold a ticket for, the sheet can put a Live Activity on your iPhone's Lock Screen and in the Dynamic Island: how long until the doors, the start and the end, and your seat. It moves on through the event by itself, with no server behind it, and appears in a paired Apple Watch's Smart Stack too. The system ends a Live Activity eight hours after it starts, so one can be turned on from eight hours before the event is due to end.

**Carry it on your wrist.** The Apple Watch app lists your upcoming events and shows each in three pages turned with the Digital Crown: the countdown, your seat, and the times. It keeps no library of its own: your iPhone sends it a copy of what is coming up whenever the library changes, so it works with the phone out of reach and can never change your records. The only thing it fetches itself is each event's flyer.

**See where the hall is.** A venue gets a page of its own with what Eventernote publishes about it (address, phone, official site, capacity, seating chart, how to get there from the station) and every event it has coming. Eventernote publishes no coordinate, so the hall is placed from its published address: Apple Maps first; where Maps has never heard of it, the address search of the Geospatial Information Authority of Japan (国土地理院); and, optionally, OpenStreetMap to narrow that down to the building itself. On a phone whose Apple Maps is served by the mainland-China provider, which carries no venues abroad, a hall outside Japan and the mainland can be placed only by OpenStreetMap, so it stays unplaced while the switch is off. The same placing draws the map in an event's sheet, opens directions, and gives your calendar entry a real location instead of a line of text. Settings › Advanced › Venue Locations shows how many of your halls each source placed.

**Show times in the hall's own clock.** Eventernote writes every time as the hall's wall clock. Eventrail keeps it that way: every event sheet prints the hall's times, with a Venue / Local switch to read that one event on your own clock instead, and the offset of the clock shown (for example GMT+9) once the hall's clock is established — from a placing, or from an address in Japan; a hall abroad nothing has placed yet shows no offset rather than a guess. An event abroad lands at the right moment in your calendar wherever you are reading from. Settings › Time Zone can print every day and time in the app on your own clock (Local Time). That changes only what is printed: months, filters, countdowns and calendar entries still go by the day the hall says the event falls on and the real moment it starts.

**Put your library in your calendar.** With calendar sync on, every event in your library is mirrored into a calendar of the app's own, past and upcoming, ticket or not, so your events show up wherever you already look for your day. Each entry carries the hall as a place you can tap for directions and, where Eventernote published a door time, an alert for the moment the doors open. It is one-way: the app writes that calendar and writes nothing else of yours. The only other calendars it looks at are ones named Eventrail, to recognise its own calendar synced from another of your devices rather than make a second one; one holding anything but Eventernote entries is never taken over. Until you turn it on, the app never asks for calendar access.

**Start with as little as you like.** The first launch asks three things and no more: where your records come in from (an Eventernote handle, a backup file, or neither), whether they sync, and whether your calendar is written. Every answer is optional, both switches start off, and each is the same row Settings carries, so nothing there is a one-way door.

**Work offline.** Your library and everything you have written on it is kept in a local file and stays fully usable with no network and no iCloud connection. Search and importing need the network; what you have already saved does not.

**Sync across your devices.** Your annotations, favorites, follows, which Following dates you have read, and the event details behind them move between your iPhone and iPad through your own private iCloud storage. There is no app-operated backend and no account to create. A change leaves the device it was made on within a second or two; when the other device picks it up is iCloud's call, not the app's. Usually that is a few seconds, but a device that has just fetched can wait a few minutes before it fetches again, so a change made right after another one tends to arrive later than the first. Settings shows when this device last fetched from iCloud, which is how you tell a change that has not arrived yet from one that went missing. Run the same version of Eventrail on every device you sync.

**Keep a copy nothing in the app can reach.** Export your library as a single `.eventrail` file and keep it wherever you keep your own files. Sync and a backup are different promises on purpose: sync keeps your devices agreeing, so a removal travels to all of them; the file is the copy that nothing you do in the app afterwards can undo. Restoring one only ever adds: it puts back what the file holds and this device no longer does, keeps whichever version of a note was typed later, and erases nothing. Tap the file in Files and Eventrail opens it, after asking.

**Import a public Eventernote profile, optionally.** Enter an Eventernote username and the app imports that profile's public attendance history and its favorited performers. A profile does not say how you got in, so its past events arrive without tickets; My Events offers to go through them and record the ones you held a ticket for, and until then they are not counted as attended. This is a one-way, read-only import of public data: no password is collected, no session cookie is extracted, and entering a username does **not** sign you in or prove you own the account.

**Act on Eventernote where Eventernote belongs.** Anything that changes your Eventernote account happens on the official website through an "Open in Eventernote" link, where you sign in directly.

## How your data is treated

The design is built around one rule: **imports serve your records; they never overwrite them.**

- The two layers are kept strictly apart. What Eventernote publishes about an event (its title, day, times, hall and billing) is the site's. Whether it is in your library and everything you wrote on it is yours. An import writes only the first.
- A refresh never touches your notes, your lottery entries, your seat, your price, your favorites, or what is in your library.
- Records are never deleted just because they are missing from one response. A failed request, incomplete pagination or a changed page layout looks the same as a genuine cancellation, so nothing is removed on the strength of one. An import only ever adds.
- A failed refresh never costs what was already held. The last good copy stays on screen with a note saying the update failed. A page whose layout has changed yields a missing field or a dropped row, never wrong information.
- Repeated imports produce no duplicates: events are keyed by stable Eventernote event IDs, not by titles or dates.
- Everything you decide about an event (whether it is in your library, the heart, your lottery entries, seat, price and note) is one record, written only when you change it. Reading an event's page from Eventernote updates a separate record of the site's facts and never touches yours, so a device that has not caught up yet cannot undo a removal just by opening the event. A device that imports your Eventernote account before your other device's notes have reached it keeps those notes once they arrive. If two devices change the same answer about an event before either has heard from the other — minutes apart, or longer for a device that was offline — the change that reaches iCloud last is the one that stands.

**Removing and re-importing.** Taking an event out of your library asks first, and clears what you wrote on it — its lottery entries, seat, price and note — on every device; the heart stays. A removal settles what this app holds: it travels to your other devices and stays gone there. It does not reach Eventernote, and it was never meant to. Your account's record is what the import reads from, so importing again is how you get back something you took out and then wanted. An import restores an event your linked account still lists, with nothing written on it, and re-follows a performer it still favorites. What the account never carried (an event saved from Search, a performer followed only in Eventrail) stays gone for good, because nothing will bring it back. Dropping something permanently means dropping it on Eventernote too.

## Refreshing

Eventernote publishes no API and stops answering an app that asks too fast, so Eventrail keeps a copy of every page it reads and only reads again what has gone stale (older than six hours). Asking by hand always reads.

| Trigger | Behavior |
| --- | --- |
| Opening a screen | Following, the Me tab, Search's Today and Just Added, an event sheet, and a performer's or hall's page show their saved copy at once and re-read only if it is stale |
| Returning to the app | The same stale check runs again when the app comes back to the foreground |
| Pull to refresh | Re-reads every followed performer's listing on Following |
| Refresh in a page's ⋯ menu | Re-reads an event's sheet, a performer's or hall's page, or Today and Just Added |
| Refresh on the Me tab | Re-imports the linked profile and re-reads every upcoming event page |
| Venue refresh in Settings | Re-places every hall in your library |
| Background | Nothing is read from Eventernote. Only a running Live Activity is brought up to date, when the system allows |

A refresh you asked for always ends in a short notice ("Updated" or "Update failed" and why). One the app started on its own only speaks up when it failed. If Eventernote refuses a request, the rest of that run stops rather than being refused too. When a page was last read is the first line of the small print at its foot.

## Privacy

- Your records live on your device and, if you turn sync on, in your private iCloud storage. There is no app-operated backend.
- Linking a public profile is labeled as unverified: it does not confirm account ownership, and no password or session cookie is ever collected.
- You can unlink a profile and keep all of your own records.
- Calendar sync writes a calendar of the app's own and changes nothing else of yours. Turning it off deletes that Eventrail calendar; it usually lives in iCloud, so it goes from your other devices too, until one of them with the switch still on writes it again. Your own calendars are left alone either way, and until you turn it on the app never asks for access.
- iCloud sync and calendar sync are per-device switches, and both start off. Turning sync off on your phone does not turn it off on your iPad.
- Lottery reminders are local notifications, scheduled by each device for itself; nothing goes through a server. The switch is on by default, per device, and the system asks for permission only the first time you save a round with a results day still to come.
- Saving a flyer or a ticket stub asks for add-only access to Photos. Nothing reads your photo library.
- The Live Activity and the Apple Watch app are drawn from what is on your iPhone. The watch is sent its copy by the phone, never through iCloud, and never asks the phone for anything.
- A backup you export goes only where you send it.
- Overview translation runs on the device. The text is not sent anywhere.
- **What leaves your device, and to whom.** Public page requests to Eventernote, and the flyer images those pages point at (the watch fetches its flyers from the same host). Today's exchange rates from Frankfurter, only when a ticket price has to be converted: one request for every currency at once, kept for twelve hours. To place a hall, its name and published address go to Apple Maps and, where Maps has no such place, to the address search of 国土地理院. OpenStreetMap is asked only while the Refine with OpenStreetMap switch is on, and only for a hall whose event you are looking at or a refresh you started: to narrow a hall in Japan to its building, or, where your phone's Apple Maps is the mainland-China provider, to place a hall outside Japan and the mainland. None of those requests carries your notes, your prices, your library, your profile or an identifier for you, and nothing asks for your location: the maps show halls, not you.

## Languages

| Language | Locale code |
| --- | --- |
| English | `en` |
| Japanese | `ja` |
| Simplified Chinese | `zh-Hans` |
| Traditional Chinese | `zh-Hant` |

The interface is localized into all four. The app follows your system language, and you can override it per app in iOS Settings (Eventrail links there from Settings › Locale).

Event content is not rewritten. Titles, venue names and performer names come from Eventernote as published (mostly Japanese) and are shown verbatim in every language, so they always match the official page. The one exception is an event's overview, which you can choose to translate on the device, as described above. Your own notes are stored and shown exactly as you typed them.

## Platforms

iPhone and iPad from a single SwiftUI app, deployment target iOS 26.0, with a widget extension that draws the Live Activity (iPhone only) and a companion Apple Watch app, watchOS 26.0, that shows what the phone sends it. macOS and visionOS were dropped deliberately. The library is a SwiftData store in Application Support, one row per record, synced by SwiftData's own CloudKit mirroring into the reader's private database. The rows are cut by who writes them (what you decided about an event in one record, what Eventernote says about it in another), so CloudKit's own rule that the last change to reach it stands is the right answer, and nothing is merged on top of it. Two devices that wrote a row for the same thing keep the same one of them, on every device.

## A note on the integration

Eventernote publishes no documented API, access tokens or OAuth registration that this project has found. Public data retrieval is therefore isolated behind an adapter, so a change to the website breaks imports without endangering your stored records or the app's screens. Every request is a read; nothing is ever written back to Eventernote. The reviewed terms of service do not expressly address third-party clients but do contain broader prohibitions. This repository does not assert permission or offer a legal conclusion, and a public release would need to account for the current terms and any guidance from the operator.

## Icon

The icon is an Icon Composer document at [`Eventrail/AppIcon.icon`](../Eventrail/AppIcon.icon): a ticket whose cutout traces an E through three event stops, over the app's blue. [`Design/AppIcon.svg`](../Design/AppIcon.svg) is the full 1024 pt source drawing it was cut from, and [`Design/AppIcon.png`](../Design/AppIcon.png) is the rendering shown in the README.
