# SPEC 17 — Historial de versiones por servicio en Markdown

> **Estado:** Implementado
> **Depende de:** SPEC 08, SPEC 16
> **Fecha:** 2026-08-15
> **Objetivo:** Registrar en un archivo Markdown el historial de versiones de cada servicio, con una descripción legible de qué objetos, parámetros, campos, tipos y obligatoriedades cambiaron en cada versión, sin alterar ningún contrato existente del control de versiones.

## Por qué existe esta SPEC

El control de versiones (SPEC 08, SPEC 16) conserva solo el estado actual de cada servicio. No responde "qué cambió entre la 1.0 y la 1.1". Se necesita un historial legible por una persona. Debe ser un artefacto derivado: el control sigue siendo la fuente de verdad y todos los contratos vigentes — lock, escritura atómica, códigos de salida, pendientes, fast-path, reinicio — permanecen intactos.

## Alcance

**Incluido:**

- Nuevo `estado/historialVersiones.md`, ignorado por Git, legible a ojo, UTF-8 sin BOM con LF.
- Una entrada por bump de versión (incluida la `1.0` de un servicio nuevo), con fecha y descripción legible de los cambios.
- Descripción generada comparando las tablas del Markdown publicado anterior con el nuevo: parámetros/campos agregados o eliminados, cambios de Tipo, de Obligatorio (NO→SI, SI→NO) o de descripción, códigos HTTP agregados o eliminados, y conteo por sección como respaldo.
- Nombre de los objetos GeneXus que cambiaron (resueltos desde `ObjetosEfectivos`); un objeto eliminado del XPZ queda como `Tipo:guid`.
- Dos modos de escritura: **append** (lotes normales, después de la escritura atómica del control) y **reemplazo** (cuando la ejecución reinicializa el control).
- Reinicio limpia y regenera: cuando la ejecución reinicializa el control (opción 3 confirmada con `-Inicializar`, control inválido/incompatible, control inexistente con historial previo o `lineageId` del encabezado distinto del control), el historial se reemplaza por completo al final del lote; en el resto de los lotes solo se agrega.
- Encabezado con `LineageId` y `Creado` como identidad del historial y disparador de reemplazo ante cambio de KB.
- Preservar intactos todos los contratos de SPEC 16: lock exclusivo, escritura atómica del control, códigos de salida `0/1/2/3`, pendientes, estados `ACTIVO/ELIMINADO/OMITIDO`, fast-path y reinicio por `-Inicializar`.
- El historial se escribe únicamente después de la escritura atómica del control y nunca altera el resultado del lote; su fallo es una advertencia sin efecto sobre el control, los artefactos ni el código de salida.

**Fuera de alcance (para futuras SPEC):**

- Cualquier cambio en `binary/ControlVersiones.ps1`, `GenerarDocumento.ps1`, `GenerarPdfServicios.ps1`, manifiesto, lanzador o perfil documental.
- Sección "Historial de cambios" dentro del documento/PDF de cada servicio.
- Script de consulta del historial.
- Reconstruir versiones anteriores a la adopción.
- Motivos de cambio por versión.
- Snapshots completos de Markdown o PDF.
- Soporte multi-cliente.

## Modelo de datos

### `estado/historialVersiones.md` (sin esquema)

```markdown
# Historial de versiones por servicio

LineageId: d6e85f10-28f3-409e-afb1-4b38c19fc8af
Creado: 2026-08-15

## APIGLM.Seguridad.WSAutenticarUsuario

- **1.1** (2026-08-15) — Objetos: SDT `APIGLM.Seguridad.Autenticacion` modificado.
  - Entrada: se agregó el parámetro `Dispositivo` (String (50), NO).
  - Entrada: el parámetro `Contraseña` pasó Obligatorio de NO a SI.
  - Errores específicos: se agregó el código 409 con su mensaje.

## APIGLM.Comun.WSBuscarCodigoPostal

- **1.0** (2026-08-15) — Versión inicial.
- **1.1** (2026-08-16) — Objetos: Procedure `APIGLM.Comun.BuscarCodigoPostal` modificado.
  - Salida exitosa: se eliminó el campo `ProvinciaDesc`.
  - Entrada: el parámetro `CodigoPostal` cambió Tipo de String (4) a String (8).
```

Convenciones:

- Modo append: cada lote normal agrega un bloque `## <FQN>` por servicio promovido con bump y una entrada por versión.
- Modo reemplazo: en un lote que reinicializa el control, el archivo se reescribe con encabezado nuevo (lineageId y fecha del lote) y las entradas `1.0` de los servicios promovidos; un servicio con documento idéntico registra `1.0 — Versión inicial.` sin cambios inventados.
- La entrada de un servicio nuevo es `- **1.0** (<fecha>) — Versión inicial.`
- La fila `Versión` de la tabla Definición se ignora siempre.
- Si las tablas no son comparables, la sección queda como `Se modificó la sección N (+a/−b)`.
- Las líneas de cambios van indentadas bajo la entrada, sin tope.

