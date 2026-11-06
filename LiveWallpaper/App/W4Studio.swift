#if !LITE_BUILD
import AVFoundation
import AppKit
import CryptoKit
import Darwin
import Foundation
import ImageIO
import LiveWallpaperCore
import Observation
import UniformTypeIdentifiers

// MARK: - Catalog

struct W4Game: Identifiable, Hashable, Sendable {
    let name: String
    let query: String
    /// Read from the old app's folder on this Mac; this art can't ship in a public repository.
    var usesLocalArt = false
    var id: String { name }
}

enum W4GameCatalog {
    static let all: [W4Game] = [
        W4Game(name: "Elden Ring", query: "Elden Ring"),
        W4Game(name: "Delta Force", query: "Delta Force", usesLocalArt: true),
        W4Game(name: "Black Myth: Wukong", query: "Black Myth: Wukong"),
        W4Game(name: "Genshin Impact", query: "Genshin Impact"),
        W4Game(name: "Honkai: Star Rail", query: "Honkai: Star Rail"),
        W4Game(name: "League of Legends", query: "League of Legends"),
        W4Game(name: "Valorant", query: "Valorant"),
        W4Game(name: "Dota 2", query: "Dota 2"),
        W4Game(name: "Counter-Strike", query: "Counter-Strike"),
        W4Game(name: "Overwatch", query: "Overwatch"),
        W4Game(name: "Apex Legends", query: "Apex Legends"),
        W4Game(name: "Cyberpunk 2077", query: "Cyberpunk 2077"),
        W4Game(name: "The Witcher 3", query: "The Witcher 3"),
        W4Game(name: "Red Dead Redemption 2", query: "Red Dead Redemption 2"),
        W4Game(name: "GTA V", query: "Grand Theft Auto V"),
        W4Game(name: "God of War", query: "God of War"),
        W4Game(name: "Dark Souls", query: "Dark Souls"),
        W4Game(name: "Sekiro", query: "Sekiro: Shadows Die Twice"),
        W4Game(name: "Hollow Knight", query: "Hollow Knight"),
        W4Game(name: "Minecraft", query: "Minecraft"),
        W4Game(name: "The Legend of Zelda", query: "The Legend of Zelda"),
        W4Game(name: "Final Fantasy VII", query: "Final Fantasy VII"),
        W4Game(name: "Arknights", query: "Arknights"),
    ]
}

struct W4WallhavenItem: Decodable, Sendable {
    struct Thumbs: Decodable, Sendable { let large: String }
    let id: String
    let url: String
    let path: String
    let resolution: String
    let source: String?
    let thumbs: Thumbs
}

struct W4WallhavenPage: Decodable, Sendable {
    struct Meta: Decodable, Sendable {
        let current_page: Int
        let last_page: Int
    }
    let data: [W4WallhavenItem]
    let meta: Meta
}

enum W4WallhavenClient {
    /// Safe-for-work results only, with no API key.
    static func search(query: String, page: Int) async throws -> W4WallhavenPage {
        var components = URLComponents(string: "https://wallhaven.cc/api/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "categories", value: "110"),
            URLQueryItem(name: "purity", value: "100"),
            URLQueryItem(name: "sorting", value: "favorites"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "atleast", value: "1920x1080"),
            URLQueryItem(name: "ratios", value: "landscape"),
            URLQueryItem(name: "page", value: String(page)),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("w4llpapr/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(W4WallhavenPage.self, from: data)
    }

    static func download(_ remote: URL) async throws -> URL {
        var request = URLRequest(url: remote)
        request.setValue("w4llpapr/1.0", forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        // The system removes its download file when this returns, so it moves somewhere that lasts.
        let kept = FileManager.default.temporaryDirectory
            .appendingPathComponent("w4-\(UUID().uuidString)")
            .appendingPathExtension(remote.pathExtension)
        try FileManager.default.moveItem(at: temporary, to: kept)
        return kept
    }
}

// MARK: - The old app's files

/// Reads what the old w4llpapr left on this Mac. Reads only; its files are never changed.
enum W4Legacy {
    private static var artFolders: [URL] {
        ["LiveWall/Resources/DeltaForceArt", "Downloads/LiveWall/Resources/DeltaForceArt"].map {
            W4FolderMemory.realHome.appendingPathComponent($0, isDirectory: true)
        }
    }

    static var artFolder: URL? {
        artFolders.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("credits.json").path) }
    }

    static func artFiles() -> [(file: URL, thumb: URL, artist: String, page: URL?)] {
        guard let folder = artFolder,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        var credits: [String: [String: String]] = [:]
        if let data = try? Data(contentsOf: folder.appendingPathComponent("credits.json")),
           let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            credits = decoded
        }
        return names.filter { $0.lowercased().hasSuffix(".jpg") }.sorted().map { name in
            let file = folder.appendingPathComponent(name)
            let thumb = folder.appendingPathComponent("thumbs/\(name)")
            let hasThumb = FileManager.default.fileExists(atPath: thumb.path)
            return (file, hasThumb ? thumb : file, credits[name]?["artist"] ?? "", credits[name]?["url"].flatMap(URL.init(string:)))
        }
    }

