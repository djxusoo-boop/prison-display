# Estado actual · PRISON DISPLAY 0.4.19

Instalada en Air, Pro e iMac. Tras la autorización del Llavero, ambos receptores muestran imagen y la colocación se conserva. El usuario confirma escritura correcta con el teclado físico del iMac en el escritorio extendido del Air. Atajos probados de forma simulada; su prueba física específica sigue pendiente. El aviso del Llavero entre actualizaciones sigue sin resolver. Véase AUDITORIA-0.4.19.txt.

---
# Estado actual · 0.4.19 instalada

Instalada en Air, Pro e iMac. El Air vuelve a esperar al Llavero; pendientes reconexión conjunta y prueba real del teclado del iMac. Se ha solicitado al usuario confirmar los avisos protegidos. Resultados de compilación, interfaz y teclado simulado: AUDITORIA-0.4.19.txt.

---
# Revisión visual preparada · 0.4.18

Véase AUDITORIA-VISUAL-0.4.18.txt. Instaladores y distribución verificados. Las apps instaladas continúan en 0.4.17.

---
# Estado actual · PRISON DISPLAY 0.4.17

Auditoría del 14 de octubre de 2026: instalada y firmas verificadas en los tres Mac. Las pruebas automatizadas y las de compatibilidad en High Sierra y Catalina pasan. El Air ya recupera sus conexiones guardadas sin repetir el aviso después de cerrar y reabrir la misma compilación. La transmisión conjunta posterior a la actualización sigue pendiente de los avisos del Llavero del Pro y del iMac; el usuario no puede confirmarlos ahora. Véase AUDITORIA-0.4.17.md para resultados, causas y límites.

---
Historial anterior (no describe el estado actual):

# Estado de validación · PRISON DISPLAY 0.4.12

Se añadió en el Mac emisor un control junto al brillo para poner a pantalla completa los dos visores conectados. El comando se envía por las dos conexiones locales cifradas que ya están aprobadas. El receptor abre su visor y entra en pantalla completa sin necesitar el ratón de ese equipo.

## Verificado en este entorno
- Aplicación universal compila para Apple Silicon y para Intel, incluida la ruta de compatibilidad con macOS 10.13.
- Pruebas del protocolo y del control de brillo/pantalla completa: 26 comprobaciones, 0 fallos.
- Prueba de interfaz del espacio de trabajo: 1626 comprobaciones, 0 fallos al ejecutar el binario de prueba independiente; incluye presencia del botón, requisito de tener dos flujos activos y controles de pantalla completa locales. Al lanzarlo dentro de `WorkspacePreview.app`, el proceso de prueba abortó durante el registro de LaunchServices antes de mostrar el resultado.

## Pendiente antes de instalar
- Firma persistente y empaquetado completados el 13 de octubre. La identidad sí estaba presente: el entorno restringido impedía verla y desbloquear el llavero. Con acceso autorizado fuera de ese entorno, ambas apps se firmaron y verificaron con el certificado fijado. Los dos instaladores pasaron la validación de versión, contenido, arquitecturas, identidad y exclusión de claves privadas.
- Falta probar el botón en vivo con el MacBook Air, el iMac y el MacBook Pro conectados a la vez. La compilación y las pruebas de interfaz no demuestran el cambio de pantalla completa en los dos equipos físicos.
- Para usarlo, los tres equipos deberán tener PRISON DISPLAY 0.4.12; la versión y el protocolo requieren que coincidan.


---
Historial de comprobaciones anteriores:

# Registro de pruebas de PRISON DISPLAY

El estado más reciente está al final del documento. Se conserva el historial de las versiones anteriores.

## Estado histórico de AireDisplay 0.2.5

**No preparada para entrega final en esa fecha.** Fecha: 1 de octubre de 2026.

## Comprobado
- Las apps compilan sin diagnósticos en la última compilación: emisor arm64/macOS mínimo 13, receptor x86_64/macOS mínimo 10.15.
- Firma ad hoc válida; Info.plist de ambas apps coincide con VERSION 0.2.1.
- Interfaz nativa de 0.2.1 inspeccionada visualmente en el MacBook. Número de versión visible en ambas ventanas y en el visor, también a pantalla completa. Receptor Intel lanzado bajo Rosetta.
- H.264 por hardware en el M4: 60 fotogramas sintéticos de 720p decodificados y contenido verificado; muestras de 1080p/60 y 1440p/30 con dimensiones verificadas. Estos datos no prueban 60 FPS sostenidos por Wi-Fi.
- Fotogramas generados por el emisor ARM: 60 decodificados correctamente en el ejecutable Intel bajo Rosetta, comparando los tres canales de color.
- Transporte TLS local: bytes idénticos, confirmación de recepción, rechazo de clave incorrecta y desconexión.
- Creación y retirada de pantalla virtual 1920×1080 en macOS 26.6.2. Pantalla principal conservada.
- Descubrimiento Bonjour sin IP manual, código de verificación coincidente, aprobación bilateral, transferencia cifrada de credenciales e inicio de TLS usando el equipo descubierto.
- Rechazo de conexión en el emisor impide obtener credenciales.
- Enlaces: construcción/lectura; rechazadas versiones distintas, campos duplicados, otro esquema, clave incorrecta y puerto cero.
- Política de límite de un fotograma pendiente implementada; prueba de FPS/latencia sostenidos todavía pendiente.
- Flujo gráfico completo de descubrimiento y aprobación bilateral: los dos diálogos muestran el mismo código; al aceptar ambos comienza la captura real.
- Captura real de escritorio extendido 1920×1080, H.264 ARM, transporte local cifrado y presentación en el receptor Intel bajo Rosetta. Fondo de escritorio y barra de menús visibles en el visor.
- Duplicación real por la alternativa de copiar/pegar enlace: escritorio principal y ventanas visibles, incluido el efecto recursivo esperado de ejecutar el visor en el mismo Mac capturado.
- Entrada a pantalla completa y salida con Escape verificadas visualmente; distintivo de versión conservado.
- Parada de extensión y nueva conexión en modo duplicación completadas. Una muestra local de duplicación indicó 29 FPS e ida/vuelta de 14,1 ms. No es latencia óptica ni un resultado de Wi-Fi entre dos equipos. La confirmación se envía al encolar la imagen en el visor, no al medir su aparición física.

## Incidencias del entorno de prueba
Las mismas apps firmadas, ejecutadas desde Documents, bloquearon el inicio del codificador de Apple y no anunciaron correctamente su disponibilidad. Al copiarlas a /private/tmp/AireDisplay-0.2.1 ambos problemas desaparecieron. El muestreo del proceso encontró el bloqueo dentro de la creación de marcadores y extensiones del sandbox del servicio de vídeo; no se ha demostrado la causa completa.

El permiso de pantalla figuraba activado pero TCC rechazaba la firma actual: el registro confirmó que la firma guardada pertenecía a otra compilación. Añadir la app sin borrar la entrada antigua no lo corrigió. Se renovó exclusivamente ScreenCapture de local.airedisplay.Sender y se añadió la copia temporal desde Ajustes, dentro del acceso de captura autorizado por el usuario. La captura posterior funcionó. No se cambiaron permisos de otras apps. Una firma ad hoc cambia entre compilaciones y puede requerir renovar el permiso; falta resolver la firma estable para distribución.

## Incidencia de Rosetta aislada
La prueba experimental de codificar en x86_64 bajo Rosetta producía verde en vez de gris. El producto nunca usa ese codificador: el emisor es exclusivamente ARM. La prueba correspondiente al trayecto real (ARM codifica, Intel decodifica) pasó. Se conserva el registro de la incidencia en build/intel-tests.log. Esto no verifica el decodificador del iMac físico.

## Prueba en el iMac físico
El usuario informó de visor negro y solicitó acceso remoto para diagnosticarlo. Tras iniciar el servicio SSH, se verificó la huella ED25519 directamente contra la huella proporcionada por el usuario y se instaló una clave de diagnóstico autorizada. Equipo confirmado: iMac14,1, x86_64, macOS 10.15.8 (19H2036).

Se ejecutaron IntelDecoderTests e IntelPairingTests en Catalina: 60 imágenes H.264 generadas en ARM, decodificación por hardware, cero fallos de píxeles; enlaces, Bonjour, TLS y aprobación bilateral locales también con cero fallos. Esto valida el códec y el emparejamiento en el equipo físico, pero aún no la transmisión gráfica entre los dos Mac.

El receptor 0.2.1 estaba en Downloads y al abrirlo se ejecutaba bajo AppTranslocation. El muestreo del proceso no mostró un bloqueo: estaba esperando eventos, sin trabajo de vídeo activo. El MacBook estaba detenido; se activó nuevamente para reproducir el fallo. Se pidió al usuario conectar ambos y comunicar el estado de la ventana principal del receptor. No se ha usado SSH para automatizar la interfaz ni capturar su pantalla.

## Corrección 0.2.2 de la conexión entre equipos
El usuario comunicó el error «Conexión en espera: POSIXErrorCode: No route to host». La prueba RouteProbe, ejecutada en Catalina contra los puertos reales del MacBook, reprodujo el fallo al reutilizar como destino la IPv6 local resuelta por Network.framework. Usar el nombre MacBook-Air-de-xuso.local para la segunda conexión dio estado ready; fijar requiredInterface sin conservar el nombre no corrigió el fallo. nc llegó a ambos puertos por IPv4 y por IPv6, y el cortafuegos del MacBook estaba desactivado: no se modificó.

En 0.2.2 las credenciales cifradas incluyen el nombre Bonjour obtenido con SCDynamicStoreCopyLocalHostName. La conexión automática y el enlace manual comparten ese nombre. El visor muestra estado o error hasta recibir una imagen.

Compilación y firmas de ambas apps verificadas. La primera ejecución restringida de CoreTests no pudo iniciar el codificador (-12902); ejecutada con acceso normal pasó. La primera prueba de emparejamiento encontró la app 0.2.1 todavía anunciada y rechazó su versión; al cerrar esa app pasaron PairingTests e IntelPairingTests 0.2.2, incluida la comprobación del nombre Bonjour. IntelDecoderTests pasó bajo Rosetta. En el iMac físico pasaron IntelDecoderTests (60 imágenes, hardware, cero fallos) e IntelPairingTests de 0.2.2.

Receptor 0.2.2 instalado en ~/Applications del iMac, con firma y versión comprobadas. Emisor preparado en /private/tmp/AireDisplay-0.2.2. Se renovó únicamente el permiso ScreenCapture previamente autorizado; Ajustes pidió Touch ID al añadir la nueva firma. Pendiente de autenticación del usuario y de comprobar imagen real entre los dos Mac con esta actualización.

## Pendiente
1. Prueba interactiva de mover y usar ventanas en la pantalla extendida, además de la captura de escritorio ya comprobada.
2. Verificar estabilidad durante varios minutos y recuperación tras suspensión.
3. Resolver ubicación y firma para distribución; actualmente solo se ha verificado la ejecución desde la carpeta temporal.
4. Reproducir y diagnosticar el visor negro del receptor en el iMac de finales de 2013 con Catalina 10.15.8. Ya hay acceso SSH autorizado y pruebas de códec aprobadas en ese equipo.
5. Medir Wi-Fi en los dos equipos: FPS sostenidos, retraso de captura a presentación, recuperación tras suspensión, reconexión, pantalla completa, prueba de varios minutos y retirada de pantalla al desconectar.
6. Medir el retraso visual real; los milisegundos mostrados son una ida/vuelta del protocolo.

El usuario eligió ejecutar una prueba guiada en el iMac físico. Se preparó outputs/AireDisplay-iMac-v0.2.1-PRUEBA.zip con el receptor Intel ya comprobado localmente; es material de prueba, no una entrega final. La firma se verificó y la versión mínima del binario es macOS 10.15. El emisor temporal del MacBook queda disponible en modo extensión, 1080p/60 y 12 Mb/s; se cerró el receptor local para probar con el iMac físico.

## Confirmación física de 0.2.2 y ajuste de fluidez 0.2.3
Ambas apps instaladas en ~/Applications. El usuario confirmó que la imagen ya funciona entre el MacBook y el iMac físico. La interfaz del emisor mostró escritorio extendido activo, 1280×720/30 FPS/20 Mb/s, una muestra de 13 FPS y 73,8 ms de ida/vuelta. Esta medida incluye codificación, transporte, decodificación y encolado, pero no mide el retraso óptico. Queda superado el bloqueo del visor negro de conexión; no se afirma que todas las pruebas de estabilidad estén completas.

