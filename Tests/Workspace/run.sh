#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h:h}"
version=$(cat VERSION)
arch=$(uname -m)
case "$arch" in
  arm64) target=13.0 ;;
  x86_64) target=10.15 ;;
  *) print "Arquitectura no compatible para las pruebas de Workspace: $arch"; exit 1 ;;
esac
python3 Packaging/generate-role-panels.py
mkdir -p build/WorkspacePreview.app/Contents/MacOS build/WorkspacePreview.app/Contents/Resources
cp Assets/PrisonLogo.jpg Assets/PrisonDisplay.icns build/WorkspacePreview.app/Contents/Resources/
python3 - "$version" <<'PY'
import plistlib
import sys
from pathlib import Path
version = sys.argv[1]
info = {
    "CFBundleExecutable": "WorkspacePreview",
    "CFBundleIdentifier": "local.airedisplay.WorkspacePreview",
    "CFBundleName": "WorkspacePreview",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": version,
}
Path("build/WorkspacePreview.app/Contents/Info.plist").write_bytes(plistlib.dumps(info))
PY
xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -D UNIFIED -target "$arch-apple-macosx$target" Sources/DesktopControl.swift Sources/Recovery.swift Sources/Preferences.swift Sources/Startup.swift Sources/Protocol.swift Sources/Cursor.swift Sources/Pairing.swift Sources/Pointer.swift Sources/Latency.swift Sources/Video.swift Sources/UI.swift Sources/Workspace.swift Sources/WindowsLink.swift Sources/Brightness.swift Sources/OldCopies.swift Sources/Corrector.swift Sources/CorrectorSelfTest.swift Sources/DisplaysPage.swift build/SendPanel.swift build/ReceivePanel.swift build/Version.swift Tests/Live/CaptureStub.swift "build/VirtualDisplay-$arch.o" -import-objc-header Sources/VirtualDisplay.h Tests/Workspace/main.swift -o build/WorkspacePreview.app/Contents/MacOS/WorkspacePreview
build/WorkspacePreview.app/Contents/MacOS/WorkspacePreview --names-only
build/WorkspacePreview.app/Contents/MacOS/WorkspacePreview --layout-preview
# The iMac and the MacBook Pro run the Intel slice, built with LEGACY (no
# ScreenCaptureKit corrector, OpenSSL transport for macOS 10.13). On an Apple
# silicon Mac the same checks run under Rosetta, so their app is tested too.
if [[ "$arch" == arm64 && -f build/LegacySecurity-x86_64.o ]] && arch -x86_64 /usr/bin/true 2>/dev/null; then
  legacy=build/WorkspacePreviewLegacy.app
  mkdir -p "$legacy/Contents/MacOS" "$legacy/Contents/Resources"
  cp Assets/PrisonLogo.jpg Assets/PrisonDisplay.icns "$legacy/Contents/Resources/"
  python3 - "$version" <<'PY'
import plistlib
import sys
from pathlib import Path
version = sys.argv[1]
info = {"CFBundleExecutable": "WorkspacePreviewLegacy", "CFBundleIdentifier": "local.airedisplay.WorkspacePreviewLegacy", "CFBundleName": "WorkspacePreviewLegacy", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version, "CFBundleVersion": version}
Path("build/WorkspacePreviewLegacy.app/Contents/Info.plist").write_bytes(plistlib.dumps(info))
PY
  dependency=build/dependencies/openssl-3.5.9
  binary="$legacy/Contents/MacOS/WorkspacePreviewLegacy"
  xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -D UNIFIED -D LEGACY -target x86_64-apple-macosx10.13 Sources/DesktopControl.swift Sources/Recovery.swift Sources/Preferences.swift Sources/Startup.swift Sources/Protocol.swift Sources/Cursor.swift Sources/Pairing.swift Sources/Pointer.swift Sources/Latency.swift Sources/Video.swift Sources/UI.swift Sources/Workspace.swift Sources/LegacyNetwork.swift Sources/LegacyCrypto.swift Sources/WindowsLink.swift Sources/Brightness.swift Sources/OldCopies.swift Sources/Corrector.swift Sources/CorrectorSelfTest.swift Sources/DisplaysPage.swift build/SendPanel.swift build/ReceivePanel.swift build/Version.swift Tests/Live/CaptureStub.swift build/VirtualDisplay-x86_64.o build/LegacyCapture-x86_64.o build/LegacySecurity-x86_64.o "$dependency/libssl.a" "$dependency/libcrypto.a" -import-objc-header Sources/UnifiedBridge.h Tests/Workspace/main.swift -o "$binary"
  # As in build.sh: CoreMedia C calls bound to CoreMedia itself (macOS 10.13 and 12).
  install_name_tool -change @rpath/libswiftCoreMedia.dylib /System/Library/Frameworks/CoreMedia.framework/Versions/A/CoreMedia "$binary" 2>/dev/null
  codesign -f -s - "$binary" 2>/dev/null
  print "Versión Intel (iMac y MacBook Pro) con Rosetta:"
  "$binary" --names-only
  "$binary" --layout-preview output=build/legacy-preview
fi
