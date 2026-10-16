#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 0 ]]; then
  echo "Aufruf: ./Scripts/check-macos.sh" >&2
  exit 2
fi
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Dieses Skript benötigt macOS mit Xcode 26+, iOS-26-SDK und einem iPhone-Simulator." >&2
  exit 1
fi
command -v python3 >/dev/null || { echo "Bitte Python 3 installieren." >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo "Bitte Xcode 26+ und die Command Line Tools auswählen." >&2; exit 1; }
command -v xcrun >/dev/null || { echo "Bitte Xcode Command Line Tools installieren." >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "Bitte XcodeGen installieren: brew install xcodegen" >&2; exit 1; }
command -v node >/dev/null || { echo "Bitte Node.js 18+ installieren." >&2; exit 1; }
xcode_major="$(xcodebuild -version | python3 -c 'import sys; print(int(sys.stdin.readline().split()[1].split(".")[0]))')"
sdk_major="$(xcrun --sdk iphoneos --show-sdk-version | python3 -c 'import sys; print(int(sys.stdin.read().strip().split(".")[0]))')"
node_major="$(node -p 'process.versions.node.split(".")[0]')"
if (( xcode_major < 26 || sdk_major < 26 )); then
  echo "App-Store-Upload erfordert Xcode 26+ und iOS-26-SDK (gefunden: Xcode ${xcode_major}, SDK ${sdk_major})." >&2
  exit 1
fi
if (( node_major < 18 )); then echo "Node.js 18+ erforderlich (gefunden: ${node_major})." >&2; exit 1; fi
xcodegen generate
project_args=(-project WebKWeb.xcodeproj)
node --test Tests/*.test.cjs
destination="${WEBKWEB_SIMULATOR_DESTINATION:-}"
if [[ -z "$destination" ]]; then
  destination="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    if "iOS" not in runtime:
        continue
    for device in devices[runtime]:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            print("platform=iOS Simulator,id=" + device["udid"])
            sys.exit(0)
sys.exit("Kein verfügbarer iPhone-Simulator. Installiere eine iOS-Runtime in Xcode.")
')"
fi
xcodebuild "${project_args[@]}" -scheme WebKWeb \
  -destination "$destination" -derivedDataPath build/DerivedData \
  -resultBundlePath "build/Tests-$(date +%s).xcresult" \
  -test-timeouts-enabled YES \
  -parallel-testing-enabled NO \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 180 \
  -skip-testing:WebKWebUITests/NativePlaybackJourneyUITests \
  CODE_SIGNING_ALLOWED=NO test
ipad_destination="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    if "iOS" not in runtime:
        continue
    for device in devices[runtime]:
        if device.get("isAvailable") and device["name"].startswith("iPad"):
            print("platform=iOS Simulator,id=" + device["udid"])
            sys.exit(0)
sys.exit("Kein verfügbarer iPad-Simulator für native Vollbild-/PiP-/Queue-Reise.")
')"
# Release the first disposable CI device before booting the iPad. Local users'
# existing Simulator sessions are not shut down.
if [[ "${CI:-}" == true && "$destination" == *id=* ]]; then
  xcrun simctl shutdown "${destination##*id=}" || true
fi
echo "Native adaptive/fullscreen/PiP journeys: $ipad_destination"
xcodebuild "${project_args[@]}" -scheme WebKWeb \
  -destination "$ipad_destination" -derivedDataPath build/DerivedData \
  -resultBundlePath "build/iPad-Tests-$(date +%s).xcresult" \
  -test-timeouts-enabled YES -parallel-testing-enabled NO \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 180 \
  -only-testing:WebKWebUITests/NativePlaybackJourneyUITests \
  CODE_SIGNING_ALLOWED=NO test
echo "Lokaler Simulator-Build und Tests erfolgreich. Gerätetests bleiben erforderlich."
