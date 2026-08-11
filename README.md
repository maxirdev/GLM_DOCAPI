# Documentación de servicios APIGLM

Este repositorio reúne la metodología y los documentos generados para los servicios HTTP de APIGLM. Su objetivo es transformar la información técnica exportada desde GeneXus en documentación uniforme, verificable y comprensible para quienes necesitan consumir los servicios.

La fuente principal es el XPZ indicado en `configuracion.json`. El archivo contiene el XML exportado de la base de conocimiento GeneXus: procedimientos, código fuente, reglas, variables, estructuras de datos, dominios y atributos. La documentación se obtiene de esa evidencia; no se completa por semejanza con otros servicios ni por suposiciones.

## Estado actual

| Proceso | Estado | Comportamiento actual |
|---|---|---|
| Exportación del XPZ | Operativo | `exportarXPZ.cmd` abre la KB configurada, exporta `Module:APIGLM` con referencias mínimas y crea un XPZ fechado. La consola conserva una lista de cinco tareas y marca cada una como `OK` o `ERROR`, dejando un indicador animado únicamente en la tarea en curso. |
| Inventario de endpoints | Operativo | Lee el XPZ configurado, localiza `APIGLM.APIGLMMain`, resuelve sus llamadas activas y genera `endpoints.json` y `endpoints.md`. |
| Visor web | Operativo | Consume `endpoints.json`, incorpora el `cliente` definido en la configuración y genera `APIServicios.html`. |
| Documentación de servicios | Operativo con revisión | Permite procesar un servicio, una selección múltiple o todo el inventario. Expande SDT recursivos de forma segura, sigue flujos reales/formales y utiliza evidencia global por identidad exacta de SDT y ruta interna. Cada resultado queda clasificado como `OK`, `WARNING`, `ERROR` u `OMITIDO`. |
| Diagnósticos | Operativo | Una ejecución completada del generador produce `review.json`; los `WARNING`/`ERROR`/`OMITIDO` pueden generar `errores.txt` y las excepciones generan `diagnostico-ia.json` en `Logs/`. |
| Grafo y detección de cambios | No implementado | El grafo de dependencias, la detección automática de cambios y `controlVersiones.json` no forman parte de los procesos disponibles. |
| Artefactos generados | Bajo demanda | El inventario, el visor, los documentos de servicios y los logs se crean al ejecutar los generadores; no se presupone que existan en una copia nueva. |

Los valores `xpz`, `packagename`, `cliente` y `serviciosIgnorados` se leen de `configuracion.json` y pueden cambiar entre ejecuciones. La cantidad de endpoints confirmados se calcula desde el XPZ activo: una diferencia respecto del conteo de referencia del script se informa como advertencia, pero no reemplaza el total calculado. Las cantidades de resultados `OK`, `WARNING`, `ERROR` y `OMITIDO` dependen de la evidencia de cada export.

Hay dos mecanismos de deduplicación distintos según el proceso:

- **Inventario**: se conserva la primera aparición de cada FQN; las repeticiones posteriores del mismo FQN se omiten silenciosamente. Los candidatos no resueltos se registran como `unresolved`.
- **Generador de servicios**: la colisión se evalúa por el nombre local del documento (último segmento del FQN en minúsculas). Si dos wrappers producirían el mismo `<wrapper>.md`, gana el primero según el orden del inventario y el resto queda como `WARNING` con nombre local duplicado.

## Inicio rápido

### Requisitos

- Windows con Windows PowerShell 5.1.
- GeneXus 18 y MSBuild de 32 bits únicamente si se utilizará la exportación automática de la KB.
- Un XPZ válido dentro de `xpz/` o en una ruta accesible.
- Un archivo `configuracion.json` en la raíz del repositorio.
- `Out-GridView` disponible únicamente si se utilizará la selección múltiple del modo 2.

El repositorio auxiliar `GeneXus-XPZ-Skills-main/` es opcional para el inventario. Su catálogo de tipos solo se usa para confirmar el GUID de Procedure: si el archivo no existe, no puede leerse, su JSON es inválido o no contiene `types.Procedure.objectTypeGuid`, el script utiliza el GUID conocido de Procedure sin detenerse.

### 0. Exportar el módulo APIGLM (opcional)

Si el XPZ debe obtenerse directamente desde la Knowledge Base local:

```powershell
.\exportarXPZ.cmd
```

El comando valida las rutas requeridas, exige que GeneXus esté cerrado y ejecuta MSBuild en una ventana oculta. La consola muestra el avance como una lista persistente:

```text
[1/5] Iniciando MSBuild ... OK
[2/5] Abriendo la Knowledge Base ... OK
[3/5] Exportando APIGLM y sus referencias ... |
```

