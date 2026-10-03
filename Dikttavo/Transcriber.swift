import AVFoundation
import Foundation
import os
import Speech

let dictationLog = Logger(subsystem: "com.vishwas.Dikttavo", category: "dictation")

enum TranscriberError: Error {
    case unsupportedLocale(Locale)
    case noAudioFormat
    case assetDownloadFailed
    case setupTimedOut

    var message: String {
        switch self {
        case .unsupportedLocale(let locale):
            let name = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
            return "Dictation isn't available for \(name) on this device."
        case .noAudioFormat, .setupTimedOut:
            #if targetEnvironment(simulator)
            return "Live dictation isn't supported in the iOS Simulator. Run Dikttavo on a real iPhone, iPad, or Mac."
            #else
            return "Couldn't start dictation. Please try again."
            #endif
        case .assetDownloadFailed:
            return "Couldn't download the speech model. Connect to the internet once — after that, Dikttavo works fully offline."
        }
    }
}

/// Runs `operation`, failing with `.setupTimedOut` if it doesn't complete in time.
/// Speech services never answer readiness queries in unsupported environments
/// (notably the simulator); this turns an endless hang into a clear error.
private func withSetupTimeout<T>(
    seconds: TimeInterval = 20,
    _ operation: @escaping () async throws -> T
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let claimed = OSAllocatedUnfairLock(initialState: false)
        @Sendable func claim() -> Bool {
            claimed.withLock { done in
                if done { return false }
                done = true
                return true
            }
        }
        Task {
            do {
                let value = try await operation()
                if claim() { continuation.resume(returning: value) }
            } catch {
                if claim() { continuation.resume(throwing: error) }
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if claim() { continuation.resume(throwing: TranscriberError.setupTimedOut) }
        }
    }
}

/// Streams microphone audio into Apple's on-device SpeechAnalyzer and publishes
/// live transcription results. Prefers SpeechTranscriber and falls back to
/// DictationTranscriber for devices or locales it doesn't support.
@MainActor
@Observable
final class Transcriber {
    private(set) var finalizedText = ""
    private(set) var volatileText = ""
    private(set) var downloadProgress: Progress?
    private(set) var usingDictationFallback = false

    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var intake: AudioIntake?

    /// Receives raw microphone buffers on the audio thread and forwards them to
    /// the analyzer, converted to its format by Apple's AnalyzerInputConverter.
    final class AudioIntake: @unchecked Sendable {
        private let converter: AnalyzerInputConverter
        private let continuation: AsyncStream<AnalyzerInput>.Continuation
        private let lock = NSLock() // ingest (audio thread) vs. flush (main actor)

        init(converter: AnalyzerInputConverter, continuation: AsyncStream<AnalyzerInput>.Continuation) {
            self.converter = converter
            self.continuation = continuation
        }

        func ingest(_ buffer: AVAudioPCMBuffer) {
            lock.withLock {
                guard let inputs = try? converter.convert(buffer, at: nil) else { return }
                inputs.forEach { continuation.yield($0) }
            }
        }

        /// Hands over the audio the converter still holds once recording stops.
        func flush() {
            lock.withLock {
                guard let inputs = try? converter.flush() else { return }
                inputs.forEach { continuation.yield($0) }
            }
        }
    }

    /// The user's preferred locale when a transcriber supports it, a same-language
    /// locale when one exists, en-US otherwise.
    static func resolveLocale(preferring preferred: Locale) async -> Locale {
        dictationLog.info("resolveLocale: querying SpeechTranscriber.supportedLocales")
        var supported = await SpeechTranscriber.supportedLocales
        dictationLog.info("resolveLocale: got \(supported.count) speech locales, querying DictationTranscriber")
        supported += await DictationTranscriber.supportedLocales
        dictationLog.info("resolveLocale: total \(supported.count) locales")
        let preferredID = preferred.identifier(.bcp47)
        if let exact = supported.first(where: { $0.identifier(.bcp47) == preferredID }) {
            return exact
        }
        if let sameLanguage = supported.first(where: {
            $0.language.languageCode == preferred.language.languageCode
        }) {
            return sameLanguage
        }
        return Locale(identifier: "en-US")
    }

