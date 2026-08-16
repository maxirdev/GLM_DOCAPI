# SPEC 15 — Panel web interactivo multicliente

> **Estado:** Borrador
> **Depende de:** SPEC 19
> **Fecha:** 2026-08-16
> **Objetivo:** Crear un panel web local y autocontenido que permita administrar clientes y ambientes, operar el pipeline documental del contexto seleccionado y consultar sus endpoints, documentos y logs sin duplicar la lógica de los scripts PowerShell.

## Por qué existe esta SPEC

La consola definida por la SPEC 19 permite elegir un cliente y un ambiente y ejecutar el pipeline con artefactos aislados. Sigue siendo una interfaz secuencial orientada a terminal y no ofrece una vista integrada para administrar la configuración, seguir trabajos largos, consultar documentos ni explorar los endpoints del contexto activo.

El repositorio también contiene un visor estático de endpoints separado del flujo operativo. Mantener dos interfaces web produciría navegación, estilos y fuentes de datos duplicados. Esta SPEC reemplaza ese visor con una pestaña del panel y conserva los scripts PowerShell como única implementación de exportación, análisis, versionado y publicación.

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
- Pestañas `Estado`, `XPZ`, `Exportar`, `Endpoints`, `Documentación`, `PDF`, `Documentos`, `Logs` y `Configuración`.
- Estado y preflight del contexto activo: cliente, ambiente, KB, herramientas, XPZ disponibles, XPZ activo, cantidades de endpoints/documentos y último review.
- Operaciones vigentes del lanzador: exportar y completar XPZ, seleccionar XPZ, inventariar endpoints, validar, generar documentación, actualizar servicios, convertir PDF y regenerar PDF con confirmación de reinicio.
- Generación particular, múltiple o total de documentos y PDF mediante selección con checkboxes, sin `Out-GridView`.
- Ejecución de cada operación como proceso PowerShell hijo con parámetros contextuales de SPEC 19, log propio y seguimiento por polling.
- Un único trabajo global a la vez; nuevas operaciones mutantes responden HTTP 409 mientras el trabajo no haya terminado.
- Persistencia de `endpoints.json` y `endpoints.md` bajo `<contexto>/documentacion/Endpoints/assets/` para consumo del panel.
- Regeneración automática de esos dos archivos cada vez que cambia el XPZ activo, incluida una exportación que produce un XPZ principal nuevo.
- Publicación conjunta y atómica de `endpoints.json` y `endpoints.md`; nunca reemplazar solo uno.
- Conservación del último inventario válido cuando falla la regeneración, marcado visualmente como obsoleto respecto del XPZ activo y con una acción para reintentar.
- Pestaña Endpoints integrada con metadatos del contexto y XPZ fuente, total confirmado, filtro por nombre o descripción y tabla de nombre, descripción, proceso y endpoint publicado.
- Eliminación de `documentacion/Endpoints/web/` y `documentacion/Endpoints/binary/GenerarVistaHTML.ps1`; no se genera `APIServicios.html` independiente.
- Listado contextual de Markdown y PDF con apertura o descarga segura.
- Listado y lectura contextual de review, diagnóstico IA, validación XPZ, historial de versiones y logs de panel/exportación.
- Resumen visual de `review.json` con estados `OK`, `WARNING`, `ERROR` y `OMITIDO` después de generar o actualizar documentación.
- CRUD de clientes y ambientes desde la pestaña Configuración, además de edición de herramientas globales, `clientesRoot`, `panel.puerto`, package y servicios ignorados.
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

- Autenticación, autorización, HTTPS o acceso desde otras máquinas; el servidor se limita a `127.0.0.1`.
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
- El CRUD siempre valida la configuración completa, no propiedades aisladas.
- Los IDs son editables únicamente durante el alta.
- Eliminar una entrada del JSON nunca elimina su directorio contextual.

### Estado de sesión

```powershell
$sesion = [pscustomobject]@{
    ContextoActivo = $null # ContextId, ClienteId, AmbienteId y rutas resueltas de SPEC 19
    XpzActivo = ''         # Override de sesión o principal más reciente del contexto
    TrabajoActual = $null  # Id, ContextId, Operacion, Estado, Log, Inicio, Progreso y CodigoSalida
    UltimoResumen = $null  # Review del contexto y ejecución más recientes
}
```

