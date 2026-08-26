# AGENTS.md

## Propósito del repositorio

Repositorio de documentación y scripts PowerShell (sin build; incluye un harness de pruebas locales). Produce documentos técnicos de los servicios HTTP de APIGLM a partir del export GeneXus configurado. Todo el contenido se escribe en **español**.

## Fuentes de evidencia (solo lectura, no editar)

- `clientes/<clienteId>/<modulo>/<ambienteId>/xpz/` — archivo `.xpz` del contexto triple activo, resuelto desde `configuracion.json` (SPEC 26). Es un ZIP que contiene un único XML con raíz `ExportFile`. Es la fuente de verdad: Source, Rules, variables, SDT, dominios, atributos y asignaciones.
- `GeneXus-XPZ-Skills-main/` — repositorio auxiliar vendido. Contiene scripts y catálogos (p. ej. `scripts/gx-object-type-catalog.json`, para confirmar tipos de objeto).

Las carpetas globales `xpz/`, `estado/`, `documentacionServicios/` y `Logs/` eran legado monocliente y se eliminaron: el pipeline contextual no las lee ni las escribe. `clientes/` es el árbol contextual activo (SPEC 19).

## Estructura de trabajo

En la raíz del repo:

- `binary/` — scripts del generador: `GenerarDocumento.ps1` (orquestador), `ActualizarServicios.ps1`, `ControlVersiones.ps1`, `HistorialVersiones.ps1`, `ManifiestoEjecucion.ps1`, `AnalizarServicio.ps1`, `RedactarDocumento.ps1`, `EscribirSalidas.ps1`, `CargarConfiguracion.ps1`, `DiagnosticoIA.ps1` y `ResumirOperacionPdf.ps1`.
- `binary/GLMUtilidades.ps1` — módulo común de utilidades (hash SHA256 de texto/archivo, normalización LF, escritura UTF-8 sin BOM, escritura atómica con validación, resolución de rutas, validación XPZ/PDF, invocación de scripts hijo, reportes de validación, fábrica de registros del control). Hoja y sin dependencias: se carga por dot-source **siempre primero**, antes de cualquier otro script del proyecto (SPEC 18).
- `binary/ServidorPanelWeb.ps1` — servidor local Windows PowerShell 5.1 con `HttpListener`, limitado a `127.0.0.1`, sesión global y API contextual del panel; sirve las tres fuentes Poppins allowlisted y expone `GET /api/servicios`.
- `binary/ExportarXPZProgreso.ps1` y `binary/ExportarXPZ.msbuild` — ejecutan la exportación de `Module:APIGLM` desde la KB local; los invoca `EjecutarExportacionGLM.ps1` (opción 1 del lanzador).
- `binary/CompletarXPZActivoGLM.ps1` — completa el XPZ activo antes de documentar: valida con `ValidarXPZ.ps1` y exporta selectivos cuando faltan componentes (hasta cinco ciclos), preguntando si continuar cuando falla o se detiene con pendientes. Lo invoca la opción 3 (Generar PDF con el XPZ seleccionado) de `GenerarDocumentosGLM.cmd`.
- `binary/GenerarListaEndpoints.ps1` — genera inventarios independientes o generaciones contextuales para el panel; los procesos operativos descubren los servicios HTTP en memoria desde `APIGLM.APIGLMMain`.
- `Logs/*-diagnostico-ia.json` — diagnóstico estructurado de excepciones con fase, ruta relativa, sentencia y stack trace. Se genera solo ante errores; revisar primero el más reciente al investigar fallos del pipeline.

En `normativas/` (commiteada):

- `analisisXPZ.md` — fuente normativa #1: cómo construir la documentación técnica desde el XPZ.
- `reglasEditoriales.md` — fuente normativa #2: presentación del documento final.
- `templateDoc.md` — fuente normativa #3: plantilla obligatoria de cada servicio.
- `analisisEndpoint.md` — cómo reproducir el inventario de endpoints desde `APIGLM.APIGLMMain`.

