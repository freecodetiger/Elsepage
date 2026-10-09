#if DEBUG
import AgentRuntime
import AppInfrastructure
import Foundation
import Observation
import Persistence
import ReaderAgent
import ReadingSessionCore
import ReflectionCore
import SpeechCore
import UIKit

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
    private let audioStore = AudioFileStore.live()

    /// Saved voice clips, newest first. Drafts, staging and trash live in
    /// dot-directories, so a plain listing of the root already excludes them.
    private func savedAudioFileNames() -> [String] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: audioStore.rootDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                return left > right
            }
            .map(\.lastPathComponent)
    }

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

    /// The app's own key window, not the whole screen: system-composited layers
    /// (status bar, banners, other apps) are deliberately absent so the captured
    /// frame is exactly the view hierarchy under test.
    private func screenshotWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    }

    private func screenshot(scale: CGFloat) -> [String: Any]? {
        guard let window = screenshotWindow() else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        // Wide-color is the default range on modern devices; pinning sRGB keeps
        // the payload 8-bit instead of 16-bit for a frame nobody color-grades.
        format.preferredRange = .standard
        let bounds = window.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        guard let png = image.pngData() else { return nil }
        return ["scale": Double(scale),
                "width": Double(bounds.width),
                "height": Double(bounds.height),
                "bytes": png.count,
                "png": png.base64EncodedString()]
    }

    private func handle(_ method: String, _ target: String, _ body: Data) async -> (Int, Data) {
        guard let url = URLComponents(string: target) else { return reply(400, ["error": "invalid_target"]) }
        let path = url.path
        if method == "GET", path == "/status" {
            return reply(200, ["protocolVersion": 1, "authentication": "none-usb-loopback", "instrumentationVersion": 8,
                               "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                               "runID": runID, "busy": busy, "environment": "isolated-memory-grdb",
                               "actions": ["reflection.submit", "speech.transcribe"],
                               "scope": "reflection-save, speech-file-transcription, ui-screenshot; no gesture automation"])
        }
        if method == "GET", path == "/perf" { return reply(200, ["report": Perf.shared.report]) }
        if method == "GET", path == "/screenshot" {
            let raw = url.queryItems?.first(where: { $0.name == "scale" })?.value ?? "2"
            guard let requested = Int(raw), (1...3).contains(requested) else {
                return reply(400, ["error": "invalid_scale"])
            }
            guard let shot = screenshot(scale: CGFloat(requested)) else {
                return reply(500, ["error": "screenshot_failed"])
            }
            return reply(200, shot)
        }
        if method == "GET", path == "/audio" {
            return reply(200, ["root": audioStore.rootDirectory.lastPathComponent,
                               "files": savedAudioFileNames()])
        }
        if method == "POST", path == "/transcribe" {
            guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return reply(400, ["error": "invalid_body"])
            }
            let requested = object["file"] as? String
            let strings = (object["contextualStrings"] as? [String]) ?? []
            guard strings.count <= SpeechRecognitionConfiguration.maximumContextualStrings else {
                return reply(400, ["error": "invalid_contextual_strings"])
            }

            // Two ways in. Uploading the clip keeps measurement audio entirely out
            // of the app: it lands in the system temp directory and is removed on
            // the way out, so it can never reach the audio library or the user's
            // recordings. Naming an existing file is for re-running something the
            // app already holds.
            var temporaryURL: URL?
            defer { if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) } }
            let file: String
            let url: URL
            if let encoded = object["audioBase64"] as? String, !encoded.isEmpty {
                guard let data = Data(base64Encoded: encoded), !data.isEmpty else {
                    return reply(400, ["error": "invalid_audio_base64"])
                }
                let temporary = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString.lowercased())
                    .appendingPathExtension("m4a")
                do { try data.write(to: temporary) } catch {
                    return reply(500, ["error": "audio_write_failed"])
                }
                temporaryURL = temporary
                file = object["fileName"] as? String ?? temporary.lastPathComponent
                url = temporary
            } else {
                guard let name = requested.flatMap({ $0.isEmpty ? nil : $0 }) ?? savedAudioFileNames().first else {
                    return reply(404, ["error": "no_audio_file"])
                }
                // The name arrives over the wire. `AudioFileStore.url(for:)` is the
                // store's own safe resolver, so a name that escapes the directory
                // throws here instead of being joined onto a path.
                guard audioStore.fileExists(named: name), let resolved = try? audioStore.url(for: name) else {
                    return reply(404, ["error": "unknown_audio_file"])
                }
                file = name
                url = resolved
            }

            // Omitting the field must leave the app's own default in place, not
            // assert one. Hardcoding `?? false` here silently made every
            // unflagged measurement run report the server configuration while
            // the shipping app had already moved on-device — the measurement
            // would have been of something that no longer ships.
            var configuration = SpeechRecognitionConfiguration(
                localeIdentifier: object["localeIdentifier"] as? String
                    ?? SpeechRecognitionConfiguration.defaultLocaleIdentifier,
                contextualStrings: strings
            )
            if let forced = object["requiresOnDeviceRecognition"] as? Bool {
                configuration.requiresOnDeviceRecognition = forced
            }
            emit("transcribe.started", action: "speech.transcribe")
            do {
                let transcript = try await FileTranscriptionService().transcribe(url, configuration: configuration)
                emit("transcribe.completed", action: "speech.transcribe")
                return reply(200, [
                    "file": file,
                    "transcript": transcript,
                    "characterCount": transcript.count,
                    "localeIdentifier": configuration.localeIdentifier,
                    "contextualStrings": configuration.contextualStrings,
                    "requiresOnDeviceRecognition": configuration.requiresOnDeviceRecognition
                ])
            } catch {
                emit("transcribe.failed", action: "speech.transcribe")
                return reply(500, ["error": "transcription_failed", "detail": error.localizedDescription])
            }
        }
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
