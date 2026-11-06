# PRISON DISPLAY

Ecosistema de pantallas, ratón, teclado y portapapeles entre Macs y un PC con Windows,
por Wi‑Fi o cable de red. Versión Mac **0.4.25** · Windows **0.2.1** (protocolo revisión 12).

## Qué hace
- **Pantallas extendidas:** el MacBook Air envía hasta dos escritorios virtuales al MacBook Pro y al iMac.
  El escritorio puede ser mayor que la pantalla que lo recibe (hasta 4K, en 16:9 y 16:10),
  y la imagen enviada se puede reducir para ir más fluida.
- **Monitor HDMI con más espacio:** escritorio virtual de ×1,25 a ×3 la resolución del monitor (hasta 5K).
- **Un solo ratón y teclado:** el ratón del Air recorre todas las pantallas; el del Pro o el iMac
  continúa por las demás pantallas del Air empujando contra el borde (ratón continuo).
  El teclado escribe donde haces clic.
- **PC con Windows:** el ratón y el teclado del Air pasan al PC por el borde elegido
  (⌘C → Ctrl+C, ⌥2 → @). Ver la pantalla del Air en el PC aún no está hecho.
- **Portapapeles compartido** entre todos los equipos (texto; imágenes entre Macs).
- **Actualización automática:** el equipo más nuevo actualiza a los demás, comprobando la firma.

## Estructura
- `Sources/` app macOS (Swift/Objective‑C); `Windows/` app Windows (C++17).
- `Tests/` pruebas; `Packaging/` instaladores; `Signing/` firma persistente (la clave privada no está en el repositorio).
- `docs/historial/` auditorías y traspasos de versiones anteriores. Estado actual: `HANDOFF.md`.

## Compilar y probar
```sh
zsh test.sh                     # protocolo, vídeo, emparejamiento, ratón
zsh Tests/features.sh           # funciones, conexión TLS real, pantallas virtuales (pantalla desbloqueada)
zsh Tests/Layout/run.sh         # interfaz
zsh Windows/tests/run-mac-e2e.sh  # agente Windows real (simulado en macOS) ↔ enlace del Mac
zsh build.sh                    # apps firmadas (requiere .signing y build/dependencies)
python3 Packaging/build-installers.py && python3 Packaging/verify-installers.py
```
