# Documentación de servicios APIGLM

Este repositorio reúne la metodología y los documentos generados para los servicios HTTP de APIGLM. Su objetivo es transformar la información técnica exportada desde GeneXus en documentación uniforme, verificable y comprensible para quienes necesitan consumir los servicios.

La fuente principal es el archivo [trunk.xpz](xpz/trunk.xpz) (versión original) y [trunk_v2.xpz](xpz/trunk_v2.xpz) (versión con modificaciones). El XPZ contiene el XML exportado de la base de conocimiento GeneXus: procedimientos, código fuente, reglas, variables, estructuras de datos, dominios y atributos. La documentación se obtiene de esa evidencia; no se completa por semejanza con otros servicios ni por suposiciones.

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
| `GenerarVistaHTML.ps1` | `documentacion/Endpoints/binary/` | Lee `endpoints.json`, incrusta los datos tal cual (sin cifrado, sin peticiones de red) en `<script type="application/json">` y escribe `APIServicios.html`. |
| `ObtenerEndpoints.cmd` | `documentacion/Endpoints/binary/` | Genera únicamente el inventario (sin visor). |

Los archivos generados (`endpoints.json`, `endpoints.md` y `APIServicios.html`) están en `.gitignore`: se producen en cada ejecución y no se versionan. Para regenerar todo basta ejecutar `GenerarDocumentacion.cmd` en la raíz del repositorio.

### Visor web

El visor resultante (`documentacion/Endpoints/web/APIServicios.html`) se abre con doble clic (`file://`), sin servidor, frameworks ni CDN:

- encabezado con el cliente definido en `configuracion.json`, la fecha de `meta.generatedAt` en formato `DD/MM/AAAA HH:mm` y el total de `meta.totalConfirmed`;
- grilla con una fila por endpoint, con Nombre y Descripción alineadas a la izquierda;
- filtro en vivo por Nombre o Descripción, sin distinguir mayúsculas ni acentos;
- toggle de tema claro/oscuro con persistencia en `localStorage` (por defecto según `prefers-color-scheme`).

## Generador automático de documentación de servicios

Además del inventario, existe un pipeline en PowerShell 5.1 (sin dependencias externas) que genera la documentación individual de un servicio aplicando mecánicamente `analisisXPZ.md` → `reglasEditoriales.md` → `templateDoc.md`. Se invoca con `ObtenerDocumento.cmd` y presenta un menú interactivo con 6 opciones:

| Opción | Descripción |
|---|---|
| 1 — Servicio particular | Lista numerada de endpoints, elige uno y genera su documentación. |
| 2 — Múltiples servicios | Abre `Out-GridView` para seleccionar varios con Ctrl+Click. |
| 3 — TODOS | Genera documentación para todos los endpoints del inventario. |
| 4 — (reservada para futura expansión) | — |
| 5 — Grafo de dependencias | Dado un endpoint, recorre el XPZ y construye un grafo de dependencias (SDTs, procedimientos llamados) desde el wrapper hasta su entrada/salida. Guarda `grafo-<wrapper>.json` en `assets/` y lo imprime en consola. |
| 6 — Detectar cambios y regenerar modificados | Compara los checksums por objeto del XPZ actual contra `controlVersiones.json`. Si detecta servicios modificados, los lista, pide confirmación y regenera solo esos con barra de progreso. |

En modos 2 y 3 se muestra barra de progreso global (`N/M` y porcentaje). Los archivos existentes se sobrescriben sin preguntar. Si hay errores, se genera `logErrores.txt` en `assets/`.

### Pipeline del generador

Cada documento se produce en tres etapas, implementadas como módulos PowerShell independientes:

| Módulo | Función |
|---|---|
| `AnalizarServicio.ps1` | Abre el XPZ como ZIP de solo lectura, localiza el wrapper por `fullyQualifiedName`, confirma que sea Procedure con `IsMain=True` y `CALL_PROTOCOL=HTTP`, detecta el programa principal delegado, resuelve método HTTP (GET por `QueryParams`, POST por `FromJson`), tipifica campos, expande SDTs, determina obligatoriedad, resuelve salida y errores HTTP, y construye el endpoint publicado. |
| `RedactarDocumento.ps1` | Toma la documentación técnica en memoria y renderiza el markdown según `templateDoc.md`, respetando bloques canónicos y reemplazando marcadores con datos o pendientes. |
| `EscribirSalidas.ps1` | Escribe el `.md` en `servicios/<wrapper>.md` (UTF-8 sin BOM, LF), genera `apiglm-doc-review.json` con juicios no automatizables, y actualiza `controlVersiones.json` con la nueva versión del servicio. |
| `GenerarDocumento.ps1` | Orquestador: carga configuración, lee inventario, despliega menú, encadena los tres módulos anteriores. |

