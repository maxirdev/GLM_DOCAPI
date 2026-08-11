# SPEC 02 — Generador de documentación de servicios APIGLM

> **Estado:** Implementado
> **Depende de:** —
> **Fecha:** 2026-08-08
> **Objetivo:** Crear un generador en PowerShell 5.1 (sin dependencias) que, a partir del XPZ y del inventario `endpoints.json`, produzca la documentación pública de un servicio APIGLM siguiendo `analisisXPZ.md` → `reglasEditoriales.md` → `templateDoc.md`, con un informe de revisión para los juicios no automatizables.

## Alcance

**Incluido:**

- Estructura de carpetas nueva `documentacion/Generador/` con la misma lógica que `documentacion/Endpoints/` (`binary/` con scripts y `.cmd`, `assets/` con salidas ignoradas).
- Archivo de configuración JSON en la raíz del proyecto: `configuracion.json`, para datos no confirmables desde el XPZ (packagename del endpoint publicado, rutas).
- Orquestador + módulos separados en PowerShell 5.1 usando solo capacidades nativas (`System.IO.Compression` y `[xml]`).
- Selección interactiva del servicio desde la lista de `documentacion/Endpoints/assets/endpoints.json` (los 135 endpoints), por número.
- Generación de un documento por invocación en `documentacion/servicios/<wrapper en minúsculas>.md`; si el archivo ya existe, aborta sin sobrescribir.
- Informe de revisión `documentacion/Generador/assets/apiglm-doc-review.json` con los ítems que requieren confirmación humana (obligatoriedad no resuelta, descripciones no derivables), cada uno con su evidencia requerida y un ejemplo.
- Seguir mecánicamente las pautas de los tres `.md` normativos; ante evidencia insuficiente, registrar `PENDIENTE DE CONFIRMACIÓN: <dato>. Evidencia requerida: <fuente>.` tal como define `analisisXPZ.md`.

**Excluido (para specs futuros):**

- Generar el inventario `endpoints.json`/`endpoints.md` (ya lo hace `GenerarListaEndpoints.ps1`).
- Documentación en lote de los 135 endpoints.
- Interfaz web o visor (análogo a `Endpoints/web/`).
- Commit en git.
- Modificación de `documentacion/analisisXPZ.md`, `reglasEditoriales.md`, `templateDoc.md` ni de los scripts de `documentacion/Endpoints/`.
- Corrección de referencias a `LPS_COM_v01.xpz` ni de la convención `Endpoint/` del README.

## Modelo de datos

**Configuración raíz `configuracion.json`:**

```json
{
  "xpz": "xpz/LPS_COM.xpz",
  "packagename": "ar.com.glmsa.seguros.comercial."
}
```

Las rutas fijas del repositorio (`endpoints.json`, `documentacion/servicios/`, `apiglm-doc-review.json`) están hardcodeadas en los scripts y no son configurables.

`packagename` es la constante del prefijo del endpoint publicado (por ejemplo `ar.com.glmsa.seguros.comercial.` en LPS_COM.xpz o `glmsuit.comercial.` en versiones más nuevas como Trunk.xpz). No se confirma desde el XPZ; se define manualmente en `configuracion.json` según el XPZ que se documenta. El endpoint se compone como `packagename` + ruta del módulo en minúsculas + `a` + procedimiento en minúsculas.

**Documentación técnica en memoria (objeto PowerShell, única transferencia al editor):**

```
FqWrapper, ProgramaPrincipal, MetodoHttp ("GET"|"POST"),
EndpointPublicado (o pendiente),
Entrada   = [ { Orden, Campo, Tipo, Obligatorio, Descripcion } ],
Estructuras = [ { RutaJson, Hijos = [ { Campo, Tipo, Obligatorio, Descripcion } ] } ],
SalidaColeccion (bool), Salida = [ { Campo, Tipo, Descripcion } ],
Errores   = [ { Codigo, Condicion, Mensaje } ],
Pendientes = [ "PENDIENTE DE CONFIRMACIÓN: ..." ]
```

**Informe de revisión `apiglm-doc-review.json`:**

