from pathlib import Path
import subprocess,tempfile,time,json,re,shlex,argparse
root=Path(__file__).resolve().parents[2];access=root/'ssh-access'
p=argparse.ArgumentParser();p.add_argument('mode');p.add_argument('route',choices=['router','direct','host']);p.add_argument('flight',choices=['one-image','two-images','three-images']);p.add_argument('cursor',choices=['inline-cursor','dedicated-cursor']);p.add_argument('--duration',default='12');p.add_argument('--bitrate',default='20000000');p.add_argument('--scene',action='store_true');p.add_argument('--probe',action='store_true');p.add_argument('--width',default='1920');p.add_argument('--height',default='1080');p.add_argument('--fps',default='60');p.add_argument('--detail',action='store_true');p.add_argument('--native',action='store_true');p.add_argument('--settings',action='store_true');p.add_argument('--extend',action='store_true');p.add_argument('--snapshot',action='store_true');p.add_argument('--input-probe',action='store_true');p.add_argument("--permission-probe",action="store_true");p.add_argument("--tuning",default="",choices=["","capture-five","cursor-four","cursor-sixteen","ack-fast","cursor-sixteen+ack-fast","lan-only","peer-wifi"]);a=p.parse_args()
opts=['-i',str(access/'id_ed25519'),'-o','IdentitiesOnly=yes','-o','BatchMode=yes','-o','ConnectTimeout=8','-o','HostKeyAlias=iMac-de-xuso-2.local','-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile='+str(access/'known_hosts')]
host='xuso@iMac-de-xuso-2.local';remote='/private/tmp/PRISON-DISPLAY-investigate';tag='-'.join([a.mode,a.route,a.flight,a.cursor])
mac_ip=subprocess.check_output(['ipconfig','getifaddr','en0'],text=True).strip()
subprocess.run(['ssh']+opts+[host,'mkdir -p '+remote],check=True)
subprocess.run(['scp']+opts+[str(root/'build/diagnostics'/(a.mode+'.zip')),host+':'+remote+'/'],check=True)
subprocess.run(['ssh']+opts+[host,'ditto -x -k '+remote+'/'+a.mode+'.zip '+remote],check=True)
with tempfile.TemporaryDirectory(prefix='prison-video-',dir='/private/tmp') as folder:
 link=Path(folder)/'link.txt';slog=root/'build'/('video-'+tag+'-sender.log');rlog=root/'build'/('video-'+tag+'-receiver.log')
 with slog.open('w') as log:
  sender=root/'build/diagnostics'/('MacBook-'+a.mode+'.app/Contents/MacOS/AireDisplay')
  proc=subprocess.Popen([str(sender),str(link),a.bitrate,a.duration,a.flight,a.cursor]+(['scene'] if a.scene else [])+['w='+a.width,'h='+a.height,'fps='+a.fps]+(['detail'] if a.detail else [])+(['native-cursor'] if a.native else [])+(['settings'] if a.settings else [])+(['extend'] if a.extend else [])+(['input-probe'] if a.input_probe else [])+(['permission-probe'] if a.permission_probe else [])+(a.tuning.split("+") if a.tuning else []),stdout=log,stderr=subprocess.STDOUT)
  try:
   end=time.monotonic()+120
   while not link.exists() and time.monotonic()<end:time.sleep(.05)
   if not link.exists():raise RuntimeError('Listener did not start; see sender log')
   # Explicit LAN trials use the current IPv4, avoiding stale DHCP and AWDL resolution.
   if a.route=='router':
    import urllib.parse
    url=urllib.parse.urlsplit(link.read_text()); items=urllib.parse.parse_qsl(url.query); items=[(k,mac_ip if k=='host' else v) for k,v in items]; link.write_text(urllib.parse.urlunsplit((url.scheme,url.netloc,url.path,urllib.parse.urlencode(items),url.fragment)))
   subprocess.run(['scp']+opts+[str(link),host+':'+remote+'/link.txt'],check=True)
   with rlog.open('w') as log:
    result=subprocess.run(['ssh']+opts+[host,remote+'/iMac-'+a.mode+'.app/Contents/MacOS/AireDisplay '+remote+'/link.txt '+a.route+(' probe' if a.probe else '')+(' snapshot' if a.snapshot else '')+(' input-probe' if a.input_probe else '')+(' '+a.tuning.replace("+"," ") if a.tuning else '')+' duration='+a.duration],stdout=log,stderr=subprocess.STDOUT,timeout=max(210,float(a.duration)+45))
   proc.wait(timeout=10)
   print(json.dumps({'case':tag,'receiverExit':result.returncode,'senderExit':proc.returncode,'sender':[x for x in slog.read_text().splitlines() if x.startswith(('METRIC','FRAME RTT','PIPELINE','STATUS','VIDEO BYTES','SETTINGS STEP'))],'receiver':[x for x in rlog.read_text().splitlines() if x.startswith(('ROUTE','RESULT','RENDER RESULT','IMAGE RESULT','INPUT RTT','CURSOR RESULT','CURSOR dedicated','CURSOR MODE','FORMAT','STATUS','ERROR'))]},ensure_ascii=False),flush=True)
   if result.returncode or proc.returncode:raise RuntimeError('Video trial failed')
   if a.scene:
    frame=re.search(r'RESULT version=[^ ]+ frames=(\d+) presented=(\d+) fps=([0-9.]+)',rlog.read_text())
    span=re.search(r'IMAGE RESULT spanSeconds=([0-9.]+)',rlog.read_text())
    expected=64.0 if a.settings else float(a.duration)
    if not frame or not span or float(frame[3])<5 or float(span[1])<expected-3:raise RuntimeError('Moving-scene capture did not remain continuous for the required duration')
    print('CONTINUITY PASS: moving image received throughout the requested trial',flush=True)
  finally:
   if proc.poll() is None:proc.terminate();proc.wait(timeout=5)
   subprocess.run(['ssh']+opts+[host,'rm -f '+remote+'/link.txt'],check=False,stdout=subprocess.DEVNULL)
