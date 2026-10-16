#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Requires macOS/Xcode; WebKit iOS journey NOT EXECUTED.' >&2; exit 1; }
xcodegen generate
device_id="$(xcrun simctl list devices available --json | python3 -c '
import json,sys
for runtime,devices in sorted(json.load(sys.stdin)["devices"].items(),reverse=True):
    if "iOS" in runtime:
        for device in devices:
            if device.get("isAvailable") and device["name"].startswith("iPad"):
                print(device["udid"]);sys.exit(0)
sys.exit("No installed iPad simulator")
')"
if [[ "${CI:-}" == true ]]; then
  xcrun simctl boot "$device_id" || true
  xcrun simctl bootstatus "$device_id" -b
fi
xcrun simctl get_app_container "$device_id" com.apple.mobilesafari app >/dev/null
xcodebuild -project WebKWeb.xcodeproj -scheme WebKWeb \
  -destination "platform=iOS Simulator,id=$device_id" -derivedDataPath build/WebKitDerivedData \
  -resultBundlePath "build/WebKit-Tests-$(date +%s).xcresult" \
  -test-timeouts-enabled YES -parallel-testing-enabled NO \
  -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 600 \
  -only-testing:WebKWebUITests/BrowserWebPlaybackJourneyUITests \
  CODE_SIGNING_ALLOWED=NO test
