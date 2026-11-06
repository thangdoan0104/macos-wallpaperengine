#if !MAS_BUILD
import AppKit
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
#endif
