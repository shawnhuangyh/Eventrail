# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Eventrail is an iPhone/iPad SwiftUI app (single target `Eventrail`, bundle id `com.shawnhuang.Eventrail`). [MyApp.swift](Eventrail/MyApp.swift) declares the `@main` `App` and shows [RootView.swift](Eventrail/Views/RootView.swift), a four-tab `TabView` (My Events / Following / Me / Search, the last with `role: .search`, which iOS 26 detaches into its own button beside the bar). There is no test target, no package manifest, and no dependencies.

Source is grouped as:

- [Eventrail/Model/](Eventrail/Model/) — `Event`, the reader's private `Tracking` record, `Feed` (one page of an Eventernote listing at a time), and `EventStore`, an `@Observable` store passed down through `.environment`. `FollowedDates` is the second thing in that environment: the upcoming dates read from each followed performer's listing, held for the life of the launch so the Following tab and the Me card share one read instead of asking twice. [PreviewData.swift](Eventrail/Model/PreviewData.swift) is fixtures for `#Preview` and the playground only; the running app starts with an empty library.
- [Eventrail/Services/](Eventrail/Services/) — the Eventernote import adapter. See below.
- [Eventrail/Views/](Eventrail/Views/) — one file per screen, plus [Components/](Eventrail/Views/Components/) for the shared glass panel, wash background, and small repeated parts.

## The Eventernote import

**The linked account's record on Eventernote is the source of truth for what the reader has been to and who they care about.** That is the premise the whole app is built on: the library is the account's attendance history as the site publishes it, and `follows` is the account's favourites. So an import is always allowed to restore what the site still lists, and it never needs the reader's permission to do it — asking Eventernote again is how the reader gets back something they took out and then wanted.

What the reader owns is the layer on top: tracking, notes, favourites, and which of their own devices hold what. A removal in the app settles *that* layer and syncs across their devices; it does not reach the account and has never claimed to. Dropping something for good means dropping it on Eventernote. The exception is what the account never carried — an event saved from Search, a performer followed in Eventrail alone — where a removal is final because nothing will import it back.

Eventernote publishes no API, so [EventernoteClient.swift](Eventrail/Services/EventernoteClient.swift) GETs the site's public pages and [EventernotePages.swift](Eventrail/Services/EventernotePages.swift) reads them with [HTMLCursor.swift](Eventrail/Services/HTMLCursor.swift), a marker-based scanner (no HTML parser, no dependency). Things worth knowing before changing any of it:

- **The User-Agent must contain `iPhone`.** The site serves a desktop template otherwise, and every selector here is from the smartphone template. This is the single most breakable assumption in the adapter.
- Pages read: `/events/search`, `/actors/search`, `/actors/{slug}/{id}/events`, `/events/{id}`, `/places/{id}`. `robots.txt` disallows only `/users/notice` and `/users/timeline`. Everything is a GET — nothing is ever written back to Eventernote, and no account is involved.
- Performer slugs come back already percent-encoded and are passed through `percentEncodedPath`; re-encoding them breaks names containing `!`, `(` or spaces.
- A performer's own listing (`/actors/{slug}/{id}/events`) is ordered from the furthest published date backwards, so every upcoming appearance sits at the front of it. `PerformerView` relies on that: it pages until the first past row appears, which is what makes its Upcoming section — and the count over it — the whole of it rather than whatever landed on page one.
- **Eventernote publishes no performer portrait.** The `gb_blur_title` cover block in the shared template is only ever filled on a member's own page; every actor page sampled across the id range leaves it out, and the actor listing and search rows carry no image either. So no performer is ever shown with a picture — not on `PerformerView`, not in an event's Performers card, not in a Search result row. An event flyer is artwork for the event rather than a likeness of the performer, so it is not stood in for one either, and an empty placeholder circle is just furniture. Don't go looking for a portrait endpoint again. (The avatar on the Me tab is a different thing: a *member* page really does publish one.)
- An event's billing publishes names only, with no link to a profile, so opening a performer from there searches for the name and takes an exact match. The search matches on the kana reading too, so a near miss is a different person.
- Search rows carry only day, title, venue, billing and a thumbnail. Times, head count and the venue address come from the event's own page, so `Event` marks that with `isDetailed` and its time fields are optional. **Do not make them non-optional** — Eventernote routinely announces an event months before it publishes a start time.
- The count beside a name in performer search is the site's *fan* count, not an event count.
- Every accessor is failable by design: a changed template yields a missing field or a dropped row, never wrong data.

