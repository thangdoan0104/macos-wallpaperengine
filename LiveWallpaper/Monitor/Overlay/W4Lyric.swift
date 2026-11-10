#if !MAS_BUILD
import AppKit
import Combine
import Foundation
import LiveWallpaperCore
import SwiftUI

// MARK: - Settings

enum W4LyricReveal: String, Codable, CaseIterable, Sendable {
    case off, fade, karaoke
}

enum W4LyricAlign: String, Codable, CaseIterable, Sendable {
    case left, center, right
}

struct W4LyricScreen: Codable, Equatable, Sendable {
    var on = true
    var floating = false
    var x = 0.5
    var y = 0.1
    /// nil follows the shared look from Settings.
    var look: W4LyricLook?
}

/// How the lyric looks; Settings holds the shared one and a display can keep its own.
struct W4LyricLook: Codable, Equatable, Sendable {
    var size = 44.0
    var bold = true
    var currentHex = "#FFFFFF"
    var nextHex = "#FFFFFF"
    var nextOpacity = 0.55
    var showNext = true
    var align = W4LyricAlign.center
    var reveal = W4LyricReveal.off
    var revealSpeed = 1.0
    var shadow = 1.0
    var widthFraction = 0.7
    var fontFamily = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? size
        bold = try c.decodeIfPresent(Bool.self, forKey: .bold) ?? bold
        currentHex = try c.decodeIfPresent(String.self, forKey: .currentHex) ?? currentHex
        nextHex = try c.decodeIfPresent(String.self, forKey: .nextHex) ?? nextHex
        nextOpacity = try c.decodeIfPresent(Double.self, forKey: .nextOpacity) ?? nextOpacity
        showNext = try c.decodeIfPresent(Bool.self, forKey: .showNext) ?? showNext
        align = try c.decodeIfPresent(W4LyricAlign.self, forKey: .align) ?? align
        reveal = try c.decodeIfPresent(W4LyricReveal.self, forKey: .reveal) ?? reveal
        revealSpeed = try c.decodeIfPresent(Double.self, forKey: .revealSpeed) ?? revealSpeed
        shadow = try c.decodeIfPresent(Double.self, forKey: .shadow) ?? shadow
        widthFraction = try c.decodeIfPresent(Double.self, forKey: .widthFraction) ?? widthFraction
        fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily) ?? fontFamily
    }
}

struct W4LyricStyle: Codable, Equatable, Sendable {
    var enabled = true
    var size = 40.0
    var bold = true
    var currentHex = "#FFFFFF"
    var nextHex = "#FFFFFF"
    var nextOpacity = 0.55
    var showNext = true
    var align = W4LyricAlign.center
    var reveal = W4LyricReveal.off
    var revealSpeed = 1.0
    var shadow = 1.0
    var widthFraction = 0.7
    var offset = 0.0
    var screens: [String: W4LyricScreen] = [:]
    var fontFamily = ""
    var favoriteFonts: [String] = []
    var recentFonts: [String] = []

    init() {}

