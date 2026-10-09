import Speech
import SpeechCore
import Testing

/// Pins the shipping defaults. A change here changes how every recording is
/// transcribed, so it should be a deliberate edit with a measurement behind it,
/// not a drive-by tweak — `requiresOnDeviceRecognition` was flipped to `true`
/// on exactly that basis.
@Test func defaultsAreTheOnesTheProductCommittedTo() {
    let configuration = SpeechRecognitionConfiguration()

    #expect(configuration.localeIdentifier == "zh-CN")
    #expect(configuration.contextualStrings.isEmpty)
    #expect(configuration.taskHint == .unspecified)
    #expect(configuration.addsPunctuation)
    #expect(configuration.shouldReportPartialResults)
    // On deliberately: recognition then never leaves the device. The measured
    // accuracy cost was nil on the five-clip sample, and without this the
    // contextual strings become an undisclosed outbound channel.
    #expect(configuration.requiresOnDeviceRecognition)
}

@Test func availabilityReportsUnavailableWhenNoRecognizerCanBeBuilt() {
    // The one branch of the rule that is testable without a device: the other
    // depends on which models the host has installed.
    #expect(SpeechRecognitionAvailability.evaluate(
        recognizer: nil,
        configuration: SpeechRecognitionConfiguration()
    ) == .unavailable(localeIdentifier: "zh-CN"))
}

@Test func theAvailabilityMessageCarriesTheLocaleOnlyWhenItIsActionable() {
    #expect(SpeechRecognitionAvailability.available.message == nil)
    // The user can install this one, so it names the language.
    #expect(SpeechRecognitionAvailability.onDeviceModelMissing(localeIdentifier: "zh-CN")
        .message?.contains("zh-CN") == true)
    // Nothing the user can do about a missing recognizer; naming the language
    // would just add noise, so this must be the plain copy.
    #expect(SpeechRecognitionAvailability.unavailable(localeIdentifier: "zh-CN").message
        == SpeechProviderError.recognitionUnavailable.errorDescription)
}

private func assistantError(code: Int) -> NSError {
    NSError(domain: SpeechProviderError.assistantErrorDomain, code: code)
}

@Test func aMissingOnDeviceAssetIsReportedAsSomethingTheUserCanFix() {
    // 1101 in the dictation domain is how a missing on-device asset actually
    // arrives — opaque on its own, and the case the pre-flight check can miss.
    let classified = SpeechProviderError.from(
        assistantError(code: SpeechProviderError.missingOnDeviceAssetCode),
        configuration: SpeechRecognitionConfiguration()
    )
    #expect(classified == .onDeviceModelUnavailable("zh-CN"))
}

@Test func theSameErrorBlamesTheModelOnlyWhenOnDeviceWasRequired() {
    // With a server path available, the model is not the problem, and sending
    // the user to install one would send them to fix the wrong thing.
    let classified = SpeechProviderError.from(
        assistantError(code: SpeechProviderError.missingOnDeviceAssetCode),
        configuration: SpeechRecognitionConfiguration(requiresOnDeviceRecognition: false)
    )
    if case .recordingCouldNotStart = classified {} else {
        Issue.record("Expected the raw failure, got \(classified)")
    }
}

@Test func unrelatedFailuresAreNotDressedUpAsModelProblems() {
    // Same code, different domain.
    let foreign = NSError(domain: "kAFAssistantErrorDomain.somethingElse",
                          code: SpeechProviderError.missingOnDeviceAssetCode)
    if case .recordingCouldNotStart = SpeechProviderError.from(foreign, configuration: .init()) {} else {
        Issue.record("A foreign domain must not be read as a missing model")
    }
    // Same domain, different code.
    if case .recordingCouldNotStart = SpeechProviderError.from(
        assistantError(code: 1107), configuration: .init()
    ) {} else {
        Issue.record("Only the missing-asset code means a missing asset")
    }
}

@Test func aMissingOnDeviceModelSaysWhatToDoAndDoesNotOfferToUpload() {
    let message = SpeechProviderError.onDeviceModelUnavailable("zh-CN").errorDescription ?? ""

    // The locale, so the user knows which model is missing.
    #expect(message.contains("zh-CN"))
    // The actionable path. iOS fetches on-device models in the background, so
    // without this the user would have no idea there is anything to wait for.
    #expect(message.contains("下载"))
    #expect(message.contains("输入文字"))
    // The whole point of on-device: the user is told the audio stays put,
    // rather than being offered a fallback that would upload it.
    #expect(message.contains("音频不会上传"))
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
