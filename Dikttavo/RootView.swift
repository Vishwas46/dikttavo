import SwiftData
import SwiftUI

/// iPhone (and narrow iPad windows): one dictation screen with History and
/// Settings in the toolbar. iPad and Mac: history in a sidebar next to it.
struct RootView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        #if os(iOS)
        if sizeClass == .compact {
            CompactLayout()
        } else {
            SplitLayout()
        }
        #else
        SplitLayout()
        #endif
    }
}

#if os(iOS)
private struct CompactLayout: View {
    private enum Screen: Hashable {
        case history, settings
    }

    @Environment(DictationEngine.self) private var engine

    var body: some View {
        // Value-based links: the stack owns what's on screen, and the same
        // history rows drive the sidebar selection on iPad and Mac.
        NavigationStack {
            DictationView()
                .navigationTitle("Dikttavo")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink(value: Screen.history) {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .disabled(engine.state != .idle)
                        .accessibilityLabel("History")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: Screen.settings) {
                            Image(systemName: "gearshape")
                        }
                        .disabled(engine.state != .idle)
                        .accessibilityLabel("Settings")
                    }
                }
                .navigationDestination(for: Screen.self) { screen in
                    switch screen {
                    case .history: HistoryView()
                    case .settings: SettingsView()
                    }
                }
                .navigationDestination(for: DictationRecord.self) { record in
                    HistoryDetailView(record: record)
                }
        }
    }
}
#endif

private struct SplitLayout: View {
    @Environment(DictationEngine.self) private var engine
    @State private var selection: DictationRecord?
    #if os(iOS)
    @State private var showingSettings = false
    #endif

    var body: some View {
        NavigationSplitView {
            HistoryView(selection: $selection)
                .toolbar {
                    ToolbarItem {
                        Button {
                            selection = nil
                        } label: {
                            Label("New Dictation", systemImage: "square.and.pencil")
                        }
                        .disabled(selection == nil)
                    }
                    #if os(iOS)
                    ToolbarItem {
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                    #endif
                }
                // Like the iPhone layout: no browsing away mid-dictation.
                .disabled(engine.state != .idle)
        } detail: {
            NavigationStack {
                if let selection {
                    HistoryDetailView(record: selection)
                        .id(selection.persistentModelID)
                } else {
                    DictationView()
                        .navigationTitle("Dikttavo")
                        .inlineNavigationTitle()
                }
            }
        }
        .onChange(of: engine.state) { _, newState in
            // Starting a dictation (e.g. with ⌘R) always brings the dictation pane back.
            if newState != .idle { selection = nil }
        }
        #if os(iOS)
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
        }
        #endif
    }
}
