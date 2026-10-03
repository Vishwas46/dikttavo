#!/usr/bin/env bash
# Dikttavo's privacy promises, checked mechanically. CI runs this on every push
# and pull request; run it locally with: scripts/check-privacy.sh
set -u
cd "$(dirname "$0")/.."

failures=0

# fail_if_found <description> <extended regex> <paths...>
fail_if_found() {
    local description="$1" pattern="$2"
    shift 2
    local matches
    matches=$(grep -rnIE "$pattern" "$@" 2>/dev/null)
    if [ -n "$matches" ]; then
        echo "FAIL  $description"
        echo "$matches" | sed 's/^/        /'
        failures=$((failures + 1))
    else
        echo "ok    $description"
    fi
}

fail_if_found "No networking APIs in the app" \
    'URLSession|URLRequest|NWConnection|NWListener|NWBrowser|NWPathMonitor|import Network|CFNetwork|CFSocket|CFStream|WKWebView|import WebKit|import CloudKit|CKContainer|SFSafariViewController|ASWebAuthenticationSession' \
    Dikttavo
fail_if_found "No Private Cloud Compute model (on-device SystemLanguageModel only)" \
    'PrivateCloudComputeLanguageModel' \
    Dikttavo
fail_if_found "No server-based speech recognition (SpeechAnalyzer only)" \
    'SFSpeech(AudioBuffer|URL)RecognitionRequest|recognitionTask\(' \
    Dikttavo
fail_if_found "No third-party packages" \
    'XCRemoteSwiftPackageReference|XCLocalSwiftPackageReference' \
    Dikttavo.xcodeproj
fail_if_found "No network entitlements for the Mac app" \
    'ENABLE_(OUTGOING|INCOMING)_NETWORK_CONNECTIONS.*= *YES|com\.apple\.security\.network\.' \
    Dikttavo.xcodeproj Dikttavo

manifests=$(find . -path ./.git -prune -o \( -name Package.swift -o -name Package.resolved -o -name Podfile -o -name Cartfile \) -print)
if [ -n "$manifests" ]; then
    echo "FAIL  No dependency manifests"
    echo "$manifests" | sed 's/^/        /'
    failures=$((failures + 1))
else
    echo "ok    No dependency manifests"
fi

# The privacy manifest must keep declaring: no tracking, no collected data.
manifest=Dikttavo/PrivacyInfo.xcprivacy
if grep -A1 '<key>NSPrivacyTracking</key>' "$manifest" | grep -q '<false/>' &&
   grep -A1 '<key>NSPrivacyCollectedDataTypes</key>' "$manifest" | grep -q '<array/>'; then
    echo "ok    Privacy manifest declares no tracking and no collected data"
else
    echo "FAIL  Privacy manifest must declare no tracking and no collected data ($manifest)"
    failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
    echo "$failures privacy check(s) failed."
    exit 1
fi
echo "All privacy checks passed."
