#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
configuration=${1:-debug}
app=build/Hark.app

"$(dirname "$0")/make-cert.sh"
swift build -c "$configuration"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Hark.icns "$app/Contents/Resources/Hark.icns"
cp ".build/$configuration/hark" "$app/Contents/MacOS/hark"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.hark.app</string>
  <key>CFBundleName</key><string>Hark</string>
  <key>CFBundleExecutable</key><string>hark</string>
  <key>CFBundleIconFile</key><string>Hark</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Hark listens while you hold its key so it can hear your command.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Hark turns your spoken command into text on this Mac.</string>
  <key>NSAppleEventsUsageDescription</key><string>Hark reads and switches your browser tabs.</string>
</dict>
</plist>
PLIST

codesign --force --sign "Hark Dev" --identifier dev.hark.app "$app"
echo "built $app"
