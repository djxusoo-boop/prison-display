#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h:h}"
common=(Sources/Protocol.swift Sources/Pointer.swift Sources/DesktopControl.swift Sources/Cursor.swift Sources/Pairing.swift build/Version.swift)
for arch in arm64 x86_64; do
 minimum=13.0; extra=()
 if [[ "$arch" == x86_64 ]]; then
  minimum=10.13
  extra=(-D LEGACY Sources/LegacyNetwork.swift Sources/LegacyCrypto.swift build/LegacySecurity-x86_64.o build/dependencies/openssl-3.5.9/libssl.a build/dependencies/openssl-3.5.9/libcrypto.a -import-objc-header Sources/UnifiedBridge.h)
 fi
 app="build/Pairing-$arch.app"
 mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"
 xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target "$arch-apple-macosx$minimum" "${common[@]}" "${extra[@]}" Tests/HighSierra/Pairing/main.swift -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' -o "$app/Contents/MacOS/Pairing"
 if [[ "$arch" == x86_64 ]]; then
  xcrun swift-stdlib-tool --copy --platform macosx --source-libraries /Library/Developer/CommandLineTools/usr/lib/swift-5.0/macosx --scan-executable "$app/Contents/MacOS/Pairing" --destination "$app/Contents/Frameworks"
 fi
 python3 - "$app" <<'PY'
from pathlib import Path
import plistlib,sys
Path(sys.argv[1],'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='local.airedisplay.Receiver',CFBundleExecutable='Pairing',CFBundleName='PRISON DISPLAY Compatibility',CFBundleVersion=Path('VERSION').read_text().strip(),CFBundleShortVersionString=Path('VERSION').read_text().strip(),CFBundlePackageType='APPL')))
PY
 python3 Signing/sign.py "$app"
done
