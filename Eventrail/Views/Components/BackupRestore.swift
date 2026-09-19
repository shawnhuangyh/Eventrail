import SwiftUI
import UniformTypeIdentifiers

/// Folds a backup file into the library, wherever the file came from.
///
/// Two screens receive one: Settings, when the reader picks a file out of the
/// document picker, and the app itself, when they tap a backup in Files and
/// choose Eventrail. What happens next is the same in both cases and belongs in
/// one place — the reading, what to say when it worked, and what to say when
/// the file turned out not to be a backup at all.
///
/// Only the asking differs. A file the reader has just chosen in a picker
/// labelled Restore needs no second question; one that arrives from outside the
/// app does, because opening a file is not the same act as asking for its
/// contents to be put back.
struct BackupRestore: ViewModifier {
    @Environment(EventStore.self) private var store

    /// The file waiting to be read, set by whoever received it and cleared
    /// here once it has been.
    @Binding var file: URL?
    /// Whether to ask before reading it.
    var asks: Bool

    @State private var report: Report?

    func body(content: Content) -> some View {
        content
            .alert("Restore this backup?", isPresented: isAsking, presenting: file) { file in
                Button("Restore") { restore(file) }
                Button("Cancel", role: .cancel) { self.file = nil }
            } message: { file in
                // Named, because the reader may well have several and this is
                // the last moment they can tell which one they tapped.
                Text("\(Text(verbatim: file.deletingPathExtension().lastPathComponent)) will be added to your library. Nothing already on this device is erased.")
            }
            .alert(report?.title ?? "", isPresented: isReporting, presenting: report) { _ in
                Button("OK", role: .cancel) {}
            } message: { report in
                report.message
            }
            .onChange(of: file) { _, file in
                // A file that needs no asking is read the moment it lands.
                if let file, !asks { restore(file) }
            }
    }

    /// Reads it, and says what it did either way. A restore that failed is told
    /// plainly — a silent one would leave the reader believing their backup is
    /// in the app when it is not.
    private func restore(_ file: URL) {
        defer { self.file = nil }
        do {
            report = Report(title: "Backup Restored", message: Self.detail(try store.restore(from: file)))
        } catch {
            report = Report(title: "Nothing Restored", message: Text(verbatim: error.localizedDescription))
        }
    }

    /// Spelled out rather than inflected: an alert's words reach UIKit as plain
    /// text, and the `^[…](inflect:)` markup arrives there unprocessed.
    private static func detail(_ restored: EventStore.RestoreSummary) -> Text {
        guard !restored.isEmpty else {
            return Text("Everything in that backup was already on this device.")
        }
        var parts: [Text] = []
        if restored.events > 0 {
            parts.append(restored.events == 1 ? Text("1 event") : Text("\(restored.events) events"))
        }
        if restored.follows > 0 {
            parts.append(restored.follows == 1 ? Text("1 performer") : Text("\(restored.follows) performers"))
        }
        if restored.records > 0 {
            parts.append(restored.records == 1 ? Text("1 tracking record")
                                               : Text("\(restored.records) tracking records"))
        }
        let list: Text = switch parts.count {
        case 1: parts[0]
        case 2: Text("\(parts[0]) and \(parts[1])")
        default: Text("\(parts[0]), \(parts[1]) and \(parts[2])")
        }
        return Text("\(list) came back. Nothing already on this device was changed.")
    }

    private var isAsking: Binding<Bool> {
        Binding { asks && file != nil } set: { if !$0 { file = nil } }
    }

    private var isReporting: Binding<Bool> {
        Binding { report != nil } set: { if !$0 { report = nil } }
    }

    /// One sentence about the last restore, kept only for as long as the alert
    /// showing it.
    private struct Report {
        var title: LocalizedStringKey
        var message: Text
    }
}

/// The document picker the reader reaches a backup through, and the reading
/// that follows it.
///
/// Two screens offer this — Settings, and the welcome's third step — and the
/// file the picker hands back is of no interest to either of them beyond
/// passing it straight on, so neither holds it any more. That also keeps the
/// one thing about the picker worth getting right in a single place: JSON is
/// allowed beside the app's own type so that a `library.json` lifted off an old
/// device can still be rescued.
///
/// No second question, on either screen: the reader picked this out of a picker
/// they opened from a row that says Restore.
struct BackupPicker: ViewModifier {
    @Binding var isPresented: Bool

    @State private var picked: URL?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented,
                          allowedContentTypes: [.eventrailBackup, .json]) { result in
                picked = try? result.get()
            }
            .restoringBackup($picked, asking: false)
    }
}

extension View {
    /// Restores whatever backup file is put into `file`.
    ///
    /// - Parameter asking: whether to confirm first. True for a file that
    ///   arrived from outside the app, false for one the reader picked here.
    func restoringBackup(_ file: Binding<URL?>, asking: Bool) -> some View {
        modifier(BackupRestore(file: file, asks: asking))
    }

    /// Opens the document picker on a backup, and reads whatever comes back.
    func choosingBackup(_ isPresented: Binding<Bool>) -> some View {
        modifier(BackupPicker(isPresented: isPresented))
    }
}
