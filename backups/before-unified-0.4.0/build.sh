#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
version=$(cat VERSION)
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print 'Versión inválida'; exit 1; }
versionSource="enum AppVersion { static let current = \"$version\" }"
if [[ ! -f build/Version.swift ]] || [[ "$(< build/Version.swift)" != "$versionSource" ]]; then
  print -r -- "$versionSource" > build/Version.swift
fi
sdk=$(xcrun --show-sdk-path)
shared=(Sources/DesktopControl.swift Sources/Recovery.swift Sources/Preferences.swift Sources/Protocol.swift Sources/Cursor.swift Sources/Pairing.swift Sources/Pointer.swift Sources/Latency.swift Sources/Video.swift Sources/UI.swift build/Version.swift)
for role in Sender Receiver; do
  if [[ "$role" == Sender ]]; then
    min=13.0; name='PRISON DISPLAY MacBook'
  else
    min=10.15; name='PRISON DISPLAY iMac'
  fi
  app="build/$name.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp Assets/PrisonLogo.jpg "$app/Contents/Resources/PrisonLogo.jpg"
  cp Assets/PrisonDisplay.icns "$app/Contents/Resources/PrisonDisplay.icns"
  for arch in arm64 x86_64; do
    targetMin=$min
    [[ "$role" == Receiver && "$arch" == arm64 ]] && targetMin=11.0
    extra=()
    if [[ "$role" == Sender ]]; then
      xcrun clang -arch "$arch" -mmacosx-version-min="$targetMin" -fobjc-arc -isysroot "$sdk" -c Sources/VirtualDisplay.m -o "build/VirtualDisplay-$arch.o"
      extra=(Sources/Capture.swift "build/VirtualDisplay-$arch.o" -import-objc-header Sources/VirtualDisplay.h -D SENDER)
    fi
    xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target "$arch-apple-macosx$targetMin" -sdk "$sdk" "${shared[@]}" "${extra[@]}" Sources/main.swift -o "build/$role-$arch"
  done
  xcrun lipo -create build/$role-arm64 build/$role-x86_64 -output "$app/Contents/MacOS/AireDisplay"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AireDisplay</string>
<key>CFBundleIdentifier</key><string>local.airedisplay.$role</string>
<key>CFBundleName</key><string>$name</string>
<key>CFBundleDisplayName</key><string>$name</string>
<key>CFBundleIconFile</key><string>PrisonDisplay</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$version</string>
<key>LSMinimumSystemVersion</key><string>$min</string>
<key>LSMinimumSystemVersionByArchitecture</key><dict><key>arm64</key><string>$([[ "$role" == Sender ]] && print 13.0 || print 11.0)</string><key>x86_64</key><string>$min</string></dict>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Conectar tus dos Mac para usar el iMac como pantalla.</string>
<key>NSBonjourServices</key><array><string>_airedisplay._tcp</string><string>_airepair._tcp</string><string>_airecursor._tcp</string></array>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>local.airedisplay.connection</string><key>CFBundleURLSchemes</key><array><string>airedisplay</string></array></dict></array>
<key>NSScreenCaptureUsageDescription</key><string>Enviar la pantalla seleccionada a tu iMac.</string>
</dict></plist>
PLIST
  if [[ "$role" == Sender ]]; then
    /usr/libexec/PlistBuddy -c 'Delete :CFBundleURLTypes' "$app/Contents/Info.plist"
  fi
  python3 Signing/sign.py "$app"
done
