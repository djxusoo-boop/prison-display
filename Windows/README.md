# PRISON DISPLAY Windows · 0.1.0-dev

Puerto iniciado. **Todavía no existe una app ni un instalador Windows utilizable.**
Este directorio contiene el núcleo portable y pruebas de compatibilidad de mensajes
con el Mac; captura, visor, control nativo y conexión de producción están pendientes.
Véase [estado y arquitectura](docs/ARQUITECTURA.md).

## Pruebas del núcleo

Requisitos: CMake, compilador C++17 y OpenSSL >=3.0. En Windows se requiere un
compilador y bibliotecas de la misma arquitectura. No se instala ningún controlador.

```text
cmake -S Windows -B Windows/build/test -DOPENSSL_ROOT_DIR=<ruta de OpenSSL>
cmake --build Windows/build/test --config Release
ctest --test-dir Windows/build/test -C Release --output-on-failure
```

Los vectores se generan en macOS con `zsh Windows/tests/generate-fixtures.sh` usando
los serializadores Swift de la app. Los tests no capturan pantalla, no publican
entrada y no utilizan credenciales de los enlaces guardados.

El perfil de prueba es Mac 0.4.22/protocolo 10; no cambiar VERSION del proyecto Mac
ni desplegar 0.4.23 HDMI para realizar estas pruebas.