### Detección de cambios entre versiones del XPZ

Cuando se dispone de una nueva versión del XPZ (ej. `trunk_v2.xpz`), la opción 6 del menú ejecuta `DetectarCambios.ps1`, que:

1. Compara el SHA256 del archivo XPZ completo contra `controlVersiones.json` (fast-path: si coincide, no hay cambios y termina).
2. Si difiere, abre el XML y compara el atributo `checksum` de cada objeto wrapper contra su registro en `controlVersiones.json`.
3. Lista los servicios cuyo checksum cambió y pregunta confirmación antes de regenerar.
4. Regenera solo los modificados usando el pipeline análisis → redacción → escritura.

`controlVersiones.json` es el registro maestro de versiones. Cada vez que `EscribirSalidas.ps1` guarda un `.md`, actualiza la entrada del servicio (`version`, `fecha`, `checksum`). La primera ejecución (bootstrap) crea entradas baseline (`version: 1`) para todos los `.md` existentes en `servicios/`.

### Grafo de dependencias

`GenerarGrafoDependencias.ps1` (opción 5) recorre el XML del XPZ a partir de un wrapper y construye un grafo de dependencias usando:

- **`parentGuid`**: jerarquía de objetos en el XML (wrapper → módulo → SDTs contenidos).
- **Referencias en Source**: análisis del texto CDATA buscando llamadas a otros `fullyQualifiedName` (Procedures, SDTs).

El resultado es un JSON (`grafo-<wrapper>.json`) con nodos (objetos referenciados, con tipo y relación) y aristas (conexiones entre ellos), más una impresión en consola.

## Estructura del repositorio

| Recurso | Qué hace |
|---|---|
| [xpz/](xpz/) | Fuente de verdad: export GeneXus. Contiene `trunk.xpz` (original), `trunk_v2.xpz` (versión modificada) y `LPS_COM.xpz` (otro package). Ignorados por git. |
| `GeneXus-XPZ-Skills-main/` | Repositorio auxiliar con scripts y catálogos (ej. `gx-object-type-catalog.json` para confirmar tipos de objeto). Ignorado por git. |
| [configuracion.json](configuracion.json) | Configuración operativa en raíz: ruta al XPZ activo, `packagename` (prefijo del endpoint publicado) y `cliente`. No se versiona. |
| [AGENTS.md](AGENTS.md) | Memoria del proyecto para agentes: reglas no obvias, estructura de carpetas, fuentes normativas y convenciones. |
| [GenerarDocumentacion.cmd](GenerarDocumentacion.cmd) | Orquestador que regenera inventario (`endpoints.json`, `endpoints.md`) y visor (`APIServicios.html`). |
| [.gitignore](.gitignore) | Excluye XPZ, salidas generadas (`endpoints.json`, `endpoints.md`, `APIServicios.html`, `*.json` de `assets/`, logs) y `GeneXus-XPZ-Skills-main/`. |
| `specs/` | Especificaciones numeradas que guían el desarrollo del proyecto (ver sección abajo). |
| `documentacion/analisisXPZ.md` | Fuente normativa #1: cómo construir la documentación técnica desde el XPZ. Define el flujo de análisis, tipos canónicos, reglas de obligatoriedad y criterios de detención. |
| `documentacion/reglasEditoriales.md` | Fuente normativa #2: presentación del documento final. Lenguaje, formato de tablas, secciones obligatorias y nomenclatura de archivos. |
| `documentacion/templateDoc.md` | Fuente normativa #3: plantilla markdown de cada servicio. Bloques canónicos y marcadores de reemplazo. |
| `documentacion/servicios/` | Documentos generados por servicio (ej. `wsobtenertotalessolicitud.md`). Uno por wrapper documentado. |
| `documentacion/Endpoints/assets/analisisEndpoint.md` | Guía para reproducir el inventario de endpoints desde `APIGLM.APIGLMMain`. |
| `documentacion/Endpoints/assets/endpoints.json` | Inventario de endpoints en JSON (generado, ignorado). |
| `documentacion/Endpoints/assets/endpoints.md` | Inventario de endpoints en markdown (generado, ignorado). |
| `documentacion/Endpoints/binary/GenerarListaEndpoints.ps1` | Script que extrae wrappers HTTP activos desde el XPZ y escribe el inventario. |
| `documentacion/Endpoints/binary/GenerarVistaHTML.ps1` | Script que genera el visor web `APIServicios.html`. |
| `documentacion/Endpoints/binary/ObtenerEndpoints.cmd` | Atajo para regenerar solo el inventario (sin visor). |
| `documentacion/Endpoints/web/APIServicios.html` | Visor estático generado (ignorado). |
| `documentacion/Endpoints/web/style.css` | Estilos del visor (claro/oscuro). |
| `documentacion/Endpoints/web/app.js` | Lógica del visor: renderizado de grilla, filtro en vivo, toggle de tema. |
| `documentacion/Generador/binary/AnalizarServicio.ps1` | Módulo de análisis: abre XPZ, resuelve wrapper, método HTTP, entrada/salida, tipos, obligatoriedad, endpoint. |
| `documentacion/Generador/binary/RedactarDocumento.ps1` | Módulo de redacción: documentación técnica → markdown según template. |
| `documentacion/Generador/binary/EscribirSalidas.ps1` | Módulo de escritura: guarda `.md`, `apiglm-doc-review.json`, actualiza `controlVersiones.json`. |
| `documentacion/Generador/binary/GenerarDocumento.ps1` | Orquestador del generador: menú interactivo de 6 opciones, pipeline análisis → redacción → escritura. |
| `documentacion/Generador/binary/ObtenerDocumento.cmd` | Atajo para invocar el generador. |
| `documentacion/Generador/binary/DetectarCambios.ps1` | Compara checksums del XPZ contra `controlVersiones.json`, lista servicios modificados y regenera bajo confirmación. |
| `documentacion/Generador/binary/GenerarGrafoDependencias.ps1` | Construye grafo de dependencias (SDTs, procedimientos) desde un wrapper usando `parentGuid` y referencias en Source. |
| `documentacion/Generador/assets/apiglm-doc-review.json` | Informe de revisión con juicios no automatizables (generado, ignorado). |
| `documentacion/Generador/assets/controlVersiones.json` | Registro maestro de versiones por servicio: `fullyQualifiedName`, `endpoint`, `fecha`, `version`, `checksum`. Se actualiza en cada generación. |
| `documentacion/Generador/assets/grafo-<wrapper>.json` | Grafo de dependencias de un servicio (generado, ignorado). |
| `documentacion/Generador/assets/logErrores.txt` | Log de errores de generación en lote (generado si hay fallos, ignorado). |

