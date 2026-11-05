from pathlib import Path
import subprocess,tempfile,time,json,re,shlex
root=Path(__file__).resolve().parents[2];access=root/'ssh-access'
opts=['-i',str(access/'id_ed25519'),'-o','IdentitiesOnly=yes','-o','BatchMode=yes','-o','ConnectTimeout=8','-o','HostKeyAlias=iMac-de-xuso-2.local','-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile='+str(access/'known_hosts')]
host='xuso@192.168.1.83';remote='/private/tmp/PRISON-DISPLAY-input-latency';rows=[]
mac_ip=subprocess.check_output(['ipconfig','getifaddr','en0'],text=True).strip()
subprocess.run(['ssh']+opts+[host,'mkdir -p '+remote],check=True)
subprocess.run(['scp']+opts+[str(root/'build/input-old.zip'),str(root/'build/input-new.zip'),host+':'+remote+'/'],check=True)
subprocess.run(['ssh']+opts+[host,'ditto -x -k '+remote+'/input-old.zip '+remote+'; ditto -x -k '+remote+'/input-new.zip '+remote],check=True)
for trial in (1,2):
 for delay in ((8,0) if trial==1 else (0,8)):
  with tempfile.TemporaryDirectory(prefix='prison-input-') as folder:
   link=Path(folder)/'synthetic-link.txt';slog=root/'build'/f'input-latency-{trial}-{delay}-sender.log';rlog=root/'build'/f'input-latency-{trial}-{delay}-receiver.log'
   with slog.open('w') as log:
    proc=subprocess.Popen(['/private/tmp/PRISON-DISPLAY-input-benchmark/'+('MacBook-old.app' if delay else 'MacBook-new.app')+'/Contents/MacOS/AireDisplay',str(link),str(root/'build/CoreTests-sample.dat'),mac_ip],stdout=log,stderr=subprocess.STDOUT)
    try:
     end=time.monotonic()+10
     while not link.exists() and time.monotonic()<end:time.sleep(.05)
     if not link.exists():raise RuntimeError('Benchmark listener did not start')
     subprocess.run(['scp']+opts+[str(link),host+':'+remote+'/'],check=True,timeout=15)
     with rlog.open('w') as log:
      result=subprocess.run(['ssh']+opts+[host,remote+('/iMac-old.app/Contents/MacOS/AireDisplay ' if delay else '/iMac-new.app/Contents/MacOS/AireDisplay ')+remote+'/'+link.name+' '+str(delay)],stdout=log,stderr=subprocess.STDOUT,timeout=45)
     text=rlog.read_text();match=re.search(r'INPUT RTT (.*)',text)
     row={'trial':trial,'delayMS':delay,'version':'0.3.11' if delay else '0.3.12','exit':result.returncode,'measurement':match.group(1) if match else None}
     rows.append(row);(root/'build/input-latency-comparison.json').write_text(json.dumps(rows,indent=2));print(json.dumps(row),flush=True)
     if result.returncode:raise RuntimeError('Input benchmark failed')
    finally:
     if proc.poll() is None:proc.terminate();proc.wait(timeout=5)
     subprocess.run(['ssh']+opts+[host,'rm -f '+shlex.quote(remote+'/'+link.name)],timeout=10,stdout=subprocess.DEVNULL)
