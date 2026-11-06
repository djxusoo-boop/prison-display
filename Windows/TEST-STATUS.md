# Validación · 0.2.1 · 6 de noviembre de 2026

- Núcleo con protocolo revisión 12 y vectores de la app Mac 0.4.25: 10046 comprobaciones, 0 fallos.
- Agente: portapapeles y actualización (rechazo de versiones antiguas, descargas dañadas, datos desordenados; actualización posible desde otra revisión), 0 fallos.
- Punta a punta con el enlace real del Mac: portapapeles en ambos sentidos y envío verificado de un .exe nuevo, 0 fallos.
- Pendiente en la torre: sustitución real del .exe y reinicio; portapapeles de Windows real.

---

# Validación · 0.2.0 · 6 de noviembre de 2026

## Comprobado en macOS
- Núcleo C++ con protocolo revisión 11 frente a vectores generados por la app Mac 0.4.24: 10046 comprobaciones, 0 fallos.
- Agente de entrada: 21 comprobaciones (permiso temporal, caducidad, liberación de teclas y botones, ⌘C → Ctrl+C, AltGr, Bloq Mayús, rueda).
- Punta a punta: el enlace real del Mac contra el agente y su servidor TLS compilados para macOS con inyector simulado: conexión, cruce, movimiento, clic, ⌘C, latidos, regreso, cierre del PC y rechazo de clave incorrecta. 0 fallos.
- `prison_display.exe` compilado como PE32+ x86-64 estático; solo depende de DLL del sistema (UCRT de Windows 10).

## Pendiente en la torre
- Abrir el .exe, permitir el firewall, conectar desde el Air y probar ratón/teclado reales, escalado de pantallas, UAC y bloqueo.

---

# Validación del puerto Windows · 0.1.0-dev

5 de noviembre de 2026.

## Comprobado

- Vectores generados con los serializadores Swift reales del producto y perfil Mac 0.4.22, protocolo 10.
- C++17 compilado y ejecutado en macOS arm64 (OpenSSL nativo) y x86_64 bajo Rosetta (OpenSSL 3.5.9 del proyecto).
- En cada arquitectura: 10046 comprobaciones, cero fallos. Incluyen 10000 entradas aleatorias limitadas, fragmentación/coalescencia, tamaños y tipos inválidos, ratón/teclado independientes, liberación selectiva, H.264 producido por el Mac y perfil TLS-PSK en memoria con secreto correcto e incorrecto.
- ZIP de diagnóstico creado y verificado sin errores de integridad.

## No comprobado / no implementado

- No se ha compilado ni ejecutado en Windows. Intel bajo Rosetta sigue siendo macOS y no valida APIs de Windows.
- No hay todavía interfaz Windows, transporte por red de producción, emparejamiento completo, captura, codificación/decodificación nativa, inyección real de entrada ni controlador de pantalla virtual implementados.
- No hay instalador ni EXE Windows listo para el usuario.
- No se ha establecido una sesión Mac-Windows ni medido latencia física.
- El script de diagnóstico Windows está revisado estáticamente, pero pendiente de ejecución en Windows.

## Toolchain portable preparado · 5/11/2026

- Se descargó en `Windows/build/toolchain` LLVM-MinGW universal para generar binarios Windows x86_64 desde macOS. Es un artefacto de compilación local y no modifica ninguno de los tres Mac ni la torre.
- La configuración cruzada de CMake detecta correctamente Clang 23.1.5 y genera `libprison_core.a` para Windows x86_64.
- El ejecutable de pruebas todavía no se entrega: el enlace cruzado de OpenSSL usa las bibliotecas macOS del entorno y falla al resolver TLS. Hay que preparar bibliotecas OpenSSL Windows compatibles o migrar la capa TLS a SChannel antes de generar un binario instalable.
- Esto confirma que la base C++ portable compila para Windows; no confirma todavía captura, vídeo, teclado/ratón ni conexión real.