### `estado/controlVersiones.json`

No cambia: esquema 2, estructura, validación, escritura atómica y reinicio tal como quedaron en SPEC 16.

## Plan de implementación

1. Crear `binary/HistorialVersiones.ps1` con `Describir-CambiosDocumento` (compara tablas por sección y produce las frases), `Redactar-EntradaHistorial` (bloque Markdown de una versión) y `Escribir-HistorialVersionado` (append o reemplazo; UTF-8 sin BOM, LF; crea el encabezado si no existe). Verificar con MD de ejemplo en consola.
2. Modificar `binary/ActualizarServicios.ps1` sin alterar su flujo: capturar el contenido del Markdown publicado antes de `Promover-ServicioArtefactos`; tras una promoción con bump, construir la entrada (objetos desde `comparacion.ObjetosModificados` y dependencias; descripciones con `Describir-CambiosDocumento`); después de `Escribir-ControlVersionesAtomico`, decidir el modo (reemplazo si hubo reinicio o si el `lineageId` del encabezado difiere del control; append en el resto) y escribir las entradas del lote en una única operación; un fallo solo emite advertencia.
3. Actualizar `test/Run-Tests.ps1` agregando casos sin modificar los existentes, en tres grupos nuevos:
   - `Ejecutar-CasosHistorial` (unit tests de `binary/HistorialVersiones.ps1`, dot-sourceado vía `Cargar-ModulosProduccion`): `Describir-CambiosDocumento` (parámetro agregado, eliminado, cambio de Tipo, de Obligatorio, código HTTP nuevo o eliminado, fallback de conteos, fila Versión ignorada); formato de entrada (`- **1.<n>** (YYYY-MM-DD) — <texto>`); detalle no vacío en toda entrada (`Versión inicial.` o líneas de cambio); continuidad sin saltos ni duplicados por bloque; detección de pérdida de entradas (1.0 y 1.2 sin 1.1); append que conserva el prefijo byte a byte; reemplazo por reinicio y por lineageId distinto; encabezado con `LineageId` y `Creado` coincidentes con el control; entrada con versión derivada del control y nunca del archivo; sincronía entre la última revisión del bloque y la revisión del control.
   - `Ejecutar-CasosEstadoControl` (unit tests de `ControlVersiones.ps1`, ya dot-sourceado): `Obtener-VersionServicio` (1.0 sin control previo; incremento 1.7→1.8; sin incremento 1.7); `Comparar-ControlVersiones` (fast-path; no fast-path con pendiente; lineage cambiado con motivo de bloqueo; objeto modificado que afecta servicios por dependencias; cambio de perfil que afecta a los ACTIVO; servicios nuevos y eliminados); `Validar-ControlVersiones` negativos adicionales (revision negativa, documentHash/pdfHash/dependencies faltantes, lineage en blanco); `Escribir-ControlVersionesAtomico` con control inválido que lanza y conserva el archivo previo íntegro; tests por contenido (regex, sin dot-sourcear `ActualizarServicios.ps1`): doble bump prohibido en el mismo lote, incremento de `attempts` en pendientes, normalización de hash excluyendo la fila Versión y reinicio del registro sin publicar.
   - `Ejecutar-CasosValidacionEstado` (validadores estáticos de `estado/`, con SKIP si los archivos no existen): el control productivo pasa `Validar-ControlVersiones`; para cada servicio ACTIVO con hashes no vacíos, los Markdown y PDF publicados existen y sus hashes coinciden con el control y la fila `Versión` del Markdown coincide con `version` (un ACTIVO con hashes vacíos es legal por `Marcar-ServicioSinPublicar`); pendientes con `attempts` ≥ 1 y `reason` no vacío; dependencias únicas y no vacías; `lineageId` con formato GUID y fingerprints hex de 64; historial coherente con el control (última revisión del bloque igual a la del control y lineageId del encabezado igual al del control).
4. Actualizar `README.md` y `AGENTS.md`: describir el archivo, los dos modos y la semántica best-effort.
5. Ejecutar `test/Run-Tests.ps1` completo (los casos vigentes deben pasar igual) y smoke test manual con XPZ real: modificar un SDT compartido y verificar la entrada 1.1; repetir sin cambios y verificar que no se agrega nada; reiniciar con la opción 3 y verificar que el historial se regenera limpio.

## Criterios de aceptación

