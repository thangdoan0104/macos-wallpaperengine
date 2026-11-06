import AppKit
import Darwin
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

    private static let windockSteam = "Library/Application Support/WinDock/Gaming/Runtime.app/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Steam"

    /// The sandbox maps homeDirectoryForCurrentUser into the container, so take the real home from the account record.
    private static var realHome: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
    }

    private static func hasWorkshopItems(_ root: String) -> Bool {
        let content = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent("steamapps/workshop/content/431960")
        return !((try? FileManager.default.contentsOfDirectory(atPath: content.path)) ?? []).isEmpty
    }

    /// WinDock's Steam wins unless the remembered folder really holds Workshop items.
    private static var preferredLibraryPath: String? {
        if let stored = libraryPath, hasWorkshopItems(stored) { return stored }
        let windock = realHome.appendingPathComponent(windockSteam, isDirectory: true).path
        return hasWorkshopItems(windock) ? windock : libraryPath
    }

    private static var preferredAssetsPath: String? {
        if let stored = assetsPath { return stored }
        let windock = realHome.appendingPathComponent(windockSteam, isDirectory: true)
            .appendingPathComponent("steamapps/common/wallpaper_engine", isDirectory: true)
        return FileManager.default.fileExists(atPath: windock.appendingPathComponent("assets").path) ? windock.path : nil
    }

    /// Reads everything from local folders; nothing here touches the network.
    @MainActor
    static func relinkAfterNewBuild(
        currentLibraryPath: String?,
        library: @escaping @MainActor (URL) async -> Void,
        assets: @MainActor (URL) -> Bool
    ) async {
        let stamp = buildStamp
        let newBuild = UserDefaults.appScoped().string(forKey: buildKey) != stamp
        UserDefaults.appScoped().set(stamp, forKey: buildKey)
        if newBuild || assetsPath == nil, let path = preferredAssetsPath {
            let ok = assets(URL(fileURLWithPath: path, isDirectory: true))
            Logger.info("Linked engine assets: \(ok)", category: .workshop)
        }
        if let path = preferredLibraryPath, newBuild || path != currentLibraryPath {
            await library(URL(fileURLWithPath: path, isDirectory: true))
            Logger.info("Linked Steam library", category: .workshop)
        }
    }
}