- `GenerarDocumentosGLM.cmd` (raíz del repo) — entrada principal: valida la configuración global, pide elegir cliente y ambiente, valida el contexto elegido (preflight), exporta y completa el XPZ, y genera los PDF del contexto activo.
- `IniciarPanelWeb.cmd` (raíz del repo) — entrada web: inicia el panel local en el puerto `panel.puerto` o `8123` y abre el navegador.
- `web/` — única interfaz web vigente del producto: HTML, CSS y JavaScript vanilla sin CDN, paquetes ni fuentes remotas.
- `web/` — panel con `Dashboard`, `XPZ`, `Exportar`, `Endpoints`, `Documentación`, `Logs` y `Configuración`; Documentación es la vista unificada por endpoint y solo ofrece descarga PDF.
- `binary/fonts/` — fuentes Poppins locales servidas únicamente como `/fonts/Poppins-Regular.ttf`, `/fonts/Poppins-SemiBold.ttf` y `/fonts/Poppins-Bold.ttf`; no duplicar ni cargar fuentes remotas.
- `configuracion.json` (raíz del repo) — configuración central multicliente y modular (SPEC 19/26): `rutas.clientesRoot`, herramientas globales, `exportacion.onlyModuleAPIGLM` y la colección `clientes`. Cada cliente define `id`, `nombre`, `packagenames.comercial` y/o `packagenames.erp`, `serviciosIgnorados` y ambientes planos. Cada ambiente define `id`, `nombre`, `modulo` (`comercial` o `erp`), `tipo` (`test` o `prod`) y `kbPath` explícito. El panel web activa un contexto triple sin inferir un XPZ automáticamente.
- `clientes/<clienteId>/<modulo>/<ambienteId>/` — árbol contextual mutable (ignorado por Git): `documentacionServicios/`, `estado/`, `xpz/`, `Logs/` y `test/{fixtures,resultados}`. Cada contexto triple aísla documentos, estado, XPZ, logs y datos de prueba; las líneas de versionado son independientes por contexto.
- Las carpetas globales `estado/`, `documentacionServicios/`, `xpz/` y `Logs/` eran legado monocliente y se eliminaron: el pipeline contextual no las lee ni las escribe (SPEC 19).
- `servicios/` — documentos Markdown por servicio (p. ej. `wsobtenertotalessolicitud.md`). La conversión a PDF se ejecuta bajo demanda desde `binary/GenerarPdfServicios.ps1` mediante Pandoc + Typst portable; la plantilla normativa continúa en `templateDoc.md`.

Orden obligatorio por servicio: analisisXPZ → reglasEditoriales → templateDoc. No recalcular decisiones durante la redacción.

## Pipeline multicliente, modular y multiambiente (SPEC 19/26)

- La configuración es central (`configuracion.json` en la raíz) y declarativa: agregar un cliente o ambiente válido requiere editar solo ese archivo, sin copiar ni modificar scripts. Los IDs deben ser slugs en minúsculas (`^[a-z0-9][a-z0-9-]*$`), únicos sin distinguir mayúsculas en su nivel, y se usan como nombres de carpeta. Dos ambientes que normalicen al mismo `kbPath` invalidan la configuración.
- El panel es la interfaz web unificada vigente. No genera `APIServicios.html` ni consume un visor estático separado; `documentacionServicios/Endpoints/` contiene únicamente generaciones persistidas y `current.json`.
- `GET /api/servicios` resuelve en el servidor la relación contextual entre XPZ, inventario, control de versiones y PDF/Markdown publicados. Devuelve FQN, endpoint, estado, versión y disponibilidad por nombre de archivo, sin rutas físicas; la ausencia de control se representa como versión nula y `versionDisponible = false`.
- La navegación del panel unifica Documentación y Documentos; la selección se identifica por FQN, la paginación es cliente (25, 50, 100) y el PDF se descarga directamente cuando existe.
- El panel es la entrada operativa modular vigente: selecciona cliente, módulo y ambiente, y activa solo la identidad triple solicitada. La consola interactiva anterior queda deprecada para nuevos contextos modulares.
- `rutas.clientesRoot` relativo se resuelve contra la raíz del repositorio y un `kbPath` relativo contra la misma raíz; nunca se deduce una ruta de KB desde `id` o `nombre`. Un contexto válido crea exactamente `documentacionServicios`, `estado`, `xpz`, `Logs`, `test/fixtures` y `test/resultados` bajo `clientes/<clienteId>/<modulo>/<ambienteId>/`.
- La aplicación no infiere un XPZ activo al iniciar. El usuario debe seleccionar explícitamente un XPZ principal desde el menú; seleccionar otro XPZ solo afecta la sesión y no modifica `configuracion.json`. Los nuevos XPZ principales y complementos se escriben únicamente en la carpeta `xpz/` del ambiente activo.
- El manifiesto de ejecución es `schemaVersion = 3` y transporta la identidad (`contextId = <cliente>/<modulo>/<ambiente>`) y las rutas canónicas del contexto; todo proceso que recibe `-ManifiestoPath` valida la pertenencia de sus rutas y rechaza esquema 2 o combinaciones híbridas. No contiene ni requiere `inventoryPath`: los servicios HTTP se descubren desde el XPZ en memoria.
- Todo lo mutable por contexto queda bajo `clientes/<clienteId>/<modulo>/<ambienteId>/`: Markdown, PDF, `controlVersiones.json`, `historialVersiones.md`, pendientes, lineage, revisiones, fingerprints, review, diagnósticos, reportes de validación, logs de exportación y `actualizacion.lock`. Contextos distintos pueden actualizarse en paralelo; una segunda actualización del mismo contexto termina con código `1` por el lock contextual.
- Las líneas de versión son independientes por contexto aunque compartan FQN y contenido: `packagenames.<modulo>` y `serviciosIgnorados` pertenecen al cliente, y el control, el historial, los hashes y las revisiones de un contexto no se comparten ni se promueven.

