import Foundation

struct ImportException: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Copies a picked photo into private app storage (read-only use of the source; the original is never opened for
/// writing). Working from a private copy keeps projects re-openable no matter what happens to the picker's file.
final class ImageImporter: @unchecked Sendable {
    private let mediaDir: URL
    private let fm = FileManager.default

    init(mediaDir: URL) {
        self.mediaDir = mediaDir
        try? fm.createDirectory(at: mediaDir, withIntermediateDirectories: true)
    }

    func importFile(at source: URL) throws -> PhotoRef {
        let id = UUID().uuidString.lowercased()
        let name = "\(id).img"
        let tmp = mediaDir.appendingPathComponent("\(name).tmp")
        let dest = mediaDir.appendingPathComponent(name)
        do {
            try? fm.removeItem(at: tmp)
            try fm.copyItem(at: source, to: tmp)
            guard let info = ImageIOUtil.info(at: tmp) else { throw ImportException(message: "Not a readable image") }
            try fm.moveItem(at: tmp, to: dest)
            return PhotoRef(id: id, file: name, width: info.width, height: info.height, exif: info.exif)
        } catch let e as ImportException {
            try? fm.removeItem(at: tmp)
            throw e
        } catch {
            try? fm.removeItem(at: tmp)
            throw ImportException(message: "Could not import photo: \(error.localizedDescription)")
        }
    }
}
