#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h:h:h}"
common=(Sources/DesktopControl.swift Sources/Recovery.swift Sources/Preferences.swift Sources/Protocol.swift Sources/Cursor.swift Sources/Pairing.swift Sources/Pointer.swift Sources/Latency.swift Sources/Video.swift Sources/UI.swift build/Version.swift)
for arch in arm64 x86_64; do
    xcrun clang -target "$arch-apple-macosx13.0" -O2 -fobjc-arc -c Tests/Safety/Sender/VirtualStub.m -o "build/VirtualSafetyStub-$arch.o"
    xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target "$arch-apple-macosx13.0" -D SENDER "${common[@]}" Tests/Live/CaptureStub.swift "build/VirtualSafetyStub-$arch.o" -import-objc-header Tests/Safety/Sender/VirtualStub.h Tests/Safety/Sender/main.swift -o "build/SenderSafetyTests-$arch"
    "build/SenderSafetyTests-$arch"
done
