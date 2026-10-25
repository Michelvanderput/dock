#!/usr/bin/env bash
# Builds GlassDock.app in ./build. Needs Xcode or the Xcode Command Line Tools.
#   ./scripts/build-app.sh            build for this Mac
#   ARCHS="arm64 x86_64" ./scripts/build-app.sh   universal build (needs full Xcode)
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS="${ARCHS:-$(uname -m)}"
ARCH_ARGS=()
for arch in $ARCHS; do ARCH_ARGS+=(--arch "$arch"); done

echo "==> Compileren ($ARCHS)"
swift build -c release "${ARCH_ARGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_ARGS[@]}" --show-bin-path)"

APP="build/GlassDock.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/GlassDock" "$APP/Contents/MacOS/GlassDock"
cp Support/Info.plist "$APP/Contents/Info.plist"

echo "==> Icoon"
if swift scripts/make-icon.swift build/AppIcon.iconset >/dev/null 2>&1 \
   && iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"; then
  rm -rf build/AppIcon.iconset
else
  echo "    (icoon overgeslagen)"
fi

echo "==> Ondertekenen (ad hoc)"
codesign --force --sign - "$APP"

ditto -c -k --keepParent "$APP" build/GlassDock.zip
echo "==> Klaar: $APP"
echo "    Installeren: sleep build/GlassDock.app naar /Applications en open hem."
