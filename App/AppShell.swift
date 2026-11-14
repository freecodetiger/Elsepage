import Combine
import LibraryCore
import ReaderCore
import SwiftUI
import UIKit

struct AppShell: View {
    @Bindable var library: LibraryModel
    @Bindable var thoughts: ThoughtsModel
    @Bindable var myMind: MyMindModel
    @Bindable var settings: SettingsRootModel
    @Bindable var achievements: AchievementModel
    @Bindable var appModel: AppModel
    @State private var selection: AppTab = .library
    @State private var readerDestination: ReaderDestination?
    @State private var importRequested = false
    @State private var keyboardVisible = false

    var body: some View {
        TabView(selection: $selection) {
            LibraryView(
                model: library,
                settings: settings,
                achievements: achievements,
                importRequest: $importRequested
            )
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Label(AppTab.library.title, systemImage: AppTab.library.symbol) }
            .tag(AppTab.library)

            ThoughtsView(model: thoughts, settings: settings) { book, locator in
                readerDestination = .init(book: book, locator: locator)
            }
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Label(AppTab.mind.title, systemImage: AppTab.mind.symbol) }
            .tag(AppTab.mind)

            MyMindView(model: myMind, settings: settings, achievements: achievements) { book, locator in
                readerDestination = .init(book: book, locator: locator)
            }
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Label(AppTab.myMind.title, systemImage: AppTab.myMind.symbol) }
            .tag(AppTab.myMind)
        }
        .tint(.elsepageInteractive)
        // The system tab bar is a single capsule. The native split bar below
        // keeps a real UITabBar (system glass + selection lens) and puts the
        // compose button beside it, only on the shelf.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardVisible {
                bottomBar
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .fullScreenCover(item: $readerDestination) { destination in
            ReaderScreen(
                model: library.readerModel(for: destination.book, locator: destination.locator),
                achievements: achievements,
                onReflectionSaved: { selection = .library }
            )
        }
        // A document imported via "用 ReadLoop 打开" lands on 书架 so the result is visible.
        .onChange(of: appModel.openLibraryAfterExternalImport) { _, shouldOpen in
            guard shouldOpen else { return }
            selection = .library
            appModel.openLibraryAfterExternalImport = false
        }
        // First-launch onboarding (PRD §11): 导入第一本书 → 配置 Provider →
        // 指向第一次阅读。Full-screen over the tab shell; completion writes the
        // flag via AppModel, and "打开刚导入的书" hands the book straight to the reader.
        .fullScreenCover(item: $appModel.onboarding) { onboarding in
            OnboardingView(model: onboarding) { book in
                appModel.completeOnboarding()
                if let book {
                    readerDestination = .init(book: book, locator: nil)
                } else {
                    selection = .library
                }
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if #available(iOS 26.0, *) {
            NativeSplitTabBar(
                selection: $selection,
                showsCompose: selection == .library,
                onImport: openImport
            )
            .padding(.leading, 8)
            .padding(.trailing, 12)
        } else {
            ElsepageMaterialTabBar(
                selection: $selection,
                showsCompose: selection == .library,
                onImport: openImport
            )
        }
    }

    private func openImport() {
        selection = .library
        importRequested = true
    }
}

// MARK: - iOS 26 native split bar

/// A real `UITabBar` plus a real glass `UIButton`, mirroring the T3 Code iOS
/// layout. The tab bar keeps its system glass and selection lens; the compose
/// button is measured against the actual tab-button row. The tab bar's trailing
/// area is reserved permanently, so hiding compose never moves the glass.
private struct NativeSplitTabBar: UIViewRepresentable {
    @Binding var selection: AppTab
    let showsCompose: Bool
    let onImport: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ElsepageSplitBarHost {
        let host = ElsepageSplitBarHost()
        host.tabBar.delegate = context.coordinator
        host.onCompose = onImport
        host.setSelection(selection)
        host.setShowsCompose(showsCompose)
        return host
    }

    func updateUIView(_ host: ElsepageSplitBarHost, context: Context) {
        context.coordinator.parent = self
        host.onCompose = onImport
        host.setSelection(selection)
        host.setShowsCompose(showsCompose)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ElsepageSplitBarHost, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? UIScreen.main.bounds.width, height: 64)
    }

    final class Coordinator: NSObject, UITabBarDelegate {
        var parent: NativeSplitTabBar

        init(_ parent: NativeSplitTabBar) {
            self.parent = parent
        }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard AppTab.all.indices.contains(item.tag) else { return }
            parent.selection = AppTab.all[item.tag]
        }
    }
}

/// A plain UIButton whose accessibility activation also sends the touch action,
/// so VoiceOver (and automation) can open the importer the same way a tap does.
private final class ElsepageComposeButton: UIButton {
    override func accessibilityActivate() -> Bool {
        sendActions(for: .touchUpInside)
        return true
    }
}