La tarea activa utiliza un indicador `| / - \`; las tareas finalizadas permanecen visibles como `OK` o `ERROR` y las siguientes aparecen cuando comienzan. La duración no se estima ni limita artificialmente.

Salidas:

- `xpz/SEGUROS_COMERCIAL_APIGLM_<marca>.xpz`;
- `Logs/exportarXPZ_<marca>.log`.

Para automatización puede usarse `exportarXPZ.cmd --no-pause`. Las rutas de GeneXus y de la KB están declaradas actualmente en el propio `.cmd`; deben revisarse antes de usarlo en otro equipo.

### 1. Configurar la ejecución

Completar `configuracion.json` con los valores correspondientes al XPZ que se analizará:

```json
{
  "xpz": "xpz/<archivo>.xpz",
  "packagename": "<prefijo-publicado>.",
  "cliente": "<cliente>",
  "serviciosIgnorados": []
}
```

`packagename` no se obtiene del XPZ: debe corresponder al package publicado de ese export. `cliente` se utiliza como etiqueta en el visor. `serviciosIgnorados` es una lista de FQN referenciados en el inventario que no se documentan: al abrir la consola se informan y se excluyen del procesamiento con estado `OMITIDO` (ni ERROR ni documento; ver [Servicios ignorados](#servicios-ignorados)).

#### Parámetros avanzados y overrides

Los scripts PowerShell aceptan parámetros que los `.cmd` no exponen. Al invocar directamente el `.ps1` se puede:

- inventario (`GenerarListaEndpoints.ps1`): `-XpzPath`, `-CatalogPath`, `-OutputDirectory`, `-ConfigPath` y `-ExpectedCount` (conteo de referencia, por defecto `135`);
- visor (`GenerarVistaHTML.ps1`): `-InputDirectory`, `-OutputPath` y `-ConfigPath`;
- generador de servicios (`GenerarDocumento.ps1`): `-ConfigPath` y `-XpzPath`.

Restricciones de los overrides:

- La ruta relativa de `xpz` de `configuracion.json` siempre se resuelve contra la raíz de este repositorio, no contra el directorio del JSON alternativo (`-ConfigPath` no cambia la base de resolución).
- `-XpzPath` reemplaza solo el XPZ, pero `packagename` y `cliente` se siguen tomando de `configuracion.json`; si se usan juntos, deben ser coherentes para no mezclar un XPZ de otro cliente con el package del configurado.
- El XPZ declarado en `configuracion.json` debe existir igualmente: `Cargar-Configuracion` lo resuelve antes de aplicar cualquier override.
- `-OutputPath` del visor no copia `app.js` ni `style.css`: el HTML generado debe quedar junto a esos archivos (o copiarlos manualmente) para conservar el estilo y la lógica.

### 2. Generar el inventario y el visor

Desde la raíz del repositorio:

```powershell
.\GenerarDocumentacion.cmd
```

La ejecución informa el conteo calculado y los candidatos que no pudieron incorporarse. Sus salidas son:

- `documentacion/Endpoints/assets/endpoints.json`;
- `documentacion/Endpoints/assets/endpoints.md`;
- `documentacion/Endpoints/web/APIServicios.html`.

El visor se abre localmente con doble clic sobre `APIServicios.html`; no requiere servidor ni conexión de red.

> **Conteo de referencia.** `ExpectedCount` tiene un valor predeterminado de `135` (histórico del inventario original) que no se deriva del XPZ. Una diferencia respecto del total calculado se informa como advertencia pero no invalida el inventario ni cambia el código de salida; puede sobrescribirse con `-ExpectedCount`.
>
> **Advertencias y código de salida.** El script devuelve 1 solo ante una excepción. Un conteo distinto del esperado, candidatos no resueltos u objetos rechazados siguen devolviendo 0.
>
> **Ejecución interactiva y automatizada.** `GenerarDocumentacion.cmd` pausa al terminar en éxito y sale inmediatamente ante error; `ObtenerEndpoints.cmd` pausa en ambos casos. Para automatización o CI conviene invocar directamente los `.ps1`, que no pausan.

### 3. Generar documentación de servicios

Después de generar el inventario:

```powershell
.\GenerarDocumentoServicio.cmd
```

El menú permite seleccionar un servicio, varios mediante `Out-GridView` o todo el inventario. Los documentos se escriben en `documentacion/servicios/`; los exitosos sobrescriben el archivo anterior y un servicio que termina en `ERROR` elimina su documento previo (ver [Estados, limpieza, logs y códigos de salida](#estados-limpieza-logs-y-códigos-de-salida)).

Al finalizar se muestra un resumen con cantidades dinámicas de `OK`, `WARNING`, `ERROR` y `OMITIDO`. Una ejecución completada escribe `Logs/<marca>-review.json`; si hay incidencias también escribe `Logs/<marca>-errores.txt` y, si hay excepciones, `Logs/<marca>-diagnostico-ia.json`. Si al menos un servicio termina en `ERROR`, el lote devuelve un código de salida distinto de cero aunque otros documentos se hayan generado correctamente; `WARNING` y `OMITIDO` devuelven 0.

## Visión general del proceso

El proceso tiene dos etapas: primero se obtiene el inventario de endpoints activos y después se analiza individualmente cada servicio.

```text
XPZ
  └─ APIGLM.APIGLMMain
       └─ wrappers HTTP activos
            └─ inventario de endpoints
                 └─ análisis del programa principal
                       └─ documentación técnica
                           └─ documentación del servicio
