# CLAUDE.md — Dikttavo

Private, fully on-device voice-to-text iPhone app: SwiftUI + Apple SpeechAnalyzer/SpeechTranscriber for live dictation, optional transcript cleanup via Foundation Models (Apple Intelligence devices), SwiftData history. Zero external dependencies, zero networking — audio and text never leave the device.

- **Status:** v1 feature-complete per README (permissions → record → transcribe → clean → save all implemented, ~1,000 lines Swift). ⚠️ Git repo is initialized but has **zero commits** — every file is untracked, so there is no history safety net yet.
- **Last updated:** 2026-07-06

## SSOT convention

This file is the entry point for a fresh session: status, exact commands, next steps. [README.md](README.md) holds the detail (privacy invariants, requirements, project-layout diagram, debug helpers) — don't duplicate it here. **At the end of any session that changes something, update Status / Next steps / Last updated above.**

## Requirements

- iOS 26.0+ deployment target; current Xcode with an iOS 26 simulator runtime.
- No Swift Package dependencies — Apple frameworks only (SwiftUI, SwiftData, AVFoundation, Speech, FoundationModels).
- Real-device runs need a signing Team set in target *Dikttavo → Signing & Capabilities*.

## Build & run

Primary workflow is Xcode: open `Dikttavo.xcodeproj`, scheme `Dikttavo`, pick an iPhone destination, ⌘R.

```bash
# Headless build check (any iOS 26 simulator):
xcodebuild -project Dikttavo.xcodeproj -scheme Dikttavo \
  -destination 'generic/platform=iOS Simulator' build
```

## Verify & debug

There is **no test target** — verification is a clean build plus a manual run (record → live transcript → cleaned toggle → history entry).

```bash
# Seed sample history in the simulator (DEBUG builds only):
xcrun simctl launch <simulator-udid> com.vishwas.Dikttavo -seedHistory

# Stream the app's diagnostic logs:
log stream --predicate 'subsystem == "com.vishwas.Dikttavo"' --level info
```

## Secrets

None. The app is fully on-device: no API keys, no `.env`, no xcconfig secrets, no network calls. Microphone and speech-recognition access are runtime iOS permission prompts. Keep it that way — "no networking code" is a stated privacy invariant in the README.

## Key files (all in `Dikttavo/`)

- `DikttavoApp.swift` — `@main` entry; SwiftData container + UserDefaults setup
- `DictationView.swift` — main UI: record button, live transcript, raw/cleaned toggle
- `DictationEngine.swift` — orchestration state machine (permissions → record → transcribe → clean → save)
- `Transcriber.swift` — SpeechAnalyzer/SpeechTranscriber + language-asset management, DictationTranscriber fallback
- `Recorder.swift` — AVAudioEngine capture; owns the audio-session lifecycle (mic-invariant critical)
- `Cleaner.swift` — Foundation Models cleanup (silently skipped on non-AI-capable devices)
- `BufferConverter.swift` — mic format → analyzer format conversion
- `DictationRecord.swift` — SwiftData model (raw + cleaned text)
- `HistoryView.swift` / `SettingsView.swift` — history list/detail/delete; language + auto-cleanup + save-history toggles

## Next 3 steps (nothing documented — suggested)

1. **Make the initial git commit** — the repo has zero commits; commit the working v1 before touching anything else (author: Vishwas's git identity).
2. **Add a unit-test target** — `DictationEngine`'s state machine and `BufferConverter` are the testable seams; currently the only verification is a manual run.
3. **Validate on a physical iPhone** — set up signing, test real-mic dictation quality and Foundation Models cleanup on Apple Intelligence hardware (simulator behavior differs for speech + FM availability).
