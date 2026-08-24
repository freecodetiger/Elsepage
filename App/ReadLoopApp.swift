import SwiftUI

@main
struct ReadLoopApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if let message = appModel.startupError {
                    ContentUnavailableView("无法打开本地书库", systemImage: "externaldrive.badge.exclamationmark", description: Text(message))
                } else if let library = appModel.library {
                    AppShell(library: library)
                } else {
                    ProgressView("正在打开书库…")
                }
            }
            .task { await appModel.start() }
        }
    }
}
