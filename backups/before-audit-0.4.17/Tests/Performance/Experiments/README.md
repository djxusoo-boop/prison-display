Experimentos de latencia del 5 de octubre de 2026. No forman parte de las apps.

ProtocolChunks.swift: bloques de vídeo de 12 KiB, dos créditos y confirmación remota. Descartado tras comparación física; no produjo mejora consistente y redujo fluidez.
CursorUDP.swift: posiciones AES-GCM con claves por dirección, nonce aleatorio, secuencia antirrepetición y alternativa TCP. Pasó las pruebas locales; las comparaciones físicas de AWDL y LAN perjudicaron al vídeo. No se activa ni distribuye en el producto.

Resultados: build/chunk-comparison.json, build/udp-routed-comparison.json, build/udp-lan-comparison.json. Los ejecutables de esos experimentos se conservan en build/PerfSender-chunks, PerfReceiver-chunks, PerfSender-udp, PerfReceiver-udp y PerfReceiver-udp-lan. Los scripts chunks.py/udp.py/udp-lan.py ejecutan esas copias compiladas, no la compilación actual del producto.
La comparación final del producto usa window-final.py y los binarios PerfSender-window-final/PerfReceiver-window-final.
