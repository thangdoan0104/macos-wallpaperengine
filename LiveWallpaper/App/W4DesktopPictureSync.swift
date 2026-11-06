#if !MAS_BUILD
import AppKit
import LiveWallpaperCore

/// w4: Launchpad, Mission Control and the menu bar tint read the macOS desktop picture, not our wallpaper window,
/// so a rendered frame of each wallpaper becomes the desktop picture, shaped the way the wallpaper fills its display.
@MainActor
final class W4DesktopPictureSync {
    static let shared = W4DesktopPictureSync()

    /// Lets the new session draw past its first frames before the first capture.
    private static let settleDelay: TimeInterval = 1.5
    /// A second capture replaces a first frame taken during a scene's intro or fade.
    private static let confirmDelay: TimeInterval = 6
    private static let retryDelay: TimeInterval = 3
    /// A capture can wait forever on a scene that stopped drawing; it must not block the next wallpaper.
    private static let captureTimeout: TimeInterval = 10

    /// Compared by value: a printed description can reorder dictionaries between reads and look like a new wallpaper.
    private struct Target: Equatable {
        let session: ObjectIdentifier
        let wallpaper: WallpaperContent
        let fitMode: VideoFitMode
        let size: CGSize
    }

    private struct ScreenState {
        var target: Target
        var changedAt = Date()
        /// Survives target changes, so a target that keeps changing can't postpone the capture forever.
        var pendingSince = Date()
        var captures = 0
        var lastAttemptAt: Date?
    }

    private static let nudgeAlpha: CGFloat = 0.99
    private static let nudgeDuration: TimeInterval = 3

    /// A capture is forced after this long, even if the target hasn't held still.
    private static let pendingLimit: TimeInterval = 5

    private weak var manager: ScreenManager?
    private var timer: Timer?
    private var spaceObserver: NSObjectProtocol?
    private var states: [CGDirectDisplayID: ScreenState] = [:]
    private var inFlightSince: [CGDirectDisplayID: Date] = [:]
    private var installed: [CGDirectDisplayID: URL] = [:]
    private var lastBlock: [CGDirectDisplayID: String] = [:]

