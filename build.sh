#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
version=$(cat VERSION)
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print 'Versión inválida'; exit 1; }
versionSource="enum AppVersion { static let current = \"$version\" }"
if [[ "$(cat build/Version.swift 2>/dev/null)" != "$versionSource" ]]; then print -r -- "$versionSource" > build/Version.swift; fi
python3 Packaging/build-openssl.py
python3 Packaging/generate-role-panels.py
sdk=$(xcrun --show-sdk-path)
runtime="$(xcrun --find swiftc)"
runtime="${runtime:h:h}/lib/swift-5.0/macosx"
[[ -d "$runtime" ]] || { print 'Falta el runtime Swift para High Sierra'; exit 1; }
shared=(Sources/DesktopControl.swift Sources/Recovery.swift Sources/Preferences.swift Sources/Startup.swift Sources/Protocol.swift Sources/Cursor.swift Sources/Pairing.swift Sources/Pointer.swift Sources/Latency.swift Sources/Video.swift Sources/UI.swift Sources/Capture.swift Sources/Workspace.swift Sources/LegacyNetwork.swift Sources/LegacyCrypto.swift build/SendPanel.swift build/ReceivePanel.swift build/Version.swift)
for arch in arm64 x86_64; do
  minimum=11.0; extra=()
  [[ "$arch" == x86_64 ]] && minimum=10.13
  xcrun clang -arch "$arch" -mmacosx-version-min="$minimum" -fobjc-arc -isysroot "$sdk" -c Sources/VirtualDisplay.m -o "build/VirtualDisplay-$arch.o"
  xcrun clang -arch "$arch" -mmacosx-version-min="$minimum" -fobjc-arc -isysroot "$sdk" -c Sources/LegacyCapture.m -o "build/LegacyCapture-$arch.o"
  if [[ "$arch" == x86_64 ]]; then
    dependency=build/dependencies/openssl-3.5.9
    xcrun clang -arch x86_64 -mmacosx-version-min=10.13 -fobjc-arc -isysroot "$sdk" -I "$dependency/include" -c Sources/LegacySecurity.m -o build/LegacySecurity-x86_64.o
    extra=(-D LEGACY build/LegacySecurity-x86_64.o "$dependency/libssl.a" "$dependency/libcrypto.a")
  fi
  xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -D UNIFIED -target "$arch-apple-macosx$minimum" -sdk "$sdk" "${shared[@]}" "${extra[@]}" "build/VirtualDisplay-$arch.o" "build/LegacyCapture-$arch.o" -import-objc-header Sources/UnifiedBridge.h -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' Sources/main.swift -o "build/Unified-$arch"
done
for role in Sender Receiver; do
  name='PRISON DISPLAY MacBook'
  [[ "$role" == Receiver ]] && name='PRISON DISPLAY iMac'
  app="build/$name.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
  cp Assets/PrisonLogo.jpg Assets/PrisonDisplay.icns "$app/Contents/Resources/"
  cp build/dependencies/openssl-3.5.9/LICENSE.txt "$app/Contents/Resources/OpenSSL-LICENSE.txt"
  cp build/dependencies/openssl-source.json "$app/Contents/Resources/OpenSSL-source.json"
  xcrun lipo -create build/Unified-arm64 build/Unified-x86_64 -output "$app/Contents/MacOS/AireDisplay"
  xcrun swift-stdlib-tool --copy --platform macosx --source-libraries "$runtime" --scan-executable build/Unified-x86_64 --destination "$app/Contents/Frameworks"
  python3 - "$app" "$role" "$name" "$version" <<'PY'
import plistlib,sys
from pathlib import Path
app,role,name,version=sys.argv[1:]
info=dict(CFBundleExecutable='AireDisplay',CFBundleIdentifier='local.airedisplay.'+role,CFBundleName=name,CFBundleDisplayName=name,CFBundleIconFile='PrisonDisplay',CFBundlePackageType='APPL',CFBundleShortVersionString=version,CFBundleVersion=version,LSMinimumSystemVersion='10.13',LSMinimumSystemVersionByArchitecture={'arm64':'11.0','x86_64':'10.13'},NSHighResolutionCapable=True,NSLocalNetworkUsageDescription='Encontrar y conectar tus Mac para enviar o recibir una pantalla.',NSBonjourServices=['_airedisplay._tcp','_airepair._tcp','_airecursor._tcp'],NSScreenCaptureUsageDescription='Enviar la pantalla seleccionada a otro Mac.',CFBundleURLTypes=[{'CFBundleURLName':'local.airedisplay.connection','CFBundleURLSchemes':['airedisplay']}])
Path(app,'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
  python3 Signing/sign.py "$app"
done
