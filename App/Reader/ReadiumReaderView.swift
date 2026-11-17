import Foundation
import LibraryCore
import ReaderCore
import ReadiumNavigator
@preconcurrency import ReadiumShared
import SwiftUI
import UIKit
import WebKit

/// The page surface the navigator actually paints. Reader sheets use the same
/// color so a dark page does not open a translucent system sheet over live text.
enum ReaderPageBackground {
    static func readiumTheme(for readerTheme: ReaderTheme, colorScheme: ColorScheme) -> Theme {
        switch readerTheme {
        case .system: colorScheme == .dark ? .dark : .light
        case .light: .light
        case .dark: .dark
        case .sepia: .sepia
        }
    }

    static func color(for readerTheme: ReaderTheme, colorScheme: ColorScheme) -> SwiftUI.Color {
        SwiftUI.Color(uiColor: readiumTheme(for: readerTheme, colorScheme: colorScheme).backgroundColor.uiColor)
    }
}

/// Geometry the reader needs from Readium's private web view. Readium exposes
/// no hook for either fact, so both are read from the hierarchy it builds.
enum ReaderWebViewAccess {
    /// Every web view under `view`. Readium uses one per visible spread.
    static func webViews(in view: UIView) -> [WKWebView] {
        var found: [WKWebView] = []
        if let web = view as? WKWebView { found.append(web) }
        for subview in view.subviews { found += webViews(in: subview) }
        return found
    }

    /// True once a chapter is loaded. Before that the web view shows
    /// `about:blank` in WebKit's default 980pt viewport.
    static func hasLoadedChapter(in view: UIView) -> Bool {
        guard let web = webViews(in: view).first else { return false }
        guard !web.isLoading, let url = web.url else { return false }
        return url.absoluteString != "about:blank"
    }

    /// Scroll mode lays the chapter out to the viewport width, so a horizontal
    /// offset can only be a leftover from the 980pt pre-load layout. Paged mode
    /// uses that offset for page turns and must be left alone.
    static func clampScrollModeOffset(in view: UIView) {
        for web in webViews(in: view) {
            let scroll = web.scrollView
            guard !scroll.isPagingEnabled else { continue }
            scroll.alwaysBounceHorizontal = false
            guard abs(scroll.contentOffset.x) > 0.5 else { continue }
            scroll.setContentOffset(
                CGPoint(x: 0, y: scroll.contentOffset.y),
                animated: false
            )
        }
    }
}

