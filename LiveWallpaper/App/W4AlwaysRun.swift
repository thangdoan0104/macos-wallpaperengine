import Foundation
import LiveWallpaperCore

/// w4: wallpapers keep playing behind other apps by default; both pause settings stay available in Settings.
/// Existing installs stored the old defaults, so those are switched once and any later choice is left alone.
enum W4AlwaysRun {
    private static let appliedKey = "W4.AlwaysRunApplied"

    @MainActor
    static func applyOnce() {
        let defaults = UserDefaults.appScoped()
        guard !defaults.bool(forKey: appliedKey) else { return }
        defaults.set(true, forKey: appliedKey)
        var settings = SettingsManager.shared.loadGlobalSettings()
        settings.pauseOnFullScreen = false
        settings.pauseOnWindowOcclusion = false
        SettingsManager.shared.saveGlobalSettings(settings)
    }
}
