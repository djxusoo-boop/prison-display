#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h:h}"
mkdir -p Windows/build/fixtures
print "enum AppVersion { static let current = \"$(cat VERSION)\" }" > Windows/build/fixtures/Version.swift
xcrun swiftc -O -swift-version 5 -module-cache-path build/ModuleCache Sources/Protocol.swift Sources/Pointer.swift Sources/DesktopControl.swift Windows/build/fixtures/Version.swift Windows/tests/swift-fixtures/main.swift -o Windows/build/fixtures/generate
Windows/build/fixtures/generate Windows/tests/fixtures
cp build/CoreTests-sample.dat Windows/tests/fixtures/video.bin
