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
for test in Reconnect Interactive Presentation PointerView; do
 mkdir -p "$out/source/$test"
 python3 - "$test" "$out" <<'PY'
from pathlib import Path
import sys
name, out = sys.argv[1:]
s = Path('Tests',name,'main.swift').read_text().replace('import Network', '#if !LEGACY\nimport Network\n#endif')
Path(out,'source',name,'main.swift').write_text(s)
PY
 xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O "${legacy[@]}" "${common[@]}" "$out/source/$test/main.swift" -o "$out/$test"
done
for test in Preferences Startup; do
 source=Sources/Preferences.swift
 [[ "$test" == Startup ]] && source=Sources/Startup.swift
 xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target x86_64-apple-macosx10.13 -Xlinker -rpath -Xlinker '@executable_path/Frameworks' "$source" "Tests/$test/main.swift" -o "$out/$test"
done
xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -D UNIFIED "${legacy[@]}" "${common[@]}" Sources/Workspace.swift build/SendPanel.swift build/ReceivePanel.swift Tests/Live/CaptureStub.swift build/VirtualDisplay-x86_64.o Tests/Workspace/main.swift -o "$out/Workspace"
printf '%s\n' 'Intel audit binaries compiled for macOS 10.13+'
