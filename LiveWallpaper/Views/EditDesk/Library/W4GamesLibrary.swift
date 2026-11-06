#if !LITE_BUILD
import AppKit
import LiveWallpaperCore
import Observation
import SwiftUI

/// The old app's library by game, shown as the Library's Game tab. Opening a picture makes it an ordinary
/// library wallpaper, so it gets the same detail panel, display buttons and settings as everything else.
@MainActor
@Observable
final class W4GamesModel {
    static let shared = W4GamesModel()

    enum Section: Hashable {
        case mine
        case search
        case game(W4Game)

        var title: String {
            switch self {
            case .mine: "Đã tải và của tôi"
            case .search: "Kết quả tìm"
            case let .game(game): game.name
            }
        }
    }

    struct Item: Identifiable, Hashable {
        let id: String
        let title: String
        let game: String
        let detail: String
        let thumb: URL?
        let full: URL?
        let page: URL?
        let authorSource: URL?
        let project: W4Project?

        var isVideo: Bool {
            project?.isVideo ?? ["mp4", "mov", "m4v"].contains(full?.pathExtension.lowercased() ?? "")
        }
    }

    private(set) var section: Section = .game(W4GameCatalog.all[0])
    private(set) var items: [Item] = []
    private(set) var isLoading = false
    var message: String?
    private(set) var busyID: String?
    private(set) var hasMore = false
    private(set) var activeSearch = ""
    private var sectionBeforeSearch: Section?

    var upscaleKind: W4UpscaleKind = .illustration
    var upscaleAmount = 0.5
    private(set) var isUpscaling = false

    private var nextPage = 1
    private var requestToken = 0
    private var hasAppeared = false

    func firstAppear() {
        guard !hasAppeared else { return }
        hasAppeared = true
        reload()
    }

    func select(_ newSection: Section) {
        sectionBeforeSearch = nil
        guard section != newSection else { return }
        section = newSection
        reload()
    }

    /// The Library's search field searches Wallhaven while this tab is open; clearing it goes back.
    func search(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            guard section == .search else { return }
            section = sectionBeforeSearch ?? .game(W4GameCatalog.all[0])
            sectionBeforeSearch = nil
            reload()
            return
        }
        guard trimmed != activeSearch || section != .search else { return }
        if section != .search { sectionBeforeSearch = section }
        activeSearch = trimmed
        section = .search
        reload()
    }

    func reload() {
        items = []
        message = nil
        hasMore = false
        nextPage = 1
        requestToken += 1
        isLoading = false
        switch section {
        case .mine:
            loadMine()
        case let .game(game) where game.usesLocalArt:
            loadLocalArt(game)
        case let .game(game):
            loadMore(query: game.query, gameName: game.name)
        case .search:
            loadMore(query: activeSearch, gameName: activeSearch)
        }
    }

    func loadNextPage() {
        switch section {
        case let .game(game): loadMore(query: game.query, gameName: game.name)
        case .search: loadMore(query: activeSearch, gameName: activeSearch)
        case .mine: break
        }
    }

    private func loadMine() {
        let projects = W4ProjectStore.list()
        var result = projects.map { project in
            Item(
                id: project.id, title: project.title, game: project.game, detail: project.game,
                thumb: project.previewURL, full: project.mediaURL, page: nil, authorSource: nil, project: project
            )
        }
        let built = Set(projects.map(\.source))
        for file in W4Legacy.wallpaperFiles() where !built.contains(file.path) {
            result.append(Item(
                id: file.path, title: file.deletingPathExtension().lastPathComponent,
                game: file.deletingLastPathComponent().lastPathComponent, detail: "Từ bản cũ",
                thumb: file, full: file, page: nil, authorSource: nil, project: nil
            ))
        }
        items = result
        if items.isEmpty {
            message = "Chưa có gì. Mở một hình ở các game, hoặc bấm + để thêm ảnh, video."
        }
    }

    private func loadLocalArt(_ game: W4Game) {
        items = W4Legacy.artFiles().map { art in
            Item(
                id: art.file.path, title: art.file.deletingPathExtension().lastPathComponent, game: game.name,
                detail: art.artist, thumb: art.thumb, full: art.file, page: art.page, authorSource: nil, project: nil
            )
        }
        if items.isEmpty {
            message = "Không thấy bộ ảnh Delta Force trong thư mục LiveWall của máy, nên chưa hiện được."
        }
    }

    private func loadMore(query: String, gameName: String) {
        guard !query.isEmpty else { return }
        requestToken += 1
        let token = requestToken
        let page = nextPage
        isLoading = true
        message = nil
        Task {
            do {
                let result = try await W4WallhavenClient.search(query: query, page: page)
                guard token == requestToken else { return }
                let known = Set(items.map(\.id))
                items += result.data.filter { !known.contains($0.path) }.map { item in
                    Item(
                        id: item.path, title: "\(gameName) \(item.id)", game: gameName, detail: item.resolution,
                        thumb: URL(string: item.thumbs.large), full: URL(string: item.path), page: URL(string: item.url),
                        authorSource: item.source.flatMap(URL.init(string:)), project: nil
                    )
                }
                hasMore = result.meta.current_page < result.meta.last_page
                nextPage = page + 1
                if items.isEmpty { message = "Không có hình nào." }
            } catch {
                guard token == requestToken else { return }
                message = "Không tải được danh sách: \(error.localizedDescription)"
            }
            if token == requestToken { isLoading = false }
        }
    }

    /// Builds the item's project, downloading the picture first when it is remote.
    func prepare(_ item: Item) async -> W4Project? {
        guard busyID == nil else { return nil }
        busyID = item.id
        defer { busyID = nil }
        do {
            if let project = item.project { return project }
            guard let full = item.full else { throw W4ProjectError.unreadableMedia }
            let source = full.isFileURL ? full.path : full.absoluteString
            if let existing = W4ProjectStore.existing(source: source) { return existing }
            if full.isFileURL {
                return try await W4ProjectStore.build(media: full, title: item.title, game: item.game, source: source)
            }
            let downloaded = try await W4WallhavenClient.download(full)
            return try await W4ProjectStore.build(media: downloaded, title: item.title, game: item.game, source: source, movingMedia: true)
        } catch {
            message = "Không dùng được hình này: \(error.localizedDescription)"
            return nil
        }
    }

    func importFiles() async -> [W4Project] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .movie]
        guard panel.runModal() == .OK else { return [] }
        busyID = "import"
        defer { busyID = nil }
        var built: [W4Project] = []
        for url in panel.urls {
            do {
                built.append(try await W4ProjectStore.build(
                    media: url, title: url.deletingPathExtension().lastPathComponent, game: "Của tôi", source: url.path
                ))
            } catch {
                message = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        if section == .mine {
            let kept = message
            reload()
            message = kept
        }
        return built
    }

    func remove(_ item: Item, manager: ScreenManager) {
        guard let project = item.project else { return }
        for entry in SettingsManager.shared.loadGlobalSettings().recentWPEImports where entry.origin.workshopID == project.id {
            manager.removeWPEImport(workshopID: project.id, matchingImportedAt: entry.importedAt, recordingDeleteTombstone: false)
        }
        W4ProjectStore.remove(project)
        reload()
    }

    /// The 4K copy is its own project; the original stays.
    func upscale(_ item: Item) async -> W4Project? {
        guard !isUpscaling else { return nil }
        guard let source = await prepare(item) else { return nil }
        isUpscaling = true
        defer { isUpscaling = false }
        message = "Đang nâng hình, có thể mất từ vài chục giây đến vài phút…"
        let input = source.mediaURL, kind = upscaleKind, amount = upscaleAmount
        do {
            let output = try await Task.detached(priority: .userInitiated) {
                try W4Upscaler.run(input: input, kind: kind, aiAmount: amount)
            }.value
            let project = try await W4ProjectStore.build(
                media: output, title: "\(item.title) 4K", game: item.game,
                source: "\(input.path)#4k-\(kind.rawValue)-\(Int(amount * 100))", movingMedia: true
            )
            message = nil
            return project
        } catch {
            message = error.localizedDescription
            return nil
        }
    }
}

