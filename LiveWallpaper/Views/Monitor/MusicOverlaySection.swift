#if !MAS_BUILD
import AppKit
import LiveWallpaperCore
import SwiftUI

// MARK: - Section

struct MusicOverlaySection: View {
    let screen: Screen
    let screenManager: ScreenManager

    @AppStorage("Music.AppearanceExpanded", store: .appScoped()) private var isAppearanceExpanded = true
    @AppStorage("Music.TypographyExpanded", store: .appScoped()) private var isTypographyExpanded = true
    @AppStorage("Music.ElementsExpanded", store: .appScoped()) private var isElementsExpanded = true
    @AppStorage("Music.LyricsExpanded", store: .appScoped()) private var isLyricsExpanded = false
    @AppStorage("Music.PlaybackExpanded", store: .appScoped()) private var isPlaybackExpanded = true
    @AppStorage("Music.EffectsExpanded", store: .appScoped()) private var isEffectsExpanded = false
    @AppStorage("Music.W4CreativeExpanded", store: .appScoped()) private var isW4CreativeExpanded = true
    @State private var w4ShowingFonts = false

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

    var body: some View {
        VStack(spacing: 12) {
            controlCard
            w4CreativeCard
            appearanceCard
            typographyCard
            elementsCard
            #if !MAS_BUILD
            W4LyricScreenCard(screenName: screen.nsScreen.localizedName, isExpanded: $isLyricsExpanded)
            #else
            lyricsCard
            #endif
            playbackCard
            effectsCard
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

    private var controlCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                layerRow
                Divider()
                styleRow
                Divider()
                sizeRow
                Divider()
                w4SizeSliders
                #if !LITE_BUILD
                // Keyed to the switch, not the live tap: demand-driven capture is legitimately
                // idle while music is paused.
                if !SettingsManager.shared.loadGlobalSettings().audioResponseEnabled {
                    Text("Audio-reactive visuals need Audio Response turned on in Settings.")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                #endif
            }
        }
        .groupBoxStyle(ContainerGroupBoxStyle())
    }

    private var layerRow: some View {
        SettingRow(
            icon: "square.stack.3d.up",
            iconColor: .blue,
            title: "Layer",
            info: "Desktop: below windows. On Top: above windows."
        ) {
            GlassSegmentedPicker(
                selection: Binding(
                    get: { music.level },
                    set: { screenManager.setMusicOverlayLevel($0, for: screen) }
                ),
                values: [.desktop, .front],
                shell: .flat,
                title: { (level: MonitorOverlayLevel) in
                    level == .desktop ? "Desktop" : "On Top"
                }
            )
            .frame(width: 180)
            .disabled(!isOn)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Music layer"))
        }
    }

    private var styleRow: some View {
        SettingRow(
            icon: "paintpalette",
            iconColor: .purple,
            title: "Style"
        ) {
            GlassSegmentedPicker(
                selection: styleBinding,
                values: [.poster, .vinyl, .aurora],
                shell: .flat,
                title: { (style: NowPlayingWidgetView.Style) in
                    switch style {
                    case .poster: "Poster"
                    case .vinyl: "Vinyl"
                    case .aurora: "Aurora"
                    }
                }
            )
            .frame(width: 180)
            .disabled(!isOn)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Style"))
        }
    }

    private var styleBinding: Binding<NowPlayingWidgetView.Style> {
        Binding(
            get: { NowPlayingWidgetView.style(music.options) },
            set: { style in updateOptions { $0.style = style } }
        )
    }

    private var sizeRow: some View {
        SettingRow(
            icon: "arrow.up.left.and.arrow.down.right",
            iconColor: .blue,
            title: "Size"
        ) {
            GlassSegmentedPicker(
                selection: sizeBinding,
                values: MusicOverlaySize.allCases,
                shell: .flat,
                title: { Self.sizeLabel($0) }
            )
            .frame(width: 170)
            .disabled(!isOn)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Widget size"))
        }
    }

    private var w4Size: W4MusicSize { W4MusicSize(music.options) }

    private func setW4Size(_ size: W4MusicSize) {
        update { current in
            var next = current
            next.options = size.applied(to: current.options)
            return next
        }
    }

