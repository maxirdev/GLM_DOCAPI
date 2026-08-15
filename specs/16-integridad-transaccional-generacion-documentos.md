# SPEC 16 — Integridad transaccional de la generación de documentos

> **Estado:** Implementada
> **Depende de:** SPEC 08, SPEC 09, SPEC 11, SPEC 12, SPEC 13, SPEC 14
> **Fecha:** 2026-08-15
> **Objetivo:** Garantizar que el lanzador y los procesos de inventario, documentación, PDF y control de versiones completen cada servicio de forma verificable sin eliminar ni promover artefactos vigentes ante errores, abortos o resultados parciales.

## Por qué existe esta SPEC

La opción 3 del lanzador incorporó lógica de regeneración, respaldo y control de versiones que atraviesa CMD y varios procesos PowerShell. La auditoría detectó parsing frágil del batch, selección no interactiva descartada, códigos de salida ambiguos y eliminación de respaldos aun cuando no existen reemplazos válidos.

La corrección debe tratar el flujo completo como una publicación transaccional por servicio. Ningún error, aborto o resultado parcial puede eliminar o reemplazar el Markdown, PDF o baseline vigente de un servicio sin que exista un reemplazo validado para ese mismo servicio.

## Alcance

**Incluido:**

- Convertir `GenerarDocumentosGLM.cmd` en un lanzador delgado que invoque `binary/GestionDocumentosGLM.ps1` y propague su código de salida.
- Mover a `binary/GestionDocumentosGLM.ps1` el menú, preflight, selección del XPZ de sesión y orquestación de exportación, actualización y regeneración.
- Normalizar todos los `.cmd` a CRLF y fijar esa convención mediante `.gitattributes`.
- Eliminar del lanzador el intercambio de datos mediante `CALL`, `FOR /F`, pipes y comandos PowerShell complejos embebidos.
- Mantener `packagename` como valor exclusivo de `configuracion.json`; no inferirlo ni reemplazarlo desde el XPZ seleccionado.
- Corregir el modo no interactivo de `GenerarDocumento.ps1` para procesar exactamente los FQN explícitos solicitados.
- Reemplazar el paso de arrays mediante `powershell.exe -File` por un contrato inequívoco basado en un manifiesto JSON de ejecución.
- Crear staging por ejecución y publicar Markdown y PDF de forma transaccional por servicio.
- Conservar los Markdown, PDF, versión y hashes anteriores de cada servicio que falle.
- Publicar los artefactos válidos de los servicios exitosos aunque otros servicios terminen pendientes.
- Ampliar el `review.json` actual para registrar el resultado Markdown/PDF y la promoción de cada servicio, sin crear un segundo reporte agregado.
- Uniformar los códigos de salida: `0` completo, `1` error fatal, `2` parcial con vigentes preservados y `3` abortado.
- Promover versión, `documentHash`, `pdfHash` y baseline únicamente después de validar Markdown y PDF.
- Mantener por ahora un único `estado/controlVersiones.json` global porque el repositorio opera con un solo cliente.
- Incrementar el esquema del control a `schemaVersion = 2`; un control incompatible o con otro `lineageId` detiene la operación y solicita una decisión explícita, sin migración ni reinicialización automática.
- Ignorar `estado/` en Git.
- Corregir estados `ACTIVO`, `ELIMINADO` y `OMITIDO`, incluida la reactivación sin perder el historial.
- Hacer que el inventario inicial conserve las llamadas activas no resueltas y que la validación pueda solicitar su exportación.
- Reutilizar el índice multi-XPZ en inventario, validación y generación.
- Regenerar el inventario después de completar el XPZ antes de iniciar la documentación.
- Usar selectores calificados por tipo y FQN en la exportación selectiva para evitar colisiones por nombre local.
- Asociar cada validación, review y staging a un identificador único de ejecución para impedir la reutilización de archivos anteriores.
- Agregar pruebas automatizadas con fixtures y un checklist de smoke test manual con XPZ real.
- Actualizar `README.md` y `AGENTS.md` con los contratos, estados y códigos finales.

