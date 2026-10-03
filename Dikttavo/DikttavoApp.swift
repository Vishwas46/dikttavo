import SwiftData
import SwiftUI

@main
struct DikttavoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer
    /// One engine for the whole app: every window shows the same dictation, and
    /// two windows can never open the microphone at the same time.
    @State private var engine: DictationEngine

    init() {
        UserDefaults.standard.register(defaults: [
            "autoCleanup": true,
            "saveHistory": true,
        ])
        let container = Self.makeModelContainer()
        self.container = container
        _engine = State(initialValue: DictationEngine(modelContext: container.mainContext))
        #if DEBUG
        Self.seedHistoryIfRequested(in: container.mainContext)
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        Window("Dikttavo", id: "main") {
            RootView()
                .environment(engine)
        }
        .defaultSize(width: 900, height: 640)
        .modelContainer(container)
        .commands { DictationCommands(engine: engine) }
        .onChange(of: scenePhase) { _, phase in
            engine.handleScenePhaseChange(toBackground: phase == .background)
        }

        Settings {
            SettingsView()
        }
        #else
        WindowGroup {
            RootView()
                .environment(engine)
        }
        .modelContainer(container)
        .commands { DictationCommands(engine: engine) }
        .onChange(of: scenePhase) { _, phase in
            engine.handleScenePhaseChange(toBackground: phase == .background)
        }
        #endif
    }

    private static func makeModelContainer() -> ModelContainer {
        do {
            #if os(macOS)
            // Outside the App Sandbox (e.g. a contributor's unsigned build), every Mac
            // app's default SwiftData store is one shared file. A named store keeps
            // Dikttavo's history its own either way.
            let folder = URL.applicationSupportDirectory.appending(path: "Dikttavo", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let configuration = ModelConfiguration(url: folder.appending(path: "History.store"))
            return try ModelContainer(for: DictationRecord.self, configurations: configuration)
            #else
            return try ModelContainer(for: DictationRecord.self)
            #endif
        } catch {
            dictationLog.error("history store unavailable, keeping this session in memory: \(error)")
            let inMemory = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: DictationRecord.self, configurations: inMemory)
        }
    }

    #if DEBUG
    /// Verification hook for environments where dictation can't run (the
    /// simulator): `simctl launch <udid> com.vishwas.Dikttavo -seedHistory`
    private static func seedHistoryIfRequested(in context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-seedHistory") else { return }
        context.insert(DictationRecord(
            rawText: "um so this is uh a seeded raw transcript with with filler words",
            cleanedText: "This is a seeded raw transcript with filler words."
        ))
        context.insert(DictationRecord(
            rawText: "second seeded dictation used to test persistence across launches",
            cleanedText: nil
        ))
    }
    #endif
}

/// ⌘R starts and stops dictation — listed in the Mac menu bar and in the iPad's
/// keyboard-shortcut overlay.
struct DictationCommands: Commands {
    let engine: DictationEngine

    var body: some Commands {
        CommandMenu("Dictation") {
            Button("Start/Stop Dictation") {
                engine.toggleRecording()
            }
            .keyboardShortcut("r")
        }
    }
}
