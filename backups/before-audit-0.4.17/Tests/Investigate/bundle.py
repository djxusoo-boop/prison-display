from pathlib import Path
import argparse,shutil,subprocess,plistlib
root=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('mode');p.add_argument('version');p.add_argument('sender');p.add_argument('receiver');a=p.parse_args()
folder=root/'build'/'diagnostics';folder.mkdir(exist_ok=True)
for role,binary in [('MacBook',a.sender),('iMac',a.receiver)]:
 app=folder/(role+'-'+a.mode+'.app')
 if app.exists():shutil.rmtree(app)
 template=next((root/'build/installer-verification-0.3.13'/role).rglob('*.app'))
 shutil.copytree(template,app)
 shutil.copy2(root/'build'/binary,app/'Contents/MacOS/AireDisplay')
 info=plistlib.loads((app/'Contents/Info.plist').read_bytes());info['CFBundleShortVersionString']=a.version;info['CFBundleVersion']=a.version
 (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
 subprocess.run(['python3',str(root/'Signing/sign.py'),str(app)],check=True)
 subprocess.run(['codesign','--verify','--strict',str(app)],check=True)
 if role=='iMac': subprocess.run(['ditto','-c','-k','--keepParent',str(app),str(folder/(a.mode+'.zip'))],check=True)