Convenciones:

- La sesión pertenece al proceso servidor y es compartida por todas las pestañas abiertas.
- No se selecciona automáticamente el primer contexto configurado.
- Cambiar el contexto descarta el XPZ anterior y activa el principal más reciente del nuevo ambiente.
- Cerrar el servidor descarta contexto, XPZ, trabajo terminado y resumen mantenidos en memoria.
- Un trabajo conserva el `ContextId` con el que fue creado y nunca consulta el contexto mutable de la interfaz para resolver sus rutas.

### Inventario persistido por ambiente

```text
clientes/<clienteId>/<ambienteId>/
└── documentacion/
    └── Endpoints/
        └── assets/
            ├── endpoints.json
            └── endpoints.md
```

`endpoints.json` conserva el contrato actual de endpoints y agrega o confirma en `meta`:

```json
{
  "meta": {
    "contextId": "trunk/testing",
    "clienteId": "trunk",
    "ambienteId": "testing",
    "xpz": "C:/DOCUMENTACIONAPI/clientes/trunk/testing/xpz/APIGLM_20260816.xpz",
    "xpzSha256": "<sha256>",
    "generatedAt": "2026-08-16T12:00:00",
    "totalConfirmed": 120
  },
  "endpoints": []
}
```

El inventario está vigente solo cuando `contextId`, ruta del XPZ y `xpzSha256` coinciden con el contexto y XPZ activos. Una diferencia no elimina los archivos: el panel los muestra como obsoletos y bloquea cualquier presentación que pudiera confundirlos con datos actuales.

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
| `POST /api/validar` | Validar completitud del XPZ activo |
| `POST /api/documentos` | Generar uno, varios o todos los servicios seleccionados |
| `POST /api/actualizar` | Buscar y publicar cambios con control de versiones contextual |
| `POST /api/pdf` | Convertir uno, varios o todos los Markdown seleccionados |
| `POST /api/pdf/regenerar` | Regenerar PDF con confirmación explícita de reinicio |
| `GET /api/trabajos/<id>` | Estado, progreso y últimas líneas del log del trabajo |
| `GET /api/documentos` | Listar Markdown y PDF del contexto activo |
| `GET /api/documentos/<nombre>` | Abrir o descargar un archivo contextual permitido |
| `GET /api/logs` | Listar logs y reportes permitidos del contexto activo |
| `GET /api/logs/<nombre>` | Leer un log contextual permitido |
| `GET /api/configuracion` | Leer configuración y resultado de validación |
| `POST /api/configuracion/clientes` | Crear un cliente con ID nuevo |
| `PUT /api/configuracion/clientes/<id>` | Editar propiedades de un cliente sin cambiar su ID |
| `DELETE /api/configuracion/clientes/<id>` | Quitar un cliente del JSON sin borrar artefactos |
| `POST /api/configuracion/clientes/<id>/ambientes` | Crear un ambiente con ID nuevo |
| `PUT /api/configuracion/clientes/<id>/ambientes/<id>` | Editar un ambiente sin cambiar su ID |
| `DELETE /api/configuracion/clientes/<id>/ambientes/<id>` | Quitar el ambiente del JSON sin borrar artefactos |
| `PUT /api/configuracion/global` | Editar rutas, herramientas, exportación y puerto |

Convenciones de API:

- Todas las respuestas usan JSON UTF-8 y contienen `ok`, `data` o `error` según corresponda.
- Las operaciones que requieren contexto responden HTTP 409 cuando no hay uno activo o existe un trabajo en curso.
- Un recurso inexistente responde 404, una entrada inválida responde 400 y un error interno responde 500 sin exponer stack trace al navegador.
- Las descargas solo resuelven nombres simples dentro de los directorios permitidos; se rechazan rutas absolutas, `..`, separadores alternativos y extensiones no admitidas.
- Al eliminar el contexto activo, la sesión queda sin contexto y exige una selección nueva.

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
- Documentación y PDF permiten selección individual, múltiple y total con conteo visible.
- Configuración usa formularios por cliente y ambiente; las eliminaciones requieren confirmación que informa expresamente que los artefactos se conservarán.
- Los estados vacíos distinguen entre contexto no seleccionado, XPZ inexistente, inventario no generado, documentos inexistentes y logs inexistentes.
- Los toasts de finalización incluyen resultado, contexto y acceso al detalle del trabajo.
- La interfaz funciona en escritorio y móvil, tiene foco visible, contraste suficiente y respeta `prefers-reduced-motion`.