    /// w4: the same sizes the handles on the layer drag, for exact values.
    @ViewBuilder
    private var w4SizeSliders: some View {
        let size = w4Size
        MusicOptionSlider(icon: "plus.magnifyingglass", iconColor: .blue, title: "Độ to", range: W4MusicSize.scaleRange,
                          value: size.scale, format: Self.percent) { value in
            setW4Size(W4MusicSize(scale: value, width: size.width, height: size.height))
        }
        .disabled(!isOn)
        MusicOptionSlider(icon: "arrow.left.and.right", iconColor: .blue, title: "Độ dài", range: W4MusicSize.widthRange,
                          value: size.width, format: Self.percent) { value in
            setW4Size(W4MusicSize(scale: size.scale, width: value, height: size.height))
        }
        .disabled(!isOn)
        MusicOptionSlider(icon: "arrow.up.and.down", iconColor: .blue, title: "Độ cao", range: W4MusicSize.heightRange,
                          value: size.height, format: Self.percent) { value in
            setW4Size(W4MusicSize(scale: size.scale, width: size.width, height: value))
        }
        .disabled(!isOn)
        Text(verbatim: "Hoặc kéo trực tiếp trên khung: góc dưới phải để to nhỏ, cạnh phải để dài ra, cạnh dưới để cao lên.")
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sizeBinding: Binding<MusicOverlaySize> {
        Binding(
            get: { music.size },
            set: { size in update { MusicOverlayLayout.setting(size: size, on: $0, boardSize: screen.frame.size) } }
        )
    }

    private static func sizeLabel(_ size: MusicOverlaySize) -> LocalizedStringKey {
        switch size {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    // MARK: Appearance

    private var appearanceCard: some View {
        GroupBox {
            CollapsibleSection(
                title: "Appearance",
                systemImage: "paintbrush",
                isExpanded: $isAppearanceExpanded
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    accentRow
                    if options.accentSource == .custom {
                        Divider()
                        accentColorRow
                    }
                    Divider()
                    w4WaveRow
                    Divider()
                    MusicOptionSlider(
                        icon: "circle.lefthalf.filled",
                        iconColor: .indigo,
                        title: "Opacity",
                        range: NowPlayingOptions.Limits.opacity,
                        value: options.opacity,
                        format: Self.percent
                    ) { value in updateOptions { $0.opacity = value } }
                    Divider()
                    MusicOptionSlider(
                        icon: "sun.max",
                        iconColor: .orange,
                        title: "Text brightness",
                        range: NowPlayingOptions.Limits.textBrightness,
                        value: options.textBrightness,
                        format: Self.percent
                    ) { value in updateOptions { $0.textBrightness = value } }
                }
                .disabled(!isEditable)
            }
        }
        .groupBoxStyle(ContainerGroupBoxStyle())
    }

    private var accentRow: some View {
        SettingRow(
            icon: "eyedropper",
            iconColor: .pink,
            title: "Accent"
        ) {
            GlassSegmentedPicker(
                selection: optionBinding(\.accentSource),
                values: [.albumArt, .custom],
                shell: .flat,
                title: { (source: NowPlayingOptions.AccentSource) in
                    source == .albumArt ? "Album art" : "Custom color"
                }
            )
            .frame(maxWidth: 210)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Accent"))
        }
    }

    private var w4WaveHex: String? {
        music.options[W4WaveColor.key]?.stringValue.flatMap(NowPlayingOptions.canonicalHex)
    }

    private func setW4WaveHex(_ hex: String?) {
        update { current in
            var next = current
            next.options[W4WaveColor.key] = hex.map(MonitorWidgetOptionValue.string)
            return next
        }
    }

    /// w4: a color for the audio wave alone.
    private var w4WaveRow: some View {
        SettingRow(icon: "waveform", iconColor: .orange, title: "Màu sóng nhạc") {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Toggle(isOn: Binding(
                    get: { w4WaveHex != nil },
                    set: { custom in
                        setW4WaveHex(custom ? (options.customAccentHex ?? "#FFC857") : nil)
                    }
                )) {
                    Text(verbatim: "Màu riêng")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                if w4WaveHex != nil {
                    ColorPicker("", selection: Binding(
                        get: { NowPlayingOptions.accentColor(fromHex: w4WaveHex ?? "")?.color ?? Design.signalAmber },
                        set: { color in
                            guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                            setW4WaveHex(NowPlayingOptions.hexString(for: NowPlayingAccentColor(
                                red: Double(srgb.redComponent),
                                green: Double(srgb.greenComponent),
                                blue: Double(srgb.blueComponent)
                            )))
                        }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityLabel(Text(verbatim: "Màu sóng nhạc"))
                }
            }
        }
    }

    private var accentColorRow: some View {
        SettingRow(icon: "paintpalette", iconColor: .pink, title: "Color") {
            ColorPicker("", selection: customAccentBinding, supportsOpacity: false)
                .labelsHidden()
                .accessibilityLabel(Text("Color"))
        }
    }

    /// The catalog stores `#RRGGBB`; the picker hands back whatever color space
    /// the system panel was in, so it is converted to sRGB before writing.
    private var customAccentBinding: Binding<Color> {
        Binding(
            get: {
                NowPlayingOptions.accentColor(fromHex: options.customAccentHex ?? "")?.color
                    ?? Design.signalAmber
            },
            set: { color in
                guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                let hex = NowPlayingOptions.hexString(for: NowPlayingAccentColor(
                    red: Double(srgb.redComponent),
                    green: Double(srgb.greenComponent),
                    blue: Double(srgb.blueComponent)
                ))
                updateOptions { $0.customAccentHex = hex }
            }
        )
    }

    // MARK: Typography

    private var typographyCard: some View {
        GroupBox {
            CollapsibleSection(
                title: "Typography",
                // Avoid textformat's system-language glyph when the app uses another language.
                systemImage: "text.alignleft",
                isExpanded: $isTypographyExpanded
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    titleFontRow
                    Divider()
                    alignmentRow
                    Divider()
                    MusicOptionSlider(
                        icon: "textformat.size",
                        iconColor: .teal,
                        title: "Title size",
                        range: NowPlayingOptions.Limits.titleScale,
                        value: options.titleScale,
                        format: Self.multiplier
                    ) { value in updateOptions { $0.titleScale = value } }
                    Divider()
                    marqueeRow
                }
                .disabled(!isEditable)
            }
        }
        .groupBoxStyle(ContainerGroupBoxStyle())
    }

    private var titleFontRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingRow(icon: "character.book.closed", iconColor: .indigo, title: "Title font") {
                EmptyView()
            }
            GlassSegmentedPicker(
                selection: Binding(
                    get: { options.resolvedTitleFont },
                    set: { font in updateOptions { $0.titleFont = font } }
                ),
                values: [.serif, .rounded, .monospaced, .system],
                shell: .flat,
                title: { (font: NowPlayingOptions.TitleFont) in
                    switch font {
                    case .serif: "Serif"
                    case .rounded: "Rounded"
                    case .monospaced: "Mono"
                    case .system: "System"
                    }
                }
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Title font"))
        }
    }

    private var alignmentRow: some View {
        SettingRow(icon: "text.alignleft", iconColor: .blue, title: "Alignment") {
            GlassSegmentedPicker(
                selection: Binding(
                    get: { options.resolvedAlignment },
                    set: { value in updateOptions { $0.alignment = value } }
                ),
                values: [.leading, .center, .trailing],
                shell: .flat,
                title: { (alignment: NowPlayingOptions.Alignment) in
                    switch alignment {
                    case .leading: "Left"
                    case .center: "Center"
                    case .trailing: "Right"
                    }
                }
            )
            .frame(width: 160)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Alignment"))
        }
    }

    private var marqueeRow: some View {
        SettingRow(
            icon: "arrow.left.arrow.right",
            iconColor: .purple,
            title: "Scroll long titles"
        ) {
            Toggle("", isOn: optionBinding(\.marquee))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(Text("Scroll long titles"))
        }
    }

    // MARK: Elements

    private var elementsCard: some View {
        GroupBox {
            CollapsibleSection(
                title: "Elements",
                systemImage: "square.stack.3d.down.right",
                isExpanded: $isElementsExpanded
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    elementToggle(icon: "photo", color: .pink, title: "Artwork", binding: optionBinding(\.showArtwork))
                    Divider()
                    elementToggle(icon: "person.wave.2", color: .orange, title: "Artist", binding: optionBinding(\.showArtist))
                    Divider()
                    elementToggle(icon: "square.stack", color: .yellow, title: "Album", binding: optionBinding(\.showAlbum))
                    Divider()
                    elementToggle(icon: "timeline.selection", color: .green, title: "Progress", binding: optionBinding(\.showProgress))
                    Divider()
                    artworkShapeRow
                    Divider()
                    MusicOptionSlider(
                        icon: "shadow",
                        iconColor: .gray,
                        title: "Artwork shadow",
                        range: NowPlayingOptions.Limits.artworkShadow,
                        value: options.artworkShadow,
                        format: Self.percent
                    ) { value in updateOptions { $0.artworkShadow = value } }
                    Divider()
                    MusicOptionSlider(
                        icon: "arrow.up.left.and.arrow.down.right",
                        iconColor: .blue,
                        title: "Artwork size",
                        range: NowPlayingOptions.Limits.artworkScale,
                        value: options.artworkScale,
                        format: Self.multiplier
                    ) { value in updateOptions { $0.artworkScale = value } }
                }
                .disabled(!isEditable)
            }
        }
        .groupBoxStyle(ContainerGroupBoxStyle())
    }

    private func elementToggle(
        icon: String, color: Color, title: LocalizedStringKey, binding: Binding<Bool>,
        info: String.LocalizationValue? = nil
    ) -> some View {
        SettingRow(icon: icon, iconColor: color, title: title, info: info) {
            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(Text(title))
        }
    }

    private var artworkShapeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingRow(icon: "square.on.circle", iconColor: .purple, title: "Artwork shape") {
                EmptyView()
            }
            GlassSegmentedPicker(
                selection: optionBinding(\.artworkShape),
                values: [.rounded, .circle, .square],
                shell: .flat,
                title: { (shape: NowPlayingOptions.ArtworkShape) in
                    switch shape {
                    case .rounded: "Rounded corners"
                    case .circle: "Circle"
                    case .square: "Square"
                    }
                }
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Artwork shape"))
        }
    }