```

El inventario indica qué servicios están activos. El análisis individual determina cómo se invoca cada uno, qué datos recibe, qué devuelve y qué errores HTTP puede generar.

## Generación automática del inventario y el visor

El inventario y el visor web se regeneran con un orquestador ubicado en la raíz del repositorio:

| Script | Ubicación | Función |
|---|---|---|
| [GenerarDocumentacion.cmd](GenerarDocumentacion.cmd) | raíz del repo | Ejecuta en secuencia los dos scripts siguientes y termina con `%ERRORLEVEL%` ≠ 0 si alguno falla. |
| `GenerarListaEndpoints.ps1` | `documentacion/Endpoints/binary/` | Lee el XPZ configurado y el catálogo de tipos de GeneXus, extrae las llamadas `WS...` activas de `APIGLM.APIGLMMain`, valida que cada objeto sea Procedure con `IsMain=True` y `CALL_PROTOCOL=HTTP`, y escribe `endpoints.json` y `endpoints.md`. |
| `GenerarVistaHTML.ps1` | `documentacion/Endpoints/binary/` | Lee `endpoints.json`, agrega o reemplaza `meta.cliente` con el valor de la configuración, vuelve a serializar el JSON (escapando `</script>`) en `<script type="application/json">` y escribe `APIServicios.html`. No reabre ni valida el XPZ. |
| `ObtenerEndpoints.cmd` | `documentacion/Endpoints/binary/` | Genera únicamente el inventario (sin visor). |

Los archivos generados (`endpoints.json`, `endpoints.md` y `APIServicios.html`) están en `.gitignore`: se producen en cada ejecución y no se versionan. Para regenerar todo basta ejecutar `GenerarDocumentacion.cmd` en la raíz del repositorio.

### Visor web

El visor resultante (`documentacion/Endpoints/web/APIServicios.html`) se abre con doble clic (`file://`), sin servidor, frameworks ni CDN:

- encabezado con el cliente definido en `configuracion.json`, la fecha de `meta.generatedAt` en formato `DD/MM/AAAA HH:mm` y el total de `meta.totalConfirmed`;
- grilla con una fila por endpoint, con Nombre y Descripción alineadas a la izquierda;
- filtro en vivo por Nombre o Descripción, sin distinguir mayúsculas ni acentos;
- toggle de tema claro/oscuro con persistencia en `localStorage` (por defecto según `prefers-color-scheme`).

Consistencia y limitaciones:

- el visor **no valida** el esquema de `endpoints.json` (exige existencia y sintaxis JSON, pero no que existan `meta`, `generatedAt`, `totalConfirmed` ni que `nombre`/`descripcion` sean cadenas);
- fuera del orquestador, puede generar un visor a partir de un inventario desactualizado o de otro XPZ: conviene regenerar primero el inventario;
- si la configuración falla al cargar, el visor continúa con `cliente` vacío;
- el HTML incrusta el JSON con `meta.cliente` agregado, pero el archivo `endpoints.json` original no se modifica;
- la grilla muestra solo Nombre y Descripción; `proceso`, `endpoint` y los candidatos `unresolved` no se presentan en la interfaz.

## Generador automático de documentación de servicios

Además del inventario, existe un pipeline en PowerShell 5.1 que genera la documentación de uno o más servicios implementando en código las reglas definidas en `analisisXPZ.md` → `reglasEditoriales.md` → `templateDoc.md`. Se invoca con `GenerarDocumentoServicio.cmd` desde la raíz y presenta un menú interactivo con tres modos:

| Opción | Descripción |
|---|---|
| 1 — Servicio particular | Lista numerada de endpoints, elige uno y genera su documentación. |
| 2 — Múltiples servicios | Abre `Out-GridView` para seleccionar varios con Ctrl+Click. |
| 3 — TODOS | Genera documentación para todos los endpoints del inventario. |

Los documentos normativos no se leen durante la generación: el markdown está codificado en `RedactarDocumento.ps1`. Cambiar `analisisXPZ.md`, `reglasEditoriales.md` o `templateDoc.md` no modifica automáticamente la salida; scripts y normativa deben mantenerse sincronizados manualmente.

En los modos 2 y 3 se muestra una barra de progreso global y, al completar cada servicio, una línea con su estado (`OK`, `WARNING` o `ERROR`). Cada ejecución completada genera `review.json`; cuando hay incidencias también genera `errores.txt` y, si existe al menos un error, `diagnostico-ia.json` con la ubicación, la sentencia y el stack trace necesarios para analizarlo.

### Selección, ignorados y duplicados

La selección trabaja sobre el inventario **después** de retirar los servicios de `serviciosIgnorados`: esos FQN no aparecen en la lista numerada del modo 1, en el `Out-GridView` del modo 2 ni en el lote del modo 3. Al abrir la consola se informan como `[IGNORADO]` (indicando además si el FQN no está en el inventario).

Aunque los ignorados no participan de la selección, **todos** los que estén presentes en el inventario se incorporan al `review.json` de cualquier ejecución completada con estado `OMITIDO`, incluso si se generó un único servicio no relacionado. Por eso `ejecucion.seleccionados` puede no incluir a un FQN que sí aparece en `servicios` con estado `OMITIDO`.

Los duplicados se resuelven por el nombre local del documento (último segmento del FQN en minúsculas):

- si dos wrappers producirían el mismo `<wrapper>.md`, gana el primero según el orden de la selección (en el modo 3, el orden del inventario);
- el resto se omite y se registra como `WARNING` con el mensaje `Nombre local duplicado '<local>'. El ganador es '<ganador>'.`;
- un duplicado no genera documento y no cambia el código de salida;
- la omisión por colisión no elimina un archivo preexistente del FQN que perdió.

### Servicios ignorados

`configuracion.json` admite el campo opcional `serviciosIgnorados`: una lista de FQN que están referenciados en el inventario pero que no deben documentarse. Los servicios omitidos:

- no participan de la selección (modos 1, 2 y 3);
- no generan ni sobrescriben un documento;
- se registran en `review.json` con estado `OMITIDO`;
- no cuentan como `ERROR` y no cambian el código de salida;
- **no eliminan** un `.md` generado por una ejecución anterior: solo se deja de producirlo. Si se quiere quitar el archivo, debe borrarse manualmente o moverse el FQN fuera de la lista.

