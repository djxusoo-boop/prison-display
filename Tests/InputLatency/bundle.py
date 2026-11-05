from pathlib import Path
import shutil,subprocess,plistlib
root=Path(__file__).resolve().parents[2]
folder=Path('/private/tmp/PRISON-DISPLAY-input-benchmark')
folder.mkdir(exist_ok=True)
for mode,version in [('old','0.3.11'),('new','0.3.12')]:
 for role, binary in [('MacBook','InputLatencySender-'+mode),('iMac','InputLatencyReceiver' if mode=='old' else 'InputLatencyReceiver-new')]:
  app=folder/(role+'-'+mode+'.app')
  if app.exists():shutil.rmtree(app)
  shutil.copytree(root/'build'/('PRISON DISPLAY '+role+'.app'),app)
  shutil.copy2(root/'build'/binary,app/'Contents/MacOS/AireDisplay')
  info=plistlib.loads((app/'Contents/Info.plist').read_bytes());info['CFBundleShortVersionString']=version;info['CFBundleVersion']=version
  (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
  subprocess.run(['python3',str(root/'Signing/sign.py'),str(app)],check=True)
  subprocess.run(['codesign','--verify','--strict',str(app)],check=True)
  if role=='iMac':subprocess.run(['ditto','-c','-k','--keepParent',str(app),str(root/'build'/('input-'+mode+'.zip'))],check=True)
print('PASS: temporary diagnostic apps use existing persistent app identities')