**Fuera de alcance (para futuras SPEC):**

- Separar el control de versiones por múltiples clientes; cuando exista más de uno se definirá una SPEC para identificar el estado por cliente y lineage.
- Implementar el panel web de la SPEC 15.
- Cambiar las reglas normativas de análisis, redacción o tipificación documental.
- Inferir `packagename` desde GeneXus o desde el contenido del XPZ.
- Mantener snapshots históricos completos de Markdown o PDF.
- Ejecutar dos actualizaciones concurrentes sobre el mismo estado.
- Migrar automáticamente controles de versiones incompatibles.

## Modelo de datos

### Manifiesto de ejecución

Cada operación no interactiva recibe una ruta a un manifiesto UTF-8 sin BOM creado en un directorio temporal de la ejecución:

```json
{
  "schemaVersion": 1,
  "ejecucionId": "20260815-143012-a4f90d2c",
  "xpz": "C:/ruta/xpz/principal.xpz",
  "fullyQualifiedNames": [
    "APIGLM.Comun.WSListarCaracterAbogado"
  ],
  "staging": "C:/ruta/tmp/actualizacion/20260815-143012-a4f90d2c"
}
```

- `ejecucionId` incluye marca temporal y sufijo aleatorio.
- `fullyQualifiedNames` conserva valores completos y no usa delimitadores interpretados por CMD.
- `staging` contiene los Markdown y PDF candidatos hasta su promoción.
- El manifiesto se elimina al finalizar; ante error puede conservarse junto al diagnóstico si es necesario para investigación.

### Review ampliado

El mismo `Logs/<marca>-review.json` incorpora el resultado de publicación:

```json
{
  "ejecucion": {
    "id": "20260815-143012-a4f90d2c",
    "xpz": "C:/ruta/xpz/principal.xpz",
    "estado": "PARCIAL",
    "codigoSalida": 2,
    "inicio": "2026-08-15T14:30:12",
    "fin": "2026-08-15T14:32:45"
  },
  "servicios": [
    {
      "fullyQualifiedName": "APIGLM.Comun.WSListarCaracterAbogado",
      "estado": "OK",
      "estadoMarkdown": "OK",
      "estadoPdf": "OK",
      "documento": "documentacion/servicios/wslistarcaracterabogado.md",
      "pdf": "documentacion/servicios/wslistarcaracterabogado.pdf",
      "markdownHash": "...",
      "pdfHash": "...",
      "versionAnterior": "1.0",
      "versionObjetivo": "1.1",
      "promocionado": true,
      "pendientes": [],
      "mensajes": []
    }
  ]
}
```

Estados de ejecución:

- `COMPLETO`: todos los servicios aplicables terminaron publicados o correctamente omitidos.
- `PARCIAL`: al menos un servicio conservó su versión anterior por una incidencia recuperable.
- `ERROR`: una falla de infraestructura impidió garantizar el estado del lote.
- `ABORTADO`: el usuario canceló antes de finalizar.

Estados PDF por servicio:

- `OK`: PDF candidato validado y promovido.
- `CONSERVADO`: falló el candidato y permanece el PDF anterior.
- `ERROR`: no existe PDF anterior y tampoco pudo producirse uno válido.
- `NO_APLICA`: servicio omitido o sin documento publicable.

### Control de versiones

`estado/controlVersiones.json` permanece global y pasa a esquema 2:

```json
{
  "schemaVersion": 2,
  "lineageId": "d6e85f10-28f3-409e-afb1-4b38c19fc8af",
  "sourceFingerprint": "...",
  "profileFingerprint": "...",
  "objects": {},
  "services": {
    "APIGLM.Comun.WSListarCaracterAbogado": {
      "wrapperGuid": "...",
      "revision": 1,
      "version": "1.1",
      "documentHash": "...",
      "pdfHash": "...",
      "dependencies": [],
      "status": "ACTIVO"
    }
  },
  "pendientes": {}
}
```

