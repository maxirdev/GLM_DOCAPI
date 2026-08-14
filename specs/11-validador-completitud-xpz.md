# SPEC 11 — Validador de completitud multi-XPZ

> **Estado:** Implementado
> **Depende de:** SPEC 03, SPEC 06
> **Fecha:** 2026-08-11
> **Nota:** Actualizado 2026-08-11 — el reporte pasó de `completos`/`incompletos`/`excluidos` a la receta de exportación (`solicitudes` + `objectList`) con nombres reales de objetos.
> **Nota (implementación):** Actualizado con la implementación de `ValidarXPZ.ps1` — el bucle por campo usa 7 estrategias (no 10), `Obtener-NodosEvidencia` se acota a profundidad 3, los objetos faltantes se extraen por regex de los mensajes de excepción y el `IndiceUnificado` lleva propiedades internas adicionales.
> **Objetivo:** Crear un script que valide la completitud de uno o varios XPZ complementarios contra el inventario de endpoints, produciendo un reporte que identifica los objetos GeneXus (procedures y SDT) a solicitar para exportar: tanto los referenciados que no están en el XPZ como los SDT padres de campos cuyo tipo de dominio no puede resolverse.

## Alcance

**Incluido:**

- `binary/ValidarXPZ.ps1` como script independiente invocable desde `GenerarDocumentacion.cmd`.
- Índice unificado multi-XPZ con resolución en cascada (qué objeto viene de qué XPZ; primera ocurrencia gana).
- Convención de nomenclatura: `<nombre>.xpz` (principal) + `<nombre>_1.xpz`, `<nombre>_2.xpz`, … (complementos) en el mismo directorio.
- Auto-descubrimiento de complementos por patrón de archivo.
- Validación de todos los servicios del inventario (excepto los de `serviciosIgnorados`, que solo se informan en consola).
- Aplicación de las 7 estrategias de resolución tipográfica en el bucle por campo (`Resolver-TipoPorLectura`, `Resolver-TipoPorFlujoParametros`, `Resolver-TipoMiembroSdtGlobal`, `Resolver-TipoPorAsignacion`, `Resolver-TipoVariable`, `Resolver-TipoAtributo`, `Resolver-TipoMiembro`), más `Resolver-EntradaGetTipos` para tipar los parámetros GET. `Resolver-TipoRhs`, `Resolver-Campo` y `Resolver-EntradaGetTipos` no se invocan dentro del bucle por campo.
- Clasificación binaria por servicio: `esPendiente = true` cuando hay al menos un objeto a exportar, `false` en caso contrario.
- Reporte JSON `Logs/<timestamp>-validacion-xpz.json` con `ejecucion` (conteos), `solicitudes` (servicios con los objetos a exportar) y `objectList` (nombres reales separados por coma).
- Código de salida 0 si ningún servicio requiere exportación adicional, 1 si hay al menos uno.

**Fuera de alcance:**

- Generación de documentos `.md`.
- Producción de un XPZ consolidado (merge físico de los parciales).
- Comparación con versiones anteriores del XPZ (cubierto por SPEC 08).
- Validación de campos de descripción (solo se validan tipos; las descripciones no bloquean la generación de documentos).
- Códigos de error HTTP, obligatoriedad, método ambiguo ni endpoint publicado.
- Reglas editoriales ni plantilla de documento.
- Escritura en carpetas productivas.
- Commit en git.

## Modelo de datos

### Entrada

El validador recibe implícitamente:

- `configuracion.json` → `xpz` (ruta del XPZ principal).
- `configuracion.json` → `serviciosIgnorados` (FQN a excluir).
- `documentacion/Endpoints/assets/endpoints.json` → inventario de endpoints.
- Archivos `.xpz` en el directorio del XPZ principal que coincidan con el patrón `<nombreBase>_<N>.xpz`.

### Salida

`Logs/<timestamp>-validacion-xpz.json`:

