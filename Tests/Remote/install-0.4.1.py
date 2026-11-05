from pathlib import Path
import subprocess,shlex
root=Path(__file__).resolve().parents[2]
for alias,host,role in [('macbook-pro-xuso-2014.local','xusoprison@192.168.1.141','MacBook'),('iMac-de-xuso-2.local','xuso@iMac-de-xuso-2.local','iMac')]:
    source='/private/tmp/PRISON-DISPLAY-install-0.4.1/PRISON DISPLAY '+role+'.app'
    destination='/Applications/PRISON DISPLAY '+role+'.app'
    backup='/private/tmp/PRISON-DISPLAY-install-0.4.1/previous-'+role+'.app'
    program='''import os,subprocess
source=%r
destination=%r
backup=%r
subprocess.check_call(['codesign','--verify','--strict',source])
if subprocess.call(['pgrep','-x','AireDisplay'],stdout=open(os.devnull,'w')) == 0:
    raise RuntimeError('PRISON DISPLAY sigue abierto; no se reemplazara una app activa')
if os.path.exists(backup): raise RuntimeError('Ya existe la copia anterior; no se sobrescribira')
had_previous=os.path.exists(destination)
if had_previous: os.rename(destination,backup)
try:
    os.rename(source,destination)
    subprocess.check_call(['codesign','--verify','--strict',destination])
except:
    if os.path.exists(destination): os.rename(destination,source)
    if had_previous: os.rename(backup,destination)
    raise
subprocess.check_call(['/usr/libexec/PlistBuddy','-c','Print CFBundleShortVersionString',destination+'/Contents/Info.plist'])
subprocess.check_call(['open','-a',destination])
print('INSTALLED_AND_OPENED',destination)
'''%(source,destination,backup)
    args=['ssh','-T','-i','ssh-access/id_ed25519','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-o','ConnectTimeout=8','-o','HostKeyAlias='+alias,'-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile=ssh-access/known_hosts',host,'/usr/bin/python -c '+shlex.quote(program)]
    subprocess.run(args,cwd=root,check=True)
