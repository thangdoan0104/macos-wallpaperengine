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

    func screen(_ name: String) -> W4LyricScreen { screens[name] ?? W4LyricScreen() }
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated { W4LyricController.shared.tick() }
        }
        rebuild()
    }

    var displayLines: [LyricLine] {
        if !lines.isEmpty { return lines }
        guard let state = nowPlaying, state.phase.hasTrack, !state.title.isEmpty else { return [] }
        return [LyricLine(time: 0, text: state.title, words: nil)]
    }

    var isVisible: Bool {
        style.enabled && nowPlaying?.phase == .playing
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
                }
            }
        }
        tick()
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
            let panel = panels[name] ?? makePanel()
            panels[name] = panel
            let width = screen.frame.width * style.widthFraction
            let height = style.size * 1.34 * 4
            let x = screen.frame.minX + (screen.frame.width - width) * place.x
            let y = screen.visibleFrame.minY + (screen.visibleFrame.height - height) * place.y
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
            panel.level = place.floating
                ? .statusBar
                : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> NSPanel {
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
        panel.contentView = NSHostingView(rootView: W4LyricView(controller: self))
        return panel
    }
}

// MARK: - View

struct W4LyricView: View {
    @ObservedObject var controller: W4LyricController
    private let sideScale: CGFloat = 0.62

    private var style: W4LyricStyle { controller.style }

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
        .font(.system(size: style.size, weight: style.bold ? .bold : .semibold, design: .rounded))
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

// MARK: - Settings section

struct W4LyricSettingsSection: View {
    @ObservedObject private var controller = W4LyricController.shared

    private func bind<T>(_ path: WritableKeyPath<W4LyricStyle, T>) -> Binding<T> {
        Binding(get: { controller.style[keyPath: path] }, set: { controller.style[keyPath: path] = $0 })
    }

    private func colorBinding(_ path: WritableKeyPath<W4LyricStyle, String>) -> Binding<Color> {
        Binding(
            get: { MonitorPanelAppearance.color(fromHex: controller.style[keyPath: path]) ?? .white },
            set: { controller.style[keyPath: path] = MonitorPanelAppearance.hex(from: $0) }
        )
    }

    private func screenBinding<T>(_ name: String, _ path: WritableKeyPath<W4LyricScreen, T>) -> Binding<T> {
        Binding(
            get: { controller.style.screen(name)[keyPath: path] },
            set: { value in
                var place = controller.style.screen(name)
                place[keyPath: path] = value
                controller.style.screens[name] = place
            }
        )
    }

    private var alignBinding: Binding<W4LyricAlign> {
        Binding(
            get: { controller.style.align },
            set: { value in
                var next = controller.style
                next.align = value
                let x: Double
                switch value {
                case .left: x = 0
                case .center: x = 0.5
                case .right: x = 1
                }
                for screen in NSScreen.screens {
                    var place = next.screen(screen.localizedName)
                    place.x = x
                    next.screens[screen.localizedName] = place
                }
                controller.style = next
            }
        )
    }

    private func slider(_ title: LocalizedStringKey, icon: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        SettingRow(icon: icon, iconColor: .pink, title: title) {
            Slider(value: value, in: range)
                .frame(width: 180)
                .labelsHidden()
        }
    }

    var body: some View {
        Section {
            SettingRow(icon: "music.note", iconColor: .pink, title: "Hiện lyric") {
                Toggle("", isOn: bind(\.enabled)).labelsHidden().toggleStyle(.switch)
            }
            Text(verbatim: controller.statusText.isEmpty ? "Mở Spotify bản máy tính và phát một bài." : controller.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            SettingRow(icon: "text.alignleft", iconColor: .pink, title: "Căn chữ") {
                Picker("", selection: alignBinding) {
                    Text(verbatim: "Trái").tag(W4LyricAlign.left)
                    Text(verbatim: "Giữa").tag(W4LyricAlign.center)
                    Text(verbatim: "Phải").tag(W4LyricAlign.right)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            SettingRow(icon: "sparkles", iconColor: .pink, title: "Hiện chữ") {
                Picker("", selection: bind(\.reveal)) {
                    Text(verbatim: "Cả dòng").tag(W4LyricReveal.off)
                    Text(verbatim: "Từng chữ").tag(W4LyricReveal.fade)
                    Text(verbatim: "Sáng từng chữ").tag(W4LyricReveal.karaoke)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            if controller.style.reveal != .off {
                slider("Tốc độ hiện chữ", icon: "speedometer", value: bind(\.revealSpeed), range: 0.5...2)
            }
            slider("Cỡ chữ", icon: "textformat.size", value: bind(\.size), range: 18...120)
            slider("Độ rộng khung", icon: "arrow.left.and.right", value: bind(\.widthFraction), range: 0.3...1)
            slider("Sớm hoặc muộn", icon: "clock", value: bind(\.offset), range: -3...3)
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
        } header: {
            Text(verbatim: "Lyric")
        }
        ForEach(NSScreen.screens, id: \.localizedName) { screen in
            let name = screen.localizedName
            Section {
                SettingRow(icon: "display", iconColor: .pink, title: "Hiện trên màn này") {
                    Toggle("", isOn: screenBinding(name, \.on)).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(icon: "macwindow.on.rectangle", iconColor: .pink, title: "Nổi trên mọi cửa sổ") {
                    Toggle("", isOn: screenBinding(name, \.floating)).labelsHidden().toggleStyle(.switch)
                }
                slider("Trái, phải", icon: "arrow.left.and.right", value: screenBinding(name, \.x), range: 0...1)
                slider("Dưới, trên", icon: "arrow.up.and.down", value: screenBinding(name, \.y), range: 0...1)
            } header: {
                Text(verbatim: "Lyric trên \(name)")
            }
        }
    }
}
#endif