```json
{
  "schemaVersion": 2,
  "ejecucion": {
    "xpz": "xpz/SEGUROS_COMERCIAL_APIGLM_v1_0.xpz",
    "inicio": "2026-08-11T20:00:00",
    "fin": "2026-08-11T20:00:45",
    "total": 209,
    "ok": 195,
    "pendientes": 14
  },
  "solicitudes": [
    {
      "servicio": "APIGLM.Cobranzas.WSBPCrearNovedadPago",
      "exportar": ["BPCrearNovedadPago"]
    },
    {
      "servicio": "APIGLM.Cotizacion.WSObtenerCotizacion",
      "exportar": ["EntServicioCotizacionRiesgoAPE", "EntServicioCotizacionRiesgoVIC"]
    },
    {
      "servicio": "APIGLM.Comun.WSObtenerRiesgo",
      "exportar": ["SDTCobertura"]
    }
  ],
  "objectList": "BPCrearNovedadPago,EntServicioCotizacionRiesgoAPE,EntServicioCotizacionRiesgoVIC,SDTCobertura"
}
```

Convenciones del modelo:

- El objetivo del reporte es la **receta de exportación**: lista qué objetos solicitar para que la generación de documentación no falle. Solo aparecen servicios con al menos un objeto a exportar.
- `solicitudes[].servicio` es el FQN del endpoint (wrapper) que necesita contexto adicional.
- `solicitudes[].exportar` son los **nombres reales** de los objetos a exportar (último segmento del FQN, sin prefijo de tipo ni módulo). Ejemplos: `BPCrearNovedadPago`, `EntServicioCotizacionRiesgoAPE`, `SDTCobertura`.
- Un objeto entra en `exportar` por una de estas dos vías:
  - **Referencia no exportada**: un Procedure o SDT al que apunta el servicio no está en el XPZ (wrapper, programa principal, SDT de entrada/salida o SDT anidado). Se agrega su nombre.
  - **Campo sin tipo resoluble**: tras aplicar las estrategias de resolución, un campo mantiene `PENDIENTE DE CONFIRMACIÓN`. Se solicita el SDT padre que contiene al campo (`$fila.SdtFqn`) para ampliar el contexto. Si no hay SDT padre (parámetro plano de GET), se solicita el programa principal.
- `objectList` es la unión de todos los objetos de `solicitudes`, deduplicada, con nombres reales separados por coma. Es el valor listo para un comando de exportación de GeneXus.
- `ejecucion.ok` = servicios sin ningún objeto a exportar; `ejecucion.pendientes` = servicios con al menos uno. No se listan los servicios `ok` (no requieren acción).
- Los servicios de `serviciosIgnorados` no se validan ni aparecen en el reporte; solo se informan en la consola.

## Plan de implementación

