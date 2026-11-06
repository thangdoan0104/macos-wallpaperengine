#if !MAS_BUILD
import AppKit
import CoreFoundation
import LiveWallpaperCore
import SwiftUI

/// w4: what the old app offered for the macOS desktop picture.
struct W4DesktopPictureSection: View {
    @State private var syncs = W4DesktopPictureSync.isEnabled
    @State private var message: String?

    var body: some View {
        Section {
            Toggle(isOn: $syncs) {
                Text(verbatim: "Đồng bộ với hình nền macOS")
            }
            .onChange(of: syncs) { _, enabled in
                W4DesktopPictureSync.shared.setEnabled(enabled)
            }
            Text(verbatim: "Để thanh menu, Launchpad và Mission Control theo đúng hình đang chạy.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                let restored = W4DesktopPictureSync.shared.restoreOriginals()
                syncs = false
                message = restored > 0
                    ? "Đã trả lại hình nền cũ trên \(restored) màn và tắt đồng bộ."
                    : "Không tìm thấy hình nền cũ đã lưu. Đã tắt đồng bộ."
            } label: {
                Text(verbatim: "Khôi phục hình nền cũ của máy")
            }
            if let message {
                Text(verbatim: message).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text(verbatim: "Hình nền macOS")
        }
    }
}

struct W4DockValues: Equatable {
    var orientation = "bottom"
    var tilesize = 48.0
    var magnification = false
    var largesize = 64.0
    var autohide = false
    var autohideDelay = 0.2
    var autohideSpeed = 0.5
    var mineffect = "genie"
    var showRecents = true
    var staticOnly = false
    var minimizeToApp = false
}

/// Reads and writes the Dock's own preferences; macOS only applies them when the Dock restarts.
enum W4Dock {
    private static let domain = "com.apple.dock" as CFString
    private static let backupKey = "W4.DockBackup"

