# SPEC 15 — Panel web interactivo multicliente

> **Estado:** Implementado
> **Depende de:** SPEC 19
> **Fecha:** 2026-08-16
> **Objetivo:** Crear un panel web local y autocontenido que permita administrar clientes y ambientes, operar el pipeline documental del contexto seleccionado y consultar sus endpoints, documentos y logs sin duplicar la lógica de los scripts PowerShell.

## Por qué existe esta SPEC

La consola definida por la SPEC 19 permite elegir un cliente y un ambiente y ejecutar el pipeline con artefactos aislados. Sigue siendo una interfaz secuencial orientada a terminal y no ofrece una vista integrada para administrar la configuración, seguir trabajos largos, consultar documentos ni explorar los endpoints del contexto activo.

El repositorio conserva referencias históricas a un visor estático de endpoints, pero sus archivos ya no forman parte del árbol operativo actual. Esta SPEC establece el panel como única interfaz web vigente y conserva los scripts PowerShell como única implementación de exportación, análisis, versionado y publicación.

## Estrategia de implementación aislada

La implementación de esta SPEC se realiza en un worktree Git separado de la carpeta estable de la consola. La skill `spec-impl` no se modifica: la creación y selección del worktree se realiza antes de invocarla.

- Rama de implementación: `spec-15-panel-web-interactivo`.
- Carpeta sugerida: `../GLM_DocAPI-spec-15-panel-web-interactivo`.
- Comando de creación:

  ```powershell
  git worktree add "..\GLM_DocAPI-spec-15-panel-web-interactivo" -b "spec-15-panel-web-interactivo"
  ```

- El worktree original debe estar limpio antes de crearlo y la SPEC debe estar aprobada y registrada en Git.
- No se permite copiar manualmente el repositorio ni crear un segundo repositorio.
- Si el worktree o la rama ya existen, se reutilizan; no se eliminan automáticamente al terminar.
- `/spec-impl 15-panel-web-interactivo` se ejecuta desde la carpeta del worktree y todos los scripts y pruebas se ejecutan allí.
- La carpeta original permanece disponible como versión estable de la consola durante toda la implementación.

## Alcance

**Incluido:**

- Nuevo `IniciarPanelWeb.cmd` en la raíz para levantar el servidor y abrir `http://127.0.0.1:<puerto>` en el navegador predeterminado.
- Nuevo `binary/ServidorPanelWeb.ps1` basado exclusivamente en `HttpListener` de Windows PowerShell 5.1, limitado a loopback.
- Nuevos `web/index.html`, `web/app.js` y `web/style.css` como única interfaz web del producto.
- Implementación autocontenida con PowerShell, HTML, CSS y JavaScript vanilla, sin frameworks, gestores de paquetes, CDN, fuentes remotas ni librerías externas.
- Selector global obligatorio de cliente y ambiente en el encabezado; ninguna operación se habilita hasta seleccionar y validar un contexto de SPEC 19.
- Una única sesión global en memoria del servidor, compartida por todas las pestañas del navegador, con un contexto activo, un XPZ activo y como máximo un trabajo en curso.
- Selección automática del XPZ principal más reciente al activar o cambiar el contexto, con posibilidad de elegir otro XPZ solo durante la sesión.
- Bloqueo del selector de contexto y de todos los botones mutantes mientras exista un trabajo activo.
- Pestañas `Estado`, `XPZ`, `Exportar`, `Endpoints`, `Documentación`, `Documentos`, `Logs` y `Configuración`. La conversión PDF se integra en `Documentación` y no tiene una pestaña ni endpoint mutante independiente.
- Estado y preflight del contexto activo: cliente, ambiente, KB, herramientas, XPZ disponibles, XPZ activo, cantidades de endpoints/documentos y último review.
- Operaciones del pipeline y scripts compartidos que el panel expondrá: exportar y completar XPZ, seleccionar XPZ, regenerar inventario de endpoints, validar, publicar documentación seleccionada, actualizar servicios y reiniciar la documentación con confirmación explícita. El panel no invoca el menú interactivo `GestionDocumentosGLM.ps1`.
- Generación y publicación particular, múltiple o total de servicios mediante selección con checkboxes, sin `Out-GridView`; Markdown y PDF se publican conjuntamente.
- Ejecución de cada operación como proceso PowerShell hijo no interactivo, con parámetros contextuales de SPEC 19, log propio y seguimiento por polling. Ningún hijo del panel puede ejecutar `Read-Host` ni esperar entrada estándar.
- Un único trabajo global a la vez; nuevas operaciones mutantes responden HTTP 409 mientras el trabajo no haya terminado.
- Persistencia de `endpoints.json` y `endpoints.md` bajo `<contexto>/documentacionServicios/Endpoints/` para consumo del panel. `documentacionServicios/` sigue siendo la raíz canónica de documentos de SPEC 19; `Endpoints/` no se incluye en el listado de documentos de servicios.
- Regeneración automática de esos dos archivos cuando se activa un contexto, cambia el XPZ activo o termina una exportación que produce un XPZ principal nuevo. La regeneración es un subpaso rastreado del trabajo que produjo el cambio.
- Publicación conjunta y recuperable de `endpoints.json` y `endpoints.md`; nunca se considera vigente un par incompleto o con generaciones distintas.
- Conservación del último inventario válido cuando falla la regeneración, marcado visualmente como obsoleto respecto del XPZ activo y con una acción para reintentar.
- Pestaña Endpoints integrada con metadatos del contexto y XPZ fuente, total confirmado, filtro por nombre o descripción y tabla de nombre, descripción, proceso y endpoint publicado.
- No se genera `APIServicios.html` ni se introduce un visor estático separado. Las referencias históricas a `documentacion/Endpoints/` y `GenerarVistaHTML.ps1` se eliminan de documentación y pruebas, pero esos archivos no forman parte de la implementación actual.
- Listado contextual de Markdown y PDF con apertura o descarga segura.
- Listado y lectura contextual de reviews por ejecución, diagnóstico IA, validación XPZ, historial de versiones y logs de panel/exportación.
- Resumen visual adaptado de los reviews contextuales con estados `OK`, `WARNING`, `ERROR`, `OMITIDO`, `ELIMINADO` y `SIN_CAMBIOS` después de generar o actualizar documentación.
- CRUD de clientes y ambientes desde la pestaña Configuración, además de edición de herramientas globales, `clientesRoot`, `panel.puerto`, package y servicios ignorados. Cada cambio valida el documento completo y reinicia la sesión contextual.
- IDs de clientes y ambientes inmutables después del alta; los nombres visibles y las demás propiedades admitidas sí pueden editarse.
- Validación del documento completo con todas las reglas de SPEC 19 antes de guardar cualquier cambio de configuración.
- Escritura atómica de `configuracion.json`; una validación o escritura fallida conserva byte a byte el archivo anterior.
- Eliminación con confirmación explícita de un cliente o ambiente en la configuración sin borrar su árbol de XPZ, documentos, versiones, estado ni logs.
- Arranque en modo solo lectura si `configuracion.json` no es JSON válido o incumple su esquema; se muestran los errores y se bloquean CRUD y operaciones.
- Campo global opcional `panel.puerto` en `configuracion.json`, con valor predeterminado 8123 cuando no está definido.
- Interfaz responsive para escritorio y móvil, tema claro/oscuro, foco visible, estados vacíos, badges, toasts, spinners y respeto de `prefers-reduced-motion`.
- Extensión de `test/Run-Tests.ps1` para cubrir servidor, API, seguridad de rutas, sesión, CRUD, trabajos, endpoints contextuales y ausencia de dependencias externas.
- Actualización de `README.md`, `AGENTS.md` y `.gitignore` para describir el panel unificado y retirar el visor estático.

