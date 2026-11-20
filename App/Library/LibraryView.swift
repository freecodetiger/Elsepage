import AchievementCore
import AppInfrastructure
import LibraryCore
import ReadingSessionCore
import ReflectionCore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: LibraryModel
    @Bindable var settings: SettingsRootModel
    let achievements: AchievementModel?
    @State private var nextActionModel: LibraryNextActionModel
    @State private var importing = false
    @State private var showsSettings = false
    /// The shelf is collapsed by default: one book, one pile. Expanding is a
    /// local, reversible state, never a navigation push.
    @State private var isExpanded = false
    /// True only once the expand/collapse animation has settled. The
    /// cover-to-reader zoom source renders its own copy of a cover, and that
    /// copy animates on its own when the source is attached or removed — which
    /// smears across the shelf transition. It stays off until the shelf is still.
    @State private var shelfSettled = true
    @State private var showsSearch = false
    @State private var selectedBook: Book?
    @State private var reflection: SessionReflectionModel?
    @State private var presentedReflectionSessionID: ReadingSessionID?
    @State private var didSaveReflectionInSheet = false
    @Binding private var importRequest: Bool
    /// Tells `AppShell` that the pushed reader owns the screen. The shell's
    /// custom glass bar is a `safeAreaInset` on the TabView, so it cannot see
    /// this navigation destination by itself.
    @Binding private var readerVisible: Bool
    @Namespace private var bookTransitionNamespace

    init(
        model: LibraryModel,
        settings: SettingsRootModel,
        achievements: AchievementModel? = nil,
        importRequest: Binding<Bool> = .constant(false),
        readerVisible: Binding<Bool> = .constant(false)
    ) {
        self.model = model
        self.settings = settings
        self.achievements = achievements
        _importRequest = importRequest
        _readerVisible = readerVisible
        _nextActionModel = State(initialValue: LibraryNextActionModel(library: model))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                shelfHeader
                ZStack {
                    Color.elsepageBackground.ignoresSafeArea()
                    if model.books.isEmpty { emptyLibrary } else { bookList(model) }
                }
            }
            .background(Color.elsepageBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType.epub], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task {
                        _ = await model.importBook(url)
                        await nextActionModel.reload()
                    }
                }
            }
            .sheet(isPresented: $showsSettings) {
                SettingsView(model: settings)
            }
            .sheet(item: $reflection) { reflection in
                SessionReflectionSheet(model: reflection) { _ in
                    didSaveReflectionInSheet = true
                    Task {
                        await model.reload()
                        await nextActionModel.reload()
                    }
                }
            }
            .onChange(of: reflection?.id) { _, currentID in
                guard currentID == nil, let sessionID = presentedReflectionSessionID else { return }
                presentedReflectionSessionID = nil
                defer { didSaveReflectionInSheet = false }
                if !didSaveReflectionInSheet {
                    nextActionModel.dismissReflectionPrompt(for: sessionID)
                    Task { await nextActionModel.reload() }
                }
            }
            .navigationDestination(item: $selectedBook) { book in
                ReaderScreen(
                    model: model.readerModel(for: book),
                    openingCover: model.cover(for: book),
                    onOpenSettings: { showsSettings = true }
                ) {
                    Task {
                        await model.reload()
                        await nextActionModel.reload()
                    }
                }
                .modifier(
                    BookZoomNavigationTransition(
                        sourceID: book.id,
                        namespace: bookTransitionNamespace
                    )
                )
            }
            .onChange(of: selectedBook) { _, book in
                readerVisible = book != nil
            }
            .alert("导入失败", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("好") {} } message: { Text(model.errorMessage ?? "") }
            .alert("这本书已经在书库中", isPresented: Binding(get: { model.duplicateTitle != nil }, set: { if !$0 { model.duplicateTitle = nil } })) { Button("好") {} } message: { Text(model.duplicateTitle ?? "") }
            .alert("从书架移除这本书？", isPresented: Binding(
                get: { model.pendingDeletion != nil },
                set: { if !$0 { model.pendingDeletion = nil } }
            )) {
                Button("取消", role: .cancel) { model.pendingDeletion = nil }
                Button("移除", role: .destructive) {
                    guard let book = model.pendingDeletion else { return }
                    model.pendingDeletion = nil
                    Task { await model.delete(book) }
                }
            } message: {
                Text("会删除本机 EPUB、阅读位置、全部标注，以及这本书的阅读会话、反思与 AI 对话，无法恢复。")
            }
            .safeAreaInset(edge: .bottom) {
                if model.isImporting { importStatus }
            }
            .task {
                await model.reload()
                await nextActionModel.reload()
            }
            .onChange(of: importRequest) { _, requested in
                guard requested else { return }
                importing = true
                importRequest = false
            }
            .onAppear {
                guard importRequest else { return }
                importing = true
                importRequest = false
            }
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: ElsepageTheme.Spacing.large) {
            Image(systemName: "books.vertical")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.elsepageInteractive)
                .accessibilityHidden(true)
            VStack(spacing: ElsepageTheme.Spacing.small) {
                Text("带一本书进来")
                    .font(ElsepageTheme.Typography.emptyStateTitle)
                Text("从“文件”导入无 DRM 的 EPUB。\n没有网络或 AI，也可以安静地读完它。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("导入 EPUB") { importing = true }
                .buttonStyle(.borderedProminent)
                .tint(.elsepageInteractive)
                // A11Y-03: AA label on the accent fill in both color schemes.
                .foregroundStyle(Color.elsepageOnInteractive)
                .disabled(model.isImporting)
        }
        .padding(ElsepageTheme.Spacing.xLarge)
    }

    private var importStatus: some View {
        HStack(spacing: ElsepageTheme.Spacing.small) {
            ProgressView()
            Text("正在导入 EPUB…").font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, ElsepageTheme.Spacing.medium)
        .padding(.vertical, ElsepageTheme.Spacing.small)
        .background(Color.elsepageSurface, in: Capsule())
        .overlay(Capsule().stroke(Color.elsepageBorder))
        .padding(.bottom, ElsepageTheme.Spacing.small)
        .accessibilityElement(children: .combine)
    }

    private var isSearching: Bool {
        !model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func bookList(_ model: LibraryModel) -> some View {
        // The grid needs its available width to size covers explicitly; the
        // collapsed shelf needs the height so the book sits on the desk rather
        // than at the top of a short page.
        GeometryReader { proxy in
            ScrollView {
                if isSearching {
                    searchResults(model, width: proxy.size.width)
                } else {
                    // Both states stay in the tree: swapping them through an
                    // `if` inserts and removes views, which `withAnimation`
                    // cannot interpolate. Opacity, offset and scale can.
                    ZStack(alignment: .top) {
                        // The two states travel in opposite directions, so a
                        // fading cover never sits on top of its other-state
                        // copy. Overlapping them read as a smeared double image.
                        // A short travel rather than the full screen: far
                        // enough that the fading hero and the fading grid do
                        // not stack on each other, short enough that neither
                        // frame is empty.
                        collapsedShelf(model, height: proxy.size.height)
                            .opacity(isExpanded ? 0 : 1)
                            .offset(y: isExpanded ? -160 : 0)
                            .allowsHitTesting(!isExpanded)
                            .accessibilityHidden(isExpanded)
                        expandedShelf(model, width: proxy.size.width)
                            .opacity(isExpanded ? 1 : 0)
                            .offset(y: isExpanded ? 0 : 160)
                            .allowsHitTesting(isExpanded)
                            .accessibilityHidden(!isExpanded)
                    }
                    .animation(expandAnimation, value: isExpanded)
                }
            }
            // `always` so a pull at the top still rubber-bands when the page
            // fits exactly — that pull is what folds the shelf back up.
            .scrollBounceBehavior(.always)
            .onScrollGeometryChange(for: ShelfEdge.self) { geometry in
                ShelfEdge(
                    // Negative while the finger pulls past the top.
                    top: geometry.contentOffset.y + geometry.contentInsets.top,
                    bottom: geometry.contentOffset.y + geometry.containerSize.height
                        - geometry.contentInsets.bottom - geometry.contentSize.height
                )
            } action: { _, edge in
                followShelfEdge(edge)
            }
        }
    }

    // MARK: - Collapsed shelf

    /// One book, one pile. Nothing else competes for the screen.
    @ViewBuilder
    private func collapsedShelf(_ model: LibraryModel, height: CGFloat) -> some View {
        let current = model.currentBook
        let rest = current.map { book in
            model.visibleBooks.filter { $0.id != book.id }
        } ?? model.visibleBooks

        VStack(spacing: 0) {
            Spacer(minLength: 16)
            if let current {
                heroCard(current)
                    .padding(.horizontal, ElsepageTheme.Spacing.pageInset)
            }
            Spacer(minLength: 24)
            if !rest.isEmpty {
                // The shell's glass tab bar is a sibling overlay the shelf
                // cannot see, so the pile is lifted past it by hand.
                shelfPile(rest)
                    .padding(.horizontal, ElsepageTheme.Spacing.pageInset)
                    .padding(.bottom, 92)
            }
        }
        // A sliver past the page, so an upward swipe has somewhere to travel
        // and can pull past the bottom — that pull is what opens the shelf.
        .frame(maxWidth: .infinity, minHeight: max(0, height) + 1, alignment: .top)
    }

    /// The cover carries the identity; the title and author are the only words.
    /// Progress is a line and a numeral, not a sentence.
    private func heroCard(_ book: Book) -> some View {
        let progress = model.progress(for: book) ?? 0
        let showsReflection = nextActionModel.pendingReflection?.book.id == book.id
        let coverWidth: CGFloat = dynamicTypeSize.isAccessibilitySize ? 132 : 180

        return VStack(spacing: 0) {
            Button {
                Haptics.bookPulled()
                selectedBook = book
            } label: {
                VStack(spacing: 0) {
                    ElsepageBookCover(
                        image: model.cover(for: book),
                        title: book.title,
                        author: book.author,
                        seed: Int(book.id.rawValue.uuid.0),
                        showsShadow: false,
                        width: coverWidth
                    )
                    // Shared with the compact row, so the cover scales between
                    // the two shelf states instead of being swapped.
                    // The zoom source renders its own copy of the cover. While
                    // the two shelf states crossfade that copy floats free of
                    // the card, so it is only attached once the shelf is still.
                    .modifier(ZoomSource(id: book.id, namespace: bookTransitionNamespace, active: shelfSettled && !isExpanded))

                    Text(book.title)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .foregroundStyle(Color.elsepageTextPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.top, 26)

                    Text(authorName(book))
                        .font(.subheadline)
                        .foregroundStyle(Color.elsepageTextSecondary)
                        .lineLimit(1)
                        .padding(.top, 4)

                    progressLine(progress, width: coverWidth)
                        .padding(.top, 22)

                    Text(progressText(progress))
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.elsepageTextTertiary)
                        .padding(.top, 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The current book is excluded from the grid, so it keeps its own
            // delete menu: otherwise the last book would have no way out.
            .contextMenu {
                Button(role: .destructive) { model.pendingDeletion = book } label: {
                    Label("从书架移除", systemImage: "trash")
                }
            }
            .accessibilityLabel(accessibilityLabel(for: book))
            .accessibilityHint("打开并继续阅读")
            .accessibilityAction(named: "移除这本书") { model.pendingDeletion = book }
            .task(id: book.id) { await model.loadCover(for: book) }

            if showsReflection {
                reflectionButton
                    .padding(.top, 20)
            }
        }
    }

    /// The rest of the shelf as a physical pile: three covers, a count and a
    /// fold glyph. No caption — tapping anywhere unfolds the grid in place.
    private func shelfPile(_ books: [Book]) -> some View {
        let preview = Array(books.prefix(3))
        return Button {
            toggleShelf(to: true)
        } label: {
            HStack(spacing: ElsepageTheme.Spacing.large) {
                ZStack(alignment: .bottomLeading) {
                    ForEach(Array(preview.enumerated()), id: \.element.id) { index, book in
                        ElsepageBookCover(
                            image: model.cover(for: book),
                            title: book.title,
                            author: book.author,
                            seed: Int(book.id.rawValue.uuid.0),
                            showsShadow: false,
                            width: 46
                        )
                        .rotationEffect(.degrees(Double(index) * 4 - 4), anchor: .bottom)
                        .offset(x: CGFloat(index) * 9, y: CGFloat(index) * -3)
                        .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
                        .task(id: book.id) { await model.loadCover(for: book) }
                    }
                }
                .frame(width: 92, height: 74, alignment: .bottomLeading)

                Spacer(minLength: 0)

                Text("\(books.count)")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.elsepageTextSecondary)

                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.elsepageTextTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("展开书架")
        .accessibilityValue("还有 \(books.count) 本未展开")
        .accessibilityHint("显示全部书籍")
    }

    // MARK: - Expanded shelf

    @ViewBuilder
    private func expandedShelf(_ model: LibraryModel, width: CGFloat) -> some View {
        let current = model.currentBook
        let gridBooks = current.map { book in
            model.visibleBooks.filter { $0.id != book.id }
        } ?? model.visibleBooks

        VStack(alignment: .leading, spacing: 0) {
            if let current {
                expandedCurrentRow(current)
                    .padding(.horizontal, ElsepageTheme.Spacing.pageInset)
            }

            // A hairline runs from the gutter to the two icon controls; no
            // section title, no count as a sentence.
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.elsepageBorder.opacity(0.7))
                    .frame(height: 0.5)
                sortMenu
                collapseButton
            }
            .padding(.leading, ElsepageTheme.Spacing.pageInset)
            .padding(.trailing, 8)
            .padding(.top, 26)
            .padding(.bottom, 2)

            bookGrid(gridBooks, width: width)
        }
        .padding(.top, 4)
    }

    /// The hero, folded into one quiet line so it anchors the expanded shelf
    /// without competing with the grid.
    private func expandedCurrentRow(_ book: Book) -> some View {
        let progress = model.progress(for: book) ?? 0
        let showsReflection = nextActionModel.pendingReflection?.book.id == book.id

        return HStack(spacing: 14) {
            Button {
                Haptics.bookPulled()
                selectedBook = book
            } label: {
                HStack(spacing: 14) {
                    ElsepageBookCover(
                        image: model.cover(for: book),
                        title: book.title,
                        author: book.author,
                        seed: Int(book.id.rawValue.uuid.0),
                        showsShadow: false,
                        width: 52
                    )
                    .modifier(ZoomSource(id: book.id, namespace: bookTransitionNamespace, active: shelfSettled && isExpanded))
                    .shadow(color: ElsepageBookCoverMetrics.shadowColor, radius: 4, y: 2)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(book.title)
                            .font(.system(.subheadline, design: .serif, weight: .semibold))
                            .foregroundStyle(Color.elsepageTextPrimary)
                            .lineLimit(1)
                        progressLine(progress, width: 104)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel(for: book))
            .accessibilityHint("打开并继续阅读")
            .task(id: book.id) { await model.loadCover(for: book) }

            Spacer(minLength: 8)

            if showsReflection {
                reflectionButton
            } else {
                Text(progressText(progress))
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.elsepageTextTertiary)
            }
        }
    }

    @ViewBuilder
    private func searchResults(_ model: LibraryModel, width: CGFloat) -> some View {
        if model.visibleBooks.isEmpty {
            ContentUnavailableView.search(text: model.searchQuery)
                .frame(maxWidth: .infinity, minHeight: 260)
                .padding(.horizontal, ElsepageTheme.Spacing.pageInset)
        } else {
            bookGrid(model.visibleBooks, width: width)
                .padding(.top, 4)
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("排序", selection: $model.sortOrder) {
                ForEach(LibrarySortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.elsepageTextSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("排序")
        .accessibilityValue(model.sortOrder.title)
    }

    private var collapseButton: some View {
        Button {
            toggleShelf(to: false)
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.elsepageTextSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("收拢书架")
    }

    // MARK: - Header & shared pieces

    /// A wordless top bar: search, then settings. The tab bar's icon already
    /// names the screen, so the shelf leads with the book itself.
    private var shelfHeader: some View {
        HStack(spacing: ElsepageTheme.Spacing.small) {
            if showsSearch {
                ElsepageSearchField(text: $model.searchQuery, prompt: "搜索书名或作者", autoFocus: true)
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        showsSearch = false
                        model.searchQuery = ""
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.elsepageTextSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("结束搜索")
            } else {
                headerIcon("magnifyingglass", label: "搜索") {
                    withAnimation(.snappy(duration: 0.2)) { showsSearch = true }
                }
                Spacer(minLength: 0)
                headerIcon("gearshape", label: "设置") { showsSettings = true }
            }
        }
        .padding(.horizontal, ElsepageTheme.Spacing.pageInset)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .frame(minHeight: 52)
    }

    private func headerIcon(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.elsepageTextSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func progressLine(_ progress: Double, width: CGFloat) -> some View {
        Capsule()
            .fill(Color.elsepageBorder)
            .frame(width: width, height: 2)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.elsepageTextPrimary)
                    .frame(width: width * max(0, min(1, progress)), height: 2)
            }
            .accessibilityHidden(true)
    }

    private func progressText(_ progress: Double) -> String {
        guard progress > 0 else { return "未开始" }
        return "\(Int((progress * 100).rounded()))%"
    }

    private var reflectionButton: some View {
        Button {
            presentReflection()
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.elsepageTextPrimary)
                .frame(width: 44, height: 44)
                .background(Color.elsepageSurface, in: Circle())
                .overlay(Circle().stroke(Color.elsepageBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("补写上一次阅读的想法")
    }

    private var expandAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.86)
    }

    /// A pull past either end of the scroll opens or closes the shelf.
    ///
    /// The collapsed page has nothing below it, so a pull past its bottom opens
    /// the grid. Pulling past the top of the expanded shelf folds it back up.
    /// The threshold sits past the rubber-band a normal flick reaches, and
    /// `shelfSettled` keeps one gesture from firing twice.
    private func followShelfEdge(_ edge: ShelfEdge) {
        guard shelfSettled, !isSearching else { return }
        if !isExpanded, edge.bottom > 90 {
            toggleShelf(to: true)
        } else if isExpanded, edge.top < -90 {
            toggleShelf(to: false)
        }
    }

    /// Drops the zoom sources before the shelf moves, then restores the one
    /// that belongs to the resting state. Without the lead time their own
    /// removal animation plays on top of the crossfade.
    private func toggleShelf(to expanded: Bool) {
        shelfSettled = false
        withAnimation(expandAnimation) { isExpanded = expanded }
        guard expandAnimation != nil else {
            shelfSettled = true
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(520))
            guard isExpanded == expanded else { return }
            shelfSettled = true
        }
    }

    private func bookGrid(_ books: [Book], width: CGFloat) -> some View {
        LibraryGridView(
            books: books,
            cover: { model.cover(for: $0) },
            progress: { model.progress(for: $0) },
            transitionNamespace: bookTransitionNamespace,
            zoomActive: shelfSettled && isExpanded,
            openBook: { selectedBook = $0 },
            loadCover: { await model.loadCover(for: $0) },
            requestDelete: { model.pendingDeletion = $0 },
            onSwap: { model.swapBooks($0, with: $1) },
            onDragChange: { model.isDraggingBook = $0 },
            trashZone: model.trashZoneFrame,
            moveBook: { model.moveBook($0.id, by: $1) },
            accessibilityLabel: { accessibilityLabel(for: $0) },
            containerWidth: width
        )
    }

    private func authorName(_ book: Book) -> String {
        guard let author = book.author?.trimmingCharacters(in: .whitespacesAndNewlines),
              !author.isEmpty else { return "未知作者" }
        return author
    }

    private func accessibilityLabel(for book: Book) -> String {
        LibraryBookAccessibility.label(
            title: book.title,
            author: book.author,
            statsLine: model.statsLine(for: book),
            progress: model.progress(for: book)
        )
    }

    /// Presents the reflection the reader offered at the end of a session and
    /// the user has not written yet. Closing it without saving skips this
    /// session for the current run only; the card returns on the next launch.
    private func presentReflection() {
        guard let pending = nextActionModel.pendingReflection,
              let locator = pending.session.endLocator else { return }
        didSaveReflectionInSheet = false
        presentedReflectionSessionID = pending.session.id
        reflection = SessionReflectionModel(
            book: pending.book,
            summary: SessionEndingSummary(session: pending.session),
            locator: locator,
            reflectionRepository: model.reflectionRepository,
            readerAgent: model.readerAgent,
            makePolishService: model.makePolishService,
            achievements: achievements,
            recordAgentDiscussion: { sessionID in
                try? await model.sessionService.recordAgentDiscussion(id: sessionID)
            }
        )
    }
}

/// Applies the native iOS 18 zoom transition to the Reader destination.
/// Reduce Motion keeps the normal navigation transition instead.
/// The cover-to-reader zoom source, attached only while the shelf is still.
/// During the expand/collapse crossfade its rendered copy would otherwise
/// drift between the two fading states.
private struct ZoomSource<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.matchedTransitionSource(id: id, in: namespace) { source in
                source
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: ElsepageBookCoverMetrics.cornerRadius,
                            style: .continuous
                        )
                    )
                    .shadow(
                        color: ElsepageBookCoverMetrics.shadowColor,
                        radius: ElsepageBookCoverMetrics.shadowRadius,
                        y: ElsepageBookCoverMetrics.shadowY
                    )
            }
        } else {
            content
        }
    }
}

/// How far the shelf is pulled past its ends, in points. `bottom` is positive
/// while the finger drags past the last row.
private struct ShelfEdge: Equatable {
    var top: CGFloat
    var bottom: CGFloat
}

private struct BookZoomNavigationTransition<ID: Hashable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let sourceID: ID
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        }
    }
}
