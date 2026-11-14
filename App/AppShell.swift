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
        // The system tab bar is a single capsule. Hide it and draw the split
        // capsule + compose bar so the three destinations sit left of the
        // trailing compose action. iOS 18 falls back to a material capsule.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardVisible {
                ElsepageTabBar(selection: $selection) {
                    openImport()
                }
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

    private func openImport() {
        selection = .library
        importRequested = true
    }
}

/// The floating split bar: a glass capsule with the three destinations and a
/// separate circular compose action. The capsule and button use the iOS 26
/// glass API; older systems and Reduce Transparency get a material/solid
/// surface with the same geometry.
private struct ElsepageTabBar: View {
    @Binding var selection: AppTab
    let onImport: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                barBody
            }
        } else {
            barBody
        }
    }

    private var barBody: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                tabButton(.library)
                tabButton(.mind)
                tabButton(.myMind)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .elsepageGlass(Capsule())

            Button(action: onImport) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.elsepageTextPrimary)
                    .frame(width: 56, height: 56)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("导入 EPUB")
            .elsepageGlass(Circle(), interactive: true)
        }
        .padding(.horizontal, ElsepageTheme.Spacing.pageInset)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
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

private struct ElsepageGlass<S: Shape>: ViewModifier {
    let shape: S
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color.elsepageSurface, in: shape)
                .overlay(shape.stroke(Color.elsepageBorder, lineWidth: 0.5))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.elsepageBorder.opacity(0.6), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.10), radius: 12, y: 4)
        }
    }
}

private extension View {
    func elsepageGlass<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        modifier(ElsepageGlass(shape: shape, interactive: interactive))
    }
}

private struct ReaderDestination: Identifiable {
    let id = UUID()
    let book: Book
    let locator: BookLocator?
}

private enum AppTab: Hashable {
    case library
    case mind
    case myMind

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
}
