#!/bin/zsh
# Builds Singe in two parts:
#   build/Singe.app           the launcher bundle (holds the Accessibility permission;
#                             kept byte-for-byte the same across updates)
#   build/libSingeCore.dylib  the whole app, replaced on every update
set -euo pipefail

root=${0:A:h:h}
cd "$root"

swift build -c release >/dev/null
bin=$(swift build -c release --show-bin-path)
cp "$bin/libSingeCore.dylib" build/libSingeCore.dylib 2>/dev/null || { mkdir -p build; cp "$bin/libSingeCore.dylib" build/; }

# The launcher's identity: its source, this script and the icon. When this hash is
# unchanged, install.sh keeps the installed Singe.app, so the permission stays.
print -n "$(cat Sources/SingeLauncher/main.swift scripts/bundle.sh Sources/SingeCore/Icons.swift | shasum -a 256 | cut -c1-16)" > build/launcher.hash

app=build/Singe.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Singe" "$app/Contents/MacOS/Singe"

# icon: render every size from the shader (the launcher finds the dylib next to it)
iconset=build/Singe.iconset
rm -rf "$iconset" && mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  "$bin/Singe" --render-icon "$iconset/icon_${size}x${size}.png" $size
  "$bin/Singe" --render-icon "$iconset/icon_${size}x${size}@2x.png" $((size * 2))
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/Singe.icns"
cp "$iconset/icon_512x512@2x.png" build/Singe-icon.png

# The bundle version stays fixed: the app's real version lives in the library (VERSION).
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
  <key>CFBundleShortVersionString</key><string>1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Singe. Definitions from Wiktionary (CC BY-SA 4.0).</string>
</dict>
</plist>
PLIST

# ad-hoc signature with a stable identifier (no Apple Developer account needed)
codesign --force --sign - --identifier app.singe.Singe "$app" >/dev/null 2>&1
print "✓ built $app (launcher $(cat build/launcher.hash)) and build/libSingeCore.dylib ($(cat VERSION))"