## Persistence and sync

`LibraryArchive` is the single value holding everything the reader owns. It is written to a plain JSON file in Application Support, deliberately *not* SwiftData — that schema is still unsettled, and this keeps what the reader adds across launches without committing to a store. `EventStore` holds one `archive` and derives `library` from it, so a merge from another device is one reviewable operation.

iCloud sync goes through [CloudSync.swift](Eventrail/Services/CloudSync.swift) on `NSUbiquitousKeyValueStore`. Things that matter:

- **Every record the reader owns is a `Stamped<Value>`** — the value plus when it changed. Merges are last-writer-wins *per record*, never per file, because a whole-blob overwrite would silently erase a note typed on the other device. `LibraryArchive.merging(_:)` is where this lives; the merge is symmetric.
- Following a performer is the reader's record too, so `follows` is stamped and tombstoned like the rest. It is keyed by Eventernote's actor id and is still *not* the favourite list the reader's Eventernote account holds — that one stays read-only here. An import brings the second in line with the first (`EventStore.adoptFollows`) and only ever adds: anyone the account still favourites is followed here, tombstone or not — asking Eventernote again is the reader's way back to somebody they unfollowed and then wanted again, and unfollowing for good means unfavouriting them on the site too. A performer *dropped* from the favourites on the site is still never unfollowed here, because that would also reach everyone followed in Eventrail alone. The key is optional on `LibraryArchive` because the synthesized decoder does not fall back to a property's default, so a new non-optional key would read every existing file as corrupt.
- `followedPerformers` sits beside `follows`, keyed the same way: who each followed actor id *is*. Eventernote's facts rather than the reader's, so it carries no timestamp and merges like `events`; it is pruned once the follow is gone. Without it the Following tab could neither name a performer nor address their listing. A follow recorded before this existed has no profile and is skipped rather than shown as a nameless row — an import backfills it if the account favourites them.
- **Removals are tombstones** (`membership[id] = Stamped(false)`), not deletions. Dropping the key instead would let the next merge resurrect the event. Tombstones are pruned after 180 days.
- **A tombstone answers for the reader's devices, not for Eventernote** — the premise at the top of *The Eventernote import*. It stops a *merge* from handing a removed record back; it does not stop an *import*. `EventStore.adopt` re-adds an event the linked account still lists and `adoptFollows` re-follows a performer it still favourites, and re-adding by hand (`toggleLibraryMembership`, following from a performer's page) has always worked the same way.
- Event facts are not the reader's, so they need no timestamp: the more complete import (`isDetailed`) wins.
- The payload is zlib-compressed before it goes to iCloud. Measured on real data: ~646 bytes/event of JSON compresses to ~134, so the 900 KB guard under Apple's 1 MB quota fits roughly 6,700 events. `CloudSync.save` refuses to write past the guard rather than letting the store drop it silently, and the Me screen shows a meter past 80%.
- `iCloudSyncEnabled` is a **per-device** preference in `UserDefaults` and deliberately does not sync — turning it off on a phone must not turn it off on the iPad.
- `LibraryFile.load()` falls back to `LegacyArchive` for files written before records carried timestamps. Don't remove that until you're sure no device holds a pre-sync file.

**Capability:** sync needs `com.apple.developer.ubiquity-kvstore-identifier`, which lives in [Eventrail.entitlements](Eventrail.entitlements) at the repo root (outside the synchronized group, so it is not bundled as a resource) and is wired via `CODE_SIGN_ENTITLEMENTS` in both configurations. Simulator builds sign locally and work as-is; a **device build needs iCloud enabled on the App ID in the developer portal**, otherwise signing fails.

