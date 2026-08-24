import SwiftUI

struct AppShell: View {
    @Bindable var library: LibraryModel
    @Bindable var thoughts: ThoughtsModel
    @State private var selection: AppTab = .library

    var body: some View {
        TabView(selection: $selection) {
            TodayView(library: library) { selection = .library }
            .tabItem { Label("今天", systemImage: "sun.max") }
            .tag(AppTab.today)

            LibraryView(model: library)
                .tabItem { Label("书架", systemImage: "books.vertical") }
                .tag(AppTab.library)

            ThoughtsView(model: thoughts)
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