## Especificaciones (specs)

El desarrollo sigue el método spec-driven. Cada spec define el alcance, modelo de datos, plan de implementación y criterios de aceptación de una funcionalidad.

| Spec | Estado | Descripción |
|---|---|---|
| SPEC 01 | — | Documentación técnica de `WSObtenerTotalesSolicitud` (servicio de referencia). |
| SPEC 02 | Aprobado | Visor web de endpoints: grilla con filtro, toggle claro/oscuro, generado desde `endpoints.json`. |
| SPEC 03 | Aprobado | Generador automático de documentación: pipeline `AnalizarServicio.ps1` → `RedactarDocumento.ps1` → `EscribirSalidas.ps1`, `configuracion.json`, selección interactiva. |
| SPEC 04 | Borrador | Menú interactivo con 3 modos (individual, múltiple vía `Out-GridView`, lote completo), barra de progreso, regeneración sin confirmación, log de errores. |
| SPEC 05 | Borrador | Integridad del pipeline: configuración única del XPZ, duplicados, estados, logs, salida de errores y optimización de parseo. |
| SPEC 06 | Borrador | Analizador XPZ de contratos completos: tipos estrictos, estructuras SDT recursivas, llamadas multilínea y estados de resolución. |
| SPEC 07 | Borrador | Coherencia documental y robustez del visor: normas, rutas, formato Markdown, seguridad, accesibilidad, móvil y rendimiento. |
| SPEC 08 | Borrador | Detector de cambios por árbol transitivo del XPZ, checksums nativos/semánticos, historial de versiones y grafo de dependencias. |
| SPEC 09 | Borrador | Harness local sin dependencias para probar pipeline, analizador y visor en entornos aislados. |

## Obtención del inventario de endpoints

El punto de partida es el objeto `APIGLM.APIGLMMain`, incluido en el XPZ. Su código fuente contiene las llamadas a los procedimientos `WS...` que forman el conjunto inicial de servicios activos.

Este proceso está automatizado en `GenerarListaEndpoints.ps1` (invocado por `GenerarDocumentacion.cmd`); los pasos siguientes describen el método que ese script implementa.

La obtención del inventario sigue esta operatoria:

1. Abrir el XPZ como un contenedor de solo lectura y localizar su XML interno.
2. Buscar en el XML el objeto `APIGLM.APIGLMMain`.
3. Leer sus llamadas activas a procedimientos `WS...`, ignorando las llamadas completamente comentadas.
4. Resolver cada llamada contra un objeto exportado en el XPZ.
5. Confirmar que el objeto sea un procedimiento, tenga `IsMain=True` y utilice `CALL_PROTOCOL=HTTP`.
6. Incorporar una sola vez cada objeto confirmado en `endpoints.md`, respetando el orden de `APIGLMMain`.