```json
{
  "servicio": "APIGLM.Emision.WSObtenerTotalesSolicitud",
  "items": [
    { "campo": "…", "asunto": "obligatoriedad|descripcion|endpoint|tipo",
      "evidenciaRequerida": "…", "ejemplo": "…",
      "pendiente": "PENDIENTE DE CONFIRMACIÓN: …" }
  ]
}
```

## Plan de implementación

1. Crear `configuracion.json` en la raíz con el esquema anterior y las carpetas `documentacion/Generador/binary/` y `documentacion/Generador/assets/`. Agregar a `.gitignore` las salidas del generador (`documentacion/Generador/assets/`).
2. Crear `documentacion/Generador/binary/AnalizarServicio.ps1` con las funciones de acceso: `Abrir-XPZ` (ZIP de solo lectura → `LPS_COM_v01.xml` con raíz `ExportFile`) y `Obtener-Objeto` (localización por `@fullyQualifiedName`).
3. En el mismo módulo, implementar la confirmación del wrapper según `analisisXPZ.md` secciones 1: tipo Procedure (catálogo), `IsMain=True`, `CALL_PROTOCOL=HTTP`, y detección de la delegación única `(in:&APIGLMRequestIn, out:&APIGLMResponse)` confirmada por la regla `parm(...)` del programa principal. Si no hay delegación única, detener sin generar.
4. Implementar la resolución de método y entrada (sección 2): GET por posiciones de `QueryParams` o POST por `FromJson` sobre `Body`; en GET conservar orden/posiciones exactas; en POST resolver el SDT destino completo conservando nombres JSON.
5. Implementar la tipografía canónica y la expansión de estructuras (sección 3): `Integer`, `Decimal`, `String`, `Boolean`, `Date (YYYY-MM-DD)`, `DateTime`, `Base64`, `Estructura <ruta>`, `Colección de Estructura <ruta>`, `Colección JSON`; tablas independientes por ruta JSON.
6. Implementar la columna `Obligatorio` con el criterio de la sección 4 (tres evidencias, limitado al programa principal sin recorrer procedimientos en cascada). El campo se marca `SI` si su nombre aparece referenciado en el Source del programa principal (where, asignación, parámetro, condición); `NO` si no aparece. Las comprobaciones explícitas de campo vacío/inválido también producen `SI`.
7. Implementar salida y errores (secciones 5 y 6): payload de `GenerarAPIGLMResponse` con 200, y códigos ≠ 200 únicamente del programa principal; `HttpCode.BadRequest→400`, `NotFound→404`, `MethodNotAllowed→405`.
8. Implementar `Resolver-Endpoint` (sección 7): nombre en minúsculas = `packagename` + ruta del módulo en minúsculas + `a` + procedimiento.
9. Crear `documentacion/Generador/binary/RedactarDocumento.ps1` (`Redactar-Documento`): renderiza el markdown según `templateDoc.md`, conservando bloques canónicos, la variante GET o POST única y el JSON común; reemplaza los demás marcadores con datos o pendientes.
10. Crear `documentacion/Generador/binary/EscribirSalidas.ps1` (`Escribir-Salidas`): escribe el documento en `documentacion/servicios/<wrapper>.md` con UTF-8 sin BOM y finales LF; si existe, aborta sin sobrescribir; escribe `apiglm-doc-review.json`.
11. Crear `documentacion/Generador/binary/GenerarDocumento.ps1` (orquestador): carga la config, lee `endpoints.json`, muestra la lista numerada, pide el número por `Read-Host`, y encadena análisis → redacción → salida.
12. Crear `documentacion/Generador/binary/ObtenerDocumento.cmd` (análogo a `ObtenerEndpoints.cmd`) y el orquestador raíz `GenerarDocumentoServicio.cmd` (análogo a `GenerarDocumentacion.cmd`).
13. Verificar contra las tres listas de control normativas usando un servicio aún no documentado.

## Criterios de aceptación