### Actualización TLS

- OpenSSL 3.5.4 se compiló desde fuente oficial con LLVM-MinGW para Windows x86_64, en modo estático y sin tests propios.
- El núcleo y `prison_core_tests.exe` ya enlazan como PE32+ Windows x86_64 usando esas bibliotecas; el ejecutable aún debe ejecutarse en la torre para validar el entorno real.

### Ejecución en la torre

- El PE estático se descargó y arrancó correctamente en Windows 10 Pro; ya no depende de `libc++.dll` ni `libunwind.dll`.
- La prueba terminó con `FAIL: Missing Swift fixture` porque el paquete de validación aún no lleva sus vectores junto al ejecutable. Es un fallo de empaquetado de pruebas, no de carga del binario; se corregirá antes de usarlo como instalador.

- Tras incluir los siete vectores Swift correctos, la torre ejecutó `prisonstatic.exe fixtures` con `PASS 10046 checks`: interoperabilidad de mensajes, entradas independientes, paquetes malformados y TLS-PSK. Esta validación no incluye todavía captura de pantalla ni inyección nativa.

Se esperan versión/build de Windows, gráfica y disponibilidad de la torre. Los Mac instalados no se han modificado y la rama HDMI 0.4.23 se ha conservado intacta.

## Acceso a la torre verificado · 5/11/2026

- Equipo identificado por el usuario en 10.0.0.13. El usuario indica acceso local sin contraseña.
- SSH responde, pero rechaza la clave del proyecto y una única prueba de contraseña vacía. No se cambió configuración SSH, contraseña ni política de seguridad.
- Se accedió correctamente por la sesión existente de Escritorio Remoto de Chrome y se verificó control real de la consola mediante `whoami`.
- Consola observada: cuenta torre\torre ssd; Windows 10 Pro, versión 10.0.19045.6466.
- WMIC informa AMD Radeon R7 200 Series y Virtual Display Driver. Esto no identifica una Radeon 270 de forma concluyente ni valida todavía captura/códec o extensión virtual.
- `where cmake` y `where cl` no encontraron programas en PATH. `where dotnet` encontró C:\Program Files\dotnet\dotnet.exe; la ejecución indicó que no encontró SDK. Un primer comando con guiones llegó con comillas por el mapa de teclado español y no debe considerarse una prueba válida de esa opción.
- El mapa de teclado del control remoto es físico: guion usa tecla slash y guion bajo Shift+slash en esa sesión española. La escritura directa de texto/paste no se transmitió a la consola; eventos de teclas individuales y Enter sí. Verificar siempre la línea visible antes de ejecutar comandos con símbolos.
- Solo se ejecutaron consultas de identidad, sistema, gráfica y herramientas. No se instalaron programas, no se crearon claves autorizadas ni se modificaron drivers o ajustes del sistema.
- El acceso gráfico está disponible; la primera interfaz Win32 de PRISON DISPLAY se compiló como PE32+ y se abrió en la torre mostrando marca, estado y versión `0.1.0-dev`.
- Esta interfaz es todavía un shell visible: no anuncia captura, vídeo ni entrada nativa hasta que esos módulos estén implementados y probados.
- La interfaz Win32 ahora incorpora descubrimiento LAN por broadcast, con versión de producto separada del perfil de cableado Mac `0.4.22`; el binario cruzado se recompiló correctamente.

### Prueba visible de la interfaz Win32 · 5/11/2026

- Se descargó y abrió en la torre el binario actual `prisondisplay.exe`.
- La ventana permaneció estable durante la observación: mostró `Equipos disponibles: 1` y `Pantallas detectadas: 1`.
- No se observó cierre inesperado ni fallo en el contador de monitores durante esta prueba.
- Esta prueba valida el arranque y el descubrimiento experimental, pero todavía no valida una sesión de pantalla real con macOS; siguen pendientes captura, vídeo, TLS de sesión, teclado/ratón e instalador.
