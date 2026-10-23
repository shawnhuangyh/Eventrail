import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A flyer made small, as the widgets (``WidgetFlyers``), the watch
/// (``FlyerCache``) and Spotlight (``SpotlightIndex``) each keep one: no
/// longer than they draw it on its longest side, turned upright, as a JPEG.
nonisolated enum Thumbnail {
    /// The image in `data`, at most `side` pixels on its longest side and
    /// compressed to `quality` — nil where `data` is not an image.
    static func jpeg(of data: Data, side: Int, quality: Double = 0.8) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: side,
              ] as CFDictionary)
        else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}
