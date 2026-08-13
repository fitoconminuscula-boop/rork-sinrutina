import AVFoundation
import Foundation
import Speech

/// On-device Spanish dictation used by the floating capture pill and the capture sheet.
/// Everything stays local: audio is never stored and recognition prefers the on-device model.
@Observable
final class VoiceDictationService {
    enum Status: Equatable {
        case idle
        case preparing
        case listening
        case microphoneDenied
        case speechDenied
        case unavailable
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var transcript: String = ""
    private(set) var level: Double = 0

    private let engine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var lastLevelUpdate = Date.distantPast

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES")) ?? SFSpeechRecognizer()
    }

    var isListening: Bool {
        status == .listening || status == .preparing
    }

    var isBlocked: Bool {
        switch status {
        case .microphoneDenied, .speechDenied, .unavailable, .failed:
            return true
        default:
            return false
        }
    }

    var statusMessage: String? {
        switch status {
        case .microphoneDenied:
            return "Activa el micrófono en Ajustes para dictar."
        case .speechDenied:
            return "Activa el reconocimiento de voz en Ajustes para dictar."
        case .unavailable:
            return "El dictado no está disponible en este dispositivo."
        case .failed(let message):
            return message
        default:
            return nil
        }
    }

    /// Clears any previous text and starts listening. Returns false when it could not start.
    @discardableResult
    func start() async -> Bool {
        guard !isListening else { return true }
        guard let recognizer, recognizer.isAvailable else {
            status = .unavailable
            return false
        }

        status = .preparing
        transcript = ""
        level = 0

        guard await hasMicrophonePermission() else {
            status = .microphoneDenied
            return false
        }
        guard await hasSpeechPermission() else {
            status = .speechDenied
            return false
        }

        do {
            try beginSession(recognizer: recognizer)
            status = .listening
            return true
        } catch {
            teardown()
            status = .failed("No pudimos escuchar ahora mismo.")
            return false
        }
    }

    /// Stops listening and returns whatever was understood.
    @discardableResult
    func stop() -> String {
        teardown()
        if !isBlocked {
            status = .idle
        }
        level = 0
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func reset() {
        transcript = ""
        if !isBlocked {
            status = .idle
        }
    }

    func dismissStatusMessage() {
        status = .idle
    }

    private func beginSession(recognizer: SFSpeechRecognizer) throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let bufferRequest = SFSpeechAudioBufferRecognitionRequest()
        bufferRequest.shouldReportPartialResults = true
        bufferRequest.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        if #available(iOS 16.0, *) {
            bufferRequest.addsPunctuation = true
        }
        request = bufferRequest

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw NSError(domain: "SinRutina.Dictation", code: 1)
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            bufferRequest.append(buffer)
            let peak = Self.peakLevel(of: buffer)
            Task { @MainActor [weak self] in
                self?.updateLevel(peak)
            }
        }

        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: bufferRequest) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let didFail = error != nil
            Task { @MainActor [weak self] in
                self?.handle(text: text, isFinal: isFinal, didFail: didFail)
            }
        }
    }

    private func handle(text: String?, isFinal: Bool, didFail: Bool) {
        if let text, !text.isEmpty {
            transcript = text
        }
        guard isFinal || didFail else { return }
        // Keep whatever was captured; the caller decides what to do with it.
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        if status == .listening && transcript.isEmpty && didFail {
            status = .idle
        }
    }

    private func updateLevel(_ peak: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastLevelUpdate) > 0.05 else { return }
        lastLevelUpdate = now
        level = level * 0.55 + peak * 0.45
    }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func hasMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        @unknown default:
            return false
        }
    }

    private func hasSpeechPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }

    private nonisolated static func peakLevel(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        var sum: Float = 0
        let samples = channelData[0]
        for index in stride(from: 0, to: frames, by: 4) {
            let value = samples[index]
            sum += value * value
        }
        let count = max(1, frames / 4)
        let rms = sqrt(sum / Float(count))
        let normalized = min(1, Double(rms) * 9)
        return normalized
    }
}
