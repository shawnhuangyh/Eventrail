import MapKit
import SwiftUI

/// One of the Passport's cards, as the reader can share it as a picture —
/// each card with a Share of its own, as Flighty shares its passport section
/// by section.
nonisolated enum PassportCard: Hashable, Identifiable {
    /// The map and the figures under it.
    case summary
    case events
    case time
    case performers
    case venues
    case lotteries
    case spending

    var id: Self { self }

    /// What the sheet is titled, and the picture's file named.
    var title: LocalizedStringResource {
        switch self {
        case .summary: "Event Passport"
        case .events: "Events"
        case .time: "Time at Events"
        case .performers: "Top Performers"
        case .venues: "Top Venues"
        case .lotteries: "Lottery Entries"
        case .spending: "Ticket Spending"
        }
    }
}

extension EnvironmentValues {
    /// Whether a Passport card is being drawn as a picture to share rather
    /// than on screen — set by ``PassportCardImage``. What leads anywhere —
    /// a See All, a menu, the Share itself — is left out of the picture
    /// (``View/leftOutOfPassportImage()``).
    @Entry var drawsPassportImage = false
}

extension View {
    /// Leaves this out of a Passport card drawn as a picture: a control with
    /// nothing to do in an image.
    func leftOutOfPassportImage() -> some View {
        modifier(LeftOutOfPassportImage())
    }

    /// The capsule a control in a Passport card's header is drawn in — the
    /// spending card's currency, every card's Share — so the two read as a
    /// pair where they stand side by side.
    func passportHeaderCapsule() -> some View {
        foregroundStyle(Color.brandTint)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color(.secondarySystemGroupedBackground), in: .capsule)
            .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
    }
}

private struct LeftOutOfPassportImage: ViewModifier {
    @Environment(\.drawsPassportImage) private var isImage

    func body(content: Content) -> some View {
        if !isImage { content }
    }
}

/// The Share on a Passport card: opens the card as a picture, to save or
/// send (``PassportShareSheet``). Its word beside the symbol where the
/// header has room for both, the symbol alone where it does not.
struct PassportShareButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    symbol
                    Text("Share")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                }
                symbol
            }
            .passportHeaderCapsule()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Share"))
        .leftOutOfPassportImage()
    }

    private var symbol: some View {
        Image(systemName: "square.and.arrow.up")
            .font(.system(size: 12.5, weight: .semibold))
    }
}

/// The Passport's map, drawn ahead as a picture for its card shared as one:
/// a `Map` is the one thing ``PassportCardImage`` cannot draw, and comes out
/// blank.
struct PassportMapPicture {
    let snapshot: MKMapSnapshotter.Snapshot

    /// What the map is of, and its proportion on the card.
    struct Request {
        let region: MKCoordinateRegion
        let aspect: CGFloat
    }

    /// The map `request` asks for, as wide as the card drawn as a picture,
    /// in `scheme` — or nil where it could not be drawn, offline say.
    static func take(_ request: Request, scheme: ColorScheme) async -> PassportMapPicture? {
        let width = PassportCardImage.cardWidth
        let options = MKMapSnapshotter.Options()
        options.region = request.region
        options.size = CGSize(width: width, height: width / request.aspect)
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        options.traitCollection = UITraitCollection { traits in
            traits.userInterfaceStyle = scheme == .dark ? .dark : .light
            traits.displayScale = PassportCardImage.scale
        }
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        return PassportMapPicture(snapshot: snapshot)
    }
}

/// A Passport card as a picture: the card at a phone's width on the wash,
/// with the app and the slice it was read over under it, since a card says
/// neither. In the reader's own appearance, as the card stood on screen.
enum PassportCardImage {
    /// The card's width in points — a phone's.
    static let cardWidth: CGFloat = 360
    static let scale: CGFloat = 3

