#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h:h:h}"
app=build/high-sierra-fixtures/Motion.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
xcrun swiftc -swift-version 5 -O -D LEGACY -target x86_64-apple-macosx10.13 Tests/Investigate/Scene.swift Tests/HighSierra/Motion/main.swift -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' -o "$app/Contents/MacOS/MotionCheck"
xcrun swift-stdlib-tool --copy --platform macosx --source-libraries /Library/Developer/CommandLineTools/usr/lib/swift-5.0/macosx --scan-executable "$app/Contents/MacOS/MotionCheck" --destination "$app/Contents/Frameworks"
python3 - "$app" <<'PY'
from pathlib import Path
import plistlib,sys
Path(sys.argv[1],'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='local.prisondisplay.MotionCheck',CFBundleExecutable='MotionCheck',CFBundleName='PRISON DISPLAY Motion Check',CFBundleShortVersionString=Path('VERSION').read_text().strip(),CFBundleVersion=Path('VERSION').read_text().strip(),CFBundlePackageType='APPL',LSMinimumSystemVersion='10.13',NSHighResolutionCapable=True)))
PY
python3 Signing/sign.py "$app"
