import Foundation
import AVFoundation
@preconcurrency import Speech

/// A voice backend that can speak text and optionally transcribe audio.
/// hf.app ships with an Apple-native implementation; 8b-native Rust sidecars
/// (liquid-rust for STT, kokoro-tiny for TTS) implement this same protocol.
@MainActor
protocol VoiceBackend: Sendable {
    /// Whether this backend is available (engine initialized, no errors).
    var available: Bool { get }
    /// Human-readable name for the UI ("Apple", "kokoro-tiny", etc.).
    var name: String { get }

    /// Speak `text` aloud. Interrupts any current speech.
    func speak(_ text: String) async
    /// Stop speech in progress.
    func stop() async

    /// Begin dictation (microphone → text). Yields partial transcripts via
    /// the `transcript` binding until `stopDictation()` is called.
    func startDictation() async
    /// Stop dictation and return the final transcript.
    func stopDictation() async -> String
    /// Whether dictation is currently active.
    var isDictating: Bool { get }
}

// MARK: - Apple-native backend

/// Apple AVSpeechSynthesizer + SFSpeechRecognizer backend.
/// Always available on macOS 14+; zero network, zero setup.
@MainActor
final class AppleVoiceBackend: VoiceBackend {
    let name = "Apple"
    var available: Bool { true }
    private(set) var isDictating = false
    var transcriptHandler: ((String) -> Void)?

    private let synth = AVSpeechSynthesizer()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func speak(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: t)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(u)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }

    func startDictation() async {
        transcript = ""; note = nil
        let status = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { s in c.resume(returning: s) }
        }
        guard status == .authorized else {
            note = "Enable Speech Recognition in System Settings › Privacy."
            return
        }
        beginAudio()
    }

    private func beginAudio() {
        guard let recognizer, recognizer.isAvailable else {
            note = "Speech recognizer unavailable for this locale."; return
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            note = "Microphone error: \(error.localizedDescription)"; return
        }
        isDictating = true

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.transcriptHandler?(self.transcript)
                }
                if error != nil || (result?.isFinal ?? false) {
                    _ = await self.stopDictation()
                }
            }
        }
    }

    func stopDictation() async -> String {
        guard isDictating else { return transcript }
        isDictating = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil; request = nil
        return transcript
    }

    var transcript = ""
    var note: String?
}

// MARK: - Process sidecar backend

/// A voice backend that delegates to an external subprocess (e.g. kokoro-tiny
/// for TTS, liquid-rust for STT). The sidecar communicates over stdin/stdout
/// with JSON-RPC-style messages.
///
/// Protocol:
///   TTS:  {"cmd":"speak","text":"..."}
///   STT:  {"cmd":"transcribe","audio":"<base64>"} → {"text":"..."}
@MainActor
final class ProcessVoiceBackend: VoiceBackend {
    let name: String
    let ttsPath: String?
    let sttPath: String?
    private(set) var isDictating = false

    var available: Bool {
        let ttsOk = ttsPath.map { FileManager.default.isExecutableFile(atPath: $0) } ?? false
        let sttOk = sttPath.map { FileManager.default.isExecutableFile(atPath: $0) } ?? false
        return ttsOk || sttOk
    }

    var transcript = ""
    var note: String?

    init(name: String, ttsPath: String?, sttPath: String?) {
        self.name = name
        self.ttsPath = ttsPath
        self.sttPath = sttPath
    }

    func speak(_ text: String) async {
        guard let ttsPath else { note = "no TTS sidecar configured"; return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ttsPath)
            process.arguments = [t]
            try process.run()
            process.waitUntilExit()
        } catch {
            note = "TTS sidecar error: \(error.localizedDescription)"
        }
    }

    func stop() async {
        // Subprocess TTS is fire-and-forget; no stop mechanism without PID tracking.
        // Future: maintain a set of child PIDs and SIGTERM them.
    }

    func startDictation() async {
        guard sttPath != nil else { note = "no STT sidecar configured"; return }
        // STT sidecar integration placeholder — requires audio capture + streaming
        // to the sidecar's stdin. Full implementation when liquid-rust is available.
        note = "STT sidecar not yet wired (liquid-rust pending)"
    }

    func stopDictation() async -> String {
        isDictating = false
        return transcript
    }
}

// MARK: - Combined engine

/// hf.app's voice layer — on-device speech with swappable backends.
///
/// Default: Apple-native (AVSpeechSynthesizer + SFSpeechRecognizer).
/// 8b-native swap: set `backend` to a `ProcessVoiceBackend` pointed at
/// kokoro-tiny (TTS) and liquid-rust (STT) binaries.
@MainActor
@Observable
final class VoiceEngine {
    /// The active voice backend. Swap at runtime to switch between Apple-native
    /// and 8b-native sidecars.
    var backend: any VoiceBackend {
        didSet { syncState() }
    }

    var speakReplies = false
    var isDictating: Bool { backend.isDictating }
    var transcript: String = ""
    var note: String?

    /// Create with the default Apple-native backend.
    init() {
        self.backend = AppleVoiceBackend()
        if let apple = backend as? AppleVoiceBackend {
            apple.transcriptHandler = { [weak self] text in
                self?.transcript = text
            }
        }
    }

    /// Create with a process sidecar backend.
    convenience init(ttsPath: String?, sttPath: String?, name: String = "Sidecar") {
        let proc = ProcessVoiceBackend(name: name, ttsPath: ttsPath, sttPath: sttPath)
        self.init()
        self.backend = proc
        syncState()
    }

    private func syncState() {
        note = nil
    }

    // MARK: - Speak (TTS)

    func speak(_ text: String) {
        guard speakReplies else { return }
        Task { await backend.speak(text) }
    }

    func stopSpeaking() {
        Task { await backend.stop() }
    }

    // MARK: - Dictate (STT)

    func toggleDictation() {
        if backend.isDictating {
            Task {
                transcript = await backend.stopDictation()
            }
        } else {
            transcript = ""
            note = nil
            Task { await backend.startDictation() }
        }
    }

    func startDictation() {
        transcript = ""
        note = nil
        Task { await backend.startDictation() }
    }

    func stopDictation() {
        Task {
            transcript = await backend.stopDictation()
        }
    }
}
