# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Eventrail is an iPhone/iPad SwiftUI app (target `Eventrail`, bundle id `moe.shawn.Eventrail`), run on the Mac as the same app through Mac Catalyst (*The Mac app*), with `EventrailTests`, `EventrailWidgets` (`moe.shawn.Eventrail.Widgets`: the Live Activity and the widgets) and `EventrailWatch` (`moe.shawn.Eventrail.watchkitapp`, embedded in the app's `Watch` folder). [MyApp.swift](Eventrail/MyApp.swift) is the `@main` `App`; [RootView.swift](Eventrail/Views/RootView.swift) is a four-tab `TabView` (My Events / Following / Me / Search, the last `role: .search`). No package manifest, no dependencies.

- [Eventrail/Model/](Eventrail/Model/) — `Event`; `Tracking`, the reader's record (`LotteryEntry` in `Lottery`, `LotteryList`); the SwiftData models (`LibraryEntry`, `LibraryEvent`, `LibraryLottery`, `FollowingReadMark`, `FollowedPerformer`, `LibrarySettings`, read-once `LibraryMembership`) and `LibraryQueries`; `LibraryArchive`; `Feed`; `Region`; `PassportStats`; `OnThisDay`; `SameDay`; `Money` (`Currencies`, `CurrencyRates`); and `EventStore`, the `@Observable` every write goes through, handed down with the container by `.library(store)`. `FollowedDates` and `VenueRegions` ride in the environment beside it, both read from Eventernote and cached on the device. [PreviewData.swift](Eventrail/Model/PreviewData.swift) is for previews only; the app starts empty.
- [Eventrail/Services/](Eventrail/Services/) — `EventernoteClient`, `EventernotePages`, `HTMLCursor`; `VenuePlaces`, `JapanAddresses`, `VenueBuildings`, `VenueRegions`; `PageReads`; `AccountEvents`; `KeptFile`; `LibraryDatabase`, `LegacyCloudZone`; `CalendarSync`; `LibraryBackup`; `EventActivities`; `WatchLink`; `WidgetLink`; `LotteryReminders`; `SpotlightIndex`; `ExchangeRates`; `TicketScanner`; `ServiceRequest` (the one GET-and-decode for the GSI register, OpenStreetMap and Frankfurter, its failure naming the host); `TravelTimes`.
- [Eventrail/Intents/](Eventrail/Intents/) — `EventEntity`, `PerformerEntity`, `VenueEntity`, `OpenIntents`, `IntentOpens`.
- [Eventrail/Views/](Eventrail/Views/) — one file per screen; [Components/](Eventrail/Views/Components/) holds the shared parts: `Typography`, `Pieces`, `ListControls` (`ListMenu`, the capsule over a list's foot holding its filter and sort; `LibraryHalfPicker`; `PencilToolbar`; the selection bar), `SettingRow`, `CurrencyChoices`, `PhotoSaving`, `BackupRestore`, `RefreshNotices`, `Fold`, `EventPane`, `OnTheMac`, `ListingPage` (what `PerformerView` and `VenueView` share), `AppCommands`, `CloseButton`, `RowReadButton` and more. **A row two screens already draw belongs here, not in a third copy.**
- [EventrailWidgets/](EventrailWidgets/) — `EventLiveActivity`, `NextEventWidget`, `LotteriesWidget`, `OnThisDayWidget`, `WidgetParts`, `WidgetSamples`, its own string and asset catalogs. [EventrailWatch/](EventrailWatch/) — `MyEventsView`, `EventPagesView`, `EventMoment`, `WatchLibraryStore`, `Flyer`, its own catalog and icon copy.
- [Shared/](Shared/) — compiled into all three targets: `EventActivityAttributes`, `EventActivityStage` (the stage rules, colours, `assumedLength` and headlines, so the watch keeps no copy), `WatchLibrary`, `WidgetLibrary`, `CalendarDay` (a day with no clock), `Gregorian`, `Thumbnail`, `ClockText`. `EventActivity.swift` and `WidgetLibrary.swift` are excepted from the watch target.

### The screens

- **My Events** (`EventsView`), the library:
  - Upcoming/Past is `LibraryHalfPicker` at the head of the list — every screen keeps the choice of which list it is at its head; the grouping is in the capsule (`EventListMenu`, Sort only); the bar keeps only the pencil. Favorite Events is built from the same parts.
  - An event ahead counts down in whole days between written dates (`DaysAway`, `Event.daysAway`), the last week in the tint — on `LibraryRow` only: counting to a date nobody kept would be the app deciding it mattered. Screens counting from today read `EnvironmentValues.today`, moved on at midnight and on `significantTimeChangeNotification`.
  - Upcoming rows carry a red clash mark (`LibraryRow.clash`). An event ahead is read or unread off the **same** `FollowingReadMark` Following keeps (`UnreadTag`); a past event carries neither.
  - Picking (`SelectionToolbar`): Select All top-left; `MarkReadButton` on Upcoming, `MarkAttendedButton` on Past (`EventStore.recordTickets(for:)`, one way only).
  - Past opens on a `TicketReviewPrompt` row when past events have arrived with nothing on their Ticket Details (`awaitingTickets(_:since:)`, `awaitsTicket`) since the per-device `ticketsReviewed`. `TicketReviewView` lists them by month with **nothing picked to begin with** — a pick is the reader saying they were there; its checkmark records tickets and counts the list as gone through. Presented with `sheet(item:)`: `sheet(isPresented:)` opened on a stale empty copy.
  - Rows swipe trailing to Remove, asked first; the swipe's button has no destructive role, which would remove the row before the answer.
- **Following** (`FollowingView`): every upcoming date of every followed performer, read from their listings, not the library.
  - Chips filter by person; the capsule holds Date (All, or the next 7 days, 30 days, 3 months or 6 months — `FollowingFilter.Window`) and Area (several at once, the menu kept open). A date range and "this week" were tried and taken out. While held to an area, halls go on being placed for as long as each run gets somewhere.
  - **An event leaves once its published end has passed (`Event.hasEnded`), only where its hall's clock is known** (`FollowedDates.hallZone`): a listing row is read on Tokyo time. Known from `VenueRegions` placing the hall in Japan, the library's retimed copy, `settleClocks(for:)`, or a `VenuePlaces` placing of that hall name (`timeZone(ofHallNamed:)`; two clocks for one name answer nothing). Such a row is re-read on its clock (`Event.published(in:)`, `FollowedDates.onHallClock`) before it is shown or judged; the cache keeps it as printed. Otherwise it stays until its day is over everywhere (`Event.isUpcomingAnywhere`, GMT−12); with no published end, until midnight.
  - Doors, start and end are read in running order, a time earlier than the one before it being the next morning (`Event.inOrder`: 開場 23:30 開演 00:30 終演 05:00).
  - A finished event is dropped from the cache (`dropFinished()`) before any read, and checked again in `events(for:)`, which a wake set for the soonest end redraws.
  - **Read like a mailbox**: a New or Updated tag after the billing caption's names until the date is opened, swiped or marked in a batch; the envelope shows only the unread; the count is in the subtitle and the tab's badge (`RootView.unreadFollowing`, over everyone followed).
  - A `FollowingReadMark` keeps a fingerprint of the row as read (`Event.listingFingerprint`: title, hall, day, times as printed, bill — not head count or flyer), so a row that comes back changed is unread again. **Its own record, never on the event's entry or facts**: on the event's row, a device behind on a removal put the event back just by opening it. Marking unread and Delete All write one with no fingerprint (a tombstone). Pruned by event. Clear Cache leaves them.
  - A `List`; the billing caption pushes through the stack's `path`, since a `NavigationLink` would take the whole row over.
- **Me** (`MeView`): the account, On This Day (left out on a day with none), the Passport, lotteries (three rows), favourites and followed performers (five each), each with See All.
  - **Not on Your Account** (`NotOnAccountView`), a row on the account card only while it holds something: kept events the account did not list (*The Eventernote import*).
  - **Settings** (`SettingsView`): General (Locale → `LocaleSettingsView`: App Language, the 概要 translation language, Default Currency — per device, `Currencies.storageKey`, yen; then Appearance, Time Zone, iCloud Sync, Calendar Sync, Lottery Reminders), Backup, Advanced (Venue Locations → `VenueLocationsView`; Clear Cache), About, and Delete All alone under Danger Zone.
  - `Appearance` is applied by setting `overrideUserInterfaceStyle` on every window and presented controller (`Appearance.apply()`). Not `preferredColorScheme` (Light back to nil stayed light), not an `onChange` in `MyApp` (it fired once).
  - **A Settings row is an icon, a name and a control**, with a second line only for a status to act on or wait for. No explanations under switches, footnotes or how-it-works cards — the Welcome screen's panels are the one place switches are explained. Two exceptions: Default Currency's one line (on Shawn's word: each ticket keeps its own currency; this is what the Passport adds up in and a new cost starts in), and `VenueLocationsView`, which explains its switch, lists the three sources in the order asked with how many halls each placed (`VenuePlaces.breakdown(for:)`), then Refine with OpenStreetMap (`preciseVenuesEnabled`, off by default, governing the third source only), the refresh and Refresh All Venues (without which the refresh skips halls Maps placed).
- **On This Day** (`OnThisDayView`): events attended on today's date in earlier years (`OnThisDay`: `Event.localDay`'s month and day, a ticket held). A leap day comes round on the 28th. Gregorian, library only, latest first. The Me card draws plain rows, not the design's large poster.
- **Lotteries** (`LotteriesView`, `Eventrail v4.dc.html` §8a): every lottery round (`LotteryEntry.isLottery`) for a kept event ahead, read off `Tracking.lotteries`.
  - The tile (`LotteryDayTile`): the tint once the results day has come unanswered, green won, grey lost, a dashed DAY ? with no day.
  - The Me card shows the next **three** awaiting (`LotteryList.next`); its See All stands wherever any round exists, past included (`LotteryList(includingPast: true)`), or Show Past was unreachable.
  - Awaiting · N / Decided · N at the head; a sort capsule (Results Day, Event Date).
  - **On Decided alone the capsule holds one switch, Show Past** (off on open, not remembered) and nothing else — a Date submenu was taken out, on Shawn's word. Past rounds read latest first (`LotteryRow.latestFirst(by:)`), a pending one as No Result. **Past rounds are only looked back on** (Shawn): no menu, no swipe, a tap opens the event; never under Awaiting.
  - **A result is given from the list** — the tile's menu (Pending, Won per choice, Lost, Edit Entry) or swipes (Won leading, asking which choice; Lost trailing) — written at once through `Tracking.givingResult(_:toLottery:)`, keeping the sheet's rules: no result before the results day (`canBeDrawn`), and asking to clear a seat or cost left without a ticket (`leavesSeatOrCostBehind(since:)`). The menu lies over the card's button on a clear frame found by an anchor preference (`TileSpot`).
  - **The design file is over the 256 KiB the design tool returns**; read it whole in Chrome through the page's own `GetFile` call, or the words are guesses.
- **Search** (`SearchView`): Eventernote's event and performer searches.
  - iPad: `searchPresentationToolbarBehavior(.avoidHidingContent)` — hiding the title left the large title half off screen (iPadOS 27.1). Not an inline title (Shawn).
  - Results carry a capsule over the search field (`.safeAreaInset`; a `.bottomBar` item isn't drawn while the tab bar is): Filter (Date, Area) and Sort (`SearchOrder`), each choice a level down. **Every filter submenu, here and on Following, puts the choice that holds nothing back (All, Anywhere) alone above a divider.** No date range (tried, taken out).
  - `SearchFilter`: the area (`area_id`, one at a time; 海外 offered) and the order go to the site; ahead/past is held in the app. **The order is `sort=event_date&order=ASC|DESC`, not `sort_by`**, which the site ignores. Pages wholly before the held-back run are skipped by halving (`SearchView.firstPage`), reading stops at the first row past it, and five pages in a row that add nothing stop on Keep Looking.
  - Before anything is typed: **Today** — the search given the site's day as 開催日 (`EventernoteClient.events(on:areaID:page:)`, area-filtered; not the 今日開催 tab, which ignores `area_id`; the day is `Event.siteDay`) — and **Just Added** (`/events/?type=2`: a hundred rows, one page, no area, so Date instead), each a `SiteListingView` read like a performer page from `ListingCache` (`site/today/<area_id>` carrying its day, so yesterday's copy never shows; `site/new`), Refresh in a ⋯ menu, no pull, no read state.
- **Performer and hall pages** (`PerformerView`, `VenueView`, and `ListingHalfView` behind See All): one capsule at the leading edge of a bottom bar (Follow or Directions, Share, ⋯ with Open in Eventernote and Refresh); the tab bar stands down.
- **The event sheet** (`EventDetailView`, `Eventrail v3.dc.html`): the flyer small beside the title — a tap opens Quick Look, a long press offers Share and Save to Photos, both handed a file named for the event (`ImageCache.file(for:named:checkedSince:)`); a timeline card (days off, or Attended with a ticket / Ended without; the clock's offset and a Venue/Local switch; Doors/Start/End drawn as the Live Activity draws them, all three, `stopsRow`; redrawn each second on the day through `EventProgress`); for a kept event, ticket and seat tiles opening `TicketDetailsView` and the Ticket Stub row where there's a ticket; then 概要, billing, hall, links. Actions in a leading bottom-bar group: add/remove, share, and a `.menuOrder(.fixed)` menu ending in Remove Event with its trash drawn red (a menu tints every icon); with a ticket, a Live Activity clock — plain off, filled green on, since a lone toolbar item draws no background.
- **Ticket Details** (`TicketDetailsView`): the rounds tried for — cards, a trailing swipe to delete, opening `LotteryEntryView`, which edits a copy only its checkmark puts back (its own back button asks first wherever backing out throws something away) — then seat, cost and note. No Purchased or seat-class chips: both are read from the rounds. The currency menu leads with Default and the hall's own (`Currencies.atVenue(of:)`) and shows the default-currency equivalent.
  - **Unlike every other screen (Shawn), it is not written as answered**: it holds a copy; X leaves the record, asking if anything changed; the checkmark (`role: .confirm`) writes only what changed on it over the record as it now stands (`Tracking.applying(changesFrom:to:)`); it can't be pulled down while it holds a change or has an entry open.
- **`WelcomeView`**: once per device on first launch — where records come from (an account or a backup), sync and the calendar. Both switches start off; each is Settings' own row.

## The Eventernote import

**The linked account on Eventernote is the source of truth for what the reader went to and who they follow.** An import the reader asked for may always restore what the site still lists, without asking; the app's own periodic read only adds. The reader owns the layer on top (tracking, notes, favourites): a removal settles that layer and syncs, never reaching the account. What the account never carried (saved from Search, followed in Eventrail alone) is removed for good.

No API: [EventernoteClient.swift](Eventrail/Services/EventernoteClient.swift) GETs public pages and [EventernotePages.swift](Eventrail/Services/EventernotePages.swift) reads them with [HTMLCursor.swift](Eventrail/Services/HTMLCursor.swift), a `memmem` marker scanner (~30× faster than `range(of:)`).

- **The User-Agent must contain `iPhone`** — otherwise the site serves the desktop template, and every selector is the smartphone one's. The single most breakable assumption.
- Pages read: `/events/search`, `/events/?type=2`, `/actors/search`, `/actors/{slug}/{id}/events`, `/events/{id}`, `/places/search`, `/places/{id}`, `/places/{id}/events`, and `/users/{handle}` and `/users/{handle}/events` once a handle is named. `robots.txt` disallows only `/users/notice` and `/users/timeline`. GETs only; nothing written back; no password or cookie.
- Slugs come back percent-encoded and go through `percentEncodedPath`; re-encoding breaks `!`, `(` and spaces. **A `+` goes as `%2B`** (`URLComponents.setQuery`): a bare `+` reads as a space.
- Performer and hall listings run from the furthest date backwards, so a page reads until the first past row, which makes its Upcoming whole. A hall's listing is `/places/{id}/events` (its page shows ten rows).
- **No hall photograph or performer portrait is published**: `VenueView` draws its own map through `VenuePlaces`; no performer is shown with a picture, no flyer stands in, no placeholder. **Don't go looking for a portrait endpoint again.** (The Me avatar is a member page's.)
- Billing publishes names only, so opening a performer searches the name and takes an exact match.
- **Times are a zoneless wall clock at the hall.** Every page is read on `Event.publishedZone` (Tokyo); a hall placed abroad has its events re-read in its zone (`Event.published(in:)`). Nothing on screen moves; the instant behind it (the calendar entry, its alert, the order) does.
  - **Settings › Time Zone** (`TimeDisplay`, per device, Venue Time by default) prints days and times on the device's clock through `Event.shown(on:)`, a copy *for formatting only*; instants, month groups, `daysAway` and the date filter keep the hall's day. Views read the setting themselves (`@AppStorage`), not through the environment.
  - The sheet's Venue/Local switch (`clockSwitch`) is sheet `@State`, never written to Settings, moving nothing else. Left out where the hall keeps this device's zone (`offersClockSwitch`) — **compared by zone, not offset** (Shawn) — and kept where the hall's clock is unknown. VoiceOver is handed a picker (`accessibilityRepresentation`).
  - Beside it, the chosen clock's offset, on every sheet. **The offset, never a place name**: a zone is the map provider's reading, and the provider follows where the reader stands — from Shanghai a Taipei hall reads "China mainland Time". Don't reinstate `TimeZone.localizedName` or `.genericLocation`. **Only an established clock** (`EventDetailView.venueZone`: a placing, a retimed event, or an address opening with a Japanese prefecture); otherwise no offset.
- Search rows carry no times, head count or address: `Event.isDetailed` marks a page read, and the times are optional. **Do not make them non-optional** — starts are published months late.
- The event page also gives 概要 (kept with its line breaks), 関連リンク, hashtags and the edit history. **Reading more of the page means bumping `Event.currentDetailFormat`**: `isFullyDetailed` compares the stored `detailFormat` and sends one sheet back for the rest — one sheet at a time, never a bulk re-read.
- **概要 translation** (Apple's Translation, `translationTask`) runs only on a tap, into `TranslationTarget` (per device; empty is the app's language). The source is named Japanese (kanji reads as Chinese to a detector); line by line, address lines carried over. **Never written to the archive.** No host; not in the Simulator.
- **A listing row names only the hall**, so `VenueRegions` finds its area in two GETs (`/places/search` by exact name, then the prefecture opening the hall page's address), cached per device for good: only "no such hall" is retried, after a month; a 404 is written down; `!_…` placeholders are never asked. A leading postal code is read past (`Region.droppingPostalCode`). Following and the Me card look up 20 halls a load. A hall abroad has its clock settled by `settleClocks(for:)` (`placeUnplaced`, else `VenueCountries` off the address).
- `Region` is the site's `area_id` facet (the `<select name="area_id">` on `/events`) less 海外: 1 関東, 2 関西, 3 東海, 4 北海道・東北・甲信・北陸, 5 中国・四国・九州・沖縄 — abroad is the absence of a prefecture; written out in [Region.swift](Eventrail/Model/Region.swift). **Don't add a sixth area or split one.**
- Performer search's count is the *fan* count. A venue page's `gb_subtitle` sections are member-written; 座席情報 and 公式サイト answer with an href; 会場TIPS' `<br>`s become newlines.
- **The app reads by itself only what is stale; the reader asking always reads** — the site stops answering a fast asker. Stale is six hours (`Freshness.window`) for `FollowedDates`, `PageReads` and `ListingCache` (keyed by `PerformerLink.cacheKey`/`VenueLink.cacheKey`). A page opens on its cached copy; a sheet re-reads when `EventStore.isStale` or not `isFullyDetailed`. **A refresh by hand ignores the window** (`needsReading` does **not** consult `PageReads`).
  - **A failed read never costs what was held**: `reload` writes over the cache, and a `RefreshFailureNote` goes under the cached copy.
  - **A refusal stops the run** (`Failure.isRateLimited`, 429 or 503).
  - At most `ListingCache.pageLimit` (10) pages a read, 200 ms apart. **Every request is `@concurrent`** (a `nonisolated async` function runs on its caller's actor). Only a read that landed is stamped.
- **A refresh by hand always ends in a notice; one the app started only when it failed** — through `RefreshNotices.report(_:byHand:)`, saying "Updated" or "Update failed" and the reason. A pill drawn by `.refreshNotices()` on each tab, inside each sheet that can refresh, and inside each page with a bar along its foot (`aboveBar`); **only the frontmost draws** (`RefreshNotices.standing`, ranked by sheet depth via `.refreshNoticesInSheet()` and by bar).
- **A site page refreshes from Refresh in its ⋯ menu (`RefreshMenuItem`); only Following has a pull** — a pull on a sheet dismisses it. "Updated 2 hours ago." opens the page's footnote (`Footnote(_:updated:)`, `EventStore.lastRead(of:)`).
  - **Following's `.refreshable` sits on the `List`, inside `.performerDestination()` and `.eventSheet`**: it is inherited by what is presented beneath it.
  - **A read started from `.refreshable` runs in its own `Task`** (`FollowedDates.run`, `reloadDetail`, `ListingCache.read`): SwiftUI cancels the action when the screen changes, and the read ended with no notice.
  - The Passport has no refresh: it is the reader's record read back.
- **Images go through `ImageCache` and `CachedImage`** (the host's ETag kept). A replaced flyer keeps its URL, so a copy is drawn without asking for `Freshness.window` and then revalidated with `If-None-Match`; **a stale copy is drawn at once**, and an unchanged answer returns the same object. A refresh by hand sets `imagesCheckedSince`, so its flyers ask again once.
- Stale checks run again on returning to `.active`. Clear Cache empties the listings, page stamps, `ListingCache`, `ImageCache` and `VenueRegions` — not `VenuePlaces`.
- **The linked account is re-read by itself once stale** (Shawn; `refreshAccountIfStale()`, on open and in `catchUp()`), judged by `LibrarySettings.lastImported` (synced): its favourites and history, then only the pages of what arrived (`arrivalPagesRead`, 20) through `placeAdded`.
  - **It only adds**: a removed event (`departedEvents`) or an unfollowed performer stays out; putting them back is Refresh's job.
  - **Not before a syncing device has heard from iCloud once** (`awaitsFirstFetch`), unless iCloud says nothing will come (`SyncStatus.mayStillImport`).
  - A failed read waits half an hour (`accountRetryPatience`); a notice only on failure.
  - **A read whose account was unlinked or changed meanwhile writes nothing** (`eventernoteHandle` checked after every request). Check it with sync off — never on a simulator syncing the reader's iCloud.
- **What the account lacks is pointed at, never written** (Shawn: no login, no cookie): every history read that reaches its last page writes the account's event ids to `AccountEvents` (per device, Caches, keyed by handle; **a read cut short writes nothing**, or listed events would read as missing; unlinking clears it). `EventStore.notOnAccount(_:)` holds the library against it — nil with no whole read. Not on Your Account lists them; each row's round button, and the sheet's ⋯ Add on Eventernote (`isNotOnAccount`), opens the event's page with `Link`, in the system browser where the reader is signed in — **not `SFSafariViewController`**, whose cookies aren't Safari's. An event leaves at the next read that finds it; the list's Refresh is `readAccountNow()`, the light read by hand, which only adds. The other way (removed here, still on the account) is not listed.
- **Every accessor is failable**: a changed template drops a field or row, never misreads one. A listing's missing block reads as empty only on a page ending in the template's `gb_foot_menu`, else `.unreadable` (a captcha would be cached as "no dates"), as is a positive total over no list or rows printed with none read.

## What the reader records

`Tracking` holds whether there's a ticket (`hasTicket`: a lottery won or a first-come round got — never asked on its own; the old `ticket` field folds into the entries, `foldLegacyTicket()`); `seat` (one free line); the class, through `ticketClass` (the highest class won, by `SeatClass.order(of:)`, else the old `seatClass` column; classes are stored as printed — S席, A席, 一般席 — and shown in the reader's language); `cost` (a `Decimal` as typed; nil is "not written", not free) in `currency` (ISO 4217; empty reads as yen), read through `price`; `lotteries` ([Lottery.swift](Eventrail/Model/Lottery.swift)); and a note.

- **A lottery is an entry, not a count** (`Eventrail v4.dc.html` §7a): `round` (one of `LotteryRound`'s five — 最速先行抽選, プレイガイド先行, プレイガイド二次先行, 一般発売, 見切れ席 — stored as printed and kept as text, so a later build's round reads back), `applications` (0 is "not written"; one per 申込券 or serial code), `day` (the results day, a `CalendarDay`), up to three ranked `LotteryChoice`s (a class and 1–8 tickets) and `result`. A new entry opens with nothing chosen; saved with its applications empty, it counts as applied once. Pending only while the day is ahead; won or lost need a day no later than today.
- **一般発売 and 見切れ席 are first come** (`isFirstCome`): written only for a seat got, with no applications, day or result, and read as won (`outcome`).
- **Everything that reads how a round went reads `outcome`, never `result`.**
- `Tracking.lotteryApplications` sums the lottery rounds' applications — what the old count meant (`carriedOver(count:)` reads the old count back).
- **Entries are listed in sale order** (`lotteriesInOrder`, Shawn's call), read so and never rewritten. Ticket Details saves them round by round (`Tracking.lotteries(_:changedFrom:to:)`), so a round another device added meanwhile stays.
- **A win is the ticket.** Seat and cost appear once there is one; taking it away with a seat or cost written asks to clear them (`leavesSeatOrCostBehind`); Add Lottery Entry with a ticket asks first. The sheet settles the class into `seatClass` (`settleSeatClass(since:)`), never emptying a class no round named. **Everything reads `ticketClass`, never the column.**
- **Interest and attendance are not fields.** Kept means the reader means to go; **attended is a ticket held once the day is over** (`EventStore.hasAttended`), never membership. A past ticket given without saying how is `LotteryEntry.ticketHeld` (`recordTicket()`: a fixed id, no lottery figures). `EventStore.status(for:)` works the badge out. **Don't re-add a field for either.**

Storage:

- **Six columns on `LibraryEntry`, one part dated `trackingChanged`, and a `LibraryLottery` row per round.** `Tracking.edits` dates fields for the archive only. **A field added here is named in `Tracking.Field`** (`sameAnswer(for:as:)` and `take(_:from:)` won't compile otherwise).
- **`currency` rides with `.cost` as one answer, so the cost is one column, `price`** ("9900 JPY", `priceText(of:in:)`), on Shawn's word: as two columns CloudKit settled them apart and ¥9,900 became NT$9,900. The older `costHundredths`/`costCurrency`/`cost` are read only where `price` is empty, and cleared only when the cost next *changes*.
- **The lotteries are rows** (Shawn's call): in one JSON column, two devices adding rounds kept only the last. A row is JSON with sorted keys (`rowText(of:)`), a `position` and a date; removal is `isRemoved`. `writeLotteries` touches only rounds that move, a round keeping its `position` while the order still holds. The old `lotteries` column, `lotteryEntries` count and `ticket` are read only while no rows exist; the first change writes them as rows dated as the entry last changed. **A round this build can't read back whole is overwritten only where the reader changed it; one it can't read at all is never taken for a removal** (`holdsUnreadableRound`) — only removing the event or Delete All clears it.
- **`Tracking` decodes every key as optional, by hand** (`init(from:)` in an extension): a synthesized decoder throws on a missing key, losing the whole archive. **New fields use `decodeIfPresent`.** `LibraryArchive`'s new keys are optional too.
- `MoneyAmount` and `EntryCount` are `ParseableFormatStyle`s so an emptied field reads nil; both read the digits out of anything typed (full-width １２３４ is 1234). Prices print through `Currencies.format`: cents only where there are any, in the locale's symbol (CNY is CN¥ in English); a worked-out figure to the whole unit.

## Same-day clashes

Kept events on one day are checked against each other ([SameDay.swift](Eventrail/Model/SameDay.swift)) — in the sheet's **Same Day** card (`SameDayCard`, for any event ahead, kept or not) and as a red mark on My Events rows (`SameDay.clashes(in:travel:)`), not an alert on adding (Shawn).

- **Be there by the start (開演)** (Shawn). The earlier event ends at its published end or `assumedLength` after its start ("May overlap … no end time announced"); an end past `longestEvent` is a typo. Same day is `Event.localDay`. With no start: "Not checked".
- `SameDay.Timing`: an overlap; the same hall by name (no journey); apart — a gap shorter than the journey is `.tightTransfer`, with no margin added. A placeholder venue (`!_…`) gets the gap alone.
- **The journey is asked only from the sheet**: `MKDirections.calculateETA` by transit, departing at the earlier end; walking under 1.5 km; car without transit. One pair at a time, kept in `Caches/Eventrail/travelTimes.json` keyed by both ids, both halls and the departure minute, re-asked after a month. Rows only read it, so a tight transfer marks a row once its sheet has been opened.
- **The mainland-China Maps provider has no routes outside the mainland**: there every pair in Japan couldn't work out a travel time.

## Where a hall is

Eventernote gives a hall's name and address, no coordinate. [VenuePlaces.swift](Eventrail/Services/VenuePlaces.swift) places it in three tiers, keyed by the hall, kept per device in a `KeptFile` in Application Support (Clear Cache leaves it). **An answer lapses only after a year unread** (`hasLapsed`, `Answer.used`); every library hall is read at launch, so none lapse.

1. **Apple Maps**, by name, believed when its address matches Eventernote's — never by reading the name back (Kアリーナ横浜 is "K-Arena Yokohama"). The only tier with an `MKMapItem.identifier`.
2. **[JapanAddresses.swift](Eventrail/Services/JapanAddresses.swift)**, 国土地理院's address register, where Maps finds nothing: MapKit's provider follows where the *device* stands, and the mainland-China one has no Japanese venues. Grade 7 and up only.
3. **[VenueBuildings.swift](Eventrail/Services/VenueBuildings.swift)**, OpenStreetMap: the named building within 800 m of the register's point, behind the per-device `preciseVenuesEnabled`.

**On the mainland-China provider, Maps is asked only about the mainland** (it matched a Seoul hall to a mainland place sharing a house number). `mapsSeesJapan()` checks once per launch (a search for 東京駅). There, a Japanese hall goes to the register, a `VenueCountries.isMainlandChina` hall to Maps, and any other hall abroad to OpenStreetMap directly (`VenueBuildings.place(named:at:country:)`).

- **The switch off means OpenStreetMap is never asked anything**; a refusal is `Deferred` (nothing written). OpenStreetMap is asked only from a sheet or the Settings refresh, never by an import.
- A hall OpenStreetMap placed gets its country's single clock (`VenueCountries.timeZone(forCountry:)`), else keeps its written one.
- The country readings are text heuristics over members' kanji and katakana addresses, which no API can replace: Korea, Taiwan, the mainland, Hong Kong and Macau, in local script, kanji, katakana and English; a name Japan shares (台東, 大田) only with its suffix; the mainland only with 省/市 (Taipei's streets bear mainland names); Korea also by 広域市/特別市. A miss costs a fallback, never a wrong country.
- OpenStreetMap files Hong Kong and Macau under `cn`, so they are searched in a bounding box (`searchScope(for:)`).
- **The one name-only search**: a hall with no address whose event title names a known city is searched by name and its shortenings (`shortenings(of:)`), inside that country only, under the same switch and rules.
- **That provider draws and answers in GCJ-02**; OpenStreetMap is WGS-84. `Answer.placing` shifts OpenStreetMap answers in `cn`, `hk`, `mo` and `tw` through `MainlandOffset` while `mapsIsMainland` — as drawn, never as stored. **Korea and Japan are not shifted: don't add them.**
- Shortening: after a **space**, try the part after it (高麗大学校 化汀 体育館 → 化汀 体育館); after a **dash**, the part before.
- **Brackets are asked for last** (`inBrackets`): dropped from every search, but abroad they hold the local name, tried before settling for the address.
- Rulesets 9–12 re-ask only answers outside Japan, 13 only "no such place". **A threshold counts from its ruleset on, never at it** (`stillStands(madeUnder:found:inJapan:)`) — compared for equality, every older hall was sent back.

**Who may ask, and when, is load-bearing.** A hall is looked up when its event is opened; the calendar mirror only reads placings (hundreds of searches in a run got the app throttled). An import places its own halls (`placeArrivedVenues`); an event added from Search goes through a one-at-a-time queue (`placeAdded`); `VenuePlaces.refresh(_:)` from Settings is the one way to ask about everything, 500 ms apart. **Tier 3 only when the reader asks.** For OpenStreetMap's policy (one request a second, no bulk): the repository in the User-Agent, 1.1 s pacing, each hall asked once for good (`Answer.triedBuilding`), a refusal stopping the run, and **an import never narrows** (`placeUnplaced`). **Crediting 国土地理院 and OpenStreetMap is a condition of use** ([AboutView.swift](Eventrail/Views/AboutView.swift)) — don't drop that footnote.

**Apple Maps' placing is never overwritten by a lesser answer** (`carrying(_:from:)`); a hall that can't be re-asked now keeps its pin.

**A placing settles the hall's clock** (Maps carries a zone): `timeZones(for:)` reads them back and `EventStore.retimeEvents()` applies them wherever a placing lands. Only halls outside Japan are asked, once (`Answer.needsZone`).

**The map says how its lookup went** (`VenuePlaces.Lookup`, `VenueMap`): finding; couldn't find (`Deferred` included); couldn't load, with Try Again; a struck pin where there's no hall. The sheet keys each answer to its question (`venueKey`).

## The Event Passport

[EventPassportView.swift](Eventrail/Views/EventPassportView.swift); [PassportStats.swift](Eventrail/Model/PassportStats.swift) is one pass over one slice.

- **Read off the library's `@Query`**: attended events for every card but Lottery Entries, which counts the whole past. With nothing attended, the empty state with Record Tickets. Nothing asks Eventernote; computed, never stored.
- `PassportScope`: all time, or a year with something in it. **Not remembered between visits.**
- Every total says what it was counted over: `timedEvents` beside `totalDuration` (an event over `longestEvent`, 16 h, isn't timed); rates out of the rounds drawn; spending over events with a price (¥0 counts, blank doesn't), by `ticketClass`.
- **Lottery Entries**: win rate, Rounds, Entries, Rounds to Win (the rounds up to the first win, in sale order), By Round, By Seat, Entries to Win (the applications over those rounds, by the first win's class) and the events tried hardest.
  - A dot per choice (`choiceMarks(of:)`, `LotteryDots`): filled discs, grey for a choice lost, orange for the one won and none after it, faint with no result — not rings or gaps; **rounds parted by a hairline** (Shawn).
  - Lottery rounds only (`isLottery`); a round with no result is No Result, never a loss.
  - A class's rate counts wins *in that class*: a win in a higher class isn't counted for it, a win lower is "other seat". A win naming no choice is left out of By Seat. Styles come from `SeatStyle.styles(for:)`.
  - A By Round or By Seat row opens its events with only the rounds it counted, every choice dotted (Shawn).
- **A Top Performers or Top Venues row opens the reader's own history there** (`AttendedHistoryView`, `AttendedLink` carrying the Passport's scope): count, first and latest, the events by year, and Open Performer / Open Venue a row on. The "You attended" tile on a performer's or hall's page opens it too, without that row. Matched by printed name (`ListingSubject.includes(_:)`), as the Passport counts; registered by `performerDestination()`, so every stack that shows a performer has it.
- **Ticket Spending is added up in one currency**: the default, or one picked for the visit; others are converted at today's rates (`ExchangeRates`; `CurrencyRates` through the euro). Paid in one other currency, it shows beside the total and in ⓘ popovers (`PassportPaidPopover`); in several, the rate day is the caption. **The card is the same height in every currency**: a conversion goes beside a figure or in a popover, never on its own line. A ticket the rates can't convert is counted apart (`unconvertedTickets`), never read as yen. The seat-type chips stay on one line (`ViewThatFits`, then scrolling — never wrapped).
- **A placeholder venue (`!_…`) or an empty one is no hall** (`Event.isAtHall`): counted, no pin.
- `PassportStats` takes `tracking` as a closure, so it stays `nonisolated` and testable.
- **Every card can be shared as a picture** (Shawn): a Share capsule in each header (`PassportShareButton`), so **every See All stands under its rows** (`PassportSeeAll`). `PassportShareSheet` previews `PassportCardImage` (360 pt at 3×, on the wash, with the app's name) over Save Image and Share. Under `ImageRenderer`: **links and menus are left out** (`leftOutOfPassportImage()`, `PassportRowLink`); **a `Map` renders blank**, so the map is snapshotted (`PassportMapPicture`); **a scroll view renders blank**, so the chips are redrawn; the size is measured and drawn to the whole point. Written as a PNG into `tmp/Passport Cards/`; Save and Share stay off until the file matches.

## The ticket stub

`TicketStubView` ([TicketStubView.swift](Eventrail/Views/TicketStubView.swift), `Eventrail v4.dc.html` §9a) is offered **only where there is a ticket**, with a seat or without (Shawn).

- **What it prints is read, never kept** (`TicketStubFace`). Its labels (OPEN, START, PRICE, SEAT, KEEPSAKE · NOT VALID FOR ENTRY) are English in every language, and the class prints as the ticket prints it. The stamp is e+'s — a heavy word in one thick rounded tilted frame, in e+'s red: 使用済 once attended, 当選 for a lottery won ahead (Shawn: not 参戦, not the design's round stamp).
- **The composer's choices are `@State`, not remembered**: Light/Night, then one row of like tiles (Mask Seat on, Flyer off, Times on, Price on, each only where there's something to print), then Save Image and Share — Shawn found the design's mix of controls chaotic. No stamp tile.
- **A masked seat is not under its mask**: the mosaic (`SeatMask`) is drawn in its place.
- The image is 1080 × 1920, written as a PNG into `tmp/Ticket Stubs/`; **Save and Share stay off until the file matches the screen**.
- The design's fonts aren't bundled; the system's condensed width and heaviest Japanese weight stand in.

## Scanning a ticket

Scan Ticket heads Ticket Details' Seat section ([TicketScanner.swift](Eventrail/Services/TicketScanner.swift)): **Choose from Photos** (e+'s スマチケ screenshots) or **Scan Paper Ticket** (`VNDocumentCameraViewController` via `TicketCamera`; Photos alone where it's unsupported).

- **On the device, with Vision** (`RecognizeTextRequest`). The picture is never kept or sent; only the seat, class, price and day are read — never the name or ticket number.
- **Read once and set upright** (`Line.upright(_:)`) by the way most characters read — not by re-reading at quarter turns, since Vision reads upside down too.
- **`TicketScan` reads the price's column upwards** (`column(above:in:)`): on an e+ card the 未使用 stamp falls between seat and price. Labels (座席, 席種) first; on paper, the first line naming a seat number, with its row and up to two lines over it. **A seat found by layout always carries a number (列, 番, 整理番号) and never the hall's name** (`hall:`); a row's pieces join only while near (`beside`); an address is never a seat. NFKC; 12列34番 becomes 12列 34番.
- **The tests use Vision's output for two real screenshots with what identifies the holder made up. Don't commit a real ticket's picture — the repository is public.** No real paper ticket has been read yet.
- A class is kept as the app keeps one (`seatClass(printed:)`): any 一般 class as 一般席, brackets dropped, 全席指定 as none. Filled in only where no round names a class.
- **Nothing is written until the reader says so twice** (Fill In, then the sheet's checkmark). **A ticket dated otherwise than the event** says so and offers Fill In Anyway.
- **Yen only** (¥, ￥, a backslash, 円).

## Persistence and sync

The library is a SwiftData store (`Library.store`, [LibraryDatabase.swift](Eventrail/Services/LibraryDatabase.swift)) **synced by SwiftData with nothing on top**: a record lands as CloudKit settled it (the last to reach the server, whole), and nothing merges or writes it back — save folding two rows about one thing. An earlier merge layer undid removals, hid kept events and kept devices trading copies. **Don't bring that layer back; make the rows such that CloudKit's rule is the right answer.**

Rows are cut by who writes them ([LibraryModels.swift](Eventrail/Model/LibraryModels.swift)):

- **`LibraryEntry`** — what the reader owns about an event: `inLibrary`, `isFavorite` and the tracking columns, each part dated (`inLibraryChanged`, `favoriteChanged`, `trackingChanged`; an older entry's parts read as `modified`). A write dates only the parts it gives (`give(_:dated:)`) and happens only when one changes (`EventStore.edit`) — **never from reading a page**. A removal is `inLibrary` false, never a deleted row. `kept` holds a JSON copy of the event **because CloudKit can deliver an entry before its facts**; `EventStore.events(of:where:)` falls back to it.
- **`LibraryEvent`** — Eventernote's facts: anything may rewrite it, and it holds nothing the reader decided. **Never emptied or deleted when the event leaves** — an emptied row lands empty everywhere. `facts` reads any row whose columns hold a title (older builds cleared `hasFacts` and left the columns).
- **`LibraryLottery`** — one round (*What the reader records*). **`FollowingReadMark`** — its own record, pruned by event three days after it (`pruneReads`). **`FollowedPerformer`**; **`LibrarySettings`** (one row). **`LibraryMembership`** — read once, never written.

Screens read through the `@Query` descriptors in [LibraryQueries.swift](Eventrail/Model/LibraryQueries.swift) and **turn entries into events through `EventStore.events(of:where:)`, never by reading rows** — it collapses duplicate entries and keeps each event until a write touches it (`save()` names what it wrote; `reindex()` forgets everything after outside changes); reading the rows directly cost ~17 ms a time. `tracking(for:)`, `unread(_:)`, `upcoming(onDayOf:)` and `facts(ofRow:)` are kept the same way. A screen works its list out once per drawing and hands it down. `EventStore` keeps only an index of rows by id (`LibraryDatabase.index(_:by:preferring:)`).

- **Duplicate rows are expected; one is kept** (`deduplicate(in:)`, after every iCloud import and every open): rows sharing an event id, an actor id or an (event, round) keep the one their model's `isPreferred` picks, the lower `uid` breaking ties, so every device keeps the same row. **Two entries are folded first** (`LibraryEntry.absorb(_:)`), part by part — kept whole, a fresh device's newer "in the library" entries once deleted every note, ticket and heart everywhere. Settings fold field by field.
- **Every iCloud import is followed by `settle(in:)` (legacy adoption, then the fold) and a reindex, whatever it brought** (`finished`).
- **A tombstone answers for the reader's devices, not for Eventernote**: an import the reader asked for raises what the account lists; the app's own read doesn't.
- **Sync is SwiftData's own**: `cloudKitDatabase: .private("iCloud.moe.shawn.Eventrail")` with the switch on, mirrored into `com.apple.coredata.cloudkit.zone`; `.none` named outright when off (else SwiftData picks `.automatic`). Every column has a default; nothing is `.unique`.
- **Nothing is `.allowsCloudEncryption`, on purpose**: the private database is already encrypted at rest; end-to-end would cost field renames (Production's fields are plain and can't change), Console visibility and a Keychain-reset failure mode. Encrypting later means a new field name.
- **CloudKit settles concurrent edits to one record by arrival**, and that is accepted. Different parts of one entry *should* both survive (only changed columns are sent; `update(_:to:)` dirties only those) — undocumented, and unseen with one device offline.
- **Older builds' records are adopted wherever nothing answers for them** (`adoptLegacyRecords(in:)`, on every open and import — not once per device, since a reinstalled device hears what older builds left only after its first open), never over an existing entry. **Every device has to run this build.** The old columns and `LibraryMembership` stay: CloudKit's schema only grows.
- **`LibraryArchive`** is the backup format, older builds' format, and their merge. `archive(in:)` exports the store; `apply(_:to:)` writes one back **additively**, only rows that move, each part with its record's date — **re-dating a part whose answer stays but whose record is newer**.
- **Event facts settle by `Event.readAt`**: the later read stands, gaps included — except that a listing row over a page copy keeps the page's bill and flyer. `EventStore.keep` folds an older copy under the row; `EventStore.apply` folds a page read into the row as it stands. Only a listing row or an older-format read has its gaps filled; address and capacity always fill gaps.
- **Only what moved is written**: `update(_:to:)` skips equal values; **a page read finding nothing new isn't written** (`Event.isSameRead(as:)`); `editedAt` is the start of the site's day. Saves are coalesced 400 ms and flushed on backgrounding (`saveNow()`).
- **A failed save is said** (`EventStore.saveFailure`) and retried; so is a backup that couldn't be written. An unreadable store throws rather than standing in an empty library.
- **A field added to `Event`, `Tracking`, `FollowingRead` or `PerformerProfile` needs a column** with a default and a line in its accessor (`LibraryEvent.facts`/`write(_:)`, `LibraryEntry.tracking`, `FollowingReadMark.read`, `profile`). Columns may be added, never removed or renamed. `anArchiveComesBackOutSayingWhatItSaid` catches a field left out.
- **The store is made once per process, by `Launch.shared`** — never in a view's initializer: each extra `EventStore` opened a second CloudKit mirror of the file, which Core Data refuses (134422) and retries forever. `LibraryDatabase` refuses a second mirror (`syncingFiles`).
- **Turning sync on or off reopens the store** (`setSyncing(_:)`). **CloudKit is never opened before the iCloud user is checked**: every launch opens without it, and `checkAccount()`/`startSyncing()` reopens once the user matches, retrying offline (`resumeSyncing()`). **A swap never drops an edit** (an unsaveable context is merged across). The old container is held a second and let go — kept alive it went on syncing — and **the file's claim (`syncingFiles`) goes with that container, not with the switch** (`letGoOfRetired()`, `startsWhenLetGo`).
- **Status** comes from `eventChangedNotification` and `accountStatus()` as `SyncStatus`, via `SyncOutcomes` (setup, import and export kept apart). `lastFetched` is the last successful **import** (`iCloudLastFetched`), not an export. When a device fetches is Core Data's call — on a push, best-effort, seconds to minutes. **There is no public API to fetch now; don't build one by reopening the container.**
- **A change of iCloud account turns sync off** (`accountChanged`, checked against the per-device `iCloudSyncAccount` at start and on `CKAccountChanged`), **and so does deleting Eventrail's iCloud data** (`userDeletedZone` → `cloudDataDeleted`). An unknown account status is shown, never left blank. Core Data may purge a departed account's rows on its own — check on a device before calling that safe.
- `iCloudSyncEnabled` is **per device**, never synced, and **off until the reader turns it on**.
- **A store that won't open is never written over** (before first unlock): the library is held in memory (`isBlocked`) and folded in by `reopen()`.
- **Older files are moved in, not dropped**: `moveIn(from:)` merges `library.json` once (keeping `library.pre-swiftdata.json`), then folds back any `library.unreadable-<stamp>.json`; `LegacyArchive` dates a file without timestamps by its modification date. **The CKSyncEngine builds' iCloud zone is read, never written** (`LegacyCloudZone`, per-device `iCloudLegacyZoneToken`; a `format` above 1 is left alone).

**What a device finds out for itself is a file, not a preference** (`UserDefaults` holds switches only): `VenuePlaces`, `VenueRegions` and `PageReads` each use a [KeptFile](Eventrail/Services/KeptFile.swift), read once and written 400 ms after the last change, in order. One that won't open is never written over; one that won't decode is moved aside as `<name>.unreadable` and folded back later.

**Backup** (`LibraryBackup`) is the one copy nothing done later can reach. A `.eventrail` file is `EVNTRAIL`, a version byte and zlib-compressed JSON — a container, not encryption (`UTType.eventrailBackup`); the importer also takes `.json`.

- **A new field means a new version byte** (`currentFormat`, 10); a higher byte is refused.
- Opened from Files through `CFBundleDocumentTypes` (`Owner`), in place, by `onOpenURL` → `restoringBackup(_:asking:)`. **The type conforms to `public.data`, not `public.archive`**, which Files refused.
- **Export goes through the share sheet** on a real temporary file (rewritten each `EventStore.revision`) for the system's preview, not a lazy `Transferable`; **on a Mac** the same file goes through `fileExporter` (`BackupFile`).
- **Restoring is `LibraryArchive.restoring(_:)`, not `merging(_:)`**, which loses to tombstones: it raises the backup's *positive* records only, adding and never erasing.

**Removals**: `removeAllEvents` empties every entry (never deleting it), unfollows everyone, unlinks the account and marks every date unread, all as tombstones. **Every removal empties the event's record too** (lotteries, ticket, seat, cost, note; not the heart), **so every way out of the library asks first**, through `confirmingRemoval(isPresented:remove:)` and `EventRemoval` in [Panels.swift](Eventrail/Views/Components/Panels.swift) — a new way out goes through it too.

**Capability**: [Eventrail.entitlements](Eventrail.entitlements) carries CloudKit (`iCloud.moe.shawn.Eventrail`) and `aps-environment`, with `remote-notification` in Info.plist; **a device build needs iCloud and Push enabled on the App ID**. The App Group `group.moe.shawn.Eventrail` is on the app and the extension ([EventrailWidgets.entitlements](EventrailWidgets.entitlements)); Xcode Cloud needs the group and the extension's and watch's App IDs registered first (one device build from Xcode does it). **The schema is created in Development by the first save and must be deployed to Production in the CloudKit Console before TestFlight can sync** (`CD_LibraryEntry`, `CD_LibraryEvent`, `CD_LibraryLottery`, `CD_FollowingReadMark`, `CD_FollowedPerformer`, `CD_LibrarySettings`, `CD_LibraryMembership`); every new column is deployed again.

## The Live Activity

For an upcoming event with a ticket (`Eventrail v3.dc.html`): [EventActivities.swift](Eventrail/Services/EventActivities.swift) runs it, [EventLiveActivity.swift](EventrailWidgets/EventLiveActivity.swift) draws it.

- **Started from the sheet, at once, never scheduled** (not `Activity.request(…, alertConfiguration:, start:)`): **iOS ends every activity, scheduled ones too, when the app is updated**, and **ends any activity eight hours after it starts**. So it starts only from `earliestStart`, eight hours (`longest`) before the event's end, and an earlier tap is turned down by the notice pill with an ✕ (`RefreshNotice.refused`, "Available from 12:30"), not an alert. Offered for a kept, ticketed event with a start that isn't over (and always for one already on); not on iPad or where Live Activities are off.
- **It moves on by itself, though nothing can send it anything**: the extension draws **every remaining stage at once** (`ContentState.phases(at:)`) and masks each to its stretch with a `Gate` — the system timer bar (`ProgressView(timerInterval:)`), the one thing that changes by itself at a set time — run through `.luminanceToAlpha()`, 60 pt past both ends, the outgoing gate turned round.
  - **The track's grey differs by renderer** (~0.66 white on the Mac's menu bar showed every stage at once), so the gate cuts at 0.85 (`brightness(-0.35)`, `contrast(16)`).
  - **The watch ignores the gates entirely**, so its card is drawn for one stage (below).
  - Checking needs a real iPhone, its watch or a mirroring Mac: the watch Simulator gets no activities, and Simulator screenshots leave the island out.
  - Only what changes with the stage is drawn per stage, never the flyer. Every redraw starts from `phases(at: .now)`; the stale date is `nextChange`.
- The app updates it on launch and foreground, while the sheet is open, a second after writes and Time Zone changes (`refreshSoon(from:)`), at stage changes and in a background refresh (`refreshTask`). An event gone from the library ends it; one over ends with "That's a wrap".
- **The compact island counts down only through the last hour**: before that it shows the target time without AM/PM, gated to the countdown at 59:59 (`glanceStatus(sizedFor:)`), because the island's width is fixed when it is drawn. It sits over a hidden template ("00:00"), its interval the last hour alone. **Where that doesn't fit, the minimal reading stands in** (`narrowStatus`, a `ViewThatFits` fallback): "47m", "1h", "40s" **in every language** (Shawn; `minimalStatus(latinUnits:)`), 13 down to 9 pt.
- **The minimal island shows the largest unit left, rounded down** (`minimalStatus`), each reading gated, the minutes and seconds being the system timer clipped to a digit-wide slot of a hidden template. Past 12 hours (`minimalHours`) it shows the time.
- **Countdowns are timers ("1:27:13")**: on iOS 27 a `Date.ComponentsFormatStyle` text never updates ("Misconfigured Text(_:format:)"), `.durationOffset` counts negative, the `.offset` styles spell words, and a custom `DiscreteFormatStyle` draws blank (FB16521246). **Don't swap it back without watching the extension's log.**
- **The Lock Screen card and the expanded island stay under 160 pt tall** — taller loses its margins and corners. In the island only the two times go in `.leading`/`.trailing`, everything else in `.bottom`, 6 pt in from the sides with 6 pt of padding at its foot. **Leave its content margins as the system sets them**, and don't use `.center`, which stays centred at its own width. Check on a device.
- The seat is a capsule in the stage's colour.
- **The watch's Smart Stack card** (`SmartStackView`, `.small` via `supplementalActivityFamilies`, `\.activityFamily`): headline and flyer, seat or hall, the two times with the fill. **Drawn for the current stage only** — no `Gate`, not through `eachStage`. A tap opens the watch app on that event (`WKSupportsLiveActivityLaunchAttributeTypes` naming `EventActivityAttributes`; an empty list reportedly fails). Not yet seen on a real watch.
- **The flyer goes through the App Group** (`posterFile(for:)`, 108 × 150 px), since the extension can't download while drawing.
- **Times are on Settings' clock**, never the sheet's switch.
- **A tap opens the event's sheet over whatever is up** (`OutsideOpens`, [OutsideOpens.swift](Eventrail/Views/Components/OutsideOpens.swift)): SwiftUI won't present a root sheet over another, so the root and **the root of every view shown as a sheet carry `.opensFromOutside()`**, and the frontmost takes the request. **A request stands until its sheet's `onAppear`** — nothing is presented over an alert, popover, Quick Look or share sheet — asked again each second by one presenter (`claimant`).

## Handoff

An open event sheet is offered to the reader's other devices ([EventHandoff.swift](Eventrail/Views/Components/EventHandoff.swift)) as `moe.shawn.Eventrail.event` (`NSUserActivityTypes`), its `webpageURL` the Eventernote page — **the whole fallback** for a device without the app.

- **Advertised once per window from `RootView`, never by each sheet**: each sheet stands at its depth (`.advertisesHandoff(of:)`), and the root advertises the frontmost.
- **It carries the event as a listing row would** (`payload(for:)`, ~1 KB, no 概要 or `readAt`), so the receiver reads the page; a copy it can't decode falls back to its own event, else the browser.
- It can't be seen in the Simulator.

## Spotlight, Siri and Shortcuts

[SpotlightIndex.swift](Eventrail/Services/SpotlightIndex.swift) indexes the library's events, followed dates not kept, followed performers and the library's halls; [Eventrail/Intents/](Eventrail/Intents/) makes them App Intents entities.

- **Public facts only, never the reader's record** (Shawn). **Don't add a tracking field to `EventEntity`.**
- Followed dates (domain `following`) expire once their day is over everywhere. A followed performer's kana reading goes in as printed, in the other kana and in romaji (`soundings(of:)`); names are never transliterated, and titles are found only as written.
- **Written as `WidgetLink` writes**: a second after a `factsRevision` change (not `revision` — notes and reads never touch it), a Time Zone change, opening, return, or a `FollowedDates.dates` change. Each item's fingerprint is kept in `Caches/Eventrail/Spotlight.json`, a digest of which is the index's client state; where they disagree the four domains are emptied and rewritten (`SpotlightIndex.format` forces that).
- **Index calls go through the `SpotlightWriter` actor, and a rebuild empties by domain, never with `deleteAllSearchableItems`** (minutes, with the main actor waiting).
- Flyers come only from `ImageCache` (`storedData(for:)`); nothing is downloaded for Spotlight.
- A tapped result (`event/<id>`, `performer/<id>`, `venue/<name>`) becomes an `IntentOpen`, opened through `OutsideOpens`. Search in App (`CoreSpotlightContinuation`) and `SearchEventernoteIntent` run the search at the Search tab's root.
- The intents (`OpenEventIntent`, `OpenPerformerIntent`, `OpenVenueIntent`, `OpenNextEventIntent`, `SearchEventernoteIntent`) go through `IntentOpens.shared`; `EventrailShortcuts` gives Siri three.
- **[AppShortcuts.xcstrings](Eventrail/AppShortcuts.xcstrings) has one entry per shortcut, keyed by its first phrase, its `stringSet` holding every phrase in each language** — an entry per phrase left the later phrases unheard. `xcodebuild` doesn't add to it: add a new phrase in every language by hand. Entity type names are keyed (`entity.event` …), since "Venue" means 現地 elsewhere.
- The entities are `nonisolated` `Codable` structs; their queries hop to the main actor through `Launch.shared`.

## The watch app

[EventrailWatch/](EventrailWatch/) (`Eventrail Watch.dc.html` §1a): My Events, then three Crown pages per event (countdown, seat, times) — a `NavigationSplitView` over a `.verticalPage` `TabView`, laid out from the 46 mm design scaled to the watch (`DesignCanvas`).

- **The phone and the watch update apart**: `WatchLibrary` and `WatchEvent` decode key by key, dropping an unreadable event rather than the copy. **New fields use `decodeIfPresent`.**
- **No store; only what the phone sends**: `WatchLink` sends the upcoming events (at most 60, with ticket, seat, class, cost, applications and `LotteryStanding` as text) as the application context **within `WatchLink.budget`** (60,000 bytes — past ~64 KB it is silently refused), on launch, revision and Time Zone changes (only where different), return and `sessionWatchStateDidChange`. **The watch never asks the phone for anything.**
- Events are read by the Live Activity's rules (`EventActivityStage`). Countdowns are system timers; `StageSchedule` redraws the rest.
- The watch fetches its own flyers (`FlyerCache`, 120 px); nothing else goes over the network.
- **Simulator**: the paired iPhone 18 Pro and Series 12 42 mm. Install and launch the iPhone app *before* installing the watch app, or the phone thinks it isn't there; a context sent in the same second as an install can be lost, so relaunch the iPhone app. A `#if DEBUG` hook handing `WatchLibraryStore` `WatchLibrary.preview` shows the screens anywhere.

## The widgets

**Next Event**, **Lotteries** and **On This Day** (the design's Widgets row, `WidgetNext.dc.html` and the rest): small and medium, plus Lock Screen families; static configurations.

- **The extension reads a copy, never the store**: `WidgetLink` writes `Widgets/library.json` into the App Group (the next ten events, awaiting rounds up to 60, attended events) only when it changed, reloading only the kinds that changed (`WidgetKind`) — a background reload costs the daily allowance. Decoded element by element; new fields optional.
- **Everything that moves with the clock is worked out as the timeline is made**, from the copy's days and times (`WidgetEvent.day`, `WidgetRound.isOut`, `CalendarDay.comesRound(on:)`, `WidgetEvent.leaves`), with entries at midnights and stage times, on Settings' clock.
- Next is the soonest kept event, ticket or not.
- **Won and Lost on the medium Lotteries widget run `GiveLotteryResult` in the extension, which must not write the store**: it leaves files in `Widgets/Answers/` (`WidgetAnswer`), taken in by the app at launch and return (`takeAnswers(into:)`) only for a round still waiting with its day come. With several choices, Won links to the round's page. Deliberately not a `LiveActivityIntent`. **Not yet seen end to end on a device**, nor whether the extension's `UNUserNotificationCenter` reaches the app's pending reminders.
- Links: an event by its Eventernote page, a round with `?round=` (`RoundLink`).
- The extension fetches flyers (`WidgetFlyers`) as the timeline is made, never while drawing, at most 540 px (a widget with far larger images isn't drawn).
- The faces take their family as a parameter, so one preview draws them all.
- **The extension's catalogs are its own**: `xcodebuild` adds no keys — add them by hand with translations (DAY and DAYS are two keys). Its palette colours are copies; white type sits on `solidTicket`/`solidWon` in dark mode.

## The calendar mirror

[CalendarSync.swift](Eventrail/Services/CalendarSync.swift) writes the library into one calendar Eventrail owns, never one the reader made — past events too, **ticket or not** (Shawn).

- **Off by default, and off is quiet**: EventKit is untouched until `calendarSyncEnabled`. A save mirrors only when membership or facts moved (`owesMirror`). `CalendarSync` is an actor. The switch and calendar id are per device.
- **The id is a cache; `calendar()` adopts before it makes** — iCloud syncs the calendar, so one made per device doubled every event. `adoptableCalendar()` wants a writable calendar of the app's name holding **nothing but Eventernote-URL entries**: the mirror deletes everything else, so adopting the reader's own same-named calendar would empty it. **Don't relax it to a title match.** `discardDuplicates(of:)` removes extras by the same test; turning the mirror off on one device takes the calendar off the others until they next mirror.
- Entries carry the hall's zone and are matched by page URL.
- **An entry the library lacks goes only where this device knows its event left** (`goes(_:library:departed:)`, `departedEvents`) — a fresh device once emptied the shared calendar everywhere. Turning the mirror off and on rebuilds it.
- **The sweep is fixed (30 years back, 10 ahead)**, read in four-year chunks; once per device it also sweeps 2018 years on and 543 back (`strays(in:)`) for entries pre-Gregorian builds misdated.
- **One alert, at the door time**; where none is published, the reader's own alert is left alone.
- **No start: an all-day entry, written floating** (`floatingDay(of:in:)`); a start without an end runs `assumedLength`.
- Placings are only read here.
- **Apple Maps' placing always wins** (`keepsLocation(_:over:found:)`, Shawn), told apart by radius: Maps' is zero, every other answer's at least a metre (`notMapsRadius`).

## The results-day reminder

[LotteryReminders.swift](Eventrail/Services/LotteryReminders.swift): a local notification at **20:00 on the results day** of every awaiting round with a day, opening `TicketDetailsView(opening:)` on that round over whatever is up (`RootView.openReminder()`).

- **Floating, on the reader's clock**: its components are written in the phone's own calendar, era included (`components(of:in:)`) — a Gregorian year on a Japanese-calendar phone never fired.
- **Scheduled from the library as it stands** (launch, revisions, return), adding only what differs (`isScheduled(as:)`) — the 60 soonest (`limit`; iOS keeps 64). Each device schedules its own.
- **On by default** (`lotteryRemindersEnabled`): the system prompt is the consent, asked on the ticket sheet's checkmark for a new or moved results day (`askIfNeeded(for:)`).
- The delegate is set as `MyApp` is made, or a tap that launches the app is lost.

## The iPhone Duo

The Duo (`iPhone19,4`, iOS 27.1): an outer screen of 466 × 678 pt used closed, an inner one of 669 × 951 with a fold down its middle. Boards: `DuoClosedEvents`, `DuoClosedEvent`, `DuoOpenEvents`, `DuoTurnedMe`, `DuoBookPassport`, `DuoPassportSheet`. Every API is iOS 27.1 behind `#available`, and nothing knows the Duo's dimensions. An iPad on its side is parted by the same code.

- **The rail is the system's**: closed and on its side, iOS 27.1 draws a vertical bar on the trailing edge (`EnvironmentValues.verticalBarEdge`, `toolbarVerticalEdge`). Closed, the app stays portrait however it is held (Shawn). The sheet's close joins the rail (`closeItem`).
- **The fold is read, never assumed** (`Fold.crossing`, [Fold.swift](Eventrail/Views/Components/Fold.swift)): the `division` reserved region, parting a view only where it runs edge to edge with 240 pt either side (`leastHalf`). `FoldSplitLayout` keeps the last view in place without a fold.
- **One bar over two scroll views follows the last laid out**, so `FoldSplitLayout` lays out the half before the fold last, and the half after keeps clear of the bar (`standingAfterTheFold()`). Nothing in the bar may reach over the half after: Search's scopes move into a `safeAreaBar` beside the fold (`BesideFoldScopes`). Check that a half takes touches with `window.hitTest(_:with:)` from a hook (its own scroll view, never the hosting view).
- **Every list of events opens its event beside itself** across a fold down the screen (`eventPane(_:)`, [EventPane.swift](Eventrail/Views/Components/EventPane.swift)), as a sheet elsewhere — one binding for both, handed across without animation.
  - **The sheet's item is its own state** (`sheetEvent`): SwiftUI writes nil up to a second after a sheet goes; a nil with no sheet up is ignored, and **a sheet put back waits for that nil** (`awaitsReceipt`, or 1.5 s).
  - **Nothing moves while the event's page has a sheet up** (`EventSheetsHold`, `holdsSheet`) — moving it dismissed Ticket Details and lost its answers. The half is tucked away (`isTucked`), and the event moves in the last sheet's `onDismiss`.
  - **Picking closes the event beside the list** (Shawn).
  - **Opening from closed, the sheet goes as the hinge moves** (`readingDuoOpening`) — the fold is published ~1.4 s late.
  - **Only from a list on screen** (`isShown`): a hidden tab's sheet is drawn over the visible tab.
  - **Until a row is chosen the half is empty** (No Event Selected), not the board's first event (Shawn); the chosen row wears a tinted ring.
- **The page beside a list has no stack**: it pushes onto the list's (so every such stack registers `venueDestination()` at its root), and its actions are the list screen's `.primaryAction` items — its close apart, ✓/Share/⋯ in a capsule, then the list's own buttons apart (Shawn). The clock stays in the menu (`keepsBarShort`).
  - **It takes exactly the width offered** (`PageWidth`, `frame(minWidth: 0, maxWidth: .infinity)`): a width measured in a scroll view, or `containerRelativeFrame`, stuck at stale values.
  - The washes are one picture (`washCanvas`); **the wash takes no touches**; a half's scroll view doesn't clip (`scrollClipDisabled`), or shadows are cut at the crease.
- **Me** stands in two columns across a fold down the screen; with the fold across, a grid (`MeView.isGrid`) with no gap at the fold (Shawn) — not `DuoTurnedMe`'s stretched cards or its map.
- **The Passport** is two pages, the year chips in a `safeAreaBar` over both, **nothing frosted under them on the Duo** (Shawn). A See All opens a panel over the second page (`passportDrawer(item:content:)`). **Every drawer is opened from the Passport itself**, since cards are rebuilt as the layout changes. The panel's X uses `closesPassportDrawer`, an `EnvironmentAction` compared by id — a closure in the environment redraws every reader.
- **An iPad on its side is parted the same way** (Shawn; `Fold(parting:)`, idiom `.pad` only): at the middle, wherever the view is wider than tall with 375 pt (`leastWindowHalf`) each side, **judged with the keyboard down**; never across. With its bar spanning both halves, the half after holds under the bar's *settled* deepest point (300 ms), drawers open under the bar, and **one frosted band** (`barBand`) runs across both Passport pages — on the iPad alone.
- **Checking it**: the Duo simulator draws no map tiles. It boots closed, and only DeviceHub's own window turns the hinge (`requestGeometryUpdate` is refused) — ask the reader, reading prints through `simctl launch --console-pty`. `--display=primary` screenshots the outer screen, `--display=primary-1` the inner. Without the hinge, a `#if DEBUG` hook in `Fold.crossing` fakes a fold on an iPad Air 11-inch; an iPad can't be turned from a hook either. Strip hooks before committing.

## The Mac app

**The Mac app is the iPad app through Mac Catalyst** (Optimize for Mac, `TARGETED_DEVICE_FAMILY = 1,2,6`, idiom `.mac`), on Shawn's word: every screen is the iPad's own, branching only where a Mac window is wider than any iPad. **Don't build Mac screens beside the iPad's** — a native target (the local branch `feat/macos`) was abandoned. One bundle id (`DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = NO`).

- **The width is used only for** (`isMac`, [OnTheMac.swift](Eventrail/Views/Components/OnTheMac.swift)): a list kept at **472 pt** with the event beside it (`Fold(listBeside:)`); the event page in two columns from 760 pt (`leastWideWidth`); Me in two from 750 (Shawn: not three); the Passport in three from 1100 (`isTriptych`). **Settings stays one column** (Shawn).
- **Titles are drawn large over the content** (`largeTitleOnMac`: a `safeAreaBar` with `.toolbar(removing: .title)` on an inline bar); the window's own title is hidden (`hidesWindowTitleOnMac()`).
- **Otherwise as on the iPad**: the system tab bar (`.sidebarAdaptable` gave a sidebar), the capsules, the toolbars, Search's one list.
- **A sheet asks for its size** (`macSheetSize(_:)`; otherwise 470 × 400), **held inside its window** (`MacSheetSize.room`, read once); a new sheet gets one. `.presentationSizing(.page)` crashed.
- **Escape closes a sheet** (`.keyboardShortcut(.cancelAction)`), asking where its button asks; **a sheet's button gives Escape up while something stands over it** (`closeShortcut` and the like), since keys fall through. A new sheet does the same.
- **A sheet presented from a window's root is handed the root's environment again** (`RootEnvironment`, `rootEnvironment(_:)`) — on a Mac it opened without the store and crashed — with the tint, the text-size cap and `outsideOpenDepth`; a root sheet added later needs it too. While Welcome is up, the menu bar's items are off.
- **A column after the first hides its scroll edge** (`standingAfterTheFold()`); the Passport takes the iPad's `barBand`.
- **A list whose month headers pin draws its own band under the bar** (`bandUnderBarOnMac()`, through `monthSections()`): the system runs a list's edge on under a pinned header, and on a Mac it stayed a header deep over Following's chips once scrolled back. Solid to the bar's foot, its line on the pinned header's own backdrop — a fade let the rows show between.
- **`settingSwitch()` ([SettingRow.swift](Eventrail/Views/Components/SettingRow.swift)) goes on each switch, never on a screen or the root**: a toggle in a menu can't draw a switch, and came out split.
- **Rows are picked by a click each** (`listSelection()`, `pickingEditMode(_:)`, `pickedByClickOnMac`): a Mac's `List(selection:)` picks one row per click. A new picking list uses all three.
- **A right-click opens what a row's swipes do** (`contextMenuOnMac(_:)`, Mac only); a new swipe gets an item here too.
- **A window that only lost focus catches up at most every five minutes** (`catchUp()`, `owesCatchUp`) — every app switch made the scene inactive.
- **Linear progress is drawn as on iOS** (`linearProgressAsOnPad()`), and **every navigation bar as an iPad's** (`PadNavigationBar`, `padNavigationBarOnMac()`, on every tab's stack and every sheet's stack root) rather than in the toolbar.
- **The menu bar** (`AppCommands`): Settings… (⌘,) over whatever is up, never twice (`standsAsSettings(covered:)`), and ⌘1–⌘4, through `focusedSceneValue`.
- **No Live Activities, widgets, watch app, fold APIs, document camera or `Playgrounds`** (fenced, or `platformFilters = (ios)`). **No `defaultSize` on the window**: Catalyst pins its smallest and largest size to it (`UIWindowScene.sizeRestrictions`).
- **The sandbox is build settings conditioned on `[sdk=macosx*]`**, as are `UIApplicationSceneManifest_Generation` (more than one window) and `UIApplicationSupportsIndirectInputEvents`.
- **Universal purchase**; Xcode Cloud archives a Catalyst build from `release`. Whether `aps-environment` reaches the Mac is unseen.
- **Checking it**: build for `variant=Mac Catalyst` with `CODE_SIGNING_ALLOWED=NO` and a check bundle id (never the reader's container), sign ad hoc with the sandbox and outgoing connections (`codesign --force --deep --sign - --entitlements …`), launch with `-ApplePersistenceIgnoreState YES`, and capture with `screencapture -o -x -l<window id>`. Temporary `#if DEBUG` hooks in `Launch` supply something to show; strip them.

## The look

From the Claude Design canvas "Eventernote Mobile App Design" (`Eventrail.dc.html`). **Pages are not drawn in glass** (Shawn): cards, rows, pills and chips use `PanelFill` and `PanelRim` through `panel(cornerRadius:tint:)`, `capsulePanel()` and `circlePanel()` ([WashBackground.swift](Eventrail/Views/Components/WashBackground.swift)); a page's buttons are `.bordered`/`.borderedProminent`, not `.glass`/`.glassProminent`. Glass is kept for what floats over a page (the list capsule, the Passport's chips, the refresh notice, close and back buttons — `glassCapsule`, `glassCircle`, `glassBackground`). Colours are colorsets in `Assets.xcassets` from the design's oklch values, the panel's with High Contrast variants; the widget extension holds copies — change both.

**Don't put glass, a material or a shadow back on a panel**: on a 700-event list they dropped one frame in six; flat colour costs almost nothing.

Every screen sits on `washBackground()`. The icon is `Eventrail/AppIcon.icon`, drawn in About from `AppIconArt`. **A changed icon means re-exporting `AppIconArt` and `Design/AppIcon.png`, and copying the document over `EventrailWatch/AppIcon.icon`.**

**Text that is read follows the reader's text size; the rest keeps the design's points** (Shawn): list rows, the event sheet's body, Ticket Details and Settings use `scalingFont(size:weight:design:)` ([Typography.swift](Eventrail/Views/Components/Typography.swift)); controls, tiles, chips, the Passport, the stub, Welcome and the extensions use `.font(.system(size:))`. **The app stops at xxxLarge** (`dynamicTypeSize(...DynamicTypeSize.xxxLarge)` on `RootView`).

## Build and run

```bash
# Build for the simulator
xcodebuild -scheme Eventrail -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build

# Build the Mac app (Mac Catalyst) — see *The Mac app* for running it
xcodebuild -scheme Eventrail -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' CODE_SIGNING_ALLOWED=NO build

# Clean build folder when the project file or build settings change
xcodebuild -scheme Eventrail clean
```

**Xcode 27 ships no `Simulator.app`**: the simulator UI is `DeviceHub.app`, opened with `open -b com.apple.dt.Devices` (`open -a Simulator` fails). `xcrun simctl` is unchanged — prefer it. [.vscode/](.vscode/) holds only SweetPad's settings; don't re-add a launch task or runner script without a reason.

Check `xcodebuild -scheme Eventrail -showdestinations` before naming a device: the simulators are iPhone 18 Pro, iPhone Air, iPhone Duo (iOS 27.1 only) and the iPads; `iPhone 17` no longer resolves, and a missing name fails the build.

```bash
# Run the unit tests
xcodebuild test -scheme Eventrail -destination 'platform=iOS Simulator,name=iPhone 18 Pro'

# Run one suite or one test
xcodebuild test -scheme Eventrail -destination '<dest>' -only-testing:EventrailTests/TrackingTests
xcodebuild test -scheme Eventrail -destination '<dest>' '-only-testing:EventrailTests/TrackingTests/twoDevicesEditingDifferentAnswersKeepBoth()'
```

**A Swift Testing test is named with its `()`**: without it the filter matches nothing and the run still says `TEST SUCCEEDED`.

[EventrailTests/](EventrailTests/) is Swift Testing hosted by the app (`@testable import Eventrail`), a synchronized group under the shared scheme. It covers pure logic only — never the network, iCloud, EventKit or MapKit; the page readers run against hand-written pages, never fetched ones, and `LibraryDatabase` on an in-memory store. `Fixtures.event(...)` names only the fields a test needs. `#expect` can't wrap a mutating call; take the result into a `let` first.

## Branches and releases

**Every change goes on `main`. `release` is what testers run, and only a pull request advances it, on Shawn's word.** Xcode Cloud builds from `release`, sending the iOS and Mac Catalyst builds to TestFlight.

```bash
# ordinary work — this is all of it
git switch main
# edit, build, commit
git push

# only when Shawn says a build should go out
gh pr create --base release --head main --title "release: <what is in this build>"
# merged on his word; Xcode Cloud builds and distributes from release
```

**Don't open that pull request unasked, and never push to `release` directly** — readiness for testers is his call.

- **Keep `main` buildable**: build the iOS app *and* the Mac Catalyst app before pushing; nothing else checks.
- **A hotfix branches off `release`** while `main` holds unfinished work (`git switch -c fix/<summary> release`), goes to `release` by PR, and is merged into `main` too.
- A PR into `main` is optional, for work worth reviewing; its branch is named by commit type (`feat/`, `fix/`, …).
- **Pull requests are written in English.**
- **Xcode Cloud builds what the repository holds** (`xcshareddata/xcodecloud/manifest.json`; `xcshareddata/` is tracked, `xcuserdata/` ignored), so local-only Xcode state fails there.

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

- `Eventrail`, `EventrailWidgets`, `EventrailWatch` and `Shared` are **PBXFileSystemSynchronizedRootGroup**s (`objectVersion = 90`), so new files are picked up — **don't hand-edit `project.pbxproj` to register sources**. `Shared` is in all three targets; `EventActivity.swift` and `WidgetLibrary.swift` are excepted from the watch. The watch app is embedded by an "Embed Watch Content" phase and a target dependency.
- [Info.plist](Info.plist) holds only what can't be a build setting (`UTExportedTypeDeclarations`, `CFBundleDocumentTypes`, `UIBackgroundModes`, `BGTaskSchedulerPermittedIdentifiers`, `NSUserActivityTypes`, `CoreSpotlightContinuation`), and [EventrailWidgets-Info.plist](EventrailWidgets-Info.plist) only `NSExtension`; `INFOPLIST_KEY_*` settings merge in. **Anything that can be a build setting should be one** — Xcode rewrites the plist and strips its comments, so reasons go here.
- `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`: the only encryption is the system's HTTPS; `CryptoKit` only hashes; a backup is compressed. **Adding encryption of the app's own means revisiting this.**

## Platform and language constraints

- iOS and iPadOS 26.0, with `SUPPORTS_MACCATALYST = YES` on the app; a native macOS target and visionOS were dropped deliberately. **Fence Mac-excluded code with `#if targetEnvironment(macCatalyst)`, not `os(macOS)`.** The watch app is watchOS 26.0. The leftover `#if os(visionOS)` branches stay unless removed on purpose.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, approachable concurrency, Swift 6: mark off-main work explicitly (`nonisolated`, `@concurrent`, actors). A `nonisolated async` function runs on its caller's actor; a non-`Sendable` framework value (`TranslationSession`) is used from a `@concurrent` function from the moment it arrives.
- **Every year, month and day the app counts, keeps or compares is Gregorian** (`Calendar.gregorian(in:)`, `asGregorian`, [Shared/Gregorian.swift](Shared/Gregorian.swift)), **never `Calendar.current`** — a Japanese calendar (Reiwa 8, with no era in `dateComponents`) or a Buddhist one put entries in 4044 and results days in the year 8. The reader's calendar only names whole dates on screen; a counted month is named from the Gregorian calendar in the reader's language (`monthSymbols(in:)`), and a lone month or year goes through `.gregorian()`. `CalendarDay` reads a year under 100 as Reiwa's and 2400 and up as the Buddhist Era's. `GregorianTests` covers six calendars, and the suite passes with the Simulator set to any of them (`defaults write -g AppleLocale en_US@calendar=japanese`) — **so tests build their dates on `Calendar.gregorian()` too.**
- String catalogs, in en, ja, zh-Hans and zh-Hant; user-facing strings are `LocalizedStringKey`s.

## Permissions and hosts

`ENABLE_APP_SANDBOX` and the other `ENABLE_*` sandbox settings are macOS's, set only under `[sdk=macosx*]` — **don't set them unconditioned**. A resource the Mac reads needs both its sandbox setting and its usage string.

- **Calendars** (`NSCalendarsFullAccessUsageDescription`; full access, to read back and adopt) — the mirror only.
- **Notifications** — `LotteryReminders` only, on the first ticket-sheet save with a results day ahead or when its switch is turned back on; never at launch.
- **Photos, add-only** (`NSPhotoLibraryAddUsageDescription`) — on the first save of a flyer, stub or Passport card. Save Image in a share sheet needs it too, or the app is killed.
- **Camera** (`NSCameraUsageDescription`) — Scan Paper Ticket only. A picked file or picture needs nothing.
- **Nothing asks for location**, the microphone, contacts or the rest. A feature that would adds a system prompt — flag it.

Five hosts and no others: `www.eventernote.com`; `eventernote.s3.amazonaws.com` (flyers, through `ImageCache` — **never `AsyncImage`**, whose cache the host's missing `Cache-Control` defeats); `msearch.gsi.go.jp`; `nominatim.openstreetmap.org`; and `api.frankfurter.dev` (its **v2**, `/v2/rates?base=EUR`, kept 12 hours, 5 minutes after a failure — v1 has no TWD or MOP). Maps goes through MapKit; anything else is opened as a link. **Another host should be argued for first.**

## Playgrounds

[RootView.swift](Eventrail/Views/RootView.swift) has a `#Playground` beside its `#Preview`, both under `#if canImport(Playgrounds)` (Catalyst has none) — not tests, and not run by `xcodebuild`.
