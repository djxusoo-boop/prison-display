## 0.4.15 (nombres recordados por pantalla)
- Cada conexión aprobada guarda el nombre del Mac receptor asociado a Pantalla 1 o Pantalla 2.
- El nombre aparece en el selector, el resumen y las instrucciones del modo experto; antes del primer enlace se mantiene Pantalla 1/2.
- Los nombres quedan guardados localmente por separado y no alteran llaveros, permisos ni perfiles de conexión.
- Pruebas de regresión para nombres iniciales, persistencia independiente y etiquetas.

## 0.4.14 (pantalla completa por monitor conectado)
- El botón del Mac principal manda la orden a cada receptor que esté transmitiendo, aunque el otro monitor aún no se haya conectado.
- El botón solo queda desactivado cuando no hay ningún receptor en directo e indica a qué pantallas envió la orden.
- Pruebas cubren primera pantalla, segunda pantalla, ambas y pantalla 2 desactivada.

## 0.4.12 (pantalla completa remota desde el Mac principal)
- Añadido junto al brillo un botón para poner a pantalla completa, con un clic, los dos visores conectados en Pantalla 1 y Pantalla 2.
- La orden viaja por cada conexión cifrada ya aprobada; el receptor abre su visor y entra a pantalla completa sin cambiar el control local del ratón.
- El botón indica cuándo faltan conexiones y solo se activa cuando las dos pantallas están transmitiendo.
- Revisión de versión y protocolo: actualiza las tres apps a la misma versión para usar este control.

## 0.4.11 (visor a pantalla completa y relleno de imagen)
- El pie «PRISON DISPLAY · versión» es un acceso directo: en modo Recibir abre la imagen a pantalla completa; en modo Enviar amplía la ventana de la app.
- El visor receptor rellena la pantalla completa sin deformar el vídeo; si las proporciones difieren, recorta ligeramente los laterales en lugar de dejar bandas negras.
- Al salir de pantalla completa vuelve al ajuste original, que muestra la imagen completa sin recortes.
- Comprobaciones de interfaz cubren el acceso directo y los dos modos de encuadre.

## 0.4.9 (puntero visible durante el cruce)
- El visor mantiene visible el puntero recibido mientras el control cruza entre escritorios; macOS podía aceptar el movimiento y ocultar a la vez la flecha superpuesta.
- Prueba de presentación para el puntero durante el cruce de escritorio.
- Firma persistente restaurada en un llavero dedicado; apps y paquetes universal Intel/Apple Silicon verificados.
- La prueba visual y la instalación en los tres Mac siguen pendientes; ver límites en PRUEBAS.txt.

## 0.4.8 (inicio fiable y ratón más ágil)
- Añadido inicio de sesión configurable para que la app pueda recuperar conexiones guardadas después de reiniciar el Mac; disponible en High Sierra, Catalina y versiones recientes.
- El primer movimiento espera hasta 120 ms a que esté listo el canal rápido, conserva el orden de clics y teclado, y elige una única ruta segura si ese canal tarda más.
- La adaptación de calidad también reacciona a congestión sostenida y jitter medido en el percentil alto, sin bajar por un pico aislado.
- Pruebas sintéticas del canal rápido y de respaldo: 0 fallos en Apple Silicon y x86_64; validación física y paquetes firmados pendientes.

## 0.4.6 (revisión de detección y conexión)
- Lista visible de Mac disponibles con botón Conectar por equipo; conexión recordada separada, con recuperación directa usando el Llavero existente.
- Búsqueda recuperable tras errores, limpieza de resultados antiguos y explicación cuando no aparecen equipos.
- Controles antiguos rechazados después de actualizar la lista; solicitudes duplicadas deshabilitadas.
- Cancelación del emparejamiento y respuestas tardías protegidas frente a desconexión y cambio de función.
- Cierre del visor comparte la limpieza de ratón, teclado, cruce y presentación con Desconectar.
- Conexión antes de diagnóstico en la vista sencilla, cabecera más compacta y controles avanzados conservados en experto.
- Preparada y probada de forma aislada; instalación principal y conexión real 0.4.6 pendientes de la revisión previa.