    static func render(_ card: some View, scope: PassportScope, scheme: ColorScheme) -> UIImage? {
        let content = VStack(alignment: .leading, spacing: 12) {
            card.frame(width: cardWidth)
            footer(scope)
        }
        .padding(20)
        .fixedSize(horizontal: false, vertical: true)
        // Measured first, and drawn to the whole point: a height a fraction
        // of a point over left the last row of pixels black.
        var size = CGSize.zero
        ImageRenderer(content: drawn(content, in: scheme)).render { measured, _ in size = measured }
        guard size.height > 0 else { return nil }
        let renderer = ImageRenderer(content: drawn(
            content
                .frame(width: size.width.rounded(.up), height: size.height.rounded(.up), alignment: .top)
                .background { WashBackground() },
            in: scheme))
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// `content` in the environment a picture is drawn in.
    private static func drawn(_ content: some View, in scheme: ColorScheme) -> some View {
        content
            .environment(\.drawsPassportImage, true)
            .environment(\.washCanvas, nil)
            .environment(\.colorScheme, scheme)
            .environment(\.legibilityWeight, .regular)
    }

    private static func footer(_ scope: PassportScope) -> some View {
        HStack(spacing: 8) {
            AppIconBadge(width: 22)
            // The app's name, not a string to translate.
            Text(verbatim: "Eventrail")
                .font(.system(size: 13, weight: .bold))
            Spacer(minLength: 8)
            Text("\(Text("Event Passport")) · \(scope.chipLabel)")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .frame(width: cardWidth)
    }
}

/// One of the Passport's cards as a picture, to save or send — opened from
/// the Share on the card, and presented by the Passport, which hands it the
/// card as it stands (`content`).
///
/// The preview is the picture itself, so what is saved is what was seen. It
/// is drawn as the sheet opens and again whenever `drawing` changes — a sync
/// landing, the exchange rates arriving — and Save Image and Share stay off
/// until the file matches, as the ticket stub's do.
struct PassportShareSheet<Card: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let card: PassportCard
    let scope: PassportScope
    /// What the card is drawn from.
    let drawing: AnyHashable
    /// The card's map, where it has one.
    let map: PassportMapPicture.Request?
    /// The card, handed its map as a picture where it has one.
    @ViewBuilder let content: (PassportMapPicture?) -> Card

    @State private var drawn: Drawn?
    /// Counted up as each save lands, for the tap and the word that say so.
    @State private var saves = 0

    private struct Key: Hashable {
        let drawing: AnyHashable
        let scheme: ColorScheme
    }

    private struct Drawn {
        let key: Key
        let image: UIImage
        let file: URL
    }

    private static var files: PictureFolder { PictureFolder(name: "Passport Cards") }

    var body: some View {
        let key = Key(drawing: drawing, scheme: colorScheme)
        VStack(spacing: 0) {
            header
            preview
                .savedToPhotosNote(saves: saves)
            PictureFileButtons(file: drawn?.key == key ? drawn?.file : nil, saves: $saves)
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 18)
        }
        .washBackground()
        .task(id: key) { await draw(key) }
        // Before the first picture is written, so only this sheet's is kept.
        .onAppear { Self.files.discardAll() }
        .onDisappear {
            if let drawn { Self.files.discard(drawn.file) }
        }
        .opensFromOutside()
    }

    private var header: some View {
        ZStack {
            Text(card.title)
                .font(.system(size: 17, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, 56)
            HStack {
                CloseButton { dismiss() }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
    }

    /// The picture as it will be saved, scaled down to fit the sheet — never
    /// up past its own size.
    private var preview: some View {
        GeometryReader { proxy in
            if let image = drawn?.image {
                let room = CGSize(width: proxy.size.width - 48, height: proxy.size.height - 24)
                let fit = max(0.1, min(1, room.width / image.size.width, room.height / image.size.height))
                let shape = RoundedRectangle(cornerRadius: 22 * fit, style: .continuous)
                Image(uiImage: image)
                    .resizable()
                    .frame(width: image.size.width * fit, height: image.size.height * fit)
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(Color.panelRim, lineWidth: 1) }
                    .shadow(color: .black.opacity(0.14), radius: 18, y: 10)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .accessibilityLabel(Text(card.title))
            } else {
                ProgressView()
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    /// Draws the picture for `key` and writes it to a file, throwing away the
    /// one it replaces.
    private func draw(_ key: Key) async {
        var picture: PassportMapPicture?
        if let map {
            picture = await PassportMapPicture.take(map, scheme: key.scheme)
            guard !Task.isCancelled else { return }
        }
        guard let image = PassportCardImage.render(content(picture), scope: scope, scheme: key.scheme),
              let file = try? await Self.files.write(image, named: fileName)
        else { return }
        guard !Task.isCancelled else {
            Self.files.discard(file)
            return
        }
        if let drawn { Self.files.discard(drawn.file) }
        drawn = Drawn(key: key, image: image, file: file)
    }

    /// "Lottery Entries 2025", "Events All Time".
    private var fileName: String {
        let slice = switch scope {
        case .allTime: String(localized: "All Time")
        case .year(let year): String(year)
        }
        return ImageCache.fileName("\(String(localized: card.title)) \(slice)")
    }
}
