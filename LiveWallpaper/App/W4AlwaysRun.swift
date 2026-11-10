import Foundation
import LiveWallpaperCore

/// w4: wallpapers keep playing behind other apps by default; both pause settings stay available in Settings.
/// Existing installs stored the old defaults, so those are switched once and any later choice is left alone.
enum W4AlwaysRun {
    private static let appliedKey = "W4.AlwaysRunApplied"
    private static let adaptiveKey = "W4.AdaptiveFPSApplied"

    @MainActor
    static func applyOnce() {
        let defaults = UserDefaults.appScoped()
        var settings = SettingsManager.shared.loadGlobalSettings()
        var changed = false
        if !defaults.bool(forKey: appliedKey) {
            defaults.set(true, forKey: appliedKey)
            settings.pauseOnFullScreen = false
            settings.pauseOnWindowOcclusion = false
            changed = true
        }
        // Still running when covered, but at half the frame rate: the second display keeps updating
        // without paying full price for a wallpaper nobody can see. Switched on once; Settings can turn it off.
        if !defaults.bool(forKey: adaptiveKey) {
            defaults.set(true, forKey: adaptiveKey)
            settings.adaptiveFrameRateEnabled = true
            changed = true
        }
        if changed { SettingsManager.shared.saveGlobalSettings(settings) }
    }
}
