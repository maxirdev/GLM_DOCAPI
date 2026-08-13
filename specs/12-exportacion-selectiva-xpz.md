# SPEC 12 — Exportación selectiva de XPZ complementarios

> **Estado:** Aprobado
> **Depende de:** SPEC 11
> **Fecha:** 2026-08-12
> **Objetivo:** Crear un procedimiento que lea el último reporte de validación, exporte sus objetos faltantes con referencias mínimas y genere complementos XPZ numerados que el validador pueda consumir junto al XPZ principal.

## Por qué existe esta SPEC

El exportador actual produce un XPZ amplio a partir de `Module:APIGLM`, pero el análisis puede detectar procedimientos u objetos que no quedaron incluidos. El validador ya descubre complementos numerados, por lo que falta una herramienta controlada para producirlos desde la receta de exportación sin reemplazar el XPZ principal.

## Alcance

**Incluido:**

- `exportarXPZSelectivo.cmd` como punto de entrada interactivo o `--no-pause`.
- `binary/ExportarXPZSelectivo.ps1` para seleccionar el reporte y orquestar MSBuild.
- `binary/ExportarXPZSelectivo.msbuild` para exportar una lista de objetos GeneXus con `DependencyType="ReferencesTo"`, `ReferenceType="Minimal"` e inclusión de referencias.
- Lectura automática del reporte `Logs/*-validacion-xpz.json` más reciente cuyo `ejecucion.xpz` coincida con el XPZ principal configurado.
- Parámetro opcional para indicar explícitamente un reporte de validación.
- Validación de que el reporte tenga `objectList` o solicitudes exportables antes de iniciar GeneXus.
- Cambio del reporte de `ValidarXPZ.ps1` para conservar selectores inequívocos por tipo y FQN, además del nombre legible actual.
- Resolución de objetos desde `solicitudes[].exportar` y deduplicación antes de exportar.
- Conversión de cada objeto a selector de exportación con tipo GeneXus y FQN completo, preservando módulos homónimos.
- Creación automática de un archivo complementario en el mismo directorio del XPZ principal, con patrón `<base>_1.xpz`, `<base>_2.xpz`, etc.
- No sobrescribir un complemento existente; elegir el siguiente número libre.
- Log independiente con timestamp, reporte de origen, XPZ principal, complemento generado, selectores y resultado de GeneXus.
- Validación estructural del XPZ generado: ZIP legible, un XML y raíz `ExportFile`.
- Compatibilidad con el descubrimiento de complementos que ya realiza `ValidarXPZ.ps1`.

**Fuera de alcance (para futuras SPEC):**

- Fusionar físicamente el XPZ principal y los complementos en un único archivo.
- Ejecutar automáticamente ciclos de validar → exportar hasta alcanzar completitud.
- Corregir en esta SPEC los tipos que siguen sin poder determinarse cuando el objeto ya está exportado.
- Exportar objetos indicados únicamente por advertencias de descripción.
- Modificar la configuración de la Knowledge Base, abrir GeneXus de forma interactiva o desplegar servicios.
- Generar documentos Markdown.

## Modelo de datos

### Selectores en el reporte de validación

El reporte mantendrá compatibilidad con `exportar` como nombres legibles y agregará una colección inequívoca por solicitud:

```json
{
  "servicio": "APIGLM.Cobranzas.WSBPInsIntencionPago",
  "exportar": ["BPInsIntencionPago"],
  "selectores": ["Procedure:Cobranzas.BotonDePago.BPInsIntencionPago"]
}
```

Para SDT u otros tipos se utilizará el prefijo GeneXus correspondiente y el `fullyQualifiedName` literal del XPZ, por ejemplo `SDT:Modulo.NombreSDT`. Si una versión del exportador requiere otra sintaxis soportada por GeneXus, el mapeo quedará centralizado en `ExportarXPZSelectivo.ps1` y se registrará en el log.

### Parámetros del procedimiento

```text
exportarXPZSelectivo.cmd [--reporte <ruta-json>] [--no-pause]
```

Si no se informa `--reporte`, se selecciona el reporte más reciente compatible con el XPZ definido en `configuracion.json`. La compatibilidad se determina por `ejecucion.xpz`, no solo por la fecha del archivo.

### Artefactos generados

- XPZ complementario: `xpz/<base-principal>_<N>.xpz`.
- Log de ejecución: `Logs/exportarXPZSelectivo_<timestamp>.log`.

El complemento conserva su relación con el principal por ubicación y nomenclatura. No se modifica `configuracion.json`; `ValidarXPZ.ps1` lo descubrirá automáticamente en la ejecución siguiente.

## Plan de implementación

