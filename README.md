<p align="center">
  <img src="Design/AppIcon.png" alt="Eventrail app icon: an ivory ticket with an E-shaped trail and three event stops, on a blue background" width="128">
</p>

<h1 align="center">Eventrail</h1>

A native SwiftUI companion app for browsing [Eventernote](https://www.eventernote.com/) events and keeping your own record of what you're interested in, what you have tickets for, and what you actually attended — stored on your device and synchronized through your private iCloud account.

> **Status: early development.** Built today: search over Eventernote's public event and performer pages, your own library with the four tracking fields, favorites, following performers and a tab of every date they have coming, linking a public Eventernote profile and importing its attendance history and favorites, mirroring the library into your calendar, and iCloud sync of everything you own. The library lives in a local JSON file mirrored to your private iCloud key-value storage; persistence has not been moved to SwiftData/CloudKit, background refresh is not built, and the interface ships in English only for now. Not affiliated with or endorsed by Eventernote.

## What it does

**Browse events natively.** Event lists, search, and detail screens rendered as a real iOS app rather than a wrapped web page, populated from publicly accessible Eventernote information. Every event links back to its original page.

**Track events on your own terms.** For any event you can independently record:

| Field | Values |
| --- | --- |
| Interest | Interested / planning to attend |
| Ticket status | Not purchased / purchased |
| Attendance | Unrecorded / attended |
| Notes | Free-form personal text |

These fields belong to you and to this app. They live in the local database, sync through iCloud, and are never written back to Eventernote.

**Keep the ones that matter in front of you.** Any event can be favorited from its detail sheet, separately from the three tracking fields — it says "keep this where I can see it", not "I have a ticket". Favorites gather on the Me tab with your library's own statistics.

**Follow performers and see what they have coming.** Follow anyone from their page, and the Following tab reads each of their Eventernote listings and shows every upcoming date they are billed on, grouped by month and filterable to one person. Nothing there is in your library until you put it there. Following is your own record, kept beside your library — it is not the favorite list your Eventernote account holds, which this app only ever reads.

**Put your library in your calendar.** With calendar sync on, every event in your library is mirrored into a calendar of the app's own, past and upcoming, so your events show up wherever you already look for your day. It is one-way: the app writes that calendar and reads nothing else of yours.

**Work offline.** Your library and everything you have annotated is kept in a local file and stays fully usable with no network and no active iCloud connection. Search and importing need the network; what you have already saved does not.

**Sync across your devices.** Personal annotations, favorites, follows, and the event snapshots behind them move between your iPhone and iPad through your own private iCloud storage. There is no app-operated backend and no account to create.

**Import a public Eventernote profile — optionally.** Enter an Eventernote username and the app imports that profile's public attendance history and its favorited performers. This is a one-way, read-only import of public data: no password is collected, no session cookie is extracted, and entering a username does **not** authenticate you or prove you own the account. The interface presents this as importing a public profile, not as signing in.

**Act on Eventernote where Eventernote belongs.** Anything that modifies your Eventernote account happens on the official website via an "Open in Eventernote" action, where you authenticate directly. On return, the app can refresh the imported public state — it never assumes a website visit means the action succeeded.

## How your data is treated

The design is built around one rule: **imports serve your records; they never overwrite them.**

- A refresh never touches your notes, interest, ticket status, or recorded attendance.
- Imported participation is stored separately from your own annotations, so an event can simultaneously read "Ticket purchased" (yours) and "Participation listed on Eventernote" (imported).
- Copying imported participation into your own tracking is always an explicit action, and later imports won't silently undo it.
- Records are never deleted just because they're missing from one response. A failed request, incomplete pagination, or a changed page layout looks the same as a genuine cancellation — only a successful, complete refresh of the relevant scope can establish that a participation is no longer listed, and even then the event and your annotations are preserved.
- On network or parsing failure, the last successful snapshot is retained and the app shows you when it last refreshed successfully.
- Repeated imports are idempotent: events and participation relationships are keyed by stable Eventernote event IDs, not by titles or dates, so re-importing produces no duplicates.
- iCloud conflict handling merges record by record rather than file by file: an edit made on one device never erases an unrelated edit made on another, and removing an event travels to your other devices instead of being undone by the next merge.

**Removing and re-importing.** A removal settles what this app holds — it travels to your other devices and stays gone there. It does not reach Eventernote, and it was never meant to: your account's record is what the import reads from, so asking Eventernote again is how you get back something you took out and then wanted. An import restores an event your linked account still lists and re-follows a performer it still favorites. What the account never carried — an event saved from Search, a performer followed here alone — stays gone for good, because nothing will bring it back. Dropping something permanently means dropping it on Eventernote too.

## Refreshing

| Trigger | Behavior | Built |
| --- | --- | --- |
| Manual refresh | Pull to refresh, or the Refresh button beside the linked account: imports immediately and reports the result | Yes |
| Launch / foreground | Refreshes if the last successful import is sufficiently old | Not yet |
| Return from the official website | Attempts a refresh when a public profile is associated | Not yet |
| Background opportunity | Refreshes when iOS grants execution time | Not yet |

Refreshing is entirely on your command today, and reports what it actually did. iOS background execution is opportunistic in any case, so the app will make no promise of exact hourly or daily refresh: manual and foreground refresh are meant to be the dependable paths, and background refresh an enhancement. The planned shape for the automatic ones is bounded, backed-off requests with upcoming events refreshed more often than history, and periodic full reconciliation to catch older changes.

## Privacy

- Personal annotations live on your device and in your private iCloud storage. No app-operated backend.
- Associating a public profile is clearly labeled as unverified — it does not confirm account ownership.
- Your notes are always visually distinct from publicly imported participation.
- You can remove an associated profile and keep all of your personal records.
- Deleting imported data and deleting personal annotations are separate controls.
- Calendar sync writes a calendar of the app's own and reads nothing else from yours; turning it off leaves your calendar alone.
- iCloud sync is a per-device switch: turning it off on your phone does not turn it off on your iPad.
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

All user-facing text — screen labels, the interest/ticket/attendance values, refresh status, and error messages — is defined as localizable strings rather than hard-coded, so dates, times, and numbers are already formatted for your locale. **The translations themselves are not written yet:** today every language falls back to English. The app follows your system language and region settings, and you can override it per-app in iOS Settings without changing your system language.

Event content is never translated. Event titles, venue names, and performer names come from Eventernote as published (predominantly Japanese) and are displayed verbatim in every language, so they always match the official page. Your own notes are likewise stored and shown exactly as you typed them, in whatever language you use.

## Scope of the first release

Native browsing, search, and event detail; the four local tracking fields; favorites and followed performers; offline access; iCloud sync; calendar mirroring; one optional public username import; manual and on-activation refresh; website links for account actions; honest refresh status and error handling; and a fully localized interface in English, Japanese, Simplified Chinese, and Traditional Chinese.

Deliberately deferred: background refresh, exact-time scheduling, an app-operated backend, writing to Eventernote from the app, importing private Eventernote notes, and managing multiple profiles.

## A note on the integration

Eventernote publishes no documented API, access tokens, or OAuth registration that this project has found. Public data retrieval is therefore isolated behind an adapter so that website changes break imports without endangering your stored records or the native screens. The reviewed terms of service do not expressly address third-party clients but do contain broader prohibitions; this repository does not assert permission or offer a legal conclusion, and a public release would need to account for the current terms and any guidance from the operator.

## Icon

The icon is an Icon Composer document at [`Eventrail/AppIcon.icon`](Eventrail/AppIcon.icon) — a ticket whose cutout traces an E through three event stops, over the app's blue. [`Design/AppIcon.svg`](Design/AppIcon.svg) is the full 1024pt source drawing it was cut from, and `Design/AppIcon.png` is the rendering shown above.

## License

[MIT](LICENSE). The license covers this app's own source; it says nothing about
Eventernote's content, which remains the site's — see the note on the
integration above.
