# Auditoría de PRISON DISPLAY 0.4.17 · 14 de octubre de 2026

## Estado real
Instalada en el MacBook Air M4, MacBook Pro 2014 con High Sierra 10.13.6 e iMac con Catalina 10.15.8. Se cerraron las apps antes de instalar. Los tres instaladores terminaron correctamente; versión y firmas verificadas. Se conservan copias de las apps anteriores en /private/tmp.

**Validación final pendiente: las apps necesitan una autorización del Llavero después de esta actualización. No se declara resuelta la reconexión de la 0.4.17 ni se afirma que las tres pantallas estén transmitiendo.** El Air muestra autorización pendiente; los avisos del Pro y del iMac se han observado por Compartir Pantalla. La herramienta impide controlar el diálogo protegido; se ha pedido al usuario que lo confirme. No se han cambiado los permisos ni las reglas de acceso del Llavero.

## Defectos corregidos
- El cursor y los clics usaban la proporción de imagen de ventana incluso cuando el visor recortaba la imagen al llenar la pantalla. Se unificaron las transformaciones de vídeo, cursor y entrada, se limita la posición visible y se liberan botones al cambiar de presentación. Cuatro regresiones reproducidas antes de la corrección pasan después.
- Los nombres de receptores antiguos no se actualizaban al reconectar. Ahora se intercambia el nombre por el canal autenticado en cada conexión y se guarda para la siguiente apertura.
- Reconexión automática tiene una preferencia persistente por función y pantalla. Al desactivarla se detiene la sesión y se retira su conexión guardada. El primer enlace continúa requiriendo confirmación; las conexiones ya autorizadas no necesitan repetir el código.
- El estado de reconexión muestra el motivo y el tiempo hasta el reintento. Se han aclarado los controles y el texto de ayuda.
- El inicio automático del Air interpretaba un servicio aún no registrado como si faltase la app en Aplicaciones. Ahora intenta registrar el servicio y comunica el estado real. Tras abrir la app actualizada, el control aparece activado sin el antiguo error. No se ha reiniciado macOS para probar el inicio de sesión real.
- Varias pruebas utilizaban assert en compilaciones optimizadas, por lo que no comprobaban realmente las condiciones. Ahora usan precondition. La prueba de interfaz ejecuta también toda la batería de disposición, no solo cuatro comprobaciones de nombres.

## Pruebas realizadas
- Protocolo, emparejamiento, cifrado TLS y códec H.264: sin fallos. Codificación ARM y decodificación Intel bajo Rosetta verificadas con contenido sintético.
- Componentes de entrada, cursor, cola prioritaria, reconexión, preferencias, inicio y presentación: sin fallos en ARM e Intel.
- Interfaz completa del Air: 1634 comprobaciones sin fallos más las comprobaciones de nombres.
- Pruebas de seguridad del emisor, errores inyectados y limpieza acotada: sin fallos en las dos arquitecturas.
- En el Pro físico y el iMac físico: Preferences, Startup, Reconnect, Interactive, Presentation y PointerView terminan sin fallos. Interfaz completa: Pro 1846 comprobaciones sin fallos; iMac 1837 sin fallos.
- Pantallas virtuales reales en el Air: creación, dos pantallas, cambio de tamaño, retirada, conservación de la principal, identidad y restauración de posiciones sin fallos. Al terminar se recuperó el conjunto original de pantallas.
- Paquetes universales: contenido, versión, firma fijada, arquitecturas, logo, icono y exclusión de claves privadas verificados.
- Antes de actualizar, cierre y reapertura de la 0.4.16 en el Air: los dos receptores reconectaron automáticamente sin códigos. Imagen del Pro observada por Compartir Pantalla. Este resultado NO se atribuye a la 0.4.17.

## Hallazgo del Llavero
La firma designada de 0.4.16 y 0.4.17 coincide (mismo identificador y certificado local). Sin embargo, securityd registra `ACL partition mismatch`: la autorización adicional contiene el hash de la compilación anterior. La firma persistente por sí sola no ha evitado el aviso. No basta con comprobar codesign para prometer continuidad del acceso al Llavero tras una actualización.

Fuentes primarias consultadas:
- https://developer.apple.com/library/archive/technotes/tn2206/
- https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements
- https://github.com/apple-oss-distributions/Security/blob/main/SecurityTool/macOS/security.1
- https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/notfound

## Pendiente tras confirmar los avisos
1. Verificar transmisión simultánea a Pro e iMac en 0.4.17 sin un nuevo emparejamiento.
2. Cerrar y abrir cada app, comprobar reconexión sin códigos y sin otro aviso en la misma compilación.
3. Verificar pantalla completa desde el Air en ambos receptores y comparar la colocación guardada: Pro a la izquierda, iMac en el centro, Air a la derecha.
4. Comprobar cursor, clics y brillo con imagen real. Las pruebas sintéticas no demuestran latencia óptica ni garantizan ausencia de tirones en la red Wi-Fi.

## Evidencias
Registros en build/audit-20261014-*.log. Los logs de pruebas remotas están además en /private/tmp/prison-audit-20261014/audit-0.4.17 de cada receptor. No contienen credenciales de producción.

## Seguimiento · 14 de octubre, 19:20
El usuario confirmó los avisos del Air. Ambas pantallas del emisor mostraron «Conexión recuperada». Se cerró y reabrió la app: cambió el proceso de 89839 a 90254 y volvió a recuperar las autorizaciones sin otro aviso. Esto valida la recuperación del Llavero en la misma compilación del Air; no valida aún la transmisión. El iMac sigue mostrando su aviso protegido y el Pro lo tenía pendiente. El usuario indicó que ahora no puede acceder a ambos; la prueba conjunta queda pendiente, sin modificar sus autorizaciones.
