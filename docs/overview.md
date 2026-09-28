# Eventrail Overview

Eventrail is a native SwiftUI app for browsing [Eventernote](https://www.eventernote.com/) events and keeping your own record of the nights you are going to and the ones you have been to: your ticket, your seat, what it cost, and whatever you want to write down. That record is stored on your device and, if you choose, synced through your private iCloud account.

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

**Browse events natively.** Event lists, search and detail screens are drawn as a real iOS app rather than a wrapped web page, filled from publicly accessible Eventernote information. Every event links back to its original page.

**Track events on your own terms.** Keeping an event is itself the record: an event in your library is one you mean to go to, and one still there after its date is one you went to. Nothing asks you to say so twice. What is left is the ticket, and what you want to remember about the night:

| Field | Values |
| --- | --- |
| Ticket | Not purchased / purchased |
| Seat | One free line, as the ticket prints it |
| Price | What it cost, in yen. Blank means "not written down", which is not the same as free |
| Lottery entries | How many times you applied for the night |
| Notes | Free-form personal text |

These fields belong to you and to this app. They live on your device, sync through iCloud, and are never written back to Eventernote. Upcoming nights in the library count down the days until they arrive.

**Keep the ones that matter in front of you.** Any event can be favorited from its detail sheet, separately from your library and your ticket. A favorite says "keep this where I can see it", not "I am going". Favorites gather on the Me tab.

**Follow performers and see what they have coming.** Follow anyone from their page, and the Following tab reads each of their Eventernote listings and shows every upcoming date they are billed on, grouped by month. You can narrow it to one person, one stretch of dates, or one part of the country. Nothing there is in your library until you put it there. Following is your own record, kept beside your library. It is not the favorite list your Eventernote account holds, which this app only ever reads.

**See what is new since you last looked.** The Following tab reads like a mailbox. A date you have not opened carries a **NEW** tag beside the performer's name, and a date you have already read comes back as **UPDATED** when Eventernote later changes its title, hall, day, times or billing. Opening a date marks it read; swiping a row from its left edge marks it read or unread; and the pencil lets you pick several and mark them at once. The envelope button at the top shows only what is unread. Which dates you have read is your own record, so it syncs to your other devices and goes into a backup. Clearing the cache leaves it alone; Delete All Events turns every date back to new.

**Read an event's overview in your language.** An event's 概要 is usually written in Japanese. On your tap, Apple's on-device Translation framework translates it into the app's language, or into another language you pick under Settings › Language. The translation is shown on the sheet and never saved.

**Read your own past back.** The Event Passport, on the Me tab, puts every hall you have stood in on a map of the country — every one that has been placed, that is; a hall no map service has found yet still counts in the numbers but has no pin, with the numbers around it: how many nights, how long they ran, how many venues, performers and prefectures, who you have seen most, where you go most, your longest and shortest nights, and the nights you applied hardest for. Filter it to one year or read all of it. Everything on it comes from your own library, so there is no second record to keep, and nothing there asks Eventernote anything.

**See where the hall is.** A venue gets a page of its own with what Eventernote publishes about it (address, phone, official site, capacity, seating chart, how to get there from the station) and every event it has coming. Eventernote publishes no coordinate, so the hall is placed from its published address: Apple Maps first; where Maps has never heard of it, the address search of the Geospatial Information Authority of Japan (国土地理院); and, optionally, OpenStreetMap to narrow that down to the building itself. On a phone whose Apple Maps is served by the mainland-China provider, which carries no venues abroad, a hall outside Japan and the mainland can be placed only by OpenStreetMap, so it stays unplaced while the switch is off. The same placing draws the map in an event's sheet, opens directions, and gives your calendar entry a real location instead of a line of text. Settings › Advanced › Venue Locations shows how many of your halls each source placed.

**Show times in the hall's own clock.** Eventernote writes every time as the hall's wall clock. Eventrail keeps it that way and labels every event sheet "Venue time", with the offset once the hall's clock is established (for example "Venue time · GMT+9") — from a placing, or from an address in Japan; a hall abroad nothing has placed yet shows the label alone rather than a guess. A night abroad lands at the right moment in your calendar wherever you are reading from. Settings › Time Zone can print every day and time on your own clock instead ("My time · GMT+8"). That changes only what is printed: months, filters, countdowns and calendar entries still go by the day the hall says the night falls on and the real moment it starts.

**Put your library in your calendar.** With calendar sync on, every event in your library is mirrored into a calendar of the app's own, past and upcoming, so your events show up wherever you already look for your day. Each entry carries the hall as a place you can tap for directions and, where Eventernote published a door time, an alert for the moment the doors open. It is one-way: the app writes that calendar and writes nothing else of yours. The only other calendars it looks at are ones named Eventrail, to recognise its own calendar synced from another of your devices rather than make a second one; one holding anything but Eventernote entries is never taken over. Until you turn it on, the app never asks for calendar access.

**Start with as little as you like.** The first launch asks three things and no more: where your records come in from (an Eventernote handle, a backup file, or neither), whether they sync, and whether your calendar is written. Every answer is optional, both switches start off, and each is the same row Settings carries, so nothing there is a one-way door.

**Work offline.** Your library and everything you have written on it is kept in a local file and stays fully usable with no network and no iCloud connection. Search and importing need the network; what you have already saved does not.

**Sync across your devices.** Your annotations, favorites, follows, which Following dates you have read, and the event details behind them move between your iPhone and iPad through your own private iCloud storage. There is no app-operated backend and no account to create. A change leaves the device it was made on within a second or two; when the other device picks it up is iCloud's call, not the app's. Usually that is a few seconds, but a device that has just fetched can wait a few minutes before it fetches again, so a change made right after another one tends to arrive later than the first. Settings shows when this device last fetched from iCloud, which is how you tell a change that has not arrived yet from one that went missing. Run the same version of Eventrail on every device you sync.

**Keep a copy nothing in the app can reach.** Export your library as a single `.eventrail` file and keep it wherever you keep your own files. Sync and a backup are different promises on purpose: sync keeps your devices agreeing, so a removal travels to all of them; the file is the copy that nothing you do in the app afterwards can undo. Restoring one only ever adds: it puts back what the file holds and this device no longer does, keeps whichever version of a note was typed later, and erases nothing. Tap the file in Files and Eventrail opens it, after asking.

**Import a public Eventernote profile, optionally.** Enter an Eventernote username and the app imports that profile's public attendance history and its favorited performers. This is a one-way, read-only import of public data: no password is collected, no session cookie is extracted, and entering a username does **not** sign you in or prove you own the account.

**Act on Eventernote where Eventernote belongs.** Anything that changes your Eventernote account happens on the official website through an "Open in Eventernote" link, where you sign in directly.

## How your data is treated

The design is built around one rule: **imports serve your records; they never overwrite them.**

- The two layers are kept strictly apart. What Eventernote publishes about an event (its title, day, times, hall and billing) is the site's. Whether it is in your library and everything you wrote on it is yours. An import writes only the first.
- A refresh never touches your notes, your ticket status, your seat, your price, your lottery count, your favorites, or what is in your library.
- Records are never deleted just because they are missing from one response. A failed request, incomplete pagination or a changed page layout looks the same as a genuine cancellation, so nothing is removed on the strength of one. An import only ever adds.
- A failed refresh never costs what was already held. The last good copy stays on screen with a note saying the update failed. A page whose layout has changed yields a missing field or a dropped row, never wrong information.
- Repeated imports produce no duplicates: events are keyed by stable Eventernote event IDs, not by titles or dates.
- Everything you decide about an event (whether it is in your library, the heart, your ticket, seat, price, lottery count and note) is one record, written only when you change it. Reading an event's page from Eventernote updates a separate record of the site's facts and never touches yours, so a device that has not caught up yet cannot undo a removal just by opening the event. A device that imports your Eventernote account before your other device's notes have reached it keeps those notes once they arrive. If two devices change the same answer about an event before either has heard from the other — minutes apart, or longer for a device that was offline — the change that reaches iCloud last is the one that stands.

**Removing and re-importing.** A removal settles what this app holds: it travels to your other devices and stays gone there. It does not reach Eventernote, and it was never meant to. Your account's record is what the import reads from, so importing again is how you get back something you took out and then wanted. An import restores an event your linked account still lists and re-follows a performer it still favorites. What the account never carried (an event saved from Search, a performer followed only in Eventrail) stays gone for good, because nothing will bring it back. Dropping something permanently means dropping it on Eventernote too.

## Refreshing

Eventernote publishes no API and stops answering an app that asks too fast, so Eventrail keeps a copy of every page it reads and only reads again what has gone stale (older than six hours). Asking by hand always reads.

| Trigger | Behavior |
| --- | --- |
| Opening a screen | Following, the Me tab, an event sheet, and a performer's or hall's page show their saved copy at once and re-read only if it is stale |
| Returning to the app | The same stale check runs again when the app comes back to the foreground |
| Pull to refresh | Re-reads Following, an event's sheet, or a performer's or hall's page |
| Refresh on the Me tab | Re-imports the linked profile and re-reads every upcoming event page |
| Venue refresh in Settings | Re-places every hall in your library |
| Background | Not built |

A refresh you asked for always ends in a short notice ("Updated" or "Update failed" and why). One the app started on its own only speaks up when it failed. If Eventernote refuses a request, the rest of that run stops rather than being refused too.

## Privacy

- Your records live on your device and, if you turn sync on, in your private iCloud storage. There is no app-operated backend.
- Linking a public profile is labeled as unverified: it does not confirm account ownership, and no password or session cookie is ever collected.
- You can unlink a profile and keep all of your own records.
- Calendar sync writes a calendar of the app's own and changes nothing else of yours. Turning it off deletes that Eventrail calendar; it usually lives in iCloud, so it goes from your other devices too, until one of them with the switch still on writes it again. Your own calendars are left alone either way, and until you turn it on the app never asks for access.
- iCloud sync and calendar sync are per-device switches, and both start off. Turning sync off on your phone does not turn it off on your iPad.
- A backup you export goes only where you send it.
- Overview translation runs on the device. The text is not sent anywhere.
- **What leaves your device, and to whom.** Public page requests to Eventernote, and the flyer images those pages point at. To place a hall, its name and published address go to Apple Maps and, where Maps has no such place, to the address search of 国土地理院. OpenStreetMap is asked only while the Refine with OpenStreetMap switch is on, and only for a hall whose event you are looking at or a refresh you started: to narrow a hall in Japan to its building, or, where your phone's Apple Maps is the mainland-China provider, to place a hall outside Japan and the mainland. None of those requests carries your notes, your library, your profile or an identifier for you, and nothing asks for your location: the maps show halls, not you.

## Languages

| Language | Locale code |
| --- | --- |
| English | `en` |
| Japanese | `ja` |
| Simplified Chinese | `zh-Hans` |
| Traditional Chinese | `zh-Hant` |

The interface is localized into all four. The app follows your system language, and you can override it per app in iOS Settings (Eventrail links there from Settings › Language).

Event content is not rewritten. Titles, venue names and performer names come from Eventernote as published (mostly Japanese) and are shown verbatim in every language, so they always match the official page. The one exception is an event's overview, which you can choose to translate on the device, as described above. Your own notes are stored and shown exactly as you typed them.

## Platforms

iPhone and iPad from a single SwiftUI target, deployment target iOS 26.0. macOS and visionOS were dropped deliberately. The library is a SwiftData store in Application Support, one row per record, synced by SwiftData's own CloudKit mirroring into the reader's private database. The rows are cut by who writes them (what you decided about an event in one record, what Eventernote says about it in another), so CloudKit's own rule that the last change to reach it stands is the right answer, and nothing is merged on top of it. Two devices that wrote a row for the same thing keep the same one of them, on every device.

## A note on the integration

Eventernote publishes no documented API, access tokens or OAuth registration that this project has found. Public data retrieval is therefore isolated behind an adapter, so a change to the website breaks imports without endangering your stored records or the app's screens. Every request is a read; nothing is ever written back to Eventernote. The reviewed terms of service do not expressly address third-party clients but do contain broader prohibitions. This repository does not assert permission or offer a legal conclusion, and a public release would need to account for the current terms and any guidance from the operator.

## Icon

The icon is an Icon Composer document at [`Eventrail/AppIcon.icon`](../Eventrail/AppIcon.icon): a ticket whose cutout traces an E through three event stops, over the app's blue. [`Design/AppIcon.svg`](../Design/AppIcon.svg) is the full 1024 pt source drawing it was cut from, and [`Design/AppIcon.png`](../Design/AppIcon.png) is the rendering shown in the README.
