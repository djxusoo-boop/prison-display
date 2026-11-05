from pathlib import Path
import plistlib, shutil, subprocess, html, hashlib, json, argparse, tempfile

project = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--version')
parser.add_argument('--apps-directory',type=Path)
arguments = parser.parse_args()
version = arguments.version or (project/'VERSION').read_text().strip()
apps = arguments.apps_directory or project/'build'
out = project/'outputs'/f'PRISON-DISPLAY-v{version}'
staging = tempfile.TemporaryDirectory(prefix='prison-installers-', dir='/private/tmp')
work = Path(staging.name)
out.mkdir(parents=True, exist_ok=True)
work.mkdir(parents=True, exist_ok=True)
records=[]
for role, identifier, arch, minimum, description in [
    ('MacBook', 'sender', 'arm64,x86_64', '10.13', 'Enviar o recibir pantalla. Intel: macOS 10.13 High Sierra o posterior. Chip Apple: macOS 11 Big Sur o posterior. En High Sierra, el envío permite duplicación; puede recibir una extensión creada en otro Mac compatible.'),
    ('iMac', 'receiver', 'arm64,x86_64', '10.13', 'Enviar o recibir pantalla. Intel: macOS 10.13 High Sierra o posterior. Chip Apple: macOS 11 Big Sur o posterior. En High Sierra, el envío permite duplicación; puede recibir una extensión creada en otro Mac compatible.')
]:
    name=f'PRISON DISPLAY {role}'
    app=apps/f'{name}.app'
    info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    assert info['CFBundleShortVersionString']==version
    subprocess.run(['codesign','--verify','--strict',str(app)],check=True)
    stage=work/role
    if stage.exists(): shutil.rmtree(stage)
    root=stage/'root'; resources=stage/'resources'; packages=stage/'packages'
    for directory in [root/'Applications',resources,packages]: directory.mkdir(parents=True,exist_ok=True)
    shutil.copytree(app,root/'Applications'/app.name)
    shutil.copy2(project/'Assets/PrisonLogo.jpg',resources/'PrisonLogo.jpg')
    component=stage/'components.plist'
    subprocess.run(['pkgbuild','--analyze','--root',str(root),str(component)],check=True)
    components=plistlib.loads(component.read_bytes())
    for item in components:
        item['BundleIsRelocatable']=False
        item['BundleIsVersionChecked']=True
        item['BundleOverwriteAction']='upgrade'
    component.write_bytes(plistlib.dumps(components))
    packageID=f'local.prisondisplay.installer.{identifier}'
    payload=packages/f'{identifier}.pkg'
    subprocess.run(['pkgbuild','--root',str(root),'--component-plist',str(component),'--identifier',packageID,'--version',version,'--install-location','/','--ownership','recommended',str(payload)],check=True)
    extra='En cada Mac elige Enviar pantalla o Recibir pantalla. En los sistemas que lo requieren, enviar necesita Grabación de pantalla. Controlar ratón y teclado necesita Accesibilidad en el Mac correspondiente. Estos permisos se conceden en los ajustes de macOS.'
    welcome=f'''<!doctype html><html lang="es"><meta charset="utf-8"><body style="font-family:-apple-system,Helvetica,Arial;font-size:14px;padding:16px;color:#222">
<h1>PRISON DISPLAY</h1><h2>{role} · v{version}</h2><p>{description}</p>
<p>Instala <b>{name}</b> en la carpeta <b>Aplicaciones</b>. Necesitarás la autorización de una cuenta administradora.</p>
<p>Es una versión de desarrollo sin firma oficial de Apple ni notarización. La app utiliza un certificado local persistente para conservar su identidad entre actualizaciones.</p>
<p>{extra}</p><p>Instala la misma versión en ambos equipos.</p></body></html>'''
    (resources/'welcome.html').write_text(welcome)
    (resources/'conclusion.html').write_text(f'''<!doctype html><html lang="es"><meta charset="utf-8"><body style="font-family:-apple-system,Helvetica,Arial;font-size:14px;padding:16px;color:#222"><h1>Todo preparado</h1><p>Abre <b>{name}</b> desde <b>Aplicaciones</b>.</p><p>{extra}</p><p>El Mac que envía se anuncia en la red; en el que recibe selecciónalo y comprueba el mismo código en ambos.</p><p>Versión {version}. El instalador no concede permisos ni inicia la app automáticamente.</p></body></html>''')
    distribution=stage/'Distribution.xml'
    distribution.write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
