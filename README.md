# Eventrail

A native SwiftUI companion app for browsing [Eventernote](https://www.eventernote.com/) events and keeping your own record of what you're interested in, what you have tickets for, and what you actually attended — stored on your device and synchronized through your private iCloud account.

> **Status: early development.** The architecture and behavior described here come from the project's design proposal; the repository currently contains the app skeleton. The Eventernote import layer still requires a feasibility prototype before the full feature set can be committed to. This is not a completed or tested integration, and it is not affiliated with or endorsed by Eventernote.

## What it does

**Browse events natively.** Event lists, search, and detail screens rendered as a real iOS/macOS/visionOS app rather than a wrapped web page, populated from publicly accessible Eventernote information. Every event links back to its original page.

**Track events on your own terms.** For any event you can independently record:

| Field | Values |
| --- | --- |
| Interest | Interested / planning to attend |
| Ticket status | Not purchased / purchased |
| Attendance | Unrecorded / attended |
| Notes | Free-form personal text |

These fields belong to you and to this app. They live in the local database, sync through iCloud, and are never written back to Eventernote.

**Work offline.** Saved events and annotations are cached locally and remain fully usable with no network and no active iCloud connection. Syncing resumes when connectivity returns.

**Sync across your devices.** Personal annotations, profile settings, and suitable event snapshots move between your iPhone, iPad, Mac, and Vision Pro through your own private iCloud storage. There is no app-operated backend and no account to create.

**Import a public Eventernote profile — optionally.** Enter an Eventernote username and the app imports that profile's public upcoming and historical participation records. This is a one-way, read-only import of public data: no password is collected, no session cookie is extracted, and entering a username does **not** authenticate you or prove you own the account. The interface presents this as importing a public profile, not as signing in.

**Act on Eventernote where Eventernote belongs.** Anything that modifies your Eventernote account happens on the official website via an "Open in Eventernote" action, where you authenticate directly. On return, the app can refresh the imported public state — it never assumes a website visit means the action succeeded.

## How your data is treated

The design is built around one rule: **imports serve your records; they never overwrite them.**

- A refresh never touches your notes, interest, ticket status, or recorded attendance.
- Imported participation is stored separately from your own annotations, so an event can simultaneously read "Ticket purchased" (yours) and "Participation listed on Eventernote" (imported).
- Copying imported participation into your own tracking is always an explicit action, and later imports won't silently undo it.
- Records are never deleted just because they're missing from one response. A failed request, incomplete pagination, or a changed page layout looks the same as a genuine cancellation — only a successful, complete refresh of the relevant scope can establish that a participation is no longer listed, and even then the event and your annotations are preserved.
- On network or parsing failure, the last successful snapshot is retained and the app shows you when it last refreshed successfully.
- Repeated imports are idempotent: events and participation relationships are keyed by stable Eventernote event IDs, not by titles or dates, so re-importing produces no duplicates.
- iCloud conflict handling merges independent fields, preserves both versions of conflicting note text rather than discarding one, and prevents an older import snapshot from replacing a newer one.

## Refreshing

| Trigger | Behavior |
| --- | --- |
| Manual refresh | Attempts an import immediately and reports the result |
| Launch / foreground | Refreshes if the last successful import is sufficiently old |
| Return from the official website | Attempts a refresh when a public profile is associated |
| Background opportunity | Refreshes when iOS grants execution time |

iOS background execution is opportunistic, so the app makes no promise of exact hourly or daily refresh. Manual and foreground refresh are the dependable paths; background refresh is an enhancement. Requests are cached, bounded, and backed off on retry, with upcoming events refreshed more often than history and periodic full reconciliation to catch older changes.

## Privacy

- Personal annotations live on your device and in your private iCloud storage. No app-operated backend.
- Associating a public profile is clearly labeled as unverified — it does not confirm account ownership.
- Your notes are always visually distinct from publicly imported participation.
- You can remove an associated profile and keep all of your personal records.
- Deleting imported data and deleting personal annotations are separate controls.
- Diagnostics exclude personal notes and any authentication material.

## Platforms

iOS, macOS, and visionOS from a single SwiftUI target (deployment target 26.0), built with Xcode. Persistence is planned on SwiftData or Core Data with CloudKit, to be chosen after validating schema constraints, conflict behavior, and migration requirements.

## Languages

The interface is localized into four languages:

| Language | Locale code |
| --- | --- |
| English | `en` |
| Japanese | `ja` |
| Simplified Chinese | `zh-Hans` |
| Traditional Chinese | `zh-Hant` |

The app follows your system language and region settings, and falls back to English for any language not on this list. You can override it per-app in iOS Settings or macOS System Settings without changing your system language.

All user-facing text — screen labels, the interest/ticket/attendance values, refresh status, and error messages — is defined as localizable strings in a String Catalog rather than hard-coded, so dates, times, and numbers are formatted for your locale too.

Event content itself is not translated. Event titles, venue names, and performer names come from Eventernote as published (predominantly Japanese) and are displayed verbatim in every language, so they always match the official page. Your own notes are likewise stored and shown exactly as you typed them, in whatever language you use.

## Scope of the first release

Native browsing, search, and event detail; the four local tracking fields; offline access; iCloud sync; one optional public username import; manual and on-activation refresh; website links for account actions; honest refresh status and error handling; and a fully localized interface in English, Japanese, Simplified Chinese, and Traditional Chinese.

Deliberately deferred: exact-time scheduling, an app-operated backend, writing to Eventernote from the app, importing private Eventernote notes, and managing multiple profiles.

## A note on the integration

Eventernote publishes no documented API, access tokens, or OAuth registration that this project has found. Public data retrieval is therefore isolated behind an adapter so that website changes break imports without endangering your stored records or the native screens. The reviewed terms of service do not expressly address third-party clients but do contain broader prohibitions; this repository does not assert permission or offer a legal conclusion, and a public release would need to account for the current terms and any guidance from the operator.

## License

Not yet specified.