/// Imports a built project into the Library and waits for its row, so its detail panel can open.
@MainActor
enum W4LibraryBridge {
    static func itemID(for project: W4Project) -> String {
        "workshop:\(project.id)"
    }

    static func ensureInLibrary(_ project: W4Project, library: SavedLibraryModel) async -> String? {
        let id = itemID(for: project)
        if library.items.contains(where: { $0.id == id }) { return id }
        WorkshopFolderImportCoordinator.shared.importProjects(from: [project.folder])
        for _ in 0 ..< 80 {
            try? await Task.sleep(for: .milliseconds(250))
            if library.items.contains(where: { $0.id == id }) { return id }
        }
        Logger.warning("Game picture \(project.id) did not reach the library", category: .workshop)
        return nil
    }
}

/// Which game the tab lists; sits where the sort menu is on the other tabs.
struct W4GamesPicker: View {
    @State private var model = W4GamesModel.shared

    var body: some View {
        LibrarySortControl(name: Text(verbatim: "Game"), value: Text(verbatim: model.section.title)) {
            Button {
                model.select(.mine)
            } label: {
                Text(verbatim: W4GamesModel.Section.mine.title)
            }
            Divider()
            ForEach(W4GameCatalog.all) { game in
                Toggle(isOn: Binding(get: { model.section == .game(game) }, set: { if $0 { model.select(.game(game)) } })) {
                    Text(verbatim: game.name)
                }
            }
        } label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: "gamecontroller")
                Text(verbatim: model.section.title)
            }
        }
    }
}

/// The Game tab's grid, drawn like the Library's own tiles.
struct W4GamesGrid: View {
    let library: SavedLibraryModel
    let initialWidth: CGFloat
    let openItem: (String) -> Void

