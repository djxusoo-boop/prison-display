# PRISON DISPLAY Windows · 0.2.0

App para el PC con Windows: **recibe el ratón y el teclado del Mac**. Lleva el
ratón del Air al borde elegido de sus pantallas y pasa al PC con el teclado;
vuelve por el mismo borde o con ⌃⌥Esc en el Mac.

- Conexión cifrada TLS 1.2 PSK con la misma derivación que el Mac. La clave se
  genera en el PC, se guarda protegida con DPAPI y se escribe una vez en el Mac
  (Enviar pantalla → PC con Windows), que la guarda en su Llavero.
- Puerto TCP 37941. Windows puede preguntar por el firewall: permite redes privadas.
- Teclas por posición física (teclado español ISO incluido). ⌘ → Ctrl, ⌥ izquierda
  → AltGr (⌥2 = @), ⌥ derecha → Alt. Rueda, botón central y Bloq Mayús incluidos.
- Un único Mac controla a la vez, con permiso temporal renovado cada 0,5 s.
  Si el Mac deja de responder 3 s, se sueltan todas las teclas y botones.
- Pendiente: ver la pantalla del Mac en Windows (captura y vídeo), instalador.

## Compilar

```text
cmake -S Windows -B Windows/build/windows -DCMAKE_TOOLCHAIN_FILE=<llvm-mingw.cmake> \
  -DOPENSSL_ROOT_DIR=<openssl-win-x86_64> -DOPENSSL_USE_STATIC_LIBS=TRUE -DCMAKE_EXE_LINKER_FLAGS=-static
cmake --build Windows/build/windows
```

Pruebas en macOS (agente real con un inyector simulado y el enlace del Mac):
`zsh Windows/tests/run-mac-e2e.sh`.
