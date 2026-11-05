import pathlib, subprocess, time, re, json
root = pathlib.Path(__file__).resolve().parents[2]
workspace = root.parents[1]
access = root / 'ssh-access'
ssh = ['ssh', '-i', str(access/'id_ed25519'), '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', '-o', 'StrictHostKeyChecking=yes', '-o', 'UserKnownHostsFile='+str(access/'known_hosts')]
scp = ['scp', '-i', str(access/'id_ed25519'), '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'UserKnownHostsFile='+str(access/'known_hosts')]
host = 'xuso@iMac-de-xuso-2.local'
remote = '/private/tmp/AireDisplay-diagnostico-0.2.1'
results=[]
for trial in range(1, 4):
    for version in ['0.2.6','0.2.7']:
        link=pathlib.Path('/private/tmp/AireDisplay-compare-'+version+'.txt')
        link.unlink(missing_ok=True)
        server_log=root/'build'/('compare-final27-'+version+'-'+str(trial)+'-sender.log')
        receiver_log=root/'build'/('compare-final27-'+version+'-'+str(trial)+'-imac.log')
        with server_log.open('w') as output:
            sender=subprocess.Popen([str(root/'build'/('PerfSender-'+version)),str(link),'20000000','15'],stdout=output,stderr=subprocess.STDOUT)
            try:
                end=time.monotonic()+10
                while not link.exists() and time.monotonic()<end: time.sleep(0.05)
                if not link.exists(): raise RuntimeError('server not ready')
                subprocess.run(scp+[str(link),host+':'+remote+'/'],check=True,timeout=30,stdout=subprocess.DEVNULL)
                with receiver_log.open('w') as received:
                    status=subprocess.run(ssh+[host,remote+'/PerfReceiver-'+version+' '+remote+'/'+link.name],stdout=received,stderr=subprocess.STDOUT,timeout=55)
                sender.wait(timeout=10)
                text=receiver_log.read_text()
                result=re.search(r'RESULT .*fps=([\d.]+).*decodeMedianMS=([\d.]+)',text)
                samples=[float(v) for v in re.findall(r'ida/vuelta ([\d.]+) ms',server_log.read_text())]
                row={'trial':trial,'version':version,'exit':status.returncode,'fps':float(result[1]) if result else None,'decodeMedianMS':float(result[2]) if result else None,'rttMedianSampleMS':sorted(samples)[len(samples)//2] if samples else None,'rttWorstSampleMS':max(samples) if samples else None,'route':next((v for v in text.splitlines() if v.startswith('ROUTE')),'not recorded')}
                results.append(row)
                (root/'build'/'performance-comparison-0.2.7.json').write_text(json.dumps(results,indent=2))
                print(json.dumps(row),flush=True)
            finally:
                if sender.poll() is None: sender.terminate(); sender.wait(timeout=5)
                link.unlink(missing_ok=True)
print('COMPARISON COMPLETE',flush=True)
