#if !LITE_BUILD
import AppKit
import LiveWallpaperCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class W4GamesModel {
    enum Section: Hashable {
        case mine
        case search
        case game(W4Game)
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
    }

    var section: Section = .game(W4GameCatalog.all[0])
    var items: [Item] = []
    var isLoading = false
    var message: String?
    var busyID: String?
    var hasMore = false
    var searchText = ""
    var activeSearch = ""
    /// nil puts a wallpaper on every display.
    var targetDisplay: CGDirectDisplayID?

    var upscaleKind: W4UpscaleKind = .illustration
    var upscaleAmount = 0.5
    var isUpscaling = false

    private var nextPage = 1
    private var requestToken = 0
    private var hasAppeared = false

    func firstAppear() {
        guard !hasAppeared else { return }
        hasAppeared = true
        reload()
    }

    func select(_ newSection: Section) {
        guard section != newSection else { return }
        section = newSection
        reload()
    }

    func submitSearch() {
        let text = searchText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        activeSearch = text
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
            loadMore(query: activeSearch, gameName: "Tìm kiếm")
        }
    }

    func loadNextPage() {
        switch section {
        case let .game(game): loadMore(query: game.query, gameName: game.name)
        case .search: loadMore(query: activeSearch, gameName: "Tìm kiếm")
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
            } catch {
                guard token == requestToken else { return }
                message = "Không tải được danh sách: \(error.localizedDescription)"
            }
            if token == requestToken { isLoading = false }
        }
    }

    func apply(_ item: Item, manager: ScreenManager) {
        guard busyID == nil else { return }
        busyID = item.id
        message = nil
        Task {
            defer { busyID = nil }
            do {
                let resolved = try await resolveProject(for: item)
                await activate(resolved, manager: manager)
            } catch {
                message = "Không dùng được hình này: \(error.localizedDescription)"
            }
        }
    }

    private func resolveProject(for item: Item) async throws -> W4Project {
        if let project = item.project { return project }
        guard let full = item.full else { throw W4ProjectError.unreadableMedia }
        let source = full.isFileURL ? full.path : full.absoluteString
        if let existing = W4ProjectStore.existing(source: source) { return existing }
        let title = item.title, game = item.game
        if full.isFileURL {
            return try await W4ProjectStore.build(media: full, title: title, game: game, source: source)
        }
        let downloaded = try await W4WallhavenClient.download(full)
        return try await W4ProjectStore.build(media: downloaded, title: title, game: game, source: source, movingMedia: true)
    }

    private func activate(_ project: W4Project, manager: ScreenManager) async {
        let screens = manager.screens.filter { targetDisplay == nil || $0.id == targetDisplay }
        for screen in screens {
            let outcome = await manager.importWallpaperEngineProject(at: project.folder, for: screen)
            if case let .rejected(reason) = outcome {
                message = "\(project.title): \(reason)"
                return
            }
        }
        message = "Đã đặt \(project.title). Vào trang chi tiết của màn hình để chỉnh sáng, mờ, hạt."
    }

    func importFiles(manager: ScreenManager) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .movie]
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        busyID = "import"
        Task {
            defer { busyID = nil }
            var last: W4Project?
            for url in urls {
                do {
                    last = try await W4ProjectStore.build(
                        media: url, title: url.deletingPathExtension().lastPathComponent, game: "Của tôi", source: url.path
                    )
                } catch {
                    message = "\(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
            if let last { await activate(last, manager: manager) }
            section = .mine
            let kept = message
            reload()
            message = kept
        }
    }

    func remove(_ item: Item, manager: ScreenManager) {
        guard let project = item.project else { return }
        for entry in SettingsManager.shared.loadGlobalSettings().recentWPEImports where entry.origin.workshopID == project.id {
            manager.removeWPEImport(workshopID: project.id, matchingImportedAt: entry.importedAt, recordingDeleteTombstone: false)
        }
        W4ProjectStore.remove(project)
        reload()
    }

    func upscale(_ item: Item, manager: ScreenManager) {
        guard !isUpscaling, let input = item.full, input.isFileURL else {
            message = "Bấm dùng hình này một lần cho tải về rồi hãy nâng 4K."
            return
        }
        isUpscaling = true
        message = "Đang nâng hình, có thể mất từ vài chục giây đến vài phút…"
        let kind = upscaleKind, amount = upscaleAmount, title = item.title, game = item.game
        Task {
            defer { isUpscaling = false }
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try W4Upscaler.run(input: input, kind: kind, aiAmount: amount)
                }.value
                let project = try await W4ProjectStore.build(
                    media: output, title: "\(title) 4K", game: game,
                    source: "\(input.path)#4k-\(kind.rawValue)-\(Int(amount * 100))", movingMedia: true
                )
                await activate(project, manager: manager)
                let kept = message
                if section == .mine { reload() }
                message = kept
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

/// The old app's library by game, in this app's shell. Choosing an image makes it a normal library wallpaper.
struct W4GamesPage: View {
    let router: EditDeskRouter

    @Environment(ScreenManager.self) private var screenManager
    @Environment(\.featureCatalog) private var featureCatalog
    @State private var model = W4GamesModel()
    @State private var upscaleItem: W4GamesModel.Item?
    @State private var stageSize: CGSize = .zero

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 10)]

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                sidebar.frame(width: 190)
                Divider()
                content
            }
            .padding(.top, DesignTokens.EditDesk.Spacing.topBar)
            TopBar(
                page: Binding(get: { router.page }, set: { router.select($0) }),
                workshopAvailable: featureCatalog.isEnabled(.wpeImport),
                windowWidth: stageSize.width,
                status: nil
            )
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { stageSize = $0 }
        .onAppear { model.firstAppear() }
        .sheet(item: $upscaleItem) { item in
            upscaleSheet(item)
        }
    }

    private var sidebar: some View {
        List {
            sidebarRow("Đã tải và của tôi", section: .mine)
            if !model.activeSearch.isEmpty {
                sidebarRow(model.activeSearch, section: .search)
            }
            Section {
                ForEach(W4GameCatalog.all) { game in
                    sidebarRow(game.name, section: .game(game))
                }
            } header: {
                Text(verbatim: "Game nổi tiếng")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func sidebarRow(_ title: String, section: W4GamesModel.Section) -> some View {
        Button {
            model.select(section)
        } label: {
            Text(verbatim: title)
                .lineLimit(1)
                .foregroundStyle(model.section == section ? DesignTokens.Colors.accent : DesignTokens.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(12)
            if let message = model.message {
                Text(verbatim: message)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            ScrollView {
                VStack(spacing: 14) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(model.items) { item in
                            tile(item)
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
                        .padding(.bottom, 12)
                    } else if model.items.isEmpty, model.message == nil {
                        Text(verbatim: "Chưa có gì ở đây")
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .padding(40)
                    }
                }
                .padding(12)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField(text: $model.searchText) {
                Text(verbatim: "Tìm game khác, rồi nhấn Enter")
            }
            .textFieldStyle(.roundedBorder)
            .onSubmit { model.submitSearch() }
            if screenManager.screens.count > 1 {
                Picker(selection: $model.targetDisplay) {
                    Text(verbatim: "Mọi màn hình").tag(CGDirectDisplayID?.none)
                    ForEach(screenManager.screens, id: \.id) { screen in
                        Text(verbatim: screen.nsScreen.localizedName).tag(CGDirectDisplayID?.some(screen.id))
                    }
                } label: {
                    Text(verbatim: "Đặt cho")
                }
                .fixedSize()
            }
            Button {
                model.importFiles(manager: screenManager)
            } label: {
                Text(verbatim: "Thêm ảnh hoặc video")
            }
            .disabled(model.busyID != nil)
        }
    }

    private func tile(_ item: W4GamesModel.Item) -> some View {
        Button {
            model.apply(item, manager: screenManager)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .overlay {
                        AsyncImage(url: item.thumb) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(Color.gray.opacity(0.2))
                        }
                    }
                    .clipped()
                if model.busyID == item.id {
                    Color.black.opacity(0.5)
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if !item.detail.isEmpty {
                    Text(verbatim: item.detail)
                        .font(.caption2)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }
            }
            .frame(height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                model.apply(item, manager: screenManager)
            } label: {
                Text(verbatim: "Đặt làm hình nền")
            }
            if item.full?.isFileURL == true, item.project?.isVideo != true {
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
                Button {
                    model.remove(item, manager: screenManager)
                } label: {
                    Text(verbatim: "Bỏ vào Thùng rác")
                }
            }
        }
    }

    private func upscaleSheet(_ item: W4GamesModel.Item) -> some View {
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
                Button {
                    upscaleItem = nil
                } label: {
                    Text(verbatim: "Đóng")
                }
                Button {
                    model.upscale(item, manager: screenManager)
                    upscaleItem = nil
                } label: {
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
