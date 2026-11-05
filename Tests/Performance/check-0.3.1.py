from pathlib import Path
import subprocess,time,json,re
root=Path(__file__).resolve().parents[2]
access=root/'ssh-access'
options=['-i',str(access/'id_ed25519'),'-o','IdentitiesOnly=yes','-o','BatchMode=yes','-o','ConnectTimeout=8','-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile='+str(access/'known_hosts')]
host='xuso@iMac-de-xuso-2.local'; remote='/private/tmp/AireDisplay-diagnostico-0.2.1'
link=Path('/private/tmp/PrisonDisplay-check-0.3.1.txt')
link.unlink(missing_ok=True)
with (root/'build/wifi-0.3.1-sender.log').open('w') as log:
    sender=subprocess.Popen([str(root/'build/PerfSender-0.3.1'),str(link),'6000000','15'],stdout=log,stderr=subprocess.STDOUT)
    try:
        deadline=time.monotonic()+10
        while not link.exists() and time.monotonic()<deadline: time.sleep(.05)
        if not link.exists(): raise RuntimeError('No se inició el emisor de prueba')
        subprocess.run(['scp']+options+[str(link),host+':'+remote+'/'],check=True,timeout=20)
        with (root/'build/wifi-0.3.1-imac.log').open('w') as output:
            result=subprocess.run(['ssh']+options+[host,remote+'/PerfReceiver-0.3.1 '+remote+'/'+link.name],stdout=output,stderr=subprocess.STDOUT,timeout=45)
        sender.wait(timeout=10)
        received=(root/'build/wifi-0.3.1-imac.log').read_text()
        metrics=(root/'build/wifi-0.3.1-sender.log').read_text()
        print(received)
        values=[float(v) for v in re.findall(r'ida/vuelta ([\d.]+) ms',metrics)]
        if values: print('RTT median sample ms',sorted(values)[len(values)//2],'max',max(values))
        if result.returncode: raise RuntimeError('Falló la recepción')
    finally:
        if sender.poll() is None: sender.terminate(); sender.wait(timeout=5)
        link.unlink(missing_ok=True)
        subprocess.run(['ssh']+options+[host,'rm -f '+remote+'/'+link.name],timeout=15)