    private static func value(_ key: String) -> Any? {
        CFPreferencesCopyValue(key as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private static func set(_ key: String, _ value: Any) {
        CFPreferencesSetValue(key as CFString, value as AnyObject, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    static func read() -> W4DockValues {
        var values = W4DockValues()
        values.orientation = value("orientation") as? String ?? values.orientation
        values.tilesize = (value("tilesize") as? NSNumber)?.doubleValue ?? values.tilesize
        values.magnification = (value("magnification") as? NSNumber)?.boolValue ?? false
        values.largesize = (value("largesize") as? NSNumber)?.doubleValue ?? values.largesize
        values.autohide = (value("autohide") as? NSNumber)?.boolValue ?? false
        values.autohideDelay = (value("autohide-delay") as? NSNumber)?.doubleValue ?? values.autohideDelay
        values.autohideSpeed = (value("autohide-time-modifier") as? NSNumber)?.doubleValue ?? values.autohideSpeed
        values.mineffect = value("mineffect") as? String ?? values.mineffect
        values.showRecents = (value("show-recents") as? NSNumber)?.boolValue ?? true
        values.staticOnly = (value("static-only") as? NSNumber)?.boolValue ?? false
        values.minimizeToApp = (value("minimize-to-application") as? NSNumber)?.boolValue ?? false
        return values
    }

    private static func encode(_ values: W4DockValues) -> [String: Any] {
        [
            "orientation": values.orientation, "tilesize": values.tilesize, "magnification": values.magnification,
            "largesize": values.largesize, "autohide": values.autohide, "autohide-delay": values.autohideDelay,
            "autohide-time-modifier": values.autohideSpeed, "mineffect": values.mineffect,
            "show-recents": values.showRecents, "static-only": values.staticOnly,
            "minimize-to-application": values.minimizeToApp,
        ]
    }

    /// False when macOS refused the change or the Dock restart.
    static func apply(_ values: W4DockValues) -> Bool {
        let defaults = UserDefaults.appScoped()
        if defaults.dictionary(forKey: backupKey) == nil {
            defaults.set(encode(read()), forKey: backupKey)
        }
        for (key, value) in encode(values) {
            set(key, value)
        }
        return commit()
    }

    static func addSpacer() -> Bool {
        var apps = value("persistent-apps") as? [Any] ?? []
        apps.append(["tile-data": [String: Any](), "tile-type": "spacer-tile"] as [String: Any])
        set("persistent-apps", apps)
        return commit()
    }

    static func restoreBackup() -> W4DockValues? {
        guard let backup = UserDefaults.appScoped().dictionary(forKey: backupKey) else { return nil }
        for (key, value) in backup {
            set(key, value)
        }
        _ = commit()
        return read()
    }

    private static func commit() -> Bool {
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            Logger.warning("Dock preferences could not be saved", category: .general)
            return false
        }
        let docks = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
        let restarted = docks.contains { $0.terminate() || $0.forceTerminate() }
        if !restarted {
            Logger.warning("Dock could not be restarted from the sandbox", category: .general)
        }
        return restarted
    }
}

struct W4DockSection: View {
    @State private var values = W4Dock.read()
    @State private var message: String?

    private static let refused = "macOS không cho app khởi động lại Dock. Mở Terminal, gõ killall Dock để thấy thay đổi."

    var body: some View {
        Section {
            Picker(selection: $values.orientation) {
                Text(verbatim: "Dưới").tag("bottom")
                Text(verbatim: "Trái").tag("left")
                Text(verbatim: "Phải").tag("right")
            } label: {
                Text(verbatim: "Vị trí")
            }
            slider("Cỡ icon", value: $values.tilesize, in: 16 ... 128, format: "%.0f")
            Toggle(isOn: $values.magnification) { Text(verbatim: "Phóng to khi rê chuột") }
            slider("Cỡ khi phóng to", value: $values.largesize, in: 16 ... 128, format: "%.0f")
            Toggle(isOn: $values.autohide) { Text(verbatim: "Tự ẩn Dock") }
            slider("Chờ trước khi hiện (giây)", value: $values.autohideDelay, in: 0 ... 2, format: "%.2f")
            slider("Thời gian trượt (giây)", value: $values.autohideSpeed, in: 0 ... 2, format: "%.2f")
            Picker(selection: $values.mineffect) {
                Text(verbatim: "Genie").tag("genie")
                Text(verbatim: "Scale").tag("scale")
                Text(verbatim: "Suck").tag("suck")
            } label: {
                Text(verbatim: "Hiệu ứng thu nhỏ")
            }
            Toggle(isOn: $values.minimizeToApp) { Text(verbatim: "Thu nhỏ cửa sổ vào icon app") }
            Toggle(isOn: $values.showRecents) { Text(verbatim: "Hiện app dùng gần đây") }
            Toggle(isOn: $values.staticOnly) { Text(verbatim: "Chỉ hiện app đang mở") }
            HStack {
                Button {
                    report(W4Dock.apply(values))
                } label: {
                    Text(verbatim: "Áp dụng cho Dock")
                }
                Button {
                    report(W4Dock.addSpacer())
                } label: {
                    Text(verbatim: "Thêm khoảng trống")
                }
                Button {
                    if let restored = W4Dock.restoreBackup() {
                        values = restored
                        message = nil
                    } else {
                        message = "Chưa đổi gì nên không có gì để khôi phục."
                    }
                } label: {
                    Text(verbatim: "Khôi phục như lúc đầu")
                }
            }
            Text(verbatim: message ?? "Khi áp dụng, Dock sẽ khởi động lại trong giây lát.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(verbatim: "Dock")
        }
    }

    private func report(_ succeeded: Bool) {
        message = succeeded ? nil : Self.refused
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: String) -> some View {
        HStack {
            Text(verbatim: title)
            Slider(value: value, in: range)
            Text(verbatim: String(format: format, value.wrappedValue))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }
}
#endif
