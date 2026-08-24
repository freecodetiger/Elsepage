import ReaderCore
import ReadiumAdapterGCDWebServer
import ReadiumNavigator
@preconcurrency import ReadiumShared
import SwiftUI
import UIKit

struct ReadiumReaderView: UIViewControllerRepresentable {
    let model: ReaderModel
    let colorScheme: ColorScheme

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeUIViewController(context: Context) -> UIViewController {
        let host = ReaderHostViewController(model: model)
        host.view.backgroundColor = .systemBackground
        context.coordinator.open(in: host)
        return host
    }
    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        Task { await coordinator.flushPosition() }
    }
    @MainActor final class Coordinator: NSObject, EPUBNavigatorDelegate {
        private let model: ReaderModel
        private weak var navigator: EPUBNavigatorViewController?
        private var publication: Publication?
        private var lastPreferences: ReaderPreferences?
        private var lastColorScheme: ColorScheme?
        private var lastHighlights: [Highlight] = []
        private var lastJumpTarget: Data?

        init(model: ReaderModel) { self.model = model }

        func open(in host: ReaderHostViewController) {
            Task {
                do {
                    let publication = try await model.readium.open(model.fileURL, allowUserInteraction: true)
                    self.publication = publication
                    model.searchHandler = { [weak self] query in
                        guard let self else { return [] }
                        return try await self.search(publication: publication, query: query)
                    }
                    model.chapters = Self.chapters(from: publication.manifest.tableOfContents)
                    let initial = try model.initialLocatorJSON.flatMap(Self.readiumLocator(from:))
                    let actions = EditingAction.defaultActions + [
                        EditingAction(title: "高亮", action: #selector(ReaderHostViewController.highlightSelection)),
                        EditingAction(title: "批注", action: #selector(ReaderHostViewController.noteSelection)),
                    ]
                    let navigator = try EPUBNavigatorViewController(
                        publication: publication,
                        initialLocation: initial,
                        config: .init(
                            editingActions: actions,
                            contentInset: [
                                .compact: (top: 8, bottom: 8),
                                .regular: (top: 16, bottom: 16),
                            ]
                        ),
                        httpServer: model.readium.httpServer
                    )
                    navigator.delegate = self
                    host.addChild(navigator)
                    navigator.view.translatesAutoresizingMaskIntoConstraints = false
                    host.view.addSubview(navigator.view)
                    NSLayoutConstraint.activate([
                        navigator.view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
                        navigator.view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
                        navigator.view.topAnchor.constraint(equalTo: host.view.topAnchor),
                        navigator.view.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
                    ])
                    navigator.didMove(toParent: host)
                    host.navigator = navigator
                    self.navigator = navigator
                    navigator.observeDecorationInteractions(inGroup: "highlights") { [weak self] event in
                        guard let id = UUID(uuidString: event.decoration.id) else { return }
                        self?.presentHighlight(id: id, from: host)
                    }
                    apply(preferences: model.preferences, colorScheme: host.traitCollection.userInterfaceStyle == .dark ? .dark : .light)
                    applyHighlights()
                } catch is CancellationError {
                    return
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
        }

        func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
            do {
                let anchor = try Self.anchor(from: locator)
                model.save(locator: anchor)
                model.currentChapterTitle = locator.title ?? model.currentChapterTitle
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }

        func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
            model.errorMessage = error.localizedDescription
        }

        func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
            model.toggleControls()
        }

        func update(preferences: ReaderPreferences, colorScheme: ColorScheme, jumpTarget: Data?) {
            if preferences != lastPreferences || colorScheme != lastColorScheme {
                apply(preferences: preferences, colorScheme: colorScheme)
            }
            applyHighlights()
            guard let jumpTarget, jumpTarget != lastJumpTarget else { return }
            lastJumpTarget = jumpTarget
            Task {
                guard let locator = try? Self.readiumLocator(from: jumpTarget) else { return }
                await navigator?.go(to: locator)
            }
        }

        private func apply(preferences: ReaderPreferences, colorScheme: ColorScheme) {
            guard let navigator else { return }
            lastPreferences = preferences
            lastColorScheme = colorScheme
            let theme: Theme = switch preferences.theme {
            case .system: colorScheme == .dark ? .dark : .light
            case .light: .light
            case .dark: .dark
            case .sepia: .sepia
            }
            navigator.submitPreferences(.init(
                fontSize: preferences.fontSize,
                lineHeight: preferences.lineHeight,
                pageMargins: preferences.pageMargins,
                publisherStyles: false,
                scroll: preferences.readingMode == .scroll,
                theme: theme
            ))
            navigator.parent?.view.backgroundColor = theme.backgroundColor.uiColor
        }

        private func applyHighlights() {
            guard let navigator else { return }
            guard model.highlights != lastHighlights else { return }
            lastHighlights = model.highlights
            let decorations = model.highlights.compactMap { highlight -> Decoration? in
                guard let locator = try? Self.readiumLocator(from: highlight.locator.json) else { return nil }
                return Decoration(
                    id: highlight.id.uuidString.lowercased(),
                    locator: locator,
                    style: .highlight(tint: Self.color(for: highlight.color))
                )
            }
            navigator.apply(decorations: decorations, in: "highlights")
        }

        private func presentHighlight(id: UUID, from host: UIViewController) {
            guard let highlight = model.highlights.first(where: { $0.id == id }) else { return }
            model.selectedHighlightID = id
            let linkedNote = model.notes.first { $0.highlightID == id }
            let alert = UIAlertController(
                title: linkedNote == nil ? "高亮" : "批注",
                message: linkedNote?.body ?? highlight.locator.textHighlight,
                preferredStyle: .actionSheet
            )
            alert.addAction(UIAlertAction(title: "跳转到此处", style: .default) { [weak model] _ in model?.jump(to: highlight.locator) })
            if let linkedNote {
                alert.addAction(UIAlertAction(title: "编辑批注", style: .default) { [weak host, weak model] _ in
                    guard let host, let model else { return }
                    Self.presentNoteEditor(linkedNote, from: host, model: model)
                })
                alert.addAction(UIAlertAction(title: "删除批注", style: .destructive) { [weak model] _ in model?.delete(note: linkedNote) })
            }
            alert.addAction(UIAlertAction(title: "删除高亮", style: .destructive) { [weak model] _ in model?.delete(highlight: highlight) })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            if let popover = alert.popoverPresentationController {
                popover.sourceView = host.view
                popover.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 1, height: 1)
            }
            host.present(alert, animated: true)
        }

        private static func presentNoteEditor(_ note: Note, from host: UIViewController, model: ReaderModel) {
            let alert = UIAlertController(title: "编辑批注", message: note.locator.textHighlight, preferredStyle: .alert)
            alert.addTextField { $0.text = note.body }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak alert, weak model] _ in
                guard let body = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else { return }
                model?.update(note: note, body: body)
            })
            host.present(alert, animated: true)
        }

        private func search(publication: Publication, query: String) async throws -> [ReaderSearchResult] {
            let iterator: any SearchIterator
            switch await publication.search(query: query) {
            case .success(let value): iterator = value
            case .failure(let error): throw error
            }
            var results: [ReaderSearchResult] = []
            while !Task.isCancelled {
                switch await iterator.next() {
                case .success(let collection):
                    guard let collection else { return results }
                    results.append(contentsOf: try collection.locators.map {
                        let anchor = try Self.anchor(from: $0)
                        return ReaderSearchResult(locator: anchor, excerpt: $0.text.highlight ?? $0.text.before ?? query)
                    })
                case .failure(let error): throw error
                }
            }
            return results
        }

        func flushPosition() async { await model.flushPosition() }

        private static func color(for color: HighlightColor) -> UIColor {
            switch color {
            case .yellow: .systemYellow.withAlphaComponent(0.42)
            case .green: .systemGreen.withAlphaComponent(0.35)
            case .blue: .systemBlue.withAlphaComponent(0.30)
            case .pink: .systemPink.withAlphaComponent(0.32)
            }
        }

        private static func chapters(from links: [ReadiumShared.Link], depth: Int = 0) -> [ReaderChapter] {
            links.flatMap { link in
                var result: [ReaderChapter] = []
                let locator = Locator(href: link.url(), mediaType: link.mediaType ?? .xhtml, title: link.title)
                if let data = try? JSONSerialization.data(withJSONObject: locator.json) {
                    result.append(.init(
                        id: "\(depth)-\(link.href)",
                        title: link.title ?? "未命名章节",
                        depth: depth,
                        href: link.href,
                        locatorJSON: data,
                        progression: locator.locations.progression
                    ))
                }
                result.append(contentsOf: chapters(from: link.children, depth: depth + 1))
                return result
            }
        }

        private static func readiumLocator(from data: Data) throws -> Locator? {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return try Locator(json: json)
        }

        static func anchor(from locator: Locator) throws -> BookLocator {
            try BookLocator(
                json: JSONSerialization.data(withJSONObject: locator.json),
                href: locator.href.string,
                progression: locator.locations.progression,
                totalProgression: locator.locations.totalProgression,
                textBefore: locator.text.before,
                textHighlight: locator.text.highlight,
                textAfter: locator.text.after
            )
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.update(
            preferences: model.preferences,
            colorScheme: colorScheme,
            jumpTarget: model.jumpTargetJSON
        )
    }
}

@MainActor final class ReaderHostViewController: UIViewController {
    let model: ReaderModel
    weak var navigator: EPUBNavigatorViewController?
    init(model: ReaderModel) { self.model = model; super.init(nibName: nil, bundle: nil) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(flushPosition), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(flushPosition), name: UIApplication.willResignActiveNotification, object: nil)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        flushPosition()
    }

    @objc private func flushPosition() { Task { await model.flushPosition() } }

    @objc func highlightSelection() {
        guard let navigator, let selection = navigator.currentSelection,
              let anchor = try? ReadiumReaderView.Coordinator.anchor(from: selection.locator) else { return }
        model.saveHighlight(locator: anchor)
        navigator.clearSelection()
    }

    @objc func noteSelection() {
        guard let navigator, let selection = navigator.currentSelection,
              let anchor = try? ReadiumReaderView.Coordinator.anchor(from: selection.locator) else { return }
        let alert = UIAlertController(title: "添加批注", message: selection.locator.text.highlight, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "写下你的想法" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert, weak navigator] _ in
            guard let body = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else { return }
            self?.model.saveNote(locator: anchor, body: body)
            navigator?.clearSelection()
        })
        present(alert, animated: true)
    }
}
