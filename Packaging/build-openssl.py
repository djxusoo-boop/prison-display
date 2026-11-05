"""Build the pinned TLS dependency locally; never changes system libraries."""
from pathlib import Path
import hashlib, json, subprocess, tarfile, urllib.request
root = Path(__file__).resolve().parents[1]
folder = root / 'build/dependencies'
folder.mkdir(parents=True, exist_ok=True)
version = '3.5.9'
digest = '603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a'
url = f'https://github.com/openssl/openssl/releases/download/openssl-{version}/openssl-{version}.tar.gz'
archive = folder / f'openssl-{version}.tar.gz'
if not archive.exists():
    request = urllib.request.Request(url, headers={'User-Agent': 'PRISON-DISPLAY-build'})
    with urllib.request.urlopen(request, timeout=90) as response: archive.write_bytes(response.read())
assert hashlib.sha256(archive.read_bytes()).hexdigest() == digest, 'OpenSSL source checksum mismatch'
source = folder / f'openssl-{version}'
if not source.exists():
    with tarfile.open(archive) as package: package.extractall(folder, filter='data')
if not (source / 'libssl.a').exists() or not (source / 'libcrypto.a').exists():
    with (folder / 'openssl-configure.log').open('w') as log:
        subprocess.run(['./Configure','darwin64-x86_64-cc','no-shared','no-tests','no-module','no-legacy','no-dso','no-comp','enable-psk','-mmacosx-version-min=10.13'],cwd=source,stdout=log,stderr=subprocess.STDOUT,check=True)
    with (folder / 'openssl-build.log').open('w') as log:
        subprocess.run(['make','-j4','build_libs'],cwd=source,stdout=log,stderr=subprocess.STDOUT,check=True)
(folder/'openssl-source.json').write_text(json.dumps({'version':version,'source':url,'sha256':digest},indent=2)+'\n')
print('Pinned OpenSSL dependency ready: Intel / macOS 10.13')
