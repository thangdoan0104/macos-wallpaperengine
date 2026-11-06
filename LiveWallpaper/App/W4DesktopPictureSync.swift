#if !MAS_BUILD
import AppKit
import LiveWallpaperCore

/// w4: Launchpad, Mission Control and the menu bar tint read the macOS desktop picture, not our wallpaper window,
/// so the first rendered frame of each wallpaper becomes the desktop picture.
@MainActor
final class W4DesktopPictureSync {
    static let shared = W4DesktopPictureSync()

    private weak var manager: ScreenManager?
    private var timer: Timer?
    private var synced: [CGDirectDisplayID: String] = [:]
    private var inFlight: Set<CGDirectDisplayID> = []

    func start(manager: ScreenManager) {
        self.manager = manager
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            MainActor.assumeIsolated { W4DesktopPictureSync.shared.tick() }
        }
    }

    private func nsScreen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }

    private func tick() {
        guard let manager, manager.wallpapersGloballyEnabled else { return }
        for screen in manager.screens {
            let id = screen.id
            guard !inFlight.contains(id), screen.runtimeSession != nil,
                  let configuration = manager.getConfiguration(for: screen) else { continue }
            let key = String(describing: configuration.activeWallpaper)
            guard synced[id] != key else { continue }
            inFlight.insert(id)
            Task { [weak self] in
                defer { self?.inFlight.remove(id) }
                guard let image = await WallpaperCoverCapture.wallpaperFrame(screen: screen, configuration: configuration),
                      let frame = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let target = self?.nsScreen(for: id) else { return }
                let outcome = await DesktopPictureFrameExtractor.applyFrame(
                    { frame },
                    screenID: id,
                    nsScreen: target,
                    install: { url, screen in
                        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                    }
                )
                if outcome == .captured { self?.synced[id] = key }
            }
        }
    }
}
#endif
