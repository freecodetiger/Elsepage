import ReflectionCore
import Testing

@Test func editingOriginalAfterPolishKeepsEditedUserTextAndDropsStalePolish() {
    var draft = ReflectionTextDraft(originalText: "原始转写")
    draft.applyPolishedText("AI 优化版")

    draft.select(.original)
    draft.updateSelectedText("用户修改后的原话")

    #expect(draft.originalText == "用户修改后的原话")
    #expect(draft.polishedText == nil)
    #expect(draft.selectedVersion == .original)
    #expect(draft.selectedText == "用户修改后的原话")
}

@Test func editingPolishedVersionLeavesOriginalSourceUntouched() {
    var draft = ReflectionTextDraft(originalText: "原始转写")
    draft.applyPolishedText("AI 优化版")

    draft.updateSelectedText("用户修改后的优化版")

    #expect(draft.originalText == "原始转写")
    #expect(draft.polishedText == "用户修改后的优化版")
    #expect(draft.selectedVersion == .polished)
}

@Test func clearingVoiceDraftAllowsFreshTextToBecomeNewSource() {
    var draft = ReflectionTextDraft(originalText: "旧语音")
    draft.applyPolishedText("旧优化")
    draft.clear()
    draft.updateSelectedText("后来手写的新内容")

    #expect(draft.originalText == "后来手写的新内容")
    #expect(draft.polishedText == nil)
    #expect(draft.selectedVersion == .original)
}

@Test func followUpSelectionClearsBothVersions() {
    var draft = ReflectionTextDraft(originalText: "原话")
    draft.applyPolishedText("优化版")

    let sent = draft.takeSelectedTextForSending()

    #expect(sent == "优化版")
    #expect(draft.originalText.isEmpty)
    #expect(draft.polishedText == nil)
    #expect(draft.selectedVersion == .original)
}