## Plan de implementación

1. Actualizar las pruebas del visor actual para fijar el contrato que se conservará (metadatos, filtro y estados vacíos), crear el esqueleto funcional de `web/index.html`, `web/app.js` y `web/style.css`, y verificarlo con fixtures sin servidor.
2. Crear `binary/ServidorPanelWeb.ps1` e `IniciarPanelWeb.cmd` con `HttpListener` loopback, puerto configurable, servicio de estáticos seguro y endpoints `estado`, `contextos` y `contexto/activar`; el panel ya permite seleccionar y mostrar un contexto de SPEC 19.
3. Implementar la sesión global, selección del XPZ más reciente, listado/override de XPZ y bloqueo del cambio de contexto durante un trabajo; probar cambio de contexto sin persistencia.
4. Implementar el manejador de un único proceso hijo, logs contextuales `panel-<id>.log`, polling, códigos finales, HTTP 409, spinners, progreso y toasts; conectar primero la validación XPZ como operación completa.
5. Adaptar `documentacion/Endpoints/binary/GenerarListaEndpoints.ps1` para publicar atómicamente JSON y Markdown en el directorio contextual con metadatos de contexto, ruta y hash del XPZ; conectar la regeneración automática al cambio/exportación de XPZ y el reintento manual.
6. Integrar la pestaña Endpoints en el panel con la funcionalidad del visor actual, agregar detección de inventario obsoleto y eliminar `documentacion/Endpoints/web/` y `documentacion/Endpoints/binary/GenerarVistaHTML.ps1` junto con sus pruebas específicas reemplazadas.
7. Conectar exportación/completitud, generación/actualización documental y PDF a los scripts existentes mediante parámetros y manifiestos de SPEC 19; agregar selección individual, múltiple y total sin duplicar lógica del pipeline.
8. Implementar documentos, logs, review e historial contextuales con rutas permitidas, descargas seguras, estados vacíos y resumen visual.
9. Implementar el CRUD de configuración con IDs inmutables, validación completa, escritura atómica, confirmación de eliminación y conservación de artefactos; agregar el modo solo lectura para configuración inválida.
10. Completar `test/Run-Tests.ps1` con pruebas HTTP y de frontend sobre dos contextos temporales, seguridad de rutas, concurrencia global, inventarios obsoletos, atomicidad y ausencia de referencias a frameworks/CDN; ejecutar la suite completa.
11. Actualizar `README.md`, `AGENTS.md` y `.gitignore`, verificar escritorio/móvil en Edge y confirmar que consola y panel producen los mismos artefactos para un mismo contexto y XPZ.

## Criterios de aceptación

