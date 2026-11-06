import AppKit
import Foundation
import LiveWallpaperCore

/// w4: macOS drops folder permissions when a build signed outside Apple's program is replaced,
/// so the chosen folders are remembered and relinked on the first launch of each new build.
enum W4FolderMemory {
    private static let libraryKey = "W4.LibraryPath"
    private static let assetsKey = "W4.AssetsPath"
    private static let buildKey = "W4.LastBuildStamp"

    static var libraryPath: String? {
        get { UserDefaults.appScoped().string(forKey: libraryKey) }
        set { UserDefaults.appScoped().set(newValue, forKey: libraryKey) }
    }

    static var assetsPath: String? {
        get { UserDefaults.appScoped().string(forKey: assetsKey) }
        set { UserDefaults.appScoped().set(newValue, forKey: assetsKey) }
    }

    nonisolated(unsafe) private static var skipped: [String] = []

    /// A project the import passed over, named by the title in its project.json.
    static func noteSkipped(folder: URL, reason: String) {
        var name = folder.lastPathComponent
        if let data = try? Data(contentsOf: folder.appendingPathComponent("project.json")),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let title = object["title"] as? String, !title.isEmpty {
            name = title
        }
        skipped.append("\(name): \(reason)")
        Logger.warning("Import skipped \(name) in \(folder.path(percentEncoded: false)): \(reason)", category: .workshop)
    }

    static func takeSkippedNote() -> String? {
        defer { skipped = [] }
        guard !skipped.isEmpty else { return nil }
        let shown = skipped.prefix(3).joined(separator: " · ")
        return skipped.count > 3 ? "\(shown) · +\(skipped.count - 3)" : shown
    }

    private static var buildStamp: String {
        let url = Bundle.main.executableURL
        let date = url.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        return "\(date?.timeIntervalSince1970 ?? 0)"
    }

    @MainActor
    static func relinkAfterNewBuild(library: @escaping @MainActor (URL) async -> Void, assets: @MainActor (URL) -> Bool) async {
        let stamp = buildStamp
        guard UserDefaults.appScoped().string(forKey: buildKey) != stamp else { return }
        UserDefaults.appScoped().set(stamp, forKey: buildKey)
        if let path = assetsPath {
            let ok = assets(URL(fileURLWithPath: path, isDirectory: true))
            Logger.info("Relinked engine assets after a new build: \(ok)", category: .workshop)
        }
        if let path = libraryPath {
            await library(URL(fileURLWithPath: path, isDirectory: true))
            Logger.info("Relinked Steam library after a new build", category: .workshop)
        }
    }
}
