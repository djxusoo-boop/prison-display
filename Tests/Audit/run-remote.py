from pathlib import Path
import concurrent.futures
import subprocess
import tarfile

root = Path(__file__).resolve().parents[2]
version = (root/'VERSION').read_text().strip()
folder = root/'build'/('audit-'+version)
archive = folder.with_suffix('.tgz')
with tarfile.open(archive, 'w:gz', format=tarfile.GNU_FORMAT) as output:
    output.add(folder, arcname=folder.name)
base = ['ssh','-i',str(root/'ssh-access/id_ed25519'),'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile='+str(root/'ssh-access/known_hosts'),'-o','ConnectTimeout=5']

def run(item):
    label, alias, host = item
    cmd = base+['-o','HostKeyAlias='+alias,host]
    with archive.open('rb') as stream:
        subprocess.run(cmd+['mkdir -p /private/tmp/prison-audit-20261014 && LC_ALL=C tar -xzf - -C /private/tmp/prison-audit-20261014'], stdin=stream, check=True)
    script = 'cd /private/tmp/prison-audit-20261014/'+folder.name+' || exit 1; result=0; for test in Preferences Startup Reconnect Interactive Presentation PointerView; do ./$test > "$test.log" 2>&1; code=$?; echo "$test exit=$code"; tail -2 "$test.log"; if [ "$code" != 0 ]; then result=1; tail -15 "$test.log"; fi; done; ./Workspace --layout-preview > Workspace.log 2>&1; code=$?; echo "Workspace exit=$code"; tail -5 Workspace.log; if [ "$code" != 0 ]; then result=1; fi; exit "$result"'
    result = subprocess.run(cmd+[script], capture_output=True, text=True, timeout=180)
    (root/'build'/('audit-20261014-'+label+'-final.log')).write_text(result.stdout+result.stderr)
    print(label, 'exit', result.returncode, result.stdout, flush=True)
    return result.returncode
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(run, [('pro','macbook-pro-xuso-2014.local','xusoprison@192.168.1.141'),('imac','imac-de-xuso-2.local','xuso@iMac-de-xuso-2.local')]))
raise SystemExit(1 if any(results) else 0)
