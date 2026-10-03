# CLAUDE.md — Dikttavo

Private, fully on-device voice-to-text app for iPhone, iPad and Mac: SwiftUI + Apple SpeechAnalyzer/SpeechTranscriber for live dictation, optional transcript cleanup via Foundation Models (Apple Intelligence devices), SwiftData history. Zero external dependencies, zero networking — audio and text never leave the device.

- **Status:** v1 feature-complete; **public open source (MIT)** at `github.com/vishwas46/dikttavo` (badges, screenshot, social card, repo pinned). **2026-10-03 platform update:** minimum OS raised to **iOS/iPadOS/macOS 27**; iPad support (sidebar layout) and a **native Mac app** (sandboxed, microphone-only entitlements); Apple's `AnalyzerInputConverter` replaced our `BufferConverter.swift`; privacy manifest; privacy CI (`scripts/check-privacy.sh` + GitHub Actions). Verified: zero-warning builds for iOS Simulator and native macOS (signed, Personal Team `LY96XV88YC`); simulator UI checks on iPhone 18 Pro and iPad Pro 11" (iOS 27); Mac app launched with its menus checked. **Never verified: live dictation on any device** — and the mic path changed in this update (new converter + iOS 27 `installAudioTap`). The first GitHub CI run starts with the push of this update. No test target.
- **Last updated:** 2026-10-03 (iOS/iPadOS/macOS 27 + iPad + native Mac + privacy manifest + privacy CI; before: 2026-09-28)

## SSOT convention

This file is the entry point for a fresh session: status, exact commands, next steps. [README.md](README.md) holds the detail (privacy invariants, requirements, project-layout diagram, debug helpers) — don't duplicate it here. **At the end of any session that changes something, update Status / Next steps / Last updated above.**

## Requirements

- iOS, iPadOS and macOS **27.0+** deployment targets; Xcode 27 (iOS 27 simulator runtime for UI checks).
- No Swift Package dependencies — Apple frameworks only (SwiftUI, SwiftData, AVFoundation, Speech, FoundationModels).
- Real-device and Mac runs need a signing Team set in target *Dikttavo → Signing & Capabilities* (the pbxproj carries the free Personal Team).

## Build & run

Primary workflow is Xcode: open `Dikttavo.xcodeproj`, scheme `Dikttavo`, pick an iPhone, iPad or **My Mac** destination, ⌘R.

```bash
# Headless build check — iPhone + iPad (one binary):
xcodebuild -project Dikttavo.xcodeproj -scheme Dikttavo \
  -destination 'generic/platform=iOS Simulator' build

# Native Mac app, signed with the personal team already in the pbxproj:
xcodebuild -project Dikttavo.xcodeproj -scheme Dikttavo \
  -destination 'platform=macOS' -allowProvisioningUpdates build
# Product lands in DerivedData .../Build/Products/Debug/Dikttavo.app — launch with `open`.
```

If `xcodebuild` says it requires Xcode (`xcode-select` pointing at CommandLineTools), prefix the command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

The iOS **Simulator cannot run live dictation** (SpeechTranscriber reports 0 locales; the app detects this and shows a message). Live testing = the Mac app or a real iPhone/iPad.

## Verify & debug

There is **no test target** — verification is a clean build, `scripts/check-privacy.sh`, and a manual run (record → live transcript → cleaned toggle → history entry). CI (`.github/workflows/ci.yml`) runs the privacy script on Ubuntu and builds iPhone/iPad + Mac on GitHub's `xcode-27` runner (labelled "preview" by GitHub — jobs may queue).

```bash
# Privacy invariants (no networking APIs, no cloud model, no packages, no Mac network entitlement):
scripts/check-privacy.sh

# Seed sample history in the simulator (DEBUG builds only):
xcrun simctl launch <simulator-udid> com.vishwas.Dikttavo -seedHistory

# Stream the app's diagnostic logs:
log stream --predicate 'subsystem == "com.vishwas.Dikttavo"' --level info
```

On the Mac, `-seedHistory` writes into your real history store (`~/Library/Containers/com.vishwas.Dikttavo/…/Application Support/Dikttavo/History.store`) — use it only if you don't mind two sample entries (Clear All removes them).