- `version` debe ser exactamente `1.<revision>`.
- `documentHash` y `pdfHash` corresponden a los archivos efectivamente publicados, no a contenido calculado en otra pasada.
- Un servicio fallido conserva íntegramente su registro anterior y queda en `pendientes`.
- Un servicio ignorado conserva su historial con `status = OMITIDO`.
- Un servicio eliminado conserva su historial con `status = ELIMINADO`.
- Un servicio que reaparece desde `ELIMINADO` u `OMITIDO` se considera candidato y vuelve a `ACTIVO` solo después de publicarse correctamente.
- Un archivo con `schemaVersion = 1`, estructura inválida o `lineageId` distinto bloquea la actualización y solicita inicialización explícita; nunca se modifica automáticamente.

## Flujo transaccional

1. `GenerarDocumentosGLM.cmd` inicia `binary/GestionDocumentosGLM.ps1` y no interpreta datos de negocio.
2. El orquestador valida configuración, herramientas, XPZ, estado y exclusión mutua.
3. El usuario selecciona el XPZ de sesión dentro de PowerShell; `packagename` continúa proviniendo de `configuracion.json`.
4. La opción 3 crea `ejecucionId`, staging y manifiesto.
5. Se genera un inventario preliminar que incluye endpoints confirmados y llamadas activas no resueltas.
6. Se valida y completa el XPZ usando reportes creados por la misma ejecución.
7. Se regenera el inventario con el conjunto multi-XPZ ya completado.
8. Se analizan los candidatos y se escriben Markdown únicamente en staging.
9. Se generan y validan los PDF contra los Markdown de staging.
10. Por cada servicio con Markdown y PDF válidos se reemplazan ambos artefactos y se promueve su versión una sola vez.
11. Por cada servicio fallido se descarta su staging, se conservan sus artefactos y baseline anteriores y se registra un pendiente.
12. Se escribe atómicamente el control solo después de resolver todos los servicios.
13. Se completa el review existente con estados Markdown/PDF, hashes publicados y código final.
14. Se elimina el staging únicamente después de confirmar que los artefactos promovidos existen y coinciden con sus hashes.

## Plan de implementación

1. Agregar `.gitattributes` con `*.cmd text eol=crlf`, normalizar los `.cmd` y añadir una prueba estática de finales de línea.
2. Crear `binary/GestionDocumentosGLM.ps1` con preflight, menú y selección XPZ; reducir `GenerarDocumentosGLM.cmd` a la invocación del script y propagación de código.
3. Definir en el orquestador los códigos `0`, `1`, `2` y `3`, y hacer que todas las operaciones propaguen esos estados sin convertir parciales en éxito.
4. Implementar el manifiesto de ejecución y adaptar `GenerarDocumento.ps1` y `GenerarPdfServicios.ps1` para consumirlo sin arrays ambiguos por `-File`.
5. Corregir la selección no interactiva de `GenerarDocumento.ps1` y validar que la cantidad procesada coincida con los FQN solicitados, salvo omitidos explícitos.
6. Extender `GenerarListaEndpoints.ps1` para usar el índice multi-XPZ y conservar candidatos activos no resueltos en el inventario preliminar.
7. Ajustar `ValidarXPZ.ps1`, `CompletarXPZActivoGLM.ps1` y `ExportarXPZSelectivo.ps1` para usar `ejecucionId`, rechazar reportes anteriores y exportar por tipo y FQN.
8. Implementar staging y escritura atómica del Markdown sin reemplazar el vigente durante el análisis.
9. Adaptar `GenerarPdfServicios.ps1` y `RenderizarMarkdownTypstPdf.ps1` para generar, validar y hashear el PDF de staging.
10. Implementar la promoción conjunta por servicio: Markdown, PDF y registro de versión; eliminar el respaldo global previo de PDFs del lanzador.
11. Actualizar `ControlVersiones.ps1` al esquema 2, endurecer su validación y eliminar el fallback no atómico cuando falle `File.Replace`.
12. Corregir en `ActualizarServicios.ps1` los pendientes, ignorados, eliminados, reactivados, fast-path y promoción posterior al PDF.
13. Ampliar el review actual y `ResumirOperacionPdf.ps1` para informar PDFs efectivamente publicados, conservados y fallidos.
14. Agregar un lock exclusivo durante toda la actualización y liberarlo en `finally`; una segunda ejecución termina con error controlado sin modificar artefactos.
15. Añadir `estado/` a `.gitignore` y actualizar `README.md` y `AGENTS.md` con flujo, códigos y recuperación.
16. Incorporar pruebas automatizadas con fixtures para contratos, staging, códigos, control y recuperación.
17. Ejecutar el smoke test manual con un XPZ real, primero sobre una copia controlada de los artefactos, y registrar el resultado en la revisión de implementación.