- [ ] `IniciarPanelWeb.cmd` levanta el servidor en `127.0.0.1:8123` o en el puerto global configurado y abre el navegador.
- [ ] Con el puerto ocupado, el lanzador informa el error, termina con código `1` y no abre una pestaña fallida.
- [ ] El panel no usa frameworks, paquetes, CDN, fuentes remotas ni librerías externas y funciona sin acceso a Internet.
- [ ] El código productivo del panel usa solo Windows PowerShell 5.1, `HttpListener`, HTML, CSS y JavaScript vanilla.
- [ ] Una configuración válida muestra clientes y ambientes, pero no activa ninguno automáticamente.
- [ ] Sin contexto activo, las operaciones permanecen bloqueadas y la interfaz solicita seleccionar cliente y ambiente.
- [ ] Activar un contexto ejecuta su preflight y usa exclusivamente sus rutas resueltas por SPEC 19.
- [ ] Una configuración inválida permite iniciar el panel en modo solo lectura, muestra errores concretos y bloquea CRUD y operaciones.
- [ ] Al cambiar de contexto se activa el XPZ principal más reciente y se descarta el override del contexto anterior.
- [ ] Seleccionar otro XPZ afecta solo la sesión y no modifica `configuracion.json`.
- [ ] No se puede cambiar cliente, ambiente ni XPZ mientras existe un trabajo activo.
- [ ] Todas las pestañas abiertas comparten el mismo contexto, XPZ y trabajo del proceso servidor.
- [ ] El servidor permite un único trabajo global y responde HTTP 409 a una segunda operación mutante.
- [ ] Cada trabajo conserva su `ContextId`, escribe su log bajo el ambiente correcto y ejecuta procesos hijo con rutas contextuales.
- [ ] Polling, spinner, deshabilitado, barra de progreso y toast reflejan el estado real del proceso hijo.
- [ ] Exportar conserva la confirmación previa, los ciclos de completitud y los códigos de salida vigentes.
- [ ] Cambiar o exportar un XPZ lanza automáticamente la regeneración de endpoints para ese contexto.
- [ ] `endpoints.json` y `endpoints.md` se publican juntos bajo `<contexto>/documentacion/Endpoints/assets/`.
- [ ] El inventario persistido identifica `contextId`, XPZ, hash, fecha y total confirmado.
- [ ] Un fallo de regeneración conserva byte a byte el último par válido y lo muestra como `OBSOLETO` respecto del XPZ activo.
- [ ] Reintentar una regeneración exitosa reemplaza ambos archivos y elimina el estado obsoleto.
- [ ] La pestaña Endpoints filtra por nombre o descripción y muestra nombre, descripción, proceso y endpoint del contexto activo.
- [ ] `documentacion/Endpoints/web/` y `GenerarVistaHTML.ps1` dejan de existir y el pipeline no genera `APIServicios.html`.
- [ ] Generar documentación permite elegir uno, varios o todos los servicios sin `Out-GridView`.
- [ ] Actualizar servicios respeta control, historial, locks, versiones y transaccionalidad del ambiente activo.
- [ ] Generar PDF permite elegir uno, varios o todos los Markdown sin eliminar sus fuentes.
- [ ] Regenerar PDF exige confirmación explícita antes de reiniciar el versionado del ambiente activo.
- [ ] El resumen posterior muestra `OK`, `WARNING`, `ERROR` y `OMITIDO` desde el review contextual correcto.
- [ ] Documentos lista y descarga únicamente `.md` y `.pdf` del contexto activo.
- [ ] Logs lista y lee únicamente archivos permitidos del contexto activo.
- [ ] Rutas con `..`, absolutas, separadores alternativos o extensiones no permitidas son rechazadas sin leer archivos externos.
- [ ] El CRUD crea clientes y ambientes con IDs válidos y rechaza IDs duplicados o rutas de KB duplicadas según SPEC 19.
- [ ] El CRUD no permite cambiar el ID de una entrada existente.
- [ ] Cada guardado valida la configuración completa y la escribe atómicamente.
- [ ] Un guardado inválido o fallido conserva byte a byte el `configuracion.json` anterior.
- [ ] Eliminar un cliente o ambiente exige confirmación, quita solo la entrada del JSON y conserva intacto su árbol contextual.
- [ ] Eliminar el contexto activo limpia la selección de sesión y no activa otro automáticamente.
- [ ] La interfaz funciona en escritorio y móvil, ofrece tema claro/oscuro, foco visible y respeta `prefers-reduced-motion`.
- [ ] Los puntos de entrada de consola siguen funcionando y producen los mismos artefactos que el panel para el mismo contexto y XPZ.
- [ ] `test/Run-Tests.ps1` cubre API, sesión, seguridad, CRUD, trabajos e inventarios sobre al menos dos contextos y termina con código `0`.
- [ ] `README.md`, `AGENTS.md` y `.gitignore` describen el panel unificado y no presentan el visor estático como interfaz vigente.

## Decisiones

