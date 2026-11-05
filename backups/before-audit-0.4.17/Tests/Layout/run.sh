#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h:h}"
common=(Sources/DesktopControl.swift Sources/Recovery.swift Sources/Preferences.swift Sources/Protocol.swift Sources/Cursor.swift Sources/Pairing.swift Sources/Pointer.swift Sources/Latency.swift Sources/Video.swift Sources/UI.swift build/Version.swift)
for role in Sender Receiver; do
 app="build/Layout$role.app"
 mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
 cp Assets/PrisonLogo.jpg "$app/Contents/Resources/"
 extra=()
 target=x86_64-apple-macosx10.15
 [[ "$role" == Sender ]] && { target=arm64-apple-macosx13.0; extra=(-D SENDER Tests/Live/CaptureStub.swift build/VirtualDisplay-arm64.o -import-objc-header Sources/VirtualDisplay.h); }
 xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target "$target" "${common[@]}" "${extra[@]}" Tests/Layout/main.swift -o "$app/Contents/MacOS/Layout$role"
 "$app/Contents/MacOS/Layout$role" --layout-preview "build/UI-$role-$(cat VERSION).png"
done