0.2.3 sustituye la espera por cada confirmación por una ventana máxima de tres fotogramas. El emisor deja de capturar cuando se llena esa ventana; el receptor limita asimismo el número pendiente. Las confirmaciones deben corresponder a secuencia y marca temporal enviadas. Pruebas de límite, liberación, duplicación y confirmación inválida pasadas; transporte TLS de tres imágenes antes de la primera confirmación pasado. Suite completa ARM y Rosetta: cero fallos (build/tests-0.2.3.log). Pendiente instalar y comparar el flujo gráfico físico de 0.2.3.

## Ajustes en directo 0.2.4
Todos los selectores llaman al motor durante la conexión. El motor detiene nuevas capturas, espera confirmaciones pendientes, cierra la captura anterior y sustituye el codificador manteniendo la secuencia. TLS permanece conectado y no se repite el emparejamiento. FPS/calidad conservan la pantalla virtual; resolución recrea esa pantalla y modo puede retirarla/crearla. macOS puede recolocar ventanas en esos dos casos.

El intento de cambiar modos sobre una pantalla existente seleccionaba tamaños intermedios o impedía retirarla al detener. Se descartó. Al recrear pantallas también se detectó reutilización de la configuración anterior con el mismo número de serie; cada nueva pantalla usa una identidad distinta. La prueba final confirma tamaños efectivos 720p, 1080p y 1440p y retirada de todas las pantallas al detener.

LiveTests usa el SenderEngine real, codificador hardware, TLS real, decoder real y confirmaciones retrasadas 75 ms, con una fuente de imágenes sintéticas que sustituye únicamente ScreenCaptureKit. Pasa cambios de resolución/FPS/calidad, cambios rápidos, duplicación, conexión conservada, secuencias crecientes y limpieza de pantallas. Cero fallos: build/live-0.2.4.log. No equivale a una prueba de actualización de captura real del escritorio.

Suite de códec/transporte/emparejamiento 0.2.4: cero fallos. Decodificador único acepta cuatro reemplazos de codificador con cambios de tamaño/FPS/bitrate y secuencia conservada. En el iMac físico, IntelDecoderTests e IntelPairingTests 0.2.4 pasaron (build/imac-tests-0.2.4.log). Ambas apps instaladas en ~/Applications, receptor con firma y versión verificadas. Pendiente prueba gráfica real de ajustes durante la sesión y comparación de latencia física con 0.2.2.

## Permiso de pantalla y visor 0.2.5
El registro de tccd confirmó que la app instalada 0.2.4 (cdhash 251a01fd…) no coincidía con el permiso guardado (74e791cb…). Desactivar/activar el interruptor conservaba el requisito antiguo. Se cerró la app, se renovó exclusivamente ScreenCapture de local.airedisplay.Sender y se añadió desde Ajustes ~/Applications/AireDisplay MacBook.app. No se cambiaron los permisos de otras apps.

La primera captura real de 0.2.4 ya fue permitida, pero el receptor local se desconectó porque AVSampleBufferDisplayLayer no aceptaba un fotograma de la ráfaga inicial. En 0.2.5 se descarta esa imagen ya decodificada, sin cerrar TLS ni perder el estado de referencias del decoder. Ambas apps compiladas. Permiso renovado de nuevo para la firma final 0.2.5 antes de probarla.

Prueba gráfica real local ARM→receptor Intel bajo Rosetta 0.2.5: escritorio extendido visible; una muestra de 1080p indicó 21 FPS y 11,9 ms de ida/vuelta. Cambio en directo a 720p y luego 6 Mb/s: imagen conservada, conexión activa, sin nuevo emparejamiento ni petición de permiso. No se interpreta el ritmo del escritorio estático como capacidad sostenida, ni la ida/vuelta como latencia óptica. Receptor del iMac físico actualizado a 0.2.5; pendiente comprobar la nueva versión en el trayecto Wi-Fi físico.

La firma continúa siendo ad hoc: otra compilación cambia su requisito. La renovación del permiso debe formar parte de cualquier actualización hasta disponer de una identidad de firma estable. No se ha debilitado el requisito de firma para eludir el control de macOS.

## Optimización 0.2.6
Calidad adaptativa, captura pendiente más reciente, confirmación tras decodificar, presentación limitada a una imagen, tiempos reales de vídeo y soporte Bonjour Wi-Fi entre pares. La red conserva TLS y aprobación bilateral; el nombre local sigue como alternativa si el servicio no conecta. No se ha reproducido el protocolo propietario de Duet.

Suite ARM y Rosetta: cero fallos (build/tests-0.2.6.log). LiveTests: cero fallos, incluidos ajustes durante transmisión, secuencia, retirada de pantallas virtuales y sustitución/limpieza de imágenes pendientes (build/live-0.2.6.log). IntelDecoderTests e IntelPairingTests ejecutados en el iMac físico: cero fallos (build/imac-tests-0.2.6.log).

Comparación física alternada: tres ejecuciones por versión, 15 segundos por ejecución, misma imagen sintética en movimiento a 1080p/60 y techo seleccionado de 20 Mb/s. Se usa el motor real de envío, H.264 por hardware, TLS y decodificación Intel por hardware; no incluye captura de escritorio ni presentación gráfica/latencia óptica.

| Prueba | Versión | FPS recibidos | Mediana de muestras de ida/vuelta (ms) | Peor muestra (ms) | Ruta registrada |
|---|---|---:|---:|---:|---|
| 1 | 0.2.5 | 15.54 | 95.5 | 1527.0 | No instrumentada |
| 1 | 0.2.6 | 11.67 | 260.9 | 1417.4 | en1, red habitual |
| 2 | 0.2.5 | 13.31 | 170.7 | 1423.2 | No instrumentada |
| 2 | 0.2.6 | 28.97 | 19.6 | 243.1 | awdl0, Wi-Fi entre pares |
| 3 | 0.2.5 | 10.90 | 563.0 | 1511.5 | No instrumentada |
| 3 | 0.2.6 | 30.37 | 149.5 | 303.9 | awdl0, Wi-Fi entre pares |

Datos completos en build/performance-comparison.json. La mediana corresponde a muestras periódicas del emisor, no a todos los fotogramas. Decodificación mediana entre 2.29 y 2.40 ms. La mejora no fue uniforme: una ejecución nueva usó en1 y fue peor. Dos eligieron awdl0 y mejoraron FPS y pausas máximas, pero aún hubo retrasos. macOS decide la ruta; no se afirma conexión directa garantizada ni rendimiento equivalente a Duet.

Ambas apps 0.2.6 instaladas en ~/Applications, versiones y firmas verificadas, copias anteriores conservadas. Se renovó únicamente ScreenCapture del emisor. Ajustes solicitó Touch ID; pendiente autenticación del usuario, nueva prueba real de captura y prueba interactiva física de fluidez.

### Captura real 0.2.6 tras autenticación
El usuario completó Touch ID. Ajustes muestra AireDisplay MacBook activado para captura de pantalla. Emisor instalado 0.2.6 y receptor Intel 0.2.6 bajo Rosetta: escritorio extendido visible, distintivo de versión visible. Cambio de 1080p a 720p y techo de calidad de 12 a 6 Mb/s mantiene imagen y conexión sin nueva petición de permiso. Muestra local de 720p: 37 FPS, ida/vuelta 11,9 ms y decodificación 3,3 ms; no representa rendimiento por Wi-Fi ni latencia óptica. El escritorio estático puede producir pocos fotogramas completos.

Receptor local cerrado y MacBook dejado disponible, extensión 720p/60 FPS/calidad automática hasta 6 Mb/s. Pendiente que el usuario abra la app instalada 0.2.6 en el iMac físico, acepte el emparejamiento en ambos y compare la respuesta de ventanas durante uso real.

## Cursor y ratón 0.2.7
El usuario confirmó que 0.2.6 se veía bastante bien, con mucho menos retraso, y autorizó trabajar primero en el lag y el ratón.

Cambios: cursor excluido del vídeo y enviado como posición normalizada en mensajes cifrados (flecha estándar). El ratón local del visor reacciona sin esperar un fotograma. Entrada de movimiento, clic, doble clic, arrastre, botón derecho y rueda vertical. La entrada remota exige Accesibilidad del emisor y conexión autenticada; no se solicita monitorización global de entrada del receptor. El teclado sigue siendo el del MacBook. Posiciones limitadas a la pantalla capturada; bandas negras ignoradas y liberación fuera de la imagen limitada al borde. Movimientos pendientes agrupados; clics y liberaciones se conservan. Se liberan botones al perder foco, cambiar ajustes, desconectar y al salir del emisor.

VideoRouteResolver espera hasta dos segundos para encontrar la interfaz awdl0 anunciada por Bonjour. Si existe, la conexión se abre sobre esa interfaz; si no existe, usa el servicio habitual. Si la conexión falla antes del saludo, queda el nombre local como alternativa. No se garantiza que AWDL siempre esté disponible. H.264 mantiene baja latencia y cambia la frecuencia máxima de imágenes completas de uno a tres segundos para reducir picos periódicos en el transporte fiable.

Pruebas ARM/Rosetta: cero fallos en build/tests-0.2.7.log. PointerTests genera eventos sin publicarlos y comprueba validación, coordenadas, permiso denegado, clics/arrastres/rueda y liberación. PointerViewTests comprueba la imagen con bandas, primer clic, movimientos, doble clic, rueda, salida de límites y pérdida de foco: cero fallos (build/pointer-view-0.2.7.log). Estas pruebas descubrieron y corrigieron un acceso a scrollingDeltaY en eventos que no eran rueda. LiveTests: cero fallos, vídeo sintético, ajustes/orden/conexión/limpieza (build/live-0.2.7.log). En el iMac físico: IntelDecoderTests 60 imágenes, hardware y cero fallos; IntelPointerTests e IntelPairingTests cero fallos, incluida cancelación del selector de ruta.

La primera comparación de 0.2.7 fue interrumpida por un tiempo de espera de transferencia SSH; había pausas severas también en 0.2.6 y ambas usaban en1. No se presentó esa ejecución como mejora. Se añadió la selección de ruta antes de la comparación final.

Comparación final alternada: tres pruebas de 15 segundos por versión, fuente sintética 1080p/60, techo de 20 Mb/s, motor de envío/H.264/TLS/decoder físico. No incluye presentación óptica ni latencia de captura real.

| Prueba | Versión | FPS | Mediana de muestras de ida/vuelta (ms) | Peor muestra (ms) | Interfaz |
|---|---|---:|---:|---:|---|
| 1 | 0.2.6 | 27.11 | 152.5 | 787.4 | awdl0 |
| 1 | 0.2.7 | 27.72 | 144.7 | 711.5 | awdl0 |
| 2 | 0.2.6 | 14.99 | 290.7 | 586.1 | en1 |
| 2 | 0.2.7 | 28.14 | 196.5 | 682.3 | awdl0 |
| 3 | 0.2.6 | 13.67 | 214.1 | 615.2 | en1 |
| 3 | 0.2.7 | 28.56 | 146.9 | 891.6 | awdl0 |

La selección nueva usó awdl0 en las tres pruebas; la anterior lo hizo en una. La mejora principal observada es seleccionar esa ruta de forma más consistente. Las pausas máximas no mejoraron uniformemente: no se afirma eliminación del lag ni equivalencia con Duet. La frecuencia de imágenes completas no se midió de forma aislada.

Ambas apps 0.2.7 instaladas en ~/Applications con copias de 0.2.6 conservadas y firmas/versiones verificadas. Se retiraron enlaces temporales de comparación. Pendiente Touch ID para renovar ScreenCapture previamente autorizado y autorización nueva de Accesibilidad. Aún faltan prueba gráfica de cursor de esta versión y prueba física de control de ratón en el iMac. No se publicaron eventos de entrada de sistema en las pruebas automáticas.

