#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
image='swift:6.1@sha256:6e43114610e161e38ad41636ebcafd6940dc67dfab355eace3a0ca100b2263db'
mkdir -p build/reports
# Requires the official Swift image to be available locally. Never starts CI,
# signs, uploads, or adds an app dependency. The container has no network.
docker image inspect "$image" >/dev/null
docker run --rm --pull never --network none -v "$PWD:/src" -w /src "$image" bash -c '
  swift --version
  swift package --scratch-path build/SwiftCoreChecks clean
  swift test --scratch-path build/SwiftCoreChecks
  for file in App/*.swift Shared/*.swift Widgets/*.swift Tests/*.swift UITests/*.swift; do
    swiftc -frontend -parse "$file"
  done
' > build/reports/swift-core-tests.log 2>&1
cat build/reports/swift-core-tests.log
printf '%s\n' 'Foundation logic tests + Swift parsing only; NO iOS SDK build or device tests.'
