#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h:h}"
for arch in arm64 x86_64; do
 target=13.0
 [[ "$arch" == x86_64 ]] && target=10.15
 xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target "$arch-apple-macosx$target" Sources/Protocol.swift Sources/Pointer.swift Sources/DesktopControl.swift build/Version.swift Tests/CursorLease/main.swift -o "build/CursorLeaseTests-$arch"
done
