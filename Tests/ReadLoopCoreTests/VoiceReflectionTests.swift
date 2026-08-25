import LibraryCore
import Persistence
import ReaderCore
import ReflectionCore
import SpeechCore
import Testing

@Test func voiceStateRequiresPermissionAndProducesAnEditableDraft() {
    var state = VoiceReflectionState()
    state.apply(.requestRecording)
    #expect(state.phase == .requestingPermission)
    state.apply(.permissionResolved(.authorized))
    state.apply(.recordingStarted)
    state.apply(.transcription(.partial("还没有说完")))
    #expect(state.phase == .recording)
    #expect(state.transcript == "还没有说完")

    state.apply(.stopRequested)
    state.apply(.transcription(.final("这是用户确认前的转写草稿")))
    #expect(state.phase == .transcriptReady)
    #expect(state.hasTranscript)
}

@Test func deniedRestrictedUnavailableAndEmptyRecognitionAreRecoverableStates() {
    var denied = VoiceReflectionState()
    denied.apply(.requestRecording)
    denied.apply(.permissionResolved(.denied))
    #expect(denied.phase == .failed)
    #expect(denied.failureMessage != nil)
    #expect(!denied.hasTranscript)

    var restricted = VoiceReflectionState()
    restricted.apply(.requestRecording)
    restricted.apply(.permissionResolved(.restricted))
    #expect(restricted.phase == .failed)

    var unavailable = VoiceReflectionState()
    unavailable.apply(.requestRecording)
    unavailable.apply(.failed("unavailable"))
    #expect(unavailable.phase == .failed)

    var empty = VoiceReflectionState()
    empty.apply(.requestRecording)
    empty.apply(.permissionResolved(.authorized))
    empty.apply(.recordingStarted)
    empty.apply(.transcription(.final("  \n")))
    #expect(empty.phase == .idle)
    #expect(!empty.hasTranscript)
}

@Test func cancellationDiscardsUnsavedTranscriptAndRecognitionFailurePreservesPartialDraft() {
    var cancelled = VoiceReflectionState()
    cancelled.apply(.requestRecording)
    cancelled.apply(.permissionResolved(.authorized))
    cancelled.apply(.recordingStarted)
    cancelled.apply(.transcription(.partial("不要保存")))
    cancelled.apply(.cancelled)
    #expect(cancelled.phase == .cancelled)
    #expect(cancelled.transcript.isEmpty)

    var failed = VoiceReflectionState()
    failed.apply(.requestRecording)
    failed.apply(.permissionResolved(.authorized))
    failed.apply(.recordingStarted)
    failed.apply(.transcription(.partial("已经说下来的部分")))
    failed.apply(.failed("network-independent recognizer failure"))
    #expect(failed.phase == .failed)
    #expect(failed.transcript == "已经说下来的部分")
}

@Test func editedVoiceTranscriptIsSavedAsUserSourceTruthAndRetriesIdempotently() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book()
    try await GRDBBookRepository(database: database).insert(book)
    let locator = try TestFixtures.realisticLocator()
    let repository = GRDBReflectionRepository(database: database)
    let service = VoiceReflectionSubmissionService(repository: repository)
    let draft = VoiceReflectionDraft(bookID: book.id, sessionID: nil, locator: locator, editedTranscript: "用户编辑后的最终文字")

    let saved = try await service.submit(draft)
    let retried = try await service.submit(draft)
    #expect(saved.id == retried.id)
    #expect(saved.originalText == retried.originalText)
    #expect(saved.inputKind == retried.inputKind)
    #expect(saved.originalText == draft.editedTranscript)
    #expect(saved.inputKind == .voiceTranscript)
    #expect(saved.audioFileName == nil)
    #expect(try await repository.messages(for: saved.id).isEmpty)
}

@Test func emptyOrConflictingVoiceTranscriptCannotOverwriteSourceTruth() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book()
    try await GRDBBookRepository(database: database).insert(book)
    let locator = try TestFixtures.realisticLocator()
    let service = VoiceReflectionSubmissionService(repository: GRDBReflectionRepository(database: database))
    let id = ReflectionID()

    await #expect(throws: VoiceReflectionSubmissionError.emptyTranscript) {
        try await service.submit(.init(id: id, bookID: book.id, sessionID: nil, locator: locator, editedTranscript: " \n "))
    }
    _ = try await service.submit(.init(id: id, bookID: book.id, sessionID: nil, locator: locator, editedTranscript: "原始语音文字"))
    await #expect(throws: VoiceReflectionSubmissionError.conflictingRetry) {
        try await service.submit(.init(id: id, bookID: book.id, sessionID: nil, locator: locator, editedTranscript: "试图覆盖"))
    }
}

@Test func voiceStateExposesAudioSaveToggleAndFileName() {
    var state = VoiceReflectionState()
    #expect(state.saveAudio == false)
    #expect(state.audioFileName == nil)

    state.saveAudio = true
    state.audioFileName = "abc-123.caf"
    #expect(state.saveAudio)
    #expect(state.audioFileName == "abc-123.caf")

    state.audioFileName = nil
    #expect(state.audioFileName == nil)
}

@Test func voiceDraftCarriesAudioFileNameAndLinkedHighlights() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book()
    try await GRDBBookRepository(database: database).insert(book)
    let reading = GRDBReadingRepository(database: database)
    let highlight = Highlight(bookID: book.id, locator: try TestFixtures.realisticLocator())
    try await reading.save(highlight: highlight)
    let locator = try TestFixtures.realisticLocator()
    let repository = GRDBReflectionRepository(database: database)
    let service = VoiceReflectionSubmissionService(repository: repository)

    let saved = try await service.submit(.init(
        bookID: book.id, sessionID: nil, locator: locator,
        editedTranscript: "语音转写", audioFileName: "abc-123.caf", linkedHighlightIDs: [highlight.id]
    ))
    #expect(saved.inputKind == .voiceTranscript)
    #expect(saved.audioFileName == "abc-123.caf")
    #expect(try await repository.linkedHighlightIDs(for: saved.id) == [highlight.id])
}

@Test func voiceDraftWithAudioFileNameRetriesIdempotently() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book()
    try await GRDBBookRepository(database: database).insert(book)
    let locator = try TestFixtures.realisticLocator()
    let service = VoiceReflectionSubmissionService(repository: GRDBReflectionRepository(database: database))
    let draft = VoiceReflectionDraft(bookID: book.id, sessionID: nil, locator: locator, editedTranscript: "保存音频的语音", audioFileName: "voice-1.caf")

    let first = try await service.submit(draft)
    let retried = try await service.submit(draft)
    #expect(first.id == retried.id)
    #expect(first.audioFileName == "voice-1.caf")
    #expect(retried.audioFileName == "voice-1.caf")
}
