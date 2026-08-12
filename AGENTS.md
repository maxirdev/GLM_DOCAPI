# AGENTS.md

## Propósito del repositorio

Repositorio de documentación y scripts PowerShell (sin build ni tests automatizados). Produce documentos técnicos de los servicios HTTP de APIGLM a partir del export GeneXus configurado. Todo el contenido se escribe en **español**.

## Fuentes de evidencia (solo lectura, no editar)

- `xpz/` — archivo `.xpz` configurado en `configuracion.json` (p. ej. `trunk.xpz`, `LPS_COM.xpz`). Es un ZIP que contiene un único XML con raíz `ExportFile`. Es la fuente de verdad: Source, Rules, variables, SDT, dominios, atributos y asignaciones.
- `GeneXus-XPZ-Skills-main/` — repositorio auxiliar vendido. Contiene scripts y catálogos (p. ej. `scripts/gx-object-type-catalog.json`, para confirmar tipos de objeto).

Ambas carpetas están en `.gitignore`: son referencias locales, no parte del producto.

## Estructura de trabajo

En la raíz del repo:

- `binary/` — scripts del generador: `GenerarDocumento.ps1` (orquestador), `AnalizarServicio.ps1`, `RedactarDocumento.ps1`, `EscribirSalidas.ps1`, `CargarConfiguracion.ps1`, `DiagnosticoIA.ps1` y `ObtenerDocumento.cmd`.
- `exportarXPZ.cmd`, `binary/ExportarXPZProgreso.ps1` y `binary/ExportarXPZ.msbuild` — utilidad opcional para exportar `Module:APIGLM` desde la KB local y generar un XPZ fechado.
- `Logs/*-diagnostico-ia.json` — diagnóstico estructurado de excepciones con fase, ruta relativa, sentencia y stack trace. Se genera solo ante errores; revisar primero el más reciente al investigar fallos del pipeline.

En `documentacion/` (commiteada):

- `analisisXPZ.md` — fuente normativa #1: cómo construir la documentación técnica desde el XPZ.
- `reglasEditoriales.md` — fuente normativa #2: presentación del documento final.
- `templateDoc.md` — fuente normativa #3: plantilla obligatoria de cada servicio.
- `Endpoints/assets/analisisEndpoint.md` — cómo reproducir el inventario de endpoints desde `APIGLM.APIGLMMain`.
- `Endpoints/assets/endpoints.md` — inventario esperado de endpoints (aún no existe en el repo).
- `Endpoints/assets/` — salidas del inventario (`endpoints.json`, `endpoints.md`, ambas ignoradas).
- `Endpoints/binary/` — scripts: `GenerarListaEndpoints.ps1` (inventario), `GenerarVistaHTML.ps1` (visor) y `ObtenerEndpoints.cmd`.
- `Endpoints/web/` — visor estático: `APIServicios.html` (generado e ignorado), `style.css`, `app.js`.
- `GenerarDocumentacion.cmd` (raíz del repo) — orquestador que regenera inventario y visor.
- `configuracion.json` (raíz del repo) — configuración operativa: ruta del XPZ, rutas de salida, `packagename` constante del endpoint publicado por XPZ y `serviciosIgnorados` (lista de FQN referenciados que no se documentan).
- `servicios/` — documentos por servicio (p. ej. `wsobtenertotalessolicitud.md`).

Orden obligatorio por servicio: analisisXPZ → reglasEditoriales → templateDoc. No recalcular decisiones durante la redacción.

## Reglas no obvias