    @Environment(ScreenManager.self) private var screenManager
    @Environment(\.libraryTileSize) private var tileSize
    @State private var model = W4GamesModel.shared
    @State private var upscaleItem: W4GamesModel.Item?

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            if let message = model.message {
                Text(verbatim: message)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.EditDesk.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            LibraryGalleryGrid(size: tileSize, aspect: .wide, initialWidth: initialWidth) {
                ForEach(model.items) { item in
                    Button {
                        open(item)
                    } label: {
                        W4GameTile(item: item, busy: model.busyID == item.id)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menu(for: item) }
                    .accessibilityLabel(Text(verbatim: item.title))
                }
            }
            if model.isLoading {
                ProgressView().padding()
            } else if model.hasMore {
                Button {
                    model.loadNextPage()
                } label: {
                    Text(verbatim: "Tải thêm")
                }
                .buttonStyle(.bordered)
                .padding(.bottom, DesignTokens.Spacing.md)
            }
        }
        .libraryGridPadding()
        .onAppear { model.firstAppear() }
        .task(id: library.query) {
            // Typing settles before Wallhaven is asked.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            model.search(library.query)
        }
        .sheet(item: $upscaleItem) { item in
            W4UpscaleSheet(item: item, model: model) {
                upscaleItem = nil
                Task {
                    if let project = await model.upscale(item) { await show(project) }
                }
            } close: {
                upscaleItem = nil
            }
        }
    }

    private func open(_ item: W4GamesModel.Item) {
        Task {
            if let project = await model.prepare(item) { await show(project) }
        }
    }

    private func show(_ project: W4Project) async {
        if let id = await W4LibraryBridge.ensureInLibrary(project, library: library) {
            openItem(id)
        } else {
            model.message = "Đã tạo \(project.title) nhưng chưa thấy nó trong Library. Thử mở tab Tất cả."
        }
    }

    @ViewBuilder
    private func menu(for item: W4GamesModel.Item) -> some View {
        Button {
            open(item)
        } label: {
            Text(verbatim: "Mở")
        }
        if !item.isVideo {
            Button {
                upscaleItem = item
            } label: {
                Text(verbatim: "Nâng lên 4K…")
            }
        }
        if let page = item.page {
            Button {
                NSWorkspace.shared.open(page)
            } label: {
                Text(verbatim: "Mở trang gốc")
            }
        }
        if let source = item.authorSource {
            Button {
                NSWorkspace.shared.open(source)
            } label: {
                Text(verbatim: "Mở nguồn của tác giả")
            }
        }
        if item.project != nil {
            Divider()
            Button(role: .destructive) {
                model.remove(item, manager: screenManager)
            } label: {
                Text(verbatim: "Bỏ vào Thùng rác")
            }
        }
    }
}

private struct W4GameTile: View {
    let item: W4GamesModel.Item
    let busy: Bool

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            DesignTokens.Colors.surfaceRaised
                .overlay {
                    if item.isVideo, item.project == nil {
                        Image(systemName: "play.rectangle")
                            .foregroundStyle(DesignTokens.EditDesk.Colors.textSecondary)
                    } else {
                        AsyncImage(url: item.thumb) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "photo")
                                .foregroundStyle(DesignTokens.EditDesk.Colors.textSecondary)
                        }
                    }
                }
                .clipped()
            LinearGradient(
                colors: [.clear, DesignTokens.EditDesk.Colors.gradientCardBottom],
                startPoint: .center, endPoint: .bottom
            )
            RoundedRectangle(cornerRadius: DesignTokens.Corner.lg, style: .continuous)
                .strokeBorder(DesignTokens.EditDesk.Colors.cardRimRing, lineWidth: 1)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.title)
                    .font(DesignTokens.EditDesk.Typography.cardTitle)
                    .foregroundStyle(DesignTokens.Colors.overlayForeground)
                    .lineLimit(1)
                if !item.detail.isEmpty {
                    Text(verbatim: item.detail)
                        .font(DesignTokens.EditDesk.Typography.metaMono)
                        .foregroundStyle(DesignTokens.Colors.overlayForeground.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(DesignTokens.EditDesk.Spacing.s8)
            if busy {
                Color.black.opacity(0.45)
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .aspectRatio(StageGeometry.cardAspectRatio, contentMode: .fit)
        .galleryTileChrome(isHovering: isHovering, reduceMotion: reduceMotion)
        .onHover { isHovering = $0 }
    }
}

private struct W4UpscaleSheet: View {
    let item: W4GamesModel.Item
    @Bindable var model: W4GamesModel
    let start: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: "Nâng lên 4K: \(item.title)")
                .font(.headline)
            Picker(selection: $model.upscaleKind) {
                ForEach(W4UpscaleKind.allCases) { kind in
                    Text(verbatim: kind.label).tag(kind)
                }
            } label: {
                Text(verbatim: "Loại hình")
            }
            HStack {
                Text(verbatim: "Mức AI")
                Slider(value: $model.upscaleAmount, in: 0 ... 1)
                Text(verbatim: "\(Int(model.upscaleAmount * 100))%")
                    .monospacedDigit()
            }
            Text(verbatim: "Mức AI 0% chỉ phóng to thường. Bản 4K được thêm thành hình riêng, hình gốc vẫn giữ.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(action: close) {
                    Text(verbatim: "Đóng")
                }
                Button(action: start) {
                    Text(verbatim: "Bắt đầu")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isUpscaling)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
#endif
