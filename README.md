<p align="center">
  <img src="Design/AppIcon.png" alt="Eventrail app icon: an ivory ticket with an E-shaped trail and three event stops, on a blue background" width="128">
</p>

<h1 align="center">Eventrail</h1>

<p align="center">A native iOS companion for <a href="https://www.eventernote.com/">Eventernote</a> — browse events, follow performers, and keep your own record of every night you go to.</p>

<p align="center"><a href="docs/overview.md">Feature overview</a></p>

<!-- TODO: add a 📸 Screenshots section here once screenshots exist -->

## 📱 Availability

Eventrail is in **beta testing** through TestFlight. It is not on the App Store yet.

<!-- TODO: add the public TestFlight invite link here -->

> Eventrail is an independent project and is not affiliated with or endorsed by Eventernote.

## ✨ Features

- **🔍 Native browsing** — Search Eventernote's public events and performers in a real iOS app, with detail pages for events, performers and venues
- **🎫 Your own records** — Keep events in a library with your ticket, seat, price, lottery entries and notes
- **⭐ Favorites & following** — Favorite events and follow performers to see every upcoming date they are billed on
- **🗺️ Event Passport** — A map of every hall you have been to, with the numbers behind your nights
- **📅 Calendar mirror** — Write your library into a calendar of the app's own, with an alert when the doors open
- **📥 Profile import** — Import a public Eventernote profile's attendance history and favorites (read-only, no password)
- **☁️ iCloud sync** — Keep your records in step across iPhone and iPad through your private iCloud storage
- **💾 Backup & restore** — Export your library to a `.eventrail` file and restore it any time
- **🌍 Multi-language** — English, Japanese, Simplified Chinese and Traditional Chinese, with on-device translation of event overviews

See the [feature overview](docs/overview.md) for how each of these works and how your data is treated.

## 🔧 Development

### 📋 Requirements

- iOS / iPadOS 26.0+
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

3. **Build and run** — pick a simulator or device and press `⌘R`.

   A device build needs iCloud enabled on the App ID in your developer portal, since sync uses the iCloud key-value store entitlement. Simulator builds work as-is.

### Common Commands

```bash
# List the destinations your Xcode can build for
xcodebuild -scheme Eventrail -showdestinations

# Build for the simulator
xcodebuild -scheme Eventrail -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
```

## 🤝 Contributing

Contributions are welcome — feel free to open an issue or a pull request against `main`.

`main` is the main development branch.

### Commit Message Guidelines

This project follows the Conventional Commits format:

- Start with a type: `feat`, `fix`, `docs`, `test`, `refactor` or `chore`
- Write a concise, imperative subject
- Name a pull request branch after its type (`feat/…`, `fix/…`)

```text
feat: add a Language screen with the translation target
fix: draw a stale flyer at once and revalidate it behind
chore: declare no non-exempt encryption
```

## 📝 License

This project is licensed under the [MIT License](LICENSE). The license covers this app's own source code; it says nothing about Eventernote's content, which remains the site's.

## 🙏 Acknowledgments

- [Eventernote](https://www.eventernote.com/) for the event, performer and venue information the app reads
- [国土地理院 (Geospatial Information Authority of Japan)](https://www.gsi.go.jp/) for its address search
- [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors for building-level venue locations

---

**Made with ❤️ using Swift and SwiftUI**
