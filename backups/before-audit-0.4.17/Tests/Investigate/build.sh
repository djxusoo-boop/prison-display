#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h:h}"
version=$(cat VERSION)
common=(Sources/DesktopControl.swift Sources/Recovery.swift Sources/Preferences.swift Sources/Protocol.swift Sources/Cursor.swift Sources/Pairing.swift Sources/Pointer.swift Sources/Latency.swift Sources/Video.swift Sources/UI.swift build/Version.swift)
xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target arm64-apple-macosx13.0 -D SENDER -D DIAGNOSTIC_SCENE "${common[@]}" Sources/Capture.swift build/VirtualDisplay-arm64.o build/LegacyCapture-arm64.o -import-objc-header Sources/UnifiedBridge.h Tests/Investigate/Scene.swift Tests/Investigate/Sender/main.swift -o "build/PerfSender-$version"
xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target x86_64-apple-macosx10.15 -D REAL_ROUTE_DIAGNOSTIC "${common[@]}" Tests/Investigate/RealReceiver/main.swift -o "build/RealReceiver-$version"
python3 Tests/Investigate/bundle.py "real-$version" "$version" "PerfSender-$version" "RealReceiver-$version"