Cada paso debe dejar funcionales las operaciones no afectadas y debe incluir una verificación específica antes de continuar.

## Criterios de aceptación

- [ ] Todos los `.cmd` versionados usan exclusivamente CRLF y `.gitattributes` impide regresiones.
- [ ] `GenerarDocumentosGLM.cmd` no contiene menú, `FOR /F`, `CALL` a subrutinas ni comandos PowerShell embebidos.
- [ ] Cerrar y volver a abrir el lanzador permite ejecutar todas las opciones sin mensajes de fragmentos tratados como comandos.
- [ ] `binary/GestionDocumentosGLM.ps1` muestra el XPZ activo y ejecuta las mismas operaciones disponibles actualmente.
- [ ] `packagename` se toma siempre de `configuracion.json` aunque se seleccione otro XPZ de sesión.
- [ ] Un manifiesto con varios FQN procesa exactamente todos los servicios solicitados.
- [ ] Las rutas y FQN con espacios, `%`, `!`, `&`, `|`, comillas o caracteres no ASCII no se reinterpretan como comandos.
- [ ] La opción 3 no mueve ni elimina previamente los PDF vigentes.
- [ ] Un servicio con Markdown y PDF válidos reemplaza ambos artefactos y promociona su versión una sola vez.
- [ ] Un servicio cuyo Markdown falla conserva Markdown, PDF, versión y hashes anteriores.
- [ ] Un servicio cuyo PDF falla conserva Markdown, PDF, versión y hashes anteriores.
- [ ] Un fallo parcial publica los servicios exitosos, conserva los fallidos y devuelve código `2`.
- [ ] Un fallo fatal devuelve código `1` sin eliminar artefactos vigentes.
- [ ] Un aborto devuelve código `3` y limpia solamente el staging de la ejecución.
- [ ] Una ejecución completa devuelve código `0`.
- [ ] El review registra `estadoMarkdown`, `estadoPdf`, hashes, versiones y `promocionado` para cada servicio.
- [ ] `ResumirOperacionPdf.ps1` cuenta archivos PDF existentes y validados, no estados inferidos del Markdown.
- [ ] El control solo contiene hashes de Markdown y PDF efectivamente publicados.
- [ ] Un error PDF crea o conserva un pendiente y se reintenta aunque coincidan los fingerprints globales.
- [ ] El fast-path no se activa si falta un Markdown/PDF vigente, hay pendientes o cambió `serviciosIgnorados`.
- [ ] Un servicio ignorado conserva historial con estado `OMITIDO`.
- [ ] Un servicio eliminado conserva historial con estado `ELIMINADO` y no se borra físicamente.
- [ ] Un servicio reactivado se regenera y vuelve a `ACTIVO` solo tras publicar ambos artefactos.
- [ ] Un `controlVersiones.json` incompatible o con otro lineage aborta antes de escribir y solicita decisión explícita.
- [ ] `estado/` está ignorado por Git.
- [ ] Dos actualizaciones simultáneas no pueden modificar el mismo control ni los mismos artefactos.
- [ ] La validación no reutiliza reportes de una ejecución anterior.
- [ ] Una llamada activa cuyo wrapper falta se conserva como candidato y puede solicitarse en la exportación selectiva.
- [ ] La exportación selectiva diferencia objetos homónimos mediante tipo y FQN.
- [ ] El inventario definitivo se regenera después de completar el XPZ.
- [ ] Los temporales se eliminan después del éxito y no se confunden con artefactos vigentes.
- [ ] Las pruebas automatizadas cubren éxito, parcial, fatal, aborto, múltiples FQN, múltiples PDF, pendiente, fast-path, ignorado, eliminado, reactivado, control incompatible y lock concurrente.
- [ ] El smoke test manual con XPZ real confirma que los PDF anteriores permanecen disponibles cuando se fuerza un fallo de conversión controlado.

