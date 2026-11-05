from pathlib import Path
import subprocess,time,json,re,tempfile,statistics,shlex
root=Path(__file__).resolve().parents[2]; access=root/'ssh-access'
opts=['-i',str(access/'id_ed25519'),'-o','IdentitiesOnly=yes','-o','BatchMode=yes','-o','ConnectTimeout=8','-o','HostKeyAlias=iMac-de-xuso-2.local','-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile='+str(access/'known_hosts')]
host='xuso@192.168.1.83'; remote='/private/tmp/PRISON-DISPLAY-router2-tests'; results=[]
subprocess.run(['ssh']+opts+[host,'mkdir -p '+remote],check=True)
subprocess.run(['scp']+opts+[str(root/'build/PerfReceiver-window-final'),host+':'+remote+'/'],check=True)
for trial in range(1,3):
 for route in (['direct','router'] if trial % 2 else ['router','direct']):
  with tempfile.TemporaryDirectory(prefix='prison-route-') as temp:
   link=Path(temp)/'synthetic-link.txt'; slog=root/'build'/f'router2-{trial}-{route}-sender.log'; rlog=root/'build'/f'router2-{trial}-{route}-imac.log'
   with slog.open('w') as out:
    sender=subprocess.Popen([str(root/'build/PerfSender-window-final'),str(link),'6000000','30']+['one-image'],stdout=out,stderr=subprocess.STDOUT)
    try:
     end=time.monotonic()+12
     while not link.exists() and time.monotonic()<end:time.sleep(.05)
     if not link.exists():raise RuntimeError('Synthetic sender failed to start')
     subprocess.run(['scp']+opts+[str(link),host+':'+remote+'/'],check=True,timeout=15)
     with rlog.open('w') as out:
      result=subprocess.run(['ssh']+opts+[host,remote+'/PerfReceiver-window-final '+remote+'/'+link.name+(' router' if route=='router' else '')],stdout=out,stderr=subprocess.STDOUT,timeout=50)
     sender.wait(timeout=10)
     rtts=[float(x) for x in re.findall(r'ida/vuelta ([\d.]+) ms',slog.read_text())]
     text=rlog.read_text(); row={'trial':trial,'route':route,'exit':result.returncode,'rttMedianMS':statistics.median(rtts) if rtts else None,'rttMaxMS':max(rtts) if rtts else None,'video':next((l for l in text.splitlines() if l.startswith('RESULT ')),''),'cursor':next((l for l in text.splitlines() if l.startswith('CURSOR RESULT ')),''),'cursorRTT':next((l for l in text.splitlines() if l.startswith('CURSOR RTT ')),''),'frameRTT':next((l for l in slog.read_text().splitlines() if l.startswith('FRAME RTT ')),''),'path':next((l for l in text.splitlines() if l.startswith('ROUTE ')),'')}
     results.append(row);(root/'build/router2-comparison.json').write_text(json.dumps(results,indent=2));print(json.dumps(row),flush=True)
     if result.returncode:raise RuntimeError('Receiver test failed')
    finally:
     if sender.poll() is None:sender.terminate();sender.wait(timeout=5)
     subprocess.run(['ssh']+opts+[host,'rm -f '+shlex.quote(remote+'/'+link.name)],timeout=10,stdout=subprocess.DEVNULL)