## Reglas no obvias

- El XPZ se abre como ZIP de solo lectura; el XML interno tiene raíz `ExportFile`.
- Inventario: solo llamadas `WS...` activas en `APIGLMMain` (una línea que comienza con `//` es una llamada inactiva). Confirmar que el objeto sea Procedure, `IsMain=True` y `CALL_PROTOCOL=HTTP`. Conservar el `fullyQualifiedName` literal, p. ej. `APIGLM.Cotizacion.WSObtenerDatosProductor`.
- Endpoint publicado ≠ nombre GeneXus: se documenta el nombre completo en minúsculas (package del módulo + módulo + procedimiento) y, para procedures HTTP `Main`, se antepone `a`. El `packagenames.<modulo>` es una constante por cliente definida en `configuracion.json`; no se confirma desde el XPZ. No construir host ni base URL.
- Nombre de archivo de servicio: `Obtener-NombreArchivoServicio` (CargarMultiXPZ.ps1) usa el último segmento del FQN en minúsculas; si dos servicios del inventario comparten ese segmento (homónimos), agrega la ruta de módulos con guiones (p. ej. `wslistarcategoriaiva-apiglm-cotizacion.md`) para que nunca compartan archivo publicado ni staging. Todos los flujos (generador, PDF, actualizador y resumen) resuelven el nombre con la misma función y el inventario completo.
- Detección incremental de cambios: si un objeto modificado del XPZ no está vinculado a ningún servicio por las `dependencies` registradas en el control, el actualizador reanaliza todos los servicios `ACTIVO` sin dependencias registradas para reconstruir la traza (sin bump de versión cuando el contenido no cambia). Es el mecanismo que sana controles creados antes de la captura de traza.
- La fila `Versión` de la tabla `Definición del servicio` la asigna el control de versiones (`estado/controlVersiones.json`, formato `1.<revisión>`; sin control previo, `1.0`). El pipeline resuelve la versión objetivo antes de generar el Markdown y la comunica por `versions` en el manifiesto de ejecución; el `documentHash` se calcula excluyendo esa fila para que el propio cambio de versión no dispare revisiones. Al cambiar el perfil documental (plantilla, reglas o redactor), se regeneran todos los servicios activos para conformar el formato.
- Entrada: solo dos patrones — GET por posiciones de `APIGLMRequestIn.QueryParams`; POST por `FromJson` desde `APIGLMRequestIn.Body`.
- Tipos canónicos únicos: `Integer (<longitud>)`, `Decimal (<longitud>, <decimales>)`, `String (<longitud>)`, `LongVarchar`, `Boolean`, `Date (YYYY-MM-DD)`, `DateTime`, `Base64`, `Estructura <attr>`, `Colección de Estructura <attr>`, `Colección JSON`. Si una conversión solo confirma la familia y no la dimensión, se admiten `Integer` o `String` sin dimensión. No usar `Texto`, `Numérico`, `Objeto JSON`, etc.
- Resolución de dominios homónimos: una referencia `Domain:Nombre` sin módulo se resuelve al dominio de la raíz (`fullyQualifiedName` igual al nombre); si se necesita otro módulo, la referencia lo califica (`Domain:Nombre, Modulo`), y esa forma prevalece.
- Resolución de SDT homónimos: análoga a la de dominios. Una referencia `sdt:Nombre` (o variable `sdt:Nombre`) sin calificador de módulo con varios candidatos se resuelve al SDT de la raíz (`fullyQualifiedName` igual al nombre); si se necesita otro módulo, la referencia lo califica (`sdt:Nombre, Modulo`), y esa forma prevalece sin respaldo a la raíz. Implementado en `Obtener-Sdt` (AnalizarServicio.ps1).
- `Obligatorio` = `SI` solo con evidencia confirmada; al confirmar un campo primitivo, dejar de recorrer. Sin evidencia = `NO`.
- Errores HTTP: únicamente llamadas a `GenerarAPIGLMResponse` con código ≠ 200 dentro del programa principal. `HttpCode.BadRequest`→400, `NotFound`→404, `MethodNotAllowed`→405. Excluir errores funcionales bajo HTTP 200.
- Fuente única: solo el XPZ del ambiente activo (`clientes/<clienteId>/<ambienteId>/xpz/`). Si el programa principal delegado o el SDT de entrada/salida no está exportado en ese XPZ, detener con el mensaje correspondiente (`El programa principal <X> no está exportado en el XPZ configurado. No puede inferirse.` / `La salida del SDT <X> no está exportada en el XPZ configurado. No puede inferirse.`). No buscarlo en otros XPZ ni inferir por analogía.
- `serviciosIgnorados` del cliente en `configuracion.json`: FQN referenciados en el inventario que no se documentan. Al abrir la consola se informan y se excluyen del procesamiento con estado `OMITIDO` (ni ERROR ni documento).
- `estado/historialVersiones.md` (ignorado por Git): historial legible por servicio con una entrada por bump de versión (incluida la `1.0` de un servicio nuevo). Es un artefacto derivado **best-effort**: el control de versiones sigue siendo la fuente de verdad, se escribe siempre después de la escritura atómica del control y su fallo solo emite advertencia. Dos modos: **append** (lotes normales, inserta la entrada dentro del bloque `## <FQN>` existente; un servicio tiene un único bloque con versiones acumuladas) y **reemplazo** (reinicio del control: `-Inicializar`, control inválido/incompatible, control inexistente con historial previo o `lineageId` del encabezado distinto del control; reescribe encabezado nuevo + entradas `1.0`). La versión de cada entrada se deriva del control (`Obtener-VersionServicio`), nunca del archivo. El fast-path no toca el archivo.
- Ante evidencia insuficiente o contradictoria, **detener y registrar** `PENDIENTE DE CONFIRMACIÓN: <dato faltante>. Evidencia requerida: <fuente necesaria>.` Nunca completar por analogía ni suposiciones.

