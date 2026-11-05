import subprocess,json
from pathlib import Path
results=[]
for mode in ['realold','realnew','realnew','realold']:
 r=subprocess.run(['python3','Tests/Investigate/video.py',mode,'direct','two-images','dedicated-cursor','--duration','18','--bitrate','20000000','--scene','--detail'],capture_output=True,text=True)
 if r.returncode:
  print(r.stdout[-1500:],r.stderr[-1000:],flush=True);raise SystemExit(1)
 result=json.loads(r.stdout.splitlines()[-1]);results.append(result)
 Path('build/real-comparison-0.3.15.json').write_text(json.dumps(results,indent=2))
 print(mode,result['receiver'],result['sender'][-1:],flush=True)