## Decisiones

- **Sí:** una única SPEC integral porque la integridad depende de contratos coordinados entre todos los componentes.
- **Sí:** `GenerarDocumentosGLM.cmd` queda como lanzador delgado y la lógica pasa a `binary/GestionDocumentosGLM.ps1`.
- **Sí:** transacción por servicio; los éxitos se publican y los fallidos conservan su versión vigente.
- **Sí:** códigos uniformes `0` completo, `1` fatal, `2` parcial y `3` abortado.
- **Sí:** promoción de versión únicamente después de validar Markdown y PDF.
- **Sí:** ampliar el review existente en vez de crear otro reporte agregado.
- **Sí:** manifiesto JSON para transportar listas y contexto entre procesos PowerShell.
- **Sí:** mantener un único `estado/controlVersiones.json` mientras exista un solo cliente.
- **Sí:** reservar para otra SPEC la separación de estado por cliente y lineage cuando se incorporen varios clientes.
- **Sí:** bloquear y consultar ante un esquema o lineage incompatible; no migrar ni reinicializar automáticamente.
- **Sí:** `packagename` proviene siempre de `configuracion.json` y nunca del XPZ.
- **Sí:** fixtures automatizados más smoke test manual con XPZ real.
- **No:** respaldo masivo previo de todos los PDF.
- **No:** interpretar listas mediante delimitadores de CMD o argumentos array ambiguos de `powershell.exe -File`.
- **No:** considerar éxito una generación parcial.
- **No:** promover baseline solo porque existe un Markdown o porque el proceso hijo devolvió código 0.
- **No:** migración automática del control incompatible.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Interrupción durante la promoción de un servicio | Staging en el mismo volumen, reemplazos atómicos, verificación posterior y baseline escrito al final. |
| Markdown promovido y PDF no promovido por una interrupción entre ambos | Registrar un journal mínimo en staging y verificar hashes al reiniciar antes de continuar. |
| Review incompleto por terminación del proceso | Escribirlo mediante temporal y reemplazo; un review sin estado final no permite promover baseline. |
| Control global usado accidentalmente con otro cliente | Validar `lineageId` y documentar que el soporte multi-cliente requiere una SPEC nueva. |
| FQN o rutas con metacaracteres | Manifiesto JSON y parámetros PowerShell; CMD no procesa datos de negocio. |
| Error del exportador selectivo con objetos homónimos | Selector obligatorio `Tipo:FQN` y validación del objeto exportado. |
| Ejecuciones simultáneas | Lock exclusivo adquirido antes de leer baseline y liberado en `finally`. |
| Pruebas con GeneXus lentas o no reproducibles | Fixtures para la lógica y smoke test real separado para integración local. |

## Lo que **no** incluye esta SPEC

- Separación del estado por múltiples clientes.
- Implementación del panel web.
- Inferencia o modificación automática de `packagename`.
- Cambios en las reglas normativas de análisis y redacción.
- Historial completo de snapshots de documentos.
- Migración automática de controles incompatibles.
- Ejecución concurrente de actualizaciones sobre el mismo repositorio.
