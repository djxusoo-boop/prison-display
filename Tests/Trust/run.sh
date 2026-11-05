#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h:h}"
for arch in arm64 x86_64; do
  minimum=13.0
  [[ "$arch" == x86_64 ]] && minimum=10.15
  xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target "$arch-apple-macosx$minimum" \
    Sources/Protocol.swift Sources/Pointer.swift Sources/DesktopControl.swift Sources/Cursor.swift Sources/Pairing.swift \
    build/Version.swift Tests/Trust/main.swift -o "build/TrustTests-$arch"
  "build/TrustTests-$arch"
done
