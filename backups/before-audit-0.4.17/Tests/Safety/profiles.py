"""Quarantine only the reviewed historical PRISON DISPLAY ICC profiles.

No WindowServer restart, preferences, permissions, or other display profiles.
Run apply/restore only after explicit approval for this one-time maintenance.
"""
from pathlib import Path
import argparse, hashlib, json, os, re, stat, struct, subprocess

p = argparse.ArgumentParser()
p.add_argument('mode', choices=['verify', 'apply', 'restore'])
p.add_argument('backup', type=Path)
a = p.parse_args()
backup = a.backup.resolve()
manifest = json.loads((backup/'manifest.json').read_text())
source = Path('/Library/ColorSync/Profiles/Displays')
assert manifest['source'] == str(source)
protected = {(1280 << 16) | 720, (1920 << 16) | 1080, (2560 << 16) | 1440}
quarantine = backup/'quarantine'

def verified(path, row):
    assert not path.is_symlink() and stat.S_ISREG(path.stat().st_mode)
    data = path.read_bytes()
    assert len(data) == row['size'] and hashlib.sha256(data).hexdigest() == row['sha256']
    assert data[36:40] == b'acsp' and len(data) >= 132
    count = struct.unpack_from('>I', data, 128)[0]
    assert 132 + 12 * count <= len(data)
    identity = None
    for i in range(count):
        tag, offset, size = struct.unpack_from('>4sII', data, 132+12*i)
        if tag == b'mmod' and size >= 20 and offset + size <= len(data):
            identity = struct.unpack_from('>III', data, offset+8)
    assert identity == (0xA1DE, 1, row['serial']) and row['serial'] not in protected

rows = manifest['profiles']
assert len({r['name'] for r in rows}) == len(rows)
for row in rows:
    assert re.fullmatch(r'(?:PRISON DISPLAY · iMac|AireDisplay · iMac)-[0-9A-Fa-f-]{36}\.icc', row['name'])
    verified(backup/row['name'], row)
    if a.mode == 'restore':
        verified(quarantine/row['name'], row)
        assert not (source/row['name']).exists()
    else:
        verified(source/row['name'], row)

if a.mode == 'verify':
    print('Verified backup and exact identities:', len(rows), 'historical profiles; three current identities excluded')
    raise SystemExit(0)

assert os.geteuid() == 0, 'Administrator access required for the approved maintenance'
# Do not move profiles while an old or new PRISON display helper is active.
processes = subprocess.check_output(['/bin/ps', '-axo', 'args='], text=True)
assert not any('--virtual-display-helper' in line and not 'profiles.py' in line for line in processes.splitlines())
quarantine.mkdir(exist_ok=True)
origin, destination = (quarantine, source) if a.mode == 'restore' else (source, quarantine)
moved = []
try:
    for row in rows:
        assert not (destination/row['name']).exists()
        os.rename(origin/row['name'], destination/row['name'])
        moved.append(row)
except BaseException:
    for row in reversed(moved):
        os.rename(destination/row['name'], origin/row['name'])
    raise

(backup/'last-operation.json').write_text(json.dumps({'mode': a.mode, 'count': len(moved)}, indent=2))
print('Historical PRISON profiles', 'restored' if a.mode == 'restore' else 'quarantined', len(moved))
# Fixed targets only. The desktop session and all applications remain open.
result = subprocess.run(['/usr/bin/killall', 'colorsyncd', 'colorsync.displayservices'])
print('Color service restart request exit:', result.returncode)
