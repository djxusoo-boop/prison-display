"""Approved-only removal using ColorSync API; never edit the system cache."""
from pathlib import Path
import argparse,subprocess,json,hashlib,os,time,plistlib,re
p=argparse.ArgumentParser();p.add_argument('mode',choices=['inspect','unregister']);p.add_argument('backup',type=Path);a=p.parse_args()
b=a.backup.resolve();plan=json.loads((b/'device-unregister-plan.json').read_text()); m=json.loads((b/'manifest.json').read_text()); old={r['name']:r for r in m['profiles']}; original=plistlib.loads((b/'device-registry-original.plist').read_bytes())
assert hashlib.sha256((b/'device-registry-original.plist').read_bytes()).hexdigest()==plan['cache_sha256']
assert len(plan['selected'])==297 and len({r['uuid'] for r in plan['selected']})==297
protected={(1280<<16)|720,(1920<<16)|1080,(2560<<16)|1440,(3200<<16)|1800,(3840<<16)|2160}
for r in plan['selected']:
 assert r['profile_name'] in old and r['serial']==old[r['profile_name']]['serial'] and r['serial'] not in protected
 assert hashlib.sha256((b/'quarantine'/r['profile_name']).read_bytes()).hexdigest()==old[r['profile_name']]['sha256']
 assert r['cache_key']=='Device.mntr.'+r['uuid'] and r['cache_key'] in original
 assert re.fullmatch(r'[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}',r['uuid'])
 assert r['profile_name'].endswith(r['uuid']+'.icc')
 factory=original[r['cache_key']]['FactoryProfiles']
 urls=[v.get('DeviceProfileURL','') for v in factory.values() if isinstance(v,dict)]
 assert len(urls)==1 and Path(urls[0]).name==r['profile_name']
assert not any('--virtual-display-helper' in l and 'unregister.py' not in l for l in subprocess.check_output(['/bin/ps','-axo','args='],text=True).splitlines())
if a.mode=='unregister': assert os.geteuid()==0
rows=plan['selected'][:1] if a.mode=='inspect' else plan['selected']; results=[]; start=time.monotonic()
try:
 for r in rows:
  assert time.monotonic()-start<90,'Maintenance deadline exceeded'
  result=subprocess.run([str(Path('build/ColorRegistryMaintenance').resolve()),a.mode,str(b),r['uuid']],capture_output=True,text=True,timeout=3)
  results.append({'uuid':r['uuid'],'exit':result.returncode,'result':result.stdout.strip()})
  assert result.returncode==0,'API refused or could not verify selected device; stopped'
 print('RESULT:',a.mode,len(results),'reviewed devices; no system cache edited')
finally:
 (b/('device-'+a.mode+'-results.json')).write_text(json.dumps(results,indent=2))
