import SwiftUI
import Photos

/// Why a picture did not reach the reader's photos.
enum PhotoSaveFailure: Error {
    /// The reader has said no, here or in Settings.
    case notAllowed
    case failed(String)
}

/// Adds a picture to the reader's photos — an event's flyer, a ticket stub —
/// asking for leave to add, and only to add, the first time.
enum PhotoSaving {
    /// Adds the picture at `file` as it is, byte for byte.
    static func add(_ file: URL) async throws(PhotoSaveFailure) {
        switch await PHPhotoLibrary.requestAuthorization(for: .addOnly) {
        case .authorized, .limited:
            do {
                try await PHPhotoLibrary.shared().performChanges { @Sendable in
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: file, options: nil)
                }
            } catch {
                throw .failed(error.localizedDescription)
            }
        default:
            throw .notAllowed
        }
    }
}

extension View {
    /// Says why a picture could not be saved, titled `title` — with a way to
    /// Settings where the reader has said no.
    func photoSaveFailureAlert(_ title: LocalizedStringKey, failure: Binding<PhotoSaveFailure?>) -> some View {
        modifier(PhotoSaveFailureAlert(title: title, failure: failure))
    }
}

private struct PhotoSaveFailureAlert: ViewModifier {
    let title: LocalizedStringKey
    @Binding var failure: PhotoSaveFailure?
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.alert(title,
                      isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } },
                      presenting: failure) { failure in
            if case .notAllowed = failure {
                Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK") {}
            }
        } message: { failure in
            switch failure {
            case .notAllowed: Text("Eventrail isn't allowed to add to your photos. You can allow it in Settings.")
            case .failed(let reason): Text(verbatim: reason)
            }
        }
    }
}