## PRISON DISPLAY 0.3.0 — identidad e interfaz
Nombre público actualizado en ambos bundles, menús, visor, avisos y pantalla virtual. Identificadores internos y esquema de enlace conservados. Logo JPG original incluido como recurso, sin alterar el archivo. Cabecera presenta el logo completo con DISPLAY debajo; icono ICNS con únicamente la O recortada del logo original sobre negro. PNG en tamaños nativos de 16 a 1024 píxeles verificados; CFBundleIconFile y recursos de ambas apps comprobados.

Interfaz oscura nativa compatible con Catalina, tarjetas de pantalla/conexión/estado, botón principal violeta y versión visible. Desplazamiento automático para pantallas pequeñas. Ventanas de MacBook y receptor Intel bajo Rosetta revisadas visualmente; selectores probados. La versión final deja logo, controles, estado y versión visibles sin recorte en el MacBook. Finder de la app instalada muestra PRISON DISPLAY MacBook, versión 0.3.0 y el icono de la O.

Suite de vídeo/TLS/emparejamiento/ratón ARM y Rosetta: cero fallos (build/tests-0.3.0.log). LiveTests final: cero fallos, incluidos creación de pantalla virtual con el nombre nuevo, ajustes en directo y retirada al desconectar (build/live-0.3.0.log). Fuente de vídeo sintética, sin permiso de captura. En el iMac físico: decoder Intel 60 imágenes por hardware, emparejamiento/ruta/cancelación y paquetes de ratón sin fallos (build/imac-tests-0.3.0.log).

Ambas apps instaladas en ~/Applications como PRISON DISPLAY MacBook.app y PRISON DISPLAY iMac.app; firmas y versión verificadas. Apps AireDisplay anteriores movidas a PRISON DISPLAY-backups de cada equipo. Emisor instalado abierto, detenido. La UI del receptor físico debe abrirla el usuario; no se automatizó mediante SSH.

Esta actualización no verifica de nuevo captura real ni control físico del ratón. Continúan pendientes la renovación del permiso de pantalla para la firma actual y la autorización nueva de Accesibilidad solicitada anteriormente. No se ampliaron permisos ni se publicaron eventos de ratón en las pruebas automáticas.


## PRISON DISPLAY 0.3.1 — apps universales e instaladores

Cada app contiene arm64 y x86_64. Emisor: macOS 13+ en ambas arquitecturas. Receptor: Intel 10.15+, arm64 11+. LSMinimumSystemVersionByArchitecture y mínimos de cada Mach-O configurados; identificadores internos, recursos, protocolo y emparejamiento conservados. Intel selecciona codificador H.264 por hardware estándar; ARM conserva RTVC.

Suite ARM y Rosetta: cero fallos (build/tests-0.3.1.log). Suite completa de codificación Intel bajo Rosetta: cero fallos, contenido de imagen, 720p/1080p/1440p, cambios de formato/bitrate y TLS (build/intel-core-0.3.1.log). La ejecución aislada inicialmente impidió acceder al codificador; ejecutada con acceso a los servicios de vídeo, pasó. No se cambiaron permisos de captura ni Accesibilidad.

Dos paquetes productbuild sin Developer ID ni notarización, versión 0.3.1, destino /Applications, sin scripts. Expansión de ambos: bytes de apps idénticos a la compilación, firma ad hoc estricta válida para todas las arquitecturas, dos arquitecturas presentes, versiones/logo/icono correctos. Requisitos de arquitectura y macOS incluidos en Distribution. installer -showChoicesXML acepta ambos en el Mac actual sin instalar. Asistente de ambos revisado: nombre, versión, requisitos y aviso de firma; emisor revisado hasta pantalla previa a Instalar, cerrado sin instalación. SHA256 y manifest incluidos.

Prueba de captura real iniciada por error al compilar LiveTests con Capture.swift: la fuente estática no produjo cinco imágenes antes de diez segundos (una comprobación falló); los ajustes posteriores, duplicación/extensión y limpieza sí pasaron. No se interpreta como prueba sintética ni de fluidez. Se repitió con CaptureStub.swift para comprobar el motor con vídeo sintético: cero fallos, incluidos cambios de ajustes/conexión/secuencia y retirada de pantalla virtual (build/live-synthetic-0.3.1.log).

El iMac físico no respondió a SSH en esta sesión; no se verificó de nuevo allí esta versión. La captura real del emisor Intel con macOS 13+, la instalación completa de los paquetes y las pruebas Wi-Fi/control de ratón en los otros equipos están pendientes. Un binario universal no garantiza compatibilidad con todos los Mac ni versiones futuras del sistema; la extensión depende de la interfaz privada CGVirtualDisplay y el envío requiere codificador por hardware. La guía y bienvenida del emisor indican la validación Intel pendiente.


### Validación física de 0.3.1 tras despertar el iMac

2 de octubre de 2026. SSH reconectado al mismo equipo verificado: iMac14,1, Catalina 10.15.8. IntelDecoderTests: 60 imágenes generadas en ARM decodificadas por hardware, cero fallos de contenido. IntelPairingTests: cero fallos, incluidos Bonjour, aprobación/código, TLS y selección/cancelación de ruta. IntelPointerTests: cero fallos de protocolo y coordenadas; no se publicaron eventos de entrada.

El paquete receptor 0.3.1 se expandió en /private/tmp, firma estricta válida para todas las arquitecturas y installer -showChoicesXML acepta sus requisitos en Catalina. No se realizó instalación administrativa ni se abrió remotamente la interfaz gráfica del iMac.

IntelCoreTests genérico se detuvo con SIGILL en main. El test usaba encoded.last! tras esperar una única imagen, sin detenerse cuando no llegaba salida; se añadió guard para informar del tiempo de espera en lugar de caer. No se da esa suite por aprobada en el Intel físico. Una prueba específica alimentando la secuencia completa (Tests/IntelEncoder/main.swift) pasó: 60 imágenes 720p y 60 imágenes 1080p a 30 FPS, todo decodificado, tres canales correctos y codificador/decoder por hardware, cero errores (build/intel-encoder-physical-0.3.1.log). No valida captura del emisor Intel ni su rendimiento en macOS 13+.

Transporte físico con el motor de envío real y fuente sintética 1080p/60, techo de 6 Mb/s durante 15 segundos: 489 imágenes recibidas y decodificadas, 32.68495 FPS, hardware=true. Interfaz awdl0. Decodificación mediana 2.287745 ms, p95 2.485287 ms. Mediana de muestras de ida/vuelta 151.1 ms; peor muestra 350.4 ms. Logs build/wifi-0.3.1-{sender,imac}.log. Sin pérdida de imágenes entre recepción y decoder. No mide captura de escritorio, presentación gráfica, latencia óptica ni ratón físico; no es una comparación contra versiones anteriores.

Actualizada la documentación del ZIP de instaladores; apps, paquetes, versiones y sus sumas SHA256 conservados sin reconstrucción. Continúan pendientes instalación completa y prueba gráfica en los otros equipos, captura Intel con macOS 13+ y control físico del ratón.


### Bucle de permiso de captura tras instalar 0.3.1

Los registros de tccd confirman Failed to match existing code requirement: permiso ScreenCapture asociado al cdhash c9bd… de 0.3.0, app en ejecución /Applications/PRISON DISPLAY MacBook.app con requisitos 3c0499…/27eb3c… de 0.3.1. Existía otra copia 0.3.0 en ~/Applications. App cerrada, copia antigua conservada en Documents/Codex/PRISON DISPLAY/Copias anteriores/0.3.0. tccutil reset ScreenCapture exclusivamente local.airedisplay.Sender completado; no se tocaron Accessibility ni permisos de otras apps. Añadir la copia /Applications a Grabación de pantalla en Ajustes solicita Touch ID; pendiente autenticación del usuario y captura real. Instalado comparado byte a byte con paquete 0.3.1. No se reconstruyó la app ni se alteró la firma. La firma ad hoc todavía puede requerir renovar este permiso tras actualizar; no se debilitó el requisito de código.


### Captura real 0.3.1 tras renovar el permiso

Usuario completó Touch ID. Ajustes muestra PRISON DISPLAY MacBook activado para Grabación de pantalla. Se abrió exclusivamente /Applications/PRISON DISPLAY MacBook.app, emisor 0.3.1, y receptor universal 0.3.1 local. Descubrimiento, mismo código y aprobación bilateral: escritorio extendido 1920×1080 visible en visor, sin petición adicional de permiso. Se detuvo y cerró/reabrió la app, se emparejó de nuevo y se confirmó por segunda vez imagen real con captura activa y versión visible. Los registros posteriores no muestran rechazos de ScreenCapture; sí muestran requisito antiguo de Accessibility, pendiente de renovación autorizada para ratón. No se tocó ese permiso ni se inyectaron eventos.

Muestra local de segunda conexión: escritorio estático 1 FPS, ida/vuelta 13.7 ms y decoder 5.2 ms. No representa FPS máximo ni latencia física/Wi-Fi. Receptor local cerrado y pantalla de prueba retirada; emisor dejado disponible para conectar al iMac físico. App y paquetes mantienen 0.3.1, sin reconstrucción ni cambio de firma. La corrección renueva la referencia local de TCC; actualizaciones futuras con firma ad hoc pueden requerir volver a autorizarla.


### Renovación de Accesibilidad 0.3.1

El usuario informó del mismo bucle al pulsar Permitir ratón del iMac. Captura 0.3.1 ya funciona. Los registros recientes confirman requisito antiguo de Accessibility frente a firma universal 0.3.1. Conexión detenida, app cerrada y tccutil reset Accessibility exclusivamente local.airedisplay.Sender completado. Ajustes → Privacidad y seguridad → Accesibilidad ya no lista la entrada antigua. Añadir solicita Touch ID: pendiente autenticación y selección /Applications/PRISON DISPLAY MacBook.app, después verificación del permiso en la app. No se cambió ScreenCapture ni permisos de otras apps, no se reconstruyó el binario.


### Accesibilidad 0.3.1 renovada y reconocida

Tras la autenticación del usuario, Ajustes muestra PRISON DISPLAY MacBook activado en Accesibilidad. App abierta por ruta exacta /Applications/PRISON DISPLAY MacBook.app: pulsar Permitir ratón del iMac informa Ratón del iMac autorizado sin pedir permiso. Se cerró y reabrió la app y se repitió: mismo resultado, sin aviso ni nuevo reinicio. Emisor dejado disponible para el iMac físico. No se publicaron eventos de ratón en esta verificación; falta prueba interactiva física de clic/arrastre/rueda. No cambió versión, firma ni permiso de captura.


## Cursor 0.3.2: compilación final y límites

PRISON DISPLAY · v0.3.2 · 2 de octubre de 2026

Cursor del MacBook mostrado en el iMac:
- Muestreo en cola independiente del codificador.
- Un envío en curso y una posición reciente pendiente como máximo.
- Descarte de posiciones antiguas al recuperarse de un bloqueo.
- Visor que agrupa movimientos pendientes y dibuja solo la posición más reciente.
- Comprobación de Accesibilidad al preparar la captura, en vez de cada movimiento.
- No envía posiciones repetidas mientras el cursor está quieto.

Pruebas de la compilación final:
- Ambas apps universales: Intel y chip Apple, versión 0.3.2, firma de integridad válida.
- Envío limitado, descarte de movimientos atrasados, desconexión y rechazo de clave errónea: 0 fallos en ARM, Rosetta e iMac Intel físico con Catalina 10.15.8.
- Visor: coordenadas, clic, arrastre, liberación, rueda y agrupación de posiciones: 0 fallos. Sin eventos reales de entrada en el sistema.
- Flujo sintético con emisor real: TLS, extensión, cambios de resolución/FPS, duplicación y retirada de pantalla virtual: 0 fallos. Sin captura real del escritorio.
- Instaladores expandidos: ejecutables idénticos a las apps finales, firma estricta válida y ambas arquitecturas presentes.

Medición final por Wi-Fi: MacBook M4 e iMac 2013, ruta AWDL, imagen y cursor sintéticos, 1080p, objetivo 60 FPS, límite 6 Mb/s, tres sesiones de 15 segundos. Incluye inicio y adaptación de calidad. Se mide el intervalo entre posiciones recibidas, no el retraso óptico ni el tiempo entre movimiento físico y dibujo en pantalla.

