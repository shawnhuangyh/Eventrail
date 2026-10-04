import SwiftUI

/// What this app is, which build of it is running, and where its source is.
///
/// Pushed from Settings rather than shown as a sheet of its own: it is the
/// bottom of that screen's last section, and a reader who opened it to read the
/// version number leaves with a back button rather than a second Done.
struct AboutView: View {
    private static let repository = URL(string: "https://github.com/shawnhuangyh/Eventrail")!
    private static let issues = URL(string: "https://github.com/shawnhuangyh/Eventrail/issues")!

    /// Read from the bundle rather than written down here, for the reason
    /// ``SettingsView`` gives: a released build cannot claim a version it is
    /// not. The build number stands beside it because two builds of the same
    /// version are the thing a bug report has to tell apart.
    private var version: Text {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              build != short else {
            return Text("Version \(short)")
        }
        return Text("Version \(short) (\(build))")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                masthead
                repositoryCard
                footnote
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .washBackground()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Who this is

    private var masthead: some View {
        VStack(spacing: 10) {
            AppIconBadge(width: 88)
                .padding(.bottom, 2)
            // The app's name, not a string to translate.
            Text(verbatim: "Eventrail")
                .font(.system(size: 22, weight: .bold))
                .kerning(-0.3)
            version
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            Text("A companion for Eventernote: browse events, keep your own record of what you have been to and what you are going to, and follow the performers you care about.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 22)
        .glassPanel()
        .padding(.top, 8)
    }

    // MARK: - Where the source is, and where a problem goes

    /// The repository and its issue tracker, one card because they are one
    /// place. Both open outside the app like every other link — there is no
    /// feedback service of our own.
    private var repositoryCard: some View {
        VStack(spacing: 0) {
            linkRow("chevron.left.forwardslash.chevron.right", "Source on GitHub",
                    to: Self.repository)
            SettingRowDivider()
            linkRow("exclamationmark.bubble", "Report a Problem", to: Self.issues)
        }
        .glassPanel(interactive: true)
    }

    private func linkRow(_ symbol: String, _ title: LocalizedStringKey, to url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var footnote: some View {
        // One paragraph: whose the records are, where the facts come from, and
        // the credits 国土地理院 and OpenStreetMap ask for as a condition of use.
        Footnote(Text("Your notes, seats and costs stay on this device and, with iCloud Sync on, in your own iCloud — there is no Eventrail server. Event details are read from Eventernote's public pages and never written back; Eventrail is not affiliated with Eventernote. Venues are placed by Apple Maps, the address search of the Geospatial Information Authority of Japan (国土地理院) and OpenStreetMap — © OpenStreetMap contributors, ODbL. Exchange rates are the central banks' reference rates, as Frankfurter publishes them."))
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }
}

/// The app's own icon, drawn at any size.
///
/// The artwork is its own image set rather than the icon itself: the icon is an
/// Icon Composer `.icon`, which the catalog holds as a layer stack and not as a
/// picture — `UIImage(named: "AppIcon")` on one throws rather than returning
/// nil, and the flattened PNGs iOS writes beside it top out at 120 points, too
/// small to stand at this size. `AppIconArt` is the same 512-point export the
/// README shows, so a changed icon means re-exporting it here too.
struct AppIconBadge: View {
    var width: CGFloat = 88

    /// The proportion iOS itself masks an icon at, so the badge is the shape
    /// the reader sees on their Home Screen rather than an approximation.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: width * 0.2237, style: .continuous)
    }

    var body: some View {
        Image(.appIconArt)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: width)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.white.opacity(0.28), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .accessibilityLabel("Eventrail")
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
