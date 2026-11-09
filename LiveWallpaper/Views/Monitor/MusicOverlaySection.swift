#if !MAS_BUILD
import AppKit
import LiveWallpaperCore
import SwiftUI

// MARK: - Section

/// w4: the Music layer's panel, grouped by what is on the layer: layer and size, cover, text,
/// colors, background, progress and buttons, effects, lyric.
struct MusicOverlaySection: View {
    let screen: Screen
    let screenManager: ScreenManager

    @AppStorage("Music.W4.Artwork", store: .appScoped()) private var isArtworkExpanded = true
    @AppStorage("Music.W4.Text", store: .appScoped()) private var isTextExpanded = true
    @AppStorage("Music.W4.Colors", store: .appScoped()) private var isColorsExpanded = true
    @AppStorage("Music.W4.Background", store: .appScoped()) private var isBackgroundExpanded = false
    @AppStorage("Music.W4.Playback", store: .appScoped()) private var isPlaybackExpanded = false
    @AppStorage("Music.EffectsExpanded", store: .appScoped()) private var isEffectsExpanded = false
    @AppStorage("Music.LyricsExpanded", store: .appScoped()) private var isLyricsExpanded = false
    @State private var showingTitleFonts = false

    private var overlay: MonitorOverlayConfiguration {
        screenManager.monitorOverlay(for: screen)
    }

    private var music: MusicOverlayConfiguration {
        overlay.music
    }

    private var isOn: Bool {
        music.enabled
    }

    private var isEditable: Bool {
        isOn
    }

    private var options: NowPlayingOptions {
        NowPlayingOptions(music.options)
    }

    private var look: W4MusicLook {
        W4MusicLook(music.options)
    }

    var body: some View {
        VStack(spacing: 12) {
            layerCard
            artworkCard
            textCard
            colorsCard
            backgroundCard
            playbackCard
            effectsCard
            W4LyricScreenCard(screenName: screen.nsScreen.localizedName, isExpanded: $isLyricsExpanded)
        }
    }

    // MARK: Option plumbing

    private func update(_ transform: (MusicOverlayConfiguration) -> MusicOverlayConfiguration) {
        let current = screenManager.monitorOverlay(for: screen).music
        let next = transform(current)
        guard next != current else { return }
        screenManager.setMusicOverlay(next, for: screen)
    }

    private func updateOptions(_ transform: @escaping (inout NowPlayingOptions) -> Void) {
        update { MusicOverlayLayout.settingOptions(on: $0, transform) }
    }

    private func optionBinding<Value>(
        _ keyPath: WritableKeyPath<NowPlayingOptions, Value>
    ) -> Binding<Value> {
        Binding(
            get: { options[keyPath: keyPath] },
            set: { value in updateOptions { $0[keyPath: keyPath] = value } }
        )
    }

    /// w4 keys live beside Loomscreen's; nil drops a key back to its default.
    private func setKey(_ key: String, _ value: MonitorWidgetOptionValue?) {
        update { current in
            var next = current
            next.options[key] = value
            return next
        }
    }

    private func setNumber(_ key: String) -> (Double) -> Void {
        { value in setKey(key, .number(value)) }
    }

    // MARK: Building blocks

