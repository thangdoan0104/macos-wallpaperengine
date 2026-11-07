import AppKit
import LiveWallpaperCore
import SwiftUI

/// w4: free sizing for the Music layer on top of its cell sizes. The box is laid out at `width`×`height`
/// of the chosen size, then the whole widget, text included, is drawn at `scale`.
struct W4MusicSize: Equatable, Sendable {
    static let scaleKey = "w4Scale"
    static let widthKey = "w4Width"
    static let heightKey = "w4Height"
    static let scaleRange: ClosedRange<Double> = 0.3 ... 1.6
    static let widthRange: ClosedRange<Double> = 0.5 ... 3.0
    static let heightRange: ClosedRange<Double> = 0.5 ... 2.0

    var scale = 1.0
    var width = 1.0
    var height = 1.0

    init(scale: Double = 1, width: Double = 1, height: Double = 1) {
        self.scale = Self.clamp(scale, Self.scaleRange)
        self.width = Self.clamp(width, Self.widthRange)
        self.height = Self.clamp(height, Self.heightRange)
    }

    init(_ options: [String: MonitorWidgetOptionValue]) {
        self.init(
            scale: options[Self.scaleKey]?.numberValue ?? 1,
            width: options[Self.widthKey]?.numberValue ?? 1,
            height: options[Self.heightKey]?.numberValue ?? 1
        )
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : 1
    }

    func applied(to options: [String: MonitorWidgetOptionValue]) -> [String: MonitorWidgetOptionValue] {
        var next = options
        for (key, value) in [(Self.scaleKey, scale), (Self.widthKey, width), (Self.heightKey, height)] {
            next[key] = abs(value - 1) < 0.001 ? nil : .number(value)
        }
        return next
    }
}

/// Lays the widget out in the unscaled box, then shrinks or grows it into the frame it was given.
struct W4MusicScaled: ViewModifier {
    let scale: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        if abs(scale - 1) < 0.001 {
            content
        } else {
            GeometryReader { proxy in
                content
                    .frame(width: proxy.size.width / scale, height: proxy.size.height / scale)
                    .scaleEffect(scale, anchor: .topLeading)
            }
        }
    }
}

enum MusicOverlayLayout {
    static let referenceBoardSize = CGSize(width: 1512, height: 982)

    static func cells(for size: MusicOverlaySize) -> (columns: Int, rows: Int) {
        switch size {
        case .small: return (2, 1)
        case .medium: return (3, 1)
        case .large: return (4, 2)
        }
    }

    static func normalizedFootprint(for size: MusicOverlaySize, boardSize: CGSize = referenceBoardSize) -> CGSize {
        let cells = cells(for: size)
        return CGSize(
            width: Double(cells.columns) * MonitorBoardGeometry.appleCellPitch.width / max(1, boardSize.width),
            height: Double(cells.rows) * MonitorBoardGeometry.appleCellPitch.height / max(1, boardSize.height)
        )
    }

    /// Layer rect in board coordinates (y-down from the top edge). Nil when the board has no usable area.
    static func renderRect(
        configuration: MusicOverlayConfiguration,
        boardSize: CGSize,
        safeArea: MonitorSafeAreaInsets
    ) -> CGRect? {
        let geometry = MonitorBoardGeometry(
            boardSize: boardSize,
            safeArea: safeArea
        )
        guard !geometry.isDegenerate else { return nil }
        let cells = cells(for: configuration.size)
        let base = geometry.pixelSize(columns: cells.columns, rows: cells.rows)
        let custom = W4MusicSize(configuration.options)
        let footprint = CGSize(
            width: min(geometry.boardSize.width, (base.width * custom.width * custom.scale).rounded()),
            height: min(geometry.boardSize.height, (base.height * custom.height * custom.scale).rounded())
        )
        let origin = geometry.clampOrigin(
            LayoutEngine.pixelOrigin(
                normalized: CGPoint(x: configuration.x, y: configuration.y),
                boardSize: geometry.boardSize
            ),
            footprint: footprint
        )
        return geometry.renderRect(forRawRect: CGRect(origin: origin, size: footprint))
    }

    // MARK: - Edits

    static func setting(x: Double, y: Double, on configuration: MusicOverlayConfiguration) -> MusicOverlayConfiguration {
        var next = configuration
        next.x = min(max(x, 0), 1)
        next.y = min(max(y, 0), 1)
        return next
    }

    static func setting(size: MusicOverlaySize, on configuration: MusicOverlayConfiguration, boardSize: CGSize = referenceBoardSize) -> MusicOverlayConfiguration {
        var next = configuration
        next.size = size
        let footprint = normalizedFootprint(for: size, boardSize: boardSize)
        next.x = min(max(next.x, 0), max(0, 1 - footprint.width))
        next.y = min(max(next.y, 0), max(0, 1 - footprint.height))
        return next
    }

    #if !MAS_BUILD
    static func settingOptions(
        on configuration: MusicOverlayConfiguration,
        _ transform: (inout NowPlayingOptions) -> Void
    ) -> MusicOverlayConfiguration {
        var options = NowPlayingOptions(configuration.options)
        transform(&options)
        var next = configuration
        next.options = options.applied(to: configuration.options)
        return next
    }
    #endif
}
