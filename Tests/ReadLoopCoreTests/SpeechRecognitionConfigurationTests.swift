import Speech
import SpeechCore
import Testing

/// These defaults are the pre-existing recognition behavior, written down. A
/// change here changes how every recording is transcribed, so it should be a
/// deliberate edit with a measurement behind it, not a drive-by tweak.
@Test func defaultsMatchThePreviouslyHardcodedBehavior() {
    let configuration = SpeechRecognitionConfiguration()

    #expect(configuration.localeIdentifier == "zh-CN")
    #expect(configuration.contextualStrings.isEmpty)
    #expect(configuration.taskHint == .unspecified)
    #expect(configuration.addsPunctuation)
    #expect(configuration.shouldReportPartialResults)
    // Off deliberately: the on-device Chinese model is smaller, so enabling this
    // trades accuracy for privacy.
    #expect(!configuration.requiresOnDeviceRecognition)
}

@Test func contextualStringsAreTrimmedDeduplicatedAndOrdered() {
    let configuration = SpeechRecognitionConfiguration(contextualStrings: [
        "  置身事内  ",
        "",
        "   ",
        "Man's Search for Meaning",
        "置身事内",
        "MAN'S SEARCH FOR MEANING",
        "兰小欢"
    ])

    // Order is the caller's ranking, so it survives; duplicates collapse
    // case-insensitively because biasing does not distinguish case.
    #expect(configuration.contextualStrings == [
        "置身事内",
        "Man's Search for Meaning",
        "兰小欢"
    ])
}

@Test func aPassageHandedInByMistakeIsRejectedRatherThanDilutingTheBias() {
    let passage = String(repeating: "这是一整段正文，", count: 20)
    let configuration = SpeechRecognitionConfiguration(contextualStrings: [
        passage,
        "页外",
        String(repeating: "字", count: SpeechRecognitionConfiguration.maximumContextualStringLength)
    ])

    #expect(configuration.contextualStrings.count == 2)
    #expect(!configuration.contextualStrings.contains(passage))
}

@Test func theListIsCappedSoAnOversizedVocabularyCannotCrowdOutEveryEntry() {
    let many = (0..<(SpeechRecognitionConfiguration.maximumContextualStrings + 25)).map { "术语\($0)" }
    let configuration = SpeechRecognitionConfiguration(contextualStrings: many)

    #expect(configuration.contextualStrings.count == SpeechRecognitionConfiguration.maximumContextualStrings)
    // The cap keeps the caller's highest-ranked entries.
    #expect(configuration.contextualStrings.first == "术语0")
}

/// The settings only matter if they actually reach the request, and nothing on
/// the live path can be asserted without a device.
@Test func everySettingLandsOnTheRequest() {
    let configuration = SpeechRecognitionConfiguration(
        localeIdentifier: "en-US",
        contextualStrings: ["置身事内", "兰小欢"],
        taskHint: .dictation,
        addsPunctuation: false,
        shouldReportPartialResults: false,
        requiresOnDeviceRecognition: true
    )
    let request = SFSpeechAudioBufferRecognitionRequest()
    configuration.apply(to: request)

    #expect(request.taskHint == .dictation)
    #expect(!request.addsPunctuation)
    #expect(!request.shouldReportPartialResults)
    #expect(request.requiresOnDeviceRecognition)
    #expect(request.contextualStrings == ["置身事内", "兰小欢"])
}