Los FQN de la lista que no estén en el inventario no interrumpen la ejecución: solo se informan como `[IGNORADO] (no esta en el inventario)`.

### Pipeline del generador

Cada documento se produce en tres etapas, implementadas como módulos PowerShell independientes:

| Módulo | Función |
|---|---|
| `AnalizarServicio.ps1` | Abre el XPZ como ZIP de solo lectura, localiza wrapper y programa principal, resuelve GET/POST, tipifica campos, expande SDT —incluidas autorreferencias—, sigue argumentos reales y parámetros formales, consulta evidencia global por `SDT FQN + ruta`, determina obligatoriedad, resuelve salidas estructuradas, delegadas, textuales o binarias, y obtiene errores HTTP y endpoint publicado. |
| `RedactarDocumento.ps1` | Toma la documentación técnica en memoria y renderiza el markdown según la plantilla, respetando bloques canónicos y reemplazando marcadores con datos o pendientes. |
| `EscribirSalidas.ps1` | Escribe el `.md` en `documentacion/servicios/<wrapper>.md` (UTF-8 sin BOM, LF). |
| `CargarConfiguracion.ps1` | Módulo común de carga de `configuracion.json`: resuelve la ruta del XPZ contra la raíz del repositorio, aplica el override de `-XpzPath` y expone `PackageName`, `Cliente` y `ServiciosIgnorados`. Se importa por dot-source desde el generador, el inventario y el visor. |
| `GenerarDocumento.ps1` | Orquestador: carga configuración, lee inventario, filtra ignorados, detecta duplicados, despliega menú, encadena los tres módulos anteriores, limpia documentos de servicios en `ERROR` y escribe los logs. |
| `DiagnosticoIA.ps1` | Captura excepciones del pipeline en un JSON estructurado para análisis técnico, con rutas relativas al repositorio y rutas externas enmascaradas. |

### Estados, limpieza, logs y códigos de salida

Cada servicio seleccionado termina en uno de estos estados:

| Estado | Significado | Documento | Código de salida |
|---|---|---|---|
| `OK` | Análisis completo sin pendientes. | Escrito (sobrescribe). | 0 |
| `WARNING` | Documento generado con pendientes de confirmación (tipos o descripciones de campos, o duplicado de nombre local). | Escrito (sobrescribe), salvo duplicados. | 0 |
| `ERROR` | El análisis no pudo completarse (SDT ausente, salida estructural no resoluble, método ambiguo, delegado no exportado, etc.). Una autorreferencia válida del mismo SDT no constituye un error. | **No** se escribe; se elimina el archivo previo del servicio. | 1 |
| `OMITIDO` | FQN en `serviciosIgnorados` presente en el inventario. | No se genera ni se elimina. | 0 |

Limpieza de documentos:

- los servicios en `OK` o `WARNING` sobrescriben su `.md`;
- un servicio en `ERROR` elimina el archivo previo (`<ultimo-segmento-fqn>.md`); un fallo en esa eliminación aborta la fase de cierre;
- `OMITIDO` y duplicados `WARNING` no eliminan archivos preexistentes.

Logs:

- ejecución completada → `review.json`;
- si hay al menos un `WARNING` o `ERROR` → `errores.txt`, con una sola línea por servicio y sus mensajes concatenados mediante `; `; también incluye las líneas `OMITIDO` de esa ejecución (una ejecución con omisiones únicamente no crea `errores.txt`);
- `review.json` conserva cada pendiente como un elemento estructurado independiente aunque el log plano los agrupe por servicio;
- si hay excepciones → `diagnostico-ia.json`;
- cancelar el `Out-GridView` del modo 2 termina con código 0 y **no** escribe logs;
- un error fatal (configuración, inventario, apertura del XPZ, cierre) escribe `diagnostico-ia.json` pero no `review.json`.

La marca temporal de los logs tiene precisión de un segundo: dos ejecuciones que finalicen dentro del mismo segundo pueden escribir las mismas rutas y sobrescribirse.

## Estructura del repositorio