1. Crear `binary/ValidarXPZ.ps1` con el esqueleto: bloque `param()`, carga de `CargarConfiguracion.ps1`, descubrimiento de complementos y bucle principal vacío.
2. Implementar `Descubrir-XPZComplementarios`: dado el nombre del XPZ principal (`SEGUROS_COMERCIAL_APIGLM_v1_0.xpz`), buscar en el mismo directorio archivos que coincidan con `<nombreBase>_<N>.xpz` y ordenarlos numéricamente por `N`. El patrón regex es `^<nombreBase>_(\d+)\.xpz$`.
3. Implementar `Construir-IndiceMultiXPZ`: abrir cada XPZ (principal y complementarios), construir su índice individual con `Construir-Indices` de `AnalizarServicio.ps1`, y fusionarlos en un índice unificado. Cada entrada del índice unificado registra el XPZ de origen (`IndiceUnificado.Origen['FQN'] = 'SEGUROS_COMERCIAL_APIGLM_v1_0.xpz'`). La fusión respeta cascada: si un FQN ya existe, se conserva el del primer XPZ. Además del índice fusionado, el objeto `IndiceUnificado` incorpora propiedades internas (no serializadas en el reporte): `XmlPrincipal` (XML del XPZ principal, reabierto aparte), `XpzPrincipalRelativo` y `XpzComplementariosRelativos` (rutas relativas al repositorio con separadores `/`).
4. Implementar `Validar-CompletitudServicio`: para un endpoint dado, ejecutar la cadena de validación:
   - Buscar wrapper en índice unificado; si no está, marcar faltante.
   - Obtener delegación (`Obtener-DelegacionUnica`) → buscar programa principal → si no está, marcar faltante. Cuando la delegación falla porque el programa principal no está exportado, el nombre del objeto faltante se extrae del mensaje de la excepción con la expresión `programa principal ([^\s]+)`.
   - Si POST: resolver SDT de entrada (`Resolver-EntradaPost`) → expandir (`Expandir-EstructuraSdt`) → marcar SDT anidados faltantes. Si la excepción indica `no está exportada en el XPZ`, se extrae el nombre del SDT con la expresión `SDT\s+([^\s]+)`.
   - Si GET: resolver parámetros (`Resolver-EntradaGetTipos`) y aplicar las estrategias a cada fila pendiente; en este flujo `$variableSdt` se pasa vacío, por lo que las dos primeras estrategias (lectura y flujo de parámetros) se omiten.
   - Resolver SDT de salida (`Resolver-Salida`) → expandir → marcar faltantes. Si la salida no se resuelve por SDT no exportado, marcarlo con el mismo patrón `SDT\s+([^\s]+)`.
   - Los nodos de evidencia se obtienen con `Obtener-NodosEvidencia` usando `-ProfundidadMaxima 3` (el generador usa la profundidad máxima 5; el validador la acota a 3 para agilizar el barrido de todo el inventario).
   - Para cada campo con tipo PENDIENTE: aplicar las 7 estrategias del bucle por campo; si ninguna resuelve, marcar el SDT padre (`$fila.SdtFqn`) o, si no, el programa principal.
   - El nombre real de cada objeto se obtiene con `Obtener-NombreObjeto` (último segmento del FQN, sin prefijo de tipo ni módulo); todos los faltantes se guardan como `[string]`.
   - Las funciones de resolución se toman mediante dot-source de `AnalizarServicio.ps1`.
5. Implementar `Write-ReporteValidacion`: serializar los resultados en el JSON con `ejecucion`, `solicitudes` y `objectList`.
6. Integrar en `GenerarDocumentacion.cmd`: agregar paso que invoque `ValidarXPZ.ps1` después del inventario. Si el validador devuelve código 1, mostrar advertencia pero continuar con el visor (no bloquear).
7. Verificar con el XPZ actual: los servicios que el pipeline reporta como ERROR (programa principal o SDT no exportado) y como WARNING (campo sin tipo) deben aparecer en `solicitudes` con los objetos a exportar, y el `objectList` debe tener los nombres reales separados por coma.

## Criterios de aceptación

- [ ] `binary/ValidarXPZ.ps1` se ejecuta en PowerShell 5.1 sin módulos externos.
- [ ] Descubre automáticamente los complementos `<nombreBase>_<N>.xpz` en el mismo directorio del XPZ principal.
- [ ] El índice unificado prioriza el primer XPZ donde aparece cada objeto (cascada).
- [ ] Un objeto referenciado (wrapper, programa principal, SDT de entrada/salida o SDT anidado) que no está en el XPZ se agrega a `exportar` con su nombre real.
- [ ] Un campo con tipo `PENDIENTE DE CONFIRMACIÓN` tras aplicar todas las estrategias agrega el SDT padre (o el programa principal si no hay SDT) a `exportar`.
- [ ] `solicitudes` solo contiene servicios con al menos un objeto a exportar.
- [ ] `exportar` usa el nombre real (último segmento del FQN), sin prefijo `Procedure:`/`SDT:` ni módulo.
- [ ] `objectList` es la unión deduplicada de todos los objetos, con nombres reales separados por coma.
- [ ] Los servicios en `serviciosIgnorados` se informan solo en consola y no aparecen en el reporte.
- [ ] El script devuelve 0 cuando ningún servicio requiere exportación adicional.
- [ ] El script devuelve 1 cuando al menos un servicio requiere exportación adicional.
- [ ] `GenerarDocumentacion.cmd` ejecuta el validador como paso adicional y continúa aunque haya pendientes.
- [ ] Sin complementos (solo XPZ principal), el validador funciona idéntico al caso de XPZ único.
- [ ] El reporte se escribe en `Logs/<timestamp>-validacion-xpz.json`.
- [ ] No se escriben archivos en carpetas productivas (`documentacion/servicios/`).
- [ ] Las 7 estrategias de resolución tipográfica del bucle por campo se aplican en el orden definido por `AnalizarServicio.ps1`, y `Resolver-EntradaGetTipos` se usa para tipar los parámetros GET.
- [ ] Los campos con tipo `PENDIENTE DE CONFIRMACIÓN` pero con descripción faltante (no tipo) no generan solicitud de exportación (solo el tipo determina la solicitud).