    /// Field by field, so a setting added in a later build never wipes what is already saved.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? size
        bold = try c.decodeIfPresent(Bool.self, forKey: .bold) ?? bold
        currentHex = try c.decodeIfPresent(String.self, forKey: .currentHex) ?? currentHex
        nextHex = try c.decodeIfPresent(String.self, forKey: .nextHex) ?? nextHex
        nextOpacity = try c.decodeIfPresent(Double.self, forKey: .nextOpacity) ?? nextOpacity
        showNext = try c.decodeIfPresent(Bool.self, forKey: .showNext) ?? showNext
        align = try c.decodeIfPresent(W4LyricAlign.self, forKey: .align) ?? align
        reveal = try c.decodeIfPresent(W4LyricReveal.self, forKey: .reveal) ?? reveal
        revealSpeed = try c.decodeIfPresent(Double.self, forKey: .revealSpeed) ?? revealSpeed
        shadow = try c.decodeIfPresent(Double.self, forKey: .shadow) ?? shadow
        widthFraction = try c.decodeIfPresent(Double.self, forKey: .widthFraction) ?? widthFraction
        offset = try c.decodeIfPresent(Double.self, forKey: .offset) ?? offset
        screens = try c.decodeIfPresent([String: W4LyricScreen].self, forKey: .screens) ?? screens
        fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily) ?? fontFamily
        favoriteFonts = try c.decodeIfPresent([String].self, forKey: .favoriteFonts) ?? favoriteFonts
        recentFonts = try c.decodeIfPresent([String].self, forKey: .recentFonts) ?? recentFonts
    }

    func screen(_ name: String) -> W4LyricScreen { screens[name] ?? W4LyricScreen() }

    var look: W4LyricLook {
        get {
            var look = W4LyricLook()
            look.size = size
            look.bold = bold
            look.currentHex = currentHex
            look.nextHex = nextHex
            look.nextOpacity = nextOpacity
            look.showNext = showNext
            look.align = align
            look.reveal = reveal
            look.revealSpeed = revealSpeed
            look.shadow = shadow
            look.widthFraction = widthFraction
            look.fontFamily = fontFamily
            return look
        }
        set {
            size = newValue.size
            bold = newValue.bold
            currentHex = newValue.currentHex
            nextHex = newValue.nextHex
            nextOpacity = newValue.nextOpacity
            showNext = newValue.showNext
            align = newValue.align
            reveal = newValue.reveal
            revealSpeed = newValue.revealSpeed
            shadow = newValue.shadow
            widthFraction = newValue.widthFraction
            fontFamily = newValue.fontFamily
        }
    }

    /// What a display draws: the shared look unless it keeps its own.
    func effective(for name: String) -> W4LyricStyle {
        var result = self
        if let own = screen(name).look { result.look = own }
        return result
    }
}

// MARK: - Word timing

/// LRCLIB usually has one time per line, so a word's time is estimated from its length unless the file tags words.
enum W4LyricWords {
    private static func isCJK(_ character: Character) -> Bool {
        guard let value = character.unicodeScalars.first?.value else { return false }
        return (0x3040...0x30FF).contains(value) || (0x3400...0x9FFF).contains(value)
    }

