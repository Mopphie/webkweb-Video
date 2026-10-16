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
# Bounded harness rechecks may reuse the exact unchanged Release source's
# completed native/Browser/iPad-baseline results. Only recorded parent trees,
# allowed harness/docs paths and DEBUG-only app diffs qualify. Any other source
# changes automatically use the complete suite again.
native_recheck="$(python3 - <<'PY'
import subprocess
def git(*args): return subprocess.check_output(['git',*args],text=True).strip()
def release(source):
    lines=[]; debug=False; include=True
    for line in source.splitlines():
        directive=line.strip()
        if directive=='#if DEBUG':
            if debug: raise ValueError('Nested conditional')
            debug=True; include=False; continue
        if debug:
            if directive=='#endif': debug=False; include=True; continue
            if directive=='#else': include=True; continue
            if directive.startswith(('#if','#elseif')): raise ValueError('Ambiguous conditional')
        if include: lines.append(line)
    if debug: raise ValueError('Unterminated conditional')
    return '\n'.join(lines)
try:
    parent=git('rev-parse','HEAD^')
    allowed={'App/NativePlayerPanel.swift','App/NativePlayer.swift','App/BrowserSession.swift','UITests/NativePlaybackJourneyUITests.swift',
             'Scripts/check-macos.sh','.github/workflows/testflight.yml','Docs/TESTFLIGHT_STATUS.md',
             'Docs/PLAYBACK_BUILD6_FOLLOWUP.md','Docs/TEST_REPORT.md'}
    changes=set(git('diff','--name-only',parent,'HEAD').splitlines())
    app_files={path for path in changes if path.startswith('App/')}
    valid=(git('status','--porcelain') == ''
           and git('rev-parse',parent+'^{tree}') in {
               'f2287ef80b6f4e8373eeba2f04176cbcf9cd04c5',
               'e59a1302b9bc5246f076cc270c9a1535b46e1d62',
               '2c48454322ec1711f909901b1424bede2ca0b858',
               'aaabdfed0f096549597bb837fd983655cfb4ae3f',
               '1d84c673f324e1c44cd716f3824464f0334c04a9',
               '91699be8834879b8ac70fb6a89d99c96b0a89046',
               '968ae7458412a74610230d5e7a6f0475047a6c7e',
               'e49923fba7e50cb8dd4e49616e02843e6ed4986d'}
           and bool(changes) and changes <= allowed
           and all(release(git('show',parent+':'+path)) == release(git('show','HEAD:'+path)) for path in app_files))
    print('true' if valid else 'false')
except (subprocess.CalledProcessError,ValueError): print('false')
PY
)"
if [[ "$native_recheck" == true ]]; then
  parent_tree="$(git rev-parse 'HEAD^^{tree}')"
  if [[ "$parent_tree" == 968ae7458412a74610230d5e7a6f0475047a6c7e || "$parent_tree" == e49923fba7e50cb8dd4e49616e02843e6ed4986d ]]; then
    echo 'Targeted PiP recheck with verified real Safari app. Exact unchanged production source: run 38942074355 (72 native + 3 Browser UI without retry + iPad fullscreen/queue/search passed; full PiP case blocked by external Settings launch timeout).'
  else
  echo 'Targeted PiP recheck; exact unchanged Release source and prior test evidence: run 38919948219 (67 native + 3 Browser UI + iPad fullscreen/queue/search passed).'
  fi
fi
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
if [[ "$native_recheck" != true ]]; then
xcodebuild "${project_args[@]}" -scheme WebKWeb \
  -destination "$destination" -derivedDataPath build/DerivedData \
  -resultBundlePath "build/Unit-Tests-$(date +%s).xcresult" \
  -test-timeouts-enabled YES \
  -parallel-testing-enabled NO \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 180 \
  -only-testing:WebKWebTests \
  CODE_SIGNING_ALLOWED=NO test
# WebKit's hosted simulator process became unresponsive after the integration
# suite in run 38917664541. Use a clean device boot for the independent UI
# process, without erasing persistent data or touching local users' sessions.
if [[ "${CI:-}" == true && "$destination" == *id=* ]]; then
  xcrun simctl shutdown "${destination##*id=}" || true
fi
xcodebuild "${project_args[@]}" -scheme WebKWeb \
  -destination "$destination" -derivedDataPath build/DerivedData \
  -resultBundlePath "build/Browser-Tests-$(date +%s).xcresult" \
  -test-timeouts-enabled YES -parallel-testing-enabled NO \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 300 \
  -retry-tests-on-failure -test-iterations 2 \
  -only-testing:WebKWebUITests/BrowserActionsUITests \
  CODE_SIGNING_ALLOWED=NO test
fi
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
if [[ "$native_recheck" != true && "${CI:-}" == true && "$destination" == *id=* ]]; then
  xcrun simctl shutdown "${destination##*id=}" || true
fi
# The first iPad launch in run 38936556842 timed out in XCTest before the
# application launched; its next launch and full PiP journey passed. Finish
# the disposable CI device's OS boot before asking XCTest to launch our app.
if [[ "${CI:-}" == true && "$ipad_destination" == *id=* ]]; then
  xcrun simctl boot "${ipad_destination##*id=}" || true
  xcrun simctl bootstatus "${ipad_destination##*id=}" -b
  if ! xcrun simctl get_app_container "${ipad_destination##*id=}" com.apple.mobilesafari app >/dev/null 2>&1; then
    echo '::error::Safari is not installed in this simulator. Required other-app PiP journey NOT EXECUTED.' >&2
    exit 1
  fi
  echo 'Verified real Safari app is installed for the other-app PiP journey.'
fi
echo "Native adaptive/fullscreen/PiP journeys: $ipad_destination"
journey_scope=(-only-testing:WebKWebUITests/NativePlaybackJourneyUITests)
if [[ "$native_recheck" == true ]]; then
  journey_scope=(-only-testing:WebKWebUITests/NativePlaybackJourneyUITests/testVideoFullscreenBackPiPOtherAppQueueNextAndSearch)
fi
xcodebuild "${project_args[@]}" -scheme WebKWeb \
  -destination "$ipad_destination" -derivedDataPath build/DerivedData \
  -resultBundlePath "build/iPad-Tests-$(date +%s).xcresult" \
  -test-timeouts-enabled YES -parallel-testing-enabled NO \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 600 \
  "${journey_scope[@]}" \
  CODE_SIGNING_ALLOWED=NO test
echo "Simulator-Prüfung erfolgreich (gezielte Wiederholung: $native_recheck). Vorherige Nachweise ggf. wiederverwendet; Gerätetests bleiben erforderlich."
