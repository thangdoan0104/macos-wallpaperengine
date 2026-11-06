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

    private struct ScreenState {
        let key: String
        var changedAt = Date()
        var captures = 0
        var lastAttemptAt: Date?
    }

    private weak var manager: ScreenManager?
    private var timer: Timer?
    private var spaceObserver: NSObjectProtocol?
    private var states: [CGDirectDisplayID: ScreenState] = [:]
    private var inFlightSince: [CGDirectDisplayID: Date] = [:]
    private var installed: [CGDirectDisplayID: URL] = [:]

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

    private func nsScreen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }

    private static let installOptions: [NSWorkspace.DesktopImageOptionKey: Any] = [
        .imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue),
        .allowClipping: true,
        .fillColor: NSColor.black,
    ]

    private func reinstallForActiveSpace() {
        for (id, url) in installed {
            guard let target = nsScreen(for: id),
                  NSWorkspace.shared.desktopImageURL(for: target) != url,
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(url, for: target, options: Self.installOptions)
        }
    }

    private func stateKey(screen: Screen, session: AnyObject, configuration: ScreenConfiguration) -> String {
        "\(configuration.activeWallpaper)|\(configuration.fitMode)|\(ObjectIdentifier(session))|\(screen.frame.size)"
    }

    private func tick() {
        guard let manager, manager.wallpapersGloballyEnabled else { return }
        let now = Date()
        for screen in manager.screens {
            let id = screen.id
            // While a wallpaper loads, the running session may still be the previous one.
            // A stopped scene draws no next frame to capture; it syncs once it plays again.
            guard (manager.suspendReasonsByScreen[id] ?? []).isEmpty,
                  screen.playbackController?.userIntendsToPlay ?? true,
                  manager.wallpaperLoads.attempt(for: screen) == nil,
                  let session = screen.runtimeSession,
                  let configuration = manager.getConfiguration(for: screen) else { continue }
            let key = stateKey(screen: screen, session: session as AnyObject, configuration: configuration)
            var state = states[id] ?? ScreenState(key: key)
            if state.key != key {
                state = ScreenState(key: key)
            }
            states[id] = state
            if let since = inFlightSince[id], now.timeIntervalSince(since) < Self.captureTimeout { continue }
            guard state.captures < 2, isDue(state, now: now) else { continue }
            states[id]?.lastAttemptAt = now
            inFlightSince[id] = now
            Task { [weak self] in
                await self?.capture(screen: screen, configuration: configuration, key: key, startedAt: now)
            }
        }
    }

    private func isDue(_ state: ScreenState, now: Date) -> Bool {
        if state.captures == 0 {
            guard now.timeIntervalSince(state.changedAt) >= Self.settleDelay else { return false }
            return state.lastAttemptAt.map { now.timeIntervalSince($0) >= Self.retryDelay } ?? true
        }
        return state.lastAttemptAt.map { now.timeIntervalSince($0) >= Self.confirmDelay } ?? true
    }

    private func capture(screen: Screen, configuration: ScreenConfiguration, key: String, startedAt: Date) async {
        let id = screen.id
        defer {
            if inFlightSince[id] == startedAt { inFlightSince[id] = nil }
        }
        guard let image = await WallpaperCoverCapture.wallpaperFrame(screen: screen, configuration: configuration),
              let target = nsScreen(for: id),
              states[id]?.key == key,
              let frame = Self.displayShaped(image, on: target, fitMode: configuration.fitMode) else { return }
        var installedURL: URL?
        let outcome = await DesktopPictureFrameExtractor.applyFrame(
            { frame },
            screenID: id,
            nsScreen: target,
            install: { url, screen in
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: Self.installOptions)
                installedURL = url
            }
        )
        guard outcome == .captured else { return }
        installed[id] = installedURL
        if states[id]?.key == key {
            states[id]?.captures += 1
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
