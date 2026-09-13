import ReflectionCore
import Testing

@Test func streamingResponseBufferCoalescesDeltasUntilFlush() {
    var buffer = StreamingResponseBuffer()
    buffer.begin()
    buffer.append("第一")
    buffer.append("段")

    #expect(buffer.visibleText.isEmpty)
    #expect(buffer.hasPendingText)

    let rendered = buffer.flush { $0 }
    #expect(rendered == "第一段")
    #expect(buffer.visibleText == "第一段")
    #expect(!buffer.hasPendingText)

    buffer.append("，第二批")
    _ = buffer.flush { $0 }
    #expect(buffer.visibleText == "第一段，第二批")
}

@Test func streamingResponseBufferAppliesDisplayFilterOncePerBatch() {
    var buffer = StreamingResponseBuffer()
    buffer.begin()
    buffer.append("可见内容")
    buffer.append("---CITATIONS---\n隐藏内容")

    var transformCalls = 0
    let rendered = buffer.flush {
        transformCalls += 1
        return String($0.split(separator: "---CITATIONS---", maxSplits: 1).first ?? "")
    }

    #expect(rendered == "可见内容")
    #expect(transformCalls == 1)
}

@Test func streamingResponseBufferCompletesAndDropsStaleState() {
    var buffer = StreamingResponseBuffer()
    buffer.begin()
    buffer.append("旧回应")
    _ = buffer.flush { $0 }
    buffer.append("未显示")
    buffer.complete()

    #expect(buffer.visibleText.isEmpty)
    #expect(!buffer.hasPendingText)
}
