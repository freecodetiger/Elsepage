import LibraryCore
import Observation
import ReaderCore
import ReadingSessionCore
import ReflectionCore
import SwiftUI

/// Feature-scoped state for the text-only, local-first reflection prompt.
/// Construction happens after the caller has ended a `ReadingSession`.
@MainActor @Observable
final class SessionReflectionModel {
    enum SubmissionState: Equatable {
        case editing
        case saving
        case saved
    }

    let book: Book
    let summary: SessionEndingSummary
    let locator: BookLocator
    private let submission: TextReflectionSubmissionService
    private let draftID = ReflectionID()

    var text = ""
    private(set) var state: SubmissionState = .editing
    var errorMessage: String?

    init(
        book: Book,
        summary: SessionEndingSummary,
        locator: BookLocator,
        reflectionRepository: any ReflectionRepository
    ) {
        self.book = book
        self.summary = summary
        self.locator = locator
        submission = TextReflectionSubmissionService(repository: reflectionRepository)
    }

    var canSubmit: Bool {
        state == .editing && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func submit() async -> Reflection? {
        guard canSubmit else { return nil }
        state = .saving
        do {
            let reflection = try await submission.submit(.init(
                id: draftID,
                bookID: book.id,
                sessionID: summary.session.id,
                locator: locator,
                originalText: text
            ))
            state = .saved
            return reflection
        } catch is CancellationError {
            state = .editing
            return nil
        } catch {
            state = .editing
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

struct SessionReflectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: SessionReflectionModel
    let onSaved: @MainActor (Reflection) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.large) {
                    header
                    TextField("写下一点此刻真正留下来的东西…", text: $model.text, axis: .vertical)
                        .lineLimit(5...12)
                        .padding(ElsepageTheme.Spacing.medium)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.medium, style: .continuous))
                        .accessibilityLabel("本次阅读感想")

                    Text("这是你的原始想法，会先保存在本机。现在不会请求 AI。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(ElsepageTheme.Spacing.page)
            }
            .background(Color.elsepageBackground)
            .navigationTitle("留下些什么")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("今天先不了") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            if let reflection = await model.submit() {
                                onSaved(reflection)
                                dismiss()
                            }
                        }
                    }
                    .disabled(!model.canSubmit)
                }
            }
        }
        .alert("暂时无法保存", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            Text(bookline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(durationLine)
                .font(.system(.title2, design: .serif, weight: .semibold))
            if let progress = model.summary.progressDelta, progress > 0 {
                Text("这次前进了 \(progress, format: .percent.precision(.fractionLength(0)))。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if model.summary.session.highlightCount > 0 || model.summary.session.noteCount > 0 {
                Text(annotationLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var bookline: String { "刚刚读了《\(model.book.title)》" }

    private var durationLine: String {
        let minutes = Int((model.summary.wallClockDuration / 60).rounded(.down))
        return minutes > 0 ? "这一段约 (minutes) 分钟" : "这一段阅读结束了"
    }

    private var annotationLine: String {
        let highlights = model.summary.session.highlightCount
        let notes = model.summary.session.noteCount
        switch (highlights, notes) {
        case (let h, let n) where h > 0 && n > 0: return "留下了 (h) 个高亮和 (n) 条批注。"
        case (let h, _): return "留下了 (h) 个高亮。"
        case (_, let n): return "留下了 (n) 条批注。"
        }
    }
}
