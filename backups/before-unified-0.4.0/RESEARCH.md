# Investigación y decisiones — 1 de octubre de 2026

### 0.3.16: bloqueo y carga de ColorSync — 8 de octubre de 2026

Observación local: 297 perfiles históricos propios y un informe de CPU de colorsync.displayservices. La identidad aleatoria se reemplaza por tres seriales deterministas por resolución. La repetición de creación/retiro reutilizó el UUID y no agregó perfiles; esto corrige la acumulación, pero la prueba prolongada sigue activando el límite de carga con los perfiles históricos presentes. No se afirma una causa exclusiva ni una reparación completa.

[La implementación primaria de Chromium](https://chromium.googlesource.com/chromium/src/+/HEAD/ui/display/mac/test/virtual_display_util_mac.mm) declara primarias, punto blanco, seriales y la cola del descriptor virtual. El código local usa primarias sRGB y cola propia, con una identidad por resolución y exclusión de pantallas simultáneas.

[La investigación publicada por el autor de otra implementación](https://github.com/dripster82/ar_workspace_manager_for_xreal/blob/main/Docs/ColorSync-AirII-investigation.md) documenta acumulación de identidades y bucles de ColorSync, incluso con identidades estables, en su hardware XREAL. Es evidencia de un mecanismo comparable, no prueba de la causa en este MacBook. No se aplica su limpieza global ni reinicio de WindowServer.

Se ha preparado únicamente el traslado reversible de 297 ICC propios antiguos, comprobando el tag mmod (vendor 0xA1DE/model 1/serial antiguo), con respaldo SHA-256. Las tres identidades actuales y todos los perfiles ajenos quedan excluidos. Reiniciar solo los servicios de color requiere la autorización específica del usuario. El programa no cambia permisos ni preferencias de otras pantallas.

La nueva protección de la app consulta metadatos de CPU fuera de la interfaz, con límite de un segundo para su propio proceso de consulta. Ante carga persistente retira su auxiliar por la cola de pantallas, aunque la entrada esté bloqueada, y detiene la extensión. No reinicia servicios del sistema ni vuelve a crear automáticamente la pantalla en esa situación. Ensayos finales de integración pendientes; véase TEST-STATUS.md.

Objetivo: utilizar un iMac Intel de finales de 2013 con Catalina 10.15.8 como receptor del escritorio de un MacBook Air M4 por Wi-Fi.

## Compatibilidad

Apple confirma Catalina 10.15.8 en sus notas de actualización. AirPlay a Mac exige Monterey 12 o posterior en el receptor y determinados modelos; Catalina requiere un receptor propio. El emisor usa ScreenCaptureKit en macOS 13 o posterior, y el receptor usa AppKit, Network, CryptoKit y VideoToolbox disponibles en Catalina. Su ejecutable es x86_64 con versión mínima 10.15. La compilación no verifica por sí sola el funcionamiento sobre Catalina.

Fuentes primarias:
- https://support.apple.com/en-ca/101184
- https://support.apple.com/en-us/108046
- https://developer.apple.com/documentation/screencapturekit
- https://developer.apple.com/videos/play/wwdc2023/10136/

## Vídeo y retraso

H.264 proporciona una vía de codificación y decodificación nativa. Apple documenta que su modo de control de tasa de baja latencia usa hardware, elimina reordenación y produce una salida por entrada. Se activa en el M4, con RealTime y sin reordenación. El receptor convierte con VideoToolbox y muestra fotogramas inmediatamente en AVSampleBufferDisplayLayer.

Una sola imagen puede estar pendiente de confirmación; las capturas nuevas se omiten mientras el receptor está ocupado. No se descartan fotogramas H.264 ya codificados, porque los siguientes pueden depender de ellos. Esto limita el retraso por cola, pero también limita los FPS al tiempo de ida y vuelta más procesamiento. TCP puede añadir retraso en redes con pérdidas. No hay una medida de latencia Wi-Fi todavía; el indicador de ida/vuelta no representa la latencia óptica total de pantalla a pantalla. UDP con recuperación selectiva sería una mejora que necesita mediciones en la red real para justificarse.

Fuente: https://developer.apple.com/videos/play/wwdc2021/10158/

## Escritorio extendido

CGVirtualDisplay crea una pantalla virtual en el emisor; el receptor no necesita instalar un controlador. Esta familia de clases no está documentada como API pública estable. La implementación resuelve las clases en ejecución, captura excepciones y ofrece errores si falta soporte. Se conserva una referencia mientras la captura está activa y se destruye tras detenerla. La prueba local de macOS 26.6.2 confirmó creación de 1920×1080, pantalla principal intacta y retirada efectiva. No implica compatibilidad con futuras versiones de macOS.

Referencia de implementación primaria: código de Chromium, que declara y prueba estas clases:
https://chromium.googlesource.com/chromium/src/+/HEAD/ui/display/mac/test/virtual_display_util_mac.mm

## Transporte y acceso

Bonjour anuncia los MacBook disponibles. Una petición intercambia claves públicas P-256 y ambas apps muestran un código de verificación de seis cifras derivado del secreto compartido. Solo tras aprobarlo en los dos Mac se transfieren las credenciales de transmisión cifradas con AES-GCM. El usuario debe comparar los códigos para autenticar el intercambio frente a un intermediario. Como alternativa manual, se copia un enlace airedisplay que contiene dirección, puerto, versión y clave; no debe compartirse con terceros. Network usa TCP sin Nagle y TLS 1.2 con PSK AES-128-GCM. La clave aleatoria de 128 bits se crea en cada arranque y no se guarda. Ningún fotograma se envía antes de autenticar y comprobar rol y versión. Las apps deben tener la misma versión. Pruebas locales confirmaron transporte de bytes idénticos y rechazo de otra clave. No hay servidor en Internet ni recopilación de telemetría.

Referencias: SDK local Security/SecProtocolOptions.h y documentación de Network:
https://developer.apple.com/documentation/network/nwprotocoltls/options
https://developer.apple.com/documentation/network/building_a_custom_peer-to-peer_protocol

## Versión y distribución

VERSION es la única fuente del número de versión. El proceso de compilación lo incorpora a las ventanas, el menú Acerca de, el visor, la negociación y Info.plist. Los cambios se registran en CHANGELOG.md. Desde 0.3.3 las apps tienen firma local persistente con el mismo certificado y requisitos designados, sin notarización de Apple ni certificado Developer ID.


### 0.3.5: posición y vida de la pantalla virtual
Las pruebas locales reprodujeron que, tras una transacción de CoreGraphics para mover la pantalla virtual, liberar el objeto podía dejar el monitor hasta terminar el proceso. El motor ahora mantiene el monitor durante cortes y usa un proceso auxiliar del mismo ejecutable firmado para retirarlo al detener o recrear. Prueba de retirada/recreación/resolución y posición: build/virtual-0.3.5.log; flujo completo final: build/live-0.3.5.log, cero fallos.
Documentación pública de posición: https://developer.apple.com/documentation/coregraphics/cgconfiguredisplayorigin(_:_:_:_:)
Observaciones del autor de otra implementación sobre vida y modo: https://github.com/go-macos/virtualdisplay/blob/main/README.md
Implementación primaria de Chromium sobre limitaciones y retirada: https://chromium.googlesource.com/chromium/src/+/HEAD/ui/display/mac/test/virtual_display_util_mac.mm
No se asume que estos comportamientos privados sean iguales en todos los macOS; se validó el resultado local.

### 0.3.8: cursor, teclado y conexiones recordadas
NSCursor.currentSystem está obsoleto en el SDK actual y Apple avisa de que devolverá nil en el futuro. El modo Original usa SCStreamConfiguration.showsCursor; el modo Rápido conserva el cursor separado y consulta la última posición cada 8 ms (antes 16 ms). Esta reducción del intervalo no equivale a una medición de latencia física.
https://developer.apple.com/documentation/appkit/nscursor/currentsystem
https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/showscursor
El teclado usa eventos del visor activo y CGEvent en el MacBook, con el permiso de Accesibilidad ya empleado por el ratón. No se instala un monitor global de teclas.
https://developer.apple.com/documentation/coregraphics/cgevent/init(keyboardeventsource:virtualkey:keydown:)
Recordar es voluntario en ambos equipos. SecItem guarda la credencial en el Llavero con cuenta propia por app y sincronización desactivada. Olvidar en el MacBook rota la clave; olvidar solo en el iMac elimina su copia y desconecta.
https://developer.apple.com/documentation/security/secitemadd(_:_:)
https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly

### 0.3.9: disponibilidad y arranque
SCStreamError distingue noCaptureSource/noDisplayList/noWindowList/systemStoppedStream de los errores de permiso y la parada explícita. Se reintenta únicamente el primer grupo, con límites y cancelación.
https://developer.apple.com/documentation/screencapturekit/scstreamerror/code/nocapturesource
La lectura inicial del Llavero usa la política de interacción del proceso de Security, restaura su valor y conserva los registros. Esta API antigua mantiene compatibilidad con Catalina y está obsoleta en el SDK moderno.
https://developer.apple.com/documentation/security/seckeychainsetuserinteractionallowed(_:)
Observación local: una copia temporal dentro de Documentos se bloqueó en VideoToolbox durante la validación del paquete; la misma copia firmada fuera de Documentos transmitió imagen. No se ha identificado con certeza la causa del bloqueo; no se cambiaron permisos de carpetas.
Comparación física de rutas: build/route-comparison.json. Dos muestras por ruta con vídeo sintético de la 0.3.8 favorecen AWDL en mediana de ida/vuelta; se conserva la preferencia actual y no se deduce una mejora óptica del cursor.
Prueba real 0.3.9: transmisión M4→Catalina con confirmaciones de decodificación, interrupción de proceso de 15 segundos y patrón animado posterior. Lectura de UI: 47 FPS, ida/vuelta 152.6 ms, decodificación 2.7 ms.

### 0.3.10: latencia y radio
Experimentos de bloques pequeños y cursor UDP independiente descartados tras comparación física; código experimental fuera de las apps en Tests/Performance/Experiments. CryptoKit AES.GCM y receiveMessage se consultaron en documentación primaria:
https://developer.apple.com/documentation/cryptokit/aes/gcm/seal(_:using:nonce:authenticating:)
https://developer.apple.com/documentation/network/nwconnection/receivemessage(completion:)
La variante de una imagen pendiente mejoró fluidez y p95 de confirmación en dos muestras por variante (build/window-final-comparison.json). Cada confirmación registrada incluye el recorrido de codificación, transporte, decodificación y ACK; no mide el movimiento físico ni el refresco óptico. El indicador de UI ahora usa la media del intervalo.
Lecturas reales de radio: M4 canal48 / 5GHz / -49dBm, iMac canal1 / 2,4GHz / -70dBm. La relación con los parones es una hipótesis plausible; no se cambió la red ni se validó todavía con ambos en 5GHz.
Empaquetado: pkgbuild quedó bloqueado en PKSIPOpenPathSafely/openat al analizar un paquete bajo Documentos. Repetir con una preparación temporal en /private/tmp completó ambos instaladores; no se modificaron permisos de carpetas.


### 0.3.14: latencia, ruta y visor — 8 de octubre de 2026
Separación TLS de cursor/entrada en ambos sentidos, decodificación fuera de la cola de entrada, agrupación de posiciones sin cruzar barreras de control y red compartida priorizada sobre AWDL. Consulta el informe de pruebas y decisiones en outputs/PRISON-DISPLAY-v0.3.14/INVESTIGACION.md. La comparación se hizo con escena repetible y motor/visor del producto en Catalina; no demuestra ausencia de lag físico.
Fuente primaria sobre detener la búsqueda entre pares antes de conectar: https://developer.apple.com/documentation/technotes/tn3213-moving-from-multipeer-connectivity-to-network-framework
Fuente sobre baja latencia y compromiso de detalle/fotogramas: https://developer.apple.com/videos/play/wwdc2021/10158/

### 0.3.15: calidad máxima y consultas de geometría — 8 de octubre de 2026

Prueba acotada de caudal LAN con datos generados, cuatro intervalos de cuatro segundos: 192,92 y 70,17 Mb/s hacia el iMac; 54,31 y 75,08 Mb/s en el sentido contrario. La velocidad de Internet no determina este enlace y la variación entre muestras impide tratar el mejor resultado como capacidad sostenida. Registro build/network-2026-10-08.json.

Ocho muestras de vídeo con escena de texto en desplazamiento y bitrate fijo, manteniendo el resto de la configuración. A 20/40 Mb/s, el iMac indicó decodificación por hardware alrededor de 2,5–3,1 ms. En ambas muestras de 60 Mb/s pasó a decodificación por software, alrededor de 19,6–27,2 ms. Esto justifica el máximo de 40 Mb/s para esta pareja. No se ha analizado el SPS para atribuir el cambio a un nivel H.264 concreto. Los tiempos de las dos últimas muestras coincidieron con otras comprobaciones; no se utilizan para demostrar causalidad de FPS o RTT. Registro build/bitrate-comparison-2026-10-08.json.

AverageBitRate expresa un objetivo de compresión, no tráfico constante: una imagen sencilla puede utilizar mucho menos. MaxAllowedFrameQP limita la degradación de detalle y puede hacer que se omitan imágenes si falta presupuesto. El producto mantiene adaptación y cola acotada; un máximo mayor no garantiza menos retraso. Fuente primaria: [Apple WWDC21, vídeo de baja latencia](https://developer.apple.com/videos/play/wwdc2021/10158/).

Cuatro muestras equilibradas anterior/nueva/nueva/anterior, captura real, escena compleja y visor del producto en Catalina. En 0.3.14, 74/114 posiciones de cursor recibidas, mediana de intervalo 93–110 ms y p95 714–1134 ms. En la candidata 0.3.15, 1302/1313 posiciones, mediana cercana a 8 ms y p95 cercano a 94 ms. La candidata conserva pausas máximas cercanas a 101 ms. Se cambian conjuntamente caché de geometría y adaptación; la comparación no aísla cada efecto. Las medidas son intervalos de mensajes recibidos, no retraso físico desde la mano ni refresco óptico. El vídeo produjo sólo 1,3–4,7 FPS en estas muestras, con esperas de inicio: no se extrapola al uso normal ni se afirma que esté resuelto. Registro build/real-comparison-0.3.15.json.

Las consultas CGDisplayBounds se almacenan bajo bloqueo y se invalidan con CGDisplayRegisterReconfigurationCallback al cambiar la configuración. Una consulta en curso no vuelve a guardar límites obsoletos si recibe una invalidación. Pruebas: mil consultas conservan una lectura, el desplazamiento invalida el origen y las pantallas vacías no quedan almacenadas. Fuente de notificaciones: [Apple CoreGraphics](https://developer.apple.com/documentation/coregraphics/cgdisplayregisterreconfigurationcallback(_:_:)).

La adaptación empieza a 12 Mb/s en los perfiles altos y exige ventanas suficientemente pobladas, mediana y percentil 75 saludables para crecer. Tras congestión espera veinte segundos antes de aumentar otra vez, evitando alternancias rápidas. Cambiar sólo el techo conserva el valor asentado (limitado si baja), la captura y la pantalla virtual. Queda pendiente la prueba completa de esta transición y del control mantenido: el sistema gráfico del MacBook dejó de responder también al abrir la app instalada. No se sustituye ese fallo por una simulación aprobada ni se instala la candidata.

### Registro histórico tras la limpieza (8 de octubre)

La inspección local solo lectura encontró 297 referencias antiguas propias dentro de 309 dispositivos, incluso tras apartar los ICC y reiniciar los dos servicios. El respaldo preserva el registro original. La operación adicional preparada utiliza [ColorSyncUnregisterDevice, documentada por Apple](https://developer.apple.com/documentation/colorsync/colorsyncunregisterdevice(_:_:)), que permite dar de baja un dispositivo por clase y UUID. No se propone borrar toda la caché. La prueba de lectura valida nombre e identidad fuera de las pantallas activas; la API omite las URL de ICC que ya no están en su ruta original, por lo que se verifica la asociación contra el respaldo y hash del ICC. La retirada aún necesita autorización específica; no hay evidencia de que por sí sola vaya a resolver el último bloqueo.

### 0.3.17: presupuesto de vídeo, cuantificación y entrada — 8 de octubre de 2026

Investigación y medidas reproducibles: outputs/PRISON-DISPLAY-v0.3.17/INVESTIGACION.md. La escena compleja anterior omitía unas 80 % de las capturas bajo el presupuesto inicial de 12 Mb/s/QP32. La comparación controlada justifica usar el presupuesto seleccionado de 20/40 y QP36 a 60 FPS, conservando32 a30. Se descartan ACK, tres imágenes y NV12 tras medición física. La entrega de entrada agrupa movimientos obsoletos manteniendo barreras y cancelación. No se demuestra reducción consistente de mediana de entrada ni lag físico cero.

Fuentes: [Apple RTVC/MaxAllowedFrameQP](https://developer.apple.com/videos/play/wwdc2021/10158/), [colas y latencia de red](https://developer.apple.com/videos/play/wwdc2022/10078/), [ScreenCaptureKit y formatos](https://developer.apple.com/videos/play/wwdc2022/10155/), [ProcessInfo](https://developer.apple.com/documentation/foundation/processinfo/activityoptions/latencycritical). La recomendación YUV420 es un punto de partida: el ensayo local no encontró una ganancia repetible y no se incorpora. La actividad permite reposo y se libera con la sesión; no se acredita como causa de los FPS medidos.


## 9 de octubre de 2026 · Cursor local al cruzar (0.3.20)

Apple exige foreground para separar el ratón físico de la posición local mediante
[CGAssociateMouseAndMouseCursorPosition](https://developer.apple.com/documentation/coregraphics/cgassociatemouseandmousecursorposition(_:)).
Los eventos conservan desplazamientos relativos mientras la posición absoluta local permanece fija.
El código anterior activaba la app de forma asíncrona y llamaba inmediatamente a CGDisplayHideCursor,
sin comprobar resultado ni separar movimiento físico/local. Es una causa compatible con el cursor residual reportado;
la desaparición visual final se debe confirmar con el usuario.

[NSCursor.hide](https://developer.apple.com/documentation/appkit/nscursor/hide()) mantiene ocultos también los cursores que se establezcan después,
y cada hide debe tener un unhide. Se usa una propiedad de ownership idempotente, adquisición solo tras foreground,
y una cancelación de activación a un segundo. El retorno normal restaura antes de devolver el foco;
[applicationWillResignActive](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationwillresignactive(_:))
restaura antes de perderlo. La notificación tardía de activación no adquiere una sesión cancelada.

Pruebas: adquisición/retorno, eventos relativos, heartbeat, desconexión, teclas y botones retenidos,
cancelación/timeout, API de asociación fallida, restauración reintentada, deinit y recuento equilibrado.
Prueba breve de las APIs reales, cinco ciclos, en M4 y Catalina (26 comprobaciones por equipo).
No instala capturador de eventos ni genera entrada de ratón/teclado. Su resultado comprueba llamadas reales
con éxito y equilibrio de la propiedad; no es una medición óptica de cursor visible. Se descartó CGCursorIsVisible
porque el SDK lo marca no soportado. No se sustituye por acceso privado.

El visor deja de dibujar la superposición separada mientras se controla el escritorio propio del MacBook.
En duplicación con cursor Original, un cursor incrustado en los píxeles puede seguir viéndose en la imagen:
no se borra esa información ni se reinicia la captura solo por cruzar. El uso habitual del usuario es extensión y cursor Rápido.
