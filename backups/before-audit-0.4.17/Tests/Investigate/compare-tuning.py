"""Sequential comparisons; compile first so builds never compete with video."""
from pathlib import Path
import subprocess, json, argparse, shutil

root = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
p.add_argument('modes', nargs='+')
p.add_argument('--duration', default='20')
a = p.parse_args()
version = (root/'VERSION').read_text().strip()
folder = root/'build'/('tuning-'+version)
rows = []
for n, mode in enumerate(a.modes):
    tag = 'tune-'+mode
    r = subprocess.run(['python3','Tests/Safety/run.py','--seconds','65','--profile-budget','0','--','python3','Tests/Investigate/video.py',tag,'router','two-images','dedicated-cursor','--duration',a.duration,'--bitrate','40000000','--scene','--detail','--extend'],cwd=root,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=70)
    (folder/(str(n)+'-'+mode+'.log')).write_text(r.stdout)
    for f in (root/'build').glob('video-'+tag+'-router-two-images-dedicated-cursor-*.log'):
        shutil.copy2(f,folder/(str(n)+'-'+f.name))
    lines = r.stdout.splitlines()
    data = next((json.loads(x) for x in lines if x.startswith('{"case"')), {})
    row = {'trial':n,'mode':mode,'exit':r.returncode,'summary':[s for k in ('sender','receiver') for s in data.get(k,[]) if s.startswith(('FRAME RTT','PIPELINE','RESULT','IMAGE RESULT','CURSOR RESULT'))]}
    rows.append(row)
    (folder/'comparisons.json').write_text(json.dumps(rows,indent=2))
    print(json.dumps(row),flush=True)
    if r.returncode:
        print(r.stdout[-1500:],flush=True)
        raise RuntimeError('Comparison failed')