    private func card<Content: View>(
        _ title: LocalizedStringKey, icon: String, expanded: Binding<Bool>, @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            CollapsibleSection(title: title, systemImage: icon, isExpanded: expanded) {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .disabled(!isEditable)
            }
        }
        .groupBoxStyle(ContainerGroupBoxStyle())
    }

    private func toggle(_ title: LocalizedStringKey, icon: String, color: Color = .purple, isOn: Binding<Bool>) -> some View {
        SettingRow(icon: icon, iconColor: color, title: title) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(Text(title))
        }
    }

    private func w4Toggle(_ title: LocalizedStringKey, icon: String, key: String, value: Bool, fallback: Bool = false) -> some View {
        toggle(title, icon: icon, isOn: Binding(get: { value }, set: { setKey(key, $0 == fallback ? nil : .bool($0)) }))
    }

    /// A segmented choice under its own title, so long Vietnamese labels never squeeze into a narrow trailing slot.
    private func choice<Value: Hashable>(
        _ title: LocalizedStringKey, icon: String, color: Color = .purple,
        selection: Binding<Value>, values: [(Value, String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingRow(icon: icon, iconColor: color, title: title) { EmptyView() }
            Picker("", selection: selection) {
                ForEach(values.indices, id: \.self) { index in
                    Text(verbatim: values[index].1).tag(values[index].0)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text(title))
        }
    }

    private func colorRow(_ title: LocalizedStringKey, icon: String, hex: String?, fallback: Color, write: @escaping (String) -> Void) -> some View {
        SettingRow(icon: icon, iconColor: .pink, title: title) {
            ColorPicker("", selection: Binding(
                get: { hex.flatMap { NowPlayingOptions.accentColor(fromHex: $0)?.color } ?? fallback },
                set: { color in
                    guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                    write(NowPlayingOptions.hexString(for: NowPlayingAccentColor(
                        red: Double(srgb.redComponent),
                        green: Double(srgb.greenComponent),
                        blue: Double(srgb.blueComponent)
                    )))
                }
            ), supportsOpacity: false)
            .labelsHidden()
            .accessibilityLabel(Text(title))
        }
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text)
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private static func multiplier(_ value: Double) -> String {
        String(format: "%.2f×", value)
    }

    private static func degrees(_ value: Double) -> String {
        String(format: "%.0f°", value)
    }

    // MARK: 1 · Layer and size

    private var size: W4MusicSize { W4MusicSize(music.options) }

    private func setSize(_ next: W4MusicSize) {
        update { current in
            var copy = current
            copy.options = next.applied(to: current.options)
            return copy
        }
    }

    private var layerCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                choice("Nằm ở", icon: "square.stack.3d.up", color: .blue, selection: Binding(
                    get: { music.level },
                    set: { screenManager.setMusicOverlayLevel($0, for: screen) }
                ), values: [(.desktop, "Dưới cửa sổ"), (.front, "Trên mọi cửa sổ")])
                Divider()
                choice("Kiểu", icon: "paintpalette", selection: Binding(
                    get: { NowPlayingWidgetView.style(music.options) },
                    set: { style in updateOptions { $0.style = style } }
                ), values: [(.poster, "Poster"), (.vinyl, "Đĩa than"), (.aurora, "Aurora")])
                Divider()
                choice("Khung cơ bản", icon: "square.grid.2x2", color: .blue, selection: Binding(
                    get: { music.size },
                    set: { value in update { MusicOverlayLayout.setting(size: value, on: $0, boardSize: screen.frame.size) } }
                ), values: [(.small, "Nhỏ"), (.medium, "Vừa"), (.large, "Lớn")])
                Divider()
                let current = size
                MusicOptionSlider(icon: "plus.magnifyingglass", iconColor: .blue, title: "Độ to", range: W4MusicSize.scaleRange,
                                  value: current.scale, format: Self.percent) { value in
                    setSize(W4MusicSize(scale: value, width: current.width, height: current.height))
                }
                MusicOptionSlider(icon: "arrow.left.and.right", iconColor: .blue, title: "Độ dài", range: W4MusicSize.widthRange,
                                  value: current.width, format: Self.percent) { value in
                    setSize(W4MusicSize(scale: current.scale, width: value, height: current.height))
                }
                MusicOptionSlider(icon: "arrow.up.and.down", iconColor: .blue, title: "Độ cao", range: W4MusicSize.heightRange,
                                  value: current.height, format: Self.percent) { value in
                    setSize(W4MusicSize(scale: current.scale, width: current.width, height: value))
                }
                note("Hoặc kéo trên khung: góc dưới phải để to nhỏ, cạnh phải để dài ra, cạnh dưới để cao lên.")
            }
            .disabled(!isOn)
        }
        .groupBoxStyle(ContainerGroupBoxStyle())
    }

    // MARK: 2 · Cover

    private var artworkCard: some View {
        card("Ảnh bìa", icon: "photo", expanded: $isArtworkExpanded) {
            if options.style == .aurora {
                note("Kiểu Aurora không có ảnh bìa. Chọn Poster hoặc Đĩa than để dùng phần này.")
            }
            toggle("Hiện ảnh bìa", icon: "photo", color: .pink, isOn: optionBinding(\.showArtwork))
            Group {
                Divider()
                choice("Vị trí", icon: "rectangle.lefthalf.inset.filled", selection: Binding(
                    get: { look.place },
                    set: { setKey(W4MusicLook.Key.place, $0 == .auto ? nil : .string($0.rawValue)) }
                ), values: W4MusicLook.Place.allCases.map { ($0, $0.label) })
                note("Tự động: ảnh nằm cùng phía với chữ.")
                Divider()
                choice("Hình dạng", icon: "square.on.circle", selection: optionBinding(\.artworkShape),
                       values: [(.rounded, "Bo góc"), (.circle, "Tròn"), (.square, "Vuông")])
                if options.artworkShape == .rounded {
                    MusicOptionSlider(icon: "square.dashed", iconColor: .purple, title: "Độ bo góc", range: 0 ... 1,
                                      value: look.radius ?? 0.05, format: Self.percent, commit: setNumber(W4MusicLook.Key.radius))
                }
                MusicOptionSlider(icon: "arrow.up.left.and.arrow.down.right", iconColor: .blue, title: "Cỡ ảnh",
                                  range: NowPlayingOptions.Limits.artworkScale, value: options.artworkScale,
                                  format: Self.multiplier) { value in updateOptions { $0.artworkScale = value } }
                MusicOptionSlider(icon: "arrow.left.and.right", iconColor: .purple, title: "Cách chữ", range: 0 ... 4,
                                  value: look.gap, format: Self.multiplier, commit: setNumber(W4MusicLook.Key.gap))
                Divider()
                MusicOptionSlider(icon: "rotate.right", iconColor: .purple, title: "Nghiêng", range: -30 ... 30,
                                  value: look.tilt, format: Self.degrees, commit: setNumber(W4MusicLook.Key.tilt))
                MusicOptionSlider(icon: "shadow", iconColor: .gray, title: "Bóng đổ",
                                  range: NowPlayingOptions.Limits.artworkShadow, value: options.artworkShadow,
                                  format: Self.percent) { value in updateOptions { $0.artworkShadow = value } }
                MusicOptionSlider(icon: "square.on.square", iconColor: .purple, title: "Viền", range: 0 ... 1,
                                  value: look.border, format: Self.percent, commit: setNumber(W4MusicLook.Key.border))
                MusicOptionSlider(icon: "sun.max", iconColor: .orange, title: "Phát sáng", range: 0 ... 1,
                                  value: look.glow, format: Self.percent, commit: setNumber(W4MusicLook.Key.glow))
                note("Viền và phát sáng dùng màu sóng nhạc ở phần Màu.")
                Divider()
                w4Toggle("Xoay khi đang phát", icon: "record.circle", key: W4MusicLook.Key.spin, value: look.spin)
                if look.spin {
                    MusicOptionSlider(icon: "speedometer", iconColor: .purple, title: "Tốc độ xoay", range: 0.2 ... 4,
                                      value: look.spinSpeed, format: Self.multiplier, commit: setNumber(W4MusicLook.Key.spinSpeed))
                }
            }
            .disabled(!options.showArtwork)
        }
    }

    // MARK: 3 · Text

    private var titleFontName: String {
        if !look.titleFamily.isEmpty { return look.titleFamily }
        switch options.resolvedTitleFont {
        case .serif: return "Có chân"
        case .rounded: return "Bo tròn"
        case .monospaced: return "Đơn sắc"
        case .system: return "Hệ thống"
        }
    }

    private var textCard: some View {
        card("Chữ", icon: "text.alignleft", expanded: $isTextExpanded) {
            SettingRow(icon: "textformat", iconColor: .indigo, title: "Phông tên bài") {
                Button {
                    showingTitleFonts = true
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: titleFontName).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .frame(minWidth: 110, maxWidth: 180)
                }
                .popover(isPresented: $showingTitleFonts, arrowEdge: .bottom) {
                    VStack(spacing: 8) {
                        Picker("", selection: Binding(
                            get: { look.titleFamily.isEmpty ? options.resolvedTitleFont : nil },
                            set: { design in
                                guard let design else { return }
                                setKey(W4MusicLook.Key.titleFamily, nil)
                                updateOptions { $0.titleFont = design }
                            }
                        )) {
                            Text(verbatim: "Có chân").tag(NowPlayingOptions.TitleFont?.some(.serif))
                            Text(verbatim: "Bo tròn").tag(NowPlayingOptions.TitleFont?.some(.rounded))
                            Text(verbatim: "Đơn sắc").tag(NowPlayingOptions.TitleFont?.some(.monospaced))
                            Text(verbatim: "Hệ thống").tag(NowPlayingOptions.TitleFont?.some(.system))
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .padding([.horizontal, .top], 10)
                        W4FontPicker(
                            controller: W4LyricController.shared,
                            family: Binding(
                                get: { look.titleFamily },
                                set: { setKey(W4MusicLook.Key.titleFamily, $0.isEmpty ? nil : .string($0)) }
                            ),
                            bold: true,
                            previewsOnLyric: false,
                            sampleText: "Tên bài hát"
                        )
                    }
                }
            }
            MusicOptionSlider(icon: "textformat.size", iconColor: .teal, title: "Cỡ tên bài",
                              range: NowPlayingOptions.Limits.titleScale, value: options.titleScale,
                              format: Self.multiplier) { value in updateOptions { $0.titleScale = value } }
            choice("Căn lề", icon: "text.alignleft", color: .blue, selection: Binding(
                get: { options.resolvedAlignment },
                set: { value in updateOptions { $0.alignment = value } }
            ), values: [(.leading, "Trái"), (.center, "Giữa"), (.trailing, "Phải")])
            toggle("Cuộn tên dài", icon: "arrow.left.arrow.right", isOn: optionBinding(\.marquee))
            Divider()
            toggle("Hiện ca sĩ", icon: "person.wave.2", color: .orange, isOn: optionBinding(\.showArtist))
            toggle("Hiện album", icon: "square.stack", color: .yellow, isOn: optionBinding(\.showAlbum))
            w4Toggle("Ca sĩ, album viết hoa", icon: "textformat", key: W4MusicLook.Key.eyebrowUpper,
                     value: look.eyebrowUpper, fallback: true)
            MusicOptionSlider(icon: "character", iconColor: .purple, title: "Giãn chữ ca sĩ", range: 0 ... 12,
                              value: look.tracking, format: { String(format: "%.0f", $0) },
                              commit: setNumber(W4MusicLook.Key.tracking))
            Divider()
            MusicOptionSlider(icon: "sun.max", iconColor: .orange, title: "Độ sáng chữ",
                              range: NowPlayingOptions.Limits.textBrightness, value: options.textBrightness,
                              format: Self.percent) { value in updateOptions { $0.textBrightness = value } }
        }
    }

    // MARK: 4 · Colors

    private var waveHex: String? {
        music.options[W4WaveColor.key]?.stringValue.flatMap(NowPlayingOptions.canonicalHex)
    }

    private var colorsCard: some View {
        card("Màu", icon: "paintbrush", expanded: $isColorsExpanded) {
            choice("Màu chính", icon: "eyedropper", color: .pink, selection: optionBinding(\.accentSource),
                   values: [(.albumArt, "Lấy từ ảnh bìa"), (.custom, "Tự chọn")])
            if options.accentSource == .custom {
                colorRow("Chọn màu chính", icon: "paintpalette", hex: options.customAccentHex, fallback: Design.signalAmber) { hex in
                    updateOptions { $0.customAccentHex = hex }
                }
            }
            note("Màu chính tô thanh tiến độ, vòng đĩa và hiệu ứng.")
            Divider()
            choice("Màu sóng nhạc", icon: "waveform", color: .orange, selection: Binding(
                get: { waveHex != nil },
                set: { custom in setKey(W4WaveColor.key, custom ? .string(options.customAccentHex ?? "#FFC857") : nil) }
            ), values: [(false, "Theo màu chính"), (true, "Màu riêng")])
            if waveHex != nil {
                colorRow("Chọn màu sóng", icon: "paintpalette", hex: waveHex, fallback: Design.signalAmber) { hex in
                    setKey(W4WaveColor.key, .string(hex))
                }
            }
            Divider()
            MusicOptionSlider(icon: "circle.lefthalf.filled", iconColor: .indigo, title: "Độ đậm cả lớp",
                              range: NowPlayingOptions.Limits.opacity, value: options.opacity,
                              format: Self.percent) { value in updateOptions { $0.opacity = value } }
        }
    }

    // MARK: 5 · Background

    private var backgroundCard: some View {
        card("Nền", icon: "rectangle.fill", expanded: $isBackgroundExpanded) {
            MusicOptionSlider(icon: "rectangle.fill", iconColor: .gray, title: "Độ đậm nền", range: 0 ... 1,
                              value: look.card, format: Self.percent, commit: setNumber(W4MusicLook.Key.card))
            MusicOptionSlider(icon: "square.dashed", iconColor: .gray, title: "Bo góc nền", range: 0 ... 1,
                              value: look.cardRadius, format: Self.percent, commit: setNumber(W4MusicLook.Key.cardRadius))
            w4Toggle("Kính mờ", icon: "drop", key: W4MusicLook.Key.blur, value: look.blur)
            w4Toggle("Nền theo màu sóng nhạc", icon: "paintpalette", key: W4MusicLook.Key.cardTint, value: look.cardTint)
            w4Toggle("Viền nền", icon: "square", key: W4MusicLook.Key.cardEdge, value: look.cardEdge)
        }
    }

    // MARK: 6 · Progress and buttons

    private var playbackCard: some View {
        card("Tiến độ và nút phát", icon: "playpause", expanded: $isPlaybackExpanded) {
            toggle("Hiện thanh tiến độ", icon: "timeline.selection", color: .green, isOn: optionBinding(\.showProgress))
            toggle("Kéo thanh tiến độ để tua", icon: "hand.draw", color: .blue, isOn: optionBinding(\.seekOnProgressDrag))
                .disabled(!options.showProgress)
            Divider()
            toggle("Nút phát khi rê chuột", icon: "playpause.circle", color: .green, isOn: optionBinding(\.showControls))
            Group {
                choice("Vị trí nút", icon: "rectangle.inset.topright.filled", color: .green, selection: Binding(
                    get: { look.controlsPlace },
                    set: { setKey(W4MusicLook.Key.controlsPlace, $0 == .auto ? nil : .string($0.rawValue)) }
                ), values: W4MusicLook.ControlsPlace.allCases.map { ($0, $0.label) })
                note("Tự động: nút nằm phía trên, đối diện ảnh bìa.")
                MusicOptionSlider(icon: "plus.magnifyingglass", iconColor: .green, title: "Cỡ nút", range: 0.6 ... 2,
                                  value: look.controlsScale, format: Self.multiplier,
                                  commit: setNumber(W4MusicLook.Key.controlsScale))
            }
            .disabled(!options.showControls)
            MusicPlaybackPermissionCaption()
        }
    }

    // MARK: 7 · Effects

    @ViewBuilder
    private var effectsCard: some View {
        #if !LITE_BUILD
        card("Hiệu ứng theo nhạc", icon: "waveform", expanded: $isEffectsExpanded) {
            if !SettingsManager.shared.loadGlobalSettings().audioResponseEnabled {
                note("Cần bật Phản hồi âm thanh trong Cài đặt để sóng nhạc và hiệu ứng chạy.")
            }
            toggle("Sóng nhạc và hiệu ứng", icon: "waveform", color: .green, isOn: optionBinding(\.audioReactive))
            Group {
                MusicOptionSlider(icon: "dial.medium", iconColor: .green, title: "Cường độ",
                                  range: NowPlayingOptions.Limits.audioIntensity, value: options.audioIntensity,
                                  format: Self.multiplier) { value in updateOptions { $0.audioIntensity = value } }
                MusicOptionSlider(icon: "metronome", iconColor: .orange, title: "Độ nhạy nhịp",
                                  range: NowPlayingOptions.Limits.beatSensitivity, value: options.beatSensitivity,
                                  format: Self.multiplier) { value in updateOptions { $0.beatSensitivity = value } }
                Divider()
                toggle("Nhún theo nhịp", icon: "rays", color: .yellow, isOn: optionBinding(\.effectPulse))
                toggle("Tách màu", icon: "camera.filters", color: .cyan, isOn: optionBinding(\.effectChromatic))
                toggle("Rung", icon: "waveform.path.ecg", color: .red, isOn: optionBinding(\.effectShake))
                toggle("Gợn sóng", icon: "circle.circle", color: .blue, isOn: optionBinding(\.effectRipple))
            }
            .disabled(!options.audioReactive)
        }
        #endif
    }
}

