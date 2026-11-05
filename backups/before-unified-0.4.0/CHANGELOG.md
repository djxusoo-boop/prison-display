# PRISON DISPLAY

## 0.3.20 — 9 de octubre de 2026
- El cruce espera a que la app del iMac tenga el foco antes de ocultar el cursor. Un fallo de activación cancela el cruce sin bloquear entrada local.
- Durante el control del MacBook, separa el ratón físico de la posición del cursor local y usa sus desplazamientos relativos; oculta el cursor con una única llamada equilibrada de AppKit.
- Restituye asociación y visibilidad al regresar, desconectar, detener, salir o cambiar de app. Cancela aprobaciones tardías y conserva el retorno de emergencia ⌃⌥Esc.
- Suprime la copia del cursor en el visor durante ese control y restaura la posición más reciente al volver. El cursor integrado en el vídeo en modo Original/duplicación no se puede borrar mediante esta superposición.
- Conserva firma, identificadores, permisos y preferencias; ambas apps e instaladores muestran 0.3.20.

Instalada y verificada en ambos equipos. Captura real de 180 s (7.944 imágenes) y ocho ajustes en directo completados, sin interrupciones ni perfiles nuevos. La app canónica del iMac está abierta y pendiente de confirmar su estado; falta observación física del cursor por el usuario. Evidencia: build/review-0.3.20/.

## 0.3.19 — 9 de octubre de 2026 · en validación
- Estado visible de disponibilidad, conexión, preparación, imagen activa, aplicación de ajustes, reconexión y error; se sitúa debajo del logo en ambos equipos. Permisos de entrada y ajustes aplicados tienen avisos independientes. Los botones impiden solicitudes duplicadas durante conexión/reconexión y mantienen disponible la desconexión; los avisos de inicio fallido y emparejamiento respetan el orden de las operaciones.
- La conexión activa requiere que el visor acepte una imagen. Decodificar, descartar por acumulación o devolver un resultado tardío ya no confirma imagen; la confirmación de transporte sigue sin esperar al visor. Protocolo 8, misma versión necesaria en ambos equipos.
- Recuperación inicial del Llavero después de crear la ventana y fuera de la interfaz, sin una lectura pasiva previa. Un único intento pendiente; cancelar o parar invalida respuestas tardías. Guardar y olvidar también se realizan fuera de la interfaz y solo confirman éxito real.
- La conexión se guarda al llegar una imagen, y el receptor conserva teclado, cruce y borde. El cruce se rearma al recibir imagen si tiene el permiso existente. Si macOS desactiva el capturador de entrada, la casilla y el aviso lo reflejan y se devuelve el control.
- El permiso de entrada comunicado al iMac se actualiza durante la sesión; un cambio ya no exige reconectar para que se refleje. El canal rápido y su alternativa muestran su estado.
- La indisponibilidad temporal de la pantalla conserva la autorización y la pantalla virtual; el receptor conserva su espera progresiva hasta recibir imagen. Un permiso denegado sigue siendo definitivo y no se solicita repetidamente.
- Bonjour, vídeo y control usan la red compartida sin activar Wi-Fi directo adicional. La detección automática continúa; ambos Mac deben compartir Wi-Fi o LAN. La repetición sin compilaciones mejoró fluidez y pausas de cursor, aunque persisten picos aislados.
- Respuestas tardías de conexiones y listeners retirados no afectan a otra sesión. Conserva certificado, identificadores, preferencias, logo e icono.

Ambas apps 0.3.19 fueron instaladas y verificadas durante la investigación. El MacBook ya está desbloqueado y se han completado las comparaciones de captura real entre ambos equipos. ACK rápido y cursor16 no mejoraron de forma consistente; siguen siendo exclusivamente diagnósticos. La repetición de red compartida sin compilaciones simultáneas terminó; se incorpora a la candidata y se está verificando la regresión final. Comprobaciones sintéticas y compilación no sustituyen las pruebas reales de imagen y ratón. Evidencia: build/review-0.3.19/PROGRESO.md.

