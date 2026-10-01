#!/bin/zsh
# Builds Singe.app from the Swift package: release binary, Info.plist, and the
# glass-bar icon rendered by Singe's own shader. Output: build/Singe.app
set -euo pipefail

root=${0:A:h:h}
cd "$root"
version=$(cat VERSION 2>/dev/null || echo 1.0.0)

swift build -c release --product Singe >/dev/null
bin=$(swift build -c release --show-bin-path)/Singe

app=build/Singe.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Singe"

# icon: render every size from the shader, then pack an .icns
iconset=build/Singe.iconset
rm -rf "$iconset" && mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  "$bin" --render-icon "$iconset/icon_${size}x${size}.png" $size
  "$bin" --render-icon "$iconset/icon_${size}x${size}@2x.png" $((size * 2))
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/Singe.icns"
cp "$iconset/icon_512x512@2x.png" build/Singe-icon.png

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>app.singe.Singe</string>
  <key>CFBundleName</key><string>Singe</string>
  <key>CFBundleDisplayName</key><string>Singe</string>
  <key>CFBundleExecutable</key><string>Singe</string>
  <key>CFBundleIconFile</key><string>Singe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${version}</string>
  <key>CFBundleVersion</key><string>${version}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Singe. Definitions from Wiktionary (CC BY-SA 4.0).</string>
</dict>
</plist>
PLIST

# ad-hoc signature with a stable identifier (no Apple Developer account needed)
codesign --force --sign - --identifier app.singe.Singe "$app" >/dev/null 2>&1
print "✓ built $app ($version)"