- [ ] `configuracion.json` existe en la raíz con las claves `xpz` y `packagename`; las rutas fijas están hardcodeadas en los scripts.
- [ ] `GenerarDocumentoServicio.cmd` muestra la lista numerada de `endpoints.json` y seleccionar un número válido genera el documento.
- [ ] Elegir un servicio no documentado produce `documentacion/servicios/<wrapper>.md`.
- [ ] Elegir un servicio ya documentado aborta sin modificar el archivo existente.
- [ ] El documento respeta el orden exacto de `templateDoc.md` y conserva solo la variante GET o POST aplicable.
- [ ] Los tipos usan exclusivamente la tipografía canónica.
- [ ] La columna `Obligatorio` contiene solo `SI` o `NO`.
- [ ] `Errores específicos` contiene solo rechazos explícitos del programa principal o la indicación estándar; el JSON común permanece debajo.
- [ ] Autenticación y tabla de Generalidades conservadas literalmente.
- [ ] Se genera `apiglm-doc-review.json` con cada ítem no confirmado, su evidencia requerida y un ejemplo.
- [ ] Los scripts usan solo PowerShell 5.1 nativo (sin módulos externos, sin ejecutables de terceros).
- [ ] Los archivos generados son UTF-8 sin BOM con finales LF.
- [ ] No se creó commit en git.

## Decisiones

- **Sí:** PowerShell 5.1 nativo. Ya es el shell del entorno; `System.IO.Compression` y `[xml]` cubren ZIP+XML sin dependencias.
- **Sí:** Entrada directa del XPZ. Es la fuente de verdad de `AGENTS.md`; el script no depende de una documentación intermedia persistente.
- **Sí:** Un documento por invocación con selección interactiva desde `endpoints.json`. Control editorial por servicio y coherencia con SPEC 01.
- **Sí:** Salida en `documentacion/servicios/<wrapper>.md` sin sobrescribir. Los pendientes se completan a mano y una sobrescritura los borraría.
- **Sí:** Config JSON en la raíz con `packagename`. El XPZ no confirma el prefijo del package publicado; la constante se define en `configuracion.json` según el XPZ que se documenta (LPS_COM.xpz → `ar.com.glmsa.seguros.comercial.`, Trunk.xpz → `glmsuit.comercial.`).
- **Sí:** Informe de revisión aparte además de los `PENDIENTE DE CONFIRMACIÓN` en el documento, para localizar los juicios humanos sin leer todo el doc.
- **Sí:** Estructura orquestador + módulos (analizar/redactar/escribir), espejando `documentacion/Endpoints/binary/`.
- **Sí:** No crear commit; lo decide el usuario.
- **No:** Documentación en lote de los 135 endpoints (spec futura).
- **No:** Generar o corregir el inventario `endpoints.json`/`endpoints.md` ni el visor web.
- **No:** Reescribir los `.md` normativos ni los scripts existentes de `Endpoints/`.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| La sección 4 (Obligatorio) se determina mecánicamente por presencia del campo en el Source del programa principal, pero las descripciones funcionales no son derivables del XML | `Obligatorio` queda `SI`/`NO` automático; las descripciones se marcan `PENDIENTE DE CONFIRMACIÓN` en el documento y como ítem con ejemplo en `apiglm-doc-review.json`. |
| `endpoints.json` desactualizado frente al XPZ (el control espera 135) | El generador usa `endpoints.json` tal cual; no forzar ni recalcular el inventario. Si falta, abortar indicando que se ejecute `GenerarDocumentacion.cmd`. |
| `Out-File`/`Set-Content` de PowerShell 5.1 escriben BOM | Usar `[System.IO.File]::WriteAllText` con `UTF8Encoding($false)` y normalizar finales a LF. |
| El packagename del endpoint publicado no se confirma desde el XPZ | Constante única en `configuracion.json`, definida según el XPZ; nunca construir el prefijo por analogía. |
| Sobrescritura accidental de un documento editado a mano | Regla de no-sobrescribir; el usuario borra el archivo si quiere regenerarlo. |

## Lo que **no** incluye esta spec

- Generación del inventario ni del visor web de endpoints.
- Documentación en lote.
- Commit en git.
- Cambios en los documentos normativos ni en los scripts de `Endpoints/`.