**Fuera de alcance (para futuras SPEC):**

- Autenticación, autorización de usuarios, HTTPS o acceso desde otras máquinas; el servidor se limita a `127.0.0.1`. El token de sesión local solo evita mutaciones cross-origin y no constituye autenticación.
- Frameworks frontend o backend, Node.js, npm, CDN, bases de datos o servicios externos.
- Renderizado de Markdown dentro del navegador; los `.md` se abren o descargan como archivo.
- Persistencia del contexto o XPZ seleccionado entre reinicios del servidor.
- Más de un trabajo simultáneo, aunque pertenezcan a ambientes diferentes.
- Eliminación, movimiento o migración de artefactos al editar la configuración.
- Edición del ID de un cliente o ambiente existente.
- Reglas de análisis, redacción o plantilla específicas por cliente.
- Swagger, OpenAPI u otra especificación adicional de los servicios.
- Reemplazo o eliminación de los puntos de entrada de consola.

## Modelo de datos

### Configuración global

La estructura de clientes, ambientes, herramientas y rutas es la definida por SPEC 19. Esta SPEC agrega solo `panel`:

```json
{
  "panel": {
    "puerto": 8123
  }
}
```

Convenciones:

- `panel.puerto` es global y debe ser un entero entre 1 y 65535.
- Si `panel` o `panel.puerto` no existe, el servidor usa 8123 sin reescribir el archivo.
- Si el JSON es válido pero el resto del esquema contiene errores y `panel.puerto` es válido, el servidor puede escuchar en el puerto declarado y queda en solo lectura. Si el puerto falta o es inválido, usa 8123 y muestra el error.
- El CRUD siempre valida la configuración completa, no propiedades aisladas. La validación incluye tipos, colecciones, IDs, duplicados de KB, `exportacion.onlyModuleAPIGLM`, `serviciosIgnorados` y `panel.puerto`.
- Los IDs son editables únicamente durante el alta.
- Eliminar una entrada del JSON nunca elimina su directorio contextual.

### Estado de sesión

```powershell
$sesion = [pscustomobject]@{
    ContextoActivo = $null # ContextId, ClienteId, AmbienteId y rutas resueltas de SPEC 19
    XpzActivo = ''         # Override de sesión o principal más reciente del contexto
    TrabajoActual = $null  # Id, ContextId, Operacion, Estado, Log, Inicio, Progreso, CodigoSalida y Warnings
    UltimoResumen = $null  # Review del contexto y ejecución más recientes
    UltimoTrabajoTerminado = $null
}
```

Convenciones:

