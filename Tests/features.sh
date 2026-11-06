#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
common=(Sources/DesktopControl.swift Sources/Recovery.swift Sources/Preferences.swift Sources/Startup.swift Sources/Protocol.swift Sources/Cursor.swift Sources/Pairing.swift Sources/Pointer.swift Sources/Latency.swift Sources/Video.swift Sources/UI.swift build/Version.swift)
for arch in arm64 x86_64; do
    target=13.0
    [[ "$arch" == x86_64 ]] && target=10.15
    xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target "$arch-apple-macosx$target" Sources/Protocol.swift Sources/Pointer.swift Sources/DesktopControl.swift build/Version.swift Tests/Desktop/main.swift -o "build/DesktopTests-$arch"
    "build/DesktopTests-$arch"
    xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target "$arch-apple-macosx$target" Sources/Recovery.swift Tests/Recovery/main.swift -o "build/RecoveryTests-$arch"
    "build/RecoveryTests-$arch"
    xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target "$arch-apple-macosx$target" Sources/Recovery.swift Tests/Safety/main.swift -o "build/GraphicsSafetyTests-$arch"
    "build/GraphicsSafetyTests-$arch"
    xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target "$arch-apple-macosx$target" Sources/Protocol.swift Sources/Pointer.swift Sources/Cursor.swift build/Version.swift Tests/Cursor/main.swift -o "build/CursorTests-$arch"
    "build/CursorTests-$arch"
    xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target "$arch-apple-macosx$target" Sources/Protocol.swift build/Version.swift Tests/Priority/main.swift -o "build/PriorityTests-$arch"
    "build/PriorityTests-$arch"
    xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target "$arch-apple-macosx$target" "${common[@]}" Tests/PointerView/main.swift -o "build/PointerViewTests-$arch"
    "build/PointerViewTests-$arch"
    xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target "$arch-apple-macosx$target" "${common[@]}" Tests/Reconnect/main.swift -o "build/ReconnectTests-$arch"
    "build/ReconnectTests-$arch"
    xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target "$arch-apple-macosx$target" Sources/Preferences.swift Tests/Preferences/main.swift -o "build/PreferencesTests-$arch"
    "build/PreferencesTests-$arch"
    xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target "$arch-apple-macosx$target" Sources/Startup.swift Tests/Startup/main.swift -o "build/StartupTests-$arch"
    "build/StartupTests-$arch"
    xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target "$arch-apple-macosx$target" "${common[@]}" Tests/Interactive/main.swift -o "build/InteractiveTests-$arch"
    "build/InteractiveTests-$arch"
done
if [[ "${1:-}" == --receiver-only ]]; then
    print 'RESULT: receiver components only; sender and physical display checks remain pending'
    exit 0
fi
xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target arm64-apple-macosx13.0 -D UNIFIED Sources/Protocol.swift Sources/Pointer.swift Sources/DesktopControl.swift build/Version.swift Tests/Continuous/main.swift -o build/ContinuousTests
if command -v cmake >/dev/null; then /bin/zsh Windows/tests/run-mac-e2e.sh; else print "SKIP: Windows agent end-to-end (cmake missing)"; fi
build/ContinuousTests
xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target arm64-apple-macosx13.0 -D SENDER "${common[@]}" Tests/Live/CaptureStub.swift build/VirtualDisplay-arm64.o -import-objc-header Sources/VirtualDisplay.h Tests/Clipboard/main.swift -o build/ClipboardTests
build/ClipboardTests
xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target arm64-apple-macosx13.0 -D SENDER "${common[@]}" Tests/Live/CaptureStub.swift build/VirtualDisplay-arm64.o -import-objc-header Sources/VirtualDisplay.h Tests/Update/main.swift -o build/UpdateTests
build/UpdateTests
/bin/zsh Tests/Presentation/run.sh
/bin/zsh Tests/Safety/Sender/run.sh
xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target arm64-apple-macosx13.0 -D SENDER "${common[@]}" Tests/Live/CaptureStub.swift build/VirtualDisplay-arm64.o -import-objc-header Sources/VirtualDisplay.h Tests/Live/main.swift -o build/LiveTests
build/LiveTests

xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target arm64-apple-macosx13.0 build/VirtualDisplay-arm64.o -import-objc-header Sources/VirtualDisplay.h Tests/Virtual/main.swift -o build/VirtualTests
build/VirtualTests
