# PRISON DISPLAY 0.4.23 — copia de continuidad

Fecha de la copia: 4 de noviembre de 2026.

## Objetivo de esta versión

- Corregir los clics desalineados al pasar el ratón del MacBook Air al MacBook Pro.
- Mantener por separado el permiso de ratón y teclado.
- Añadir en la app del Air un panel para mostrar en el HDMI un escritorio virtual con más espacio que la resolución física del monitor.
- Mantener el MacBook Air como equipo principal y el MacBook Pro antiguo como pantalla por Wi‑Fi.

## Trabajo ya incorporado

- El último desplazamiento pendiente se aplica antes de cada clic.
- El receptor sincroniza la posición real de Quartz antes de publicar una pulsación.
- La geometría de la pantalla se actualiza al crear o cambiar una pantalla virtual.
- El panel `Monitor HDMI con más espacio` detecta monitores externos y ofrece 2560×1440, 3200×1800 y 3840×2160.
- El HDMI se duplica temporalmente para liberar el límite de escritorios externos del MacBook Air; después pasa a mostrar la pantalla virtual.
- Al detener, el HDMI vuelve a su colocación ampliada original.
- El codificador prueba RTVC, después H.264 por hardware y finalmente software si macOS tiene ocupado el codificador rápido.
- La versión del proyecto es `0.4.23`.

## Validación completada antes de esta copia

- Pruebas principales de protocolo, vídeo 720p/1080p/1440p, Intel, emparejamiento y ratón: sin fallos.
- Pruebas específicas del ratón y de la interfaz receptora: sin fallos.
- Pruebas de maquetación del emisor y receptor: sin fallos.
- Vista previa del emisor: `build/UI-Sender-0.4.23.png` (se regenera; la carpeta `build` no está en la copia).

## Validación pendiente al crear esta copia

La última modificación cambia la pantalla HDMI local a una superficie HiDPI 2× para que macOS conserve 3840×2160 de espacio lógico. Hay que volver a ejecutar primero:

```sh
xcrun clang -arch arm64 -mmacosx-version-min=13.0 -fobjc-arc -isysroot "$(xcrun --sdk macosx --show-sdk-path)" -c Sources/VirtualDisplay.m -o build/VirtualDisplay-arm64.o
xcrun swiftc -module-cache-path build/ModuleCache -swift-version 5 -O -target arm64-apple-macosx13.0 build/VirtualDisplay-arm64.o -import-objc-header Sources/VirtualDisplay.h Tests/Virtual/main.swift -o build/VirtualTests
build/VirtualTests
```

Después:

```sh
zsh test.sh
zsh Tests/Layout/run.sh
zsh Tests/features.sh
zsh build.sh
```

Las pruebas que usan WindowServer, VideoToolbox o pantallas reales deben ejecutarse con acceso normal a macOS, no en un entorno restringido.

## Instalación

El Air y el Pro deben llevar exactamente la misma versión de PRISON DISPLAY para conectarse. Antes de sustituir las apps instaladas, conserva una copia de la versión anterior. No borres datos del Llavero ni permisos de Accesibilidad/Grabación de pantalla.

## Restaurar en otra conversación o cuenta

1. Descomprime el ZIP en una carpeta de trabajo.
2. Abre esa carpeta como proyecto en Codex.
3. Entrega este archivo al nuevo chat y pide: “Continúa PRISON DISPLAY 0.4.23 desde `HANDOFF-0.4.23.md`; termina la validación HiDPI, compila e instala en el Air y el Pro”.
4. No es necesario recuperar la carpeta `build`; `build.sh` la reconstruye.

La copia no contiene credenciales privadas ni datos del Llavero.
