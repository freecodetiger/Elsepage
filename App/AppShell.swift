import LibraryCore
import ReaderCore
import SwiftUI

struct AppShell: View {
    @Bindable var library: LibraryModel
    @Bindable var thoughts: ThoughtsModel
    @Bindable var myMind: MyMindModel
    @Bindable var providerSettings: ProviderSettingsModel
    @State private var selection: AppTab = .today
    @State private var readerDestination: ReaderDestination?

    var body: some View {
        TabView(selection: $selection) {
            TodayView(library: library) { book in
                readerDestination = .init(book: book, locator: nil)
            } openLibrary: {
                selection = .library
            }
            .tabItem { Label("今天", systemImage: "sun.max") }
            .tag(AppTab.today)

            LibraryView(model: library, providerSettings: providerSettings) { selection = .today }
                .tabItem { Label("书架", systemImage: "books.vertical") }
                .tag(AppTab.library)

            ThoughtsView(model: thoughts, providerSettings: providerSettings) { book, locator in
                readerDestination = .init(book: book, locator: locator)
            }
            .tabItem { Label("思想", systemImage: "brain.head.profile") }
            .tag(AppTab.mind)

            MyMindView(model: myMind, providerSettings: providerSettings) { book, locator in
                readerDestination = .init(book: book, locator: locator)
            }
            .tabItem { Label("我的头脑", systemImage: "person.crop.rectangle") }
            .tag(AppTab.myMind)
        }
        .tint(.elsepageAccent)
        .fullScreenCover(item: $readerDestination) { destination in
            ReaderScreen(
                model: library.readerModel(for: destination.book, locator: destination.locator),
                onReflectionSaved: { selection = .today }
            )
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