- **Sí:** SPEC 19 permanece como contrato del pipeline y esta SPEC agrega únicamente la interfaz web y la persistencia contextual requerida por Endpoints.
- **Sí:** panel único para operación y consulta de endpoints. Evita mantener dos aplicaciones web y dos lenguajes visuales.
- **Sí:** `HttpListener` y frontend vanilla. El panel no introduce dependencias externas ni requiere Internet.
- **Sí:** selector global obligatorio. Todas las pestañas observan el mismo contexto y reducen el riesgo de operar sobre otro ambiente.
- **Sí:** sesión única del servidor. Es coherente con un servicio loopback para un operador local.
- **Sí:** un único trabajo global. Simplifica el seguimiento y evita que una pestaña cambie el estado visible mientras otra operación muta artefactos.
- **Sí:** bloquear cambios de contexto durante un trabajo. El resultado y el progreso siempre se atribuyen al contexto que inició la operación.
- **Sí:** XPZ más reciente al cambiar de contexto y override no persistido. Coincide con la consola de SPEC 19.
- **Sí:** inventario persistido por ambiente para la pestaña Endpoints. El inventario efímero del pipeline de SPEC 19 mantiene su finalidad transaccional independiente.
- **Sí:** regenerar endpoints con cada cambio de XPZ. La vista intenta mantenerse alineada con la fuente activa sin exigir una acción adicional.
- **Sí:** conservar y marcar obsoleto ante error. Un fallo no destruye el último inventario válido ni lo presenta como actual.
- **Sí:** CRUD completo con IDs inmutables. Permite administrar contextos sin convertir un cambio de identificador en una migración de artefactos.
- **Sí:** escritura atómica y validación total del JSON. No se permiten estados parcialmente válidos.
- **Sí:** eliminar configuración sin eliminar datos. La baja administrativa no es una operación destructiva sobre documentos, versiones o XPZ.
- **Sí:** modo solo lectura ante configuración inválida. La corrección se realiza fuera del panel para no intentar mutar un documento cuyo modelo no pudo establecerse.
- **No:** mantener sincronizado un `APIServicios.html`. La pestaña Endpoints consume directamente la API contextual.
- **No:** persistir contexto o XPZ de sesión. Cada arranque exige una selección consciente.
- **No:** múltiples trabajos por ambiente. Los locks de SPEC 19 siguen protegiendo el pipeline, pero el panel conserva una cola efectiva de tamaño uno.
- **No:** renderizar Markdown. Los archivos se abren o descargan sin agregar un motor de renderizado.
- **No:** reemplazar la consola. Ambos puntos de entrada invocan la misma lógica compartida.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Una pestaña cambia el contexto mientras otra observa un trabajo | Sesión global visible, selectores bloqueados durante trabajos y `ContextId` inmutable dentro de cada trabajo. |
| El inventario queda desalineado después de cambiar el XPZ | Regeneración automática y validación por contexto, ruta y SHA256 del XPZ. |
| Falla la regeneración y se pierde la última vista útil | Publicación conjunta y atómica; se conserva el par anterior y se marca `OBSOLETO`. |
| El CRUD corrompe o deja parcialmente válida la configuración | Validación completa, escritura atómica y conservación byte a byte ante cualquier fallo. |
| Eliminar un contexto destruye versiones o documentos | La API elimina solo la entrada del JSON; nunca ejecuta borrado sobre el árbol contextual. |
| Path traversal permite leer archivos del equipo | Nombres simples, raíces canónicas contextuales, extensiones permitidas y rechazo explícito de rutas absolutas o segmentos `..`. |
| Un proceso largo queda vivo al cerrar la pestaña | El trabajo pertenece al servidor y al proceso hijo; al recargar, el navegador recupera su estado por polling. |
| El servidor se cierra mientras hay un proceso hijo | El log contextual y los artefactos transaccionales permiten diagnosticarlo; el pipeline conserva los contratos de fallo de SPEC 19. |
| Puerto ocupado o configuración inválida impiden operar | Error explícito de puerto; configuración inválida abre la interfaz en modo solo lectura usando el puerto predeterminado cuando sea necesario. |
| Eliminación del visor anterior causa regresión de consulta | La pestaña Endpoints conserva filtro, metadatos y estados vacíos antes de retirar los archivos anteriores. |
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
