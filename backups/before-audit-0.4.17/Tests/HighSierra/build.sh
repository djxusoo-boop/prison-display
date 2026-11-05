#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h:h}"
directory=build/high-sierra-fixtures
mkdir -p "$directory"
common=(Sources/DesktopControl.swift Sources/Recovery.swift Sources/Preferences.swift Sources/Protocol.swift Sources/Cursor.swift Sources/Pairing.swift Sources/Pointer.swift Sources/Latency.swift Sources/Video.swift Sources/UI.swift Sources/LegacyNetwork.swift Sources/LegacyCrypto.swift build/Version.swift)
security=(build/LegacySecurity-x86_64.o build/dependencies/openssl-3.5.9/libssl.a build/dependencies/openssl-3.5.9/libcrypto.a -import-objc-header Sources/UnifiedBridge.h)
names=(Core Encoder Sender Receiver)
if (( $# > 0 )); then names=("$@"); fi
for name in "${names[@]}"; do
  app="$directory/$name.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources"
  extra=()
  case "$name" in
    Core) source=Tests/main.swift ;;
    PointerView) source=Tests/PointerView/main.swift ;;
    TLSProgress) source=Tests/HighSierra/TLSProgress/main.swift ;;
    PeerInterop) source=Tests/HighSierra/PeerInterop/main.swift ;;
    Encoder) source=Tests/IntelEncoder/main.swift ;;
    Pipeline) source=Tests/HighSierra/Pipeline/main.swift; extra=(-D SENDER Tests/HighSierra/Pipeline/CaptureStub.swift build/VirtualDisplay-x86_64.o) ;;
    Sender) source=Tests/Investigate/Sender/main.swift; extra=(-D SENDER -D DIAGNOSTIC_SCENE Sources/Capture.swift build/VirtualDisplay-x86_64.o build/LegacyCapture-x86_64.o Tests/Investigate/Scene.swift) ;;
    CaptureCodec) source=Tests/HighSierra/CaptureCodec/main.swift; extra=(-D DIAGNOSTIC_ENCODER Sources/Capture.swift build/LegacyCapture-x86_64.o) ;;
    Receiver) source=Tests/Investigate/RealReceiver/main.swift; extra=(-D REAL_ROUTE_DIAGNOSTIC) ;;
    Workspace) source=Tests/Workspace/main.swift; extra=(-D UNIFIED Sources/Workspace.swift build/SendPanel.swift build/ReceivePanel.swift Tests/Live/CaptureStub.swift build/VirtualDisplay-x86_64.o); cp Assets/PrisonLogo.jpg Assets/PrisonDisplay.icns "$app/Contents/Resources/" ;;
  esac
  xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -D LEGACY -target x86_64-apple-macosx10.13 "${common[@]}" "${extra[@]}" "${security[@]}" "$source" -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' -o "$app/Contents/MacOS/AireDisplay"
  xcrun swift-stdlib-tool --copy --platform macosx --source-libraries /Library/Developer/CommandLineTools/usr/lib/swift-5.0/macosx --scan-executable "$app/Contents/MacOS/AireDisplay" --destination "$app/Contents/Frameworks"
  python3 - "$app" "$name" <<'PY'
from pathlib import Path
import plistlib,sys
app,name=sys.argv[1:]
role='Sender' if name=='Sender' else 'Receiver'
Path(app,'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='local.airedisplay.'+role,CFBundleExecutable='AireDisplay',CFBundleName='PRISON DISPLAY Test '+name,CFBundleShortVersionString=Path('VERSION').read_text().strip(),CFBundleVersion=Path('VERSION').read_text().strip(),CFBundlePackageType='APPL',LSMinimumSystemVersion='10.13',NSHighResolutionCapable=True)))
PY
  python3 Signing/sign.py "$app"
done