## 0.3.18 — 8 de octubre de 2026
- Recuperación explícita de la conexión guardada cuando el Llavero requiere autorización. La lectura se realiza fuera de la interfaz, permite cancelar y no borra credenciales ni altera el acceso del Llavero.
- Una parada invalida resultados tardíos; no se generan solicitudes de autorización automáticas repetidas.
- Conserva sin cambios las mejoras de vídeo/entrada de0.3.17 y el certificado persistente.

## 0.3.17 — 8 de octubre de 2026
- Los perfiles de 20/40 Mb/s empiezan con el presupuesto seleccionado, en vez de quedar limitados inicialmente a 12. Se mantiene la reducción ante congestión y su pausa de recuperación.
- A 60 FPS, el límite de cuantificación pasa de 32 a 36 en esos perfiles: conserva el límite de degradación de texto y evita omitir la mayoría de las imágenes de escenas complejas. A 30 FPS se conserva 32.
- La entrada recibida del iMac agrupa movimientos consecutivos obsoletos antes de aplicarlos, conservando clics, teclas, arrastres y cambios de control en orden. Cancelación por sesión, límite de acumulación y turnos acotados.
- Actividad de baja latencia solo durante sesiones autenticadas, liberada al cortar o parar; se permite el reposo del equipo.
- Conserva dos imágenes como máximo en tránsito con canal de control independiente, firma persistente, identificadores, preferencias y protección gráfica de 0.3.16.

Comparación de captura real con texto en movimiento en M4→Catalina: referencia anterior 8 FPS frente a 40–48 con el nuevo perfil máximo en muestras de 20 s. Prueba final de 90 s: 43,87 FPS, sin caída durante la prueba y cero perfiles nuevos. Entrada generada por el canal real: mediana de ida/vuelta de 10,11 ms; no es una medición óptica ni del ratón físico. Persisten pausas aisladas de Wi-Fi. Core 313, funciones 400, canal independiente 20 y Catalina 224 comprobaciones sin fallos. Se conservan ensayos fallidos y variantes descartadas en build/tuning-0.3.17; no se afirma lag cero.

## 0.3.16 — 8 de octubre de 2026
- Identidad estable de pantalla virtual por resolución, evitando generar nuevos perfiles de color en cada conexión. Exclusión de una segunda copia y arranque/parada del auxiliar con límites de tiempo.
- Creación y retirada de pantalla fuera de la interfaz y de las colas de vídeo/entrada. Guarda la posición solo al cambiar la configuración y conserva los bordes al cambiar resolución.
- Protección ante sobrecarga sostenida de color: retira únicamente su propio auxiliar y detiene la extensión con un aviso, incluso si la cola de entrada está bloqueada. La app no reinicia servicios del sistema.
- Retirada de la pantalla aunque ScreenCaptureKit no complete la parada; salir tiene una espera limitada de la cola de entrada.
- Incorpora el máximo de 40 Mb/s, caché de geometría y mejoras adaptativas de la candidata 0.3.15. Conserva firma, identificadores, preferencias, logo e icono.

366 comprobaciones de funciones y 209 en Catalina sin fallos. Captura real con movimiento durante 90 s y ocho configuraciones en directo completadas; cero perfiles nuevos. Ambas apps instaladas y verificadas en 0.3.16. Se realizó, con autorización específica y respaldo, una limpieza selectiva de 297 ICC y sus registros antiguos; la carga de color se mantiene en 0 % en las muestras posteriores. La limpieza no forma parte del instalador. Hay pausas de Wi-Fi observadas y falta valorar el ratón físico; no se afirma lag cero ni ausencia de futuros bloqueos. La revisión visual final espera desbloqueo manual del MacBook.