## 0.4.5 (vista sencilla y modo experto)
- Vista sencilla por defecto, centrada en elegir un Mac, conectar y ver el estado.
- Modo experto en la barra lateral muestra imagen, cursor, teclado, cruce entre equipos y métricas. Cambiar la vista conserva ajustes, dirección y sesiones.
- Acciones Enviar pantalla, Añadir pantalla y Recibir pantalla; instrucciones cortas para conectar.
- Brillo conjunto, pantalla completa y colocación siguen accesibles en la vista sencilla.
- Conexión manual por enlace desplegable mediante ¿No aparece el Mac?
- Preferencia de modo experto guardada por equipo. Las pruebas de distribución aíslan las lecturas del Llavero para no solicitar acceso a las conexiones del usuario.

## 0.4.4 (brillo conjunto)
- Deslizador y botones −/+ en las tres apps para el brillo físico de los Mac conectados.
- Confirmación individual con porcentaje leído de cada pantalla; accesible desde enviar y recibir.
- Distribución desde un receptor a través del emisor al otro receptor, con la conexión cifrada existente.
- Control fuera de las colas de captura e imagen; mínimo 5 % para evitar apagar el panel.
- Barra lateral desplazable para mantener accesibles los ajustes en ventanas pequeñas.

## 0.4.3 (instalada en los tres Mac; reconexión pendiente del Llavero)
- Restaura ambas pantallas en una sola transacción y conserva sus bordes al cambiar la resolución del monitor central.
- Los auxiliares procesan los eventos gráficos necesarios para guardar colocaciones externas.
- Evita sustituir la colocación elegida por la recolocación automática de macOS durante una desconexión temporal; sigue guardando cambios manuales posteriores.
- Recupera coordenadas del cursor en segundo plano cuando se pierde una notificación, manteniendo las consultas fuera del muestreo del ratón.
- Validación real simultánea con High Sierra y Catalina; conservados certificado, identificadores y protocolo de emparejamiento.

## 0.4.2
- Corrige el cierre de Catalina al iniciar el envío: evita enlazar directamente CGPreflightScreenCaptureAccess, ausente en ese sistema aunque el SDK lo declara compatible.
- Consulta dinámica en macOS 11 y posterior; el capturador antiguo mantiene la comprobación de permisos propia de macOS.
- Conserva identidad de firma, identificadores, ajustes y funcionamiento de dos pantallas remotas.

## 0.4.1 — Dos receptores simultáneos
- Pantalla 1 y Pantalla 2 en el mismo emisor, con captura, codificación, canal de cursor, ajustes, recuperación y cuentas del Llavero independientes.
- Identidades de monitor y colocación separadas; conserva la identidad y los ajustes originales de Pantalla 1.
- Indicadores de las dos conexiones en la barra lateral; cambiar de panel no detiene el otro envío.
- Flecha concreta rasterizada y situada por encima del vídeo para evitar depender de imágenes de cursor de AppKit en High Sierra.
- Un solo receptor puede controlar el escritorio principal a la vez; las concesiones se liberan al terminar o expirar.
- Pruebas reales del M4 a High Sierra y Catalina al mismo tiempo, incluyendo cambio de resolución y retiro de un monitor.

# PRISON DISPLAY

## 0.4.0 — 12 de octubre de 2026

