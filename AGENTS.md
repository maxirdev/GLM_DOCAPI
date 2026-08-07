# AGENTS.md

## Propósito del repositorio

Repositorio de documentación (sin código, sin build, sin tests). Produce fichas técnicas de los servicios HTTP de APIGLM a partir del export GeneXus `xpz/LPS_COM.xpz`. Todo el contenido se escribe en **español**.

## Fuentes de evidencia (solo lectura, no editar)

- `xpz/LPS_COM.xpz` — archivo ZIP que contiene un único XML `LPS_COM_v01.xml`, raíz `ExportFile`. Es la fuente de verdad: Source, Rules, variables, SDT, dominios, atributos y asignaciones.
- `GeneXus-XPZ-Skills-main/` — repositorio auxiliar vendido. Contiene scripts y catálogos (p. ej. `scripts/gx-object-type-catalog.json`, para confirmar tipos de objeto).

Ambas carpetas están en `.gitignore`: son referencias locales, no parte del producto.

## Estructura de trabajo (`documentacion/`, commiteada)

- `analisisXPZ.md` — fuente normativa #1: cómo construir la ficha técnica desde el XPZ.
- `reglasEditoriales.md` — fuente normativa #2: presentación del documento final.
- `templateDoc.md` — fuente normativa #3: plantilla obligatoria de cada servicio.
- `Endpoints/analisisEndpoint.md` — cómo reproducir el inventario de endpoints desde `APIGLM.APIGLMMain`.
- `Endpoints/endpoints.md` — inventario esperado de endpoints (aún no existe en el repo).
- `servicios/` — documentos por servicio (aún vacío).

Orden obligatorio por servicio: analisisXPZ → reglasEditoriales → templateDoc. No recalcular decisiones durante la redacción.

## Reglas no obvias

- El XPZ se abre como ZIP de solo lectura; el XML interno tiene raíz `ExportFile`.
- Inventario: solo llamadas `WS...` activas en `APIGLMMain` (una línea que comienza con `//` es una llamada inactiva). Confirmar que el objeto sea Procedure, `IsMain=True` y `CALL_PROTOCOL=HTTP`. Conservar el `fullyQualifiedName` literal, p. ej. `APIGLM.Cotizacion.WSObtenerDatosProductor`.
- Endpoint publicado ≠ nombre GeneXus: se escribe en minúsculas y, para procedures HTTP `Main`, se antepone `a` (`wslistarsolicitudes` → `awslistarsolicitudes`). No construir host, base URL ni package.
- Entrada: solo dos patrones — GET por posiciones de `APIGLMRequestIn.QueryParams`; POST por `FromJson` desde `APIGLMRequestIn.Body`.
- Tipos canónicos únicos: `Integer (<longitud>)`, `Decimal (<longitud>, <decimales>)`, `String (<longitud>)`, `Boolean`, `Date (YYYY-MM-DD)`, `DateTime`, `Base64`, `Estructura <attr>`, `Colección de Estructura <attr>`, `Colección JSON`. No usar `Texto`, `Numérico`, `Objeto JSON`, etc.
- `Obligatorio` = `SI` solo con evidencia confirmada; al confirmar un campo primitivo, dejar de recorrer. Sin evidencia = `NO`.
- Errores HTTP: únicamente llamadas a `GenerarAPIGLMResponse` con código ≠ 200 dentro del programa principal. `HttpCode.BadRequest`→400, `NotFound`→404, `MethodNotAllowed`→405. Excluir errores funcionales bajo HTTP 200.
- Ante evidencia insuficiente o contradictoria, **detener y registrar** `PENDIENTE DE CONFIRMACIÓN: <dato faltante>. Evidencia requerida: <fuente necesaria>.` Nunca completar por analogía ni suposiciones.

## Verificación e inconsistencias conocidas

- No hay lint ni tests. La verificación son las listas de control al final de `analisisXPZ.md`, `reglasEditoriales.md` y `templateDoc.md`; `Endpoints/analisisEndpoint.md` espera 135 endpoints. Si el conteo difiere, primero determinar si cambió el XPZ o `APIGLMMain`; no forzar el número.
- Markdown en UTF-8 sin BOM y finales de línea LF.
- `Endpoints/analisisEndpoint.md` referencia `../recursos/LPS_COM_v01.xpz` y `../scripts/gx-object-type-catalog.json`; las rutas reales son `xpz/LPS_COM.xpz` y `GeneXus-XPZ-Skills-main/scripts/gx-object-type-catalog.json`.
- El README escribe `Endpoint/` (singular) y `Endpoint/endpoints.md`; la carpeta real es `Endpoints/`. No corregir estas referencias por cuenta propia sin avisar.

## Skills

- `spec` / `spec-impl` instalados en `.agents/skills/` (tracked; lockfile `skills-lock.json`). Responden en español y leen `AGENTS.md` como memoria del proyecto.