| Recurso | Qué hace |
|---|---|
| [xpz/](xpz/) | Exportaciones GeneXus disponibles localmente. El archivo activo es el indicado por `configuracion.json`; la carpeta está ignorada por git. |
| `GeneXus-XPZ-Skills-main/` | Repositorio auxiliar opcional con scripts y catálogos, como `gx-object-type-catalog.json`. Está ignorado por git. |
| [configuracion.json](configuracion.json) | Configuración operativa y dinámica: ruta al XPZ activo, `packagename` del endpoint publicado, etiqueta `cliente` y lista `serviciosIgnorados`. |
| [AGENTS.md](AGENTS.md) | Memoria del proyecto para agentes: reglas no obvias, estructura de carpetas, fuentes normativas y convenciones. |
| [exportarXPZ.cmd](exportarXPZ.cmd) | Exporta automáticamente `Module:APIGLM` desde la KB local, presenta cinco tareas con estado y genera un XPZ y su log con marca temporal. |
| [GenerarDocumentacion.cmd](GenerarDocumentacion.cmd) | Orquestador que regenera inventario (`endpoints.json`, `endpoints.md`) y visor (`APIServicios.html`). |
| [GenerarDocumentoServicio.cmd](GenerarDocumentoServicio.cmd) | Entry point del generador interactivo de documentación de servicios. |
| [.gitignore](.gitignore) | Excluye los XPZ, el repositorio auxiliar, los inventarios, el visor, los documentos generados y los logs. |
| `specs/` | Especificaciones numeradas que guían el desarrollo del proyecto (ver sección abajo). |
| `documentacion/analisisXPZ.md` | Fuente normativa #1: cómo construir la documentación técnica desde el XPZ. Define el flujo de análisis, tipos canónicos, obligatoriedad por subnivel, criterios de detención y la fuente única de evidencia. |
| `documentacion/reglasEditoriales.md` | Fuente normativa #2: presentación del documento final. Lenguaje, formato de tablas, secciones obligatorias y nomenclatura de archivos. |
| `documentacion/templateDoc.md` | Fuente normativa #3: plantilla markdown de cada servicio. Bloques canónicos y marcadores de reemplazo. |
| `documentacion/servicios/` | Documentos generados por servicio. Cada archivo utiliza el nombre local del wrapper en minúsculas. |
| `documentacion/Endpoints/assets/analisisEndpoint.md` | Guía para reproducir el inventario de endpoints desde `APIGLM.APIGLMMain`. `endpoints.json` y `endpoints.md` son salidas generadas (ignoradas). |
| `documentacion/Endpoints/assets/endpoints.json` | Inventario de endpoints en JSON (generado, ignorado). |
| `documentacion/Endpoints/assets/endpoints.md` | Inventario de endpoints en markdown (generado, ignorado). |
| `documentacion/Endpoints/binary/GenerarListaEndpoints.ps1` | Script que extrae wrappers HTTP activos desde el XPZ y escribe el inventario. |
| `documentacion/Endpoints/binary/GenerarVistaHTML.ps1` | Script que genera el visor web `APIServicios.html`. |
| `documentacion/Endpoints/binary/ObtenerEndpoints.cmd` | Atajo para regenerar solo el inventario (sin visor). |
| `documentacion/Endpoints/web/APIServicios.html` | Visor estático generado (ignorado). |
| `documentacion/Endpoints/web/style.css` | Estilos del visor (claro/oscuro). |
| `documentacion/Endpoints/web/app.js` | Lógica del visor: renderizado de grilla, filtro en vivo, toggle de tema. |
| `binary/AnalizarServicio.ps1` | Módulo de análisis: abre el XPZ configurado, resuelve wrapper y programa principal, método HTTP, entrada/salida, tipos, obligatoriedad por subnivel, errores HTTP y endpoint. |
| `binary/RedactarDocumento.ps1` | Módulo de redacción: documentación técnica → markdown según template. |
| `binary/EscribirSalidas.ps1` | Módulo de escritura: guarda el `.md`. |
| `binary/CargarConfiguracion.ps1` | Módulo común de carga de `configuracion.json` con resolución de rutas contra la raíz del repositorio. |
| `binary/DiagnosticoIA.ps1` | Módulo común de diagnóstico de excepciones para el generador, el inventario y el visor. |
| `binary/GenerarDocumento.ps1` | Orquestador del generador: filtra ignorados, detecta duplicados, menú interactivo de tres modos, pipeline análisis → redacción → escritura, limpieza de `ERROR` y logs. |
| `binary/ExportarXPZProgreso.ps1` | Ejecuta MSBuild en segundo plano, interpreta sus eventos y mantiene visibles las tareas terminadas y la tarea activa. |
| `binary/ExportarXPZ.msbuild` | Proyecto MSBuild que abre la KB, exporta `Module:APIGLM` con referencias mínimas y cierra la KB. |
| `binary/ObtenerDocumento.cmd` | Atajo para invocar el generador de documentación de servicios desde `binary/`. |
| `Logs/exportarXPZ_<marca>.log` | Log completo generado por MSBuild durante una exportación automática del XPZ. |
| `Logs/yyyyMMdd-HHmmss-review.json` | Resultado agregado de una ejecución completada (incluye `OK`, `WARNING`, `ERROR` y los `OMITIDO` presentes en el inventario). |
| `Logs/yyyyMMdd-HHmmss-errores.txt` | `WARNING`, `ERROR` y `OMITIDO` legibles; se genera solo cuando hay al menos un warning o error. |
| `Logs/yyyyMMdd-HHmmss-diagnostico-ia.json` | Excepciones estructuradas con fase, causa interna, ubicación, sentencia y stack trace; se genera solo cuando hay errores. |

## Especificaciones (specs)

El desarrollo sigue el método spec-driven. Cada spec define el alcance, modelo de datos, plan de implementación y criterios de aceptación de una funcionalidad.

