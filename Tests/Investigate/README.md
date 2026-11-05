# Investigación de PRISON DISPLAY

Fecha: 7–8 de octubre de 2026. M4 y iMac Intel Catalina físico, red compartida.

Los programas de esta carpeta son diagnósticos y no se distribuyen como apps.
No publican eventos de ratón o teclado en el escritorio. Las imágenes de la
prueba de nitidez son generadas. Las pruebas de vídeo sí capturan el escritorio
con el permiso ya autorizado de PRISON DISPLAY.

- `input.py`: cuatro muestras de 15 s, orden anterior/nueva/nueva/anterior,
  posiciones simuladas a 120 Hz, vídeo H.264 de referencia y ReceiverEngine real.
  Mide ida y vuelta de respuestas recibidas; la agrupación de movimientos hace
  que algunas posiciones no tengan respuesta individual. No mide latencia óptica.
- `video.py`: captura real del emisor, escena opcional `--scene`, decodificador
  compatible con Catalina. Los modos `realbaseline`/`realcandidate` utilizan
  ReceiverEngine, VideoView y los presentadores del producto en el iMac físico.
  `presented` cuenta llamadas completadas a VideoView.present, no una observación
  óptica de la pantalla. FPS cuenta imágenes decodificadas por unidad de tiempo.
- `Scene.swift`: texto fijo y barra animada para que ScreenCaptureKit genere
  movimiento repetible. Sin esta escena, el número de capturas depende también
  de cuánto cambie el escritorio y no expresa por sí solo capacidad de la red.
- `bundle.py`: envuelve ejecutables diagnósticos con el mismo identificador y
  certificado persistente. El certificado privado nunca se incluye.
- `Tests/Interactive`: bloqueo artificial del decodificador de 700 ms; entrada,
  cursor, orden de clics/teclas y desconexión del canal independiente.
- `Tests/ImageQuality`: texto generado a 2 Mb/s y cuantificación sin límite,
  límite 32 y 36. Más detalle puede implicar imágenes omitidas por el codificador.

Los ensayos usan credenciales temporales en ficheros privados y eliminan los
enlaces al terminar. SSH requiere la clave ya autorizada y la huella verificada
del iMac. Los scripts no imprimen las credenciales de conexión.

Registros en build: video-controlled-0.3.14.json,
video-return-path-0.3.14.json, video-final-window-0.3.14.json,
video-real-visor-0.3.14.json, control-comparison-0.3.14.json.
Los resultados parciales anteriores no se sustituyen por una promesa de ausencia
absoluta de retraso: hace falta la prueba humana del ratón físico en ambos sentidos.

## Revisión histórica del bloqueo 0.3.16

`build.sh` compila los diagnósticos con VERSION actual; `native.py` utiliza la misma versión. `video.py --extend` permite una prueba sostenida de extensión. La escena se recrea en el monitor actual al cambiar de captura para evitar animaciones suspendidas al retirarse una pantalla. El primer ensayo de 90 s se detuvo por sobrecarga de ColorSync; su fallo se conserva. Tras la reparación específicamente autorizada y la corrección de la herramienta de escena, se completaron la suite, los ocho ajustes y 90 s de imagen en movimiento. Véase el historial final de 0.3.16 en TEST-STATUS.md.

`Tests/Safety/run.py` vigila tiempo, perfiles nuevos y carga de color. Solo termina el grupo que él mismo lanzó. `Tests/Safety/profiles.py verify` comprueba el respaldo e identidades; `apply` y `restore` se ejecutan únicamente tras autorización específica para mantenimiento del sistema. La reparación de los 297 ICC y sus registros ya está completada y respaldada; no debe repetirse como parte de las pruebas. No forma parte de la app ni del instalador. Las apps 0.3.16 fueron instaladas y verificadas.

## Revisión 0.3.17

`video.py --scene --detail --extend --input-probe` utiliza captura real, el emisor y el visor del producto en Catalina. La entrada generada a 120 Hz recorre el canal de control y construye CGEvent; su publicación al sistema se sustituye por una posición de diagnóstico que vuelve por el canal real de cursor. No publica movimientos ni teclas y no mide mano→píxel. La agrupación hace que no todas las posiciones tengan respuesta individual.

`tuning.py` y `compare-tuning.py` preparan variantes aisladas antes de medir secuencialmente. Los resultados completos están en build/tuning-0.3.17. La referencia conserva Sources de 0.3.16 pero anuncia versión de protocolo 0.3.17 para permitir una comparación equivalente. No es una versión para instalar. Los experimentos de tres imágenes, ACK y NV12 no se incorporan al producto.

La prueba final de 90 s recibió/presentó 3.944 imágenes (43,87 FPS), con movimiento durante 89,80 s, sin cortes durante el intervalo y cero perfiles nuevos. Ocho configuraciones en directo completaron 63,84 s de imagen y 2.062 presentaciones. Las pausas de este último ensayo incluyen los cambios deliberados de captura/pantalla. El cierre del emisor al finalizar provoca los mensajes de desconexión del receptor, fuera del intervalo medido. Informe: outputs/PRISON-DISPLAY-v0.3.17/INVESTIGACION.md. Queda aceptación física del ratón y medición óptica; no se declara funcionamiento perfecto.

## Recuperación del Llavero0.3.18

Los cambios de vídeo/entrada de0.3.17 se conservan. Al abrir la copia canónica, la lectura pasiva del Llavero devolvió -25293 pese a la firma continua. La acción explícita permite autorizar la lectura fuera de la interfaz; no modifica el registro ni su ACL. Tests/Layout prueba lectura cancelada, inexistente, recuperación, parada y resultado tardío con una función inyectada y datos generados. Tests/Trust/run.sh usa únicamente cuentas sintéticas únicas en el Llavero y las elimina al terminar. No lee credenciales de producción.

## Revision0.3.19

Protocolo8 informa de la primera imagen aceptada por VideoView aparte de los ACK de decodificacion. presentation/backpressure se cuentan por separado. La produccion usa Bonjour y todos los sockets sobre la red compartida, sin activar peer Wi-Fi; ambos Mac deben compartir Wi-Fi o LAN. `--tuning peer-wifi` permite solo en diagnosticos comparar el comportamiento anterior. `lan-only` es ahora redundante y se conserva para reproducir los ensayos previos. Capturas0.3.19, comparacion repetida sin compilaciones y muestras rechazadas se conservan en build/review-0.3.19. No se adoptan ACK rapido/cursor16 ni se afirma ausencia de pausas de red.
