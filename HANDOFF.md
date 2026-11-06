# Estado actual · PRISON DISPLAY Mac 0.4.26 · Windows 0.2.2

Fecha: 6 de noviembre de 2026. Rama `mejoras-rendimiento`.

## Equipos
- MacBook Air (M4, macOS 26): emisor, 0.4.26 instalada. Copias anteriores en `~/Applications/PRISON DISPLAY-backups/`.
- MacBook Pro 2014 (app «MacBook») e iMac (app «iMac»): receptores. Pendiente instalar 0.4.26 a mano
  (última vez: a partir de aquí se actualizan solos desde el Air).
- PC torre Windows 10 Pro: `prison_display.exe` 0.2.2, puertos TCP 37941 (entrada) y 37942 (emparejamiento), anuncio UDP 37930.
- Red doméstica actual 10.0.0.x (antes 192.168.1.x).

## Compilación
- `build.sh` necesita `.signing` (identidad persistente, fuera del repositorio) y `build/dependencies`
  (OpenSSL 3.5.9 para Intel). Compila primero la app del iMac y la mete, con el `.exe` de Windows,
  en `MacBook.app/Contents/Resources/Updates/` para las actualizaciones automáticas.
- Windows: LLVM‑MinGW + OpenSSL Windows estático (`Windows/README.md`).

## Validado
- Batería completa con la pantalla desbloqueada: todo pasa salvo la prueba HDMI (requiere monitor)
  y tres de colocación de pantallas que fallan de forma intermitente también con el código original.
- Actualización real con apps firmadas: 0.4.25 → 0.4.26 aceptada; rechaza otra app, app manipulada,
  firma ad hoc y versión que no coincide.

## Pendiente de prueba física
- Monitor HDMI con escritorio ampliado.
- Ratón continuo con los tres Mac; Air → PC con ratón/teclado/portapapeles reales; actualización real del .exe.

## Notas
- Con la pantalla bloqueada macOS no permite pantallas virtuales ni captura: las pruebas reales fallan en bloque.
- El aviso del Llavero en actualizaciones se debe a la firma propia sin Team ID; solo lo resuelve un certificado de Apple Developer.

## Siguiente gran paso
- Ver la pantalla del Air en el PC: receptor Windows (descubrimiento, emparejamiento con el Mac, H.264 con Media Foundation, presentación, ACK y entrada). Necesita la torre accesible para validarlo.
- HEVC descartado por ahora: el MacBook Pro 2014 no decodifica HEVC por hardware.