Sesión 1: RESULT version=0.3.2 frames=815 decoded=815 fps=54.45278258716984 hw=true decodeMedianMS=2.224949 decodeP95MS=2.45409
CURSOR RESULT dedicated=false samples=939 medianGapMS=15.689574 p95GapMS=21.16785 maxGapMS=1023.908942

Sesión 2: RESULT version=0.3.2 frames=827 decoded=827 fps=55.965938613276236 hw=true decodeMedianMS=2.210504 decodeP95MS=2.388991
CURSOR RESULT dedicated=false samples=939 medianGapMS=15.856049 p95GapMS=20.875594 maxGapMS=396.792719

Sesión 3: RESULT version=0.3.2 frames=434 decoded=434 fps=29.43439455300973 hw=true decodeMedianMS=2.291035 decodeP95MS=2.472603
CURSOR RESULT dedicated=false samples=939 medianGapMS=15.304091 p95GapMS=21.633424 maxGapMS=872.532636

La conexión independiente de cursor se probó y quedó desactivada: en tres comparaciones empeoró las pausas máximas (~865–873 ms frente a ~306–318 ms con el transporte compartido). La versión entregada conserva el transporte compartido con acumulación limitada de posiciones.

La mediana entre posiciones de la configuración final fue ~15–16 ms. Siguen apareciendo pausas ocasionales (~397–1024 ms). No se ha demostrado que desaparezca el enganchón observado por el usuario ni una mejora porcentual respecto a 0.3.1.

Pendiente: instalar esta compilación, renovar permisos si macOS lo solicita, captura gráfica real 0.3.2 y prueba interactiva física con el ratón del MacBook. La captura real y persistencia de permisos se habían comprobado con 0.3.1; no sustituyen la prueba de 0.3.2. El emisor Intel sigue sin validación física en un Intel con macOS 13+.

### Preparación de instalación 0.3.2

Instalador MacBook abierto en el asistente de Apple; pendiente autenticación del usuario. Copia 0.3.1 conservada en Documents/Codex/PRISON DISPLAY/Copias anteriores/0.3.1. Instalador receptor transferido a Desktop/PRISON-DISPLAY-v0.3.2 del iMac y SHA256 verificado contra manifest. El usuario debe terminar los asistentes y después comprobar captura/ratón reales; no se han renovado permisos ni se afirma completada la instalación.

### Bucle de Accesibilidad tras instalar 0.3.2

Confirmada app activa /Applications/PRISON DISPLAY MacBook.app v0.3.2. tccd registra rechazo porque Accessibility conserva requisitos 3c049977…/27eb3c92… de 0.3.1, frente a bcf036dc…/78fb2145… actuales. Se detuvo y cerró la app y se renovó únicamente Accessibility de local.airedisplay.Sender con tccutil. Ajustes ya no muestra la entrada antigua; Añadir solicita Touch ID. Pendiente autenticación del usuario, selección de la copia actual y comprobación tras reiniciar la app. No se modificó permiso de pantalla, ejecutable, firma ni versión.

### Accesibilidad 0.3.2 reconocida tras renovación

Usuario completó la autenticación y Ajustes muestra PRISON DISPLAY MacBook activado en Accesibilidad. Abierta la copia exacta /Applications/PRISON DISPLAY MacBook.app v0.3.2: Permitir ratón del iMac informa Ratón del iMac autorizado sin diálogo adicional. Cerrada y reabierta la app, repetida la comprobación con el mismo resultado. Sin reconstrucción, cambio de firma ni de permiso de pantalla. No se publicaron eventos de entrada del sistema; pendiente la comprobación física del control desde el iMac. App dejada abierta y lista para iniciar conexión.


## Firma persistente 0.3.3 → 0.3.4

PRISON DISPLAY · v0.3.4 · Corrección de identidad entre actualizaciones

Cambios:
- Firma local persistente con un certificado exclusivo de PRISON DISPLAY.
- Requisito que exige el identificador y ese certificado exacto; no está ligado al hash de cada compilación.
- El proceso de compilación falla si falta la identidad. No genera otra ni vuelve a firma ad hoc.
- La app comprueba Accesibilidad sin mostrar otra solicitud automática. Si falta, el botón abre Ajustes.
- La captura comprueba el permiso antes de iniciar y muestra instrucciones si falta, sin reiterar solicitudes en cada intento.
- Sin cambios de confianza de certificados, Gatekeeper, SIP o permisos concedidos automáticamente.

Comprobado:
- Dos versiones diferentes (0.3.3 y 0.3.4), ejecutables distintos, mismo certificado y mismo requisito.
- Validación estricta de ambas arquitecturas de emisor y receptor.
- Una app firmada ad hoc con el mismo identificador no satisface la identidad nueva.
- Una modificación de un recurso sellado invalida la firma.
- Certificado incrustado idéntico al certificado persistente esperado.
- Receptor validado mediante codesign estricto en el iMac físico con Catalina 10.15.8, sin importar certificados ni alterar confianza allí.
- Suite vídeo, TLS, emparejamiento y ratón ARM/Rosetta: cero fallos.
- Paquetes finales expandidos: firma válida, ejecutable idéntico a la app final, versión 0.3.4 y sin claves privadas, llaveros o contraseñas.

Prueba real completada en el MacBook del usuario el 2 de octubre de 2026: instalación 0.3.3, autorización inicial de pantalla y Accesibilidad, captura real del escritorio extendido y comprobación de Accesibilidad autorizada. Actualización mediante el instalador a 0.3.4 sin reiniciar ni modificar ningún permiso: captura real 1920×1080 visible en el receptor local y botón de ratón autorizado sin diálogo adicional. Cerradas y reabiertas ambas apps 0.3.4, se repitieron emparejamiento, imagen real y comprobación de Accesibilidad con el mismo resultado. Esta prueba verifica la conservación de ambos permisos en esta actualización y este Mac; no sustituye la prueba interactiva física del ratón del iMac.

La captura del emisor Intel en un Intel con macOS 13+ y el control interactivo físico del ratón siguen pendientes. El emisor requiere macOS 13 o posterior; receptor Intel Catalina 10.15+.

Se conservó la copia anterior 0.3.2. La sustitución directa en Aplicaciones fue denegada por el sistema; la app permanece 0.3.2 hasta completar el instalador estándar de Apple. Se renovaron únicamente ScreenCapture y Accessibility de local.airedisplay.Sender para la transición autorizada; no se concedieron permisos automáticamente.


## 0.3.5 · Cursor, reconexión y preferencias

PRISON DISPLAY · v0.3.5

- Cursor del MacBook: se recalcula su posición con los límites actuales de la pantalla, incluso después de moverla en Ajustes. Se evita ocultarlo indefinidamente junto a una posición antigua del ratón del iMac.
- Reconexión automática después de un corte de una sesión ya aceptada, con espera progresiva de 1 a 10 segundos. Conserva en memoria la misma clave de esa sesión y la pantalla virtual. Detener, Desconectar o cerrar las apps cancela los reintentos; un nuevo inicio del emisor necesita emparejar de nuevo.
- Modo, resolución, FPS y calidad se guardan al cambiarlos y se recuperan al abrir la app.
- Posición de la pantalla guardada durante el uso y al detener. Se restaura al recrearla y se mantienen los lados al cambiar resolución.
- Ventana del visor con posición y tamaño guardados.
- La pantalla virtual tiene un proceso auxiliar dentro de la misma app para retirarla correctamente después de que macOS haya cambiado su colocación. No instala servicios ni necesita permisos nuevos.
- Misma firma persistente de 0.3.3 y 0.3.4. No se reinician ni se amplían permisos de pantalla o Accesibilidad.

Instala 0.3.5 en ambos Mac y abre las copias de Aplicaciones. La reconexión cubre cortes de la sesión mientras el emisor sigue abierto; no guarda credenciales de conexión en disco ni empareja automáticamente otro ordenador.

PRISON DISPLAY · v0.3.5 · Pruebas del 2 de octubre de 2026

Completado:
- Compilación universal arm64/x86_64 y firma estricta de ambas apps, con el mismo certificado persistente y requisitos que 0.3.3/0.3.4. Una firma ajena con el mismo identificador y un recurso alterado se rechazan.
- Vídeo/H.264 hardware, TLS, emparejamiento, ruta y paquetes de ratón: suites ARM y Rosetta, cero fallos (build/tests-0.3.5.log).
- Visor: mapeo de clic, arrastre, rueda, primer clic, límites, liberación, capa visible del cursor, coordenadas superiores y descarte de posiciones antiguas. ARM y Rosetta, cero fallos; sin publicar eventos del sistema (build/features-0.3.5.log, secciones PointerView).
- Receptor real con TLS y vídeo H.264: tres cortes, reconexión automática, nuevos fotogramas y cursor recibidos, cancelación manual y rechazo de una clave incorrecta. ARM, Rosetta y el iMac físico con Catalina: cero fallos.
- Ajustes persistentes y recuperación segura de valores fuera de rango: ARM, Rosetta y Catalina, cero fallos.
- Pantalla virtual: colocar a la izquierda, retirar, recrear en la misma posición, cambiar tamaño manteniendo el lado y recuperar el conjunto original de pantallas: cero fallos (build/virtual-0.3.5.log).
- Motor emisor real, captura sintética y vídeo hardware por TLS: cambios de resolución/FPS/calidad, duplicación/extensión, posición del cursor después de recolocar, corte, reconexión con el mismo monitor y colocación, y retirada final. Prueba final cero fallos (build/live-0.3.5.log). Pruebas anteriores detectaron el problema de retirada; se corrigió separando la vida de la pantalla virtual.
- App 0.3.5 instalada en el MacBook: ejecutable idéntico al de la compilación final, firma válida, pantalla extendida 1920×1080 visible en receptor local, Accesibilidad autorizada y control de un clic hacia la pantalla virtual comprobado. Actualización desde 0.3.4 sin cambiar ni volver a conceder permisos.
- Instalador del iMac transferido y hash comprobado en el iMac físico.

Pendiente de prueba interactiva final del usuario: visibilidad/fluidez del cursor entre los dos Mac físicos con las apps 0.3.5, suspensión y recuperación Wi-Fi en uso real. Los cortes de laboratorio no equivalen a todas las caídas de un router. Si se cierra o reinicia el emisor, hace falta emparejar de nuevo.

El emisor Intel sigue sin prueba de captura real en un Intel con macOS 13+. Emisor macOS 13+, receptor Intel Catalina 10.15+, receptor Apple Silicon macOS 11+. La interfaz de pantalla virtual es privada y puede variar entre macOS.

Validación GUI adicional 0.3.5: ajuste real a 30 FPS, app cerrada/reabierta y 30 FPS conservados. Se restauraron los 60 FPS iniciales. Comprobación de Accesibilidad tras reapertura: autorizado sin diálogo. Emisor dejado Disponible para conectar; receptor local de prueba cerrado. iMac físico instalado 0.3.4 en la última comprobación; paquete 0.3.5 y guías en su Escritorio, hash verificado, pendiente instalación del usuario y confirmación visual del cursor.
Los paquetes 0.3.5 expandidos contienen el ejecutable final idéntico para cada rol, versión correcta, firma estricta de ambas arquitecturas y ninguna clave privada/llavero/contraseña. La prueba gráfica local de un clic colocó el puntero en la pantalla virtual (lectura de CoreGraphics); no se afirma medida óptica de latencia del iMac.

## 0.3.8 — 4 de octubre de 2026

PRUEBAS · PRISON DISPLAY v0.3.8

