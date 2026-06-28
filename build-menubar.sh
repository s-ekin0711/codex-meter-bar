#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/Codex Limits Menu Bar.app"
APP_CONTENTS="$APP/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"

rm -rf "$APP"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

cp "$ROOT/Resources/Info.plist" "$APP_CONTENTS/Info.plist"
if [[ -f "$ROOT/Resources/CodexLimits.icns" ]]; then
  cp "$ROOT/Resources/CodexLimits.icns" "$APP_RESOURCES/CodexLimits.icns"
fi
printf "APPL????" > "$APP_CONTENTS/PkgInfo"

swiftc \
  -target arm64-apple-macosx14.0 \
  -parse-as-library \
  -O \
  -framework SwiftUI \
  -framework AppKit \
  "$ROOT/Sources/CodexLimitsMenuBar.swift" \
  -o "$APP_MACOS/CodexLimitsMenuBar"

codesign --force --sign - "$APP"
echo "$APP"
