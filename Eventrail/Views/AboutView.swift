import SwiftUI

/// What this app is, which build of it is running, and where its source is.
///
/// Pushed from Settings rather than shown as a sheet of its own: it is the
/// bottom of that screen's last section, and a reader who opened it to read the
/// version number leaves with a back button rather than a second Done.
struct AboutView: View {
    private static let repository = URL(string: "https://github.com/shawnhuangyh/Eventrail")!

    /// Read from the bundle rather than written down here, for the reason
    /// ``SettingsView`` gives: a released build cannot claim a version it is
    /// not. The build number stands beside it because two builds of the same
    /// version are the thing a bug report has to tell apart.
    private var version: Text {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              build != short else {
            return Text(verbatim: "Version \(short)")
        }
        return Text(verbatim: "Version \(short) (\(build))")
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
            Text("A companion for Eventernote: browse events, keep your own record of what you're interested in, hold and attended, and follow the performers you care about.")
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

    // MARK: - Where the source is

    private var repositoryCard: some View {
        Link(destination: Self.repository) {
            HStack(spacing: 12) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Source on GitHub")
                        .font(.system(size: 14, weight: .semibold))
                    // The address itself, so the reader can see where the tap
                    // goes before they take it.
                    Text(verbatim: Self.repository.absoluteString.replacingOccurrences(of: "https://", with: ""))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
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
        .glassPanel(interactive: true)
    }

    private var footnote: some View {
        Text("Eventrail is open source under the MIT licence. It is not affiliated with or endorsed by Eventernote; event details come from that site's publicly accessible pages and are never written back.")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