// MARK: - Option slider

/// Commits on release, not on every tick: each commit rewrites the whole settings blob.
private struct MusicOptionSlider: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    let range: ClosedRange<Double>
    let value: Double
    let format: (Double) -> String
    let commit: (Double) -> Void

    /// Non-nil only while a drag is in flight.
    @State private var draft: Double?

    var body: some View {
        let live = draft ?? value
        SettingRow(icon: icon, iconColor: iconColor, title: title) {
            HStack(spacing: DesignTokens.Inspector.sliderValueSpacing) {
                Slider(
                    value: Binding(get: { live }, set: { draft = $0 }),
                    in: range,
                    onEditingChanged: { editing in
                        guard !editing else { return }
                        if let draft {
                            commit(draft)
                        }
                        draft = nil
                    }
                )
                .controlSize(.small)
                .frame(minWidth: 56, maxWidth: DesignTokens.Inspector.sliderWidth)
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(verbatim: format(live)))
                Text(verbatim: format(live))
                    .font(DesignTokens.Typography.metric)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .help(Text(verbatim: format(live)))
                    .frame(width: DesignTokens.Inspector.sliderValueWidth, alignment: .trailing)
            }
        }
    }
}

// MARK: - Playback permission caption

/// Reads the cached authorization periodically; the initial refresh does not prompt.
private struct MusicPlaybackPermissionCaption: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            caption
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            await NowPlayingController.shared.refreshAuthorization(
                for: NowPlayingMonitor.shared.currentState.playerBundleID
            )
        }
    }

    @ViewBuilder
    private var caption: some View {
        switch NowPlayingController.shared.authorization(
            for: NowPlayingMonitor.shared.currentState.playerBundleID
        ) {
        case .denied:
            Text("Playback control denied. Enable access in System Settings → Privacy & Security → Automation.")
        case .authorized:
            EmptyView()
        case .notDetermined:
            Text("Playback control requires Automation permission on first use.")
        }
    }
}
#endif
