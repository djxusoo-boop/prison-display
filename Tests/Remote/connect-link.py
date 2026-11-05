from pathlib import Path
import subprocess,shlex,urllib.parse
root=Path(__file__).resolve().parents[2];version=(root/'VERSION').read_text().strip()
link=subprocess.check_output(['/usr/bin/pbpaste'],text=True).strip();u=urllib.parse.urlparse(link)
assert u.scheme=='airedisplay' and u.netloc=='connect' and urllib.parse.parse_qs(u.query).get('version')==[version]
a=root/'ssh-access';args=['ssh','-i',str(a/'id_ed25519'),'-o','IdentitiesOnly=yes','-o','BatchMode=yes','-o','ConnectTimeout=8','-o','HostKeyAlias=iMac-de-xuso-2.local','-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile='+str(a/'known_hosts'),'xuso@10.0.0.5','sh']
app=f'/private/tmp/PRISON-DISPLAY-test-{version}/PRISON DISPLAY iMac.app'
p=subprocess.run(args,input='open -a '+shlex.quote(app)+' '+shlex.quote(link)+'\n',text=True,capture_output=True)
print('Enlace temporal entregado al receptor de prueba del iMac' if p.returncode==0 else 'Error al entregar el enlace')
raise SystemExit(p.returncode)