Verificado:
- Compilación universal arm64/x86_64 de ambas apps y versión 0.3.8 en los paquetes.
- H.264, cifrado TLS, validación de mensajes y emparejamiento bilateral: MacBook y pruebas Intel/Rosetta.
- En el iMac físico Catalina 10.15.8: decodificación H.264 por hardware, descubrimiento/emparejamiento, cursor, transporte, mensajes de teclado, visor, reconexiones y preferencias.
- Flujo de emisor con CAPTURA SINTÉTICA: cambios de resolución/FPS/calidad/modo/cursor, conservación de posición, cortes/reanudación y retirada de la pantalla virtual.
- Teclado con eventos simulados: permiso, foco del visor, repetición, modificadores, liberación al desconectar/desactivar y atajos locales. Ninguna pulsación de prueba se envió al escritorio del usuario.
- Cursor bajo transporte bloqueado: solo conserva la última posición; las respuestas antiguas no reactivan una sesión detenida.
- Conexión aprobada recordada: espera al emisor cuando este se abre más tarde; detener cancela los reintentos.
- Errores remotos permanentes visibles y sin bucle de reconexión.
- Guardar/actualizar/olvidar en el Llavero: probado en el MacBook con credencial ficticia y cuenta temporal; no se leen conexiones del usuario.
- Diseño nativo a 600/660/900 puntos en MacBook y Catalina: sin tarjetas colapsadas, controles solapados ni textos comprimidos.
- Firma: mismo certificado y requisito designado que versiones anteriores en ambas arquitecturas. Firmas ad hoc y recursos alterados rechazados.
- Instaladores desempaquetados: ejecutables, logo, icono y versión coinciden con la compilación final; no incluyen claves privadas ni herramientas de SSH.

Pendiente de prueba manual:
- Captura real 0.3.8 entre ambos equipos, forma del cursor en FL Studio, teclado/atajos reales y sensación/medición física del lag por Wi-Fi. No se afirma una reducción medida del retraso total.
- Persistencia en el Llavero desde la app gráfica del iMac: el diagnóstico por SSH falló con -25308 (interacción no permitida). No se desbloqueó ni alteró el Llavero; la función es opcional y la conexión normal continúa si falla.
- Instalación completa de estos paquetes y continuidad real de permisos tras actualizarlos. Se verifica la identidad estáticamente, sin modificar TCC.
- Captura del emisor en un Intel con macOS 13 o posterior y funcionamiento en los otros Mac no disponibles.

La versión instalada 0.3.7 permanece disponible; estas pruebas no sustituyeron las apps de producción.


### Comprobación real 0.3.8 — 4 de octubre de 2026
Ambas apps instaladas en Aplicaciones verificadas como 0.3.8. El iMac físico detecta por Bonjour el anuncio _airepair._tcp del MacBook; los puertos observados son accesibles por TCP. Se abrió el receptor a petición del usuario y se entregó el enlace temporal mediante SSH con clave de host verificada, sin mostrar ni guardar la clave. El emisor muestra Escritorio extendido activo y confirmaciones reales del receptor a 1920×1080, con decodificación de 2.3 ms. El dato observado de ida/vuelta fue 254.4 ms con escritorio sin actividad; no es una medición óptica del cursor ni garantía de fluidez. No se cambiaron los permisos ni se habilitó Recordar. Pendiente: valoración visual/física del iMac, emparejamiento por código de esta sesión y persistencia del Llavero desde su sesión gráfica.


## 0.3.14 — 8 de octubre de 2026

Versión preparada para prueba física del usuario; no se declara resuelto el lag.

La compilación universal, firma persistente, expansión de paquetes y exclusión de claves privadas pasaron. Core: 300 comprobaciones; features: 314; canal independiente: 20. Registros finales: build/core-ready-0.3.14.log, features-ready-0.3.14.log, interactive-ready-0.3.14.log, signing-ready-0.3.14.log, verify-packages-ready-0.3.14.log.

Pruebas nativas en Catalina, cero fallos: prioridad, cursor, reconexión, canal independiente, emparejamiento y 60 imágenes por hardware. Registros: build/catalina-core-ready-0.3.14.log y catalina-features-ready-0.3.14.log. Una comprobación inicial de lectura de opciones IP falló: Catalina devuelve .any en una nueva envoltura. Se comprobó con conexiones DNS reales que .v4 y .v6 sí seleccionan sus respectivas familias; se sustituyó esa introspección por una prueba de comportamiento. Se conservan los registros iniciales del fallo.

Cuatro muestras con captura real, escena repetible y ReceiverEngine/VideoView en el iMac: vídeo 20,50–22,98 FPS anterior frente a 24,97–26,40 candidata (media +18,13 %), pero pausas de cursor de 197–199 ms siguen presentes. Registros: build/video-real-visor-0.3.14.json. El contador de presentación cuenta llamadas al método del visor, no observación óptica.

Transporte de entrada final, cuatro muestras equilibradas de 15 s: p95 de respuestas 181–272 ms anterior frente a 9,39–9,98 ms candidata. La candidata agrupa posiciones: 1204/1802 y 1204/1801 respuestas; máximos 225 y 99 ms. Los percentiles excluyen posiciones agrupadas. Son movimientos simulados con Wi-Fi y ReceiverEngine reales; no latencia óptica del ratón físico. Registro: build/control-comparison-0.3.14.json y control-comparison-ready-0.3.14.log.

Paquetes públicos verificados en /Users/xuso/Documents/Codex/PRISON DISPLAY/PRISON-DISPLAY-v0.3.14. Receptor y guía copiados al escritorio del iMac, con SHA-256 idéntico. La instalación definitiva necesita autorización administradora de macOS en cada equipo; pendiente al cerrar estas comprobaciones.

### Instalación real 0.3.14 — 8 de octubre de 2026
El MacBook ya tenía la 0.3.14, con ejecutable idéntico al paquete público. El iMac seguía en 0.3.13. Con la autorización directa del usuario, el instalador estándar actualizó el iMac a 0.3.14 y terminó correctamente. Verificación posterior en Catalina: versión, firma estricta de ambas arquitecturas y requisito persistente correctos; SHA-256 del ejecutable c2ac236aa97866ef2269ea87c376fd475f2df55c250eec8fcf73f738012c782c, idéntico al paquete comprobado. Se abrió la app del iMac. No se modificaron permisos, confianza ni preferencias de seguridad.
La coincidencia de versiones está comprobada; no se afirma que ambas estén transmitiendo ahora. La apertura del MacBook se bloqueó durante esta sesión.

## 0.3.15 — 8 de octubre de 2026 · candidata interna

- Core: 313 comprobaciones pasadas, incluyendo arranque, incremento, congestión, enfriamiento y cambios de máximo de la calidad adaptativa. Registro build/core-0.3.15.log.
- Funciones de escritorio, recuperación, cursor, prioridad, reconexión y preferencias: las secciones anteriores a Live de build/features-final-0.3.15.log pasaron en ARM y Rosetta. No se considera aprobada la suite completa: Live tuvo fallos.
- Canal independiente: 20 comprobaciones pasadas en ARM/Rosetta, incluyendo bloqueo artificial de decodificación de 700 ms, orden de clics/teclas y cierre de sesión si falla el control. No se publicaron eventos de entrada. Registro build/interactive-final-0.3.15.log.
- iMac físico Catalina: 11 ejecutables de prueba, cero salidas fallidas. Incluyen decodificador Intel, emparejamiento, coordenadas/invalidación de caché, escritorio, recuperación, cursor, prioridad, visor, reconexión, preferencias y canal independiente. Registro build/catalina-ready-0.3.15.log y resumen JSON homónimo. Estos ejecutables comprueban componentes; no sustituyen la sesión completa con captura del MacBook.
- Ambas apps universales compilaron; mismo certificado y requisitos desde 0.3.3. Firma ad hoc y recurso modificado rechazados. Paquetes internos expandidos: versión, ejecutable, logo, icono y firma correctos, sin claves privadas/SSH/llaveros. Registros build/build-ready-0.3.15.log, signing-ready-0.3.15.log y verify-packages-ready-0.3.15.log.
- Interfaces renderizadas con AppKit en el iMac: 180 comprobaciones del emisor y 182 del receptor, cero fallos a 600/660/900 puntos. Calidad/FPS/modo/cursor corresponden a los valores elegidos; inspección visual de ambas imágenes sin solapamientos. El emisor de este diagnóstico usa captura sintética y destino 10.15 sólo para comprobar dibujo; la app emisora distribuible sigue requiriendo macOS 13+. Registros build/layout-Sender-Catalina-0.3.15.log y layout-Receiver-Catalina-0.3.15.log.
- Comparación física de cuatro muestras equilibradas, captura real y escena de texto en movimiento: build/real-comparison-0.3.15.json. Se registran tanto las mejoras de cadencia del cursor como las pausas y baja frecuencia de vídeo, sin afirmar ausencia de lag ni 60 FPS.

Pendiente / bloqueado:
- Live, extensión, cambio de ajustes en la sesión completa y reconexión con recolocación. Se detectaron fallos de arranque y pérdida de conexión; se separó la cola del receptor de la interfaz y se añadió el mismo latido de control del producto. La repetición no pudo completar la creación de pantalla virtual. Se mantienen build/live-final-0.3.15.log y live-authorized-0.3.15.log.
- Al abrir la prueba como app de la sesión gráfica, quedó esperando a SkyLight/CoreGraphics. La app ya instalada 0.3.14 también dejó de responder al abrirse. Los muestreos propios muestran esperas en CGSGetDisplaySystemState y en la inicialización de pantallas; no se ha identificado la causa. No se reinició WindowServer, no se desbloqueó la sesión ni se cambiaron permisos.
- La repetición final de nitidez de texto quedó bloqueada antes de producir resultados y se terminó. Los resultados parciales anteriores se conservan y no se presentan como aprobación final.
- El Llavero devolvió -25293 al leer la conexión recordada. La variante de consulta diagnóstica posterior se bloqueó en una confirmación del sistema y se terminó; no se incorpora ese cambio al producto ni se alteran registros o acceso del Llavero.
- Ratón físico y latencia óptica, estabilidad sostenida de imagen y captura del emisor Intel en macOS 13+. El usuario está apartado; se solicitó comprobar la sesión del MacBook al volver.

Estado: paquetes 0.3.15 internos; no publicados ni instalados. Ambas apps instaladas y comprobadas como 0.3.14. No se dan por resueltos los fallos de prueba ni el lag.

## 0.3.16 — 8 de octubre de 2026 · limpieza de ICC realizada, registro pendiente

El MacBook arrancó a las 07:53:34. Se encontró un informe anterior de sobrecarga de colorsync.displayservices (00:37:30–00:40:22) con 90 s de CPU en 172 s y trabajo de creación/lectura de perfiles iniciado por WindowServer. No demuestra por sí solo la causa exclusiva del último bloqueo. Había 297 perfiles ICC de PRISON DISPLAY/AireDisplay antes de estas pruebas; el código anterior daba una identidad aleatoria a cada pantalla.

Comprobaciones completadas:
- Core: 313 comprobaciones, cero fallos. build/core-0.3.16.log.
- Primera revisión 0.3.16 de vida/identidad de la pantalla: 325 comprobaciones de funciones, cero fallos; incluye cambios de resolución/FPS/calidad/cursor, duplicar/extender, corte y reconexión manteniendo identidad/posición. Se crearon tres perfiles para las tres resoluciones. build/features-0.3.16.log.
- Repetición de VirtualTests: 22 comprobaciones, cero fallos y cero perfiles nuevos. Incluye auxiliar que ignora SIGTERM, respuesta fragmentada, respuesta inválida, segunda copia rechazada e identidad ColorSync reutilizada. build/virtual-repeat-0.3.16.log.
- Canal independiente: 20 comprobaciones ARM/Rosetta, cero fallos, incluido bloqueo de decodificación de 700 ms y orden de entrada. Sin publicar eventos. build/interactive-0.3.16.log.
- Captura real M4→Catalina: ocho configuraciones en una conexión, 876 imágenes decodificadas y enviadas al visor; formatos y modos recibidos. Cero perfiles nuevos. Este ensayo corto no aprobó rendimiento sostenido: la extensión terminó con pocas imágenes, y la cadencia de cursor agregada incluye el intervalo con cursor incrustado. build/settings-real-0.3.16.log.
- Nitidez generada: 90/90 imágenes en cada objetivo 12/20/40/60 Mb/s, cero omisiones ni fallos. El ensayo local de 60 no demuestra decodificación por hardware a 60 en el iMac; el producto conserva un máximo de 40. build/quality-fixture-0.3.16.log.
- Interfaz: 362 comprobaciones de geometría a 600/660/900 puntos, cero fallos; ambas imágenes inspeccionadas. La app MacBook 0.3.16 abrió y mostró Disponible para conectar; la copia de pruebas informó Llavero -25293 y mantuvo la conexión manual disponible. build/layout-0.3.16.log y UI-Sender/Receiver-0.3.16.png.
- Política y monitor de sobrecarga: 11 comprobaciones por arquitectura, incluyendo ráfaga breve, recuperación, carga persistente, cancelación y consulta limitada de metadatos sin señales al sistema. La última acción de retirar el auxiliar independientemente de la cola de entrada está compilada, pero pendiente de su ensayo de integración completo.
- Catalina físico: 12 ejecutables de componentes, 209 comprobaciones PASS y cero salidas fallidas. Incluye GraphicsSafetyTests, decodificación, entrada, reconexión y preferencias. build/native-protected-0.3.16.log y catalina-ready-0.3.16.json.
- Últimas apps universales: compilación y firma persistente correctas; misma identidad que 0.3.3, rechazo de firma ad hoc y recurso alterado. Paquetes expandidos: versión, binarios, recursos, firma y exclusión de claves privadas correctos. build/build-0.3.16.log, signing-protected-0.3.16.log y packages-verification-protected-0.3.16.log.

