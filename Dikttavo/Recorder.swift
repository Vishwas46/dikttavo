import AVFoundation

/// Owns the microphone. The audio session is active strictly between start() and
/// stop() — never in the background, never between dictations. This is what keeps
/// the orange mic indicator scoped to actual recording.
final class Recorder {
    private let engine = AVAudioEngine()
    private var isRecording = false

    /// Activates the audio session and streams microphone buffers to `onBuffer`
    /// (called on the audio thread).
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [.allowBluetoothHFP])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            onBuffer(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
        isRecording = true
    }

    /// Stops capture and deactivates the audio session immediately, releasing the mic.
    func stop() {
        guard isRecording else { return }
        isRecording = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