private final class ElsepageSplitBarHost: UIView {
    let tabBar = ElsepageNativeTabBar()
    private let composeButton = ElsepageComposeButton(type: .system)
    private let tabs = AppTab.all
    private var showsCompose = false
    private var selection: AppTab = .library
    var onCompose: (() -> Void)?
    private lazy var tabBarTrailing = tabBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -64)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        tabBar.itemPositioning = .fill
        if #available(iOS 17.0, *) {
            tabBar.traitOverrides.horizontalSizeClass = .compact
        }
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabBar)
        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabBarTrailing,
            tabBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
        tabBar.onContentLayout = { [weak self] frame in
            self?.layoutCompose(alongside: frame)
        }

        composeButton.accessibilityLabel = "导入 EPUB"
        composeButton.addTarget(self, action: #selector(composeTapped), for: .touchUpInside)
        composeButton.isHidden = true
        addSubview(composeButton)

        configureCompose()
        configureItems()
        setSelection(selection)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelection(_ tab: AppTab) {
        selection = tab
        guard let index = tabs.firstIndex(of: tab),
              let items = tabBar.items,
              items.indices.contains(index) else { return }
        if tabBar.selectedItem !== items[index] {
            tabBar.selectedItem = items[index]
        }
    }

    func setShowsCompose(_ shows: Bool) {
        guard showsCompose != shows else { return }
        showsCompose = shows
        composeButton.isHidden = !shows
        if shows {
            setNeedsLayout()
            tabBar.setNeedsLayout()
            tabBar.layoutIfNeeded()
        } else {
            composeButton.frame = .zero
        }
    }

    private func configureItems() {
        tabBar.items = tabs.enumerated().map { index, tab in
            let item = UITabBarItem(
                title: nil,
                image: UIImage(systemName: tab.symbol),
                tag: index
            )
            item.selectedImage = UIImage(systemName: tab.selectedSymbol)
            item.accessibilityLabel = tab.title
            item.accessibilityIdentifier = "elsepage-tab-\(index)"
            return item
        }
        tabBar.tintColor = UIColor(Color.elsepageTextPrimary)
        tabBar.unselectedItemTintColor = UIColor(Color.elsepageTextSecondary)
    }

    @objc private func composeTapped() {
        onCompose?()
    }

    private func configureCompose() {
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = .glass()
        } else {
            configuration = .gray()
        }
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .label
        configuration.image = UIImage(systemName: "plus")
        composeButton.configuration = configuration
    }

    private func layoutCompose(alongside frame: CGRect) {
        guard showsCompose, frame.height > 0 else { return }
        let row = convert(frame, from: tabBar)
        let size = row.height + 8
        composeButton.frame = CGRect(
            x: row.maxX + 16,
            y: row.midY - size / 2,
            width: size,
            height: size
        )
    }
}

/// The tab bar's laid-out item row is private to UIKit. Read the real tab
/// buttons (ignoring the enlarged glass-lens copy) so compose can sit exactly
/// beside the floating glass, as T3 Code does.
private final class ElsepageNativeTabBar: UITabBar {
    var onContentLayout: ((CGRect) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        let identified = tabButtons(in: self) {
            $0.accessibilityIdentifier?.hasPrefix("elsepage-tab-") == true
        }
        let candidates = identified.isEmpty ? tabButtons(in: self) { _ in true } : identified
        let buttons = candidates.filter {
            let size = convert($0.bounds, from: $0).size
            return abs(size.width - $0.bounds.width) < 1 && abs(size.height - $0.bounds.height) < 1
        }
        let row = buttons.reduce(CGRect.null) { $0.union(convert($1.bounds, from: $1)) }
        if !row.isNull {
            onContentLayout?(row)
        }
    }

    private func tabButtons(in view: UIView, matching match: (UIView) -> Bool) -> [UIView] {
        view.subviews.filter { !$0.isHidden }.flatMap { subview in
            if subview is UIControl, match(subview) { return [subview] }
            return tabButtons(in: subview, matching: match)
        }
    }
}

// MARK: - iOS 18 / Reduce Transparency fallback

/// The same split geometry with a material capsule instead of Liquid Glass.
/// Compose occupies a reserved slot even when hidden, so the capsule never
/// changes width or position.
private struct ElsepageMaterialTabBar: View {
    @Binding var selection: AppTab
    let showsCompose: Bool
    let onImport: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                tabButton(.library)
                tabButton(.mind)
                tabButton(.myMind)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .elsepageMaterial(Capsule())

            if showsCompose {
                Button(action: onImport) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.elsepageTextPrimary)
                        .frame(width: 56, height: 56)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("导入 EPUB")
                .elsepageMaterial(Circle())
            } else {
                Color.clear
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.bottom, 8)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            Image(systemName: tab.symbol)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(isSelected ? Color.elsepageTextPrimary : Color.elsepageTextSecondary)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 52, height: 36)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ElsepageMaterial<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color.elsepageSurface, in: shape)
                .overlay(shape.stroke(Color.elsepageBorder, lineWidth: 0.5))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.elsepageBorder.opacity(0.6), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.10), radius: 12, y: 4)
        }
    }
}

private extension View {
    func elsepageMaterial<S: Shape>(_ shape: S) -> some View {
        modifier(ElsepageMaterial(shape: shape))
    }
}

// MARK: - Shared

private struct ReaderDestination: Identifiable {
    let id = UUID()
    let book: Book
    let locator: BookLocator?
}

private enum AppTab: Hashable {
    case library
    case mind
    case myMind

    static let all: [AppTab] = [.library, .mind, .myMind]

    var title: String {
        switch self {
        case .library: "书架"
        case .mind: "想法"
        case .myMind: "我的"
        }
    }

    var symbol: String {
        switch self {
        case .library: "books.vertical"
        case .mind: "lightbulb"
        case .myMind: "person.crop.circle"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .library: "books.vertical.fill"
        case .mind: "lightbulb.fill"
        case .myMind: "person.crop.circle.fill"
        }
    }
}
