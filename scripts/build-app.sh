#!/bin/sh
# Build a native arm64 .app bundle into ./build/Penlight.app.
set -eu
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Penlight"
APP="build/Penlight.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Penlight"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Penlight</string>
  <key>CFBundleIdentifier</key><string>tw.cooldongdong.penlight</string>
  <key>CFBundleName</key><string>Penlight</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
# Stable identity keeps Input Monitoring across rebuilds (see make-signing-cert.sh).
# The older name is still accepted so an existing certificate keeps working.
IDENTITY=""
for name in "Penlight Local Signing" "Hawk Presenter Local Signing"; do
  if security find-certificate -c "$name" >/dev/null 2>&1; then IDENTITY="$name"; break; fi
done
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "warning: no local signing certificate, ad-hoc signing; permissions reset on every rebuild" >&2
  echo "         run ./scripts/make-signing-cert.sh once to fix" >&2
  codesign --force --sign - "$APP"
fi
echo "Built: $APP"
