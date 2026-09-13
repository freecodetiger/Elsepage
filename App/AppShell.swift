import LibraryCore
import ReaderCore
import SwiftUI

struct AppShell: View {
    @Bindable var library: LibraryModel
    @Bindable var thoughts: ThoughtsModel
    @Bindable var myMind: MyMindModel
    @Bindable var settings: SettingsRootModel
    @Bindable var achievements: AchievementModel
    @Bindable var appModel: AppModel
    @State private var selection: AppTab = .library
    @State private var readerDestination: ReaderDestination?

    var body: some View {
        TabView(selection: $selection) {
            LibraryView(
                model: library,
                settings: settings,
                achievements: achievements
            )
            .tabItem { Label("书架", systemImage: "books.vertical") }
            .tag(AppTab.library)

            ThoughtsView(model: thoughts, settings: settings) { book, locator in
                readerDestination = .init(book: book, locator: locator)
            }
            .tabItem { Label("想法", systemImage: "lightbulb") }
            .tag(AppTab.mind)

            MyMindView(model: myMind, settings: settings, achievements: achievements) { book, locator in
                readerDestination = .init(book: book, locator: locator)
            }
            .tabItem { Label("我的", systemImage: "person.crop.circle") }
            .tag(AppTab.myMind)
        }
        .tint(.elsepageInteractive)
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
}
