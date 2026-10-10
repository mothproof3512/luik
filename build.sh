#!/bin/bash
# Builds Luik.app in ./build using only the Xcode Command Line Tools (or Xcode).
#
#   ./build.sh            build
#   ./build.sh --install  build and copy to /Applications
#   ./build.sh --run      build and launch
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Luik"
BUNDLE_ID="dev.luik.app"
VERSION="$(grep -o 'static let version = "[^"]*"' Sources/Luik/Settings.swift | cut -d'"' -f2)"
VERSION="${VERSION:-0.0.0}"
APP="build/$APP_NAME.app"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift not found. Install the Command Line Tools with:  xcode-select --install" >&2
  exit 1
fi

echo "▶ swift build (release) … (the first build takes a few minutes)"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
if [ ! -x "$BIN/$APP_NAME" ]; then
  echo "Build failed: $BIN/$APP_NAME not found. See the errors above." >&2
  exit 1
fi

echo "▶ Assembling app bundle …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# Copy any package resource bundles (not needed today, but future-proof).
for bundle in "$BIN"/*.bundle; do
  if [ -e "$bundle" ]; then
    cp -R "$bundle" "$APP/Contents/Resources/"
  fi
done

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
EOF

# Icon (iconset -> icns) when iconutil is available.
if command -v iconutil >/dev/null 2>&1 && [ -d "Resources/AppIcon.iconset" ]; then
  iconutil -c icns "Resources/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null \
    || echo "  (icon skipped: iconutil reported an error)"
fi

# Code signing. macOS ties permissions such as Screen Recording (used for evidence screenshots)
# to the app's signing identity. An ad-hoc signature ("-") changes with every build, so the
# permission has to be granted again after each rebuild. A certificate with a stable identity
# fixes that: run ./scripts/make-signing-identity.sh once to create a local "Luik Local"
# certificate, or set LUIK_CODESIGN_IDENTITY to the name of any code-signing identity you have.
IDENTITY="${LUIK_CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q '"Luik Local"'; then
  IDENTITY="Luik Local"
fi
if [ -n "$IDENTITY" ]; then
  if codesign --force --deep --sign "$IDENTITY" "$APP" >/dev/null 2>&1; then
    echo "▶ Signed with \"$IDENTITY\" (permissions survive rebuilds)"
  else
    echo "  (signing with \"$IDENTITY\" failed; falling back to an ad-hoc signature)"
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"
  fi
else
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"
  echo "  (ad-hoc signature: macOS will ask for Screen Recording again after every rebuild;"
  echo "   run ./scripts/make-signing-identity.sh once to avoid that)"
fi

echo "✔ Done: $APP"

case "${1:-}" in
  --install)
    echo "▶ Copying to /Applications …"
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    echo "✔ Installed: /Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app"
    ;;
  --run)
    open "$APP"
    ;;
esac
