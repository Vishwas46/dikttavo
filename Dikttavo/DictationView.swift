import SwiftUI

/// The dictation pane: live transcript, record button, copy and share.
struct DictationView: View {
    enum TranscriptMode: String, CaseIterable {
        case cleaned = "Cleaned"
        case raw = "Raw"
    }

    @Environment(DictationEngine.self) private var engine
    @Environment(\.openURL) private var openURL
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
        return Bindable(engine).transcript
    }

    var body: some View {
        @Bindable var engine = engine
        VStack(spacing: 0) {
            transcriptArea
            controls
        }
        .onChange(of: engine.state) { _, newState in
            if newState != .idle {
                editorFocused = false
            } else {
                mode = engine.cleanedTranscript != nil ? .cleaned : .raw
            }
        }
        .alert("Allow microphone & speech recognition", isPresented: $engine.permissionDenied) {
            Button("Open \(Platform.settingsAppName)") {
                openURL(Platform.privacySettingsURL)
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Dikttavo needs the microphone and speech recognition to take dictation. Turn both on in \(Platform.settingsAppName) — everything stays on this device.")
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
                            Text("\(Platform.tapVerb) the mic and start speaking")
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
                    Text("\(Platform.tapVerb) to dictate")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let cleanupNote = engine.cleanupUnavailableMessage {
                    Text(cleanupNote)
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
            Platform.copyToClipboard(shownText.wrappedValue)
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
