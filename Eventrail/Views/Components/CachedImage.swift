import SwiftUI

/// `AsyncImage`, drawn through ``ImageCache`` so an image downloaded once is
/// never downloaded again for as long as it has not changed.
///
/// Starts filled in wherever the image is already decoded in memory, so a row
/// scrolled back into view does not flash its placeholder for a frame first.
///
/// Reads ``EnvironmentValues/imagesCheckedSince``, so a screen refreshed by
/// hand has every flyer on it asked about again as it draws.
struct CachedImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.imagesCheckedSince) private var checkedSince

    @State private var image: UIImage?
    /// Which address ``image`` is a picture of, so a view handed a different
    /// one drops the old picture rather than showing it under the new address.
    @State private var shownURL: URL?

    init(url: URL?,
         @ViewBuilder content: @escaping (Image) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap(ImageCache.shared.memoryImage(for:)))
        _shownURL = State(initialValue: url)
    }

    /// What the image is loaded for: the address, and the last refresh by
    /// hand it has to be at least as fresh as.
    private struct Load: Equatable {
        let url: URL?
        let checkedSince: Date?
    }

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: Load(url: url, checkedSince: checkedSince)) {
            guard let url else {
                image = nil
                return
            }
            if shownURL != url {
                image = ImageCache.shared.memoryImage(for: url)
                shownURL = url
            }
            // Kept rather than blanked while a new copy of the same image is
            // on its way, and kept when none comes: the old flyer beats a
            // placeholder.
            if let loaded = await ImageCache.shared.image(for: url, checkedSince: checkedSince) {
                image = loaded
            }
        }
    }
}