Pruebas detenidas y trabajo pendiente:
- La extensión real prevista de 90 s se detuvo a los 9,32 s por carga combinada de ColorSync superior al límite durante cinco muestras; cero perfiles nuevos. build/extended-stability-0.3.16.log.
- La repetición con la protección inicial se detuvo a los 85,62 s durante Live, por el mismo límite externo. No se presenta como suite completa aprobada. build/features-protected-0.3.16.log. Se ha reforzado después la retirada independiente y añadido ensayos de cola de entrada bloqueada, captura sin respuesta y salida limitada; aún deben completarse.
- Los servicios de color continuaron mostrando carga elevada con las pruebas cerradas. No se han reiniciado WindowServer ni el equipo, cerrado otras apps, cambiado permisos, eliminado preferencias de pantallas o borrado perfiles.
- Respaldo verificado de 297 perfiles históricos propios, excluyendo fabricante/modelo ajenos y las tres identidades nuevas. build/colorsync-backup-2026-10-08/manifest.json y REPARACION.md. Tests/Safety/profiles.py ofrece verificación, traslado reversible y restauración; apply/restore requieren la autorización expresa preparada en esta conversación y acceso de administrador. No forma parte de las apps ni instaladores.
- Tras la autorización: reparación acotada, comprobar carga, completar Live y extensión prolongada, actualizar ambos equipos, verificar sus versiones/firma y probar la conexión real. La aceptación del ratón físico sigue siendo necesaria para afirmar que el lag está resuelto.

Estado actual: versión 0.3.16 candidata interna, no instalada ni publicada. Continúan instaladas las dos apps 0.3.14. La reparación del sistema y la validación final están pendientes; el problema no se da por resuelto.

### Reparación autorizada y repetición, 8 de octubre

- El usuario autorizó la limpieza propuesta. Se apartaron exactamente 297 ICC antiguos a build/colorsync-backup-2026-10-08/quarantine. Los originales respaldados y los apartados conservan sus hashes. Permanecen 13 perfiles de pantalla: tres identidades actuales propias y diez ajenos.
- La primera terminación normal no retiró los procesos. El reinicio mediante launchctl fue rechazado por SIP; no se alteró SIP. La terminación exclusivamente de colorsyncd/colorsync.displayservices completó el reinicio autorizado: nuevos PID 6669/6667 a las 09:28:52. WindowServer conservó PID 403 y la sesión abierta.
- La carga combinada de color siguió aproximadamente entre 49 y 73 % en las muestras posteriores, con las apps cerradas. No se considera resuelta la saturación. repair-observations.json y restart-observations.json conservan las mediciones.
- Dos repeticiones completas se detuvieron por el límite externo al entrar en Live (86,59 y 83,54 s), sin perfiles nuevos: build/features-after-repair-0.3.16.log y features-after-service-restart-0.3.16.log. No se presentan como suites aprobadas.
- La integración de protección aislada sí pasó 14 comprobaciones ARM/Intel bajo Rosetta, cero fallos: build/sender-safety-both-0.3.16.log. Usa SenderEngine/TLS/códec reales y sustituye solo la pantalla virtual/captura. Verifica retirada independiente de una cola de entrada bloqueada, interfaz sensible, mensaje/desconexión, callback de parada ausente y salida limitada. No crea pantallas reales ni publica entrada de sistema; no prueba rendimiento físico.
- La inspección solo lectura del registro de dispositivos encontró 309 entradas, 297 correspondientes exactamente a los ICC apartados. Registro original respaldado en device-registry-original.plist; plan selectivo conserva los otros 12 dispositivos. ColorSyncDeviceCopyDeviceInfo confirma nombre y UUID antiguo fuera de las pantallas activas. La API omite la URL cuando el ICC ya está apartado; la identidad ICC se valida contra el respaldo. UUID fuera de la lista rechazado.
- Se preparó la retirada mediante ColorSyncUnregisterDevice, con límite por llamada y parada ante errores. No se modifica directamente la caché. La autorización separada está solicitada y pendiente: REGISTRO.md. Ninguna entrada del registro se ha retirado todavía.
- Verificación final de este tramo: ambas apps instaladas siguen en 0.3.14 y sus firmas estrictas son válidas. La candidata 0.3.16 sigue interna, sin instalar ni publicar, hasta completar la estabilidad real.

### Retirada del registro autorizada y completada

ColorSyncUnregisterDevice completó 297 bajas sin fallos tras la autorización explícita. registry-repair-verified.json confirma ausencia de los 297 UUID y conservación exacta de las otras 12 entradas; también verifica respaldos y cuarentena de los ICC. Cuatro muestras de ambos servicios de color fueron 0 % CPU, sin reiniciar WindowServer ni cambiar TCC.

La primera suite posterior tuvo un fallo del receptor de pruebas: mantenía la secuencia de vídeo de la sesión anterior al iniciar una autenticación nueva. Se corrigió solo la prueba, reiniciando el decodificador y la secuencia al cambiar de sesión. La repetición completa features-registry-repaired-final-0.3.16.log pasó 366 comprobaciones, cero fallos, 124,58 s y cero perfiles nuevos. Incluye retirada de pantalla real con entrada bloqueada y sin callback de parada, además de las pruebas aisladas ARM/Rosetta.

Firma continua e instaladores finales nuevamente verificados, sin cambios de Source desde la compilación protegida. La captura real prolongada y los ocho ajustes con el motor real se van a repetir; los resultados anteriores fallidos se conservan. Las apps instaladas siguen en 0.3.14 hasta completar esta validación.

### Captura real final e instalación 0.3.16

La baja cadencia de los primeros ensayos posteriores a la reparación correspondía a un escritorio estático: la app de diagnóstico no procesaba los eventos de AppKit ni ubicaba correctamente su ventana cuando la lista de NSScreen estaba desactualizada. El fotograma recibido confirmó el escritorio sin la escena. Se corrigió solo la herramienta: finishLaunching, procesamiento de eventos/ventanas, ubicación alternativa con geometría CoreGraphics, actualización explícita y restauración de la posición tras finalizar. Dos fotogramas recibidos confirman la escena y distinta posición del marcador; el validador ahora exige continuidad de imagen y duración, además de salida correcta. Los ensayos anteriores se mantienen como evidencia parcial.

- Captura real corta con movimiento confirmado: 911 imágenes recibidas/presentadas, 36,49 FPS, 24,86 s de imagen, p95 de separación 103,93 ms, máxima 161,98 ms. received-motion-10/60-0.3.16.png inspeccionadas; actual-motion-confirmed-0.3.16.log.
- Captura real prolongada M4→Catalina por red compartida, detalle y techo 40 Mb/s: 2.327 imágenes, 25,92 FPS, imagen durante 89,75 s, cero perfiles nuevos y ningún disparo de protección. p95 de separación de imágenes 115,82 ms, máxima 790,35 ms. Cursor separado: mediana de separación 7,84 ms, p95 94,68 ms y máxima 539,31 ms. long-moving-image-final-0.3.16.log y long-confirmed-motion/. Son medidas de llegada/encolado; no ópticas.
- Ocho configuraciones con movimiento en la misma conexión: 1.514 imágenes, 23,73 FPS, duración de imagen 63,71 s, formatos 720p/1080p/1440p, duplicar/extender, calidades 6/12/20/40, 30/60 FPS, cursor incrustado/separado. Continuidad validada, cero perfiles nuevos. settings-moving-image-final-0.3.16.log. Sus pausas incluyen cambios de captura/pantalla, por lo que no miden lag físico de cursor.
- Repetición Catalina física: 12 ejecutables, 209 PASS, cero fallos. native-registry-repaired-final-0.3.16.log.
- Ambas apps 0.3.16 instaladas por sus paquetes. MacBook SHA256 4949886cf5f6afa61842978be0060c7a82249c7e907569f44339b1144d34d5b0; iMac 122b5297c96f66de8b36ae6ea630fcf3f74c5d2ffc297788fb9e750a70b7de99. Firmas estrictas válidas y mismo requisito de certificado que antes. Copias previas conservadas.
- Las dos apps se han abierto mediante su ruta canónica. El control visual responde que el MacBook está bloqueado y necesita desbloqueo manual del usuario; no se ha intentado eludirlo. Quedan comprobación visual/estado final de conexión y valoración del ratón físico. Los paquetes y la información de pruebas están en Documents/Codex/PRISON DISPLAY/PRISON-DISPLAY-v0.3.16, con ESTADO.txt que expone esa limitación.

## 0.3.17 — 8 de octubre de 2026


- Core: 313 comprobaciones PASS, cero fallos.
- Funciones ARM y Intel/Rosetta: 400 PASS, cero fallos. Incluye captura y pantalla reales, posición, corte/reconexión, cambios de calidad, retirada con entrada bloqueada y parada acotada. Duración 135,93 s; cero perfiles nuevos.
- Canal de control y bloqueo de decodificación: 20 PASS, cero fallos.
- Catalina físico: 12 ejecutables, 224 PASS, cero fallos; el decodificador también termina correctamente.
- Nitidez de texto generado: cuatro variantes, 90/90 imágenes cada una y cero omisiones. Inspección de texto/lineas y de una imagen decodificada en el iMac. La métrica numérica muestrea un canal de color: no es una validación perceptual exhaustiva.
- Ocho ajustes en una misma conexión: 720p/1080p/1440p, 30/60 FPS, 6/12/20/40 Mb/s, duplicar/extender y cursor separado/incrustado. 2.062 imágenes, 63,84 s de movimiento, continuidad aprobada, cero perfiles nuevos. La pausa máxima de 1,07 s incluye cambios deliberados de pantalla/captura.
- Extensión sostenida 1080p/60/máximo40: 3.944 imágenes recibidas y presentadas, 43,87 FPS, 89,80 s de movimiento. Imagen: mediana de confirmación 21,75 ms; separación p95 96,99 ms y máxima 291,05 ms. Cursor: separación mediana 8,48 ms, p95 17,79 ms y máxima 167,87 ms. Sin caída durante el intervalo; el cierre intencional al terminar provoca los mensajes de desconexión finales. Cero perfiles nuevos.
- Firma: cuatro comprobaciones de continuidad y casos negativos correctas. Mismo certificado/identificadores, ninguna renovación de TCC.
- Instaladores expandidos: versión, binarios, logo, icono y firma coinciden; claves privadas y acceso SSH excluidos.

FPS cuenta imágenes recibidas/decodificadas. «Presentadas» cuenta llamadas del visor completadas, no una cámara frente a la pantalla. RTT incluye la confirmación del protocolo. No se deben confundir estos datos con latencia óptica.


Registros y decisiones: outputs/PRISON-DISPLAY-v0.3.17/INVESTIGACION.md. La referencia congelada conserva el comportamiento de 0.3.16 con versión de protocolo 0.3.17, para no alterar el emparejamiento de la comparación. Los ensayos de ACK, tres imágenes y NV12 quedan descartados. Pendiente en este punto: instalación canónica y aceptación física del ratón.

### Instalación 0.3.17 y lectura del Llavero

Ambos paquetes se instalaron correctamente en Aplicaciones. Versión, binario, firma estricta por arquitectura, certificado continuo y recibo comprobados. MacBook: 5bfc4f5d482b216cdb22036b1a8f16bf22f24be65333d8f3260d94789be9d418; iMac: e10abb6a35f4d73c04b5fdb8c9989433162056b81b1ea8b7a1d7e10023c5b65a. Al abrir el MacBook mostró Disponible, 1080p/60/Máxima40/Rápido conservados, pero lectura del Llavero -25293 y Recordar desactivado. No se declara conexión canónica final comprobada. Se prepara0.3.18 para ofrecer recuperación explícita, sin borrar el elemento ni cambiar su ACL.

