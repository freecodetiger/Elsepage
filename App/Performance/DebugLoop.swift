#if DEBUG
import AgentRuntime
import Foundation
import Observation
import Persistence
import ReaderAgent
import ReadingSessionCore
import ReflectionCore

/// Device-side business adapter. HTTP transport knows no ReadLoop concepts.
@MainActor @Observable
final class DebugLoop {
    static let shared = DebugLoop()
    private(set) var isRunning = false
    private(set) var message = "服务已关闭"
    private var server: DebugHTTPServer?
    private var environment: ReflectionTestEnvironment?
    private var model: SessionReflectionModel?
    private var busy = false
    private var generation = UUID()
    private var runID = UUID().uuidString
    private var events: [[String: Any]] = []
    private var sequence = 0
    private var operations: [String: [String: Any]] = [:]
    private var actionTexts: [String: String] = [:]

    func start() {
        guard server == nil else { return }
        runID = UUID().uuidString
        sequence = 0
        let service = DebugHTTPServer() { [weak self] method, path, body in
            guard let self else { return (503, Data()) }
            return await self.handle(method, path, body)
        }
        service.onStateChange = { [weak self] ready, detail in
            guard let self else { return }
            self.isRunning = ready
            self.message = detail
            if !ready { self.stop(); self.message = detail }
        }
        do {
            try service.start()
            server = service
            isRunning = true
            message = "USB: 127.0.0.1:18765（等待客户端连接）"
        } catch { message = "启动失败：\(error.localizedDescription)" }
    }

    func stop() {
        server?.stop()
        server = nil
        generation = UUID()
        environment = nil
        model = nil
        busy = false
        operations = [:]
        actionTexts = [:]
        events = []
        isRunning = false
        message = "服务已关闭"
    }

    private func emit(_ name: String, action: String) {
        sequence += 1
        events.append(["seq": sequence, "runID": runID, "actionID": action,
                       "name": name, "uptime": ProcessInfo.processInfo.systemUptime])
        if events.count > 1000 { events.removeFirst(events.count - 1000) }
    }

    private func reply(_ code: Int, _ value: [String: Any]) -> (Int, Data) {
        (code, (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data())
    }

    private func snapshot() async throws -> [String: Any] {
        guard let environment else { return ["ready": false, "runID": runID] }
        let capturedRun = runID
        let capturedGeneration = generation
        let capturedSequence = sequence
        let capturedModel = model
        let persisted = try await environment.reflections.allReflections()
        let session = try await environment.sessions.session(id: environment.session.id)
        guard capturedRun == runID, capturedGeneration == generation, capturedSequence == sequence, !busy else {
            throw CancellationError()
        }
        return ["ready": true, "runID": runID,
                "model": ["state": capturedModel.map { String(describing: $0.state) } ?? "missing",
                          "reflectionID": capturedModel?.reflection?.id.description ?? ""],
                "persistence": ["count": persisted.count,
                                "reflectionIDs": persisted.map { $0.id.description },
                                "texts": persisted.map(\.originalText),
                                "discussionCount": session?.agentDiscussionCount ?? 0]]
    }

    private func handle(_ method: String, _ target: String, _ body: Data) async -> (Int, Data) {
        guard let url = URLComponents(string: target) else { return reply(400, ["error": "invalid_target"]) }
        let path = url.path
        if method == "GET", path == "/status" {
            return reply(200, ["protocolVersion": 1, "authentication": "none-usb-loopback", "instrumentationVersion": 7,
                               "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                               "runID": runID, "busy": busy, "environment": "isolated-memory-grdb",
                               "actions": ["reflection.submit"], "scope": "reflection-save; no Agent or UI automation"])
        }
        if method == "GET", path == "/perf" { return reply(200, ["report": Perf.shared.report]) }
        if method == "GET", path == "/events" {
            let raw = url.queryItems?.first(where: { $0.name == "after" })?.value ?? "0"
            guard let after = Int(raw), after >= 0 else { return reply(400, ["error": "invalid_cursor"]) }
            return reply(200, ["runID": runID, "lastSequence": sequence,
                               "firstSequence": events.first?["seq"] as? Int ?? sequence + 1,
                               "events": events.filter { ($0["seq"] as? Int ?? 0) > after }])
        }
        if method == "GET", path == "/snapshot" {
            guard !busy else { return reply(409, ["error": "action_in_progress"]) }
            do { return reply(200, try await snapshot()) }
            catch is CancellationError { return reply(409, ["error": "session_changed"]) }
            catch { return reply(500, ["error": "snapshot_failed"]) }
        }
        if method == "GET", path.hasPrefix("/actions/") {
            guard let operation = operations[String(path.dropFirst("/actions/".count))] else {
                return reply(404, ["error": "unknown_action"])
            }
            return reply(200, operation)
        }
        if method == "POST", path == "/session" {
            guard !busy else { return reply(409, ["error": "action_in_progress"]) }
            busy = true
            let current = generation
            do {
                let fixture = try await ReflectionTestEnvironment.make()
                guard generation == current else { return reply(409, ["error": "stopped"]) }
                environment = fixture
                model = SessionReflectionModel(book: fixture.book, summary: SessionEndingSummary(session: fixture.session),
                    locator: fixture.locator, reflectionRepository: fixture.reflections,
                    readerAgent: ReaderAgent(reflections: fixture.reflections, models: DebugNoProvider()),
                    recordAgentDiscussion: { id in
                        try? await fixture.sessions.incrementAgentDiscussionCount(id: id, by: 1)
                    })
                runID = UUID().uuidString
                operations = [:]
                actionTexts = [:]
                events = []
                sequence = 0
                busy = false
                emit("session.ready", action: "setup")
                return reply(200, ["runID": runID, "ready": true])
            } catch {
                if generation == current { busy = false }
                return reply(500, ["error": "fixture_failed"])
            }
        }
        if method == "POST", path == "/actions" {
            guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let id = object["id"] as? String, UUID(uuidString: id) != nil,
                  object["name"] as? String == "reflection.submit",
                  let text = object["text"] as? String, text.utf8.count <= 16000 else {
                return reply(400, ["error": "invalid_action"])
            }
            if let operation = operations[id] {
                guard actionTexts[id] == text else { return reply(409, ["error": "conflicting_retry"]) }
                return reply(200, operation)
            }
            guard !busy else { return reply(409, ["error": "action_in_progress"]) }
            guard let model, environment != nil else { return reply(409, ["error": "create_session_first"]) }
            guard operations.count < 100 else { return reply(409, ["error": "start_new_session"]) }
            busy = true
            let current = generation
            operations[id] = ["id": id, "status": "running", "runID": runID]
            actionTexts[id] = text
            emit("action.started", action: id)
            Task { @MainActor in
                model.text = text
                let saved = await model.submit()
                guard self.generation == current else { return }
                self.busy = false
                self.emit(saved == nil ? "action.rejected" : "reflection.save.returned", action: id)
                self.operations[id] = ["id": id, "status": saved == nil ? "rejected" : "completed",
                                       "runID": self.runID, "reflectionID": saved?.id.description ?? ""]
            }
            return reply(202, operations[id]!)
        }
        return reply(404, ["error": "unknown_route"])
    }
}

private struct DebugNoProvider: ModelClientFactory {
    func makeClient() async throws -> any ModelClient { throw ModelFailure.invalidConfiguration }
}
#endif
