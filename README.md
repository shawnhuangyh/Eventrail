<p align="center">
  <img src="Design/AppIcon.png" alt="Eventrail app icon: an ivory ticket with an E-shaped trail and three event stops, on a blue background" width="128">
</p>

<h1 align="center">Eventrail</h1>

A native SwiftUI companion app for browsing [Eventernote](https://www.eventernote.com/) events and keeping your own record of the nights you are going to and the ones you have been to — your ticket, your seat, what it cost, and whatever you want to write down — stored on your device and synchronized through your private iCloud account.

> **Status: in beta testing.** Work lands on `main`; test builds are cut by Xcode Cloud from the `release` branch, which a pull request advances when a build is meant to go out — see [Development](#development). Built today: search over Eventernote's public event and performer pages; your own library, with what you paid, where you sat and how many times you entered the lottery; favorites; following performers and a tab of every date they have coming, filterable by when and where; pages for a performer and for a hall, each with everything Eventernote publishes about it and a map of where it stands; the Event Passport, which reads your own past back to you; linking a public Eventernote profile and importing its attendance history and favorites; mirroring the library into your calendar, with an alert when the doors open; a backup file you export and keep; and iCloud sync of everything you own. The library lives in a local JSON file mirrored to your private iCloud key-value storage; persistence has not been moved to SwiftData/CloudKit, background refresh is not built, and the interface ships in English only for now. Not affiliated with or endorsed by Eventernote.

## What it does

**Browse events natively.** Event lists, search, and detail screens rendered as a real iOS app rather than a wrapped web page, populated from publicly accessible Eventernote information. Every event links back to its original page.

**Track events on your own terms.** Keeping an event is itself the record: an event in your library is one you mean to go to, and one still there after its date is one you went to. Nothing asks you to say so twice. What is left is the ticket, and what you want to remember about the night:

| Field | Values |
| --- | --- |
| Ticket | Not purchased / purchased |
| Seat | One free line, as the ticket prints it |
| Price | What it cost, in yen — blank is "not written down", which is not the same as free |
| Lottery entries | How many times you applied for the night |
| Notes | Free-form personal text |

These fields belong to you and to this app. They live in the local database, sync through iCloud, and are never written back to Eventernote.

**Keep the ones that matter in front of you.** Any event can be favorited from its detail sheet, separately from your library and your ticket — it says "keep this where I can see it", not "I am going". Favorites gather on the Me tab, beside what your library adds up to.

**Follow performers and see what they have coming.** Follow anyone from their page, and the Following tab reads each of their Eventernote listings and shows every upcoming date they are billed on, grouped by month and narrowable to one person, one stretch of dates, or one part of the country. Nothing there is in your library until you put it there. Following is your own record, kept beside your library — it is not the favorite list your Eventernote account holds, which this app only ever reads.

**Read your own past back.** The Event Passport, on the Me tab, is every hall you have stood in on a map of the country, with the numbers around it: how many nights, how long they ran, how many venues, performers and prefectures, who you have seen most, where you go most, your longest and shortest nights, and the nights you applied hardest for. Filter it to one year or read all of it. Everything on it comes from your own library — no second record to keep, and nothing there asks Eventernote anything.

**See where the hall is.** A venue gets a page of its own with what Eventernote publishes about it — address, phone, official site, capacity, seating chart, how to get out of the station — and every event it has coming. Eventernote publishes no coordinate, so the hall is placed from its published address: Apple Maps first, and where Maps has never heard of it, the address search of the Geospatial Information Authority of Japan, optionally refined to the building itself by OpenStreetMap. The same placing draws the map in an event's sheet, opens directions, and gives your calendar entry a real location rather than a line of text.

**Put your library in your calendar.** With calendar sync on, every event in your library is mirrored into a calendar of the app's own, past and upcoming, so your events show up wherever you already look for your day. Each entry carries the hall as a place you can tap for directions and, where Eventernote published a door time, an alert for the moment the doors open. It is one-way: the app writes that calendar and reads nothing else of yours. Until you turn it on, the app never asks for calendar access at all.

**Start with as little as you like.** The first launch asks three things and no more: where your records come in from — an Eventernote handle, a backup file, or neither — whether they sync, and whether your calendar is written. Every answer is optional, both switches start off, and each is the same row Settings carries, so nothing there is a one-way door.

**Work offline.** Your library and everything you have annotated is kept in a local file and stays fully usable with no network and no active iCloud connection. Search and importing need the network; what you have already saved does not.

**Sync across your devices.** Personal annotations, favorites, follows, and the event snapshots behind them move between your iPhone and iPad through your own private iCloud storage. There is no app-operated backend and no account to create.

**Keep a copy nothing in the app can reach.** Export your library as a single `.eventrail` file and keep it wherever you keep your own files. Sync and a backup are different promises on purpose: sync keeps your devices agreeing, so a removal travels to all of them; the file is the copy that nothing you do in the app afterwards can undo. Restoring one only ever adds — it puts back what the file holds and this device no longer does, keeps whichever version of a note was typed later, and erases nothing. Tap the file in Files and Eventrail opens it, after asking.

**Import a public Eventernote profile — optionally.** Enter an Eventernote username and the app imports that profile's public attendance history and its favorited performers. This is a one-way, read-only import of public data: no password is collected, no session cookie is extracted, and entering a username does **not** authenticate you or prove you own the account. The interface presents this as importing a public profile, not as signing in.

**Act on Eventernote where Eventernote belongs.** Anything that modifies your Eventernote account happens on the official website via an "Open in Eventernote" action, where you authenticate directly. On return, the app can refresh the imported public state — it never assumes a website visit means the action succeeded.

## How your data is treated

The design is built around one rule: **imports serve your records; they never overwrite them.**

- The two layers are kept strictly apart. What Eventernote publishes about an event — its title, day, times, hall and billing — is the site's; whether it is in your library and everything you wrote on it is yours. An import writes only the first.
- A refresh never touches your notes, your ticket status, your seat, your price, your lottery count, your favorites, or what is in your library.
- Records are never deleted just because they're missing from one response. A failed request, incomplete pagination, or a changed page layout looks the same as a genuine cancellation, so nothing is removed on the strength of one — an import only ever adds.
- On network or parsing failure, the last successful snapshot is retained and the app shows you when it last refreshed successfully. A page whose layout has changed yields a missing field or a dropped row, never wrong information.
- Repeated imports are idempotent: events are keyed by stable Eventernote event IDs, not by titles or dates, so re-importing produces no duplicates.
- iCloud conflict handling merges record by record rather than file by file: every record you own carries the moment it changed, so an edit made on one device never erases an unrelated edit made on another, and removing an event travels to your other devices instead of being undone by the next merge.

**Removing and re-importing.** A removal settles what this app holds — it travels to your other devices and stays gone there. It does not reach Eventernote, and it was never meant to: your account's record is what the import reads from, so asking Eventernote again is how you get back something you took out and then wanted. An import restores an event your linked account still lists and re-follows a performer it still favorites. What the account never carried — an event saved from Search, a performer followed here alone — stays gone for good, because nothing will bring it back. Dropping something permanently means dropping it on Eventernote too.

## Refreshing

| Trigger | Behavior | Built |
| --- | --- | --- |
| Manual refresh | The Refresh button beside the linked account: imports immediately and reports the result | Yes |
| Pull to refresh | Re-reads the followed performers' dates on Following, and places any unplaced halls on the Passport | Yes |
| Launch / foreground | Refreshes if the last successful import is sufficiently old | Not yet |
| Return from the official website | Attempts a refresh when a public profile is associated | Not yet |
| Background opportunity | Refreshes when iOS grants execution time | Not yet |

Refreshing is entirely on your command today, and reports what it actually did. iOS background execution is opportunistic in any case, so the app will make no promise of exact hourly or daily refresh: manual and foreground refresh are meant to be the dependable paths, and background refresh an enhancement. The planned shape for the automatic ones is bounded, backed-off requests with upcoming events refreshed more often than history, and periodic full reconciliation to catch older changes.

## Privacy

- Personal annotations live on your device and in your private iCloud storage. No app-operated backend.
- Associating a public profile is clearly labeled as unverified — it does not confirm account ownership. No password or session cookie is ever collected.
- Your own records are always visually distinct from what was imported.
- You can remove an associated profile and keep all of your personal records.
- Deleting imported data and deleting personal annotations are separate controls.
- Calendar sync writes a calendar of the app's own and reads nothing else from yours; turning it off leaves your calendar alone, and until you turn it on the app never asks for access.
- iCloud sync is a per-device switch: turning it off on your phone does not turn it off on your iPad.
- A backup you export goes only where you send it.
- **What leaves your device, and to whom.** Public page requests to Eventernote, and the flyer images those pages point at. To place a hall, its name and its published address go to Apple Maps, and where Maps has no such place, to the address search of the Geospatial Information Authority of Japan (国土地理院) and — only if you leave the precise-venues switch on, and only for a hall whose event you are looking at — to OpenStreetMap. None of those requests carries your notes, your library, your profile, or an identifier for you, and nothing asks for your location: the maps show halls, not you.
- Diagnostics exclude personal notes and any authentication material.

## Platforms

iPhone and iPad from a single SwiftUI target (deployment target 26.0), built with Xcode. macOS and visionOS were dropped deliberately. The library is currently a plain JSON file in Application Support, mirrored to iCloud key-value storage; SwiftData or Core Data with CloudKit is still the intended destination, to be chosen after validating schema constraints, conflict behavior, and migration requirements.

## Languages

The app is written to be localized into four languages:

| Language | Locale code |
| --- | --- |
| English | `en` |
| Japanese | `ja` |
| Simplified Chinese | `zh-Hans` |
| Traditional Chinese | `zh-Hant` |

All user-facing text — screen labels, the ticket and status values, refresh status, and error messages — is defined as localizable strings rather than hard-coded, so dates, times, and numbers are already formatted for your locale. **The translations themselves are not written yet:** today every language falls back to English. The app follows your system language and region settings, and you can override it per-app in iOS Settings without changing your system language.

Event content is never translated. Event titles, venue names, and performer names come from Eventernote as published (predominantly Japanese) and are displayed verbatim in every language, so they always match the official page. Your own notes are likewise stored and shown exactly as you typed them, in whatever language you use.

## Scope of the first release

Native browsing, search, and event, performer and venue detail; the local tracking fields; favorites and followed performers; the Event Passport; maps for the halls; offline access; iCloud sync; an exported backup file; calendar mirroring with door-time alerts; one optional public username import; manual and on-activation refresh; website links for account actions; honest refresh status and error handling; and a fully localized interface in English, Japanese, Simplified Chinese, and Traditional Chinese.

Deliberately deferred: background refresh, exact-time scheduling, an app-operated backend, writing to Eventernote from the app, importing private Eventernote notes, and managing multiple profiles.

## A note on the integration

Eventernote publishes no documented API, access tokens, or OAuth registration that this project has found. Public data retrieval is therefore isolated behind an adapter so that website changes break imports without endangering your stored records or the native screens. The reviewed terms of service do not expressly address third-party clients but do contain broader prohibitions; this repository does not assert permission or offer a legal conclusion, and a public release would need to account for the current terms and any guidance from the operator.

## Development

The app is in beta testing. Every change lands on `main`, which is committed to directly; `release` is the branch testers' builds come from. Xcode Cloud starts on branch changes to `release`, and `release` is advanced only by a pull request opened when a build is meant to go out — so a commit on `main` reaches no one until then:

```bash
# ordinary work
git switch main
# edit, build, commit
git push

# when a build should go out
gh pr create --base release --head main --title "release: <what is in this build>"
```

That pull request is where the whole of a build is read before it ships. A hotfix branches off `release` when `main` is carrying unfinished work, and is merged into both. A pull request into `main` is welcome for anything worth reviewing, but is not required for ordinary work; where one is opened, the branch takes the commit type as its prefix (`feat/`, `fix/`, `docs/`, `test/`, `refactor/`, `chore/`).

Commit subjects follow `<type>: <concise imperative summary>`. Build for the simulator with:

```bash
xcodebuild -scheme Eventrail -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
```

There is no package manifest and no dependency to fetch; opening [`Eventrail.xcodeproj`](Eventrail.xcodeproj) in Xcode is enough.

## Icon

The icon is an Icon Composer document at [`Eventrail/AppIcon.icon`](Eventrail/AppIcon.icon) — a ticket whose cutout traces an E through three event stops, over the app's blue. [`Design/AppIcon.svg`](Design/AppIcon.svg) is the full 1024pt source drawing it was cut from, and `Design/AppIcon.png` is the rendering shown above.

## License

[MIT](LICENSE). The license covers this app's own source; it says nothing about
Eventernote's content, which remains the site's — see the note on the
integration above.