    /// Images and videos the old app downloaded or was given.
    static func wallpaperFiles() -> [URL] {
        let root = W4FolderMemory.realHome.appendingPathComponent("Library/Application Support/LiveWall/Wallpapers", isDirectory: true)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker where W4ProjectStore.allowedExtensions.contains(url.pathExtension.lowercased()) {
            found.append(url)
        }
        return found.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The first display's look in the old app, in this page's property units.
    static func defaultValues() -> [String: Any] {
        let plist = W4FolderMemory.realHome.appendingPathComponent("Library/Preferences/local.livewall.app.plist")
        guard let data = try? Data(contentsOf: plist),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let saved = root["settingsV2"] as? Data,
              let settings = try? JSONSerialization.jsonObject(with: saved) as? [String: Any],
              let old = (settings["screens"] as? [String: [String: Any]])?.values.first else { return [:] }
        var values: [String: Any] = [:]
        func percent(_ from: String, _ to: String) {
            if let number = old[from] as? Double { values[to] = (number * 100).rounded() }
        }
        func plain(_ from: String, _ to: String) {
            if let value = old[from] { values[to] = value }
        }
        func color(_ from: String, _ to: String) {
            if let hex = old[from] as? String, let triple = W4ProjectStore.colorTriple(hex: hex) { values[to] = triple }
        }
        percent("brightness", "brightness")
        percent("contrast", "contrast")
        percent("saturation", "saturation")
        plain("blur", "blur")
        color("tintHex", "tint")
        percent("tintOpacity", "tintopacity")
        plain("motionOn", "motionon")
        percent("motionAmount", "motionamount")
        plain("motionSeconds", "motionseconds")
        plain("particlesOn", "particleson")
        plain("particlePreset", "particlepreset")
        color("particleHex", "particlecolor")
        percent("particleDensity", "particledensity")
        percent("particleSpeed", "particlespeed")
        percent("particleSize", "particlesize")
        if let fit = old["fit"] as? String {
            values["fit"] = ["fill": "cover", "fit": "contain", "stretch": "fill", "center": "none"][fit] ?? "cover"
        }
        return values
    }
}

// MARK: - Projects

struct W4Project: Identifiable, Hashable, Sendable {
    let id: String
    let folder: URL
    let title: String
    let game: String
    let kind: String
    let mediaName: String
    let source: String

    var mediaURL: URL { folder.appendingPathComponent(mediaName) }
    var previewURL: URL { folder.appendingPathComponent("preview.jpg") }
    var isVideo: Bool { kind == "video" }
}

enum W4ProjectError: LocalizedError {
    case unreadableMedia

    var errorDescription: String? {
        "Không đọc được hình hoặc video này."
    }
}

/// Each image or video becomes a Wallpaper Engine web project on disk, and goes through the normal import.
enum W4ProjectStore {
    static let allowedExtensions = ["jpg", "jpeg", "png", "heic", "webp", "mp4", "mov", "m4v"]
    private static let videoExtensions = ["mp4", "mov", "m4v"]

    static var root: URL {
        ConfigurationDirectory().root.appendingPathComponent("W4Projects", isDirectory: true)
    }