## 0.3.15 — 8 de octubre de 2026 · en validación
- Nuevo máximo de 40 Mb/s, conservando los índices de los perfiles anteriores y los ajustes guardados.
- Límites de pantallas almacenados e invalidados al recolocarlas o cambiar su configuración; evita consultarlos al servidor gráfico en cada movimiento de ratón.
- Arranque a 12 Mb/s en los perfiles de 20/40, recuperación más rápida en enlaces estables y pausa de recuperación tras congestión para reducir oscilaciones de calidad.
- Cambiar únicamente la calidad actualiza el codificador, conserva la captura, la pantalla virtual y el canal de control.
- Indicador separado de datos de vídeo generados, objetivo adaptativo y máximo seleccionado.
- Mismo certificado persistente, identificadores, logo e icono.

Los paquetes se han preparado y comprobado internamente. No se distribuye ni instala esta versión mientras quede pendiente la prueba completa de extensión y cambios en directo: la sesión gráfica del MacBook ha dejado de responder a consultas de pantalla y a la apertura de la app instalada 0.3.14. Se conservan los fallos de las pruebas; no se declara resuelto el lag.

## 0.3.14 — 8 de octubre de 2026
- Cursor en ambos sentidos y entrada del iMac por un canal TLS independiente, activado de forma predeterminada.
- Decodificación en una cola separada de la entrada. Se mantienen clics, teclas, arrastres y cambios de sesión en orden; se agrupan únicamente movimientos consecutivos obsoletos.
- Búsqueda entre pares detenida mientras se conecta y transmite. Se prioriza la red compartida, con IPv4 y alternativa IPv6, conservando AWDL como último recurso automático.
- Dirección autenticada del canal de control para evitar «No route to host» de Catalina. Protocolo 7; ambas apps deben actualizarse juntas.
- Hasta dos imágenes en tránsito cuando el canal de control independiente está autenticado; una mientras se inicia o se utiliza la alternativa de vídeo. Cambiar el límite conserva las confirmaciones pendientes.
- El perfil «Más calidad» limita la degradación del texto en el codificador Apple. Con poco ancho de banda puede omitir imágenes para conservar detalle.
- Al fallar un canal de entrada utilizado se reconecta sin repetir clics. Se vuelve a anunciar disponibilidad tras un corte.
- Se conserva el certificado persistente, identificadores, preferencias, logo e icono.

Pruebas con la escena repetible y el motor/visor en el M4 y Catalina: 20,50–22,98 FPS en 0.3.13 frente a 24,97–26,40 FPS en esta versión. La mejora media de estas cuatro muestras fue del 18 %. Aún se registraron pausas del cursor cercanas a 200 ms. Estas medidas y la prueba de transporte con movimientos simulados no prueban la latencia óptica ni confirman que el ratón físico ya se sienta bien.


## 0.3.10 — 5 de octubre de 2026
- Ventana de envío de una imagen en el emisor para limitar acumulación delante del cursor.
- Ida/vuelta mostrada como media del intervalo, con reinicio al cambiar captura.
- Comparación física de dos muestras de 30 s por variante: 28,93→38,81 FPS y p95 de imágenes 149,81→88,36 ms. No es latencia óptica del ratón.
- Captura real y recuperación tras pausa de proceso de 15 s comprobadas en M4→Catalina.
- Firma y recursos originales conservados.

## 0.3.9 — 5 de octubre de 2026
• El MacBook se anuncia al abrir la app para facilitar que el iMac lo encuentre.
• Si macOS tarda en preparar la pantalla, se reintenta la captura de forma limitada.
• Se recuperan interrupciones temporales de captura conservando conexión y pantalla virtual; los errores de permisos no provocan reintentos infinitos.
• La lectura inicial del Llavero ya no deja el arranque esperando una autorización oculta. Si no puede leer la conexión guardada, muestra el problema y permite conectar manualmente.
• Se limpia la información de rendimiento antigua al parar o reiniciar la captura.
• Más tiempo para iniciar la pantalla virtual y retirada segura si falla el inicio.

Se conserva la firma local, los identificadores, logo, icono y formato universal.
Esta versión mejora estabilidad. No se ha medido una reducción de la latencia física del ratón.