## 0.3.18 — recuperación explícita del Llavero


- Core:313 PASS, cero fallos.
- Funciones:400 PASS, cero fallos y cero perfiles nuevos; 130,35 s. Los motores de vídeo/entrada permanecen iguales al finalizar el refuerzo de cancelación del botón.
- Interfaz final:384 PASS, cero fallos. Lectura cancelada/inexistente/recuperada, ventana disponible mientras se autoriza, resultado tardío ignorado y no encolar otra lectura mientras el diálogo sigue pendiente. Geometría de ambas apps a600/660/900 puntos; imágenes inspeccionadas. Se inyecta una lectura sintética: no se accede al Llavero de producción.
- Llavero ARM/Intel bajo Rosetta:18 PASS, cero fallos, únicamente cuentas sintéticas únicas con retirada al terminar. Lectura pasiva y explícita restauran la política de interacción del proceso.
- Catalina físico:12 ejecutables,224 PASS y cero fallos.

La primera compilación manual del ejecutable independiente de Trust omitió dos dependencias y falló; se corrigió el comando y se añadió Tests/Trust/run.sh reproducible. Las apps y la interfaz habían compilado correctamente. Se conserva el historial de pruebas de0.3.17.

Pendiente en este punto: prueba prolongada final, instalación de ambos paquetes y recuperación real del Llavero canónico. La prueba sintética no sustituye la autorización de macOS para la credencial guardada.

## 0.3.19 · investigación en curso · 9 de octubre de 2026

No instalada ni preparada para entrega final. Ambas apps instaladas continúan en 0.3.18. Desarrollo de estado visible, confirmación por el visor, recuperación del Llavero fuera de la interfaz, preferencias de entrada, callbacks retirados y recuperación de pantalla temporalmente indisponible. Protocolo 8; misma versión exacta en ambos equipos. Firma persistente/identificadores preservados, verificación positiva y negativa pasada.

Comprobaciones posteriores a la nueva confirmación del visor: Core 313, componentes receptor ARM/Intel 328, entrada independiente 20, protección de emisor simulada 14, presentación simulada 36 y recuperación/rechazo de confirmaciones simulada 28: cero fallos. En Catalina físico, 13 ejecutables de componentes y 251 comprobaciones: cero fallos. La modificación final de botones y orden de fases se compila pero todavía requiere terminar su regresión de interfaz y repetir las pruebas finales relevantes. Las ejecuciones de componentes usan posiciones/imagen simuladas y no inyectan entrada al escritorio.

Captura real anterior al bloqueo: Wi-Fi compartido 5 GHz, capacidad LAN 217–245 Mb/s. Las muestras de cursor a 16 ms/TCP sin ACK stretching fueron prometedoras, pero la confirmación repetida se detuvo con cero imágenes al bloquearse el MacBook. No se incorporan a producción mientras falte confirmación. Captura actual, ajustes reales, modo duplicado/extendido, transmisión sostenida, lectura real del Llavero, continuidad de permisos en instalación y valoración física siguen pendientes de desbloqueo manual. La distribución de ventanas se prueba fuera de pantalla; no sustituye esa comprobación física. Evidencia y fallos retenidos en build/review-0.3.19/PROGRESO.md.

Cierre de comprobaciones fuera de pantalla: botones/orden de fases e interfaz actual, 429 PASS/0 FAIL; distribución inspeccionada en ambos roles. Recuperación sintética actual, 28 PASS/0 FAIL; firma actual cuatro comprobaciones pasadas. Compilación universal final fuera de pantalla completada. El caso de disponibilidad del canal rápido frente al transporte de entrada elegido requiere precisión adicional y prueba. No instaladores finales ni instalación de 0.3.19; continúa pendiente el desbloqueo manual para el resto de la validación real.


### Reanudacion con escritorio desbloqueado

CUA confirma acceso a la ventana instalada0.3.18; el bloqueo ya no impide comprobar imagen real. Ocho ensayos repetidos de captura19 finalizaron con imagen aceptada en el visor y sin nuevos ICC. No hay mejora consistente para cursor16/ACK rapido; no se incorporan. Otros ocho ensayos LAN-only/20/40 finalizaron correctamente, pero los primeros se solaparon con compilacion; no se presentan como prueba causal de mejora. Se prepara confirmacion sin carga de compilacion. La regresion actual de Core313, funciones458 e Interactive30 termina sin fallos; resto en ejecucion. No se han cambiado permisos TCC.


## 0.4.0 — comprobación del 12 de octubre de 2026

Candidata universal con dos funciones por app. Core final: 325 comprobaciones; componentes/integración: 492; interacción: 30; recuperación temporal: 28. Sin fallos en sus últimos registros. High Sierra y Catalina: 203 comprobaciones de core/pipeline, seguidas por la regresión de primera imagen antes de completar inicio en High Sierra, 9 comprobaciones sin fallos. Compresor Intel/compatible: 11 comprobaciones sin fallos en High Sierra. Interfaz: 744 comprobaciones en el M4/Rosetta y 777 en High Sierra; imágenes propias de interfaz inspeccionadas. Firmas persistentes y controles negativos correctos; ambos paquetes expandidos y verificados.

M4 → High Sierra, escritorio extendido real 1280×720/60: 1.217 imágenes recibidas y aceptadas en 24,51 s de movimiento; promedio 49,39 FPS, RTT mediana 19,23 ms. Entrada simulada: mediana 9,12 ms / p95 13,11 ms. Sin eventos publicados al escritorio. High Sierra → M4, 720p30 con compresor compatible separado: 458 imágenes/35 s, 13,25 FPS, RTT mediana 105,14 ms; entrada simulada 9,15 / 12,94 ms. El hardware en la comparación equivalente: 8,13 FPS/256,44 ms. El RTT excluye tiempo previo de captura y no mide latencia óptica.

Cinco ajustes de duplicación en High Sierra terminaron sin fallo: 720p30 → 1080p60 → 20/40 Mb/s → 720p30; el receptor informó ambas resoluciones y recibió imagen al regresar. Una ventana auxiliar de pruebas provocó un cierre de AppKit antiguo; corregida su propiedad de cierre y repetida la prueba con escena externa. No se incorporaron captura NV12/superficies compartidas, tres imágenes ni ACK sin compensación.

Estado a petición del usuario de probar ya: PRISON DISPLAY MacBook v0.4.0 instalada, firma verificada y proceso abierto en /Applications del MacBook de 2014. En el M4 está abierta la v0.4.0 comprobada desde build, disponible para conectar y con permiso de control concedido. La sustitución de la copia root-owned de /Applications fue denegada por el sistema; esa copia sigue en 0.3.20 y no se cambió su dueño. El iMac todavía conserva 0.3.20. Pendientes: prueba física guiada, instalación canónica del M4 y actualización/ensayos finales del iMac. No se declara completada la validación de todos los equipos.

## 0.4.1 — 2026-10-12

PRISON DISPLAY · v0.4.1 · Pruebas del 12/10/2026

COMPROBADO EN EQUIPOS REALES
MacBook Air M4 envía dos extensiones distintas al mismo tiempo:
- MacBook Pro de 2014, High Sierra 10.13.6: 1004 imágenes recibidas, 1003 aceptadas por el visor; media de 29,9 FPS durante una prueba que incluye cambio de resolución y recuperación de captura.
- iMac de 2013, Catalina reportado 10.15.8: 800 imágenes recibidas y aceptadas por el visor; media de 34,6 FPS antes de detener expresamente esa conexión.
- Ambos receptores utilizaron el canal TLS separado para el cursor. Mediana entre posiciones: 7,8 ms; percentil 95: aproximadamente 9,5-9,6 ms. Es cadencia del canal, no retraso óptico del ratón físico.
- Se cambió Pantalla 1 de 1080p60 a 720p30 mientras Pantalla 2 seguía conectada.
- Se detuvo Pantalla 2 y Pantalla 1 continuó. macOS solicitó recuperar su captura al retirar el otro monitor y la app volvió a mostrar imagen.
- La prueba incluyó pausas de hasta 1,43 s de imagen y 1,26 s del cursor durante reconfiguraciones. No equivale a una prueba de uso sin cambios ni a latencia normal continua.

COMPROBACIONES ADICIONALES
- 28 pruebas de pantallas virtuales: dos identificadores distintos a la misma resolución, protección de copias duplicadas, cambio de tamaño independiente, retiro, identidad estable y colocación guardada. Cero fallos finales.
- 760 comprobaciones de interfaz en el M4/Rosetta; 793 en High Sierra y 802 en Catalina. Cero fallos.
- 374 comprobaciones de componentes de entrada, reconexión, preferencias y cursor en ambas arquitecturas. Cero fallos.
- 14 comprobaciones de errores y cierre del emisor. Cero fallos; sin inyectar entrada real al sistema.
- Prueba del visor y la flecha ejecutada en High Sierra: cero fallos. Flecha rasterizada por la app, independiente de la imagen de NSCursor y por encima de la capa de vídeo.
- Regresión de protocolo, cifrado, códec y entrada: cero fallos.
- Ambos instaladores: binarios universales, versiones, assets, firma persistente y exclusión de claves privadas verificados.

INSTALACIÓN Y LÍMITES
M4 y MacBook Pro: 0.4.1 instalada en /Applications y abierta.
iMac: instalador 0.4.1 en el Escritorio; su instalación exige autenticación local de administrador. La prueba simultánea allí utilizó el receptor temporal 0.4.1 firmado.
Pendiente: confirmar visualmente la flecha con el ratón físico y aceptar la conexión normal del iMac a Pantalla 2 tras instalar.
No se ha medido latencia óptica ni se promete una tasa de 60 FPS en cualquier Wi-Fi. Las pruebas de movimiento generadas no equivalen a FL Studio real ni al ratón físico.
High Sierra envía duplicación y recibe extensión; no dispone de las clases de pantalla virtual para originar una extensión.

PRISON DISPLAY 0.4.2 — Corrección Catalina

Causa comprobada en el informe de cierre del iMac: símbolo CGPreflightScreenCaptureAccess inexistente. Apple DTS documenta este fallo de disponibilidad: https://developer.apple.com/forums/thread/683860?answerId=684400022

Verificado:
- Ambos ejecutables universales compilados y firmados con la identidad existente.
- Ejecutable Intel sin enlace directo al símbolo ausente.
- Componentes de recepción, preferencias, cursor, recuperación y control probados en ambas arquitecturas; prueba nueva de Catalina y fallo cerrado de permisos en sistemas modernos aprobada.
- Ambos instaladores verificados: versión, firma, dependencias y contenido.
- Ejecutable real 0.4.2 probado en el iMac Catalina: diagnóstico y arranque normal sin nuevos cierres; instalado en ~/Applications y abierto en modo Recibir.

Pendiente:
- Actualización de la copia protegida en /Applications: instalador abierto en el iMac; requiere autenticación local de administrador.
- Nueva conexión de producción iMac–M4 tras esa instalación. No se afirma todavía que esta conexión esté comprobada.
- M4 y MacBook Pro conservan 0.4.1 y su conexión existente; esta corrección no modifica el protocolo.

PRISON DISPLAY 0.4.2 — Verificación final

Los tres Mac tienen 0.4.2 instalada. Firma y arranque del iMac Catalina verificados; no se han generado nuevos informes de cierre después de la corrección.

La ventana de producción del M4 confirma simultáneamente:
Pantalla 1: Imagen en directo (MacBook Pro 2014).
Pantalla 2: Imagen en directo (iMac Catalina).
El código de emparejamiento del iMac fue confirmado coincidente por el usuario. La segunda sesión informa de imagen decodificada por el receptor. Se activó Recordar en el M4 y la app confirma Conexión guardada.

Corrección: consulta dinámica de CGPreflightScreenCaptureAccess en macOS 11 y posterior; Catalina usa la autorización del capturador antiguo. Apple DTS documenta la declaración errónea del SDK: https://developer.apple.com/forums/thread/683860?answerId=684400022

