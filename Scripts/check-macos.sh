#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Dieses Skript benötigt macOS mit Xcode 16+ und einem iOS-17+-Simulator." >&2
  exit 1
fi
command -v xcodegen >/dev/null || { echo "Bitte XcodeGen installieren: brew install xcodegen" >&2; exit 1; }
command -v node >/dev/null || { echo "Bitte Node.js 18+ installieren." >&2; exit 1; }
xcodegen generate
project_args=(-project WebKWeb.xcodeproj)
if [[ "${1:-}" == "--cast" ]]; then
  command -v pod >/dev/null || { echo "Bitte CocoaPods installieren." >&2; exit 1; }
  pod install
  project_args=(-workspace WebKWeb.xcworkspace)
elif [[ -f WebKWeb.xcworkspace/contents.xcworkspacedata ]]; then
  project_args=(-workspace WebKWeb.xcworkspace)
fi
node --test Tests/playback.test.cjs
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
  CODE_SIGNING_ALLOWED=NO test
echo "Lokaler Simulator-Build und Tests erfolgreich. Gerätetests bleiben erforderlich."
