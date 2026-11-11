#!/bin/zsh
# Separate test copy of the MacBook app: same signature (keeps the screen
# permission), marked PrisonDisplayTestBuild so it never updates, never
# registers at login and never removes the installed copy.
set -euo pipefail
cd "${0:A:h:h}"
version=$(cat VERSION)
folder="${1:-$HOME/Desktop/PRISON-DISPLAY-$version-prueba}"
app="$folder/PRISON DISPLAY Prueba.app"
mkdir -p "$folder"; rm -rf "$app"
ditto "build/PRISON DISPLAY MacBook.app" "$app"
rm -rf "$app/Contents/Resources/Updates"
python3 - "$app" <<'PY'
import plistlib, sys
from pathlib import Path
p = Path(sys.argv[1], 'Contents/Info.plist'); d = plistlib.loads(p.read_bytes())
d.update(CFBundleName='PRISON DISPLAY Prueba', CFBundleDisplayName='PRISON DISPLAY Prueba', PrisonDisplayTestBuild=True)
p.write_bytes(plistlib.dumps(d))
PY
python3 Signing/sign.py "$app"
print -r -- "$app"