- Ambas distribuciones incluyen Enviar pantalla y Recibir pantalla en una ventana común con barra lateral. Conservan los identificadores de MacBook/iMac para actualizar sin sustituir su identidad.
- Logo completo dentro de cada panel, icono de la O grande y centrado, controles espaciados, selectores legibles y desplazamiento en pantallas pequeñas. Función elegida, versión, conexión, permisos de entrada y ajustes aplicados visibles.
- Compatibilidad Intel desde High Sierra 10.13, con runtime Swift incluido, captura CGDisplayStream y transporte TLS-PSK OpenSSL. Apple silicon desde macOS 11, con ScreenCaptureKit cuando está disponible y captura anterior como alternativa.
- High Sierra puede enviar duplicación y recibir duplicación/extensión de otro Mac. La extensión al enviar se deshabilita cuando faltan las clases de pantalla virtual. Sus instalaciones nuevas empiezan a 720p/30; los ajustes guardados se conservan.
- High Sierra utiliza el compresor compatible de Apple en su propia cola, con una entrada acotada; el hardware queda como alternativa si no puede prepararse. Los demás sistemas mantienen el compresor por hardware.
- Captura antigua en una cola separada, con entrega del último fotograma. No acumula una cola de imágenes antiguas mientras se procesa vídeo o entrada.
- Se conserva la primera imagen que llegue durante la preparación. Cambiar resolución con un escritorio quieto ya no descarta su único fotograma. Callbacks de capturas retiradas no alimentan otra captura.
- El envío TLS anterior progresa hasta que el socket pide esperar, con un presupuesto por turno para ceder a otros mensajes. No depende del siguiente ping para terminar un paquete grande.
- Metadatos por fotograma para compresión asíncrona Intel, arranque acotado, finalización de la última imagen inactiva y drenaje antes de cambiar configuración.
- La calidad se ajusta según transporte/decodificación; el retraso del compresor local no se confunde con congestión de la red.
- Misma firma local persistente, identificadores, preferencias y cuentas existentes del Llavero. La función añadida de cada app tiene su propia cuenta de confianza.

Pruebas y límites actuales: TEST-STATUS.md y PRUEBAS.txt del instalador. Las cifras simuladas de controles no sustituyen una comprobación física del ratón/teclado. La fluidez de envío de High Sierra es inferior a la del M4.

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


## 0.4.7
- Lista de equipos disponibles y guardados más directa, con conexión desde cada fila.
- Protección frente a selecciones obsoletas, dobles intentos y respuestas tardías de sesiones anteriores.
- Estado de búsqueda y reconexión más claro.
- Lectura de conexiones guardadas sin abrir diálogos de autenticación automáticamente al iniciar.
- Cerrar el visor libera también los recursos del cruce de ratón y teclado.

Validación, límites y estado de instalación: outputs/PRISON-DISPLAY-v0.4.7/PRUEBAS.txt.
## 0.4.8 (inicio automático, ratón y estabilidad)
- PRISON DISPLAY se abre con el inicio de sesión y recupera conexiones previamente guardadas; el usuario puede desactivar la opción desde la ventana principal.
- El primer movimiento espera brevemente al canal rápido de ratón; si no llega a tiempo, mantiene el canal de vídeo para no alterar el orden de clics y teclas.
- La calidad adapta la carga de vídeo también a la congestión sostenida en la cola de latencia, no sólo a una mediana alta.
- El estado identifica cuándo el canal rápido se está preparando.
- El número de versión permanece visible y sincronizado en ambas apps.

## 0.4.10 (arreglo de cierre al iniciar en High Sierra y Catalina)
- Evita consultar y modificar LSSharedFileList durante el inicio en macOS 10.13–12; la llamada provocaba un cierre inmediato en Intel al preparar «Abrir al iniciar sesión».
- Mantiene el inicio administrado por macOS 13 y posterior. En versiones anteriores el control se desactiva y explica cómo añadir la app desde Ítems de inicio.
- Validación en equipos físicos: instalada y abierta en un MacBook Pro Intel con High Sierra 10.13.6 y en un iMac Intel con Catalina 10.15.8; ambos procesos permanecieron activos sin generar nuevos informes de cierre.

## 0.4.13 (reconexión guardada automática)

- Si macOS rechaza la primera lectura silenciosa del Llavero, la app reintenta una sola vez con la autorización normal de macOS y conecta el Mac ya enlazado al recuperar el perfil.
- Si la autorización sigue pendiente o se rechaza, mantiene disponible «Recuperar conexión guardada» y no elimina el emparejamiento.

## 0.4.16 (estabilidad del codificador compatible)
- Evita enviar la opción RTVC, exclusiva del codificador hardware de Apple silicon, cuando se fuerza el modo software compatible. Esta combinación podía devolver `kVTParameterErr (-12902)`.
- Añade una prueba real de creación y codificación de un fotograma en el modo software compatible; el envío normal conserva el codificador acelerado por hardware.

