import AVFAudio
import AppInfrastructure
import Foundation
import Observation
import SpeechCore
import SwiftUI
import UIKit

@MainActor @Observable
final class VoiceReflectionRecorder {
    private let provider: any LiveTranscriptionProvider
    private let audioStore: AudioFileStore
    private var streamTask: Task<Void, Never>?
    private var stopFallbackTask: Task<Void, Never>?
    private var pendingStartID: UUID?

    private(set) var state = VoiceReflectionState()
    private(set) var draftAudioURLs: [URL] = []

    init(
        provider: (any LiveTranscriptionProvider)? = nil,
        audioStore: AudioFileStore = .live()
    ) {
        self.provider = provider ?? SystemSpeechTranscriptionProvider()
        self.audioStore = audioStore
    }

    var latestTranscript: String { state.transcript }
    var isRecording: Bool { state.phase == .recording || state.phase == .stopping }
    var saveAudio: Bool {
        get { state.saveAudio }
        set {
            state.saveAudio = newValue
            if !newValue, !isRecording {
                discardAudioDrafts()
            }
        }
    }

    func start() async {
        guard state.phase == .idle || state.phase == .cancelled || state.phase == .failed || state.phase == .transcriptReady else { return }
        stopFallbackTask?.cancel()
        stopFallbackTask = nil
        let startID = UUID()
        pendingStartID = startID
        defer {
            if pendingStartID == startID { pendingStartID = nil }
        }
        state.apply(.requestRecording)
        let permission = provider.authorizationStatus == .notDetermined
            ? await provider.requestAuthorization()
            : provider.authorizationStatus
        guard pendingStartID == startID, state.phase == .requestingPermission else {
            provider.cancel()
            return
        }
        state.apply(.permissionResolved(permission))
        guard permission == .authorized else { return }
        guard provider.isAvailable else {
            state.apply(.failed(SpeechProviderError.recognitionUnavailable.localizedDescription))
            return
        }

        let previousAudioFileName = state.audioFileName
        var createdDraft: URL?
        do {
            if state.saveAudio {
                let url = try audioStore.newDraftURL(fileExtension: provider.preferredAudioFileExtension)
                createdDraft = url
                draftAudioURLs.append(url)
                try provider.prepareAudioRecording(at: url)
                state.audioFileName = url.lastPathComponent
            } else {
                discardAudioDrafts()
                try provider.prepareAudioRecording(at: nil)
            }
            let stream = try provider.start(localeIdentifier: nil)
            state.apply(.recordingStarted)
            streamTask = Task { [weak self] in
                do {
                    for try await event in stream {
                        guard !Task.isCancelled else { return }
                        self?.state.apply(.transcription(event))
                    }
                    self?.stopFallbackTask?.cancel()
                    self?.stopFallbackTask = nil
                    if self?.state.phase == .stopping, self?.state.hasTranscript == true {
                        self?.state.apply(.transcription(.final(self?.state.transcript ?? "")))
                    }
                } catch is CancellationError {
                    // Explicit cancellation is a normal state and is applied by cancel().
                } catch {
                    self?.state.apply(.failed(error.localizedDescription))
                }
            }
        } catch {
            if let createdDraft {
                audioStore.discardDraft(at: createdDraft)
                draftAudioURLs.removeAll { $0 == createdDraft }
                state.audioFileName = draftAudioURLs.last?.lastPathComponent ?? previousAudioFileName
            }
            state.apply(.failed(error.localizedDescription))
        }
    }

    func stop() {
        guard state.phase == .recording else { return }
        state.apply(.stopRequested)
        provider.stop()
        let transcript = state.transcript
        stopFallbackTask?.cancel()
        stopFallbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.state.phase == .stopping else { return }
            self.state.apply(.transcription(.final(transcript)))
            self.stopFallbackTask = nil
        }
    }

    func cancel() {
        pendingStartID = nil
        stopFallbackTask?.cancel()
        stopFallbackTask = nil
        streamTask?.cancel()
        streamTask = nil
        provider.cancel()
        state.apply(.cancelled)
        discardAudioDrafts()
    }

    /// Explicitly drops every unsubmitted take when the user turns audio saving
    /// off or abandons the draft.
    func discardAudioDrafts() {
        for url in draftAudioURLs {
            audioStore.discardDraft(at: url)
        }
        draftAudioURLs.removeAll()
        state.audioFileName = nil
    }
}

