from pathlib import Path
import subprocess,shlex,json
root=Path(__file__).resolve().parents[2]
access=root/'ssh-access'
options=['-i',str(access/'id_ed25519'),'-o','IdentitiesOnly=yes','-o','BatchMode=yes','-o','ConnectTimeout=8','-o','HostKeyAlias=iMac-de-xuso-2.local','-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile='+str(access/'known_hosts')]
version=(root/'VERSION').read_text().strip()
host='xuso@iMac-de-xuso-2.local'; remote='/private/tmp/PRISON-DISPLAY-native-'+version
names=['IntelDecoderTests','IntelPairingTests','IntelPointerTests','DesktopTests-x86_64','RecoveryTests-x86_64','GraphicsSafetyTests-x86_64','CursorTests-x86_64','PriorityTests-x86_64','PointerViewTests-x86_64','ReconnectTests-x86_64','PreferencesTests-x86_64','InteractiveTests-x86_64','PresentationTests-x86_64']
subprocess.run(['ssh']+options+[host,'mkdir -p '+remote+'/build'],check=True)
subprocess.run(['scp']+options+[str(root/'build'/name) for name in names]+[host+':'+remote+'/'],check=True)
subprocess.run(['scp']+options+[str(root/'build/CoreTests-vectors.dat'),str(root/'build/CoreTests-sample.dat'),host+':'+remote+'/build/'],check=True)
results=[]
with (root/('build/catalina-ready-'+version+'.log')).open('w') as log:
    for name in names:
        args=['./'+name]+(['build/CoreTests-vectors.dat'] if name=='IntelDecoderTests' else [])
        result=subprocess.run(['ssh']+options+[host,'cd '+remote+' && '+shlex.join(args)],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=90)
        log.write('TEST '+name+'\n'+result.stdout+'\n');log.flush()
        row={'test':name,'exit':result.returncode,'passes':result.stdout.count('PASS:'),'failures':result.stdout.count('FAIL:')}
        print(json.dumps(row),flush=True);results.append(row)
        if result.returncode:raise RuntimeError('Native Catalina check failed: '+name)
(root/('build/catalina-ready-'+version+'.json')).write_text(json.dumps(results,indent=2))
