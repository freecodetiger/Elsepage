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
    @State private var selection: AppTab = .today
    @State private var readerDestination: ReaderDestination?

    var body: some View {
        TabView(selection: $selection) {
            TodayView(library: library, achievements: achievements) { book in
                readerDestination = .init(book: book, locator: nil)
            } openLibrary: {
                selection = .library
            }
            .tabItem { Label("今天", systemImage: "sun.max") }
            .tag(AppTab.today)

            LibraryView(model: library, settings: settings) { selection = .today }
                .tabItem { Label("书架", systemImage: "books.vertical") }
                .tag(AppTab.library)

            ThoughtsView(model: thoughts, settings: settings) { book, locator in
                readerDestination = .init(book: book, locator: locator)
            }
            .tabItem { Label("思想", systemImage: "brain.head.profile") }
            .tag(AppTab.mind)

            MyMindView(model: myMind, settings: settings, achievements: achievements) { book, locator in
                readerDestination = .init(book: book, locator: locator)
            }
            .tabItem { Label("我的头脑", systemImage: "person.crop.rectangle") }
            .tag(AppTab.myMind)
        }
        .tint(.elsepageAccent)
        .fullScreenCover(item: $readerDestination) { destination in
            ReaderScreen(
                model: library.readerModel(for: destination.book, locator: destination.locator),
                achievements: achievements,
                onReflectionSaved: { selection = .today }
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
    case today
    case library
    case mind
    case myMind
}
