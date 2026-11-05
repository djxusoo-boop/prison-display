#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
version=$(cat VERSION)
versionSource="enum AppVersion { static let current = \"$version\" }"
if [[ ! -f build/Version.swift ]] || [[ "$(< build/Version.swift)" != "$versionSource" ]]; then
  print -r -- "$versionSource" > build/Version.swift
fi
shared=(Sources/Protocol.swift Sources/Pointer.swift Sources/Latency.swift Sources/Video.swift build/Version.swift)
xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target arm64-apple-macosx13.0 "${shared[@]}" Tests/main.swift -o build/CoreTests
build/CoreTests
xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target arm64-apple-macosx13.0 Sources/Protocol.swift Sources/Pairing.swift build/Version.swift Tests/Pairing/main.swift -o build/PairingTests
build/PairingTests
xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target x86_64-apple-macosx10.15 "${shared[@]}" Tests/Intel/main.swift -o build/IntelDecoderTests
build/IntelDecoderTests build/CoreTests-vectors.dat
xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target x86_64-apple-macosx10.15 Sources/Protocol.swift Sources/Pairing.swift build/Version.swift Tests/Pairing/main.swift -o build/IntelPairingTests
build/IntelPairingTests

xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target arm64-apple-macosx13.0 -D SENDER Sources/Protocol.swift Sources/Pointer.swift build/Version.swift Tests/Pointer/main.swift -o build/PointerTests
build/PointerTests
xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target x86_64-apple-macosx10.15 Sources/Protocol.swift Sources/Pointer.swift build/Version.swift Tests/Pointer/main.swift -o build/IntelPointerTests
build/IntelPointerTests