- La sesión pertenece al proceso servidor y es compartida por todas las pestañas abiertas.
- No se selecciona automáticamente el primer contexto configurado.
- Cambiar el contexto descarta el XPZ anterior y activa el principal más reciente del nuevo ambiente.
- Cerrar el servidor descarta contexto, XPZ, trabajos terminados y resumen mantenidos en memoria. Antes de cerrar, el servidor intenta terminar el árbol del proceso hijo activo y registra el resultado.
- Un trabajo conserva el `ContextId` con el que fue creado y nunca consulta el contexto mutable de la interfaz para resolver sus rutas.
- La selección del XPZ principal más reciente reutiliza una función compartida con la consola y devuelve objetos con nombre, ruta, fecha y marca de principal. El panel no parsea la salida textual de `ListarXPZPrincipales.ps1`.
- Activar un contexto no activa otro automáticamente si el contexto anterior fue eliminado. La regeneración automática del inventario se registra como trabajo y puede fallar sin desactivar el contexto.
- Después de cualquier guardado o eliminación de configuración, la sesión se limpia por completo y exige seleccionar nuevamente cliente, ambiente y XPZ. Un cambio de `panel.puerto` entra en vigor al reiniciar el servidor.
- El servidor conserva en memoria el trabajo activo y solo el último trabajo terminado. Los trabajos anteriores se consultan mediante sus logs contextuales.

### Inventario persistido por ambiente

```text
clientes/<clienteId>/<ambienteId>/
└── documentacionServicios/
    └── Endpoints/
        ├── generations/
        │   ├── <generationId>/
        │   │   ├── endpoints.json
        │   │   └── endpoints.md
        │   └── ...
        └── current.json
```

`current.json` es un puntero pequeño publicado atómicamente que contiene el `generationId` activo. El panel resuelve el par JSON/Markdown desde esa generación y nunca lee archivos de generaciones distintas. Se conservan la generación actual y la anterior; la eliminación de generaciones más antiguas es best-effort.

`endpoints.json` conserva el contrato actual de endpoints y agrega o confirma en `meta`:

```json
{
  "schemaVersion": 1,
  "meta": {
    "generationId": "20260816-120000-a1b2c3d4",
    "contextId": "trunk/testing",
    "clienteId": "trunk",
    "ambienteId": "testing",
    "xpz": "C:/DOCUMENTACIONAPI/clientes/trunk/testing/xpz/APIGLM_20260816.xpz",
    "xpzSha256": "<sha256>",
    "generatedAt": "2026-08-16T12:00:00Z",
    "totalConfirmed": 120,
    "totalProcessable": 116,
    "totalIgnored": 4
  },
  "endpoints": []
}
```

Los servicios incluidos en `serviciosIgnorados` no aparecen en `endpoints`; se informa su cantidad en `totalIgnored` y se muestran como omitidos en el resumen del contexto.

El inventario está vigente solo cuando `contextId`, ruta canónica del XPZ, `xpzSha256` y `generationId` coinciden con el contexto y XPZ activos. Una diferencia no elimina las generaciones: el panel puede mostrar la última generación como consulta histórica con un banner `OBSOLETO`, pero no permite presentarla como inventario actual. La pestaña Endpoints es consumidora del inventario persistido, no fuente operativa única.

### API JSON

| Método y ruta | Acción |
|---|---|
| `GET /api/estado` | Estado global, errores de configuración, contexto, XPZ y trabajo actuales |
| `GET /api/contextos` | Clientes y ambientes configurados para los selectores |
| `POST /api/contexto/activar` | Validar y activar `{ clienteId, ambienteId }` |
| `GET /api/xpz` | Listar XPZ principales del contexto activo |
| `POST /api/xpz/activar` | Activar un XPZ de sesión y lanzar la regeneración de endpoints |
| `POST /api/exportar` | Exportar/completar el contexto y regenerar endpoints con el XPZ nuevo |
| `GET /api/endpoints` | Obtener inventario, vigencia y metadatos del contexto activo |
| `POST /api/endpoints/regenerar` | Reintentar la generación contextual de JSON y Markdown |
| `GET /api/servicios` | Descubrir servicios directamente desde el XPZ activo para selección operativa |
| `POST /api/validar` | Validar completitud del XPZ activo |
| `POST /api/documentos` | Generar y publicar uno, varios o todos los servicios seleccionados mediante `ActualizarServicios.ps1` |
| `POST /api/actualizar` | Publicar cambios detectados usando exclusivamente el XPZ activo |
| `POST /api/documentacion/reiniciar` | Reiniciar control, historial, Markdown y PDF del ambiente con confirmación explícita |
| `GET /api/trabajos/<id>` | Estado, progreso y últimas líneas del log del trabajo |
| `GET /api/documentos` | Listar Markdown y PDF del contexto activo |
| `GET /api/documentos/<nombre>` | Abrir o descargar un archivo contextual permitido |
| `GET /api/logs` | Listar logs y reportes permitidos del contexto activo |
| `GET /api/logs/<nombre>` | Leer un log contextual permitido |
| `GET /api/reportes/historial` | Leer `estado/historialVersiones.md` del contexto activo |
| `GET /api/reportes/review-ultimo` | Leer el último review válido del contexto activo |
| `GET /api/reportes/validacion-ultima` | Leer el último reporte de validación XPZ válido del contexto activo |
| `GET /api/configuracion` | Leer configuración, `configHash` y resultado de validación |
| `POST /api/configuracion/clientes` | Crear un cliente con ID nuevo |
| `PUT /api/configuracion/clientes/<id>` | Editar propiedades de un cliente sin cambiar su ID |
| `DELETE /api/configuracion/clientes/<id>` | Quitar un cliente del JSON sin borrar artefactos |
| `POST /api/configuracion/clientes/<id>/ambientes` | Crear un ambiente con ID nuevo |
| `PUT /api/configuracion/clientes/<id>/ambientes/<id>` | Editar un ambiente sin cambiar su ID |
| `DELETE /api/configuracion/clientes/<id>/ambientes/<id>` | Quitar el ambiente del JSON sin borrar artefactos |
| `PUT /api/configuracion/global` | Editar rutas, herramientas, exportación y puerto con `configHash` precondicional |

