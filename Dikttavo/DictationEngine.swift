import AVFoundation
import Foundation
import Speech
import SwiftData

/// Drives a dictation session: permissions, recorder, transcriber, and UI state.
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

    /// Set by the view; used to persist finished dictations to local history.
    var modelContext: ModelContext?

    private let recorder = Recorder()
    let transcriber = Transcriber()
    private let cleaner = Cleaner()

    var downloadProgress: Progress? { transcriber.downloadProgress }
    var cleanupAvailable: Bool { cleaner.isAvailable }

    init() {
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
            try recorder.start { buffer in
                intake.ingest(buffer)
            }
            transcript = ""
            cleanedTranscript = nil
            state = .listening
        } catch {
            await transcriber.cancel()
            recorder.stop()
            state = .idle
            errorMessage = (error as? TranscriberError)?.message
                ?? "Couldn't start dictation. Please try again."
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

        if UserDefaults.standard.bool(forKey: "saveHistory"),
           !transcript.isEmpty,
           let modelContext {
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
