# SPEC 15 — Panel web interactivo del lanzador

> **Estado:** Aprobado
> **Depende de:** SPEC 13, SPEC 14
> **Fecha:** 2026-08-13
> **Objetivo:** Crear un panel web local servido por `HttpListener` que exponga en el navegador todas las operaciones del lanzador unificado, coexistiendo con los `.cmd`/`.ps1` actuales.

## Por qué existe esta SPEC

La consola (`GenerarDocumentosGLM.cmd`, `GenerarDocumento.ps1`, `GenerarPdfServicios.ps1`) es la única interfaz operativa. El repositorio ya tiene un precedente web de solo lectura (`documentacion/Endpoints/web/`). Esta SPEC lo convierte en un panel interactivo: mismas operaciones, misma lógica (los scripts actuales siguen siendo la fuente única), distinta presentación.

## Alcance

**Incluido:**

- `IniciarPanelWeb.cmd` en la raíz que levanta el servidor y abre el navegador en `http://127.0.0.1:<puerto>`.
- `binary/ServidorPanelWeb.ps1` con `HttpListener` (loopback) que sirve estáticos desde `web/` y expone una API JSON.
- `web/index.html`, `web/app.js`, `web/style.css` — panel con pestañas (Estado, XPZ, Exportar, Documentación, PDF, Documentos, Logs, Configuración), reutilizando los tokens de diseño del visor actual con una capa de interfaz moderna (ver [Interfaz y estados visuales](#interfaz-y-estados-visuales)).
- Las operaciones del lanzador unificado: estado/preflight, seleccionar XPZ activo (memoria del servidor), exportar y completar XPZ (con confirmación de KB completa y ciclo de 5 iteraciones), inventario, validación, generación de documentos (particular/varios/todos), PDF (particular/varios/todos), listado de documentos con apertura/descarga de `.md` y `.pdf`, lectura de logs y edición de `configuracion.json` por formulario.
- Resumen de `review.json` (OK/WARNING/ERROR/OMITIDO) mostrado en el panel tras generar documentación.
- Ejecución de cada operación como proceso hijo con log propio en `Logs/panel-<id>.log` y progreso por polling; una operación a la vez.
- Parámetros retrocompatibles: `-Seleccionados <lista>` en `GenerarDocumento.ps1` y `GenerarPdfServicios.ps1`, y `-Confirmado` en `EjecutarExportacionGLM.ps1`.
- Campo opcional `panel.puerto` en `configuracion.json` (default 8123).

**Fuera de alcance (para futuras SPEC):**

- Autenticación o acceso remoto; el panel se limita a loopback.
- Renderizado Markdown en el navegador; los `.md` solo se abren o descargan.
- Modificar las reglas de análisis, redacción o la plantilla normativa.
- Eliminar o rediseñar el visor de endpoints ni los `.cmd` actuales.
- Persistir la selección de XPZ entre reinicios del servidor.
- Swagger u otra especificación de los servicios documentados (se evaluará en una SPEC futura).

## Modelo de datos

`configuracion.json` agrega un campo opcional:

```json
{
  "panel": { "puerto": 8123 }
}
```

Estado de sesión en `ServidorPanelWeb.ps1` (memoria):

```powershell
$sesion = [pscustomobject]@{
  XpzActivo     = ''          # ruta completa del XPZ de sesión
  TrabajoActual = $null       # { Id, Operacion, Estado, Log, Inicio }
  UltimoResumen = $null       # review.json parseado para el panel
}
```

API JSON del servidor:

| Método y ruta | Acción |
|---|---|
| `GET /` y estáticos `web/*` | Interfaz del panel |
| `GET /api/estado` | Preflight (config, XPZ disponibles, herramientas, último review) |
| `GET /api/xpz` / `POST /api/xpz/activar` | Listar principales / fijar XPZ de sesión |
| `POST /api/exportar` | `EjecutarExportacionGLM.ps1 -Confirmado` (body: `confirmarKB`) |
| `POST /api/inventario` | `GenerarListaEndpoints.ps1` |
| `POST /api/validar` | `ValidarXPZ.ps1` |
| `POST /api/documentos` | `GenerarDocumento.ps1` con `-Seleccionados` o `-Todos` |
| `POST /api/pdf` | `GenerarPdfServicios.ps1` con `-Seleccionados` o `-Todos` |
| `GET /api/trabajos/<id>` | Estado + últimas líneas del log del proceso hijo |
| `GET /api/logs` | Listado y contenido de `Logs/*-review.json`, `-errores.txt`, `-diagnostico-ia.json`, `-validacion-xpz.json`, `panel-*.log` |
| `GET/PUT /api/configuracion` | Leer / guardar todos los campos del JSON vía formulario |
| `GET /api/servicios/<nombre>.md` / `.pdf` | Abrir o descargar |

Convenciones:

- Cada operación lanza un proceso `powershell.exe` hijo con salida redirigida a `Logs/panel-<id>.log`; el navegador hace polling a `/api/trabajos/<id>`.
- Si ya hay un trabajo en curso, el servidor rechaza nuevas operaciones con HTTP 409.
- Las rutas servidas por `/api/servicios` se resuelven únicamente dentro de `documentacion/servicios`; las de `/api/logs` dentro de `Logs` (sin path traversal).

## Interfaz y estados visuales

Todos los componentes se implementan con CSS/JS vanilla (sin frameworks, sin CDN, sin imágenes): spinners y barras se dibujan con CSS puro. Se conserva la paleta corporativa del visor actual (`--color-primario: #1e6fff`, tema claro/oscuro) y se pulen layout y componentes.

**Botones con estado de carga (spinner loading buttons):**

- Cualquier botón de operación (Exportar, Inventario, Validar, Generar documentos, Generar PDF, Guardar configuración) expone un estado `cargando`: `disabled`, spinner embebido (giro CSS con `::after` o `<span class="spinner">`) y etiqueta cambiada a `Procesando…`.
- Al lanzar una operación, el botón entra en `cargando`; sale cuando `/api/trabajos/<id>` reporta estado final (`OK`/`ERROR`).
- Mientras hay un trabajo en curso, todos los botones de operación quedan deshabilitados; el servidor además responde 409 ante nuevas operaciones.

**Barra de progreso del trabajo activo:**

- Sección fija "Trabajo en curso" con el nombre de la operación, el estado y una barra de progreso.
- Barra indeterminada (animada) para exportaciones largas; barra determinada (porcentaje) para operaciones con total conocido (documentos, PDF), calculado por línea de log de resultado o contando avance.
- Autorefresh del estado cada 1–2 s mientras el trabajo está activo; se detiene al llegar al estado final.

**Resultados y feedback:**

- Badges/pills de estado OK (verde), WARNING (ámbar), ERROR (rojo), OMITIDO (gris) en el resumen de review y en listas de servicios.
- Toasts al finalizar cada operación: éxito o error, con el conteo resumido y acceso al detalle.
- Cards en el dashboard de Estado (XPZ activo, herramientas, últimos logs) en lugar de tablas planas.
- Empty states ("No hay documentos aún", "Sin logs disponibles") en las pestañas correspondientes.
- Microdetalles: sombras suaves, esquinas redondeadas, foco visible en formularios y botones, `transition` de estados y respeto de `prefers-reduced-motion`.

## Plan de implementación

1. Crear `web/index.html`, `web/app.js`, `web/style.css` con la estructura de pestañas, el tema claro/oscuro del visor actual y los componentes base de la interfaz moderna (cards, badges, toasts, empty states).
2. Crear `binary/ServidorPanelWeb.ps1` con `HttpListener` en `127.0.0.1:<puerto>`, servido de estáticos y endpoints de estado/XPZ/configuración (sin procesos hijo todavía).
3. Agregar el manejador de trabajos: lanzar proceso hijo, escribir `Logs/panel-<id>.log`, estado por polling y bloqueo de una operación a la vez.
4. Implementar los estados de carga: spinner en botones, deshabilitado global mientras hay trabajo, barra de progreso (indeterminada y determinada) y toasts de fin de operación.
5. Conectar las operaciones de inventario y validación al manejador de trabajos.
6. Agregar `-Seleccionados <FQN,...>` a `GenerarDocumento.ps1` y conectar la generación de documentos (particular/varios/todos) y el resumen de review en el panel con badges de estado.
7. Agregar `-Seleccionados <nombre,...>` a `GenerarPdfServicios.ps1` y conectar la conversión PDF.
8. Agregar `-Confirmado` a `EjecutarExportacionGLM.ps1` y conectar exportar/completar con confirmación de KB completa.
9. Crear `IniciarPanelWeb.cmd` que valida el puerto, levanta el servidor y abre el navegador; agregar `panel.puerto` a la configuración y su lectura.
10. Revisar contra las listas de `analisisXPZ.md`/`reglasEditoriales.md` la coherencia de nombres y estados del panel.

Cada paso deja el panel funcional para el siguiente; la consola no se rompe porque los parámetros nuevos son opcionales.

## Criterios de aceptación

- [ ] `IniciarPanelWeb.cmd` levanta el servidor y abre el navegador en `http://127.0.0.1:8123` (o el puerto de `panel.puerto`).
- [ ] Con el puerto ocupado, el `.cmd` informa el error y no abre una pestaña fallida.
- [ ] El panel muestra el estado del preflight (config, XPZ disponibles, herramientas) sin ejecutar procesos.
- [ ] La pestaña XPZ lista los principales con nombre, fecha y tag ÚLTIMO (reutiliza `ListarXPZPrincipales.ps1`).
- [ ] Al activar un XPZ, las operaciones siguientes usan ese XPZ de sesión sin modificar `configuracion.json`.
- [ ] Exportar lanza el flujo de `EjecutarExportacionGLM.ps1` con sus 5 ciclos; con KB completa pide confirmación en el panel antes de arrancar.
- [ ] El panel muestra en vivo las líneas del log del proceso hijo y el estado del trabajo.
- [ ] Al lanzar una operación, su botón muestra el spinner de carga y la etiqueta `Procesando…`, y se deshabilita hasta el estado final.
- [ ] Mientras hay un trabajo en curso, todos los botones de operación quedan deshabilitados; el servidor responde 409 ante nuevas operaciones.
- [ ] El panel muestra una barra de progreso indeterminada para exportaciones y determinada para documentos/PDF con total conocido.
- [ ] Al finalizar cada operación se muestra un toast de éxito o error con el conteo resumido.
- [ ] El resumen de review y las listas de servicios usan badges de estado OK (verde), WARNING (ámbar), ERROR (rojo) y OMITIDO (gris).
- [ ] Las pestañas sin contenido muestran un empty state ("No hay documentos aún", "Sin logs disponibles").
- [ ] La interfaz respeta `prefers-reduced-motion` para spinners y transiciones.
- [ ] Inventario y validación regeneran `endpoints.json` y `Logs/*-validacion-xpz.json` como hoy.
- [ ] Generar documentación permite elegir un servicio, varios (checkboxes) o todos; la selección múltiple no requiere `Out-GridView`.
- [ ] Tras generar documentación, el panel muestra el resumen OK/WARNING/ERROR/OMITIDO y la lista de estados leyendo `review.json`.
- [ ] La conversión PDF permite elegir uno, varios o todos los `.md` y conserva los archivos fuente.
- [ ] La pestaña Documentos lista `.md`/`.pdf` de `documentacion/servicios` y permite abrirlos/descargarlos.
- [ ] La pestaña Logs lista y muestra `review.json`, `errores.txt`, `diagnostico-ia.json` y `validacion-xpz.json`.
- [ ] El botón Configuración abre un formulario que edita todos los campos del JSON y guarda JSON válido en `configuracion.json`.
- [ ] Los `.cmd` y `.ps1` actuales siguen funcionando sin cambios en su interfaz.

## Decisiones

- **Sí:** `HttpListener` de PowerShell 5.1 para el servidor. Sin dependencias, sin frameworks, sin CDN.
- **Sí:** proceso hijo por operación con log propio y polling. Un export de 20-30 min no bloquea el navegador.
- **Sí:** una operación a la vez, igual que la consola. Evita exportaciones/validaciones concurrentes sobre la misma KB.
- **Sí:** XPZ activo en memoria del servidor, igual que la sesión batch de SPEC 14.
- **Sí:** `.md` solo para abrir/descargar; no se renderiza Markdown en el navegador.
- **Sí:** el form de configuración edita todos los campos, con validación de existencia en las rutas.
- **Sí:** `web/` en la raíz como núcleo de toda la funcionalidad web, separado del visor de endpoints.
- **Sí:** puerto por defecto 8123, configurable en `panel.puerto` de `configuracion.json`.
- **Sí:** spinners, barra de progreso y toasts con CSS/JS vanilla; se conserva la paleta corporativa y se pulen layout y componentes.
- **No:** autenticación ni acceso fuera de loopback.
- **No:** persistir la selección de XPZ entre reinicios del servidor.
- **No:** reemplazar los `.cmd`/`.ps1` actuales; la consola sigue siendo válida.
- **No:** renderizado Markdown ni exportación selectiva como botón separado.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Exportación larga y cierre de pestaña | El trabajo vive en el proceso hijo; el panel puede recargarse y reconsultar `/api/trabajos/<id>`. |
| Puerto 8123 ocupado | El `.cmd` valida y informa el error; el puerto es configurable. |
| Proceso hijo con salida no UTF-8 | Los logs se escriben con `System.Text.UTF8Encoding(false)` y el polling lee el mismo archivo. |
| Barra determinada imprecisa sin total conocido | Se usa barra indeterminada por defecto y determinada solo cuando la operación reporta un total. |
| El form de configuración permite rutas inválidas | Validación de existencia y aviso antes de guardar; el preflight sigue reportando fallas. |
| Interferencia con la KB durante exportación | Bloqueo de una operación a la vez y confirmación explícita de KB completa. |

## Lo que **no** incluye esta SPEC

- Autenticación o acceso remoto.
- Renderizado de Markdown en el navegador.
- Exportación selectiva como operación suelta.
- Persistencia del XPZ activo entre sesiones del servidor.
- Cambios en las reglas de análisis/redacción ni en el visor de endpoints.
- Reemplazo o eliminación de los puntos de entrada de consola.
- Swagger u otra especificación de los servicios documentados.