Una llamada en `APIGLMMain` es inicialmente un candidato. Solo se considera endpoint confirmado cuando el objeto correspondiente existe en el XML y cumple las propiedades HTTP requeridas.

El inventario conserva el nombre completo de GeneXus, por ejemplo:

```text
APIGLM.Cotizacion.WSObtenerDatosProductor
```

Ese nombre identifica el wrapper dentro de la base de conocimiento, pero todavía no representa la dirección publicada que utilizará un consumidor.

## Análisis individual de un servicio

Una vez seleccionado un elemento del inventario, se analiza su objeto `WS...`. Este objeto funciona como wrapper HTTP: recibe la solicitud, ejecuta controles generales y delega el procesamiento en un procedimiento separado.

El procedimiento separado que recibe `APIGLMRequestIn` y produce `APIGLMResponse` es el programa principal del servicio. Allí se busca la información necesaria para preparar la documentación técnica.

El análisis individual comprende:

1. Confirmar el wrapper HTTP y localizar su único programa principal.
2. Determinar el método del servicio:
   - En un GET, la entrada se obtiene de las posiciones de `APIGLMRequestIn.QueryParams`.
   - En un POST, la entrada se obtiene de la estructura deserializada desde `APIGLMRequestIn.Body` mediante `FromJson`.
3. Resolver los tipos de los campos a través de sus variables, dominios, atributos o estructuras de datos.
4. Expandir las estructuras compuestas hasta identificar sus campos simples.
5. Determinar qué campos son obligatorios a partir del uso confirmado en el proceso.
6. Identificar la estructura devuelta cuando la operación finaliza correctamente.
7. Registrar únicamente los errores HTTP explícitos generados por `GenerarAPIGLMResponse` dentro del programa principal.
8. Resolver el endpoint publicado y preparar la documentación técnica que utilizarán las reglas editoriales y la plantilla.

Las validaciones funcionales pueden servir para determinar si un campo es obligatorio, pero no se publican como una sección independiente. Los errores incluidos dentro de una respuesta HTTP 200 tampoco se presentan como errores HTTP del servicio.

## Nombre GeneXus y endpoint publicado

El inventario y la documentación final muestran identificadores diferentes porque cumplen funciones distintas.

| Concepto | Ejemplo | Uso |
|---|---|---|
| Nombre GeneXus | `APIGLM.Cotizacion.WSObtenerDatosProductor` | Localiza el wrapper dentro del XPZ. |
| Endpoint publicado | `glmsuit.comercial.cotizacion.awsobtenerdatosproductor` | Identifica la ruta relativa documentada para consumir el servicio. |

El endpoint publicado se confirma durante el análisis individual. Se escribe en minúsculas y, para los procedimientos HTTP principales, incorpora el prefijo `a`. El `packagename` (ej. `glmsuit.comercial.` para Trunk) se define en `configuracion.json`.

## Cómo documentar un servicio (vía generador automático)

1. Asegurarse de que `configuracion.json` apunte al XPZ correcto y tenga el `packagename` adecuado.
2. Ejecutar `GenerarDocumentacion.cmd` para regenerar el inventario desde el XPZ actual.
3. Ejecutar `ObtenerDocumento.cmd` y elegir un modo en el menú interactivo (opciones 1, 2 o 3).
4. El generador ejecuta automáticamente `analisisXPZ.md` → `reglasEditoriales.md` → `templateDoc.md` y escribe el `.md` en `servicios/`.
5. Revisar `apiglm-doc-review.json` para los juicios no automatizables (obligatoriedad no resuelta, descripciones pendientes).

Para regenerar servicios tras un cambio de XPZ, usar la opción 6 del menú: detecta automáticamente qué servicios cambiaron y los regenera.

## Cuándo detener el análisis

La documentación no debe completarse mediante estimaciones. El análisis se detiene y se registra un pendiente cuando, entre otros casos:

- el wrapper no delega en un programa principal separado y único;
- no se puede determinar si la entrada es GET o POST conforme a los patrones admitidos;
- una estructura o un tipo necesario no puede resolverse dentro del XPZ;
- el endpoint publicado no está confirmado;
- distintas fuentes presentan información contradictoria.

Cuando falta evidencia, el documento debe indicar qué dato está pendiente y qué fuente permitiría confirmarlo. De esta manera, la documentación diferencia claramente los hechos comprobados de la información todavía no disponible.

## Resultado esperado

Cada archivo de `servicios/` debe permitir que una persona comprenda, sin consultar directamente el código GeneXus:

- cuál es el propósito del servicio;
- qué endpoint y método debe utilizar;
- cómo autenticarse;
- qué parámetros o campos debe enviar;
- qué estructura recibe como respuesta satisfactoria;
- qué errores HTTP explícitos puede devolver.

El resultado final es una documentación orientada al consumidor del servicio, respaldada por la evidencia técnica contenida en el XPZ.
