import Foundation

struct ProjectSummary: Equatable, Identifiable {
    var id: String
    var name: String
    var updatedAt: Int64
    var mode: ProjectMode
    var photoCount: Int
    var thumb: URL?
}

/// File-based, app-private storage: `projects/<id>.json`, `thumbs/<id>.jpg`, `media/<photo files>`.
/// Nothing leaves this directory unless the user exports or shares.
final class ProjectStore: @unchecked Sendable {
    let root: URL
    let mediaDir: URL
    private let projectsDir: URL
    private let thumbsDir: URL
    private let fm = FileManager.default

    init(root: URL) {
        self.root = root
        mediaDir = root.appendingPathComponent("media", isDirectory: true)
        projectsDir = root.appendingPathComponent("projects", isDirectory: true)
        thumbsDir = root.appendingPathComponent("thumbs", isDirectory: true)
        for d in [mediaDir, projectsDir, thumbsDir] { try? fm.createDirectory(at: d, withIntermediateDirectories: true) }
    }

    private func file(_ id: String) -> URL { projectsDir.appendingPathComponent("\(id).json") }
    func thumbFile(_ id: String) -> URL { thumbsDir.appendingPathComponent("\(id).jpg") }

    /// Atomic write: a crash mid-save can never corrupt the previous version.
    func save(_ p: CollageProject) throws {
        let data = try ProjectJson.serialize(p)
        try data.write(to: file(p.id), options: .atomic)
    }

    func load(_ id: String) -> CollageProject? {
        guard let data = try? Data(contentsOf: file(id)) else { return nil }
        return try? ProjectJson.parseProject(data)
    }

    func saveThumb(_ id: String, jpeg: Data) {
        try? jpeg.write(to: thumbFile(id), options: .atomic)
    }

    private func projectFiles() -> [URL] {
        ((try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "json" }
    }

    /// Newest first. Unreadable files are skipped, never crash the home screen.
    func list() -> [ProjectSummary] {
        projectFiles().compactMap { f -> ProjectSummary? in
            guard let data = try? Data(contentsOf: f), let p = try? ProjectJson.parseProject(data) else { return nil }
            let t = thumbFile(p.id)
            return ProjectSummary(id: p.id, name: p.name, updatedAt: p.updatedAt, mode: p.mode, photoCount: p.photoCount, thumb: fm.fileExists(atPath: t.path) ? t : nil)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func delete(_ id: String) {
        try? fm.removeItem(at: file(id))
        try? fm.removeItem(at: thumbFile(id))
        collectGarbage()
    }

    /// Remove imported photos no remaining project refers to.
    func collectGarbage() {
        var used = Set<String>()
        for f in projectFiles() {
            guard let data = try? Data(contentsOf: f), let p = try? ProjectJson.parseProject(data) else { return } // keep everything if something is unreadable
            for c in p.cells { if let ph = c.photo { used.insert(ph.file) } }
        }
        for u in (try? fm.contentsOfDirectory(at: mediaDir, includingPropertiesForKeys: nil)) ?? [] {
            if !used.contains(u.lastPathComponent) && u.pathExtension != "tmp" { try? fm.removeItem(at: u) }
        }
    }
}

final class TemplateStore: @unchecked Sendable {
    private let file: URL

    init(root: URL) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        file = root.appendingPathComponent("templates.json")
    }

    func list() -> [SavedTemplate] {
        guard let data = try? Data(contentsOf: file),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        return arr.compactMap { ($0 as? [String: Any]).flatMap { try? ProjectJson.parseTemplate($0) } }
    }

    func add(_ t: SavedTemplate) { write(list().filter { $0.id != t.id } + [t]) }
    func delete(_ id: String) { write(list().filter { $0.id != id }) }

    private func write(_ all: [SavedTemplate]) {
        guard let data = try? JSONSerialization.data(withJSONObject: all.map { ProjectJson.toDict($0) }) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
