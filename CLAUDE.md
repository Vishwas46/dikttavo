# CLAUDE.md — Dikttavo

Private, fully on-device voice-to-text iPhone app: SwiftUI + Apple SpeechAnalyzer/SpeechTranscriber for live dictation, optional transcript cleanup via Foundation Models (Apple Intelligence devices), SwiftData history. Zero external dependencies, zero networking — audio and text never leave the device.

- **Status:** v1 feature-complete per README; **public open source (MIT)** at `github.com/vishwas46/dikttavo` (README badges + screenshot, topics, social-preview card uploaded, repo pinned on profile). Local checkout moved to `~/Documents/workspace/private/dikttavo` 2026-08-07; Mac (Designed for iPhone) build re-verified from the new path (`BUILD SUCCEEDED`, free Personal Team `LY96XV88YC`, `bv.vishwas46@gmail.com`). The signed Mac app has *not been launched/live-tested yet*. iPhone on-device verification (mic dot, airplane mode) still pending. No test target. Everything committed and pushed.
- **Last updated:** 2026-08-07

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

On this Mac, bare `xcodebuild` fails: `xcode-select` points at CommandLineTools, not Xcode.app. Prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, or switch once via `sudo xcode-select -s /Applications/Xcode.app`.

```bash
# Mac app (Designed for iPhone) — builds signed with the personal team already in the pbxproj:
xcodebuild -project Dikttavo.xcodeproj -scheme Dikttavo \
  -destination 'platform=macOS,variant=Designed for iPhone' -allowProvisioningUpdates build
# Product lands in DerivedData .../Build/Products/Debug-iphoneos/Dikttavo.app — launch with `open`.
```

The iOS **Simulator cannot run live dictation** (SpeechTranscriber reports 0 locales; the app detects this and shows a message). Live testing = Mac run or a real iPhone.

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

## App Store plan (decided 2026-08-07)

Free app → publish as **Individual** under `bv.vishwas46@gmail.com` (currently free tier — needs the $99/yr Apple Developer Program enrollment before any upload; fastest via the Apple Developer app on iPhone). Declare **non-trader** in App Store Connect (free non-commercial app → no personal contact published in EU). NOT under the forming GmbH — App Transfer can move it to the org account later if wanted. Mac App Store comes free via "Designed for iPhone" once the iOS app ships. Android would be a full rewrite — deferred until iOS proves demand.

## Next 3 steps

1. **Launch + live-test the Mac build** (already built & signed): run the Mac build command above, `open` the app, grant mic + speech prompts, then record → live transcript → AI cleanup → history. Verify the macOS menu-bar mic indicator turns off within ~1s of stop. Copy the .app to /Applications for daily use. While testing, screen-record a 10–15s dictation for a README demo GIF — the single biggest star-driver for app repos.
2. **Validate on the physical iPhone** — click-by-click script exists from the 2026-07-05 session handoff: live dictation, orange mic dot timing, airplane-mode run, first-use model download.
3. **When ready to ship:** enroll as Individual, then unit tests (`DictationEngine`, `BufferConverter`) + a GitHub Actions build check before the first TestFlight upload.
