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
