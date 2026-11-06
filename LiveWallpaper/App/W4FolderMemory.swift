import AppKit
import Darwin
import Foundation
import LiveWallpaperCore
import Observation

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
        let name = title(of: folder)
        skipped.append("\(name): \(reason)")
        Logger.warning("Import skipped \(name) in \(folder.path(percentEncoded: false)): \(reason)", category: .workshop)
    }

    nonisolated(unsafe) private static var presets: [String] = []

    /// A project that registers as a variation of another scene instead of a wallpaper of its own.
    static func notePreset(folder: URL) {
        presets.append(title(of: folder))
    }

    static func takeScanNotes() -> (skipped: [String], presets: [String]) {
        defer {
            skipped = []
            presets = []
        }
        return (skipped, presets)
    }

    private static func title(of folder: URL) -> String {
        if let data = try? Data(contentsOf: folder.appendingPathComponent("project.json")),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let title = object["title"] as? String, !title.isEmpty {
            return title
        }
        return folder.lastPathComponent
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

    /// WinDock's Steam is where new items land, so it wins whenever it holds Workshop items.
    private static var preferredLibraryPath: String? {
        let windock = realHome.appendingPathComponent(windockSteam, isDirectory: true).path
        return hasWorkshopItems(windock) ? windock : libraryPath
    }

    /// The library reachable through the App Support entitlement alone, for when no bookmark grant survives.
    static var directlyReadableLibrary: URL? {
        guard let path = preferredLibraryPath, hasWorkshopItems(path) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
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

/// What the last library scan saw, shown in Settings so a missing item has a visible reason.
@MainActor
@Observable
final class W4LibraryScanReport {
    static let shared = W4LibraryScanReport()

    var isScanning = false
    var finishedAt: Date?
    var libraryPath: String?
    var hasAccess = true
    var foldersOnDisk = 0
    var foldersWithProject = 0
    var stillDownloading = 0
    var inLibrary = 0
    var added = 0
    var relinked = 0
    var conflicts = 0
    var presets: [String] = []
    var skipped: [String] = []
    var deletedIDs: [String] = []

    /// Reads folder counts while the caller holds library access.
    func readDisk(steamRoot: URL?) {
        libraryPath = steamRoot?.path(percentEncoded: false)
        hasAccess = steamRoot != nil
        guard let steamRoot else {
            foldersOnDisk = 0
            stillDownloading = 0
            return
        }
        let workshop = steamRoot.appendingPathComponent("steamapps/workshop", isDirectory: true)
        func folderCount(_ relative: String) -> Int {
            let names = (try? FileManager.default.contentsOfDirectory(
                atPath: workshop.appendingPathComponent(relative).path
            )) ?? []
            return names.filter { !$0.hasPrefix(".") }.count
        }
        foldersOnDisk = folderCount("content/431960")
        stillDownloading = folderCount("downloads/431960")
    }

    /// Reasons not yet shown in a toast, so the recurring scan doesn't repeat them every minute.
    private var announced: Set<String> = []

    func unannounced(_ lines: [String]) -> [String] {
        lines.filter { announced.insert($0).inserted }
    }
}
