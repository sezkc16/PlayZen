import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Picks a video file and hands back a temporary copy URL.
/// The caller (Library / Files tab) copies it into Documents via
/// `VideoLibrary.importFile(from:)` — the picker itself deletes nothing.
struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        // MKV has no built-in UTType; accept it as data so v1 can list it
        // (playback shows the honest "MKV needs v2 / VLCKit" message).
        if let mkv = UTType(filenameExtension: "mkv") { types.append(mkv) }
        else { types.append(.data) }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