    func start(manager: ScreenManager) {
        self.manager = manager
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { W4DesktopPictureSync.shared.tick() }
        }
        if spaceObserver == nil {
            // macOS keeps one desktop picture per Space, so another Space still holds the previous wallpaper's.
            spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { W4DesktopPictureSync.shared.reinstallForActiveSpace() }
            }
        }
    }

    private static let enabledKey = "W4.DesktopSyncEnabled"
    private static let originalPrefix = "W4.OriginalDesktop."

    static var isEnabled: Bool {
        UserDefaults.appScoped().object(forKey: enabledKey) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.appScoped().set(enabled, forKey: Self.enabledKey)
        // Turning it back on should sync what is playing now, not wait for the next change.
        states = [:]
        if !enabled { installed = [:] }
    }

    /// Kept per display name, the first time this app replaces that display's picture.
    private func rememberOriginal(of target: NSScreen) {
        let key = Self.originalPrefix + target.localizedName
        let defaults = UserDefaults.appScoped()
        guard defaults.string(forKey: key) == nil, let current = NSWorkspace.shared.desktopImageURL(for: target),
              !current.path.hasPrefix(DesktopPictureFrameExtractor.picturesDirectory.path) else { return }
        defaults.set(current.path, forKey: key)
    }

    /// Stops syncing and returns how many displays got their picture back.
    func restoreOriginals() -> Int {
        setEnabled(false)
        var restored = 0
        for target in NSScreen.screens {
            guard let path = UserDefaults.appScoped().string(forKey: Self.originalPrefix + target.localizedName) else { continue }
            if (try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: target, options: [:])) != nil {
                restored += 1
            }
        }
        return restored
    }

    private func nsScreen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }

    private func reinstallForActiveSpace() {
        guard Self.isEnabled else { return }
        for (id, url) in installed {
            guard let target = nsScreen(for: id),
                  NSWorkspace.shared.desktopImageURL(for: target) != url,
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(url, for: target, options: [:])
        }
    }

    /// Logged only when the reason changes, so the log says why a screen isn't syncing without repeating every second.
    private func noteBlocked(_ id: CGDirectDisplayID, _ reason: String?) {
        guard lastBlock[id] != reason else { return }
        lastBlock[id] = reason
        if let reason {
            Logger.notice("Desktop sync waits on screen \(id): \(reason)", category: .screenManager)
        }
    }

    private func tick() {
        guard Self.isEnabled, let manager, manager.wallpapersGloballyEnabled else { return }
        let now = Date()
        for screen in manager.screens {
            let id = screen.id
            // A stopped scene draws no frame to capture; it syncs once it plays again.
            if let reasons = manager.suspendReasonsByScreen[id], !reasons.isEmpty {
                noteBlocked(id, "suspended \(reasons.map(\.rawValue).sorted())")
                continue
            }
            if screen.playbackController?.userIntendsToPlay == false {
                noteBlocked(id, "paused by user")
                continue
            }
            // While a wallpaper loads, the running session may still be the previous one.
            if let attempt = manager.wallpaperLoads.attempt(for: screen) {
                noteBlocked(id, "load attempt \(attempt.phase)")
                continue
            }
            guard let session = screen.runtimeSession,
                  let configuration = manager.getConfiguration(for: screen) else {
                noteBlocked(id, "no session")
                continue
            }
            noteBlocked(id, nil)
            let sessionID = ObjectIdentifier(session as AnyObject)
            let target = Target(
                session: sessionID,
                wallpaper: configuration.activeWallpaper,
                fitMode: configuration.fitMode,
                size: screen.frame.size
            )
            var state = states[id] ?? ScreenState(target: target)
            if state.target != target {
                let pendingSince = state.captures == 0 ? state.pendingSince : now
                state = ScreenState(target: target, pendingSince: pendingSince)
                Logger.notice("Desktop sync: new wallpaper on screen \(id)", category: .screenManager)
            }
            states[id] = state
            if let since = inFlightSince[id] {
                guard now.timeIntervalSince(since) >= Self.captureTimeout else { continue }
                Logger.warning("Desktop sync: capture on screen \(id) took over \(Self.captureTimeout)s", category: .screenManager)
            }
            guard state.captures < 2, isDue(state, now: now) else { continue }
            states[id]?.lastAttemptAt = now
            inFlightSince[id] = now
            Task { [weak self] in
                await self?.capture(screen: screen, configuration: configuration, sessionID: sessionID, startedAt: now)
            }
        }
    }

    private func isDue(_ state: ScreenState, now: Date) -> Bool {
        if state.captures == 0 {
            guard now.timeIntervalSince(state.changedAt) >= Self.settleDelay
                || now.timeIntervalSince(state.pendingSince) >= Self.pendingLimit else { return false }
            return state.lastAttemptAt.map { now.timeIntervalSince($0) >= Self.retryDelay } ?? true
        }
        return state.lastAttemptAt.map { now.timeIntervalSince($0) >= Self.confirmDelay } ?? true
    }

    private func capture(screen: Screen, configuration: ScreenConfiguration, sessionID: ObjectIdentifier, startedAt: Date) async {
        let id = screen.id
        defer {
            if inFlightSince[id] == startedAt { inFlightSince[id] = nil }
        }
        guard let image = await WallpaperCoverCapture.wallpaperFrame(screen: screen, configuration: configuration) else {
            Logger.notice("Desktop sync: no frame from screen \(id)", category: .screenManager)
            return
        }
        guard let session = screen.runtimeSession, ObjectIdentifier(session as AnyObject) == sessionID,
              manager?.wallpaperLoads.attempt(for: screen) == nil else {
            Logger.notice("Desktop sync: wallpaper on screen \(id) changed during capture", category: .screenManager)
            return
        }
        guard let target = nsScreen(for: id),
              let frame = Self.displayShaped(image, on: target, fitMode: configuration.fitMode) else {
            Logger.warning("Desktop sync: could not draw frame for screen \(id)", category: .screenManager)
            return
        }
        guard Self.isEnabled else { return }
        rememberOriginal(of: target)
        var installedURL: URL?
        let outcome = await DesktopPictureFrameExtractor.applyFrame(
            { frame },
            screenID: id,
            nsScreen: target,
            install: { url, screen in
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                installedURL = url
            }
        )
        Logger.notice("Desktop sync: screen \(id) outcome \(outcome), macOS reports match \(NSWorkspace.shared.desktopImageURL(for: target) == installedURL)", category: .screenManager)
        guard outcome == .captured else { return }
        installed[id] = installedURL
        states[id]?.captures += 1
        nudgeSystemWallpaper(under: screen.activeWallpaperWindow, screenID: id)
    }

    /// macOS accepts the new picture but appears to hold back redrawing a desktop that an opaque window fully covers,
    /// and the menu bar blurs what is actually drawn. Slightly translucent, the wallpaper window stops counting as covering it.
    private func nudgeSystemWallpaper(under window: NSWindow?, screenID: CGDirectDisplayID) {
        guard let window, window.alphaValue == 1 else {
            Logger.notice("Desktop sync: nudge skipped on screen \(screenID), alpha \(window?.alphaValue ?? -1)", category: .screenManager)
            return
        }
        window.alphaValue = Self.nudgeAlpha
        Task { [weak window] in
            try? await Task.sleep(for: .seconds(Self.nudgeDuration))
            if let window, window.alphaValue == Self.nudgeAlpha { window.alphaValue = 1 }
        }
    }

    /// The picture at the display's own pixels, so macOS has nothing left to crop differently from the wallpaper window.
    private static func displayShaped(_ image: NSImage, on target: NSScreen, fitMode: VideoFitMode) -> CGImage? {
        let scale = target.backingScaleFactor
        let width = Int((target.frame.width * scale).rounded())
        let height = Int((target.frame.height * scale).rounded())
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        let canvas = NSRect(x: 0, y: 0, width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = graphics
        graphics.imageInterpolation = .high
        NSColor.black.setFill()
        canvas.fill()
        image.draw(
            in: WallpaperCoverCapture.placementRect(
                for: image.size, in: canvas, fitMode: fitMode, displayWidth: target.frame.width
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        graphics.flushGraphics()
        return context.makeImage()
    }
}
#endif
