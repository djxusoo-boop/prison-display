#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h:h}"
version=$(cat VERSION)
out="build/audit-$version"
mkdir -p "$out/Frameworks" "$out/build"
cp -R 'build/PRISON DISPLAY MacBook.app/Contents/Frameworks/' "$out/Frameworks/"
cp build/CoreTests-vectors.dat build/CoreTests-sample.dat "$out/build/"
common=(Sources/DesktopControl.swift Sources/Recovery.swift Sources/Preferences.swift Sources/Startup.swift Sources/Protocol.swift Sources/Cursor.swift Sources/Pairing.swift Sources/Pointer.swift Sources/Latency.swift Sources/Video.swift Sources/UI.swift Sources/LegacyNetwork.swift Sources/LegacyCrypto.swift build/Version.swift)
legacy=(-D LEGACY -target x86_64-apple-macosx10.13 -import-objc-header Sources/UnifiedBridge.h build/LegacySecurity-x86_64.o build/dependencies/openssl-3.5.9/libssl.a build/dependencies/openssl-3.5.9/libcrypto.a -Xlinker -rpath -Xlinker '@executable_path/Frameworks')
xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -D UNIFIED "${legacy[@]}" "${common[@]}" Sources/Workspace.swift build/SendPanel.swift build/ReceivePanel.swift Tests/Live/CaptureStub.swift build/VirtualDisplay-x86_64.o Tests/Workspace/main.swift -o "$out/Workspace"
printf '%s\n' 'Intel audit binaries compiled for macOS 10.13+'
