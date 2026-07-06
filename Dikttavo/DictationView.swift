import SwiftData
import SwiftUI

struct DictationView: View {
    enum TranscriptMode: String, CaseIterable {
        case cleaned = "Cleaned"
        case raw = "Raw"
    }

    @State private var engine = DictationEngine()
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @State private var mode: TranscriptMode = .raw
    @State private var justCopied = false
    @State private var pulsing = false
    @FocusState private var editorFocused: Bool

    /// The transcript currently shown (and edited, copied, shared).
    private var shownText: Binding<String> {
        if mode == .cleaned && engine.cleanedTranscript != nil {
            return Binding(
                get: { engine.cleanedTranscript ?? "" },
                set: { engine.cleanedTranscript = $0 }
            )
        }
        return $engine.transcript
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcriptArea
                controls
            }
            .navigationTitle("Dikttavo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .disabled(engine.state != .idle)
                    .accessibilityLabel("History")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .disabled(engine.state != .idle)
                    .accessibilityLabel("Settings")
                }
            }
        }
        .task {
            engine.modelContext = modelContext
            #if DEBUG
            // Verification hook for environments where dictation can't run (the
            // simulator): `simctl launch <udid> com.vishwas.Dikttavo -seedHistory`
            if ProcessInfo.processInfo.arguments.contains("-seedHistory") {
                modelContext.insert(DictationRecord(
                    rawText: "um so this is uh a seeded raw transcript with with filler words",
                    cleanedText: "This is a seeded raw transcript with filler words."
                ))
                modelContext.insert(DictationRecord(
                    rawText: "second seeded dictation used to test persistence across launches",
                    cleanedText: nil
                ))
            }
            #endif
        }
        .onChange(of: scenePhase) { _, newPhase in
            engine.handleScenePhaseChange(toBackground: newPhase == .background)
        }
        .onChange(of: engine.state) { _, newState in
            if newState != .idle {
                editorFocused = false
            } else {
                mode = engine.cleanedTranscript != nil ? .cleaned : .raw
            }
        }
        .alert("Allow microphone & speech recognition", isPresented: $engine.permissionDenied) {
            Button("Open Settings") {
                openURL(URL(string: UIApplication.openSettingsURLString)!)
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Dikttavo needs the microphone and speech recognition to take dictation. Turn both on in Settings — everything stays on your iPhone.")
        }
    }

    // MARK: Transcript

    @ViewBuilder
    private var transcriptArea: some View {
        switch engine.state {
        case .listening, .finishing:
            let volatileTail = Text(engine.transcriber.volatileText).foregroundStyle(.secondary)
            ScrollView {
                Text("\(engine.transcriber.finalizedText)\(volatileTail)")
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .defaultScrollAnchor(.bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .cleaning:
            ScrollView {
                Text(engine.cleanedTranscript ?? engine.transcript)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .defaultScrollAnchor(.bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .idle, .preparing:
            VStack(spacing: 0) {
                if engine.cleanedTranscript != nil {
                    Picker("Transcript", selection: $mode) {
                        ForEach(TranscriptMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                }
                TextEditor(text: shownText)
                    .font(.body)
                    .focused($editorFocused)
                    .padding(.horizontal, 12)
                    .overlay(alignment: .topLeading) {
                        if shownText.wrappedValue.isEmpty {
                            Text("Tap the mic and start speaking")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 17)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 14) {
            statusLine
            recordButton
            HStack(spacing: 12) {
                copyButton
                shareButton
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch engine.state {
        case .idle:
            VStack(spacing: 4) {
                if let error = engine.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    Text("Tap to dictate")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !engine.cleanupAvailable {
                    Text("AI cleanup isn't available on this device — transcripts stay raw.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        case .preparing:
            if let progress = engine.downloadProgress {
                VStack(spacing: 6) {
                    ProgressView(progress)
                        .frame(maxWidth: 220)
                        .labelsHidden()
                    Text("Downloading speech model — one time only")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Preparing…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        case .listening:
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 9, height: 9)
                Text("Listening…")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
            }
        case .finishing:
            HStack(spacing: 8) {
                ProgressView()
                Text("Finishing…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .cleaning:
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                Text("Tidying up…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recordButton: some View {
        Button {
            engine.toggleRecording()
        } label: {
            ZStack {
                if engine.state == .listening {
                    Circle()
                        .stroke(.red.opacity(0.35), lineWidth: 5)
                        .frame(width: 102, height: 102)
                        .scaleEffect(pulsing ? 1.07 : 0.95)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
                }
                Circle()
                    .fill(.red)
                    .frame(width: 84, height: 84)
                if engine.state == .listening {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.white)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 106, height: 106)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.5 : 1)
        .onChange(of: engine.state) { _, newState in
            pulsing = newState == .listening
        }
        .accessibilityLabel(engine.state == .listening ? "Stop dictation" : "Start dictation")
    }

    private var isBusy: Bool {
        engine.state == .preparing || engine.state == .finishing || engine.state == .cleaning
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = shownText.wrappedValue
            justCopied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                justCopied = false
            }
        } label: {
            Label(justCopied ? "Copied" : "Copy", systemImage: justCopied ? "checkmark" : "doc.on.doc")
                .frame(minWidth: 90)
        }
        .buttonStyle(.bordered)
        .disabled(shownText.wrappedValue.isEmpty || engine.state != .idle)
    }

    private var shareButton: some View {
        ShareLink(item: shownText.wrappedValue) {
            Label("Share", systemImage: "square.and.arrow.up")
                .frame(minWidth: 90)
        }
        .buttonStyle(.bordered)
        .disabled(shownText.wrappedValue.isEmpty || engine.state != .idle)
    }
}

#Preview {
    DictationView()
}