## Verificación e inconsistencias conocidas

- No hay build ni lint. `test/Run-Tests.ps1` ejecuta las pruebas locales del pipeline y analizador; la verificación adicional son las listas de control al final de `analisisXPZ.md`, `reglasEditoriales.md` y `templateDoc.md`. El descubrimiento operativo se valida contra `APIGLMMain` en memoria; no se fuerza un conteo proveniente de archivos de inventario.
- Markdown en UTF-8 sin BOM y finales de línea LF.
- `normativas/analisisEndpoint.md` referencia el XPZ configurado en `configuracion.json` y `GeneXus-XPZ-Skills-main/scripts/gx-object-type-catalog.json` mediante `../../../`.

## Integridad transaccional

- La actualización genera Markdown y PDF en staging y publica ambos por servicio; nunca reemplaza solo uno.
- El control usa `schemaVersion = 2`; `version` debe ser exactamente `1.<revision>` y los hashes corresponden a los archivos publicados.
- Un fallo conserva los artefactos anteriores y crea o actualiza un pendiente; una segunda ejecución simultánea termina con código `1` por el lock exclusivo.
- Los estados persistidos son `ACTIVO`, `ELIMINADO` y `OMITIDO`; la reactivación solo ocurre después de publicar Markdown y PDF válidos.
- Códigos de salida: `0` completo, `1` error fatal, `2` parcial y `3` abortado.

## Skills

- `spec` / `spec-impl` instalados en `.agents/skills/` (tracked; lockfile `skills-lock.json`). Responden en español y leen `AGENTS.md` como memoria del proyecto.
