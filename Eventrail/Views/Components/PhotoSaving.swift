import SwiftUI
import Photos

/// Why a picture did not reach the reader's photos.
enum PhotoSaveFailure: Error {
    /// The reader has said no, here or in Settings.
    case notAllowed
    case failed(String)
}

/// Adds a picture to the reader's photos — an event's flyer, a ticket stub, a
/// Passport card — asking for leave to add, and only to add, the first time.
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

/// A folder of its own in the temporary directory that pictures made to be
/// kept or sent — a ticket stub, a Passport card — are written into as PNG
/// files: a file the share sheet can compose its own preview of, and Photos
/// can be handed as it is.
nonisolated struct PictureFolder: Sendable {
    let name: String

    /// Writes `image` as a PNG named `name`, in a folder of its own under
    /// this one.
    @concurrent
    func write(_ image: UIImage, named name: String) async throws -> URL {
        guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        let folder = folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "\(name).png", directoryHint: .notDirectory)
        try data.write(to: file, options: .atomic)
        return file
    }

    /// Throws away a file ``write(_:named:)`` made, with its folder.
    func discard(_ file: URL) {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    /// Throws away every file ``write(_:named:)`` has made here — what a
    /// screen closed by the app being quit left behind.
    func discardAll() {
        try? FileManager.default.removeItem(at: folder)
    }

    private var folder: URL {
        URL.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
    }
}

/// Save Image and Share, side by side, for a picture written to `file` — the
/// ticket stub's and a Passport card's. Both are greyed until there is a
/// file; each save that lands counts `saves` up, for
/// ``View/savedToPhotosNote(saves:)`` to say so.
struct PictureFileButtons: View {
    let file: URL?
    @Binding var saves: Int

    @State private var saveFailure: PhotoSaveFailure?

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { await save() }
            } label: {
                Label("Save Image", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.primary)
            .disabled(file == nil)
            shareButton
        }
        .font(.system(size: 16, weight: .semibold))
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
        .photoSaveFailureAlert("Couldn't Save the Image", failure: $saveFailure)
    }

    /// The share sheet, handed the file — once it is there, and greyed until
    /// then.
    @ViewBuilder
    private var shareButton: some View {
        let label = Label("Share", systemImage: "square.and.arrow.up")
            .frame(maxWidth: .infinity)
        Group {
            if let file {
                ShareLink(item: file) { label }
            } else {
                Button {} label: { label }
                    .disabled(true)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.brandTint)
    }

    /// Adds the picture to the reader's photos — see ``PhotoSaving``.
    private func save() async {
        guard let file else { return }
        do {
            try await PhotoSaving.add(file)
            saves += 1
        } catch {
            saveFailure = error
        }
    }
}

extension View {
    /// Says why a picture could not be saved, titled `title` — with a way to
    /// Settings where the reader has said no.
    func photoSaveFailureAlert(_ title: LocalizedStringKey, failure: Binding<PhotoSaveFailure?>) -> some View {
        modifier(PhotoSaveFailureAlert(title: title, failure: failure))
    }

    /// "Saved to Photos" over the top of this for a moment, with the tap that
    /// says so, each time `saves` counts up — see ``PictureFileButtons``.
    func savedToPhotosNote(saves: Int) -> some View {
        modifier(SavedToPhotosNote(saves: saves))
    }
}

private struct SavedToPhotosNote: ViewModifier {
    let saves: Int

    @State private var isShowing = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isShowing { note }
            }
            .task(id: saves) {
                guard saves > 0 else { return }
                isShowing = true
                try? await Task.sleep(for: .seconds(1.8))
                guard !Task.isCancelled else { return }
                isShowing = false
            }
            .animation(.snappy, value: isShowing)
            .sensoryFeedback(.success, trigger: saves)
    }

    private var note: some View {
        Label("Saved to Photos", systemImage: "checkmark")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(Color(red: 28 / 255, green: 26 / 255, blue: 34 / 255).opacity(0.86), in: .capsule)
            .shadow(color: Color(red: 20 / 255, green: 18 / 255, blue: 30 / 255).opacity(0.2), radius: 10, y: 8)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
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