## Secrets

None. The app is fully on-device: no API keys, no `.env`, no xcconfig secrets, no network calls. Microphone and speech-recognition access are runtime OS permission prompts. Keep it that way — "no networking code" is a stated privacy invariant in the README, enforced by `scripts/check-privacy.sh`.

## Key files (all in `Dikttavo/` unless noted)

- `DikttavoApp.swift` — `@main` entry; the one app-wide `DictationEngine`, SwiftData container (named store on Mac), scenes (`Window` + `Settings` on Mac), ⌘R Dictation menu
- `RootView.swift` — layout switch: iPhone stack vs. iPad/Mac sidebar (`NavigationSplitView`)
- `DictationView.swift` — dictation pane: record button, live transcript, raw/cleaned toggle
- `DictationEngine.swift` — orchestration state machine (permissions → record → transcribe → clean → save)
- `Transcriber.swift` — SpeechAnalyzer/SpeechTranscriber + language assets, DictationTranscriber fallback, `AnalyzerInputConverter` intake
- `Recorder.swift` — AVAudioEngine capture; owns the mic lifecycle (audio session on iOS — mic-invariant critical)
- `Cleaner.swift` — Foundation Models cleanup (on-device model only), availability messages, long-dictation chunking
- `Platform.swift` — the few iOS/macOS differences (clipboard, privacy-settings URL, wording)
- `DictationRecord.swift` — SwiftData model (raw + cleaned text)
- `HistoryView.swift` / `SettingsView.swift` — history list/detail/delete; language + auto-cleanup + save-history toggles
- `PrivacyInfo.xcprivacy` — App Store privacy manifest (no tracking, no data collected, UserDefaults reason CA92.1)
- `scripts/check-privacy.sh`, `.github/workflows/ci.yml` (repo root) — privacy checks + CI

## App Store plan (decided 2026-08-07, Mac part updated 2026-10-02)

Free app → publish as **Individual** under `bv.vishwas46@gmail.com` (currently free tier — needs the $99/yr Apple Developer Program enrollment before any upload; fastest via the Apple Developer app on iPhone). Declare **non-trader** in App Store Connect (free non-commercial app → no personal contact published in EU). NOT under the forming GmbH — App Transfer can move it to the org account later if wanted. The Mac app is now a **native macOS build of the same target and bundle ID** (one App Store record, iPhone + iPad + Mac). Android would be a full rewrite — deferred until iOS proves demand.

## Platform decision (2026-10-02)

- Minimum OS raised to 27 on all three platforms (Vishwas: the 27 speech/AI models are much better; it also unlocks Apple's `AnalyzerInputConverter` and the throwing `installAudioTap`).
- iPad + native Mac added in the same multiplatform target; this reverses the 2026-08-07 "Mac via Designed for iPhone" plan.
- Mac app is sandboxed with **audio input only** — no network entitlement, so macOS itself blocks connections; `check-privacy.sh` fails the build if one appears.
- Gemini plan review was offered for this change (platform upgrade + CI classes) and implicitly declined ("go ahead").

## Next 3 steps

1. **Live-test the native Mac app** — Xcode ▸ destination **My Mac** ▸ ⌘R. Grant the microphone + speech prompts, then record → live transcript → AI cleanup → history; check the menu-bar mic indicator turns off within ~1 s of stopping. This is the first live run of the new 27 audio path. While testing, screen-record a 10–15 s dictation for the README demo GIF (the single biggest star-driver).
2. **Validate on the physical iPhone (and an iPad if available)** — live dictation, orange mic-dot timing, an airplane-mode run, the first-use model download. Write the click-by-click steps for Vishwas when this starts.
3. **Confirm the first CI run is green (GitHub ▸ Actions; the `xcode-27` runner may queue), then run the launch plan** — demo GIF in README, community files (CONTRIBUTING, issue templates), a v1.1 release; post the "reference sample for SpeechAnalyzer + Foundation Models on iOS 27" angle (Show HN, r/iOSProgramming, r/SwiftUI, iOS Dev Weekly, `open-source-ios-apps`). Enroll ($99) when ready for TestFlight.
