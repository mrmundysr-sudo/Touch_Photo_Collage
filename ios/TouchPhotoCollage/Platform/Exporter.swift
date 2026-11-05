import Foundation
import UIKit
import UniformTypeIdentifiers
import os

enum ExportFormat: String, CaseIterable {
    case jpeg, png
    var ext: String { self == .jpeg ? "jpg" : "png" }
    var type: UTType { self == .jpeg ? .jpeg : .png }
    var mime: String { self == .jpeg ? "image/jpeg" : "image/png" }
}

enum ExportQuality: CaseIterable {
    case standard, maximum
    var label: String { self == .standard ? "Standard" : "Maximum" }
    var longSide: Int { self == .standard ? 2048 : 4800 }
    var jpegQuality: Int { self == .standard ? 90 : 100 }
}

struct ExportRequest: Equatable {
    var format = ExportFormat.jpeg
    var quality = ExportQuality.standard
    /// Only honoured for PNG with a transparent background.
    var transparent = false
}

struct ExportResult: Equatable {
    var width: Int
    var height: Int
    var bytes: Int64
}

/// Chooses output pixel dimensions. Pure so it can be tested; the memory budget keeps low-RAM devices alive.
enum ExportSizing {
    /// Bytes we allow the final bitmap to use (RGBA = 4 bytes/px).
    static func budgetBytes(availableMemory: Int64) -> Int64 { max(Int64(Double(availableMemory) * 0.36), 24 * 1024 * 1024) }

    static func size(_ spec: CanvasSpec, quality: ExportQuality, budgetBytes: Int64) -> (Int, Int) {
        var long = quality.longSide
        while true {
            let (w, h) = LayoutEngine.sizeForLongSide(spec, longSide: long)
            if Int64(w) * Int64(h) * 4 <= budgetBytes || long <= 1024 { return (w, h) }
            long = Int(Double(long) * 0.9)
        }
    }

    /// Memory the process may still use. Falls back to a quarter of physical memory where the OS does not say.
    static func availableMemory() -> Int64 {
        let avail = Int64(os_proc_available_memory())
        return avail > 0 ? avail : Int64(ProcessInfo.processInfo.physicalMemory / 4)
    }
}

final class Exporter: @unchecked Sendable {
    private let mediaDir: URL

    init(mediaDir: URL) { self.mediaDir = mediaDir }

    func sizeFor(_ project: CollageProject, _ quality: ExportQuality) -> (Int, Int) {
        ExportSizing.size(project.canvas, quality: quality, budgetBytes: ExportSizing.budgetBytes(availableMemory: ExportSizing.availableMemory()))
    }

    /// Render and encode once; the pixels are encoded exactly one time so nothing is recompressed.
    func export(_ project: CollageProject, _ req: ExportRequest, to url: URL) throws -> ExportResult {
        let (w, h) = sizeFor(project, req.quality)
        let keepAlpha = req.format == .png && req.transparent && project.background.type == .transparent
        let renderer = CollageRenderer(provider: FileImageProvider(mediaDir: mediaDir, cacheBytes: 0))
        guard let image = renderer.render(project, width: w, height: h, options: .init(keepTransparent: keepAlpha)) else {
            throw ExportError.renderFailed
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            let bytes = try ImageIOUtil.write(image, to: url, as: req.format.type, quality: Double(req.quality.jpegQuality) / 100)
            return ExportResult(width: image.width, height: image.height, bytes: bytes)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// Writes to the private caches folder (cleared first) and returns the file for the share sheet / Photos.
    func prepareFile(_ project: CollageProject, _ req: ExportRequest) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shared", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(Exporter.fileName(project, req))
        _ = try export(project, req, to: url)
        return url
    }

    static func fileName(_ p: CollageProject, _ req: ExportRequest) -> String {
        var base = ""
        var lastUnderscore = false
        for ch in p.name {
            let ok = ch.isASCII && (ch.isLetter || ch.isNumber || ch == "." || ch == "-")
            if ok { base.append(ch); lastUnderscore = false } else if !lastUnderscore { base.append("_"); lastUnderscore = true }
        }
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if base.isEmpty { base = "collage" }
        return "\(base.prefix(40))_\(Int(Date().timeIntervalSince1970 * 1000)).\(req.format.ext)"
    }
}
