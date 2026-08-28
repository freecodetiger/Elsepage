import AppInfrastructure
import LibraryCore
import Persistence
import RetrievalCore
import XCTest
@testable import ReadLoop

@MainActor
final class ReadiumPublicationIntegrationTests: XCTestCase {
    private var fixture: URL {
        try! XCTUnwrap(Bundle(for: Self.self).url(forResource: "minimal", withExtension: "epub"))
    }

    func testReadiumOpensRealEPUBAndExtractsMetadata() async throws {
        let publication = try await ReadiumServices().open(fixture, allowUserInteraction: false)
        XCTAssertFalse(publication.isRestricted)
        XCTAssertEqual(publication.metadata.title, "ReadLoop Foundation Fixture")
        XCTAssertEqual(publication.metadata.authors.first?.name, "ReadLoop Contributors")
        XCTAssertEqual(publication.readingOrder.count, 1)
    }

    func testReadiumMetadataFeedsFingerprintAndIdempotentImport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = try AppDatabase.inMemory()
        let repository = GRDBBookRepository(database: database)
        let store = try BookFileStore(directory: root.appendingPathComponent("Books", isDirectory: true))
        let readium = ReadiumServices()
        let metadata = try await ReadiumMetadataReader(readium: readium).metadata(at: fixture)
        let importer = BookImporter(repository: repository, files: store)

        guard case .imported(let book) = try await importer.importEPUB(at: fixture, metadata: metadata),
              case .duplicate(let duplicate) = try await importer.importEPUB(at: fixture, metadata: metadata) else {
            XCTFail("Expected imported then duplicate"); return
        }
        XCTAssertEqual(book.id, duplicate.id)
        XCTAssertEqual(book.title, "ReadLoop Foundation Fixture")
        XCTAssertEqual(book.author, "ReadLoop Contributors")
    }

    func testReadiumContentBuildsNavigableLocalFTSIndex() async throws {
        let database = try AppDatabase.inMemory()
        let books = GRDBBookRepository(database: database)
        let index = GRDBBookIndexRepository(database: database)
        let book = Book(fingerprint: .init(rawValue: "readium-index"), title: "Fixture", fileName: "fixture.epub", fileSize: 1)
        try await books.insert(book)
        let publication = try await ReadiumServices().open(fixture, allowUserInteraction: false)
        let extractor = ReadiumBookContentExtractor(bookID: book.id, publication: publication)
        try await BookIndexPipeline(extractor: extractor, repository: index, chunker: .init(targetCharacters: 120, maximumCharacters: 240)).index(bookID: book.id)

        let chunks = try await index.chunks(for: book.id, version: BookIndexPipeline.currentVersion)
        XCTAssertFalse(chunks.isEmpty)
        XCTAssertTrue(chunks.allSatisfy { !$0.startLocator.json.isEmpty && !$0.resourceHref.isEmpty })
        let results = try await index.lexicalSearch(bookID: book.id, query: "reader begins", boundary: .init(resourceOrdinal: .max), limit: 5)
        XCTAssertFalse(results.isEmpty)
    }

    func testReflectionEditorKeepsThirdPartyKeyboardClearUntilEditingEnds() {
        var synchronization = ReflectionTextSynchronization(initialText: "不会复活的旧文字")
        synchronization.editingBegan()

        // Some third-party keyboards mutate UITextView directly without a
        // textDidChange callback. A SwiftUI refresh must not restore the model.
        XCTAssertNil(synchronization.modelTextToApply(
            modelText: "不会复活的旧文字",
            uiText: "",
            hasMarkedText: false
        ))
        XCTAssertEqual(synchronization.editingEnded(uiText: ""), "")
    }

    func testReflectionEditorStillAppliesAnExternalClearAfterSend() {
        var synchronization = ReflectionTextSynchronization(initialText: "已经发送的文字")
        synchronization.editingBegan()
        synchronization.userTextDidChange("已经发送的文字", hasMarkedText: false)

        XCTAssertEqual(synchronization.modelTextToApply(
            modelText: "",
            uiText: "已经发送的文字",
            hasMarkedText: false
        ), "")
    }

    func testReflectionComposerUsesTheEditorsFullNaturalHeight() {
        XCTAssertEqual(ReflectionComposerPolicy.naturalHeight(20), 44)
        XCTAssertEqual(ReflectionComposerPolicy.naturalHeight(82), 82)
        XCTAssertEqual(ReflectionComposerPolicy.naturalHeight(180), 180)
    }

    func testReflectionComposerOnlySendsASettledNonemptyDraft() {
        XCTAssertTrue(ReflectionComposerPolicy.canSend(
            text: "继续说", isRecording: false, isResponding: false, hasMarkedText: false
        ))
        XCTAssertFalse(ReflectionComposerPolicy.canSend(
            text: "  \n", isRecording: false, isResponding: false, hasMarkedText: false
        ))
        XCTAssertFalse(ReflectionComposerPolicy.canSend(
            text: "还没说完", isRecording: true, isResponding: false, hasMarkedText: false
        ))
        XCTAssertFalse(ReflectionComposerPolicy.canSend(
            text: "等待回应", isRecording: false, isResponding: true, hasMarkedText: false
        ))
        XCTAssertFalse(ReflectionComposerPolicy.canSend(
            text: "nihao", isRecording: false, isResponding: false, hasMarkedText: true
        ))
    }

    func testReflectionPlaceholderFollowsUIKitVisibleInputIncludingMarkedText() {
        XCTAssertTrue(ReflectionTextPresentationPolicy.showsPlaceholder(text: "", hasMarkedText: false))
        XCTAssertFalse(ReflectionTextPresentationPolicy.showsPlaceholder(text: "", hasMarkedText: true))
        XCTAssertFalse(ReflectionTextPresentationPolicy.showsPlaceholder(text: "你好", hasMarkedText: false))
    }

    func testReflectionDraftKeepsOriginalWhenPolishedVersionIsSelected() {
        var draft = ReflectionDraft(originalText: "这是我的原话")

        draft.applyPolishedText("这是整理后的表达")

        XCTAssertEqual(draft.originalText, "这是我的原话")
        XCTAssertEqual(draft.selectedText, "这是整理后的表达")
        XCTAssertEqual(draft.selectedVersion, .polished)
    }

    func testEditingOriginalInvalidatesAnExistingPolishedVersion() {
        var draft = ReflectionDraft(originalText: "原话", polishedText: "整理版", selectedVersion: .original)

        draft.updateOriginalText("原话，再补充一点")

        XCTAssertEqual(draft.originalText, "原话，再补充一点")
        XCTAssertNil(draft.polishedText)
        XCTAssertEqual(draft.selectedVersion, .original)
    }

    func testReflectionDraftCanBeRestoredAfterClearing() {
        var draft = ReflectionDraft(originalText: "原话", polishedText: "整理版", selectedVersion: .polished)
        let snapshot = draft

        draft.clear()
        XCTAssertFalse(draft.canSend)

        draft = snapshot
        XCTAssertEqual(draft.selectedText, "整理版")
        XCTAssertEqual(draft.originalText, "原话")
    }

    func testTakingAReflectionForSendingImmediatelyClearsOnlyThatDraft() {
        var draft = ReflectionDraft(originalText: "  已经说完的这一段  ")

        XCTAssertEqual(draft.takeSelectedTextForSending(), "已经说完的这一段")
        XCTAssertFalse(draft.canSend)

        draft.updateOriginalText("Agent 回复期间继续写的新内容")
        XCTAssertEqual(draft.selectedText, "Agent 回复期间继续写的新内容")
    }
}
