from pathlib import Path
import subprocess,tempfile,time,json,re,argparse
root=Path(__file__).resolve().parents[2];access=root/'ssh-access'
opts=['-i',str(access/'id_ed25519'),'-o','IdentitiesOnly=yes','-o','BatchMode=yes','-o','ConnectTimeout=8','-o','HostKeyAlias=iMac-de-xuso-2.local','-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile='+str(access/'known_hosts')]
host='xuso@iMac-de-xuso-2.local';remote='/private/tmp/PRISON-DISPLAY-investigate';rows=[]
mac_ip=subprocess.check_output(['ipconfig','getifaddr','en0'],text=True).strip()
for mode in ['inputbaseline','inputcandidate']:
 subprocess.run(['scp']+opts+[str(root/'build/diagnostics'/(mode+'.zip')),host+':'+remote+'/'],check=True)
 subprocess.run(['ssh']+opts+[host,'ditto -x -k '+remote+'/'+mode+'.zip '+remote],check=True)
for trial,mode in [(1,'inputbaseline'),(1,'inputcandidate'),(2,'inputcandidate'),(2,'inputbaseline')]:
 with tempfile.TemporaryDirectory(prefix='prison-control-',dir='/private/tmp') as folder:
  link=Path(folder)/'input-link.txt';tag=str(trial)+'-'+mode;slog=root/'build'/('control-'+tag+'-sender.log');rlog=root/'build'/('control-'+tag+'-receiver.log')
  with slog.open('w') as log:
   sender=root/'build/diagnostics'/('MacBook-'+mode+'.app/Contents/MacOS/AireDisplay')
   proc=subprocess.Popen([str(sender),str(link),str(root/'build/CoreTests-sample.dat'),mac_ip],stdout=log,stderr=subprocess.STDOUT)
   try:
    end=time.monotonic()+12
    while not link.exists() and time.monotonic()<end:time.sleep(.05)
    if not link.exists():raise RuntimeError('Listener did not start')
    subprocess.run(['scp']+opts+[str(link),host+':'+remote+'/input-link.txt'],check=True)
    with rlog.open('w') as log:
     result=subprocess.run(['ssh']+opts+[host,remote+'/iMac-'+mode+'.app/Contents/MacOS/AireDisplay '+remote+'/input-link.txt 0'],stdout=log,stderr=subprocess.STDOUT,timeout=50)
    match=re.search(r'INPUT RTT (.*)',rlog.read_text());row={'trial':trial,'mode':mode,'exit':result.returncode,'measurement':match.group(1) if match else None}
    rows.append(row);(root/'build/control-comparison-0.3.14.json').write_text(json.dumps(rows,indent=2));print(json.dumps(row),flush=True)
    if result.returncode:raise RuntimeError('Control trial failed')
   finally:
    if proc.poll() is None:proc.terminate();proc.wait(timeout=5)
    subprocess.run(['ssh']+opts+[host,'rm -f '+remote+'/input-link.txt'],check=False,stdout=subprocess.DEVNULL)
