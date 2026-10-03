import AVFoundation

/// Owns the microphone. Capture runs strictly between start() and stop() — never
/// in the background, never between dictations. On iPhone and iPad the audio
/// session is active only for that span too. This is what keeps the orange mic
/// indicator scoped to actual recording.
final class Recorder {
    struct NoMicrophoneError: Error {}

    private let engine = AVAudioEngine()
    private var isRecording = false
    private var hardwareObserver: NSObjectProtocol?

    /// Starts capture and streams microphone buffers to `onBuffer` (called on the
    /// audio thread). `onHardwareChange` runs on the main queue if the audio
    /// hardware changes mid-recording (say, headphones plugged in) — the system
    /// stops the engine then, so the dictation should end.
    func start(
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onHardwareChange: @escaping () -> Void
    ) throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [.allowBluetoothHFP])
        try session.setActive(true)
        #endif

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // A Mac without a built-in or connected microphone reports an empty format.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            deactivateSession()
            throw NoMicrophoneError()
        }
        do {
            try input.installAudioTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
                onBuffer(AVAudioPCMBuffer(copying: buffer))
            }
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            deactivateSession()
            throw error
        }
        hardwareObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { _ in
            onHardwareChange()
        }
        isRecording = true
    }

    /// Stops capture and releases the mic immediately.
    func stop() {
        guard isRecording else { return }
        isRecording = false
        if let hardwareObserver {
            NotificationCenter.default.removeObserver(hardwareObserver)
        }
        hardwareObserver = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        deactivateSession()
    }

    private func deactivateSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
