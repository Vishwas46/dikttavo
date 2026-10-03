import AVFoundation
import Foundation
import Speech
import SwiftData

/// Drives a dictation session: permissions, recorder, transcriber, and UI state.
/// The app owns exactly one, shared by all of its windows.
@MainActor
@Observable
final class DictationEngine {
    enum State: Equatable {
        case idle
        case preparing   // permissions, locale resolution, asset download
        case listening
        case finishing   // finalizing the transcript
        case cleaning    // on-device AI cleanup of the raw transcript
    }

    private(set) var state: State = .idle
    var transcript = ""
    var cleanedTranscript: String?
    var permissionDenied = false
    private(set) var errorMessage: String?

    /// Where finished dictations are saved (when history is on).
    private let modelContext: ModelContext

    private let recorder = Recorder()
    let transcriber = Transcriber()
    private let cleaner = Cleaner()

    var downloadProgress: Progress? { transcriber.downloadProgress }
    /// Why AI cleanup can't run right now; nil when it can.
    var cleanupUnavailableMessage: String? { cleaner.unavailableMessage }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        #if os(iOS)
        // A phone call or Siri taking the mic ends the dictation cleanly.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .listening else { return }
                await self.stopDictation()
            }
        }
        #endif
    }

    func toggleRecording() {
        switch state {
        case .idle:
            Task { await self.startDictation() }
        case .listening:
            Task { await self.stopDictation() }
        case .preparing, .finishing, .cleaning:
            break
        }
    }

    /// Ends dictation if the app leaves the foreground — the mic never runs in the background.
    func handleScenePhaseChange(toBackground: Bool) {
        if toBackground && state == .listening {
            Task { await self.stopDictation() }
        }
    }

    private func startDictation() async {
        errorMessage = nil
        state = .preparing

        guard await requestPermissions() else {
            permissionDenied = true
            state = .idle
            return
        }

        do {
            let storedID = UserDefaults.standard.string(forKey: "localeID") ?? ""
            let preferred = storedID.isEmpty ? Locale.current : Locale(identifier: storedID)
            let locale = await Transcriber.resolveLocale(preferring: preferred)
            let intake = try await transcriber.start(locale: locale)
            try recorder.start(
                onBuffer: { buffer in
                    intake.ingest(buffer)
                },
                onHardwareChange: { [weak self] in
                    Task { @MainActor in
                        guard let self, self.state == .listening else { return }
                        await self.stopDictation()
                    }
                }
            )
            transcript = ""
            cleanedTranscript = nil
            state = .listening
        } catch {
            await transcriber.cancel()
            recorder.stop()
            state = .idle
            errorMessage = switch error {
            case let error as TranscriberError: error.message
            case is Recorder.NoMicrophoneError: "No microphone found. Connect one and try again."
            default: "Couldn't start dictation. Please try again."
            }
        }
    }

    private func stopDictation() async {
        state = .finishing
        recorder.stop() // releases the mic immediately; the indicator goes dark
        let raw = await transcriber.stop()
        transcript = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanedTranscript = nil

        let autoCleanup = UserDefaults.standard.bool(forKey: "autoCleanup")
        if autoCleanup, !transcript.isEmpty, cleaner.isAvailable {
            state = .cleaning
            cleanedTranscript = await cleaner.clean(transcript) { [weak self] partial in
                self?.cleanedTranscript = partial
            }
        }

        if UserDefaults.standard.bool(forKey: "saveHistory"), !transcript.isEmpty {
            modelContext.insert(DictationRecord(rawText: transcript, cleanedText: cleanedTranscript))
            try? modelContext.save()
        }
        state = .idle
    }

    private func requestPermissions() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        return speechStatus == .authorized
    }
}
