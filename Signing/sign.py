"""Persistent local signer. Never regenerates a missing identity during a build."""
from pathlib import Path
import hashlib, json, os, re, secrets, subprocess, sys, tempfile

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / '.signing'
PIN = ROOT / 'Signing' / 'identity.json'
KEYCHAIN = PRIVATE / 'prison-display-signing-v2.keychain-db'
KEYCHAIN_PASSWORD = PRIVATE / 'signing-v2-password'

def run(args, **kwargs):
    process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
    try:
        stdout, stderr = process.communicate()
    except KeyboardInterrupt:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill(); process.wait()
        raise
    result = subprocess.CompletedProcess(args, process.returncode, stdout, stderr)
    if process.returncode:
        raise subprocess.CalledProcessError(process.returncode, args, output=stdout, stderr=stderr)
    return result

def initialize():
    if PIN.exists() or PRIVATE.exists():
        raise RuntimeError('La identidad ya existe o quedó una preparación pendiente. No se reemplazará.')
    PRIVATE.mkdir(mode=0o700)
    password = secrets.token_hex(32)
    password_file = KEYCHAIN_PASSWORD
    password_file.write_text(password); password_file.chmod(0o600)
    original = re.findall(r'"([^"]+)"', run(['security','list-keychains','-d','user'],text=True).stdout)
    try:
        with tempfile.TemporaryDirectory(dir=PRIVATE) as tmp:
            folder = Path(tmp); config = folder/'openssl.cnf'; key = folder/'key.pem'; cert = folder/'cert.pem'
            config.write_text('[req]\nprompt=no\ndistinguished_name=dn\nx509_extensions=ext\n[dn]\nCN=PRISON DISPLAY Local Signing\n[ext]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n')
            run(['openssl','req','-x509','-newkey','rsa:3072','-nodes','-sha256','-days','3650','-config',str(config),'-keyout',str(key),'-out',str(cert)])
            der = run(['openssl','x509','-in',str(cert),'-outform','der']).stdout
            fingerprint = hashlib.sha1(der).hexdigest().upper()
            backup = PRIVATE/'identity-backup.p12'
            run(['openssl','pkcs12','-export','-inkey',str(key),'-in',str(cert),'-out',str(backup),'-name','PRISON DISPLAY Local Signing','-passout','file:'+str(password_file),'-macalg','sha1','-keypbe','PBE-SHA1-3DES','-certpbe','PBE-SHA1-3DES'])
            backup.chmod(0o600)
            run(['security','create-keychain','-p',password,str(KEYCHAIN)])
            run(['security','unlock-keychain','-p',password,str(KEYCHAIN)])
            run(['security','import',str(backup),'-k',str(KEYCHAIN),'-P',password,'-x','-T','/usr/bin/codesign'])
            # `codesign` must be present in both the key ACL (-T above) and
            # the partition list; omitting its partition can leave signing
            # blocked while macOS waits for private-key authorization.
            run(['security','set-key-partition-list','-S','apple-tool:,apple:,codesign:','-s','-k',password,str(KEYCHAIN)])
            (ROOT/'Signing/certificate.der').write_bytes(der)
            PIN.write_text(json.dumps({'certificateSHA1':fingerprint,'name':'PRISON DISPLAY Local Signing','keychain':str(KEYCHAIN.relative_to(ROOT))},indent=2)+'\n')
    finally:
        run(['security','list-keychains','-d','user','-s',*original])
    print('Identidad local persistente creada. Clave privada excluida de los instaladores.')

def sign(app):
    if not PIN.exists() or not KEYCHAIN.exists():
        raise RuntimeError('Falta la identidad persistente. Restaura la copia privada; no uses firma ad hoc.')
    metadata = json.loads(PIN.read_text()); fingerprint = metadata['certificateSHA1']
    assert hashlib.sha1((ROOT/'Signing/certificate.der').read_bytes()).hexdigest().upper() == fingerprint
    # Use only the project keychain. Falling back to the user's login keychain
    # can trigger repeated macOS password dialogs and silently change the
    # signing identity used by updates.
    signer = KEYCHAIN.resolve()
    if not signer.exists():
        raise RuntimeError('Falta el llavero local de firma. No se consultará el llavero personal ni se abrirán avisos de contraseña.')
    found = run(['security','find-identity','-v','-p','codesigning',str(signer)],text=True).stdout
    if not re.search(r'\b' + re.escape(fingerprint) + r'\b', found, re.IGNORECASE):
        raise RuntimeError('El llavero local no contiene la identidad privada de firma esperada. No se consultará el llavero personal.')
    password = KEYCHAIN_PASSWORD.read_text()
    run(['security','unlock-keychain','-p',password,str(signer)])
    # Explicitly sign the Swift overlays bundled for older macOS releases.
    for library in sorted((app/'Contents/Frameworks').glob('*.dylib')):
        run(['codesign','--force','--sign',fingerprint,'--keychain',str(signer),'--timestamp=none',str(library)])
    run(['codesign','--force','--sign',fingerprint,'--keychain',str(signer),'--timestamp=none',str(app)])
    run(['codesign','--verify','--strict','--all-architectures',str(app)])
    displayed = run(['codesign','-d','-r-',str(app)],text=True)
    requirement = displayed.stdout + displayed.stderr
    if fingerprint.lower() not in requirement.lower() or 'cdhash' in requirement:
        raise RuntimeError('La firma no tiene el anclaje persistente esperado.')
    print('Firma persistente verificada:', app.name)

try:
    if sys.argv[1:] == ['--initialize']: initialize()
    elif len(sys.argv) == 2: sign(Path(sys.argv[1]))
    else: raise RuntimeError('Uso: sign.py --initialize | ruta-app')
except Exception as error:
    # Never echo security arguments: they include the private keychain password.
    if isinstance(error,subprocess.CalledProcessError):
        print('Falló la operación de firma:', error.stderr.decode(errors='replace') if isinstance(error.stderr,bytes) else error.stderr, file=sys.stderr)
    else: print(str(error),file=sys.stderr)
    sys.exit(1)
