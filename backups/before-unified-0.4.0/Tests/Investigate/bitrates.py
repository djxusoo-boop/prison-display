"""Balanced real-capture trials; bitratetest disables adaptation only in its frozen diagnostic source."""
import subprocess,json
from pathlib import Path
results=[]
for rate in [20000000,40000000,60000000,12000000,12000000,60000000,40000000,20000000]:
 r=subprocess.run(['python3','Tests/Investigate/video.py','bitratetest','direct','two-images','dedicated-cursor','--duration','15','--bitrate',str(rate),'--scene','--detail'],capture_output=True,text=True)
 if r.returncode:
  print(r.stdout[-2000:],r.stderr[-1200:],flush=True);raise SystemExit(1)
 result=json.loads(r.stdout.splitlines()[-1]);result['fixedTarget']=rate;results.append(result)
 Path('build/bitrate-comparison-2026-10-08.json').write_text(json.dumps(results,indent=2))
 print('DONE',rate,result['receiver'],result['sender'][-2:],flush=True)
