# PRISON DISPLAY para Windows — investigación y estado

Versión del trabajo: 0.1.0-dev. No es una app Windows terminada ni un instalador.
Los Mac instalados y su VERSION no se modifican en este trabajo.

## Funciones solicitadas

- Escritorios propios de Mac y Windows controlados mediante un único ratón/teclado, con cruce explícito y retorno seguro.
- Ratón y teclado con interruptores independientes y persistencia.
- Windows recibe una pantalla duplicada o extendida originada por un Mac.
- Windows envía una pantalla existente a un Mac.
- Extender desde Windows: módulo opcional de monitor virtual, sujeto a controlador compatible firmado y autorización separada. No habilitar modo de pruebas, desactivar Secure Boot, rebajar la firma de controladores ni tocar políticas de seguridad.
- Detección en LAN, primer enlace con verificación y reconexión de equipos ya autorizados.
- Estética grafito/morada y número de versión visible.

## Decisiones técnicas investigadas

- Captura propuesta: DXGI Desktop Duplication, con imágenes en D3D11 y cursor separado. Recuperar DXGI_ERROR_ACCESS_LOST al cambiar pantalla, bloquear la sesión o cambiar el modo. Windows.Graphics.Capture es una alternativa a evaluar con Windows/build y GPU reales.
- Vídeo propuesto: Media Foundation H.264 con CODECAPI_AVLowLatencyMode, sin reordenación y colas acotadas. Verificar codificador hardware y admitir fallo explícito o alternativa medida. No afirmar baja latencia hasta medir el equipo.
- Entrada propuesta: SendInput de Win32, con estado propio de teclas/botones y marcadores que eviten bucles. Soltar entrada al desactivar, perder el enlace o finalizar una concesión. Respetar UIPI; no elevar privilegios automáticamente para controlar UAC o aplicaciones elevadas.
- Credenciales propuestas: DPAPI/Credential Manager por usuario. No guardar enlaces/PSK en claro ni anunciarlos por mDNS. No autorizar todos los equipos de la LAN automáticamente.
- Descubrimiento propuesto: API DNS-SD nativa cuando esté disponible. Fallo de descubrimiento no autoriza ampliar el firewall; enlace manual validado como alternativa.
- Compatibilidad: el Mac exige igualdad exacta de versión en el saludo. El trabajo Windows tiene versión de producto independiente y pruebas con el perfil estable de Mac 0.4.22/revisión 10; eso no acredita interoperabilidad de una aplicación completa ni cambia los Mac a 0.4.23.

## Implementado y comprobado aquí

- Núcleo C++17 portátil: encuadre y análisis incremental acotado de paquetes, nombres UTF-8, ratón, teclado, vídeo H.264 y concesión de escritorio.
- Derivación PSK SHA-256 idéntica a CryptoKit y perfil TLS 1.2 PSK-AES128-GCM-SHA256 probado en memoria, incluido rechazo de secreto incorrecto. Esto no constituye una conexión real entre Windows y Mac.
- Vectores generados por los serializadores Swift del producto, incluidos H.264 real y caracteres no ASCII.
- Independencia ratón/teclado, liberación selectiva de pulsaciones, eliminación de modificadores cuando teclado está apagado, cursor de último valor y rechazo de mensajes malformados.
- Script diagnóstico de Windows de solo lectura. No activa SSH, no cambia registro, firewall, permisos, controladores ni política de ejecución.

## Pendiente antes de entregar una app utilizable

1. Confirmar Windows/build, arquitectura, gráfica y disponibilidad de acceso al equipo real.
2. Implementar transporte de sockets con cancelación/límites, emparejamiento P-256/HKDF/AES-GCM, descubrimiento y almacenamiento de enlaces. El ensayo TLS actual cubre criptografía, no el transporte completo.
3. Implementar y compilar captura, códec, visor, entrada y cruce nativos de Windows. No están implementados aún.
4. Integrar interfaz, reconexión y compatibilidad completa con ambos sentidos y varios monitores.
5. Compilar y ejecutar en Windows, probar ratón físico, distribución española, escalado, cambio de monitor, suspensión, bloqueo y desconexión.
6. Elegir/validar la vía de monitor virtual y firma. No hay controlador Windows distribuible preparado.
7. Preparar y verificar instalador; no hay EXE/instalador Windows preparado todavía.

## Fuentes primarias

- https://learn.microsoft.com/en-us/windows-hardware/drivers/display/desktop-duplication-api
- https://learn.microsoft.com/en-us/windows/win32/medfound/codecapi-avlowlatencymode
- https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput
- https://learn.microsoft.com/en-us/windows-hardware/drivers/display/iddcx-objects
- https://github.com/microsoft/Windows-driver-samples/tree/main/video/IndirectDisplay
