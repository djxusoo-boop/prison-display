from pathlib import Path
import subprocess,shutil,tempfile
root=Path(__file__).resolve().parents[2]
def call(args):return subprocess.run(args,capture_output=True,text=True)
def requirement(app):
 p=call(['codesign','-d','-r-',str(app)])
 return (p.stdout+p.stderr).split('designated => ')[1].splitlines()[0].strip()
for role in ['MacBook','iMac']:
 old=root/f'build/permission-transition-0.3.3/PRISON DISPLAY {role}.app';new=root/f'build/PRISON DISPLAY {role}.app'
 expected=requirement(old)
 assert expected==requirement(new) and 'certificate leaf' in expected and 'cdhash' not in expected
 assert (old/'Contents/MacOS/AireDisplay').read_bytes()!=(new/'Contents/MacOS/AireDisplay').read_bytes()
 for app in [old,new]:
  p=call(['codesign','--verify','--strict','--all-architectures','-R','='+expected,str(app)]);assert p.returncode==0,p.stderr
  with tempfile.TemporaryDirectory(dir=root/'build') as folder:
   prefix=str(Path(folder)/'cert-');p=call(['codesign','-d','--extract-certificates='+prefix,str(app)]);assert p.returncode==0,p.stderr
   assert Path(prefix+'0').read_bytes()==(root/'Signing/certificate.der').read_bytes()
 print('PASS:',role,'two different executables match the same certificate requirement')
 if role=='MacBook':
  oldAdhoc=root/'build/rejected-adhoc.app'
  if oldAdhoc.exists():shutil.rmtree(oldAdhoc)
  shutil.copytree(new,oldAdhoc)
  p=call(['codesign','--force','--sign','-',str(oldAdhoc)]);assert p.returncode==0,p.stderr
  p=call(['codesign','--verify','-R','='+expected,str(oldAdhoc)]);assert p.returncode!=0
  print('PASS: ad hoc app with same identifier is rejected')
  with tempfile.TemporaryDirectory(dir=root/'build') as folder:
   altered=Path(folder)/'Changed.app';shutil.copytree(new,altered)
   (altered/'Contents/Resources/PrisonLogo.jpg').write_bytes(b'test tampering')
   p=call(['codesign','--verify','--strict',str(altered)]);assert p.returncode!=0
   print('PASS: modified sealed resource is rejected')
print('RESULT: signing continuity and negative checks passed')