## 0.3.8 — 4 de octubre de 2026
- Cursor separado: intervalo de consulta reducido de 16 a 8 ms, manteniendo cola acotada y prioridad.
- Cursor Original opcional dentro del vídeo para conservar formas de las apps; Rápido sigue predeterminado.
- Teclado del iMac opcional, limitado al visor enfocado; liberación de teclas y modificadores al perder foco o desconectar.
- Rueda horizontal y modificadores del ratón.
- Recordar conexión voluntariamente en el Llavero y recuperar el servicio Bonjour al volver a abrir ambas apps; olvidar en el emisor revoca la clave anterior.
- Comprobación temprana de grabación de pantalla y errores remotos legibles sin reconexión infinita por fallo de captura.
- Se conserva certificado, identificadores, logo, icono, ajustes y distribución universal.

## 0.3.0 — 2 de octubre de 2026
- Nombre público PRISON DISPLAY en ambas apps, menús, visor y pantalla virtual.
- Logo PRISON original integrado en cabeceras; icono nativo únicamente con la O del logo sobre negro.
- Interfaz oscura con tarjetas de pantalla/conexión/estado, acento violeta y botón principal destacado.
- Versión visible y desplazamiento automático en pantallas pequeñas.
- Se conservan identificadores internos, cifrado, enlaces y controles de la versión anterior.

## 0.2.7 — 2 de octubre de 2026
- Cursor separado del vídeo: puntero local inmediato y posición del MacBook por mensajes pequeños cifrados. La representación remota usa flecha estándar.
- Ratón del iMac: movimiento, clic, doble clic, arrastre, botón derecho y rueda vertical. Requiere Accesibilidad del emisor; el teclado permanece en el MacBook.
- Movimientos pendientes agrupados; clics y liberaciones mantienen orden. Liberación de botones al cambiar ajustes, perder foco o desconectar.
- Búsqueda breve de interfaz Wi-Fi entre pares antes de abrir vídeo; alternativa por red local si no está disponible.
- Imágenes completas H.264 cada tres segundos para reducir picos periódicos de datos en la conexión fiable.

## 0.2.6 — 1 de octubre de 2026
- Descubrimiento y vídeo admiten Wi-Fi entre pares mediante Bonjour, con alternativa al nombre local si el servicio no conecta.
- Calidad automática: arranque a un máximo de 6 Mb/s, reducción rápida ante congestión y recuperación gradual hasta el límite elegido, sin reiniciar el codificador.
- Se conserva únicamente la última captura pendiente; al liberarse el envío se transmite esa imagen.
- Reloj del vídeo basado en tiempo real, con duración conforme a los FPS seleccionados.
- Confirmación tras decodificar, sin esperar a la interfaz. Presentación con buzón de una imagen reciente.
- Medición separada del tiempo de decodificación y bitrate actual. Tráfico marcado como vídeo interactivo.

## 0.2.5 — 1 de octubre de 2026
- El visor descarta una imagen ya decodificada si su capa aún no admite otra, conservando la conexión y el estado H.264. Evita desconexiones al arrancar con varias imágenes en tránsito.

## 0.2.4 — 1 de octubre de 2026
- Ajustes de modo, resolución, FPS y calidad aplicados durante la conexión, sin nuevo emparejamiento.
- Se vacía la ventana de transporte antes de cambiar el codificador y la captura; se mantiene el orden de los fotogramas.
- Los cambios de FPS/calidad conservan la pantalla virtual; cambiar resolución recrea la pantalla para evitar que macOS la retenga al desconectar.

## 0.2.3 — 1 de octubre de 2026
- Hasta tres fotogramas en tránsito para evitar que cada envío espere una ida y vuelta completa. Cola limitada y confirmaciones verificadas.
- El receptor admite esa ventana sin interrumpir la transmisión.

