#if !LITE_BUILD
import CoreImage
import Foundation
import ImageIO
import LiveWallpaperCore
import UniformTypeIdentifiers

enum W4UpscaleKind: String, CaseIterable, Identifiable, Sendable {
    case illustration, photo

    var id: String { rawValue }
    var label: String { self == .illustration ? "Tranh, anime" : "Ảnh thật, render 3D" }
    var model: String { self == .illustration ? "realesrgan-x4plus-anime" : "realesrgan-x4plus" }
}

enum W4UpscaleError: LocalizedError {
    case unreadable, toolMissing, toolFailed(Int32), writeFailed

    var errorDescription: String? {
        switch self {
        case .unreadable: "Không đọc được hình này."
        case .toolMissing: "Bản này thiếu công cụ AI. Thử kéo Mức AI về 0%."
        case let .toolFailed(code): "Công cụ AI lỗi (mã \(code)). Thử kéo Mức AI về 0%."
        case .writeFailed: "Không lưu được hình."
        }
    }
}

/// Real-ESRGAN (BSD-3-Clause) by Xintao Wang and contributors, blended over a plain enlargement.
enum W4Upscaler {
    private static let targetWidth = 3840.0
    private static let targetHeight = 2160.0
    private static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    /// The AI output is 4x the source (a 1080p picture comes back at 7680x4320); decode it straight at the
    /// size that is kept instead of holding the full bitmap.
    private static func load(_ url: URL, maxPixel: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary)
    }

    private static func scaled(_ image: CIImage, to size: CGSize) -> CIImage {
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(size.height / image.extent.height, forKey: kCIInputScaleKey)
        filter.setValue((size.width / image.extent.width) / (size.height / image.extent.height), forKey: kCIInputAspectRatioKey)
        let output = filter.outputImage ?? image
        return output.cropped(to: CGRect(origin: output.extent.origin, size: size))
    }

    /// An AI amount of 0 only enlarges; higher amounts blend the AI result over that enlargement.
    static func run(input: URL, kind: W4UpscaleKind, aiAmount: Double) throws -> URL {
        try autoreleasepool { try render(input: input, kind: kind, aiAmount: aiAmount) }
    }

    private static func render(input: URL, kind: W4UpscaleKind, aiAmount: Double) throws -> URL {
        // A context per run, without kept intermediates, so nothing stays in memory after the picture is written.
        let context = CIContext(options: [.cacheIntermediates: false])
        defer { context.clearCaches() }
        guard let image = load(input) else { throw W4UpscaleError.unreadable }
        let width = Double(image.width), height = Double(image.height)
        let scale = max(targetWidth / width, targetHeight / height, 1)
        let size = CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
        let base = scaled(CIImage(cgImage: image), to: size)
        var result = base

        if aiAmount > 0.001 {
            let raw = try runAI(input: input, kind: kind)
            defer { try? FileManager.default.removeItem(at: raw) }
            guard let aiImage = load(raw, maxPixel: max(size.width, size.height) * 1.05) else { throw W4UpscaleError.unreadable }
            let ai = scaled(CIImage(cgImage: aiImage), to: size)
            if let mix = CIFilter(name: "CIDissolveTransition") {
                mix.setValue(base.transformed(by: .init(translationX: -base.extent.minX, y: -base.extent.minY)), forKey: kCIInputImageKey)
                mix.setValue(ai.transformed(by: .init(translationX: -ai.extent.minX, y: -ai.extent.minY)), forKey: kCIInputTargetImageKey)
                mix.setValue(aiAmount, forKey: kCIInputTimeKey)
                result = (mix.outputImage ?? base).cropped(to: CGRect(origin: .zero, size: size))
            }
        }

        guard let final = context.createCGImage(result, from: result.extent) else { throw W4UpscaleError.writeFailed }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("w4-4k-\(UUID().uuidString).jpg")
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw W4UpscaleError.writeFailed
        }
        CGImageDestinationAddImage(destination, final, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw W4UpscaleError.writeFailed }
        return output
    }

    private static func runAI(input: URL, kind: W4UpscaleKind) throws -> URL {
        guard let tool = Bundle.main.resourceURL?.appendingPathComponent("Upscaler", isDirectory: true),
              FileManager.default.isExecutableFile(atPath: tool.appendingPathComponent("realesrgan-ncnn-vulkan").path) else {
            throw W4UpscaleError.toolMissing
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("w4-ai-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = tool.appendingPathComponent("realesrgan-ncnn-vulkan")
        process.currentDirectoryURL = tool
        process.arguments = ["-i", input.path, "-o", output.path, "-n", kind.model, "-s", "4", "-m", tool.appendingPathComponent("models").path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        Logger.notice("Upscale tool exited with \(process.terminationStatus)", category: .workshop)
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: output.path) else {
            throw W4UpscaleError.toolFailed(process.terminationStatus)
        }
        return output
    }
}
#endif
