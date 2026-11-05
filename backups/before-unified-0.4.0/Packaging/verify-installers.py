from pathlib import Path
import subprocess,plistlib,shutil,json,hashlib
root=Path(__file__).resolve().parents[1];version=(root/'VERSION').read_text().strip();out=root/'outputs'/f'PRISON-DISPLAY-v{version}';folder=root/'build'/f'installer-verification-{version}'
if folder.exists():shutil.rmtree(folder)
folder.mkdir()
for row in json.loads((out/'manifest.json').read_text()):
 pkg=out/row['file'];assert hashlib.sha256(pkg.read_bytes()).hexdigest()==row['sha256'];dest=folder/row['role']
 subprocess.run(['pkgutil','--expand-full',str(pkg),str(dest)],check=True,capture_output=True)
 apps=list(dest.rglob('*.app'));assert len(apps)==1;app=apps[0];original=root/'build'/app.name
 info=plistlib.loads((app/'Contents/Info.plist').read_bytes());assert info['CFBundleShortVersionString']==version
 subprocess.run(['codesign','--verify','--strict','--all-architectures',str(app)],check=True,capture_output=True)
 for name in ['MacOS/AireDisplay','Resources/PrisonLogo.jpg','Resources/PrisonDisplay.icns']:assert (app/'Contents'/name).read_bytes()==(original/'Contents'/name).read_bytes()
 for path in dest.rglob('*'):
  assert path.suffix not in ['.p12','.pem','.key','.keychain-db'] and path.name not in ['id_ed25519','keychain-password']
 print('PASS:',row['role'],'version, final binary, logo, icon, signature and private-key exclusion')
print('RESULT: installer validation passed')