- [ ] Todos los casos existentes de `test/Run-Tests.ps1` pasan sin modificaciones.
- [ ] El control se escribe antes que el historial, nunca al revés.
- [ ] Un fallo del historial no cambia el código de salida, no crea pendientes y no toca el control ni los artefactos.
- [ ] `estado/historialVersiones.md` se crea con su encabezado (LineageId y Creado) y en lotes normales solo crece por append.
- [ ] Un servicio nuevo genera `1.0 — Versión inicial.`
- [ ] Un bump genera una entrada con versión, fecha, objetos cambiados y descripciones.
- [ ] Un parámetro agregado se describe con su tipo y obligatoriedad.
- [ ] Un cambio de Obligatorio se describe como NO→SI o SI→NO; un cambio de Tipo con su valor anterior y nuevo.
- [ ] Un código HTTP nuevo o eliminado se describe con su número.
- [ ] La fila Versión de Definición nunca aparece como cambio.
- [ ] Un reanálisis sin cambio de contenido no agrega nada.
- [ ] Un fallo de generación o publicación no agrega nada y conserva el archivo anterior.
- [ ] Un reinicio del control deja el historial con solo el encabezado nuevo y las entradas `1.0` del lote.
- [ ] Un cambio de `lineageId` reemplaza el historial en vez de mezclar entradas de dos KB.
- [ ] Un control borrado manualmente con historial previo provoca reemplazo, no append con versiones duplicadas.
- [ ] Un lote fallido conserva el historial anterior íntegro.
- [ ] Un objeto eliminado del XPZ queda registrado como `Tipo:guid`.
- [ ] El fast-path no toca el archivo.
- [ ] `Obtener-VersionServicio` devuelve `1.0` sin control previo y `1.<n+1>` con incremento.
- [ ] `Comparar-ControlVersiones` determina fast-path, pendientes, lineage cambiado, objetos modificados y servicios afectados.
- [ ] Una escritura atómica con control inválido lanza y conserva el control previo íntegro.
- [ ] Toda entrada del historial tiene versión consecutiva con la anterior del mismo servicio (sin saltos ni duplicados) y detalle no vacío.
- [ ] Una entrada intermedia eliminada manualmente se detecta por discontinuidad.
- [ ] El append conserva el contenido previo del historial byte a byte.
- [ ] El encabezado del historial conserva `LineageId` y `Creado` y su lineageId coincide con el del control.
- [ ] La versión de cada entrada se deriva del control, nunca del archivo.
- [ ] La última revisión del bloque de un servicio coincide con la revisión del control (sin desincronía en ninguna dirección).
- [ ] Los validadores estáticos de `estado/` verifican control, artefactos publicados, pendientes, dependencias, lineage y fingerprints, con SKIP cuando `estado/` no existe.
- [ ] Los casos nuevos no modifican ningún caso vigente del harness.
- [ ] `README.md` y `AGENTS.md` documentan el archivo y su semántica.

## Decisiones

- **Sí:** Markdown legible por sobre JSONL y por sobre el campo `historico` en el control.
- **Sí:** el control queda intacto; el historial es un artefacto derivado best-effort.
- **Sí:** descripciones desde la comparación de tablas del documento, sin persistir análisis previos.
- **Sí:** solo se registra con bump; sin motivo de versión.
- **Sí:** reinicio limpia y regenera ambos archivos; sin separadores de época.
- **Sí:** `LineageId` y `Creado` en el encabezado como identidad y disparador de reemplazo.
- **Sí:** integridad de SPEC 16 preservada: mismo lock, mismos códigos, misma escritura atómica del control.
- **Sí:** la versión de cada entrada del historial se deriva del control (`Obtener-VersionServicio`), nunca se parsea del archivo.
- **Sí:** validadores estáticos del historial y del control en `Run-Tests.ps1`, con SKIP cuando `estado/` no existe.
- **No:** autoverificación del escritor al hacer append; la integridad del historial se audita en las pruebas, no en el pipeline.
- **No:** cambiar el perfil documental ni los módulos vigentes fuera de `ActualizarServicios.ps1`.
- **No:** sección de historial dentro del documento/PDF.
- **No:** script de consulta del historial.
- **No:** historial retroactivo para servicios existentes.
- **No:** snapshots completos de Markdown o PDF.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Append interrumpido deja una línea parcial | Bloque por lote al final; lo peor es una línea ilegible, y el control permanece intacto. |
| Falla el reemplazo tras escribir el control | Advertencia best-effort; el lineageId del encabezado no coincide y el siguiente lote reemplaza. |
| Mezcla de historial entre KB | El lineageId del encabezado dispara reemplazo automático. |
| Tablas no comparables producen descripciones pobres | Fallback de conteos por sección, siempre informativo. |
| Crecimiento del archivo | Solo entradas por bump, acotadas a los cambios reales. |
| Edición manual o corrupción del historial (salto, duplicado, detalle vacío o pérdida de una entrada) | El escritor deriva las versiones del control y las pruebas validan continuidad, formato, detalle y sincronía con el control; el pipeline no puede originar el defecto. |

## Lo que **no** incluye esta SPEC

- Cambios en el control de versiones, el generador, los PDF, el manifiesto o el lanzador.
- Historial dentro del documento o PDF del servicio.
- Script de consulta del historial.
- Historial retroactivo de versiones previas a la adopción.
- Motivos de cambio por versión.
- Snapshots completos de documentos.
- Soporte multi-cliente.

Cada uno, si llega, irá en su propia SPEC.