## 0.2.2 — 1 de octubre de 2026
- La conexión de vídeo utiliza el nombre Bonjour enviado en las credenciales cifradas, en lugar de reutilizar una dirección IPv6 local resuelta. Corrige el error de ruta reproducido en Catalina.
- El visor muestra el estado o el error de conexión mientras no recibe imagen.
- Nombre de conexión común para detección automática y enlace manual.

## 0.2.1 — 1 de octubre de 2026
- El anuncio de disponibilidad se retira al iniciar una transmisión.
- Caducidad de las solicitudes de emparejamiento a los dos minutos.
- El receptor exige su aprobación local antes de aceptar credenciales.
- Pruebas de descubrimiento Bonjour, rechazo, enlace y emparejamiento cifrado.

## 0.2.0 — 1 de octubre de 2026
- Conexión entre equipos detectados sin introducir IP ni clave.
- Aprobación en ambos Mac con código de verificación de seis cifras.
- Intercambio P-256 y transferencia de credenciales cifrada con AES-GCM.
- Enlace airedisplay como recurso manual, con botones copiar/pegar.
- Eliminados los campos de dirección y clave del flujo normal.

## 0.1.1 — 1 de octubre de 2026
- Corregido el cierre de captura durante el arranque.
- Una clave incorrecta no cierra la escucha del MacBook.
- Visible la dirección manual y el puerto junto al estado de espera.
- Conservadas las proporciones en macOS 14 o posterior.
- Corregida la detección del codificador RTVC de baja latencia de Apple.
- Número de versión compartido entre ventanas, menús, visor, metadatos y protocolo.

## 0.1.0 — 1 de octubre de 2026
- Implementación inicial de emisor arm64 y receptor Intel para Catalina.
- H.264, conexión TLS con clave de 128 bits, búsqueda Bonjour.
- Duplicación y creación de escritorio extendido mediante pantalla virtual.
- 720p, 1080p y 1440p; 30/60 FPS; 6, 12 y 20 Mb/s.
- Confirmación de cada fotograma; sin cola de vídeo acumulada.


## 0.3.4
- Certificado local persistente para conservar identidad entre compilaciones y requisito ligado a certificado más identificador.
- Compilación falla si falta la clave persistente; sin regeneración o firma ad hoc automática.
- Accesibilidad sin solicitudes automáticas repetidas; abre Ajustes cuando falta.
- Preflight de captura evita iniciar solicitudes de pantalla repetidamente.
- Comparación de firmas entre 0.3.3 y 0.3.4; actualización real en el MacBook conserva pantalla y Accesibilidad sin volver a concederlos, también después de cerrar y reabrir ambas apps.


## 0.3.5

- Cursor del MacBook: se recalcula su posición con los límites actuales de la pantalla, incluso después de moverla en Ajustes. Se evita ocultarlo indefinidamente junto a una posición antigua del ratón del iMac.
- Reconexión automática después de un corte de una sesión ya aceptada, con espera progresiva de 1 a 10 segundos. Conserva en memoria la misma clave de esa sesión y la pantalla virtual. Detener, Desconectar o cerrar las apps cancela los reintentos; un nuevo inicio del emisor necesita emparejar de nuevo.
- Modo, resolución, FPS y calidad se guardan al cambiarlos y se recuperan al abrir la app.
- Posición de la pantalla guardada durante el uso y al detener. Se restaura al recrearla y se mantienen los lados al cambiar resolución.
- Ventana del visor con posición y tamaño guardados.
- La pantalla virtual tiene un proceso auxiliar dentro de la misma app para retirarla correctamente después de que macOS haya cambiado su colocación. No instala servicios ni necesita permisos nuevos.
- Misma firma persistente de 0.3.3 y 0.3.4. No se reinician ni se amplían permisos de pantalla o Accesibilidad.

Instala 0.3.5 en ambos Mac y abre las copias de Aplicaciones. La reconexión cubre cortes de la sesión mientras el emisor sigue abierto; no guarda credenciales de conexión en disco ni empareja automáticamente otro ordenador.
