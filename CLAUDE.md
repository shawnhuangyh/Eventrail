# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Eventrail is an iPhone/iPad SwiftUI app (single target `Eventrail`, bundle id `com.shawnhuang.Eventrail`). [MyApp.swift](Eventrail/MyApp.swift) declares the `@main` `App` and shows [RootView.swift](Eventrail/Views/RootView.swift), a three-tab `TabView` (My Events / Me / Search, the last with `role: .search`). There is no test target, no package manifest, and no dependencies.

Source is grouped as:

- [Eventrail/Model/](Eventrail/Model/) — `Event`, the reader's private `Tracking` record, and `EventStore`, an `@Observable` in-memory store passed down through `.environment`. Persistence is deliberately absent until the SwiftData/CloudKit schema is settled; [SampleData.swift](Eventrail/Model/SampleData.swift) stands in for the Eventernote import adapter.
- [Eventrail/Views/](Eventrail/Views/) — one file per screen, plus [Components/](Eventrail/Views/Components/) for the shared glass panel, wash background, and small repeated parts.

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
