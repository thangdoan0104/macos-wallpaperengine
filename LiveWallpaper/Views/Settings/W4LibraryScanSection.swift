#if !LITE_BUILD
import AppKit
import LiveWallpaperCore
import SwiftUI

/// w4: says what the library scan found, so an item missing from the library has a visible reason.
struct W4LibraryScanSection: View {
    @Environment(WorkshopSetupController.self) private var controller
    @State private var report = W4LibraryScanReport.shared

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                ForEach(lines, id: \.self) { line in
                    Text(verbatim: line)
                        .font(DesignTokens.Typography.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    Task { await controller.w4ForceRescan() }
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        if report.isScanning {
                            ProgressView().controlSize(.small)
                        }
                        Text(verbatim: "Quét lại ngay")
                    }
                }
                .disabled(report.isScanning)

                if !report.deletedIDs.isEmpty {
                    Button {
                        Task { await controller.w4RestoreDeleted(report.deletedIDs) }
                    } label: {
                        Text(verbatim: "Hiện lại \(report.deletedIDs.count) item đã xoá")
                    }
                    .disabled(report.isScanning)
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
                } label: {
                    Text(verbatim: "Sao chép")
                }
                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } header: {
            Text(verbatim: "Quét thư viện Steam")
        }
        .task {
            if report.finishedAt == nil {
                await controller.w4ForceRescan()
            }
        }
    }

    private var lines: [String] {
        guard let finishedAt = report.finishedAt else { return ["Chưa quét lần nào."] }
        guard report.hasAccess else {
            return [
                "Không đọc được thư mục Steam, nên không thấy được item nào.",
                "Cấp quyền lại ở phần thư viện Steam phía trên và chọn thư mục Steam của WinDock.",
            ]
        }
        var result = [
            "Lần quét cuối: \(finishedAt.formatted(date: .omitted, time: .standard))",
            "Thư mục: \(report.libraryPath ?? "—")",
            "Item trong thư mục: \(report.foldersOnDisk), đã có trong thư viện: \(report.inLibrary), vừa thêm: \(report.added)",
        ]
        let incomplete = report.foldersOnDisk - report.foldersWithProject
        if incomplete > 0 {
            result.append("Chưa có project.json (chưa tải xong?): \(incomplete)")
        }
        if report.stillDownloading > 0 {
            result.append("Steam còn đang tải: \(report.stillDownloading)")
        }
        if report.relinked > 0 {
            result.append("Nối lại: \(report.relinked)")
        }
        if report.conflicts > 0 {
            result.append("Trùng với item ở thư mục khác: \(report.conflicts)")
        }
        if !report.deletedIDs.isEmpty {
            result.append("Đã xoá khỏi thư viện trước đây nên bị ẩn: \(report.deletedIDs.joined(separator: ", "))")
        }
        if !report.presets.isEmpty {
            result.append("Là preset, nằm trong phần preset của scene gốc: \(report.presets.joined(separator: ", "))")
        }
        for line in report.skipped {
            result.append("Không nhận: \(line)")
        }
        return result
    }
}
#endif