Convenciones de API:

- Todas las respuestas usan JSON UTF-8 y contienen `ok`, `data` o `error` según corresponda.
- Las operaciones mutantes aceptan únicamente `Content-Type: application/json`, tienen un límite de cuerpo de 1 MiB y requieren el token de sesión local enviado en `X-Panel-Token`.
- Las operaciones que requieren contexto responden HTTP 409 cuando no hay uno activo o existe un trabajo en curso.
- Un recurso inexistente responde 404, una entrada inválida responde 400 y un error interno responde 500 sin exponer stack trace al navegador.
- Las operaciones aceptadas responden HTTP 202 con `jobId`; dos mutaciones concurrentes responden HTTP 409.
- Las descargas solo resuelven identificadores lógicos y nombres simples dentro de directorios allowlisted; se rechazan rutas absolutas, `..`, `/`, `\`, `:`, doble codificación y extensiones no admitidas.
- La API no emite CORS, valida `Host` contra loopback, usa `Cache-Control: no-store` y no permite que una petición cross-origin ejecute mutaciones.
- Al eliminar el contexto activo, la sesión queda sin contexto y exige una selección nueva.
- `GET /api/servicios` abre el XPZ activo y reutiliza `Cargar-IndiceMultiXPZ` y `Obtener-ServiciosHttpDesdeIndice`; su resultado es efímero, puede almacenarse en memoria por `xpzSha256` durante la sesión y no se publica como sustituto del inventario persistido.
- `GET /api/configuracion` devuelve el hash SHA-256 de los bytes actuales de `configuracion.json`. Toda mutación de configuración debe incluir ese `configHash`; si el archivo cambió desde la lectura, responde HTTP 409 y no escribe.

### Contratos de selección y procesos hijos

Las operaciones documentales no aceptan rutas del sistema. La selección usa FQN del inventario actual:

```json
{
  "mode": "selected",
  "fullyQualifiedNames": ["APIGLM.Modulo.WSServicio"]
}
```

`mode` puede ser `selected` o `all`. `selected` exige un array no vacío y `all` no admite elementos. Se rechazan duplicados, FQN inexistentes e ignorados. Los FQN se descubren y validan contra el XPZ activo, aunque el inventario persistido esté ausente u obsoleto. La selección de la interfaz incluye el resultado de `GET /api/servicios`; no se aceptan rutas de archivos.

El panel crea un manifiesto esquema 2 con el contexto canónico, XPZ, staging y selección, y ejecuta los scripts compartidos directamente. No invoca el menú de `GestionDocumentosGLM.ps1`. Los hijos deben admitir modo no interactivo: las confirmaciones de exportación completa, continuación ante pendientes y reinicio se resuelven en la API antes de iniciar el proceso y se pasan como parámetros explícitos. Un hijo que solicite entrada estándar es un error del trabajo.

La exportación y la completitud conservan los ciclos y códigos de SPEC 19, pero su política se declara en la petición (`abort` o `continue`). `continue` permite publicar solo la evidencia disponible y conserva los pendientes. En ese caso el trabajo termina como `COMPLETED`, código `0`, con `warnings` y pendientes explícitos visibles en la respuesta, el review y el toast; nunca se oculta que el XPZ quedó incompleto.

La regeneración selectiva reanaliza los FQN solicitados aunque no existan cambios detectados. Solo incrementa la versión si cambia el `documentHash` normalizado; si el contenido es idéntico, publica o verifica los artefactos sin producir un bump falso.

`POST /api/documentacion/reiniciar` exige:

```json
{
  "confirmReset": true,
  "xpzSha256": "<hash mostrado al confirmar>"
}
```

El servidor responde 400 si falta la confirmación y 409 si cambió el contexto, XPZ o hash desde la pantalla de confirmación.

### Estados de trabajo

Un trabajo tiene los estados `QUEUED`, `RUNNING`, `COMPLETED`, `PARTIAL`, `ABORTED` o `FAILED`. Conserva `id`, `contextId`, `operacion`, `log`, `inicio`, `fin`, `codigoSalida`, `progreso`, `warnings`, `error` y las últimas líneas del log. El código de salida de SPEC 19 es la autoridad: `0` se muestra como `COMPLETED`, `2` como `PARTIAL`, `3` como `ABORTED` y `1` como `FAILED`. Cuando la política `continue` deja pendientes, el estado sigue siendo `COMPLETED` con código `0`, pero `warnings` no puede estar vacío.

El lock global del servidor se adquiere antes de aceptar una mutación. El trabajo conserva todas sus rutas y su `ContextId` aunque la sesión cambie después. Al cerrar el servidor no se promete reanudar ni matar procesos hijos: el trabajo queda diagnosticable por su log y la siguiente sesión comienza vacía.

## Interfaz y estados visuales

- Encabezado persistente con selectores de cliente y ambiente, XPZ activo, indicador de trabajo y alternador de tema.
- Los selectores comienzan sin valor y requieren una elección explícita.
- Una configuración inválida muestra un banner de error y deja disponibles únicamente Estado y Configuración en modo lectura.
- Los botones de operación usan estado `cargando`: quedan deshabilitados, muestran spinner CSS y cambian su etiqueta a `Procesando...`.
- Mientras hay un trabajo activo se deshabilitan todos los botones mutantes y los selectores; las consultas de progreso, documentos y logs siguen disponibles.
- La sección `Trabajo en curso` muestra operación, contexto, inicio, estado, últimas líneas y una barra indeterminada o determinada cuando existe un total fiable.
- El navegador consulta el trabajo cada 1–2 segundos y detiene el polling al llegar a un estado final.
- Los resultados usan badges `OK` (verde), `WARNING` (ámbar), `ERROR` (rojo), `OMITIDO` (gris) y `OBSOLETO` (violeta o ámbar diferenciado).
- La pestaña Endpoints muestra filtro inmediato por nombre o descripción, metadatos, tabla responsive y acción `Regenerar` cuando falta o está obsoleto el inventario.
- Documentación permite seleccionar individualmente, en lote o todos los servicios, con conteo visible, y publica Markdown y PDF conjuntamente.
- El adaptador visual de reviews no interpreta `ACTIVO` como `OK` por sí solo: `ERROR` prevalece si falla Markdown, PDF, control o promoción; `WARNING` representa pendientes, PDF conservado o código parcial; `OK` exige publicación válida; `OMITIDO` y `ELIMINADO` se muestran como estados propios; un fast-path sin cambios se muestra como `SIN_CAMBIOS`.
- Configuración usa formularios por cliente y ambiente; las eliminaciones requieren confirmación que informa expresamente que los artefactos se conservarán.
- Los estados vacíos distinguen entre contexto no seleccionado, XPZ inexistente, inventario no generado, documentos inexistentes y logs inexistentes.
- Las capacidades se muestran por operación: consultar artefactos y descubrir servicios desde un XPZ no requiere todas las herramientas; exportar requiere GeneXus y MSBuild; generar PDF requiere Pandoc y Typst. La ausencia de una herramienta no desactiva operaciones no relacionadas.
- Los toasts de finalización incluyen resultado, contexto y acceso al detalle del trabajo.
- La interfaz funciona en escritorio y móvil, tiene foco visible, contraste suficiente y respeta `prefers-reduced-motion`.

## Plan de implementación

1. Crear o reutilizar el worktree `../GLM_DocAPI-spec-15-panel-web-interactivo` en la rama `spec-15-panel-web-interactivo`, verificar que la implementación se ejecuta allí y conservar la carpeta estable sin cambios de la implementación web.
2. Convertir los contratos históricos del visor en fixtures de prueba (metadatos, filtro y estados vacíos), crear el esqueleto funcional de `web/index.html`, `web/app.js` y `web/style.css`, y verificarlo sin servidor.
3. Crear `binary/ServidorPanelWeb.ps1` e `IniciarPanelWeb.cmd` con `HttpListener` loopback, puerto configurable, servicio de estáticos seguro y endpoints `estado`, `contextos` y `contexto/activar`; el panel ya permite seleccionar y mostrar un contexto de SPEC 19.
4. Implementar la sesión global, selección del XPZ más reciente, listado/override de XPZ y bloqueo del cambio de contexto durante un trabajo; probar cambio de contexto sin persistencia.
5. Implementar el manejador de un único proceso hijo, logs contextuales `panel-<id>.log`, polling, códigos finales, HTTP 409, spinners, progreso, toasts y terminación controlada del árbol de procesos; conectar primero la validación XPZ como operación completa.
6. Extraer a `binary/CargarMultiXPZ.ps1` la selección compartida del XPZ principal más reciente y adaptar `binary/GenerarListaEndpoints.ps1` para aceptar manifiesto contextual, reutilizar `Obtener-ServiciosHttpDesdeIndice`, excluir `serviciosIgnorados` y generar generaciones versionadas con `current.json`.
7. Integrar la pestaña Endpoints con el inventario persistido en `documentacionServicios/Endpoints/`, implementar `generationId`, validación de vigencia, retención actual/anterior, rollback y descubrimiento efímero mediante `GET /api/servicios`.
8. Conectar exportación/completitud y generación documental a los scripts existentes mediante manifiestos y parámetros no interactivos de SPEC 19. La publicación seleccionada pasa por `ActualizarServicios.ps1`, conserva Markdown, PDF, control, hashes e historial y no crea un endpoint PDF independiente.
9. Implementar documentos, reportes, logs, review e historial contextuales con rutas permitidas, descargas seguras, estados vacíos y resumen visual; el último review se valida por contexto, fecha UTC, ejecución y control.
10. Separar validación estructural, preflight sin escrituras e inicialización del árbol. Implementar el CRUD de configuración con IDs inmutables, validación completa incluyendo `panel.puerto`, escritura atómica, `configHash`, confirmación de eliminación, conservación de artefactos e invalidación de sesión.
11. Completar `test/Run-Tests.ps1` con pruebas HTTP y de frontend sobre dos contextos temporales, procesos sin stdin, seguridad de rutas, concurrencia global, inventarios obsoletos, generaciones y puntero, rollback, atomicidad de configuración, cierre de procesos y ausencia de referencias a frameworks/CDN; reemplazar los `SKIP` heredados del visor.
12. Actualizar `README.md`, `AGENTS.md` y `.gitignore`, verificar escritorio/móvil en Edge y confirmar que consola y panel producen los mismos artefactos para un mismo contexto y XPZ.

## Criterios de aceptación

- [ ] La implementación se ejecuta desde `../GLM_DocAPI-spec-15-panel-web-interactivo` en la rama `spec-15-panel-web-interactivo`, y la carpeta estable original no recibe archivos del panel durante el desarrollo.
- [ ] `IniciarPanelWeb.cmd` levanta el servidor en `127.0.0.1:8123` o en el puerto global configurado y abre el navegador.
- [ ] Con el puerto ocupado, el lanzador informa el error, termina con código `1` y no abre una pestaña fallida.
- [ ] El panel no usa frameworks, paquetes, CDN, fuentes remotas ni librerías externas y funciona sin acceso a Internet.
- [ ] El código productivo del panel usa solo Windows PowerShell 5.1, `HttpListener`, HTML, CSS y JavaScript vanilla.
- [ ] Una configuración válida muestra clientes y ambientes, pero no activa ninguno automáticamente.
- [ ] Sin contexto activo, las operaciones permanecen bloqueadas y la interfaz solicita seleccionar cliente y ambiente.
- [ ] Activar un contexto ejecuta su preflight y usa exclusivamente sus rutas resueltas por SPEC 19.
- [ ] Si el contexto tiene XPZ pero el inventario persistido falta u obsoleto, `POST /api/contexto/activar` activa el contexto y responde HTTP 202 con el `jobId` de regeneración.
- [ ] Una configuración inválida permite iniciar el panel en modo solo lectura, muestra errores concretos y bloquea CRUD y operaciones.
- [ ] Al cambiar de contexto se activa el XPZ principal más reciente y se descarta el override del contexto anterior.
- [ ] Seleccionar otro XPZ afecta solo la sesión y no modifica `configuracion.json`.
- [ ] No se puede cambiar cliente, ambiente ni XPZ mientras existe un trabajo activo.
- [ ] Todas las pestañas abiertas comparten el mismo contexto, XPZ y trabajo del proceso servidor.
- [ ] El servidor permite un único trabajo global y responde HTTP 409 a una segunda operación mutante.
- [ ] El token anti-CSRF local se inyecta al servir `index.html`, todas las pestañas pueden usarlo y una mutación sin token es rechazada.
- [ ] Cada trabajo conserva su `ContextId`, escribe su log bajo el ambiente correcto y ejecuta procesos hijo con rutas contextuales.
- [ ] Polling, spinner, deshabilitado, barra de progreso y toast reflejan el estado real del proceso hijo.
- [ ] Exportar conserva la confirmación previa, los ciclos de completitud y los códigos de salida vigentes.
- [ ] Activar el contexto, cambiar el XPZ o exportar un XPZ nuevo lanza una regeneración de endpoints registrada dentro de un trabajo.
- [ ] `endpoints.json` y `endpoints.md` se publican juntos bajo `<contexto>/documentacionServicios/Endpoints/generations/<generationId>/`, y `current.json` se cambia como único puntero atómico.
- [ ] Se conservan la generación actual y la anterior; una interrupción durante la publicación deja el puntero anterior intacto o permite recuperar el estado sin mezclar generaciones.
- [ ] El inventario persistido identifica `schemaVersion`, `generationId`, `contextId`, `clienteId`, `ambienteId`, ruta canónica del XPZ, hash, fecha y totales confirmado, procesable e ignorado.
- [ ] `serviciosIgnorados` no aparece en `endpoints` y su cantidad queda reflejada en `totalIgnored`.
- [ ] Un fallo de regeneración conserva byte a byte el último par válido y lo muestra como `OBSOLETO` respecto del XPZ activo.
- [ ] Reintentar una regeneración exitosa reemplaza ambos archivos y elimina el estado obsoleto.
- [ ] `GET /api/servicios` descubre servicios desde el XPZ activo aunque el inventario persistido falte o esté obsoleto, y los FQN se revalidan antes de cualquier publicación.
- [ ] La pestaña Endpoints filtra por nombre o descripción y muestra nombre, descripción, proceso y endpoint del contexto activo; un inventario obsoleto no puede iniciar operaciones.
- [ ] El pipeline no genera `APIServicios.html` y no depende de un visor estático separado; las referencias históricas al visor se retiran.
- [ ] Generar documentación permite elegir uno, varios o todos los servicios sin `Out-GridView` y publica mediante `ActualizarServicios.ps1`.
- [ ] Actualizar servicios respeta control, historial, locks, versiones y transaccionalidad del ambiente activo.
- [ ] La acción de documentación permite elegir uno, varios o todos los servicios sin eliminar sus fuentes y conserva la transacción Markdown/PDF y sus hashes.
- [ ] Reiniciar documentación exige confirmación explícita, hash del XPZ y deja claro que reinicia control, historial, Markdown y PDF del ambiente activo.
- [ ] El resumen posterior adapta el review contextual correcto y muestra `OK`, `WARNING`, `ERROR`, `OMITIDO`, `ELIMINADO` y `SIN_CAMBIOS` según la publicación real.
- [ ] Documentos lista y descarga únicamente `.md` y `.pdf` del contexto activo.
- [ ] Logs lista y lee únicamente archivos permitidos del contexto activo.
- [ ] Rutas con `..`, absolutas, `/`, `\`, `:`, doble codificación o extensiones no permitidas son rechazadas sin leer archivos externos.
- [ ] El CRUD crea clientes y ambientes con IDs válidos y rechaza IDs duplicados o rutas de KB duplicadas según SPEC 19.
- [ ] El CRUD no permite cambiar el ID de una entrada existente.
- [ ] Cada guardado valida la configuración completa, incluyendo `panel.puerto` y tipos de colecciones, y la escribe atómicamente.
- [ ] Cada mutación de configuración exige el `configHash` leído previamente y responde HTTP 409 sin escribir si el archivo cambió externamente.
- [ ] Un guardado inválido o fallido conserva byte a byte el `configuracion.json` anterior.
- [ ] Eliminar un cliente o ambiente exige confirmación, quita solo la entrada del JSON y conserva intacto su árbol contextual.
- [ ] Eliminar el contexto activo limpia la selección de sesión y no activa otro automáticamente.
- [ ] La interfaz funciona en escritorio y móvil, ofrece tema claro/oscuro, foco visible y respeta `prefers-reduced-motion`.
- [ ] Los puntos de entrada de consola siguen funcionando y producen los mismos artefactos que el panel para el mismo contexto y XPZ.
- [ ] `test/Run-Tests.ps1` cubre API, sesión, seguridad, CRUD, trabajos sin stdin e inventarios sobre al menos dos contextos y termina con código `0`.
- [ ] Al cerrar el servidor con un trabajo activo se intenta terminar el árbol del proceso hijo y el resultado queda registrado.
- [ ] `README.md`, `AGENTS.md` y `.gitignore` describen el panel unificado, la ruta contextual nueva y no presentan el visor estático como interfaz vigente.

## Decisiones

- **Sí:** SPEC 19 permanece como contrato del pipeline y esta SPEC agrega únicamente la interfaz web y la persistencia contextual requerida por Endpoints.
- **Sí:** panel único para operación y consulta de endpoints. Evita mantener dos aplicaciones web y dos lenguajes visuales.
- **Sí:** `HttpListener` y frontend vanilla. El panel no introduce dependencias externas ni requiere Internet.
- **Sí:** selector global obligatorio. Todas las pestañas observan el mismo contexto y reducen el riesgo de operar sobre otro ambiente.
- **Sí:** sesión única del servidor. Es coherente con un servicio loopback para un operador local.
- **Sí:** un único trabajo global. Simplifica el seguimiento y evita que una pestaña cambie el estado visible mientras otra operación muta artefactos.
- **Sí:** bloquear cambios de contexto durante un trabajo. El resultado y el progreso siempre se atribuyen al contexto que inició la operación.
- **Sí:** XPZ más reciente al cambiar de contexto y override no persistido. Coincide con la consola de SPEC 19.
- **Sí:** inventario persistido por ambiente bajo `documentacionServicios/Endpoints/` para la pestaña Endpoints. El inventario efímero del pipeline de SPEC 19 mantiene su finalidad transaccional independiente.
- **Sí:** regenerar endpoints con cada cambio de XPZ. La vista intenta mantenerse alineada con la fuente activa sin exigir una acción adicional.
- **Sí:** publicar inventarios en generaciones versionadas y cambiar un único puntero `current.json`. Evita presentar un JSON y un Markdown de generaciones diferentes después de una interrupción.
- **Sí:** conservar la generación actual y la anterior. Las generaciones más antiguas se limpian best-effort y no forman parte del contrato de consulta.
- **Sí:** conservar y marcar obsoleto ante error. Un fallo no destruye el último inventario válido, pero el panel lo presenta solo como consulta histórica y no lo usa para mutaciones.
- **Sí:** usar `GET /api/servicios` para descubrimiento efímero desde el XPZ activo. El inventario persistido sirve para consulta y metadatos, no es la fuente operativa única.
- **Sí:** excluir `serviciosIgnorados` del array persistido y mostrar únicamente su cantidad. La selección y publicación los rechaza.
- **Sí:** eliminar el endpoint y la pestaña PDF independientes. La pestaña Documentación publica Markdown y PDF conjuntamente mediante `ActualizarServicios.ps1`.
- **Sí:** continuar con XPZ incompleto como `COMPLETED` con código `0` y warnings explícitos cuando el operador elige la política `continue`.
- **Sí:** activar contexto con regeneración pendiente responde `202` y devuelve `jobId`; el contexto y el XPZ quedan activos aunque el inventario falle.
- **Sí:** reanalizar selecciones explícitas sin bump falso. El versionado solo cambia si cambia el `documentHash` normalizado.
- **Sí:** habilitar capacidades por operación según herramientas disponibles, en lugar de bloquear la activación completa del contexto.
- **Sí:** proteger el CRUD con `configHash` y HTTP 409 ante cambios externos para no sobrescribir configuración ajena.
- **Sí:** conservar en memoria el trabajo activo y el último terminado; los anteriores se consultan mediante logs.
- **Sí:** intentar terminar el árbol de procesos al cerrar el servidor y registrar el resultado.
- **Sí:** exponer historial, review y validación mediante rutas lógicas separadas.
- **Sí:** inyectar el token local anti-CSRF en el HTML servido por el proceso para compartirlo entre pestañas.
- **Sí:** toda publicación de documentación seleccionada pasa por `ActualizarServicios.ps1`; el panel no publica Markdown o PDF por separado.
- **Sí:** las confirmaciones interactivas se convierten en decisiones explícitas de API antes de iniciar procesos hijos.
- **Sí:** CRUD completo con IDs inmutables. Permite administrar contextos sin convertir un cambio de identificador en una migración de artefactos.
- **Sí:** escritura atómica y validación total del JSON. No se permiten estados parcialmente válidos.
- **Sí:** eliminar configuración sin eliminar datos. La baja administrativa no es una operación destructiva sobre documentos, versiones o XPZ.
- **Sí:** modo solo lectura ante configuración inválida. La corrección se realiza fuera del panel para no intentar mutar un documento cuyo modelo no pudo establecerse.
- **No:** mantener o generar un `APIServicios.html`. La pestaña Endpoints consume directamente la API contextual.
- **No:** persistir contexto o XPZ de sesión. Cada arranque exige una selección consciente.
- **No:** múltiples trabajos por ambiente. Los locks de SPEC 19 siguen protegiendo el pipeline, pero el panel conserva una cola efectiva de tamaño uno.
- **No:** renderizar Markdown. Los archivos se abren o descargan sin agregar un motor de renderizado.
- **No:** reemplazar la consola. Ambos puntos de entrada invocan la misma lógica compartida.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Una pestaña cambia el contexto mientras otra observa un trabajo | Sesión global visible, selectores bloqueados durante trabajos y `ContextId` inmutable dentro de cada trabajo. |
| La implementación web contamina la carpeta estable de la consola | Worktree Git obligatorio, rama dedicada, validación de ruta de trabajo al iniciar y pruebas ejecutadas desde el worktree. |
| El inventario queda desalineado después de cambiar el XPZ | Regeneración automática y validación por contexto, ruta canónica, `generationId` y SHA256 del XPZ. |
| Falla la regeneración y se pierde la última vista útil | Staging, promoción con rollback y lectura que exige generación coincidente; se conserva el par anterior y se marca `OBSOLETO`. |
| El CRUD corrompe o deja parcialmente válida la configuración | Validación completa, escritura atómica y conservación byte a byte ante cualquier fallo. |
| Eliminar un contexto destruye versiones o documentos | La API elimina solo la entrada del JSON; nunca ejecuta borrado sobre el árbol contextual. |
| Path traversal permite leer archivos del equipo | Identificadores lógicos, raíces canónicas contextuales, allowlists de directorios/extensiones, validación Host y rechazo de rutas absolutas, separadores, `..`, `:` y doble codificación. |
| Un proceso largo queda vivo al cerrar la pestaña | El trabajo pertenece al servidor y al proceso hijo; al recargar, el navegador recupera su estado por polling. |
| El servidor se cierra mientras hay un proceso hijo | El log contextual y los artefactos transaccionales permiten diagnosticarlo; el pipeline conserva los contratos de fallo de SPEC 19. |
| Puerto ocupado o configuración inválida impiden operar | Error explícito de puerto; configuración inválida abre la interfaz en modo solo lectura usando el puerto declarado si es válido o 8123 como fallback. |
| La retirada de referencias históricas del visor causa regresión de consulta | La pestaña Endpoints conserva filtro, metadatos, estados obsoletos y estados vacíos; se prueban los contratos antes de retirar las referencias. |
| Futuras incorporaciones agregan dependencias externas accidentalmente | Pruebas estáticas rechazan referencias a CDN, imports de paquetes, `node_modules`, `package.json` y gestores de dependencias. |

## Lo que **no** incluye esta SPEC

- Acceso remoto, autenticación, HTTPS o múltiples usuarios.
- Frameworks, librerías externas, paquetes o CDN.
- Múltiples trabajos simultáneos.
- Persistencia de contexto o XPZ seleccionado.
- Migración o eliminación de artefactos al editar la configuración.
- Renderizado de Markdown.
- Swagger u OpenAPI.
- Reglas documentales específicas por cliente.
- Reemplazo de la consola.

Cada uno de esos temas, si se aborda, va en su propia SPEC.