## Decisiones

- **Sí:** índice unificado multi-XPZ con resolución en cascada (primera ocurrencia gana).
- **Sí:** convención de nomenclatura `<nombreBase>_<N>.xpz` para complementos, auto-descubiertos en el mismo directorio del XPZ principal.
- **Sí:** dot-source de `AnalizarServicio.ps1` para reutilizar las 7 estrategias de resolución tipográfica del bucle por campo (más `Resolver-EntradaGetTipos` para los parámetros GET).
- **Sí:** `GenerarDocumentacion.cmd` ejecuta el validador como paso no bloqueante (advierte pero no detiene el visor).
- **Sí:** JSON como único formato de salida, consumible por procesos automáticos de re-exportación desde GeneXus.
- **Sí:** el reporte solo lista lo accionable: objetos a exportar. No lista los servicios `ok` ni los `serviciosIgnorados`.
- **Sí:** los objetos a exportar usan el nombre real (último segmento del FQN), sin prefijo de tipo, para usarse directo en el comando de exportación.
- **Sí:** un campo con tipo no resoluble solicita el SDT padre; si no hay SDT (parámetro plano de GET), solicita el programa principal.
- **Sí:** solo tipos (no descripciones) generan solicitud de exportación.
- **No:** `configuracion.json` no lista los XPZ complementarios (son dinámicos, se descubren por patrón de archivo en el mismo directorio).
- **No:** no se genera un XPZ consolidado físico.
- **No:** no se comparan versiones de XPZ (SPEC 08).
- **No:** no se validan códigos HTTP, obligatoriedad ni método HTTP (son errores de diseño, no de datos).
- **No:** no se generan documentos `.md`.
- **No:** el reporte no incluye trazabilidad de XPZ de origen por objeto ni detalle de `buscadoEn`/`motivo`.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Dos XPZ exportan el mismo objeto con contenido distinto | La cascada usa el primero. Si el primero está desactualizado, el usuario debe renombrar o reordenar los archivos. |
| Un GUID existe en varios XPZ con distinto FQN | El índice unificado indexa por FQN y por GUID; la cascada aplica al FQN. Si hay colisión de GUID, se usa el del primer XPZ para ese FQN. |
| El índice unificado crece con muchos XPZ | Memoizar `Construir-IndiceMultiXPZ`. La memoria de un XPZ típico son ~50 MB de XML; 5 XPZ ≈ 250 MB, manejable en PS 5.1. |
| Nombres de complementos que no siguen la convención `<nombreBase>_<N>.xpz` quedan sin descubrir | Documentar la convención en el `Write-Host` de inicio del validador. Si un complemento no se descubre, el usuario debe renombrarlo. |
| El validador lanza una excepción no controlada | El catch top-level de `ValidarXPZ.ps1` escribe el error en consola y devuelve código 1. `GenerarDocumentacion.cmd` continúa. |
| El SDT padre de un campo sin tipo ya está en el XPZ (tipo no resoluble por otra causa) | La solicitud de exportación es informativa: al re-exportar se confirma si el tipo aparece; si no, el campo sigue como PENDIENTE en la generación. |

## Lo que **no** incluye esta spec

- Producción de un XPZ consolidado físico.
- Comparación con versiones anteriores del XPZ (SPEC 08).
- Validación de descripciones de campos.
- Códigos de error HTTP, obligatoriedad o método HTTP.
- Generación de documentos `.md`.
- Commit en git.
