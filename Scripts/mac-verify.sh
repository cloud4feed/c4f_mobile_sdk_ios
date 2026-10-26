#!/usr/bin/env bash
# Phase 2 verification on a Mac (EC2 Mac over SSH). Run from the repository root:
#   bash Scripts/mac-verify.sh            # build + unit tests + example app on the simulator
#   bash Scripts/mac-verify.sh logs       # follow SDK logs of the running example app
set -euo pipefail

SIMULATOR="${SIMULATOR:-iPhone 16}"
BUNDLE_ID="com.cloud4feed.SurveySDKTestApp"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build-ios"

if [[ "${1:-}" == "logs" ]]; then
  xcrun simctl spawn booted log stream --level debug \
    --predicate 'subsystem == "com.cloud4feed.mobilesdk" OR eventMessage CONTAINS "[TestApp]"'
  exit 0
fi

echo "== Toolchain"
xcodebuild -version
swift --version

echo "== 1. Unit tests on macOS (Apple Foundation)"
(cd "$ROOT" && swift test)

echo "== 2. SDK build for the iOS simulator (UIKit / WebKit / SwiftUI code)"
(cd "$ROOT" && xcodebuild -scheme Cloud4FeedSDK -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$BUILD_DIR/sdk" build | tail -n 20)

echo "== 3. Example app"
command -v xcodegen >/dev/null || brew install xcodegen
(cd "$ROOT/Example/SurveySDKTestApp-iOS" && xcodegen)
xcodebuild -project "$ROOT/Example/SurveySDKTestApp-iOS/SurveySDKTestApp.xcodeproj" \
  -scheme SurveySDKTestApp -sdk iphonesimulator -destination "platform=iOS Simulator,name=$SIMULATOR" \
  -derivedDataPath "$BUILD_DIR/app" build | tail -n 20

APP="$BUILD_DIR/app/Build/Products/Debug-iphonesimulator/SurveySDKTestApp.app"

echo "== 4. Simulator"
xcrun simctl boot "$SIMULATOR" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR" -b
xcrun simctl uninstall booted "$BUNDLE_ID" 2>/dev/null || true   # fresh state, like `pm clear`
xcrun simctl install booted "$APP"
xcrun simctl launch booted "$BUNDLE_ID"
sleep 5
xcrun simctl io booted screenshot "$BUILD_DIR/launch.png"
echo "Screenshot: $BUILD_DIR/launch.png"
echo "Follow logs with: bash Scripts/mac-verify.sh logs"
