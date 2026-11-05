#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
common=(Sources/DesktopControl.swift Sources/Recovery.swift Sources/Preferences.swift Sources/Startup.swift Sources/Protocol.swift Sources/Cursor.swift Sources/Pairing.swift Sources/Pointer.swift Sources/Latency.swift Sources/Video.swift Sources/UI.swift build/Version.swift)
for arch in arm64 x86_64; do
 target=13.0
 [[ "$arch" == x86_64 ]] && target=10.15
 xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target "$arch-apple-macosx$target" "${common[@]}" Tests/PointerView/main.swift -o "build/PointerViewTests-$arch"
 "build/PointerViewTests-$arch"
done
