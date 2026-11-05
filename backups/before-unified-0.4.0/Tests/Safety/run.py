"""Bound a diagnostic and stop only its own process group if graphics stalls."""
from pathlib import Path
import argparse,os,signal,subprocess,time,json

p=argparse.ArgumentParser();p.add_argument('--seconds',type=float,default=180)
p.add_argument('--profile-budget',type=int,default=3);p.add_argument('command',nargs=argparse.REMAINDER)
a=p.parse_args();command=a.command[1:] if a.command[:1]==['--'] else a.command
if not command:p.error('a diagnostic command is required')
def profiles():
    return {x.name for x in Path('/Library/ColorSync/Profiles/Displays').glob('*.icc') if x.name.startswith(('PRISON DISPLAY','AireDisplay'))}
baseline=profiles();start=time.monotonic();overloaded=0;failure=None
proc=subprocess.Popen(command,start_new_session=True)
try:
    while proc.poll() is None:
        time.sleep(1)
        cpu=0.0
        rows=subprocess.check_output(['ps','-axo','%cpu=,comm='],text=True)
        for row in rows.splitlines():
            fields=row.split(None,1)
            if len(fields)==2 and Path(fields[1]).name in ('colorsync.displayservices','colorsyncd'):
                cpu+=float(fields[0])
        overloaded=overloaded+1 if cpu>85 else 0
        added=len(profiles()-baseline)
        if time.monotonic()-start>a.seconds:failure='diagnostic deadline exceeded'
        elif overloaded>=5:failure='sustained ColorSync CPU overload'
        elif added>a.profile_budget:failure='virtual display identity budget exceeded'
        if failure:
            print('SAFETY STOP:',failure,flush=True);os.killpg(proc.pid,signal.SIGTERM)
            try:proc.wait(timeout=2)
            except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);proc.wait(timeout=3)
            break
    print('SAFETY RESULT',json.dumps({'seconds':round(time.monotonic()-start,2),'newProfiles':len(profiles()-baseline),'exit':proc.returncode,'stop':failure}),flush=True)
finally:
    if proc.poll() is None:
        os.killpg(proc.pid,signal.SIGKILL);proc.wait(timeout=3)
raise SystemExit(1 if failure else proc.returncode)
