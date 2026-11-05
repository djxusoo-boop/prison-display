from pathlib import Path
import subprocess,time,json,re
root=Path(__file__).resolve().parents[2]; access=root/'ssh-access'
options=['-i',str(access/'id_ed25519'),'-o','IdentitiesOnly=yes','-o','BatchMode=yes','-o','ConnectTimeout=8','-o','HostKeyAlias=iMac-de-xuso-2.local','-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile='+str(access/'known_hosts')]
host='xuso@10.0.0.5'; remote='/private/tmp/AireDisplay-diagnostico-0.2.1'; results=[]
for trial in range(1,2):
    for mode in ['dedicated']:
        link=Path('/private/tmp/PrisonDisplay-cursor-check.txt'); link.unlink(missing_ok=True)
        senderLog=root/'build'/f'cursor-wifi-{trial}-{mode}-sender.log'
        receiverLog=root/'build'/f'cursor-wifi-{trial}-{mode}-imac.log'
        with senderLog.open('w') as log:
            args=[str(root/'build/PerfSender-0.3.2'),str(link),'6000000','15']
            if mode=='inline': args.append('inline-cursor')
            sender=subprocess.Popen(args,stdout=log,stderr=subprocess.STDOUT)
            try:
                end=time.monotonic()+10
                while not link.exists() and time.monotonic()<end: time.sleep(.05)
                if not link.exists(): raise RuntimeError('No sender')
                subprocess.run(['scp']+options+[str(link),host+':'+remote+'/'],check=True,timeout=20)
                with receiverLog.open('w') as output:
                    result=subprocess.run(['ssh']+options+[host,remote+'/PerfReceiver-0.3.2 '+remote+'/'+link.name],stdout=output,stderr=subprocess.STDOUT,timeout=45)
                sender.wait(timeout=10)
                received=receiverLog.read_text()
                row={'trial':trial,'mode':mode,'exit':result.returncode,'video':next((line for line in received.splitlines() if line.startswith('RESULT')),''),'cursor':next((line for line in received.splitlines() if line.startswith('CURSOR RESULT')),''),'route':next((line for line in received.splitlines() if line.startswith('ROUTE')),'')}
                results.append(row); (root/'build/cursor-probe-0.3.2.json').write_text(json.dumps(results,indent=2))
                print(json.dumps(row),flush=True)
                if result.returncode: raise RuntimeError('Receiver failed')
            finally:
                if sender.poll() is None: sender.terminate(); sender.wait(timeout=5)
                link.unlink(missing_ok=True)
subprocess.run(['ssh']+options+[host,'rm -f '+remote+'/PrisonDisplay-cursor-check.txt'],timeout=15)
