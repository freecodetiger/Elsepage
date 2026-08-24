import ReaderCore
import ReadiumAdapterGCDWebServer
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit

struct ReadiumReaderView: UIViewControllerRepresentable {
    let model: ReaderModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeUIViewController(context: Context) -> UIViewController {
        let host = ReaderHostViewController(model: model)
        host.view.backgroundColor = .systemBackground
        context.coordinator.open(in: host)
        return host
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    @MainActor final class Coordinator: NSObject, EPUBNavigatorDelegate {
        private let model: ReaderModel
        private weak var navigator: EPUBNavigatorViewController?

        init(model: ReaderModel) { self.model = model }

        func open(in host: ReaderHostViewController) {
            Task {
                do {
                    let publication = try await model.readium.open(model.fileURL, allowUserInteraction: true)
                    let initial = try model.initialLocatorJSON.flatMap(Self.readiumLocator(from:))
                    let actions = EditingAction.defaultActions + [
                        EditingAction(title: "高亮", action: #selector(ReaderHostViewController.highlightSelection)),
                        EditingAction(title: "批注", action: #selector(ReaderHostViewController.noteSelection)),
                    ]
                    let navigator = try EPUBNavigatorViewController(
                        publication: publication,
                        initialLocation: initial,
                        config: .init(editingActions: actions),
                        httpServer: model.readium.httpServer
                    )
                    navigator.delegate = self
                    host.addChild(navigator)
                    navigator.view.frame = host.view.bounds
                    navigator.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    host.view.addSubview(navigator.view)
                    navigator.didMove(toParent: host)
                    host.navigator = navigator
                    self.navigator = navigator
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
        }

        func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
            do {
                let anchor = try Self.anchor(from: locator)
                model.save(locator: anchor)
            } catch {
                model.errorMessage = error.localizedDescription
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
}

@MainActor final class ReaderHostViewController: UIViewController {
    let model: ReaderModel
    weak var navigator: EPUBNavigatorViewController?
    init(model: ReaderModel) { self.model = model; super.init(nibName: nil, bundle: nil) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

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