    static func tokens(_ line: String) -> [String] {
        var out: [String] = []
        var current = ""
        var endedWord = false
        for character in line {
            if character.isWhitespace {
                current.append(character)
                endedWord = true
            } else {
                if !current.isEmpty && (endedWord || isCJK(character)) {
                    out.append(current)
                    current = ""
                }
                current.append(character)
                endedWord = isCJK(character)
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    static func progress(tokens: [String], elapsed: Double, lineDuration: Double, speed: Double) -> [Double] {
        guard !tokens.isEmpty else { return [] }
        let weights = tokens.map { Double(max(1, $0.trimmingCharacters(in: .whitespaces).count)) + 1 }
        let total = weights.reduce(0, +)
        let sung = min(max(0.2, lineDuration * 0.9), Double(tokens.count) * 0.42) / max(0.1, speed)
        let fade = max(0.14, min(0.4, sung / Double(tokens.count) * 1.4))
        var used = 0.0
        var result: [Double] = []
        for weight in weights {
            let start = used / total * sung
            result.append(min(1, max(0, (elapsed - start) / fade)))
            used += weight
        }
        return result
    }
}

// MARK: - Finding lyrics when the exact search misses

enum W4LyricMatch {
    private static func cutAtBracket(_ text: String) -> String {
        let marks = CharacterSet(charactersIn: "(（[【《「〈")
        var cut = text
        if let range = cut.rangeOfCharacter(from: marks) { cut = String(cut[..<range.lowerBound]) }
        if let range = cut.range(of: " - ") { cut = String(cut[..<range.lowerBound]) }
        cut = cut.trimmingCharacters(in: .whitespaces)
        return cut.isEmpty ? text : cut
    }

    static func coreTitle(_ title: String) -> String { cutAtBracket(title) }

    static func coreArtist(_ artist: String?) -> String {
        let first = (artist ?? "").components(separatedBy: ",").first ?? ""
        return cutAtBracket(first.trimmingCharacters(in: .whitespaces))
    }

    static func simplified(_ text: String) -> String {
        text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
    }

    static func normalized(_ text: String) -> String {
        String(simplified(text).lowercased().filter { $0.isLetter || $0.isNumber })
    }

    static func isSameSong(candidateTitle: String, candidateArtist: String, title: String, artist: String?, durationGap: Double) -> Bool {
        let wanted = normalized(coreTitle(title))
        let found = normalized(candidateTitle)
        guard !wanted.isEmpty, found.contains(wanted) else { return false }
        let a = normalized(coreArtist(artist))
        let b = normalized(candidateArtist)
        if !a.isEmpty, !b.isEmpty, a.contains(b) || b.contains(a) { return durationGap <= 8 }
        return found == wanted && durationGap <= 2
    }

    /// Two rows at one time are usually the original and a translation: keep the original. Rows that only name a singer go.
    static func cleaned(_ lines: [LyricLine]) -> [LyricLine] {
        var unique: [LyricLine] = []
        for line in lines {
            if let last = line.text.last, last == ":" || last == "：", line.text.count <= 12 { continue }
            if let previous = unique.last, abs(previous.time - line.time) < 0.01 { continue }
            unique.append(line)
        }
        return unique
    }
}

// MARK: - Schemes

/// w4: a scheme keeps the lyric's look and its place on the captured display, inside the Music layer's
/// options so it travels with the scheme's overlay. Favourite and recent fonts stay global.
@MainActor
enum W4SchemeLyric {
    private static let key = "w4Lyric"

    static func embedding(in overlay: MonitorOverlayConfiguration, screenName: String) -> MonitorOverlayConfiguration {
        let current = W4LyricController.shared.style
        var place = current.screen(screenName)
        place.look = place.look ?? current.look
        guard let data = try? JSONEncoder().encode(place), let text = String(data: data, encoding: .utf8) else { return overlay }
        var next = overlay
        next.music.options[key] = .string(text)
        return next
    }

    /// Only the applied display changes; the shared look and the other displays stay.
    static func restore(from overlay: MonitorOverlayConfiguration, screenName: String) {
        guard let text = overlay.music.options[key]?.stringValue, let data = text.data(using: .utf8) else { return }
        let controller = W4LyricController.shared
        if let place = try? JSONDecoder().decode(W4LyricScreen.self, from: data), place.look != nil {
            controller.style.screens[screenName] = place
        } else if let older = try? JSONDecoder().decode(W4LyricStyle.self, from: data) {
            // Schemes saved by the build before kept the whole style with its place under one key.
            var place = older.screens.values.first ?? controller.style.screen(screenName)
            place.look = older.look
            controller.style.screens[screenName] = place
        }
    }
}

// MARK: - Controller

@MainActor
final class W4LyricController: ObservableObject {
    static let shared = W4LyricController()
    private static let defaultsKey = "W4.LyricStyle"

    @Published var style: W4LyricStyle {
        didSet {
            guard style != oldValue else { return }
            if let data = try? JSONEncoder().encode(style) {
                UserDefaults.appScoped().set(data, forKey: Self.defaultsKey)
            }
            rebuild()
        }
    }
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var active = -1
    @Published private(set) var nowPlaying: MonitorNowPlayingState?
    @Published private(set) var statusText = ""
    /// The font under the pointer in the picker, shown on the real lyric until the pointer leaves.
    @Published var previewFontFamily: String?

    private let subscriberID = UUID()
    private var trackKey = ""
    private var panels: [String: NSPanel] = [:]
    private var timer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var started = false

    private init() {
        if let data = UserDefaults.appScoped().data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(W4LyricStyle.self, from: data) {
            style = saved
        } else {
            style = W4LyricStyle()
        }
    }

    func start() {
        guard !started else { return }
        started = true
        NowPlayingMonitor.shared.subscribe(id: subscriberID) { _, state in
            Task { @MainActor in W4LyricController.shared.apply(state) }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { W4LyricController.shared.rebuild() }
        }
        rebuild()
    }

    /// The 10 Hz clock runs only while a song with lyrics plays, so the Mac can idle the rest of the time.
    private func syncTimer() {
        let needed = started && nowPlaying?.phase == .playing && !lines.isEmpty
        if needed, timer == nil {
            let t = Timer(timeInterval: 0.1, repeats: true) { _ in
                MainActor.assumeIsolated { W4LyricController.shared.tick() }
            }
            t.tolerance = 0.03
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !needed, let t = timer {
            t.invalidate()
            timer = nil
        }
    }

    var displayLines: [LyricLine] {
        if !lines.isEmpty { return lines }
        guard let state = nowPlaying, state.phase.hasTrack, !state.title.isEmpty else { return [] }
        return [LyricLine(time: 0, text: state.title, words: nil)]
    }

    var isVisible: Bool {
        style.enabled && nowPlaying?.phase == .playing
    }

    var activeLineText: String {
        let lines = displayLines
        return lines.indices.contains(active) ? lines[active].text : ""
    }

    func font(size: Double, bold: Bool, family chosen: String) -> Font {
        let family = previewFontFamily ?? chosen
        let weight: Font.Weight = bold ? .bold : .semibold
        if family.isEmpty { return .system(size: size, weight: weight, design: .rounded) }
        return Font.custom(family, size: size).weight(weight)
    }

    func playhead(at date: Date) -> Double {
        guard let state = nowPlaying, let position = state.position else { return 0 }
        var time = position
        if state.phase == .playing, let sampled = state.positionSampledAt {
            time += max(0, date.timeIntervalSince1970 - sampled) * state.effectivePlaybackRate
        }
        return time + style.offset + 0.15
    }

    private func apply(_ state: MonitorNowPlayingState) {
        nowPlaying = state
        let key = state.phase.hasTrack ? "\(state.title)|\(state.artist ?? "")" : ""
        if key != trackKey {
            trackKey = key
            lines = []
            active = -1
            statusText = key.isEmpty ? "Chưa thấy nhạc đang phát" : "Đang tìm lyric"
            if !key.isEmpty {
                Task { [weak self] in
                    let found = await NowPlayingLyricsStore.shared.lyrics(for: state)
                    guard let self, self.trackKey == key else { return }
                    self.lines = found
                    self.statusText = found.isEmpty ? "Chưa có lyric cho bài này" : "Đã có lyric: \(found.count) dòng"
                    self.syncTimer()
                }
            }
        }
        tick()
        syncTimer()
    }

    private func tick() {
        guard !lines.isEmpty else {
            if active != 0 { active = displayLines.isEmpty ? -1 : 0 }
            return
        }
        let index = NowPlayingLyrics.activeIndex(lines: lines, at: playhead(at: Date())) ?? -1
        if index != active { active = index }
    }

    func rebuild() {
        guard started else { return }
        let screens = NSScreen.screens
        let names = Set(screens.map(\.localizedName))
        for (name, panel) in panels where !names.contains(name) || !style.screen(name).on {
            panel.orderOut(nil)
            panels[name] = nil
        }
        for screen in screens {
            let name = screen.localizedName
            let place = style.screen(name)
            guard place.on else { continue }
            let panel = panels[name] ?? makePanel(screenName: name)
            panels[name] = panel
            let look = style.effective(for: name)
            let width = screen.frame.width * look.widthFraction
            let height = look.size * 1.34 * 4
            let x = screen.frame.minX + (screen.frame.width - width) * place.x
            let y = screen.visibleFrame.minY + (screen.visibleFrame.height - height) * place.y
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
            panel.level = place.floating
                ? .statusBar
                : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            panel.orderFrontRegardless()
        }
    }

    private func makePanel(screenName: String) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 220),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: W4LyricView(controller: self, screenName: screenName))
        return panel
    }
}

// MARK: - View

struct W4LyricView: View {
    @ObservedObject var controller: W4LyricController
    let screenName: String
    private let sideScale: CGFloat = 0.62

