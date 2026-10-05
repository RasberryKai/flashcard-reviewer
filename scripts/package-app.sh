#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_BUNDLE_NAME=${APP_BUNDLE_NAME:-FlashcardReviewer.app}
APP_DIR="$ROOT_DIR/.build/$APP_BUNDLE_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
CACHE_DIR="$ROOT_DIR/.build/swiftpm-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-module-cache"
export SWIFT_MODULECACHE_PATH="$ROOT_DIR/.build/swift-module-cache"

cd "$ROOT_DIR"
swift build -c release --disable-sandbox --cache-path "$CACHE_DIR" --scratch-path "$ROOT_DIR/.build"
BIN_DIR=$(swift build -c release --show-bin-path --disable-sandbox --cache-path "$CACHE_DIR" --scratch-path "$ROOT_DIR/.build")
RESOURCE_BUNDLE="$BIN_DIR/FlashcardReviewer_FlashcardReviewer.bundle"
EXECUTABLE="$BIN_DIR/FlashcardReviewer"
if [ ! -x "$EXECUTABLE" ] || [ ! -d "$RESOURCE_BUNDLE" ]; then
  printf 'Missing app binary or SwiftPM resource bundle in %s\n' "$BIN_DIR" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$CONTENTS_DIR/Resources"
cp "$EXECUTABLE" "$MACOS_DIR/FlashcardReviewer"
cp "$ROOT_DIR/Assets/Brand/FlashcardReviewer.icns" "$CONTENTS_DIR/Resources/FlashcardReviewer.icns"
cp -R "$RESOURCE_BUNDLE" "$APP_DIR/FlashcardReviewer_FlashcardReviewer.bundle"
cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>FlashcardReviewer</string>
  <key>CFBundleIdentifier</key><string>com.flashcardreviewer.mac</string>
  <key>CFBundleName</key><string>Flashcard Reviewer</string>
  <key>CFBundleIconFile</key><string>FlashcardReviewer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
printf 'Created %s\n' "$APP_DIR"
