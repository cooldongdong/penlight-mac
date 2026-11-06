#!/bin/sh
# Build a native arm64 .app bundle into ./build/Hawk Presenter.app (ad-hoc signed).
set -eu
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/HawkPresenter"
APP="build/Hawk Presenter.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/HawkPresenter"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>HawkPresenter</string>
  <key>CFBundleIdentifier</key><string>tw.cooldongdong.hawk-presenter</string>
  <key>CFBundleName</key><string>Hawk Presenter</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
# Stable identity keeps Input Monitoring across rebuilds (see make-signing-cert.sh).
IDENTITY="Hawk Presenter Local Signing"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "warning: '$IDENTITY' not found, ad-hoc signing; Input Monitoring resets on every rebuild" >&2
  codesign --force --sign - "$APP"
fi
echo "Built: $APP"
