# Firma persistente de PRISON DISPLAY

Las versiones desde 0.3.3 usan el certificado local indicado en `identity.json`, con requisitos automáticos que exigen el identificador de la app y ese certificado exacto. Una firma ad hoc liga el requisito a cada compilación y rompe la continuidad de los permisos.

`build.sh` llama a `sign.py` y falla si falta la identidad. No genera certificados nuevos ni vuelve a firma ad hoc. El mismo certificado firma las dos arquitecturas. No se emplean requisitos basados solamente en el identificador ni se altera TCC para conceder permisos.

Los secretos están exclusivamente en `.signing`, excluido de Git y de los paquetes. El firmador solo consulta el llavero dedicado, cuyo ACL y partición de firma autorizan `codesign`; si no encuentra la identidad fijada, se detiene sin consultar el llavero de inicio de sesión ni provocar avisos repetidos de contraseña. `identity-backup.p12` es el respaldo cifrado, protegido por `keychain-password`; el llavero de firma se desbloquea con `signing-v2-password`. Deben conservarse juntos en un respaldo privado. La carpeta tiene modo 0700 y los archivos, 0600. No compartir esta carpeta con las apps.

El firmador no cambia la lista de búsqueda, el llavero predeterminado, los ajustes de confianza, Gatekeeper ni SIP. El certificado no es Developer ID y no permite notarizar. No debe regenerarse al limpiar `build`.

La migración desde la firma anterior requiere renovar los permisos una vez. La continuidad debe verificarse con captura real y Accesibilidad antes y después de actualizar a otra versión firmada con este certificado. Una comprobación estática de los requisitos no sustituye esa prueba.

Referencia: [Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).