enum VoiceReflectionControlStyle: Equatable {
    case fullDraft
    case compactComposer
}

struct VoiceReflectionControls: View {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var editableText: String
    @Binding var audioDraftURLs: [URL]
    /// Conversation follow-ups use speech as an input method only. They do not
    /// expose or persist a message-level audio file.
    var allowsAudioSaving = true
    var style: VoiceReflectionControlStyle = .fullDraft
    var canPolish = false
    var onPolish: (() async -> Void)? = nil
    /// Fired once per recording completion so the model can auto-optimize the
    /// transcript (说得乱没关系,AI 把表达理顺)。The model's own guard makes it
    /// a no-op after the first per-draft optimization.
    var onAutoPolish: (() async -> Void)? = nil
    var onRecordingStart: () -> Void = {}
    var onVoiceTranscript: () -> Void = {}
    var onRecordingStateChange: (Bool) -> Void = { _ in }
    var onFailureMessageChange: (String?) -> Void = { _ in }
    @State private var recorder = VoiceReflectionRecorder()
    @State private var textBeforeRecording = ""
    @State private var pressTask: Task<Void, Never>?
    @State private var isHoldingLongPress = false
    @State private var isPolishing = false
    /// A11Y-01: the mic glyph follows Dynamic Type; the disc keeps a fixed,
    /// recognizable size.
    @ScaledMetric(relativeTo: .body) private var fullIconSize: CGFloat = 30
    @ScaledMetric(relativeTo: .body) private var compactIconSize: CGFloat = 17