<title>{name} · v{version}</title>
<welcome file="welcome.html" mime-type="text/html"/>
<conclusion file="conclusion.html" mime-type="text/html"/>
<options customize="never" require-scripts="false" hostArchitectures="{arch}"/>
<allowed-os-versions><os-version min="{minimum}"/></allowed-os-versions>
<domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
<choices-outline><line choice="app"/></choices-outline>
<choice id="app" title="{name}" visible="false"><pkg-ref id="{packageID}"/></choice>
<pkg-ref id="{packageID}" version="{version}" onConclusion="none">{identifier}.pkg</pkg-ref>
</installer-gui-script>''')
    installer=out/f'PRISON-DISPLAY-{role}-v{version}.pkg'
    subprocess.run(['productbuild','--distribution',str(distribution),'--resources',str(resources),'--package-path',str(packages),str(installer)],check=True)
    records.append({'file':installer.name,'version':version,'role':role,'architecture':arch,'minimumMacOS':minimum,'sha256':hashlib.sha256(installer.read_bytes()).hexdigest()})
(out/'SHA256.txt').write_text(''.join(f"{r['sha256']}  {r['file']}\n" for r in records))
(out/'INSTALACION.txt').write_text(f'''PRISON DISPLAY · v{version}

LOS DOS INSTALADORES PERMITEN ENVIAR Y RECIBIR
MacBook e iMac indican la app que se actualiza y su función inicial; no restringen sus funciones. Para conservar los permisos, actualiza la misma app que ya tienes. En un Mac nuevo basta con instalar una de ellas.

COMPATIBILIDAD
Intel: macOS 10.13 High Sierra o posterior. Chip Apple: macOS 11 Big Sur o posterior. El paquete es universal y elige automáticamente el procesador.
High Sierra puede enviar una pantalla duplicada y recibir la pantalla de otro Mac. No puede crear la pantalla virtual que usa esta app para extender al enviar. Puede recibir el escritorio extendido creado por un Mac compatible.

INSTALACIÓN Y CONEXIÓN
1. Pasa el paquete por AirDrop o USB y abre el instalador en cada Mac.
2. El asistente instala su app en Aplicaciones; necesita una cuenta administradora.
3. Abre las apps. En uno elige Enviar pantalla; en el otro, Recibir pantalla.
4. En el receptor, pulsa el Mac disponible y confirma el mismo código en ambos solo la primera vez. Después reconectan automáticamente mientras las apps estén abiertas.
5. Si no aparece, usa Copiar enlace en el emisor y Pegar enlace en el receptor.
6. En el emisor ajusta modo, resolución, fluidez, calidad y cursor. Los cambios se aplican en directo.
7. Para controlar el escritorio propio del otro Mac, activa el cruce en el receptor y elige su posición. Control + Opción + Esc devuelve el control local.

TRES PANTALLAS CON EL MACBOOK AIR M4
1. En el M4 elige Enviar pantalla y la primera pantalla (aparece con el nombre del Mac enlazado). Conserva Extender escritorio.
2. En el primer receptor elige Recibir pantalla y selecciona la primera pantalla del Air. Si ya está enlazado, conserva su conexión guardada; no cambies el destino.
3. En el M4 pulsa Pantalla 2. Se anuncia una segunda conexión y Pantalla 1 sigue activa.
4. En el segundo receptor selecciona la segunda pantalla del Air. Solo para un enlace nuevo, comprueba y acepta el mismo código en ambos.
5. El botón Organizar pantallas del M4 abre la colocación de los tres monitores. Cada pantalla guarda su posición por separado.
6. Puedes elegir resolución, FPS, calidad y cursor distintos para cada receptor. Cambiar de Pantalla 1 a Pantalla 2 en la barra lateral no interrumpe el otro envío.
7. Detener afecta solo a la pantalla seleccionada. Cambiar a Recibir pantalla o cerrar la app del M4 detiene los dos envíos.
8. Reconectar automáticamente viene activado. Tras confirmar el primer código y recibir imagen se guarda el enlace en ambos Mac. Al volver a abrir, no pide otro código. Desactívalo en ambos extremos para olvidar el acceso. Los dos envíos tienen cuentas separadas del Llavero.

PERMISOS Y AJUSTES
La app conserva su certificado, identificador, ajustes y cuentas existentes del Llavero. Al añadir la función de enviar a una app que antes solo recibía, macOS puede requerir el permiso de pantalla por primera vez. La app no borra permisos ni los solicita repetidamente cuando están autorizados.
Las conexiones recordadas de cada función se guardan por separado en el Llavero. Cambiar de función detiene la conexión actual. Se conserva la función seleccionada para la próxima apertura.

Estas apps usan un certificado local persistente y no están notarizadas por Apple. El instalador no modifica los ajustes de seguridad ni concede permisos. Si macOS bloquea su apertura, usa la autorización de apertura en Seguridad y privacidad para este paquete concreto. Guía de Apple: https://support.apple.com/es-es/102445
Al actualizar, macOS puede pedir otra autorización del Llavero aunque se conserve el certificado local. La reconexión espera a que se complete ese aviso.
No contienen las claves privadas de firma o SSH. La implementación TLS para Intel incluye OpenSSL, con su licencia en los recursos de la app.
Instala la misma versión en los dos Mac y evita abrir copias antiguas a la vez.
Los resultados y límites de las pruebas se detallan en PRUEBAS.txt.
''')
(out/'manifest.json').write_text(json.dumps(records,indent=2,ensure_ascii=False))
print(f'Installers prepared: {out}')
