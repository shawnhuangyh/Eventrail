<p align="center">English · <a href="README.zh-CN.md">简体中文</a></p>

<p align="center">
  <img src="Design/AppIcon.png" alt="Eventrail app icon: an ivory ticket with an E-shaped trail and three event stops, on a blue background" width="128">
</p>

<h1 align="center">Eventrail</h1>

<p align="center">A native iOS companion for <a href="https://www.eventernote.com/">Eventernote</a> — browse events, follow performers, and keep your own record of every event you go to, from the lottery to the ticket stub.</p>

<p align="center"><a href="docs/overview.md">Feature overview</a></p>

<!-- TODO: add a 📸 Screenshots section here once screenshots exist -->

## 📱 Availability

Eventrail is in **beta testing** through TestFlight, for iPhone, iPad and Apple Watch. It is not on the App Store yet.

<!-- TODO: add the public TestFlight invite link here -->

> Eventrail is an independent project and is not affiliated with or endorsed by Eventernote.

## ✨ Features

- **🔍 Native browsing** — Search Eventernote's public events and performers, filtered by date and area and sorted either way, or start from the site's own Today and Just Added lists; every event, performer and hall has a page of its own
- **🎫 Your own records** — Keep events in a library with every lottery round you entered, your seat, what it cost in any currency, and notes; the ticket is read from the round you won
- **🎰 Lotteries** — Every round still waiting on a result in one list, by results day, with the result recorded from the list itself and a reminder at 8 PM on results day
- **⭐ Favorites & following** — Favorite events and follow performers to see every upcoming date they are billed on, with new and changed dates marked until you have looked at them
- **🗺️ Event Passport** — A map of the halls you have been to, with the numbers behind your events: time spent, ticket spending by seat class, and how your lotteries went
- **🎟️ Ticket stub** — Turn a ticket into a keepsake image to save or share, with the seat masked if you like
- **⏱️ Live Activity** — On the day of an event you hold a ticket for, follow it from the doors to the end on the Lock Screen, in the Dynamic Island and in your Apple Watch's Smart Stack
- **⌚ Apple Watch app** — Your upcoming events on your wrist: the countdown, your seat and the times
- **📅 Calendar mirror** — Write your library into a calendar of the app's own, with an alert when the doors open
- **📥 Profile import** — Import a public Eventernote profile's attendance history and favorites (read-only, no password), then tick off the events you held a ticket for
- **☁️ iCloud sync** — Keep your records in step across iPhone and iPad through your private iCloud storage, with no server of the app's own
- **💾 Backup & restore** — Export your library to a `.eventrail` file and restore it any time
- **🌍 Multi-language** — English, Japanese, Simplified Chinese and Traditional Chinese, with on-device translation of event overviews and times on the hall's clock or your own

See the [feature overview](docs/overview.md) for how each of these works and how your data is treated.

## 🔧 Development

### 📋 Requirements

- iOS / iPadOS 26.0+, and watchOS 26.0+ for the watch app
- Xcode 26.0+ (the project is developed against Xcode 27)
- No package manager and no third-party dependencies

### 🚀 Getting Started

1. **Clone the repository**

   ```bash
   git clone https://github.com/shawnhuangyh/Eventrail.git
   cd Eventrail
   ```

2. **Open in Xcode**

   ```bash
   open Eventrail.xcodeproj
   ```

3. **Build and run** — pick a simulator or device and press `⌘R`. The `Eventrail` scheme builds the widget extension and the watch app too, and embeds both.

   Simulator builds work as-is. A device build needs iCloud (with the `iCloud.moe.shawn.Eventrail` CloudKit container) and Push Notifications enabled on the App ID in your developer portal, since sync runs on CloudKit, and the App Group `group.moe.shawn.Eventrail` on both the app and the widget extension, since the Live Activity's flyer is handed over through it. Automatic signing registers the group and the extension's and watch app's App IDs on the first device build from Xcode; a signing that cannot, such as Xcode Cloud's, needs them to exist first. Before a TestFlight build can sync, deploy the CloudKit schema to Production in the CloudKit Console, and again whenever a model gains a type or a field: run a development build with iCloud Sync on first, so the Development schema has it to deploy.

   The Live Activity needs a real iPhone to check: the Simulator's screenshots leave the Dynamic Island out, and the watch Simulator is sent no Live Activity.

### Common Commands

```bash
# List the destinations your Xcode can build for
xcodebuild -scheme Eventrail -showdestinations

# Build for the simulator
xcodebuild -scheme Eventrail -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build

# Run the unit tests
xcodebuild test -scheme Eventrail -destination 'platform=iOS Simulator,name=iPhone 18 Pro'

# Run one test (a Swift Testing test is named with its "()", or nothing runs)
xcodebuild test -scheme Eventrail -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  '-only-testing:EventrailTests/TrackingTests/twoDevicesEditingDifferentAnswersKeepBoth()'
```

Xcode 27 ships no `Simulator.app`; its simulator window is `DeviceHub.app` (`open -b com.apple.dt.Devices`). `xcrun simctl` works as before.

## 🤝 Contributing

Contributions are welcome — feel free to open an issue or a pull request against `main`.

`main` is where all work lands. `release` is what TestFlight testers run: Xcode Cloud builds from it, and it moves only by a pull request from `main` when a build is ready to go out.

### Commit Message Guidelines

This project follows the Conventional Commits format:

- Start with a type: `feat`, `fix`, `docs`, `test`, `refactor` or `chore`
- Write a concise, imperative subject
- Name a pull request branch after its type (`feat/…`, `fix/…`)

```text
feat: remind on a lottery's results day at 8 PM
fix: stop the calendar mirror crashing on a new untimed event
docs: describe sync as SwiftData settles it
```

## 📝 License

This project is licensed under the [MIT License](LICENSE). The license covers this app's own source code; it says nothing about Eventernote's content, which remains the site's.

## 🙏 Acknowledgments

- [Eventernote](https://www.eventernote.com/) for the event, performer and venue information the app reads
- [国土地理院 (Geospatial Information Authority of Japan)](https://www.gsi.go.jp/) for its address search
- [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors for building-level venue locations
- [Frankfurter](https://frankfurter.dev/) for the central banks' reference exchange rates

---

**Made with ❤️ using Swift and SwiftUI**