| Spec | Estado | Descripción |
|---|---|---|
| [SPEC 02](specs/02-visor-endpoints.md) | Aprobado e implementado | Visor web de endpoints: grilla con filtro, tema claro/oscuro y generación desde `endpoints.json`. |
| [SPEC 03](specs/03-generador-documentacion-servicios.md) | Aprobado e implementado | Pipeline `AnalizarServicio.ps1` → `RedactarDocumento.ps1` → `EscribirSalidas.ps1`, configuración dinámica y selección interactiva. |
| [SPEC 04](specs/04-menu-interactivo-generador.md) | Implementado | Menú interactivo con tres modos (individual, múltiple vía `Out-GridView`, lote completo), barra de progreso, regeneración sin confirmación y log de errores. |
| [SPEC 05](specs/05-integridad-pipeline-generacion.md) | Implementado | Integridad del pipeline: configuración única del XPZ, duplicados, estados `OK`/`WARNING`/`ERROR`/`OMITIDO`, logs y códigos de salida. |
| [SPEC 06](specs/06-analizador-xpz-contratos-completos.md) | Implementado | Analizador XPZ de contratos completos: tipos estrictos, estructuras SDT recursivas expandidas por ruta JSON y estados de resolución. |
| [SPEC 07](specs/07-coherencia-documental-y-visor.md) | Implementado | Coherencia documental y robustez del visor: normas y rutas alineadas con el pipeline real, seguridad, accesibilidad y adaptación móvil del visor. |
| [SPEC 08](specs/08-detector-cambios-xpz.md) | Borrador | Detector de cambios por árbol transitivo del XPZ, checksums, historial de versiones y grafo de dependencias. |
| [SPEC 09](specs/09-pruebas-automatizadas-locales.md) | Borrador | Harness local sin dependencias para probar pipeline, analizador y visor en entornos aislados. |

Las filas en `Borrador` corresponden a funcionalidades en desarrollo; las funcionalidades que no aparecen en esta tabla no se consideran disponibles. Las propuestas futuras deben incorporarse mediante una spec aprobada antes de documentarse como parte del proceso operativo.

## Obtención del inventario de endpoints

El punto de partida es el objeto `APIGLM.APIGLMMain`, incluido en el XPZ. Su código fuente contiene las llamadas a los procedimientos `WS...` que forman el conjunto inicial de servicios activos.

Este proceso está automatizado en `GenerarListaEndpoints.ps1` (invocado por `GenerarDocumentacion.cmd`); los pasos siguientes describen el método que ese script implementa.

La obtención del inventario sigue esta operatoria:

1. Abrir el XPZ como un contenedor de solo lectura y seleccionar la primera entrada cuyo nombre termine en `.xml`; se valida que su raíz sea `ExportFile` (no se verifica que el ZIP contenga un único XML).
2. Buscar en el XML el objeto `APIGLM.APIGLMMain`.
3. Leer sus llamadas activas a procedimientos `WS...`, ignorando las llamadas completamente comentadas.
4. Resolver cada llamada contra un objeto exportado en el XPZ.
5. Confirmar que el objeto sea un procedimiento, tenga `IsMain=True` y utilice `CALL_PROTOCOL=HTTP`.
6. Incorporar una sola vez cada objeto confirmado en `endpoints.md`, respetando el orden de `APIGLMMain`.

Una llamada en `APIGLMMain` es inicialmente un candidato. Solo se considera endpoint confirmado cuando el objeto correspondiente existe en el XML y cumple las propiedades HTTP requeridas.

Alcance de la detección y candidatos no incorporados:

- la extracción es por expresión regular y recoge **una sola llamada por línea** (la primera coincidencia); no hay un parser completo de sintaxis GeneXus;
- una línea cuyo primer contenido sea `//` se descarta por completo, aunque contenga texto que parezca una llamada;
- los candidatos que no pueden resolverse (sin coincidencia o con varias) se registran en el inventario como `unresolved`;
- los objetos que se resuelven pero no confirman tipo Procedure, `IsMain=True` o `CALL_PROTOCOL=HTTP` se descartan y solo aparecen en consola (no se guardan en los artefactos);
- las repeticiones del mismo FQN se omiten silenciosamente: se conserva la primera aparición.

El inventario conserva el nombre completo de GeneXus, por ejemplo:

```text
APIGLM.Cotizacion.WSObtenerDatosProductor
```

Ese nombre identifica el wrapper dentro de la base de conocimiento, pero todavía no representa la dirección publicada que utilizará un consumidor.

## Análisis individual de un servicio

Una vez seleccionado un elemento del inventario, se analiza su objeto `WS...`. Este objeto funciona como wrapper HTTP: recibe la solicitud, ejecuta controles generales y delega el procesamiento en un procedimiento separado.

Se prefiere un programa principal separado: un procedimiento que recibe `in:&APIGLMRequestIn` y produce `out:&APIGLMResponse`, localizado por la delegación única en el wrapper. Si no existe una delegación utilizable pero el wrapper contiene lógica REST reconocible (`QueryParams`, `Body`, `GenerarAPIGLMResponse`, `HttpResponse.AddFile/AddString` o `GenerarHttpResponse`), el propio wrapper se analiza como programa principal. Solo se detiene cuando no hay delegación ni lógica REST.

El análisis individual comprende:

1. Confirmar el wrapper HTTP y localizar su programa principal (separado o el propio wrapper).
2. Determinar el método del servicio:
   - **POST**: se reconoce únicamente cuando el programa lee `APIGLMRequestIn.Body` y lo deserializa con `FromJson`. Se usa la primera llamada balanceada que menciona `Body`; la variable destino debe estar declarada con `ATTCUSTOMTYPE=sdt:...`.
   - **GET**: todo lo demás, incluida la ausencia de entrada funcional. La entrada se obtiene de las posiciones de `APIGLMRequestIn.QueryParams` mediante asignaciones directas `&variable = ...&colQueryParams.Item(<entero>)`; solo se reconoce la primera llamada y las posiciones numéricas directas. Si no hay parser reconocido, el método queda GET con entrada vacía.
   - Si el programa combina `QueryParams` con `FromJson` sobre una estructura en una posición de la URL, el método es ambiguo y el análisis se detiene con `ERROR`.
