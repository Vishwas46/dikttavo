# Dikttavo

![Platform](https://img.shields.io/badge/platform-iOS%2026%2B%20%7C%20Apple%20Silicon%20Mac-blue)
![Tech](https://img.shields.io/badge/SwiftUI-SpeechAnalyzer%20%2B%20Foundation%20Models-orange)
![Privacy](https://img.shields.io/badge/AI-100%25%20on--device-brightgreen)
![Dependencies](https://img.shields.io/badge/dependencies-zero-lightgrey)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

A private, fully on-device voice-to-text app for iPhone. Tap to record, speak,
watch the live transcription, and get a tidied-up version the moment you stop —
all without a single byte leaving the device.

Every dictation app *says* it's private. Dikttavo is ~1,000 lines of Swift you
can read in an afternoon: **there is no networking code in this app** — no
URLSession, no sockets, no SDKs, no analytics. It works with airplane mode on.
That claim is auditable, and this repo is the audit.

<p align="center">
  <img src="docs/screenshot-main.png" width="300" alt="Dikttavo main screen — tap the mic and start speaking">
</p>

- **Transcription:** Apple `SpeechAnalyzer` + `SpeechTranscriber` (iOS 26), with
  automatic fallback to `DictationTranscriber` for locales or devices the new
  transcriber doesn't cover.
- **Cleanup:** Apple Foundation Models (`SystemLanguageModel`) removes filler
  words, fixes punctuation/capitalization, and formats sentences — on devices
  with Apple Intelligence. Elsewhere the app quietly keeps the raw transcript.
- **History:** SwiftData store in the app sandbox. Per-item delete, Clear All,
  and a privacy toggle that stops saving entirely.
- **Zero dependencies:** one SwiftUI module. No network code, no analytics, no
  accounts, no third-party SDKs.

## Privacy invariants

1. Everything runs on-device; the app contains no networking code. The only
   network activity ever triggered is iOS itself downloading a speech model the
   first time a language is used (and Apple Intelligence models, managed by the
   OS). After that, dictation and cleanup work in airplane mode.
2. The microphone is live **only** between tapping record and tapping stop.
   `AVAudioSession` is activated at start and deactivated (`setActive(false)`)
   the instant recording stops — see `Recorder.swift`. There is no background
   listening and no warm session between dictations; leaving the app stops
   dictation (`handleScenePhaseChange`).
3. iOS shows the orange microphone indicator while recording. That's expected —
   it should appear when you start and vanish within ~1 second of stopping.

## Requirements

- Xcode 26, iOS 26.0+ deployment target, iPhone only.
- Live dictation requires a real iPhone — the iOS Simulator doesn't support the
  speech engines (the app detects this and says so instead of hanging).
- AI cleanup requires an Apple-Intelligence-capable iPhone (15 Pro or newer)
  with Apple Intelligence enabled. Otherwise the app shows a small note and
  keeps transcripts raw.

## Run it

1. Open `Dikttavo.xcodeproj` in Xcode.
2. Pick the `Dikttavo` scheme and an iPhone destination (simulator for UI-only,
   a connected iPhone for real dictation).
3. For a device: select the project → target **Dikttavo** → *Signing &
   Capabilities* → choose your **Team** (add your Apple ID under Xcode ▸
   Settings ▸ Accounts if the menu is empty). Change the bundle identifier if
   it collides.
4. Press ⌘R. First run on device: enable Developer Mode when iOS asks
   (Settings ▸ Privacy & Security ▸ Developer Mode), and trust the developer
   certificate (Settings ▸ General ▸ VPN & Device Management).
5. Tap the red mic button, grant microphone + speech recognition, and speak.

First use of a language downloads its speech model once (progress bar in the
app). Everything afterwards — including airplane mode — is fully offline.

### On a Mac (Apple Silicon)

macOS 26 ships the same speech and Apple Intelligence stack, so the iPhone app
runs as-is: choose the **My Mac (Designed for iPhone)** destination in Xcode and
press ⌘R. The orange mic indicator appears in the macOS menu bar while
recording — same rules, same code.

## Project layout

```
Dikttavo/
├── DikttavoApp.swift      app entry, SwiftData container, settings defaults
├── DictationView.swift    main screen: record button, live transcript, raw/cleaned toggle
├── DictationEngine.swift  state machine: permissions → record → transcribe → clean → save
├── Recorder.swift         AVAudioEngine capture; audio session lifecycle (the mic invariant)
├── Transcriber.swift      SpeechAnalyzer + SpeechTranscriber/DictationTranscriber + assets
├── BufferConverter.swift  mic format → analyzer format
├── Cleaner.swift          Foundation Models transcript cleanup (tidy only, never answer)
├── DictationRecord.swift  SwiftData model (raw + cleaned)
├── HistoryView.swift      local history list + detail, delete / clear all
└── SettingsView.swift     language, auto-cleanup, save-history toggles
```

## Debug helpers

- `simctl launch <udid> com.vishwas.Dikttavo -seedHistory` seeds two sample
  history records (DEBUG builds only) so history UI can be exercised in the
  simulator, where dictation itself can't run.
- Diagnostic logging: subsystem `com.vishwas.Dikttavo`, category `dictation`
  (`log stream --predicate 'subsystem == "com.vishwas.Dikttavo"' --level info`).

## Contributing

Issues and PRs are welcome — especially dictation-quality reports for non-English
locales and testing on different Apple Intelligence hardware. One rule is
non-negotiable: **no networking code, no third-party dependencies.** PRs that
add either will be declined regardless of the feature; the entire point of this
app is that its privacy claims are enforced by absence.

## License

[MIT](LICENSE) — do whatever you like, attribution appreciated.
