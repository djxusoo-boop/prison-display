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
    ('MacBook', 'sender', 'arm64,x86_64', '13.0', 'Mac Intel o con chip Apple M1 o posterior, con macOS 13 Ventura o posterior. La captura real del emisor Intel todavía requiere validación en un Intel con macOS 13 o posterior.'),
    ('iMac', 'receiver', 'arm64,x86_64', '10.15', 'Mac Intel con macOS 10.15 Catalina o posterior, o Mac con chip Apple y macOS 11 Big Sur o posterior.')
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
    extra=('Al abrir la app, permite Grabación de pantalla en el MacBook. Para usar el ratón del iMac, permite también Accesibilidad en el MacBook.' if role=='MacBook' else 'No necesita permiso de Grabación de pantalla en el iMac. Para cruzar del escritorio propio del iMac al MacBook, permite Accesibilidad en PRISON DISPLAY iMac y activa la opción de cruce. Abre la app y elige el MacBook disponible.')
    welcome=f'''<!doctype html><html lang="es"><meta charset="utf-8"><body style="font-family:-apple-system,Helvetica,Arial;font-size:14px;padding:16px;color:#222">
<h1>PRISON DISPLAY</h1><h2>{role} · v{version}</h2><p>{description}</p>
<p>Instala <b>{name}</b> en la carpeta <b>Aplicaciones</b>. Necesitarás la autorización de una cuenta administradora.</p>
<p>Es una versión de desarrollo sin firma oficial de Apple ni notarización. La app utiliza un certificado local persistente para conservar su identidad entre actualizaciones.</p>
<p>{extra}</p><p>Instala la misma versión en ambos equipos.</p></body></html>'''
    (resources/'welcome.html').write_text(welcome)
    (resources/'conclusion.html').write_text(f'''<!doctype html><html lang="es"><meta charset="utf-8"><body style="font-family:-apple-system,Helvetica,Arial;font-size:14px;padding:16px;color:#222"><h1>Todo preparado</h1><p>Abre <b>{name}</b> desde <b>Aplicaciones</b>.</p><p>{extra}</p><p>El MacBook se anuncia al abrir la app; en el iMac elígelo y acepta el mismo código en los dos.</p><p>Versión {version}. El instalador no concede permisos ni inicia la app automáticamente.</p></body></html>''')
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

1. Pasa el instalador correspondiente por AirDrop, memoria USB o tu método habitual.
2. En el MacBook, abre PRISON-DISPLAY-MacBook-v{version}.pkg.
   Universal Intel / chip Apple. Requiere macOS 13 o posterior.
   La captura real del emisor Intel aún no está validada en un Intel con macOS 13+.
3. En el iMac, abre PRISON-DISPLAY-iMac-v{version}.pkg.
   Universal Intel / chip Apple. Intel: macOS 10.15 o posterior.
   Chip Apple: macOS 11 o posterior.
4. Sigue el asistente. Cada instalador coloca únicamente su app en Aplicaciones.
5. Abre PRISON DISPLAY MacBook y permite Grabación de pantalla.
   Si quieres controlar con el ratón del iMac, autoriza Accesibilidad en el MacBook.
6. Para usar el ratón y teclado del iMac en el escritorio propio del MacBook,
   permite Accesibilidad en PRISON DISPLAY iMac. En la app del iMac activa
   «Cruzar del escritorio del iMac al MacBook» y elige en qué lado está.
   Regresa por el mismo borde o pulsa Control + Opción + Esc.
   Se conservan el borde, el teclado y la opción de cruce. Si dejaste el cruce
   activado, se rearmará cuando llegue una imagen y tenga Accesibilidad.
   La app muestra si está esperando conexión, listo o controlando el MacBook.
7. Conecta ambos Mac a la misma red Wi-Fi o LAN. La detección y la conexión
   usan esa red; no activan una red Wi-Fi directa adicional.
   El MacBook se anuncia al abrir la app. En el iMac elígelo en Disponibles y acepta el mismo código en ambos. Si no aparece, copia el enlace del MacBook y pégalo en el iMac.

Si macOS avisa que el desarrollador no está verificado, usa la autorización manual para este instalador en Ajustes > Privacidad y seguridad > Abrir igualmente. En Catalina, está en Preferencias del Sistema > Seguridad y privacidad > General. Autoriza únicamente el paquete que acabas de pasar desde esta carpeta.
Guía de Apple: https://support.apple.com/es-es/102445

Ambos instaladores contienen apps universales: el sistema elige automáticamente Intel o chip Apple. No hace falta elegir otro paquete por procesador. El emisor utiliza captura moderna y un codificador H.264 por hardware; no cubre todos los Mac ni todos los macOS. La extensión usa una interfaz de pantalla virtual de macOS que puede variar según el sistema. Si no está disponible, la app informa del error y permite usar duplicación.

Estos paquetes no están firmados con Developer ID ni notarizados por Apple. No necesitan una suscripción. No cambian los ajustes de seguridad, no conceden permisos, no instalan servicios de inicio ni copian claves de diagnóstico. Las apps están firmadas con un certificado local persistente; la clave privada nunca se incluye en las apps o instaladores.

Al pasar de 0.3.2 o una versión anterior a esta firma persistente, hay que renovar una vez los permisos de Grabación de pantalla y Accesibilidad del MacBook. En futuras actualizaciones se conserva el mismo certificado y el mismo identificador. La app no elimina los permisos ni los solicita en cada conexión cuando macOS reconoce la autorización. La firma local no equivale a una firma oficial de Apple.

Si hay una copia anterior en la carpeta Aplicaciones de tu usuario, ciérrala y evita abrir ambas copias. Usa la nueva de Aplicaciones. Instala la misma versión en ambos Mac.

Si el Llavero impide leer una conexión guardada, pulsa «Recuperar conexión guardada…» en la app y completa o cancela la confirmación de macOS. La lectura se realiza sin bloquear la ventana y no borra la conexión. No hace falta renovar Grabación de pantalla ni Accesibilidad para esta recuperación. No envíes tu contraseña por chat.

La instalación requiere cuenta administradora. Los paquetes rechazan equipos con arquitectura o macOS incompatibles. No se ha comprobado una instalación completa en los otros dos equipos todavía.
''')
(out/'manifest.json').write_text(json.dumps(records,indent=2,ensure_ascii=False))
print(f'Installers prepared: {out}')