3. Resolver los tipos de los campos a través de sus variables, dominios, atributos, estructuras y conversiones confirmadas. Cuando un tipo sigue pendiente, se consulta un índice memoizado por identidad exacta del SDT y ruta interna, construido desde asignaciones de todo el XPZ.
4. Expandir las estructuras compuestas hasta identificar sus campos simples; cada estructura y subestructura se documenta en una tabla independiente identificada por su ruta JSON completa. Una referencia al mismo SDT conserva el campo recursivo y detiene allí la expansión para evitar tablas infinitas.
5. Determinar qué campos son obligatorios a partir del uso confirmado en el proceso (ver [Cálculo de Obligatorio](#cálculo-de-obligatorio)).
6. Resolver la salida satisfactoria HTTP 200 (ver [Salida](#salida)).
7. Registrar únicamente los errores HTTP explícitos generados por `GenerarAPIGLMResponse` dentro del programa principal (ver [Errores HTTP](#errores-http)).
8. Resolver el endpoint publicado y preparar la documentación técnica que utilizarán las reglas editoriales y la plantilla.

Las validaciones funcionales pueden servir para determinar si un campo es obligatorio, pero no se publican como una sección independiente. Los errores incluidos dentro de una respuesta HTTP 200 tampoco se presentan como errores HTTP del servicio.

### Salida

La salida satisfactoria usa HTTP 200 y puede adoptar estas formas, cada una con su bloque en la plantilla:

| Forma | Patrón detectado | Documentación |
|---|---|---|
| SDT (simple o colección) | `GenerarAPIGLMResponse(HttpCode.OK, ..., &Var.ToJson())` | Tabla de campos y tablas por ruta JSON para subestructuras. |
| SDT delegado | `APIGLMResponse` fluye hacia un Procedure exportado con parámetro `out:` confirmado | Se sigue el enlace real/formal y se documenta la estructura resuelta en el Procedure delegado. |
| Colección primitiva | Variable que declara colección de un tipo primitivo | `Colección de <tipo del elemento>` o `Colección JSON` si el tipo no se confirma. |
| Escalar | `&X` o `&X.ToString()` como payload | Un único campo con su tipo canónico. |
| Mensaje | Literal o texto compuesto enviado como respuesta exitosa | Uno o más mensajes normalizados, sin inventar un SDT ni un campo JSON. |
| Vacío | Payload `''` o `""` | `Sin mensaje explícito` (no genera pendiente). |
| Binario | `HttpResponse.AddFile` | `Content-Type: application/octet-stream` + `Archivo binario`; no se presupone PDF porque también puede tratarse de XLSX u otro formato. |

La salida es una colección cuando el payload declara `AttCollection=True` o cuando el SDT está definido como colección en su nodo principal. Si el SDT de salida no está exportado en el XPZ o la estructura no puede determinarse, el análisis se detiene con `ERROR` y no se genera el documento (ver [Cuándo detener el análisis](#cuándo-detener-el-análisis)).

### Errores HTTP

La única evidencia admitida es una llamada a `GenerarAPIGLMResponse` con código distinto de 200 dentro del programa principal. Los códigos reconocidos son:

| `HttpCode.*` | Código HTTP |
|---|---|
| `BadRequest` | 400 |
| `Unauthorized` | 401 |
| `Forbidden` | 403 |
| `NotFound` | 404 |
| `MethodNotAllowed` | 405 |
| `InternalServerError` | 500 |
| `NotImplemented` | 501 |
| `ServiceUnavailable` | 503 |
| otro/desconocido | 0 → se muestra como `PENDIENTE DE CONFIRMACIÓN` |

Los errores funcionales dentro de una respuesta HTTP 200 y los códigos provenientes del wrapper, procedimientos auxiliares o estados internos del payload quedan excluidos.

### Cálculo de Obligatorio

- La obligatoriedad se calcula por campo y por ruta JSON completa, tanto en la fila raíz como en cada subnivel. Un campo en `SI` no promueve a su estructura padre, ni el `SI` de una estructura o colección se hereda a sus hijos: cada uno requiere evidencia propia de uso en el programa principal.
- Se consideran el programa principal y las fuentes de los procedimientos alcanzables (transitivo, con profundidad máxima 5) como evidencia complementaria.
- En GET, la asignación inicial desde `&colQueryParams.Item(N)` se ignora para este cálculo. El campo queda `SI` únicamente cuando después se valida, consume o pasa como argumento; si solo se parsea, queda `NO`.
- Cuando un SDT se pasa completo a otro Procedure, la obligatoriedad se sigue por el enlace confirmado entre argumento real y parámetro formal, con memoización y protección contra ciclos. No se mezclan variables locales homónimas de fuentes auxiliares.
- Los campos homónimos de estructuras distintas no comparten obligatoriedad: cada uno se resuelve con su propia ruta JSON.

## Nombre GeneXus y endpoint publicado

El inventario y la documentación final muestran identificadores diferentes porque cumplen funciones distintas.

| Concepto | Ejemplo | Uso |
|---|---|---|
| Nombre GeneXus | `APIGLM.Cotizacion.WSObtenerDatosProductor` | Localiza el wrapper dentro del XPZ. |
| Endpoint publicado | `{packagename}apiglm.cotizacion.awsobtenerdatosproductor` | Identifica la ruta relativa documentada para consumir el servicio. |

El endpoint publicado se escribe en minúsculas y se construye con el `packagename` definido en `configuracion.json` y **toda** la ruta de módulos del FQN (incluido el módulo raíz `APIGLM`), seguida del nombre del procedimiento. Para los procedimientos HTTP principales se antepone `a` al nombre del proceso. El `packagename` debe tomarse de la configuración activa y no inferirse desde el XPZ ni por semejanza con otro servicio.

## Cómo documentar un servicio (vía generador automático)

1. Asegurarse de que `configuracion.json` apunte al XPZ correcto, tenga el `packagename` adecuado y la lista `serviciosIgnorados` actualizada.
2. Ejecutar `GenerarDocumentacion.cmd` para regenerar el inventario desde el XPZ actual.
3. Ejecutar `GenerarDocumentoServicio.cmd` y elegir un modo en el menú interactivo (opciones 1, 2 o 3).
4. El generador aplica las reglas implementadas a partir de `analisisXPZ.md` → `reglasEditoriales.md` → `templateDoc.md` y escribe cada `.md` en `documentacion/servicios/`.
5. Revisar `Logs/*-errores.txt` y `*-review.json` para los warnings, errores y pendientes de la ejecución.
6. Ante un error, compartir el archivo `Logs/*-diagnostico-ia.json` más reciente para localizar rápidamente la fase y la línea que fallaron.

Tras cambiar el XPZ o cualquier valor de `configuracion.json`, regenerar primero el inventario y el visor. Después volver a ejecutar el generador de servicios en el modo adecuado; el proceso actual no detecta automáticamente qué objetos cambiaron.

> **Coherencia inventario-XPZ.** El generador de servicios no verifica que `endpoints.json` corresponda al XPZ activo: carga el inventario desde una ruta fija y luego abre el XPZ por separado. Si el inventario está desactualizado, cada wrapper que no exista en el XPZ abierto termina en `ERROR`. Conviene regenerar el inventario antes de documentar.

## Cuándo detener el análisis

Hay dos resultados posibles cuando falta evidencia, y es importante distinguirlos:

**Pendientes recuperables → `WARNING` y documento.** El análisis continúa, el documento se escribe y los datos faltantes se marcan como `PENDIENTE DE CONFIRMACIÓN` (y se listan en `review.json`). Ocurre, por ejemplo, cuando un tipo o una descripción de campo no puede resolverse dentro del XPZ.

**Errores estructurales → `ERROR` y sin documento.** El análisis se detiene, no se genera el documento y el servicio queda en `ERROR`. Ocurre, entre otros casos, cuando:

- no hay delegación única ni lógica REST en el wrapper;
- el método es ambiguo (combina `QueryParams` con `FromJson` desde una posición de la URL);
- el programa principal delegado no está exportado en el XPZ configurado (`El programa principal <X> no está exportado en el XPZ configurado. No puede inferirse.`);
- la entrada o la salida referencia un SDT ausente (`La entrada del SDT <X> ...` / `La salida del SDT <X> ... no puede inferirse.`); una autorreferencia al mismo SDT es válida y se documenta sin expandirla indefinidamente;
- la salida HTTP 200 no puede determinarse;
- distintas fuentes presentan información contradictoria.

El objetivo normativo es que el documento indique qué dato está pendiente y qué fuente permitiría confirmarlo, diferenciando hechos comprobados de información todavía no disponible. Nota: los textos pendientes generados hoy indican el dato faltante, pero no siempre incluyen la evidencia requerida; esa completitud es un objetivo a alcanzar en el generador.

## Limitaciones actuales

Comportamientos conocidos que conviene tener presentes y que no deben interpretarse como diseño definitivo:

- **Escrituras no atómicas.** El inventario escribe `endpoints.json` y luego `endpoints.md`; un error intermedio puede dejar JSON nuevo y Markdown anterior. El visor sobrescribe directamente el HTML. No hay archivos temporales ni rollback.
- **Pendientes fuera del estado.** La descripción funcional faltante o los mensajes/códigos HTTP pendientes pueden aparecer dentro del documento sin cambiar el estado a `WARNING` (solo los pendientes de tipos y descripciones de campos alimentan el estado).
- **Códigos de error no mapeados.** Un `HttpCode.*` desconocido se conserva como código `0` y se muestra como `PENDIENTE DE CONFIRMACIÓN` en la tabla de errores.
- **`-XpzPath` y fuente única.** El override permite analizar un XPZ distinto del configurado manteniendo `packagename`/`cliente` de la configuración; usar con coherencia o el inventario puede no corresponder al XPZ abierto.
- **Coherencia inventario-XPZ.** El generador no verifica que `endpoints.json` corresponda al XPZ activo.
- **Detección por regex.** El inventario detecta una llamada por línea y no distingue comentarios de bloque ni cadenas; no hay parser completo de GeneXus.
- **Markdown sin escape.** `nombre` y `descripcion` se insertan literalmente en la tabla del inventario: un carácter `|` o un salto de línea del XPZ puede romper la fila.
- **Visor móvil y seguridad.** La grilla no usa contenedor de desplazamiento horizontal y `cliente` se inserta sin escapar en el HTML.

## Resultado esperado

Cada archivo de `documentacion/servicios/` debe permitir que una persona comprenda, sin consultar directamente el código GeneXus:

- cuál es el propósito del servicio;
- qué endpoint y método debe utilizar;
- cómo autenticarse;
- qué parámetros o campos debe enviar;
- qué estructura recibe como respuesta satisfactoria;
- qué errores HTTP explícitos puede devolver.

El resultado final es una documentación orientada al consumidor del servicio, respaldada por la evidencia técnica contenida en el XPZ.