1. Crear `binary/ExportarXPZSelectivo.msbuild` con propiedades para `KBPath`, `XPZFile` y `ObjectList`, y una tarea `ExportarObjetosSelectivos` que abra la KB, exporte con referencias mínimas y cierre la KB incluso ante error.
2. Crear `binary/ExportarXPZSelectivo.ps1` con validación de rutas, carga de configuración y función para localizar el reporte más reciente compatible o aceptar `-ReportePath` explícito.
3. Implementar en el script la lectura de `selectores` y la validación de que cada selector tenga tipo y FQN; usar `objectList` como compatibilidad de respaldo solo cuando el reporte sea antiguo y no existan selectores inequívocos.
4. Implementar la selección del siguiente complemento libre mediante comprobación de rutas concretas `<base>_<N>.xpz`, comenzando en 1, sin borrar ni sobrescribir archivos existentes.
5. Implementar el lanzamiento de MSBuild con el mismo control de procesos, fases, log y validación ZIP/XML utilizado por `ExportarXPZProgreso.ps1`.
6. Ajustar `binary/ValidarXPZ.ps1` y `Write-ReporteValidacion` para emitir `selectores` con tipo y FQN, manteniendo `exportar` y `objectList` para compatibilidad.
7. Crear `exportarXPZSelectivo.cmd` con las rutas de GeneXus/KB existentes, mensajes de salida, códigos de retorno y opción `--no-pause`.
8. Actualizar `README.md` y la documentación operativa para explicar el flujo: ejecutar validación, exportar complemento, conservar todos los XPZ y volver a validar.
9. Verificar manualmente el flujo con el reporte `Logs/20260812-085704-validacion-xpz.json`: generar un complemento, confirmar su estructura, comprobar que no se sobrescribe el siguiente archivo y ejecutar otra validación para verificar que el complemento sea descubierto.

## Criterios de aceptación

- [ ] `exportarXPZSelectivo.cmd --no-pause` se ejecuta en PowerShell 5.1/MSBuild de 32 bits sin módulos externos.
- [ ] Sin `--reporte`, se usa el reporte más reciente cuyo `ejecucion.xpz` coincide con `configuracion.json`.
- [ ] Con `--reporte`, se usa exactamente el archivo indicado y se rechaza si no es JSON válido o no corresponde al XPZ configurado.
- [ ] Un reporte sin objetos pendientes termina con mensaje claro y no inicia GeneXus.
- [ ] Los selectores exportados incluyen tipo GeneXus y FQN completo, sin perder módulos homónimos.
- [ ] La exportación usa `ReferencesTo`, `Minimal`, `IncludeChildren="true"` y conserva un XML raíz `ExportFile`.
- [ ] El primer complemento se genera como `<base>_1.xpz` y las ejecuciones posteriores eligen el siguiente número libre.
- [ ] Ningún complemento existente se sobrescribe o elimina.
- [ ] El XPZ complementario queda en el mismo directorio del XPZ principal.
- [ ] El log registra reporte de origen, objetos, selector, ruta de salida y resultado.
- [ ] Un XPZ inválido o una ejecución fallida de GeneXus devuelve código distinto de cero y deja el principal intacto.
- [ ] `ValidarXPZ.ps1` descubre automáticamente el complemento generado sin cambios manuales en `configuracion.json`.
- [ ] Al combinar el XPZ principal y el complemento, el validador deja de marcar como ausentes los objetos efectivamente exportados.
- [ ] El reporte conserva `exportar` y `objectList` para compatibilidad con reportes y herramientas existentes.
- [ ] La documentación explica que se deben conservar el XPZ principal y todos sus complementos para el análisis multi-XPZ.

## Decisiones

- **Sí:** analizar el reporte de validación más reciente compatible con el XPZ configurado; evita exportar una receta de otra versión.
- **Sí:** aceptar un reporte explícito; permite reproducibilidad y automatización.
- **Sí:** guardar tipo y FQN completo; evita colisiones entre objetos homónimos.
- **Sí:** exportar referencias mínimas; permite que el complemento contenga el contexto necesario para analizar el objeto.
- **Sí:** un complemento por ejecución, numerado desde `_1`; hace visible cada iteración y evita ciclos automáticos difíciles de revisar.
- **Sí:** mantener el XPZ principal intacto y acumular complementos; el validador ya implementa la cascada de lectura.
- **No:** fusionar XPZ; la combinación lógica queda a cargo del índice multi-XPZ de SPEC 11.
- **No:** sobrescribir `_1.xpz` ni cualquier complemento existente; se conserva evidencia de cada exportación.
- **No:** inferir objetos desde nombres ambiguos del `objectList` cuando falten selectores inequívocos en un reporte nuevo; se debe detener y pedir regenerar la validación.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| GeneXus no acepta FQN con el prefijo esperado en `Objects` | Centralizar el mapeo de selector, validar el log de MSBuild y documentar la sintaxis confirmada por la KB. |
| El reporte más reciente pertenece a otro XPZ | Comparar `ejecucion.xpz` con la ruta configurada y rechazar discrepancias. |
| Un complemento contiene una versión anterior de un objeto | El validador conserva la primera ocurrencia de la cascada; el log registra el orden y el usuario puede revisar o renombrar los archivos. |
| La receta contiene nombres antiguos sin `selectores` | Mantener respaldo controlado para reportes `schemaVersion` anteriores y advertir que puede haber ambigüedad. |
| La exportación requiere más iteraciones | El flujo conserva `_1`, `_2`, etc.; después de cada ejecución se vuelve a validar y se genera otro complemento si corresponde. |

## Lo que **no** incluye esta SPEC

- XPZ consolidado físico.
- Iteración automática validar/exportar.
- Corrección de tipos no resolubles dentro de objetos ya exportados.
- Cambios en reglas editoriales o generación de documentos.
- Despliegue o ejecución de los servicios.

