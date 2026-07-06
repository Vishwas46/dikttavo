import Speech
import SwiftUI

struct SettingsView: View {
    @AppStorage("localeID") private var localeID = ""
    @AppStorage("autoCleanup") private var autoCleanup = true
    @AppStorage("saveHistory") private var saveHistory = true
    @State private var locales: [Locale] = []

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $localeID) {
                    Text("Automatic (device language)").tag("")
                    ForEach(locales, id: \.identifier) { locale in
                        Text(displayName(for: locale)).tag(locale.identifier(.bcp47))
                    }
                }
            } footer: {
                Text("Languages supported by on-device transcription. A new language downloads its model once, then works fully offline.")
            }

            Section {
                Toggle("Clean up transcripts automatically", isOn: $autoCleanup)
            } footer: {
                Text("Tidies each transcript with Apple Intelligence on this iPhone — removes filler words, fixes punctuation. Requires a device with Apple Intelligence; otherwise transcripts stay raw.")
            }

            Section {
                Toggle("Save dictations to history", isOn: $saveHistory)
            } footer: {
                Text("When off, Dikttavo stores nothing — a transcript exists only on screen until you dictate again. Saved history never leaves this iPhone.")
            }
        }
        .navigationTitle("Settings")
        .task {
            var supported = await SpeechTranscriber.supportedLocales
            let known = Set(supported.map { $0.identifier(.bcp47) })
            let dictationOnly = await DictationTranscriber.supportedLocales
                .filter { !known.contains($0.identifier(.bcp47)) }
            supported += dictationOnly
            locales = supported.sorted { displayName(for: $0) < displayName(for: $1) }
        }
    }

    private func displayName(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }
}
