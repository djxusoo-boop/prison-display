#!/bin/zsh
set -euo pipefail
common=(Sources/DesktopControl.swift Sources/Recovery.swift Sources/Preferences.swift Sources/Protocol.swift Sources/Cursor.swift Sources/Pairing.swift Sources/Pointer.swift Sources/Latency.swift Sources/Video.swift Sources/UI.swift build/Version.swift)
for arch in arm64 x86_64; do
 min=13.0
 [[ "$arch" == x86_64 ]] && min=10.15
 xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target "$arch-apple-macosx$min" "${common[@]}" Tests/Interactive/main.swift -o build/InteractiveTests-$arch
 build/InteractiveTests-$arch
 done
