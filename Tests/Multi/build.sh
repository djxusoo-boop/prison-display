#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h:h}"
version=$(cat VERSION)
app=build/diagnostics/Multi-$version.app
mkdir -p "$app/Contents/MacOS"
common=(Sources/DesktopControl.swift Sources/Recovery.swift Sources/Preferences.swift Sources/Protocol.swift Sources/Cursor.swift Sources/Pairing.swift Sources/Pointer.swift Sources/Latency.swift Sources/Video.swift Sources/UI.swift Sources/Capture.swift build/Version.swift)
xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -D SENDER -target arm64-apple-macosx13.0 "${common[@]}" build/VirtualDisplay-arm64.o build/LegacyCapture-arm64.o -import-objc-header Sources/UnifiedBridge.h Tests/Multi/main.swift -o "$app/Contents/MacOS/AireDisplay"
python3 - "$app" "$version" <<'PY'
import plistlib,sys
from pathlib import Path
Path(sys.argv[1],'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='local.airedisplay.Sender',CFBundleExecutable='AireDisplay',CFBundleName='PRISON DISPLAY Multi Test',CFBundlePackageType='APPL',CFBundleShortVersionString=sys.argv[2],CFBundleVersion=sys.argv[2])))
PY
python3 Signing/sign.py "$app"