    static func projectID(source: String) -> String {
        let digest = SHA256.hash(data: Data(source.utf8))
        return "w4-" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func colorTriple(hex: String) -> String? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        func part(_ shift: UInt32) -> String {
            String(format: "%.3f", Double((value >> shift) & 255) / 255)
        }
        return "\(part(16)) \(part(8)) \(part(0))"
    }

    private static func read(folder: URL) -> W4Project? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("w4.json")),
              let info = try? JSONDecoder().decode([String: String].self, from: data),
              let media = info["media"], let kind = info["kind"] else { return nil }
        return W4Project(
            id: folder.lastPathComponent, folder: folder, title: info["title"] ?? folder.lastPathComponent,
            game: info["game"] ?? "", kind: kind, mediaName: media, source: info["source"] ?? ""
        )
    }

    static func existing(source: String) -> W4Project? {
        read(folder: root.appendingPathComponent(projectID(source: source), isDirectory: true))
    }

    static func list() -> [W4Project] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let folders = names.map { root.appendingPathComponent($0, isDirectory: true) }
        func date(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return folders.sorted { date($0) > date($1) }.compactMap(read(folder:))
    }

    static func remove(_ project: W4Project) {
        try? FileManager.default.trashItem(at: project.folder, resultingItemURL: nil)
    }

    /// `movingMedia` consumes a temporary download; anything else is copied and its original stays put.
    static func build(media: URL, title: String, game: String, source: String, movingMedia: Bool = false) async throws -> W4Project {
        let fileManager = FileManager.default
        let folder = root.appendingPathComponent(projectID(source: source), isDirectory: true)
        let ext = media.pathExtension.lowercased()
        let kind = videoExtensions.contains(ext) ? "video" : "image"
        let mediaName = "media.\(ext.isEmpty ? "jpg" : ext)"

        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(mediaName)
        try? fileManager.removeItem(at: target)
        if movingMedia {
            try fileManager.moveItem(at: media, to: target)
        } else {
            try fileManager.copyItem(at: media, to: target)
        }
        guard let preview = await previewImage(of: target, kind: kind) else {
            try? fileManager.removeItem(at: folder)
            throw W4ProjectError.unreadableMedia
        }
        try writeJPEG(preview, to: folder.appendingPathComponent("preview.jpg"))

        let values = W4Legacy.defaultValues()
        let manifest: [String: Any] = [
            "title": title,
            "type": "web",
            "file": "index.html",
            "preview": "preview.jpg",
            "general": ["properties": properties(kind: kind, values: values)],
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.appendingPathComponent("project.json"), options: .atomic)
        let config: [String: Any] = ["kind": kind, "src": mediaName, "props": values]
        let configData = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        var configScript = Data("window.W4=".utf8)
        configScript.append(configData)
        configScript.append(Data(";".utf8))
        try configScript.write(to: folder.appendingPathComponent("config.js"), options: .atomic)
        try Data(W4WallpaperPage.html.utf8).write(to: folder.appendingPathComponent("index.html"), options: .atomic)
        let info = ["title": title, "game": game, "kind": kind, "media": mediaName, "source": source]
        try JSONEncoder().encode(info).write(to: folder.appendingPathComponent("w4.json"), options: .atomic)
        return W4Project(id: folder.lastPathComponent, folder: folder, title: title, game: game, kind: kind, mediaName: mediaName, source: source)
    }

    private static func previewImage(of url: URL, kind: String) async -> CGImage? {
        if kind == "video" {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 960, height: 960)
            return try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 960,
        ] as CFDictionary)
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw W4ProjectError.unreadableMedia
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw W4ProjectError.unreadableMedia }
    }

    /// The settings shown on the wallpaper's own page, as Wallpaper Engine project properties.
    private static func properties(kind: String, values: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        var order = 0.0
        func add(_ key: String, _ fields: [String: Any], fallback: Any? = nil) {
            order += 1
            var entry = fields
            entry["order"] = order
            if let value = values[key] ?? fallback { entry["value"] = value }
            result[key] = entry
        }
        func group(_ key: String, _ text: String) {
            add(key, ["type": "group", "text": text])
        }
        func slider(_ key: String, _ text: String, _ low: Double, _ high: Double, _ value: Double, condition: String? = nil) {
            var fields: [String: Any] = ["type": "slider", "text": text, "min": low, "max": high, "step": 1]
            if let condition { fields["condition"] = condition }
            add(key, fields, fallback: value)
        }
        func combo(_ key: String, _ text: String, _ options: [(String, String)], _ value: String, condition: String? = nil) {
            var fields: [String: Any] = [
                "type": "combo", "text": text,
                "options": options.map { ["label": $0.0, "value": $0.1] },
            ]
            if let condition { fields["condition"] = condition }
            add(key, fields, fallback: value)
        }
        func toggle(_ key: String, _ text: String, _ value: Bool) {
            add(key, ["type": "bool", "text": text], fallback: value)
        }
        func color(_ key: String, _ text: String, _ value: String, condition: String? = nil) {
            var fields: [String: Any] = ["type": "color", "text": text]
            if let condition { fields["condition"] = condition }
            add(key, fields, fallback: value)
        }

        group("grouplook", "Hình")
        combo("fit", "Cách hiển thị", [("Phủ kín màn", "cover"), ("Vừa khung", "contain"), ("Kéo giãn", "fill"), ("Giữ nguyên, căn giữa", "none")], "cover")
        slider("brightness", "Độ sáng", -60, 40, 0)
        slider("contrast", "Tương phản", 50, 160, 100)
        slider("saturation", "Độ đậm màu", 0, 200, 100)
        slider("blur", "Làm mờ", 0, 40, 0)
        color("tint", "Màu phủ", "0 0 0")
        slider("tintopacity", "Độ đậm màu phủ", 0, 80, 0)
        if kind == "video" {
            group("groupvideo", "Video")
            slider("videospeed", "Tốc độ phát", 25, 200, 100)
            slider("videovolume", "Âm lượng", 0, 100, 0)
        } else {
            group("groupmotion", "Chuyển động của ảnh")
            toggle("motionon", "Hình trôi chậm", true)
            slider("motionamount", "Biên độ", 10, 100, 50, condition: "motionon.value")
            slider("motionseconds", "Một lượt (giây)", 10, 120, 45, condition: "motionon.value")
        }
        group("groupparticles", "Hạt")
        toggle("particleson", "Hiện hạt", true)
        combo("particlepreset", "Kiểu", [("Tàn lửa bay lên", "embers"), ("Tuyết rơi", "snow"), ("Đom đóm", "fireflies"), ("Bụi sáng", "dust")], "embers", condition: "particleson.value")
        color("particlecolor", "Màu hạt", "1 0.878 0.702", condition: "particleson.value")
        slider("particledensity", "Mật độ", 20, 400, 100, condition: "particleson.value")
        slider("particlespeed", "Tốc độ", 20, 300, 100, condition: "particleson.value")
        slider("particlesize", "Kích thước", 30, 300, 100, condition: "particleson.value")
        group("groupmusic", "Theo nhạc")
        toggle("pulseon", "Hình nhún theo nhịp", false)
        slider("pulseamount", "Độ nhún", 20, 300, 100, condition: "pulseon.value")
        return result
    }
}