The UI comes from the Claude Design canvas "Eventernote Mobile App Design" (`Eventrail.dc.html`), which specifies a Liquid Glass treatment in light and dark. All glass goes through `glassBackground(in:interactive:)` in [WashBackground.swift](Eventrail/Views/Components/WashBackground.swift) — that one helper also holds a `#if os(visionOS)` material fallback, kept from when the target still built for visionOS. Palette colours are colorsets in `Assets.xcassets` generated from the design's oklch values, with light and dark variants.

## Build and run

```bash
# Build for the simulator
xcodebuild -scheme Eventrail -destination 'platform=iOS Simulator,name=iPhone 17' build

# Clean build folder when the project file or build settings change
xcodebuild -scheme Eventrail clean
```

`xcodebuild test` will fail until a test target exists; add one in Xcode (File > New > Target > Unit Testing Bundle) before writing tests, then run a single test with
`xcodebuild test -scheme Eventrail -destination '<dest>' -only-testing:EventrailTests/SomeTests/testSomething`.

## Commit messages

Every commit message subject must follow:

```text
<type>: <concise imperative summary>
```

Examples:

```text
feat: add provider-based custom filters
fix: audit Google Drive restore downloads
docs: document production deployment
test: cover stale provider cache fallback
refactor: isolate subscription metadata handling
chore: update development dependencies
```

## Project structure conventions

- The `Eventrail` group is a **PBXFileSystemSynchronizedRootGroup** (`objectVersion = 90`). New `.swift` files dropped anywhere under [Eventrail/](Eventrail/) are picked up automatically — do **not** hand-edit `project.pbxproj` to register sources. Only build settings, targets, and capabilities need project-file edits.
- `Eventrail.xcodeproj/xcuserdata/` is user state and is checked in here by accident of the initial commit; avoid touching it.

## Platform and language constraints

- `SUPPORTED_PLATFORMS = iphoneos iphonesimulator` with `SDKROOT = auto`, `SUPPORTS_MACCATALYST = NO`, and `TARGETED_DEVICE_FAMILY = 1,2` (iPhone, iPad). macOS and visionOS were dropped deliberately; `platform=macOS` and visionOS destinations will not resolve.
- Deployment target is iOS **26.0** at both the project and target level, so recent SwiftUI APIs are available without availability checks.
- Some `#if os(visionOS)` branches survive from when the target built for visionOS (`glassBackground` in [WashBackground.swift](Eventrail/Views/Components/WashBackground.swift), `tabViewSearchActivation` in [RootView.swift](Eventrail/Views/RootView.swift)). They are unreachable now but make re-adding the platform cheap — remove them only on purpose.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — types are `@MainActor` by default. Mark work that must leave the main actor explicitly (`nonisolated`, `@concurrent`, actors). `SWIFT_APPROACHABLE_CONCURRENCY = YES`, Swift language mode 5.
- `LOCALIZATION_PREFERS_STRING_CATALOGS` / `SWIFT_EMIT_LOC_STRINGS` are on and known regions are en, ja, zh-Hans, zh-Hant — user-facing strings should be localizable `LocalizedStringKey`s, not raw `String`s.

## Sandbox capabilities

App Sandbox is enabled; the entitlements the target already grants are the practical limit on what features can be built without a project-file change:

- Allowed: calendars (`ENABLE_RESOURCE_ACCESS_CALENDARS`), location, outgoing network, read-only user-selected files, app groups.
- Denied: incoming network, camera, microphone, contacts, Bluetooth, USB, printing.

If a feature needs a capability not on the allowed list, flag it — it requires flipping the corresponding `ENABLE_*` build setting in both Debug and Release configurations.

## Playgrounds

[RootView.swift](Eventrail/Views/RootView.swift) imports `Playgrounds` and defines a `#Playground` block alongside the `#Preview`. These are inline-execution scratch areas for Xcode; they are not tests and are not run by `xcodebuild`.