struct ReadiumReaderView: UIViewControllerRepresentable {
    let model: ReaderModel
    /// Value snapshots make Observation changes visible to the SwiftUI/UIKit bridge.
    let preferences: ReaderPreferences
    let highlights: [Highlight]
    let notes: [Note]
    let jumpTargetJSON: Data?
    let colorScheme: ColorScheme

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeUIViewController(context: Context) -> UIViewController {
        let host = ReaderHostViewController(model: model)
        host.view.backgroundColor = .systemBackground
        context.coordinator.open(in: host)
        return host
    }
    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.cancelOpening()
        Task { await coordinator.flushPosition() }
    }
    @MainActor final class Coordinator: NSObject, EPUBNavigatorDelegate {
        private let model: ReaderModel
        private weak var navigator: EPUBNavigatorViewController?
        private var publication: Publication?
        private var lastPreferences: ReaderPreferences?
        private var lastColorScheme: ColorScheme?
        private var lastHighlights: [Highlight] = []
        private var lastNotes: [Note] = []
        private var lastJumpTarget: Data?
        private var openingTask: Task<Void, Never>?
        /// Phase-0 perf: open() → first locationDidChange timing.
        private var parseInterval: Perf.Interval?
        private var navigatorReadyAt: CFTimeInterval = 0
        private var firstPageRecorded = false

        init(model: ReaderModel) { self.model = model }

        func open(in host: ReaderHostViewController) {
            openingTask?.cancel()
            openingTask = Task { [weak self, weak host] in
                do {
                    guard let self, let host else { return }
                    parseInterval = Perf.shared.begin(.readerParse)
                    let publication = try await model.readium.open(model.fileURL, allowUserInteraction: true)
                    if let interval = parseInterval { Perf.shared.end(interval) }
                    parseInterval = nil
                    try Task.checkCancellation()
                    self.publication = publication
                    model.searchHandler = { [weak self] query in
                        guard let self else { return [] }
                        return try await self.search(publication: publication, query: query)
                    }
                    model.chapters = Self.chapters(from: publication.manifest.tableOfContents)
                    let initial = try model.initialLocatorJSON.flatMap(Self.readiumLocator(from:))
                    // The system selection menu is suppressed in favor of the
                    // app's own in-place toolbar (shouldShowMenuForSelection).
                    // Copy remains for hardware keyboards and system affordances.
                    let actions = [EditingAction.copy]
                    let navigator = try EPUBNavigatorViewController(
                        publication: publication,
                        initialLocation: initial,
                        config: .init(
                            preferences: Self.readiumPreferences(
                                from: model.preferences,
                                colorScheme: host.traitCollection.userInterfaceStyle == .dark ? .dark : .light
                            ),
                            editingActions: actions,
                            // Readium scrolls vertically inside one spine resource.
                            // Keep its outer page turn enabled so readers can cross
                            // chapter/resource boundaries at the top and bottom.
                            disablePageTurnsWhileScrolling: false
                        )
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
                    model.onSelectionFinished = { [weak navigator] in navigator?.clearSelection() }
                    navigator.observeDecorationInteractions(inGroup: "highlights") { [weak self, weak navigator] event in
                        guard let id = UUID(uuidString: event.decoration.id), let navigator else { return }
                        let point = event.point.map { AnnotationLog.rect(CGRect(origin: $0, size: .zero)) } ?? "nil"
                        AnnotationLog.event("decoration.activated id=\(AnnotationLog.id(id)) rect=\(AnnotationLog.rect(event.rect)) point=\(point)")
                        let anchor = Self.menuAnchor(for: event)
                        Task { [weak self] in
                            let noteIDs = await Self.decorationIDsAtLastPoint(in: "notes", navigator: navigator)
                            AnnotationLog.event("highlight.hit id=\(AnnotationLog.id(id)) resolved=\(noteIDs != nil) overlapNotes=\(noteIDs?.map { AnnotationLog.id($0) }.joined(separator: ",") ?? "unresolved")")
                            self?.model.handleHighlightActivation(
                                for: id,
                                confirmedNoteID: noteIDs?.first,
                                resolvedPointOverlap: noteIDs != nil,
                                anchor: anchor
                            )
                        }
                    }
                    navigator.observeDecorationInteractions(inGroup: "notes") { [weak self, weak navigator] event in
                        guard let id = UUID(uuidString: event.decoration.id), let navigator else { return }
                        let anchor = Self.menuAnchor(for: event)
                        Task { [weak self] in
                            let highlightIDs = await Self.decorationIDsAtLastPoint(in: "highlights", navigator: navigator)
                            AnnotationLog.event("note.hit id=\(AnnotationLog.id(id)) resolved=\(highlightIDs != nil) overlapHighlights=\(highlightIDs?.map { AnnotationLog.id($0) }.joined(separator: ",") ?? "unresolved")")
                            self?.model.handleNoteActivation(
                                for: id,
                                confirmedHighlightID: highlightIDs?.first,
                                resolvedPointOverlap: highlightIDs != nil,
                                anchor: anchor
                            )
                        }
                    }
                    apply(preferences: model.preferences, colorScheme: host.traitCollection.userInterfaceStyle == .dark ? .dark : .light)
                    // Highlights own the primary hit target when ranges overlap;
                    // the highlight menu exposes any overlapping note explicitly.
                    applyHighlights(model.highlights)
                    applyNotes(model.notes)
                    navigatorReadyAt = CFAbsoluteTimeGetCurrent()
                    startFirstPageWatch(in: host)
                } catch is CancellationError {
                    self?.abortParseIfNeeded()
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.abortParseIfNeeded()
                    self?.model.errorMessage = error.localizedDescription
                }
                self?.openingTask = nil
            }
        }

        func cancelOpening() {
            openingTask?.cancel()
            openingTask = nil
            navigator?.delegate = nil
        }

        /// Waits for the first chapter to paint, then reveals the reader. The
        /// reveal is also the point where scroll mode's horizontal offset is
        /// pinned: the pre-load layout is 980pt wide and a drag during that
        /// window parks the page off-centre.
        private func startFirstPageWatch(in host: ReaderHostViewController) {
            Task { @MainActor [weak self, weak host] in
                for _ in 0 ..< 50 {
                    guard self != nil, let host else { return }
                    if ReaderWebViewAccess.hasLoadedChapter(in: host.view) {
                        ReaderWebViewAccess.clampScrollModeOffset(in: host.view)
                        self?.model.markFirstPageRendered()
                        return
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                // Never trap the reader behind the cover if the load signal is
                // missed; the worst case is the old behaviour for one open.
                self?.model.markFirstPageRendered()
            }
        }

        private func recordFirstPageIfNeeded() {
            guard !firstPageRecorded else { return }
            firstPageRecorded = true
            let now = CFAbsoluteTimeGetCurrent()
            if navigatorReadyAt > 0 {
                Perf.shared.record(.readerToFirstPage, ms: (now - navigatorReadyAt) * 1000)
            }
            if let interval = model.perfOpenInterval {
                Perf.shared.end(interval)
                model.perfOpenInterval = nil
            } else if model.perfOpenBeganAt > 0 {
                Perf.shared.record(.readerOpen, ms: (now - model.perfOpenBeganAt) * 1000)
            }
            Perf.shared.signpostEvent("reader.firstPage")
        }

        private func abortParseIfNeeded() {
            if let interval = parseInterval {
                Perf.shared.abort(interval)
                parseInterval = nil
            }
        }

        /// Readium applies these margins inside the full-screen navigator.
        /// Only the safe area is reserved: the chrome is a floating overlay, so
        /// tapping to show it never changes the layout and never reflows the
        /// page. The transient capsule is allowed to cover the text beneath it.
        func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
            let safe = navigator.view.window?.safeAreaInsets ?? .zero
            return UIEdgeInsets(
                top: safe.top + ReaderChromeMetrics.contentTopInset,
                left: safe.left,
                bottom: safe.bottom + ReaderChromeMetrics.contentBottomInset,
                right: safe.right
            )
        }

        func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
            do {
                let anchor = try Self.anchor(from: locator)
                recordFirstPageIfNeeded()
                AnnotationLog.event("locationChange href=\(locator.href) progression=\(locator.locations.progression ?? -1)")
                model.save(locator: anchor)
                model.currentChapterTitle = locator.title ?? model.currentChapterTitle
                model.hideControls()
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }

        func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
            model.errorMessage = error.localizedDescription
        }

        func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
            let selectionActive = self.navigator?.currentSelection != nil
            guard !selectionActive else {
                AnnotationLog.event("didTapAt point=\(AnnotationLog.rect(CGRect(origin: point, size: .zero))) → ignored (selection active)")
                return
            }
            // One tap, one change: a tap on content dismisses an open
            // highlight menu instead of also toggling the reader chrome. A
            // tap inside the menu's grace window is swallowed entirely — it
            // is a stray event from the very tap that opened the menu.
            switch model.closeHighlightMenu() {
            case .closed, .deferred: return
            case .absent:
                AnnotationLog.event("didTapAt point=\(AnnotationLog.rect(CGRect(origin: point, size: .zero))) → chrome toggle")
                model.toggleControls()
            }
        }

        func navigator(_ navigator: SelectableNavigator, shouldShowMenuForSelection selection: Selection) -> Bool {
            guard let anchor = try? ReadiumReaderView.Coordinator.anchor(from: selection.locator),
                  let epubNavigator = self.navigator else {
                AnnotationLog.event("selection.callback → fallback to system menu (anchor conversion failed)")
                return true
            }
            let selectedText = selection.locator.text.highlight ?? ""
            let expectedAnchor = anchor
            Task { [weak self, weak epubNavigator] in
                guard let self, let epubNavigator else { return }
                let range = await self.resolveSelectionRange(
                    anchor: expectedAnchor,
                    fallback: epubNavigator,
                    bookID: self.model.book.id
                )
                guard let current = epubNavigator.currentSelection,
                      let currentAnchor = try? ReadiumReaderView.Coordinator.anchor(from: current.locator),
                      currentAnchor.identifiesSameAnchor(as: expectedAnchor) else {
                    return
                }
                self.model.showSelectionMenu(
                    locator: expectedAnchor,
                    range: range,
                    text: selectedText,
                    frame: selection.frame
                )
            }
            return false
        }

        private func resolveSelectionRange(
            anchor: BookLocator,
            fallback navigator: EPUBNavigatorViewController,
            bookID: BookID
        ) async -> AnnotationRange? {
            guard case .success(let value) = await navigator.evaluateJavaScript(Self.selectionRangeScript),
                  let result = value as? [String: Any],
                  let startValue = result["start"] as? NSNumber,
                  let endValue = result["end"] as? NSNumber else {
                return nil
            }
            let startProgression = startValue.doubleValue
            let endProgression = endValue.doubleValue
            guard startProgression.isFinite, endProgression.isFinite,
                  (0...1).contains(startProgression), (0...1).contains(endProgression) else {
                return nil
            }
            do {
                let start = try Self.rangeLocator(
                    from: anchor,
                    progression: min(startProgression, endProgression)
                )
                let end = try Self.rangeLocator(
                    from: anchor,
                    progression: max(startProgression, endProgression)
                )
                return AnnotationRange(
                    bookID: bookID,
                    resourceHref: anchor.href,
                    startLocator: start,
                    endLocator: end
                )
            } catch {
                AnnotationLog.event("selection.range.failed \(error)")
                return nil
            }
        }

        private static func rangeLocator(from anchor: BookLocator, progression: Double) throws -> BookLocator {
            let text = anchor.textHighlight ?? ""
            let json = try JSONSerialization.data(withJSONObject: [
                "href": anchor.href,
                "type": "application/xhtml+xml",
                "locations": ["progression": progression],
                "text": ["highlight": text],
            ], options: [.sortedKeys])
            return try BookLocator(
                json: json,
                href: anchor.href,
                progression: progression,
                textHighlight: text
            )
        }

        private static let selectionRangeScript = """
        (function() {
          const selection = window.getSelection();
          if (!selection || selection.isCollapsed || selection.rangeCount === 0) return null;
          const range = selection.getRangeAt(0);
          const selected = selection.toString();
          if (!selected || !selected.trim()) return null;
          function textOffset(node, offset) {
            try {
              const probe = document.createRange();
              probe.selectNodeContents(document.body);
              probe.setEnd(node, offset);
              return probe.toString().length;
            } catch (_) {
              return null;
            }
          }
          const startOffset = textOffset(range.startContainer, range.startOffset);
          const endOffset = textOffset(range.endContainer, range.endOffset);
          const total = (document.body.textContent || "").length;
          if (startOffset === null || endOffset === null || total <= 0) return null;
          return {
            start: Math.min(startOffset, endOffset) / total,
            end: Math.max(startOffset, endOffset) / total
          };
        })()
        """

        nonisolated func navigator(_ navigator: EPUBNavigatorViewController, setupUserScripts userContentController: WKUserContentController) {
            let source = """
            window.__readiumLastDecorationPoint = null;
            (function() {
              const remember = function(event) {
                window.__readiumLastDecorationPoint = { x: event.clientX, y: event.clientY };
              };
              document.addEventListener("click", remember, true);
              document.addEventListener("pointerup", remember, true);
            })();
            """
            userContentController.addUserScript(WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        }

        private static func menuAnchor(for event: OnDecorationActivatedEvent) -> CGRect? {
            guard let point = event.point else { return event.rect }
            return CGRect(x: point.x, y: point.y, width: 1, height: 1)
        }

        private static func decorationIDsAtLastPoint(
            in group: String,
            navigator: EPUBNavigatorViewController
        ) async -> [UUID]? {
            let script = """
            (function() {
              const point = window.__readiumLastDecorationPoint;
              if (!point || !window.readium) return { x: null, y: null, ids: [] };
              const group = readium.getDecorations('\(group)');
              const result = [];
              function contains(rect) {
                return point.x >= rect.left && point.x <= rect.right &&
                       point.y >= rect.top && point.y <= rect.bottom;
              }
              for (const item of (group.items || [])) {
                let matched = false;
                const elements = item.clickableElements || [];
                for (const element of elements) {
                  if (contains(element.getBoundingClientRect())) {
                    matched = true;
                    break;
                  }
                }
                if (matched) result.push(item.decoration.id);
              }
              return { x: point.x, y: point.y, ids: result };
            })()
            """
            guard case .success(let value) = await navigator.evaluateJavaScript(script),
                  let payload = value as? [String: Any],
                  let ids = payload["ids"] as? [String],
                  let x = (payload["x"] as? NSNumber)?.doubleValue,
                  let y = (payload["y"] as? NSNumber)?.doubleValue else { return nil }
            let pointDescription = String(format: "(%.1f,%.1f)", x, y)
            AnnotationLog.event("decoration.point group=\(group) point=\(pointDescription) ids=\(ids.joined(separator: ","))")
            Perf.shared.event("annotation.point group=\(group) point=\(pointDescription) ids=\(ids.joined(separator: ","))")
            return ids.compactMap(UUID.init(uuidString:))
        }

        func update(
            preferences: ReaderPreferences,
            highlights: [Highlight],
            notes: [Note],
            colorScheme: ColorScheme,
            jumpTarget: Data?
        ) {
            if preferences != lastPreferences || colorScheme != lastColorScheme {
                apply(preferences: preferences, colorScheme: colorScheme)
            }
            applyHighlights(highlights)
            applyNotes(notes)
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
            let readiumPreferences = Self.readiumPreferences(from: preferences, colorScheme: colorScheme)
            navigator.submitPreferences(readiumPreferences)
            navigator.parent?.view.backgroundColor = readiumPreferences.theme?.backgroundColor.uiColor
            // Switching into scroll mode reflows the chapter; drop any
            // horizontal offset the previous page layout left behind.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak navigator] in
                guard let navigator else { return }
                ReaderWebViewAccess.clampScrollModeOffset(in: navigator.view)
            }
        }

        private static func readiumPreferences(from preferences: ReaderPreferences, colorScheme: ColorScheme) -> EPUBPreferences {
            let theme = ReaderPageBackground.readiumTheme(for: preferences.theme, colorScheme: colorScheme)
            return .init(
                fontSize: preferences.fontSize,
                lineHeight: preferences.lineHeight,
                pageMargins: preferences.pageMargins,
                paragraphSpacing: 0.65,
                publisherStyles: false,
                scroll: preferences.readingMode == .scroll,
                textNormalization: true,
                theme: theme
            )
        }

        private func applyHighlights(_ highlights: [Highlight]) {
            guard let navigator else { return }
            guard highlights != lastHighlights else { return }
            AnnotationLog.event("decorations.reapply count=\(highlights.count)")
            lastHighlights = highlights
            let decorations = highlights.compactMap { highlight -> Decoration? in
                guard let locator = try? Self.readiumLocator(from: highlight.locator.json) else { return nil }
                return Decoration(
                    id: highlight.id.uuidString.lowercased(),
                    locator: locator,
                    style: .highlight(tint: Self.color(for: highlight.color))
                )
            }
            navigator.apply(decorations: decorations, in: "highlights")
        }

        private func applyNotes(_ notes: [Note]) {
            guard let navigator else { return }
            guard notes != lastNotes else { return }
            lastNotes = notes
            var seenRanges = Set<String>()
            let decorations = notes.compactMap { note -> Decoration? in
                // One underline per TextRange, regardless of NoteEntry count.
                guard seenRanges.insert(note.locator.canonicalKey).inserted,
                      let locator = try? Self.readiumLocator(from: note.locator.json) else { return nil }
                return Decoration(
                    id: note.id.uuidString.lowercased(),
                    locator: locator,
                    style: .underline(tint: UIColor.tintColor.withAlphaComponent(0.55))
                )
            }
            navigator.apply(decorations: decorations, in: "notes")
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
            case .yellow: UIColor(red: 0.94, green: 0.78, blue: 0.30, alpha: 0.28)
            case .green: .systemGreen.withAlphaComponent(0.35)
            case .blue: .systemBlue.withAlphaComponent(0.30)
            case .pink: .systemPink.withAlphaComponent(0.32)
            }
        }

        private static func chapters(from links: [ReadiumShared.Link], depth: Int = 0) -> [ReaderChapter] {
            links.flatMap { link in
                var result: [ReaderChapter] = []
                let locator = Locator(href: link.url(), mediaType: link.mediaType ?? .xhtml, title: link.title)
                if let data = try? locator.jsonData() {
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
            try Locator(json: JSONValue(jsonData: data), warnings: nil)
        }

        static func anchor(from locator: Locator) throws -> BookLocator {
            try BookLocator(
                json: locator.jsonData(),
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
            preferences: preferences,
            highlights: highlights,
            notes: notes,
            colorScheme: colorScheme,
            jumpTarget: jumpTargetJSON
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
        // Anchors are screen coordinates of the previous layout.
        model.clearTransientAnnotationUI(reason: "rotation")
        flushPosition()
        // The reflow after a rotation can leave scroll mode parked sideways.
        for delay in [0.6, 1.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                ReaderWebViewAccess.clampScrollModeOffset(in: self.view)
            }
        }
    }

    @objc private func flushPosition() { Task { await model.flushPosition() } }
}