    var body: some View {
        VStack(spacing: ElsepageTheme.Spacing.medium) {
            if style == .fullDraft {
                statusLine
            }
            micButton
            if style == .fullDraft, allowsAudioSaving || canPolish {
                HStack(spacing: 12) {
                    if allowsAudioSaving {
                        Toggle("保存音频", isOn: Binding(
                            get: { recorder.saveAudio },
                            set: { recorder.saveAudio = $0 }
                        ))
                        .font(.caption)
                        .toggleStyle(.switch)
                        .accessibilityLabel("保存这段音频")
                    }
                    Spacer()
                    if canPolish, !editableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            Task {
                                isPolishing = true
                                await onPolish?()
                                isPolishing = false
                            }
                        } label: {
                            if isPolishing {
                                ProgressView().controlSize(.small)
                                    // A11Y-03: keep the hit target stable while
                                    // the spinner replaces the label.
                                    .frame(minHeight: 44)
                            } else {
                                Label("优化", systemImage: "wand.and.stars")
                                    .frame(minHeight: 44)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isPolishing)
                    }
                }
                .disabled(
                    recorder.state.phase == .requestingPermission
                        || recorder.state.phase == .stopping
                        || recorder.isRecording
                )
            }
        }
        .frame(maxWidth: style == .fullDraft ? .infinity : nil)
        .onChange(of: recorder.latestTranscript) { _, transcript in
            let prefix = textBeforeRecording.trimmingCharacters(in: .whitespacesAndNewlines)
            editableText = transcript.isEmpty ? textBeforeRecording : [prefix, transcript].filter { !$0.isEmpty }.joined(separator: "\n\n")
            if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onVoiceTranscript()
            }
        }
        .onChange(of: recorder.draftAudioURLs) { _, urls in
            audioDraftURLs = allowsAudioSaving ? urls : []
        }
        .onChange(of: recorder.state.failureMessage) { _, message in
            onFailureMessageChange(message)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, recorder.isRecording {
                recorder.stop()
            }
        }
        .onChange(of: recorder.state.phase) { _, phase in
            onRecordingStateChange(
                phase == .requestingPermission || phase == .recording || phase == .stopping
            )
            if phase == .transcriptReady {
                Task { await onAutoPolish?() }
            }
        }
        .onAppear {
            if !allowsAudioSaving {
                recorder.saveAudio = false
                audioDraftURLs = []
            }
        }
        .onDisappear {
            recorder.cancel()
            onRecordingStateChange(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("语音感想")
    }

    @ViewBuilder private var statusLine: some View {
        if recorder.state.phase == .requestingPermission {
            ProgressView("正在请求权限…")
                .font(.footnote)
        } else if let failure = recorder.state.failureMessage {
            Text(failure).font(.footnote).foregroundStyle(.secondary)
        } else if recorder.isRecording {
            Text("正在转写…点击或松手结束")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if recorder.state.hasTranscript {
            Text("已转写，可继续编辑或续录")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Prominent bottom-center mic button. Both default interactions work:
    /// tap to start / tap to stop, and hold to start / release to stop.
    private var micButton: some View {
        // A11Y-03: both variants keep the 44pt minimum tap target.
        let size: CGFloat = style == .compactComposer ? 44 : 76
        let iconSize: CGFloat = style == .compactComposer ? compactIconSize : fullIconSize
        return ZStack {
            Circle()
                .fill(recorder.isRecording ? Color.red.opacity(0.12) : Color.elsepageAccent.opacity(0.10))
                .frame(width: size, height: size)
                .overlay(
                    Circle().strokeBorder(recorder.isRecording ? Color.red : Color.elsepageAccent, lineWidth: 2)
                )
            Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(recorder.isRecording ? Color.red : Color.elsepageAccent)
                .accessibilityHidden(true)
        }
        .scaleEffect(recorder.isRecording ? 1.1 : 1.0)
        .animation(.snappy(duration: 0.2), value: recorder.isRecording)
        .contentShape(Circle())
        // A11Y-02: the mic drives a gesture, not a Button, so the traits and
        // state must be explicit for VoiceOver.
        .accessibilityLabel(recorder.isRecording ? "结束录音" : "开始语音输入")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("轻点开始或结束录音，也可以长按说话、松手结束")
        .accessibilityValue(recorder.isRecording ? "正在转写" : "")
        .accessibilityRespondsToUserInteraction(true)
        .gesture(recordingGesture)
    }

    private var recordingGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // A deliberate scroll that starts on the button cancels the pending press.
                guard abs(value.translation.width) < 20, abs(value.translation.height) < 20 else {
                    pressTask?.cancel()
                    pressTask = nil
                    return
                }
                guard pressTask == nil else { return }
                pressTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    isHoldingLongPress = true
                    haptic()
                    if !recorder.isRecording {
                        beginRecording()
                    }
                }
            }
            .onEnded { _ in
                let wasLongPress = isHoldingLongPress
                pressTask?.cancel()
                pressTask = nil
                isHoldingLongPress = false
                if wasLongPress {
                    if recorder.isRecording { recorder.stop() }
                    haptic()
                } else if recorder.isRecording {
                    recorder.stop()
                } else {
                    beginRecording()
                }
            }
    }

    private func beginRecording() {
        onRecordingStart()
        if !allowsAudioSaving {
            recorder.saveAudio = false
            recorder.discardAudioDrafts()
            audioDraftURLs = []
        }
        textBeforeRecording = editableText
        Task { await recorder.start() }
    }

    private func haptic() {
        Haptics.recordingPress()
    }
}


/// Compact playback surface for an audio file that belongs to a saved
/// Reflection. Missing files degrade to text without interrupting the thread.
struct ReflectionAudioAttachment: View {
    let fileName: String
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.xSmall) {
            HStack(spacing: ElsepageTheme.Spacing.small) {
                Button {
                    togglePlayback()
                } label: {
                    Label(isPlaying ? "停止" : "播放录音", systemImage: isPlaying ? "stop.fill" : "play.fill")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(errorMessage != nil)

                Text("原始录音")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            player?.stop()
            player = nil
            isPlaying = false
        }
    }

    private func togglePlayback() {
        if isPlaying {
            player?.stop()
            player = nil
            isPlaying = false
            return
        }
        do {
            let url = try AudioFileStore.live().url(for: fileName)
            guard FileManager.default.fileExists(atPath: url.path) else {
                errorMessage = "录音文件暂不可用。"
                return
            }
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            self.player = player
            isPlaying = true
            errorMessage = nil
        } catch {
            errorMessage = "录音暂时无法播放。"
        }
    }
}