- El XPZ se abre como ZIP de solo lectura; el XML interno tiene raíz `ExportFile`.
- Inventario: solo llamadas `WS...` activas en `APIGLMMain` (una línea que comienza con `//` es una llamada inactiva). Confirmar que el objeto sea Procedure, `IsMain=True` y `CALL_PROTOCOL=HTTP`. Conservar el `fullyQualifiedName` literal, p. ej. `APIGLM.Cotizacion.WSObtenerDatosProductor`.
- Endpoint publicado ≠ nombre GeneXus: se documenta el nombre completo en minúsculas (package + módulo + procedimiento) y, para procedures HTTP `Main`, se antepone `a` (`wslistarsolicitudes` → `...apiglm...awslistarsolicitudes`). El `packagename` es una constante única por XPZ definida en `configuracion.json` (raíz del repo), por ejemplo `ar.com.glmsa.seguros.comercial.` para LPS_COM.xpz o `glmsuit.comercial.` para Trunk.xpz; no se confirma desde el XPZ. No construir host ni base URL.
- Entrada: solo dos patrones — GET por posiciones de `APIGLMRequestIn.QueryParams`; POST por `FromJson` desde `APIGLMRequestIn.Body`.
- Tipos canónicos únicos: `Integer (<longitud>)`, `Decimal (<longitud>, <decimales>)`, `String (<longitud>)`, `LongVarchar`, `Boolean`, `Date (YYYY-MM-DD)`, `DateTime`, `Base64`, `Estructura <attr>`, `Colección de Estructura <attr>`, `Colección JSON`. Si una conversión solo confirma la familia y no la dimensión, se admiten `Integer` o `String` sin dimensión. No usar `Texto`, `Numérico`, `Objeto JSON`, etc.
- Resolución de dominios homónimos: una referencia `Domain:Nombre` sin módulo se resuelve al dominio de la raíz (`fullyQualifiedName` igual al nombre); si se necesita otro módulo, la referencia lo califica (`Domain:Nombre, Modulo`), y esa forma prevalece.
- Resolución de SDT homónimos: análoga a la de dominios. Una referencia `sdt:Nombre` (o variable `sdt:Nombre`) sin calificador de módulo con varios candidatos se resuelve al SDT de la raíz (`fullyQualifiedName` igual al nombre); si se necesita otro módulo, la referencia lo califica (`sdt:Nombre, Modulo`), y esa forma prevalece sin respaldo a la raíz. Implementado en `Obtener-Sdt` (AnalizarServicio.ps1).
- `Obligatorio` = `SI` solo con evidencia confirmada; al confirmar un campo primitivo, dejar de recorrer. Sin evidencia = `NO`.
- Errores HTTP: únicamente llamadas a `GenerarAPIGLMResponse` con código ≠ 200 dentro del programa principal. `HttpCode.BadRequest`→400, `NotFound`→404, `MethodNotAllowed`→405. Excluir errores funcionales bajo HTTP 200.
- Fuente única: solo el XPZ de `configuracion.json`. Si el programa principal delegado o el SDT de entrada/salida no está exportado en ese XPZ, detener con el mensaje correspondiente (`El programa principal <X> no está exportado en el XPZ configurado. No puede inferirse.` / `La salida del SDT <X> no está exportada en el XPZ configurado. No puede inferirse.`). No buscarlo en otros XPZ ni inferir por analogía.
- `serviciosIgnorados` en `configuracion.json`: FQN referenciados en el inventario que no se documentan. Al abrir la consola se informan y se excluyen del procesamiento con estado `OMITIDO` (ni ERROR ni documento).
- Ante evidencia insuficiente o contradictoria, **detener y registrar** `PENDIENTE DE CONFIRMACIÓN: <dato faltante>. Evidencia requerida: <fuente necesaria>.` Nunca completar por analogía ni suposiciones.

## Verificación e inconsistencias conocidas

- No hay lint ni tests. La verificación son las listas de control al final de `analisisXPZ.md`, `reglasEditoriales.md` y `templateDoc.md`; `Endpoints/assets/analisisEndpoint.md` espera que el conteo coincida con `endpoints.md`. Si el conteo difiere, primero determinar si cambió el XPZ o `APIGLMMain`; no forzar el número.
- Markdown en UTF-8 sin BOM y finales de línea LF.
- `Endpoints/assets/analisisEndpoint.md` referencia el XPZ configurado en `configuracion.json` y `GeneXus-XPZ-Skills-main/scripts/gx-object-type-catalog.json` mediante `../../../`.

## Skills

- `spec` / `spec-impl` instalados en `.agents/skills/` (tracked; lockfile `skills-lock.json`). Responden en español y leen `AGENTS.md` como memoria del proyecto.
