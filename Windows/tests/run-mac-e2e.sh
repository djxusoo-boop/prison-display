#!/bin/zsh
# Mac link ↔ real Windows agent (compiled for macOS with a recording sink).
set -euo pipefail
cd "${0:A:h:h:h}"
openssl=$(brew --prefix openssl@3 2>/dev/null || true)
cmake -S Windows -B Windows/build/native-test ${openssl:+-DOPENSSL_ROOT_DIR=$openssl} >/dev/null
cmake --build Windows/build/native-test -j >/dev/null
Windows/build/native-test/prison_core_tests Windows/tests/fixtures | tail -1
Windows/build/native-test/prison_agent_tests | tail -1
xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target arm64-apple-macosx13.0 -D UNIFIED Sources/Protocol.swift Sources/Pointer.swift Sources/DesktopControl.swift Sources/WindowsLink.swift build/Version.swift Tests/WindowsLink/main.swift -o build/WindowsLinkTests
build/WindowsLinkTests "$PWD/Windows/build/native-test/prison_agent_host"