    // MARK: Lyrics

    private var lyricsCard: some View {
        GroupBox {
            CollapsibleSection(
                title: "Lyrics",
                systemImage: "quote.bubble",
                isExpanded: $isLyricsExpanded
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    elementToggle(
                        icon: "text.quote", color: .pink, title: "Show lyrics",
                        binding: optionBinding(\.showLyrics),
                        info: "Lyrics use LRCLIB and require an internet connection."
                    )
                    Divider()
                    lyricsLinesRow
                }
                .disabled(!isEditable)
            }
        }
        .groupBoxStyle(ContainerGroupBoxStyle())
    }

    private var lyricsLinesRow: some View {
        SettingRow(
            icon: "list.bullet",
            iconColor: .teal,
            title: "Lyric lines",
            info: "Three lines are available at the large size."
        ) {
            GlassSegmentedPicker(
                selection: optionBinding(\.lyricsLines),
                values: [1, 3],
                shell: .flat,
                title: { $0 == 1 ? "1 line" : "3 lines" }
            )
            .frame(width: 120)
            .disabled(!options.showLyrics)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Lyric lines"))
        }
    }

    // MARK: Playback

    private var playbackCard: some View {
        GroupBox {
            CollapsibleSection(
                title: "Playback",
                systemImage: "playpause",
                isExpanded: $isPlaybackExpanded
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    elementToggle(
                        icon: "playpause.circle", color: .green, title: "Transport controls",
                        binding: optionBinding(\.showControls),
                        info: "Hover over the overlay to show playback controls."
                    )
                    Divider()
                    elementToggle(
                        icon: "hand.draw", color: .blue, title: "Drag progress to seek",
                        binding: optionBinding(\.seekOnProgressDrag)
                    )
                    MusicPlaybackPermissionCaption()
                }
                .disabled(!isEditable)
            }
        }
        .groupBoxStyle(ContainerGroupBoxStyle())
    }

    // MARK: Effects

    /// Lite ships no capture pipeline, so there is nothing here to dial.
    @ViewBuilder
    private var effectsCard: some View {
        #if !LITE_BUILD
        GroupBox {
            CollapsibleSection(
                title: "Effects",
                systemImage: "waveform",
                isExpanded: $isEffectsExpanded
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    audioReactiveRow
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        MusicOptionSlider(
                            icon: "dial.medium",
                            iconColor: .green,
                            title: "Intensity",
                            range: NowPlayingOptions.Limits.audioIntensity,
                            value: options.audioIntensity,
                            format: Self.multiplier
                        ) { value in updateOptions { $0.audioIntensity = value } }
                        Divider()
                        elementToggle(
                            icon: "rays", color: .yellow, title: "Pulse",
                            binding: optionBinding(\.effectPulse)
                        )
                        Divider()
                        elementToggle(
                            icon: "camera.filters", color: .cyan, title: "Color split",
                            binding: optionBinding(\.effectChromatic)
                        )
                        Divider()
                        elementToggle(
                            icon: "waveform.path.ecg", color: .red, title: "Shake",
                            binding: optionBinding(\.effectShake)
                        )
                        Divider()
                        elementToggle(
                            icon: "circle.circle", color: .blue, title: "Ripples",
                            binding: optionBinding(\.effectRipple)
                        )
                        Divider()
                        MusicOptionSlider(
                            icon: "metronome",
                            iconColor: .orange,
                            title: "Beat sensitivity",
                            range: NowPlayingOptions.Limits.beatSensitivity,
                            value: options.beatSensitivity,
                            format: Self.multiplier
                        ) { value in updateOptions { $0.beatSensitivity = value } }
                    }
                    .disabled(!options.audioReactive)
                }
                .disabled(!isEditable)
            }
        }
        .groupBoxStyle(ContainerGroupBoxStyle())
        #endif
    }

    private var audioReactiveRow: some View {
        SettingRow(
            icon: "waveform",
            iconColor: .green,
            title: "Audio reactive",
            info: "Spectrum, glow and particles respond to system audio."
        ) {
            Toggle("", isOn: optionBinding(\.audioReactive))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(Text("Audio reactive"))
        }
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private static func multiplier(_ value: Double) -> String {
        String(format: "%.2f×", value)
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
// MARK: - w4 creative card

extension MusicOverlaySection {
    private var w4Look: W4MusicLook { W4MusicLook(music.options) }

    private func w4Set(_ key: String, _ value: MonitorWidgetOptionValue?) {
        update { current in
            var next = current
            next.options[key] = value
            return next
        }
    }

    private func w4Number(_ key: String) -> (Double) -> Void {
        { value in w4Set(key, .number(value)) }
    }

    private func w4Toggle(_ title: LocalizedStringKey, icon: String, key: String, value: Bool, fallback: Bool = false) -> some View {
        SettingRow(icon: icon, iconColor: .purple, title: title) {
            Toggle("", isOn: Binding(get: { value }, set: { w4Set(key, $0 == fallback ? nil : .bool($0)) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private static func degrees(_ value: Double) -> String { String(format: "%.0f°", value) }

    private func w4Heading(_ text: String) -> some View {
        Text(verbatim: text)
            .font(DesignTokens.Typography.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    /// Layout and look beyond Loomscreen's: where the cover sits and how it is framed, title font, a card behind.
    var w4CreativeCard: some View {
        let look = w4Look
        return GroupBox {
            CollapsibleSection(title: "Bố cục và trang trí", systemImage: "wand.and.stars", isExpanded: $isW4CreativeExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    w4Heading("Ảnh bìa")
                    SettingRow(icon: "rectangle.lefthalf.inset.filled", iconColor: .purple, title: "Vị trí ảnh") {
                        Picker("", selection: Binding(
                            get: { look.place },
                            set: { w4Set(W4MusicLook.Key.place, $0 == .auto ? nil : .string($0.rawValue)) }
                        )) {
                            ForEach(W4MusicLook.Place.allCases) { place in
                                Text(verbatim: place.label).tag(place)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 250)
                    }
                    MusicOptionSlider(icon: "arrow.up.left.and.arrow.down.right", iconColor: .blue, title: "Cỡ ảnh",
                                      range: NowPlayingOptions.Limits.artworkScale, value: options.artworkScale,
                                      format: Self.multiplier) { value in updateOptions { $0.artworkScale = value } }
                    MusicOptionSlider(icon: "square.dashed", iconColor: .purple, title: "Bo góc ảnh", range: 0 ... 1,
                                      value: look.radius ?? 0.05, format: Self.percent, commit: w4Number(W4MusicLook.Key.radius))
                        .disabled(options.artworkShape != .rounded)
                    MusicOptionSlider(icon: "rotate.right", iconColor: .purple, title: "Nghiêng ảnh", range: -30 ... 30,
                                      value: look.tilt, format: Self.degrees, commit: w4Number(W4MusicLook.Key.tilt))
                    MusicOptionSlider(icon: "square.on.square", iconColor: .purple, title: "Viền ảnh", range: 0 ... 1,
                                      value: look.border, format: Self.percent, commit: w4Number(W4MusicLook.Key.border))
                    MusicOptionSlider(icon: "sun.max", iconColor: .orange, title: "Phát sáng quanh ảnh", range: 0 ... 1,
                                      value: look.glow, format: Self.percent, commit: w4Number(W4MusicLook.Key.glow))
                    MusicOptionSlider(icon: "arrow.left.and.right", iconColor: .purple, title: "Cách chữ", range: 0 ... 4,
                                      value: look.gap, format: Self.multiplier, commit: w4Number(W4MusicLook.Key.gap))
                    w4Toggle("Xoay khi đang phát", icon: "record.circle", key: W4MusicLook.Key.spin, value: look.spin)
                    if look.spin {
                        MusicOptionSlider(icon: "speedometer", iconColor: .purple, title: "Tốc độ xoay", range: 0.2 ... 4,
                                          value: look.spinSpeed, format: Self.multiplier, commit: w4Number(W4MusicLook.Key.spinSpeed))
                    }
                    Text(verbatim: "Viền và phát sáng dùng màu sóng nhạc.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()
                    w4Heading("Chữ")
                    SettingRow(icon: "textformat", iconColor: .purple, title: "Phông tên bài") {
                        Button {
                            w4ShowingFonts = true
                        } label: {
                            Text(verbatim: look.titleFamily.isEmpty ? "Theo kiểu chữ" : look.titleFamily)
                                .lineLimit(1)
                                .frame(minWidth: 90, maxWidth: 170)
                        }
                        .popover(isPresented: $w4ShowingFonts, arrowEdge: .bottom) {
                            W4FontPicker(
                                controller: W4LyricController.shared,
                                family: Binding(
                                    get: { look.titleFamily },
                                    set: { w4Set(W4MusicLook.Key.titleFamily, $0.isEmpty ? nil : .string($0)) }
                                ),
                                bold: true
                            )
                        }
                    }
                    MusicOptionSlider(icon: "textformat.size", iconColor: .blue, title: "Cỡ tên bài",
                                      range: NowPlayingOptions.Limits.titleScale, value: options.titleScale,
                                      format: Self.multiplier) { value in updateOptions { $0.titleScale = value } }
                    w4Toggle("Tên ca sĩ viết hoa", icon: "textformat", key: W4MusicLook.Key.eyebrowUpper,
                             value: look.eyebrowUpper, fallback: true)
                    MusicOptionSlider(icon: "character", iconColor: .purple, title: "Giãn chữ tên ca sĩ", range: 0 ... 12,
                                      value: look.tracking, format: { String(format: "%.0f", $0) },
                                      commit: w4Number(W4MusicLook.Key.tracking))

                    Divider()
                    w4Heading("Nền")
                    MusicOptionSlider(icon: "rectangle.fill", iconColor: .gray, title: "Độ đậm nền", range: 0 ... 1,
                                      value: look.card, format: Self.percent, commit: w4Number(W4MusicLook.Key.card))
                    MusicOptionSlider(icon: "square.dashed", iconColor: .gray, title: "Bo góc nền", range: 0 ... 1,
                                      value: look.cardRadius, format: Self.percent, commit: w4Number(W4MusicLook.Key.cardRadius))
                    w4Toggle("Kính mờ", icon: "drop", key: W4MusicLook.Key.blur, value: look.blur)
                    w4Toggle("Nền theo màu sóng nhạc", icon: "paintpalette", key: W4MusicLook.Key.cardTint, value: look.cardTint)
                    w4Toggle("Viền nền", icon: "square", key: W4MusicLook.Key.cardEdge, value: look.cardEdge)
                }
                .disabled(!isEditable)
            }
        }
        .groupBoxStyle(ContainerGroupBoxStyle())
    }
}
#endif