// MARK: - Menu bar mark

/// The old app's menu bar mark; macOS tints a template image to match the bar.
@MainActor
enum W4MenuBarMark {
    static let image: NSImage = {
        let glyphW = ["10001", "10001", "10001", "10101", "10101", "11011", "10001"]
        let glyph4 = ["00010", "00110", "01010", "10010", "11111", "00010", "00010"]
        let shift = [1: 1, 2: 1, 5: -1]
        let height: CGFloat = 14
        let cell = height / 7
        let result = NSImage(size: NSSize(width: cell * 12, height: height))
        result.lockFocusFlipped(true)
        NSColor.black.setFill()
        for y in 0 ..< 7 {
            for (x, value) in (glyphW[y] + "0" + glyph4[y]).enumerated() where value == "1" {
                NSRect(x: CGFloat(x + (shift[y] ?? 0) + 1) * cell, y: CGFloat(y) * cell, width: cell, height: cell).fill()
            }
        }
        result.unlockFocus()
        result.isTemplate = true
        return result
    }()
}

enum W4FontLoader {
    /// The lyric font picker lists these once they are registered for this process.
    static func registerBundledFonts() {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "W4Fonts") ?? [])
        for url in urls where ["W4Pixel-Regular", "VT323-Regular"].contains(url.deletingPathExtension().lastPathComponent) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
#endif
