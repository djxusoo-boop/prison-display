from pathlib import Path
import subprocess,plistlib,shutil,json,hashlib

root=Path(__file__).resolve().parents[1]
version=(root/'VERSION').read_text().strip()
out=root/'outputs'/f'PRISON-DISPLAY-v{version}'
folder=root/'build'/f'installer-verification-{version}'
certificate_fingerprint=json.loads((root/'Signing/identity.json').read_text())['certificateSHA1'].lower()

def inventory(directory):
 result={}
 for path in directory.rglob('*'):
  relative=str(path.relative_to(directory))
  if path.is_symlink(): result[relative]=('link',str(path.readlink()))
  elif path.is_file(): result[relative]=('file',hashlib.sha256(path.read_bytes()).hexdigest())
 return result

if folder.exists():shutil.rmtree(folder)
folder.mkdir()
for row in json.loads((out/'manifest.json').read_text()):
 pkg=out/row['file'];assert hashlib.sha256(pkg.read_bytes()).hexdigest()==row['sha256'];dest=folder/row['role']
 subprocess.run(['pkgutil','--expand-full',str(pkg),str(dest)],check=True,capture_output=True)
 apps=list(dest.rglob('*.app'));assert len(apps)==1;app=apps[0];original=root/'build'/app.name
 info=plistlib.loads((app/'Contents/Info.plist').read_bytes());assert info['CFBundleShortVersionString']==version
 assert info['CFBundleVersion']==version
 assert info['LSMinimumSystemVersionByArchitecture']=={'arm64':'11.0','x86_64':'10.13'}
 assert info['CFBundleIdentifier']=='local.airedisplay.'+('Sender' if row['role']=='MacBook' else 'Receiver')
 binary=app/'Contents/MacOS/AireDisplay'
 assert set(subprocess.check_output(['lipo','-archs',str(binary)],text=True).split())=={'arm64','x86_64'}
 dependencies=subprocess.check_output(['otool','-arch','x86_64','-L',str(binary)],text=True)
 assert all('/'+framework+'/' not in dependencies for framework in ['Network.framework','CryptoKit.framework','ScreenCaptureKit.framework'])
 assert (app/'Contents/Frameworks/libswiftCore.dylib').is_file()
 for library in (app/'Contents/Frameworks').glob('*.dylib'):
  requirement=subprocess.run(['codesign','-d','-r-',str(library)],check=True,capture_output=True,text=True)
  assert certificate_fingerprint in (requirement.stdout+requirement.stderr).lower()
 assert inventory(app)==inventory(original), 'packaged app differs from the signed build'
 assert (app/'Contents/_CodeSignature/CodeResources').is_file()
 requirement=subprocess.run(['codesign','-d','-r-',str(app)],check=True,capture_output=True,text=True)
 assert certificate_fingerprint in (requirement.stdout+requirement.stderr).lower()
 for name in ['MacOS/AireDisplay','Resources/PrisonLogo.jpg','Resources/PrisonDisplay.icns']:assert (app/'Contents'/name).read_bytes()==(original/'Contents'/name).read_bytes()
 for path in dest.rglob('*'):
  assert path.suffix not in ['.p12','.pem','.key','.keychain-db'] and path.name not in ['id_ed25519','keychain-password']
 print('PASS:',row['role'],'version, exact app payload, pinned signer identity, logo, icon and private-key exclusion')
print('RESULT: installer validation passed')