    /// Prepares the analyzer (downloading model assets on first use) and returns
    /// the intake that the recorder should feed.
    func start(locale: Locale) async throws -> AudioIntake {
        finalizedText = ""
        volatileText = ""

        let localeID = locale.identifier(.bcp47)
        let speechLocales = await SpeechTranscriber.supportedLocales
        dictationLog.info("start: locale \(localeID), SpeechTranscriber supported: \(speechLocales.contains { $0.identifier(.bcp47) == localeID })")

        if speechLocales.contains(where: { $0.identifier(.bcp47) == localeID }) {
            usingDictationFallback = false
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            try await ensureAssets(for: transcriber)
            dictationLog.info("start: assets ready")
            resultsTask = Task {
                do {
                    for try await result in transcriber.results {
                        ingest(text: String(result.text.characters), isFinal: result.isFinal)
                    }
                } catch {
                    // The results stream ends when the analyzer finishes or is cancelled.
                }
            }
            return try await startAnalyzer(with: transcriber)
        }

        let dictationLocales = await DictationTranscriber.supportedLocales
        guard dictationLocales.contains(where: { $0.identifier(.bcp47) == localeID }) else {
            throw TranscriberError.unsupportedLocale(locale)
        }
        usingDictationFallback = true
        let fallback = DictationTranscriber(
            locale: locale,
            contentHints: [],
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        try await ensureAssets(for: fallback)
        resultsTask = Task {
            do {
                for try await result in fallback.results {
                    ingest(text: String(result.text.characters), isFinal: result.isFinal)
                }
            } catch {
                // The results stream ends when the analyzer finishes or is cancelled.
            }
        }
        return try await startAnalyzer(with: fallback)
    }

    /// Ends the audio input, waits for the remaining results to finalize, and
    /// returns the complete transcript.
    func stop() async -> String {
        intake?.flush()
        inputContinuation?.finish()
        do {
            try await withSetupTimeout { [analyzer] in
                try await analyzer?.finalizeAndFinishThroughEndOfInput()
            }
            await resultsTask?.value // the results stream has ended; drain the last segments
        } catch {
            resultsTask?.cancel()
            if let analyzer {
                try? await withSetupTimeout(seconds: 5) {
                    await analyzer.cancelAndFinishNow()
                }
            }
        }
        let text = finalizedText
        reset()
        return text
    }

    /// Abandons the current session without waiting for results.
    func cancel() async {
        inputContinuation?.finish()
        resultsTask?.cancel()
        if let analyzer {
            try? await withSetupTimeout(seconds: 5) {
                await analyzer.cancelAndFinishNow()
            }
        }
        reset()
    }

    private func ingest(text: String, isFinal: Bool) {
        if isFinal {
            finalizedText += text
            volatileText = ""
        } else {
            volatileText = text
        }
    }

    private func startAnalyzer(with module: any SpeechModule) async throws -> AudioIntake {
        let status = await AssetInventory.status(forModules: [module])
        dictationLog.info("startAnalyzer: asset status \(String(describing: status))")

        let analyzer = SpeechAnalyzer(modules: [module])
        self.analyzer = analyzer
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation

        dictationLog.info("startAnalyzer: creating input converter")
        let converter: AnalyzerInputConverter
        do {
            converter = try await withSetupTimeout {
                try await AnalyzerInputConverter.converter(compatibleWith: [module])
            }
        } catch let error as TranscriberError {
            throw error
        } catch {
            dictationLog.error("startAnalyzer: no input converter: \(error)")
            throw TranscriberError.noAudioFormat
        }
        dictationLog.info("startAnalyzer: starting analyzer")
        try await withSetupTimeout {
            try await analyzer.start(inputSequence: stream)
        }
        dictationLog.info("startAnalyzer: analyzer started")
        let intake = AudioIntake(converter: converter, continuation: continuation)
        self.intake = intake
        return intake
    }

    private func ensureAssets(for module: any SpeechModule) async throws {
        do {
            dictationLog.info("ensureAssets: requesting installation request")
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                dictationLog.info("ensureAssets: download needed, starting")
                downloadProgress = request.progress
                defer { downloadProgress = nil }
                try await request.downloadAndInstall()
            } else {
                dictationLog.info("ensureAssets: nothing to download")
            }
        } catch {
            dictationLog.error("ensureAssets failed: \(error)")
            throw TranscriberError.assetDownloadFailed
        }
    }

    private func reset() {
        analyzer = nil
        intake = nil
        inputContinuation = nil
        resultsTask = nil
        volatileText = ""
    }
}