Verificación adicional: compilación universal, firma persistente, ausencia de importación directa de la función no disponible, componentes y pruebas de permisos en ambas arquitecturas, contenido y firmas de ambos instaladores.

Límite: no se ha medido latencia óptica ni confirmado físicamente fluidez y colocación de ventanas durante esta corrección. No se afirma latencia perfecta. La app exige versiones idénticas en el emparejamiento: no deben mezclarse 0.4.1 y 0.4.2.

PRISON DISPLAY 0.4.3 — corrección de colocación preparada

Detectado en producción 0.4.2: posiciones guardadas distintas de las activas; después de cambiar resolución, el Pro podía quedar adyacente al Air y el iMac al extremo izquierdo. Después de reiniciar, el orden dependía de qué receptor reconectaba primero.

Corrección 0.4.3: una transacción conjunta para ambos orígenes guardados y conservación de la cadena de monitores cuando cambia la resolución del monitor central.

Pruebas: 30 comprobaciones de monitores virtuales reales, cero fallos, incluida la regresión del monitor central. Compilación universal y firmas existentes verificadas. Ambos instaladores verificados. No desplegada todavía: las copias principales de Air e iMac son propiedad de administrador y no existe autorización sudo vigente. Los tres Mac permanecen en 0.4.2; no se mezclan versiones.

Estado final 0.4.2: conexiones de ambos receptores recuperadas, coordenadas verificadas Pro x=-3840, iMac x=-1920, Air x=0, y=0 en las tres. Monitores remotos 1920x1080, Air lógico 1710x1107. Posiciones guardadas con ese orden. Movimiento de prueba transmitido a ambos; métricas de producción observadas Pro 39 FPS/32.5 ms ida-vuelta/9.2 ms decodificación e iMac 50 FPS/21.7 ms ida-vuelta/2.4 ms decodificación. Son muestras puntuales de transmisión, no medidas ópticas del ratón.

Límite: sin comprobación física del cursor por el usuario. La 0.4.2 puede volver a alterar la disposición en una reconexión; la solución de código preparada sigue pendiente de instalación y validación final de producción.

PRISON DISPLAY 0.4.3 — verificación de colocación y cursor

Correcciones: restauración conjunta de las dos posiciones, conservación de adyacencia al cambiar resolución del monitor central, procesamiento de avisos gráficos en los auxiliares, protección de la posición elegida frente a recolocaciones temporales por desconexión, recuperación de coordenadas del cursor en segundo plano.

Resultados finales:
- 331 comprobaciones de núcleo/protocolo/cursor en ARM e Intel: sin fallos.
- 376 comprobaciones de componentes/preferencias/recuperación: sin fallos.
- 31 comprobaciones de monitores virtuales reales: sin fallos. Incluyen persistencia de una colocación externa con ambos auxiliares activos, cambio del monitor central, retirada independiente, nueva colocación manual y recreación.
- 14 comprobaciones de fallos y retirada del emisor: sin fallos.
- Ejecutables universales e instaladores: firmas y contenido verificados con la identidad existente.

Prueba real 0.4.3, M4 a High Sierra y Catalina simultáneamente:
Pro: 905 imágenes mostradas de 905 recibidas; media 28.16 FPS incluyendo cambio de 1080p60 a 720p30; intervalo de cursor mediano 7.79 ms, p95 9.63 ms.
iMac: 765 imágenes mostradas de 765 recibidas; media 31.50 FPS; intervalo de cursor mediano 7.80 ms, p95 9.82 ms.
Al cerrar la segunda conexión, la primera siguió recibiendo imágenes. Prueba sin fallos.
Pausa máxima durante reconfiguración: imagen Pro 1002 ms y cursor 837 ms; iMac imagen 364 ms y cursor 104 ms. Estas métricas no son mediciones ópticas del ratón ni promesas de 60 FPS sostenidos.

Referencia de Apple: https://developer.apple.com/documentation/coregraphics/cgdisplayreconfigurationcallback
Los avisos externos se entregan a aplicaciones que procesan los eventos gráficos; la consulta previa al cambio todavía no representa el estado final.

Estado de instalación: 0.4.3 probada con ejecutables de diagnóstico firmados; las aplicaciones principales siguen en 0.4.2. macOS deniega sustituir las copias protegidas de Air e iMac sin autenticación de administrador. No se han cambiado permisos de sistema, certificado ni autorización de captura. La instalación y comprobación final de las apps principales 0.4.3 siguen pendientes. No se mezclan versiones de producción.


Instalación autorizada 0.4.3: installer completado en Air M4, Pro 2014 e iMac; versiones canónicas y firmas estrictas verificadas; apps reiniciadas. Air conserva ajustes y permiso de control. Reconexión pendiente de autorización del Llavero; CUA rechaza SecurityAgent. No se afirma conexión de producción ni geometría final verificadas tras instalación.


## Brillo conjunto 0.4.4
Instalada mediante installer en los tres equipos, versiones y firmas estrictas canónicas verificadas. 23 comprobaciones de mensajes, 331 de núcleo, 376 de componentes, 832 de interfaz final sobre Intel en Air y 889 de interfaz sobre High Sierra real, sin fallos. Control físico probado en Air, Pro e iMac con 50 %, 60 % y restauración de niveles previos, correcto. Compilación universal final y paquetes verificados. Evidencia: build/brightness-*.log y Tests/Brightness/. La confirmación de brillo simultáneo en producción espera el diálogo del Llavero tras la actualización; el control CUA bloquea SecurityAgent. Se ha pedido al usuario la confirmación local. No se afirman las tres respuestas en sesión de producción.


## 0.4.5 interfaz sencilla instalada
1.447 comprobaciones locales, 1.600 en High Sierra real y 1.615 en Catalina real, sin fallos. Instaladores y firmas estrictas finales verificados; installer completado en los tres y apps canónicas abiertas en 0.4.5. En Air se comprobó el modo sencillo, experto y despliegue/cierre de enlace, conservando ajustes. Brillo conjunto real 0.4.4 validado con tres respuestas antes de actualizar. La reconexión 0.4.5 espera confirmación protegida del Llavero; no se declara conexión final comprobada. Usuario está ausente y autorizó autenticación para instalar; CUA bloquea SecurityAgent, por lo que no se manipula su protección por otros medios.


## 0.4.5 verificación final tras autorización del usuario
Ambas sesiones instaladas indican Imagen en directo. Brillo confirmado por los tres Mac al 5 %. Se conserva el modo experto elegido por el usuario. CoreGraphics confirma Pro producto 1 x=-3840, iMac producto 2 x=-1920, Air principal x=0; y=0 en los tres. Remotos 1920x1080, Air lógico 1710x1107. No fue necesario recolocar ni reiniciar. No se ha medido latencia óptica del cursor.


## 0.4.6 revisión previa solicitada por el usuario
No se han sustituido las aplicaciones principales: los tres equipos permanecen en 0.4.5 y mantienen las sesiones. Preparadas correcciones de detección, lista por equipo, cancelación y cierre de visor. Interfaz: 1564 comprobaciones locales, 1741 en High Sierra real, 1732 en Catalina real, cero fallos. Núcleo/protocolo y pruebas específicas de Reconnect, Desktop, CursorLease y Recovery sin fallos. Firma y contenido de paquetes universales verificados. Disposición activa y guardada Pro(-3840), iMac(-1920), Air(0), y=0. Revisión detallada y límites en outputs/PRISON-DISPLAY-v0.4.6/AUDITORIA.md. La conexión principal Wi-Fi y la autorización posterior a actualización todavía no están validadas en 0.4.6; no se declara entrega instalada.


## 0.4.7 revisión profunda
Compilación universal y dos instaladores verificados. Interfaz: 1.579 pruebas locales, 1.755 en High Sierra 10.13.6 real y 1.746 en Catalina 10.15.8 real, sin fallos. Suites de núcleo, cursor, posiciones, reconexión, escritorio remoto y recuperación: sin fallos. Pruebas TLS de 10 MiB: diez intercambios con cada Mac Intel, mediana 76,6 ms con el Pro y 67,0 ms con el iMac, sin errores. Estas mediciones no representan latencia óptica ni vídeo continuo. Los tres Mac tienen 0.4.7 instalada y abierta; firmas y versión verificadas. El Pro y el iMac descubren ambos servicios del Air por Bonjour. La prueba de imagen y reconexión en producción sigue pendiente de completar la recuperación de la conexión del Llavero en el Air. Informe de alcance en outputs/PRISON-DISPLAY-v0.4.7/PRUEBAS.txt.


## 0.4.7 despliegue y comprobación remota
Instaladores completados en Air M4 26.6.2, Pro 2014 High Sierra 10.13.6 e iMac Catalina 10.15.8. Los dos Mac remotos muestran versión 0.4.7, firma estricta válida y permiso de captura disponible; las apps arrancan en modo Recibir. Los dos descubren por Bonjour Pantalla 1 y Pantalla 2 del Air. En la ventana del Air se observan 0.4.7 y la conservación de modo extendido, 1080p, 60 FPS, 40 Mb/s, experto, cursor rápido y permiso de control. La conexión guardada queda esperando autorización del Llavero, por lo que no se declara imagen en directo ni reconexión probadas. El indicador de brillo conjunto pasó de 95% en la ventana previa a 6% al iniciar 0.4.7; no se ordenó ningún cambio de brillo. Informe: outputs/PRISON-DISPLAY-v0.4.7/PRUEBAS.txt.

## 0.4.7 verificación posterior del Llavero
El usuario confirmó la autorización del Llavero en el Air. La conexión guardada se recuperó y el emisor volvió a anunciar sus dos pantallas; Pro e iMac las descubren por Bonjour. La ventana del Air permanece en «Disponible para conectar» y no se observan conexiones TCP de PRISON DISPLAY desde los receptores a los puertos anunciados del Air. Las apps remotas están abiertas en 0.4.7, pero no se pudo obtener su estado visual por SSH. Por tanto, instalación, permisos y descubrimiento están verificados; imagen continua, ratón y reconexión entre equipos siguen pendientes de una conexión real. Informe actualizado en outputs/PRISON-DISPLAY-v0.4.7/PRUEBAS.txt.


PRISON DISPLAY 0.4.11 — acceso directo al visor y relleno en pantalla completa

Cambios preparados en la barra lateral de todas las apps: «PRISON DISPLAY · v0.4.11» ejecuta la acción de pantalla completa. En el receptor abre el visor del escritorio recibido; en el emisor amplía la ventana principal. El vídeo mantiene ajuste completo en ventana y usa relleno proporcional en pantalla completa, con recorte lateral cuando las proporciones difieren. El ejecutable de pruebas de Workspace compila con estos casos; no se ejecutó porque esta misma vista de prueba ya provocó el cierre de AppKit registrado en esta conversación. `zsh test.sh` pasa los tests anteriores de protocolo/flujo hasta fallar al preparar el compresor de pantalla (`-12902`), ajeno a estos cambios. Los instaladores no se generaron: la firma persistente detuvo el build porque el llavero local no contiene la identidad privada; el certificado P12 de respaldo sí coincide, pero macOS rechazó incluso crear un llavero temporal.

## 0.4.16 diagnóstico del error VideoToolbox
La sonda nativa de VideoToolbox confirmó que el emisor hardware del M4 crea sesiones y codifica 60 fotogramas 720p; la limitación del aislamiento impedía esa prueba en sandbox. El error `-12902` sí se reproduce al combinar la selección software con RTVC; se corrigió la selección y se añadió una regresión que crea el modo software compatible, codifica y decodifica una imagen. La suite de núcleo registra `RESULT: 0 failures`; 60 fotogramas 720p codificados/decodificados correctamente y los perfiles 1080p60 y 1440p30 probados. La prueba es local y no sustituye una medición de Wi‑Fi ni validación en High Sierra/Catalina.

La suite de receptor terminó sin fallos cuando se ejecutó con acceso nativo; la lectura del proceso ColorSync queda en 0,0 % y no se modifica. Cuatro comprobaciones de nombres guardados pasan. El helper de interfaz WorkspacePreview sigue sin inicializar AppKit en esta sesión, por lo que esa prueba de ventana completa no se declara pasada. Paquetes 0.4.16 firmados y verificados; todavía no reinstalados en los Mac del usuario.
