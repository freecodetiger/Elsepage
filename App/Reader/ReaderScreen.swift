import SwiftUI

struct ReaderScreen: View {
    @State var model: ReaderModel
    var body: some View {
        Group {
            if model.isPrepared {
                ReadiumReaderView(model: model).ignoresSafeArea(edges: .bottom)
            } else {
                ProgressView("正在打开…")
            }
        }
            .navigationTitle(model.book.title)
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.prepare() }
            .alert("无法打开书籍", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("好") {} } message: { Text(model.errorMessage ?? "") }
    }
}