    private var style: W4LyricStyle { controller.style.effective(for: screenName) }

    private var frameAlign: Alignment {
        switch style.align {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    private var anchor: UnitPoint {
        switch style.align {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    private func color(_ hex: String) -> Color {
        MonitorPanelAppearance.color(fromHex: hex) ?? .white
    }

    private func lineText(_ line: LyricLine, next: LyricLine?, base: Color, revealing: Bool, now: Date) -> Text {
        guard revealing, !line.text.isEmpty else { return Text(verbatim: line.text).foregroundColor(base) }
        let time = controller.playhead(at: now)
        let tokens: [String]
        let amounts: [Double]
        if let words = line.words, !words.isEmpty {
            tokens = words.map(\.text)
            amounts = words.map { min(1, max(0, (time - $0.time) / 0.18)) }
        } else {
            tokens = W4LyricWords.tokens(line.text)
            amounts = W4LyricWords.progress(tokens: tokens, elapsed: time - line.time,
                                            lineDuration: next.map { $0.time - line.time } ?? 4,
                                            speed: style.revealSpeed)
        }
        let floorAlpha = style.reveal == .karaoke ? 0.35 : 0.0
        var result = Text(verbatim: "")
        for (token, amount) in zip(tokens, amounts) {
            let piece: Text = Text(verbatim: token).foregroundColor(base.opacity(floorAlpha + (1 - floorAlpha) * amount))
            result = result + piece
        }
        return result
    }

    private func row(_ index: Int, in lines: [LyricLine]) -> some View {
        let distance = index - controller.active
        let isCurrent = distance == 0
        let hideUpcoming = style.reveal == .fade && distance > 0 && lines.count > 1
        let opacity: Double = isCurrent ? 1 : (hideUpcoming || abs(distance) != 1 || !style.showNext ? 0 : style.nextOpacity)
        let base = color(isCurrent ? style.currentHex : style.nextHex)
        let revealing = isCurrent && style.reveal != .off && lines.count > 1
        let line = lines[index]
        let next = index + 1 < lines.count ? lines[index + 1] : nil
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !revealing)) { context in
            lineText(line, next: next, base: base, revealing: revealing, now: context.date)
        }
        .font(controller.font(size: style.size, bold: style.bold, family: style.fontFamily))
        .lineLimit(1)
        .minimumScaleFactor(0.45)
        .scaleEffect(isCurrent ? 1 : sideScale, anchor: anchor)
        .opacity(opacity)
        .offset(y: CGFloat(distance) * style.size * 1.22)
        .frame(maxWidth: .infinity, alignment: frameAlign)
    }

    var body: some View {
        let lines = controller.displayLines
        let low = max(0, controller.active - 2)
        let high = min(lines.count - 1, controller.active + 2)
        ZStack {
            if low <= high {
                ForEach(Array(low...high), id: \.self) { index in
                    row(index, in: lines)
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .compositingGroup()
        .shadow(color: .black.opacity(0.8 * style.shadow), radius: 6 * style.shadow, x: 0, y: 2)
        .shadow(color: .black.opacity(0.45 * style.shadow), radius: 18 * style.shadow)
        .opacity(controller.isVisible ? 1 : 0)
        .animation(.spring(response: 0.6, dampingFraction: 0.88), value: controller.active)
        .animation(.easeInOut(duration: 0.35), value: controller.isVisible)
    }
}

// MARK: - Font picker

struct W4FontInfo: Identifiable, Equatable {
    enum Kind: Equatable { case sans, serif, script, mono, display, other }

    let family: String
    let kind: Kind
    let hasVietnamese: Bool
    let hasCJK: Bool
    var id: String { family }
}

@MainActor
enum W4FontCatalog {
    private static var cached: [W4FontInfo]?

    static var all: [W4FontInfo] {
        if let cached { return cached }
        let vietnamese = "ăâđêôơưạệộựằ".unicodeScalars
        let cjk = "月光夜の".unicodeScalars
        let built = NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .compactMap { family -> W4FontInfo? in
                guard let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 14) else { return nil }
                let raw = font.fontDescriptor.symbolicTraits.rawValue
                let kind: W4FontInfo.Kind
                if raw & (1 << 10) != 0 {
                    kind = .mono
                } else {
                    switch (raw >> 28) & 0xF {
                    case 1, 2, 3, 4, 5, 7: kind = .serif
                    case 8: kind = .sans
                    case 9: kind = .display
                    case 10: kind = .script
                    default: kind = .other
                    }
                }
                let covered = font.coveredCharacterSet
                return W4FontInfo(family: family, kind: kind,
                                  hasVietnamese: vietnamese.allSatisfy { covered.contains($0) },
                                  hasCJK: cjk.allSatisfy { covered.contains($0) })
            }
        cached = built
        return built
    }
}

struct W4FontPicker: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "Tất cả"
        case favorite = "Yêu thích"
        case recent = "Gần đây"
        case vietnamese = "Có tiếng Việt"
        case cjk = "Có chữ Hán"
        case sans = "Không chân"
        case serif = "Có chân"
        case script = "Viết tay"
        case mono = "Đơn cách"
        case display = "Trang trí"
        var id: String { rawValue }
    }

    @ObservedObject var controller: W4LyricController
    /// The look being edited: the shared one or a display's own.
    @Binding var family: String
    var bold = true
    /// The lyric on screen shows the hovered font; off when picking for something else.
    var previewsOnLyric = true
    var sampleText: String?
    @State private var query = ""
    @State private var filter = Filter.all
    @State private var fonts: [W4FontInfo] = []

    private var shown: [W4FontInfo] {
        let style = controller.style
        var list = fonts
        switch filter {
        case .all: break
        case .favorite: list = list.filter { style.favoriteFonts.contains($0.family) }
        case .recent:
            list = style.recentFonts.compactMap { name in fonts.first { $0.family == name } }
        case .vietnamese: list = list.filter(\.hasVietnamese)
        case .cjk: list = list.filter(\.hasCJK)
        case .sans: list = list.filter { $0.kind == .sans }
        case .serif: list = list.filter { $0.kind == .serif }
        case .script: list = list.filter { $0.kind == .script }
        case .mono: list = list.filter { $0.kind == .mono }
        case .display: list = list.filter { $0.kind == .display }
        }
        let text = query.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            list = list.filter { $0.family.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        return list
    }

    private var sample: String {
        if let sampleText { return sampleText }
        let line = controller.activeLineText
        return line.isEmpty ? "Lyric sẽ hiện như thế này" : line
    }

    private func pick(_ chosen: String) {
        if !chosen.isEmpty {
            var style = controller.style
            style.recentFonts.removeAll { $0 == chosen }
            style.recentFonts.insert(chosen, at: 0)
            style.recentFonts = Array(style.recentFonts.prefix(10))
            controller.style = style
        }
        family = chosen
    }

    private func toggleFavorite(_ family: String) {
        var style = controller.style
        if style.favoriteFonts.contains(family) {
            style.favoriteFonts.removeAll { $0 == family }
        } else {
            style.favoriteFonts.append(family)
        }
        controller.style = style
    }

    private func row(_ info: W4FontInfo) -> some View {
        let selected = family == info.family
        let favorite = controller.style.favoriteFonts.contains(info.family)
        return HStack(spacing: 8) {
            Button { pick(info.family) } label: {
                HStack(spacing: 8) {
                    Text(verbatim: info.family)
                        .font(.custom(info.family, size: 16))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if info.hasVietnamese {
                        Text(verbatim: "VI").font(.caption2).foregroundStyle(.secondary)
                    }
                    if selected {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { toggleFavorite(info.family) } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .foregroundStyle(favorite ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: favorite ? "Bỏ yêu thích \(info.family)" : "Yêu thích \(info.family)"))
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .onHover { inside in
            guard previewsOnLyric else { return }
            if inside {
                controller.previewFontFamily = info.family
            } else if controller.previewFontFamily == info.family {
                controller.previewFontFamily = nil
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(verbatim: sample)
                .font(previewsOnLyric
                    ? controller.font(size: 22, bold: bold, family: family)
                    : (family.isEmpty ? .system(size: 22, weight: .bold) : Font.custom(family, size: 22).weight(.bold)))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, minHeight: 44)
            TextField("", text: $query, prompt: Text(verbatim: "Tìm phông"))
                .textFieldStyle(.roundedBorder)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Filter.allCases) { item in
                        Button(item.rawValue) { filter = item }
                            .buttonStyle(.bordered)
                            .tint(filter == item ? Color.accentColor : Color.secondary)
                            .controlSize(.small)
                    }
                }
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    Button { pick("") } label: {
                        HStack {
                            Text(verbatim: "Mặc định của hệ thống").font(.system(size: 15, design: .rounded))
                            Spacer()
                            if family.isEmpty {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    ForEach(shown) { info in
                        row(info)
                    }
                }
            }
            Text(verbatim: "Rê chuột để xem ngay trên lyric, bấm để chọn. VI là phông có đủ dấu tiếng Việt.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(width: 400, height: 500)
        .onAppear { fonts = W4FontCatalog.all }
        .onDisappear { controller.previewFontFamily = nil }
    }
}

// MARK: - Settings section

/// Every control for one look, shared by Settings and a display's Music panel.
struct W4LyricLookControls: View {
    @ObservedObject var controller: W4LyricController
    @Binding var look: W4LyricLook
    /// Also moves the lyric to that side of the display(s) this look draws on.
    let onAlign: (W4LyricAlign) -> Void
    var sliderWidth: CGFloat = 180

    @State private var showingFonts = false

    private func bind<T>(_ path: WritableKeyPath<W4LyricLook, T>) -> Binding<T> {
        Binding(get: { look[keyPath: path] }, set: { look[keyPath: path] = $0 })
    }

    private func colorBinding(_ path: WritableKeyPath<W4LyricLook, String>) -> Binding<Color> {
        Binding(
            get: { MonitorPanelAppearance.color(fromHex: look[keyPath: path]) ?? .white },
            set: { look[keyPath: path] = MonitorPanelAppearance.hex(from: $0) }
        )
    }

    private func stepFont(_ delta: Int) {
        let list = W4FontCatalog.all.map(\.family)
        guard !list.isEmpty else { return }
        let current = list.firstIndex(of: look.fontFamily) ?? (delta > 0 ? -1 : 0)
        look.fontFamily = list[(current + delta + list.count) % list.count]
    }

    private func slider(_ title: LocalizedStringKey, icon: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        SettingRow(icon: icon, iconColor: .pink, title: title) {
            Slider(value: value, in: range)
                .frame(width: sliderWidth)
                .labelsHidden()
        }
    }

    var body: some View {
        SettingRow(icon: "text.alignleft", iconColor: .pink, title: "Căn chữ") {
            Picker("", selection: Binding(get: { look.align }, set: { value in
                look.align = value
                onAlign(value)
            })) {
                Text(verbatim: "Trái").tag(W4LyricAlign.left)
                Text(verbatim: "Giữa").tag(W4LyricAlign.center)
                Text(verbatim: "Phải").tag(W4LyricAlign.right)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 170)
        }
        SettingRow(icon: "sparkles", iconColor: .pink, title: "Hiện chữ") {
            Picker("", selection: bind(\.reveal)) {
                Text(verbatim: "Cả dòng").tag(W4LyricReveal.off)
                Text(verbatim: "Từng chữ").tag(W4LyricReveal.fade)
                Text(verbatim: "Sáng từng chữ").tag(W4LyricReveal.karaoke)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 250)
        }
        if look.reveal != .off {
            slider("Tốc độ hiện chữ", icon: "speedometer", value: bind(\.revealSpeed), range: 0.5...2)
        }
        SettingRow(icon: "textformat", iconColor: .pink, title: "Phông chữ") {
            HStack(spacing: 6) {
                Button { stepFont(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel(Text(verbatim: "Phông trước"))
                Button {
                    showingFonts = true
                } label: {
                    Text(verbatim: look.fontFamily.isEmpty ? "Mặc định" : look.fontFamily)
                        .lineLimit(1)
                        .frame(minWidth: 90, maxWidth: 170)
                }
                .popover(isPresented: $showingFonts, arrowEdge: .bottom) {
                    W4FontPicker(controller: controller, family: bind(\.fontFamily), bold: look.bold)
                }
                Button { stepFont(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel(Text(verbatim: "Phông sau"))
            }
        }
        slider("Cỡ chữ", icon: "textformat.size", value: bind(\.size), range: 18...120)
        slider("Độ rộng khung", icon: "arrow.left.and.right", value: bind(\.widthFraction), range: 0.3...1)
        SettingRow(icon: "bold", iconColor: .pink, title: "Chữ đậm") {
            Toggle("", isOn: bind(\.bold)).labelsHidden().toggleStyle(.switch)
        }
        SettingRow(icon: "paintpalette", iconColor: .pink, title: "Màu dòng đang hát") {
            ColorPicker("", selection: colorBinding(\.currentHex), supportsOpacity: false).labelsHidden()
        }
        SettingRow(icon: "list.bullet", iconColor: .pink, title: "Hiện dòng trước và sau") {
            Toggle("", isOn: bind(\.showNext)).labelsHidden().toggleStyle(.switch)
        }
        SettingRow(icon: "paintpalette", iconColor: .pink, title: "Màu dòng trước và sau") {
            ColorPicker("", selection: colorBinding(\.nextHex), supportsOpacity: false).labelsHidden()
        }
        slider("Độ rõ dòng trước và sau", icon: "circle.lefthalf.filled", value: bind(\.nextOpacity), range: 0.1...1)
        slider("Bóng chữ", icon: "shadow", value: bind(\.shadow), range: 0...1)
    }

    static func x(for align: W4LyricAlign) -> Double {
        switch align {
        case .left: 0
        case .center: 0.5
        case .right: 1
        }
    }
}

/// Settings: what every display shares. Each display's own place and look live in its Music panel.
struct W4LyricSettingsSection: View {
    @ObservedObject private var controller = W4LyricController.shared

    private var sharedLook: Binding<W4LyricLook> {
        Binding(get: { controller.style.look }, set: { controller.style.look = $0 })
    }

    var body: some View {
        Section {
            SettingRow(icon: "music.note", iconColor: .pink, title: "Hiện lyric") {
                Toggle("", isOn: Binding(get: { controller.style.enabled }, set: { controller.style.enabled = $0 }))
                    .labelsHidden().toggleStyle(.switch)
            }
            Text(verbatim: controller.statusText.isEmpty ? "Mở Spotify bản máy tính và phát một bài." : controller.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            SettingRow(icon: "clock", iconColor: .pink, title: "Sớm hoặc muộn") {
                Slider(value: Binding(get: { controller.style.offset }, set: { controller.style.offset = $0 }), in: -3...3)
                    .frame(width: 180)
                    .labelsHidden()
            }
            W4LyricLookControls(controller: controller, look: sharedLook) { align in
                // Displays that keep their own look also keep their own place.
                var next = controller.style
                for screen in NSScreen.screens where next.screen(screen.localizedName).look == nil {
                    var place = next.screen(screen.localizedName)
                    place.x = W4LyricLookControls.x(for: align)
                    next.screens[screen.localizedName] = place
                }
                controller.style = next
            }
            Text(verbatim: "Đây là kiểu chung cho mọi màn. Vị trí và kiểu riêng của từng màn chỉnh trong phần chỉnh lớp phủ của màn đó, mục Nhạc → Lyric.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text(verbatim: "Lyric chung")
        }
    }
}

/// A display's Music panel: where its lyric sits, and optionally a look of its own. Saved with schemes.
struct W4LyricScreenCard: View {
    let screenName: String
    @Binding var isExpanded: Bool
    @ObservedObject private var controller = W4LyricController.shared

    private var place: W4LyricScreen { controller.style.screen(screenName) }

    private func placeBinding<T>(_ path: WritableKeyPath<W4LyricScreen, T>) -> Binding<T> {
        Binding(
            get: { controller.style.screen(screenName)[keyPath: path] },
            set: { value in
                var next = controller.style.screen(screenName)
                next[keyPath: path] = value
                controller.style.screens[screenName] = next
            }
        )
    }

    private var ownLook: Binding<W4LyricLook> {
        Binding(
            get: { controller.style.effective(for: screenName).look },
            set: { placeBinding(\.look).wrappedValue = $0 }
        )
    }

    private func slider(_ title: LocalizedStringKey, icon: String, value: Binding<Double>) -> some View {
        SettingRow(icon: icon, iconColor: .pink, title: title) {
            Slider(value: value, in: 0...1)
                .frame(width: 160)
                .labelsHidden()
        }
    }

    var body: some View {
        GroupBox {
            CollapsibleSection(title: "Lyric", systemImage: "quote.bubble", isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    if !controller.style.enabled {
                        Text(verbatim: "Lyric đang tắt chung trong Cài đặt → Lớp phủ.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    SettingRow(icon: "display", iconColor: .pink, title: "Hiện trên màn này") {
                        Toggle("", isOn: placeBinding(\.on)).labelsHidden().toggleStyle(.switch)
                    }
                    Divider()
                    SettingRow(icon: "macwindow.on.rectangle", iconColor: .pink, title: "Nổi trên mọi cửa sổ") {
                        Toggle("", isOn: placeBinding(\.floating)).labelsHidden().toggleStyle(.switch)
                    }
                    Divider()
                    slider("Trái, phải", icon: "arrow.left.and.right", value: placeBinding(\.x))
                    slider("Dưới, trên", icon: "arrow.up.and.down", value: placeBinding(\.y))
                    Divider()
                    SettingRow(icon: "paintbrush", iconColor: .pink, title: "Kiểu riêng cho màn này") {
                        Toggle("", isOn: Binding(
                            get: { place.look != nil },
                            set: { own in placeBinding(\.look).wrappedValue = own ? controller.style.look : nil }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    if place.look != nil {
                        W4LyricLookControls(controller: controller, look: ownLook, onAlign: { align in
                            placeBinding(\.x).wrappedValue = W4LyricLookControls.x(for: align)
                        }, sliderWidth: 160)
                    } else {
                        Text(verbatim: "Đang theo kiểu chung trong Cài đặt. Bật lên để chỉnh font, cỡ, màu riêng cho màn này.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(verbatim: "Lưu bộ màn hình là lưu luôn lyric của màn này.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!controller.style.enabled)
            }
        }
        .groupBoxStyle(ContainerGroupBoxStyle())
    }
}
#endif
