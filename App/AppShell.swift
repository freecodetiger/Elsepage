import SwiftUI

struct AppShell: View {
    @Bindable var library: LibraryModel
    @State private var selection: AppTab = .library

    var body: some View {
        TabView(selection: $selection) {
            PlaceholderTab(
                title: "今天",
                systemImage: "sun.max",
                message: "继续阅读与今日行动将在后续阶段呈现。"
            )
            .tabItem { Label("今天", systemImage: "sun.max") }
            .tag(AppTab.today)

            LibraryView(model: library)
                .tabItem { Label("书架", systemImage: "books.vertical") }
                .tag(AppTab.library)

            PlaceholderTab(
                title: "思想",
                systemImage: "brain.head.profile",
                message: "这里将承载你的长期阅读思想档案。"
            )
            .tabItem { Label("思想", systemImage: "brain.head.profile") }
            .tag(AppTab.mind)
        }
        .tint(.elsepageAccent)
    }
}

private enum AppTab: Hashable {
    case today
    case library
    case mind
}

private struct PlaceholderTab: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        NavigationStack {
            ZStack {
                Color.elsepageBackground.ignoresSafeArea()
                ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
                    .padding(ElsepageTheme.Spacing.xLarge)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
