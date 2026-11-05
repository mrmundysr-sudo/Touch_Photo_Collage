import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// A picked photo copied to a private temporary file (so very large originals never sit in memory).
struct PickedImage: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let dest = IncomingFiles.directory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedImage(url: dest)
        }
    }
}

/// Presents the system photo picker (out of process: it needs no photo-library permission and the app never sees
/// photos the user does not choose) and hands the chosen files back as private temporary copies.
struct PhotoPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    var maxCount: Int
    var onLoading: (Bool) -> Void
    var onPicked: ([URL], _ failed: Int) -> Void
    @State private var selection: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresented, selection: $selection, maxSelectionCount: max(1, maxCount), matching: .images)
            .onChange(of: selection) { items in
                guard !items.isEmpty else { return }
                selection = []
                onLoading(true)
                Task {
                    var urls: [URL] = []
                    var failed = 0
                    for item in items {
                        if let picked = try? await item.loadTransferable(type: PickedImage.self) { urls.append(picked.url) } else { failed += 1 }
                    }
                    onLoading(false)
                    onPicked(urls, failed)
                }
            }
    }
}

extension View {
    func photoPicker(isPresented: Binding<Bool>, maxCount: Int, onLoading: @escaping (Bool) -> Void, onPicked: @escaping ([URL], Int) -> Void) -> some View {
        modifier(PhotoPickerModifier(isPresented: isPresented, maxCount: maxCount, onLoading: onLoading, onPicked: onPicked))
    }
}
