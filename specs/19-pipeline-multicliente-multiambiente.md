# SPEC 19 — Pipeline multicliente y multiambiente

> **Estado:** Aprobado
> **Depende de:** SPEC 04, SPEC 13, SPEC 14, SPEC 16, SPEC 18
> **Fecha:** 2026-08-16
> **Objetivo:** Adaptar la consola y el pipeline compartido para generar y versionar documentación aislada por cliente y ambiente mediante una configuración central parametrizable.

## Por qué existe esta SPEC

El pipeline actual opera sobre una única Knowledge Base y usa rutas globales para el XPZ, los documentos, el control de versiones, el historial, los logs y el inventario técnico. Esa topología impide documentar varios clientes y sus ambientes sin reemplazar artefactos, mezclar versiones o consumir datos de otra ejecución.

La lógica normativa de análisis y redacción ya es común a todas las KB. Esta SPEC cambia la selección y las rutas operativas, pero conserva esa única implementación compartida.

## Alcance

**Incluido:**

- Reemplazar el esquema monocliente de `configuracion.json` por una configuración central con herramientas globales, raíz configurable de clientes y una colección parametrizable de clientes y ambientes.
- Definir por cliente `id`, `nombre`, `packagename`, `serviciosIgnorados` y `ambientes`.
- Definir por ambiente `id`, `nombre` y `kbPath`; no deducir la ruta de la KB desde sus nombres.
- Resolver `rutas.clientesRoot` relativo a la raíz del repositorio o como ruta absoluta.
- Resolver un `kbPath` relativo contra la raíz del repositorio o conservarlo si es absoluto.
- Exigir IDs de cliente y ambiente en minúsculas con formato `^[a-z0-9][a-z0-9-]*$`, únicos en su nivel y usados como nombres de carpeta.
- Rechazar configuraciones donde dos ambientes apunten a la misma ruta de KB una vez normalizada.
- Mostrar al iniciar `GenerarDocumentosGLM.cmd` un selector de cliente y luego un selector de ambiente entre los elementos configurados.
- Validar primero el esquema y las herramientas globales; después de la selección, ejecutar para el contexto elegido las mismas validaciones de arranque que existen hoy, incluida la disponibilidad de la KB.
- Terminar con código `1`, mensaje preciso y sin crear carpetas ni archivos cuando el cliente, el ambiente o su KB sean inválidos.
- Agregar al menú una opción para cambiar de cliente o ambiente sin cerrar la consola; el cambio repite el preflight completo antes de activar el nuevo contexto.
- Crear para cada ambiente válido el árbol contextual `documentacionServicios/`, `estado/`, `xpz/`, `Logs/`, `test/fixtures/` y `test/resultados/` bajo `rutas.clientesRoot/<clienteId>/<ambienteId>/`.
- Mantener en `test/` de la raíz el harness y las pruebas compartidas; las carpetas `test/` contextuales contienen solo fixtures y resultados del ambiente.
- Seleccionar por defecto el XPZ principal más reciente de la carpeta `xpz/` del ambiente con la lógica vigente de `ListarXPZPrincipales.ps1`.
- Conservar la selección manual de otro XPZ como override de la sesión, sin persistirla ni modificar `configuracion.json`.
- Guardar los nuevos XPZ principales y complementarios exclusivamente en la carpeta `xpz/` del ambiente activo; el XPZ recién exportado pasa a ser el más reciente por la convención vigente.
- Propagar una única identidad de contexto a inventario técnico, validación, completitud, análisis, redacción, PDF, actualización, resumen y diagnóstico.
- Extender el manifiesto de ejecución a `schemaVersion = 2` para vincular cliente, ambiente, configuración, XPZ, inventario interno, documentos, estado, logs y staging de una misma ejecución.
- Generar el inventario que necesita el pipeline actual dentro del staging de la ejecución contextual, consumirlo por ruta explícita y eliminarlo junto con el manifiesto; no publicarlo como artefacto web.
- Aislar por ambiente los Markdown, PDF, `controlVersiones.json`, `historialVersiones.md`, pendientes, lineage, revisiones, fingerprints, review, diagnósticos, reportes de validación y logs de exportación.
- Ubicar `actualizacion.lock` en el `estado/` del ambiente para permitir actualizaciones simultáneas de ambientes distintos y rechazar una segunda actualización del mismo ambiente con código `1`.
- Mantener líneas de versión completamente independientes entre ambientes, aunque contengan los mismos FQN y el mismo contenido documental.
- Transformar la configuración actual en el cliente inicial `trunk`, con ambiente `testing`, `kbPath` igual a `C:/KBs/SEGUROS_COMERCIAL_TRUNK`, y conservar el `packagename` y `serviciosIgnorados` actuales en el nivel cliente.
- Empezar el nuevo contexto sin documentos ni estado previo: los artefactos globales actuales no se migran, no se eliminan y no se consumen.
- Adaptar `test/Run-Tests.ps1` para usar contextos temporales y demostrar el aislamiento entre al menos dos clientes y dos ambientes.
- Actualizar `README.md`, `AGENTS.md` y `.gitignore` con el nuevo contrato de configuración y rutas.

**Fuera de alcance (para futuras SPEC):**

- Proyecto web de endpoints, incluidos sus JSON, Markdown, HTML, CSS, JavaScript y contratos de publicación.
- Migración de `xpz/`, `estado/`, `documentacionServicios/` o `Logs/` globales a un contexto nuevo.
- Compatibilidad final con el esquema anterior de `configuracion.json`.
- Promoción o sincronización de documentos y versiones entre TESTING y PRODUCCIÓN.
- Línea de versiones compartida entre ambientes de un cliente.
- Reglas de análisis, redacción o plantillas diferentes por cliente.
- Herramientas GeneXus, MSBuild, Pandoc o Typst diferentes por cliente o ambiente.
- Ejecución distribuida en otros equipos o almacenamiento remoto.

## Modelo de datos

### `configuracion.json`

```json
{
  "rutas": {
    "clientesRoot": "clientes"
  },
  "exportacion": {
    "onlyModuleAPIGLM": true
  },
  "herramientas": {
    "geneXusProgramDir": "C:/Program Files (x86)/GeneXus/GeneXus18",
    "msbuildPath": "C:/Windows/Microsoft.NET/Framework/v4.0.30319/MSBuild.exe",
    "pandocPath": "binary/tools/pandoc.exe",
    "typstPath": "binary/tools/typst.exe"
  },
  "clientes": [
    {
      "id": "trunk",
      "nombre": "Trunk",
      "packagename": "glmsuit.comercial.",
      "serviciosIgnorados": [
        "APIGLM.WSRedireccionHome",
        "APIGLM.Comun.WSLiberarSolicitud",
        "APIGLM.Test.WSTestMaxi",
        "APIGLM.WSEjemplo"
      ],
      "ambientes": [
        {
          "id": "testing",
          "nombre": "Testing",
          "kbPath": "C:/KBs/SEGUROS_COMERCIAL_TRUNK"
        }
      ]
    }
  ]
}
```

Convenciones:

- `rutas.clientesRoot` puede ser absoluto o relativo a la raíz del repositorio; el valor inicial es `clientes`.
- `kbPath` es explícito por ambiente y nunca se construye desde `id` o `nombre`; una ruta relativa se resuelve contra la raíz del repositorio.
- `herramientas` y `exportacion` son globales.
- `packagename` y `serviciosIgnorados` pertenecen al cliente y se comparten entre sus ambientes.
- Un cliente puede declarar uno o más ambientes; los nombres visibles pueden ser libres y los IDs siguen la convención de slug.
- Las colecciones `clientes` y `ambientes` no admiten IDs duplicados sin distinguir mayúsculas de minúsculas.
- Dos `kbPath` que resuelven a la misma ruta física invalidan la configuración, incluso si pertenecen a clientes distintos.
- El archivo no contiene una propiedad `xpz`: la selección predeterminada se deriva de la carpeta contextual y cualquier override vive solo durante la sesión.

### Contexto resuelto

`Cargar-Configuracion` devuelve para la selección activa un objeto único con estas propiedades canónicas:

```text
ConfigPath
RaizRepositorio
ClientesRoot
ClienteId
ClienteNombre
AmbienteId
AmbienteNombre
ContextId
DirectorioContexto
KbPath
PackageName
ServiciosIgnorados
DirectorioXpz
DirectorioServicios
DirectorioEstado
RutaControl
RutaHistorial
RutaLock
DirectorioLogs
DirectorioTestFixtures
DirectorioTestResultados
Herramientas
```

`ContextId` tiene la forma `<clienteId>/<ambienteId>`. Todas las rutas son absolutas después de resolver el contexto.

### Árbol por ambiente

```text
clientes/<clienteId>/<ambienteId>/
├── documentacion/
│   └── servicios/
├── estado/
│   ├── controlVersiones.json
│   ├── historialVersiones.md
│   └── actualizacion.lock
├── xpz/
├── Logs/
└── test/
    ├── fixtures/
    └── resultados/
```

Las carpetas y archivos ignorados se crean solo después de que el esquema global, el cliente, el ambiente, las herramientas requeridas y la KB hayan pasado el preflight.

### Manifiesto de ejecución `schemaVersion = 2`

```json
{
  "schemaVersion": 2,
  "ejecucionId": "20260816-120000-a1b2c3d4",
  "contextId": "trunk/testing",
  "clienteId": "trunk",
  "ambienteId": "testing",
  "configPath": "C:/DOCUMENTACIONAPI/configuracion.json",
  "xpz": "C:/DOCUMENTACIONAPI/clientes/trunk/testing/xpz/APIGLM_20260816.xpz",
  "servicesDirectory": "C:/DOCUMENTACIONAPI/clientes/trunk/testing/documentacionServicios",
  "stateDirectory": "C:/DOCUMENTACIONAPI/clientes/trunk/testing/estado",
  "logsDirectory": "C:/DOCUMENTACIONAPI/clientes/trunk/testing/Logs",
  "fullyQualifiedNames": [],
  "versions": {},
  "staging": "C:/Temp/APIGLM-ejecuciones/.../staging"
}
```

Todo proceso que recibe `-ManifiestoPath` valida que las rutas usadas pertenecen al mismo contexto y rechaza combinaciones híbridas, como XPZ de un ambiente con control o documentos de otro.

## Plan de implementación

1. Extender `binary/CargarConfiguracion.ps1` con la lectura y validación del nuevo esquema, resolución de cliente/ambiente y construcción del objeto de contexto; agregar fixtures multicliente a `test/fixtures/` y pruebas unitarias sin cambiar todavía los puntos de entrada.
2. Reemplazar `configuracion.json` por el modelo inicial de `trunk/testing` y adaptar `binary/ValidarConfiguracionGLM.ps1` para validar primero la configuración global y después un contexto seleccionado; comprobar configuraciones válidas, IDs inválidos, duplicados, KB inexistente y ausencia de escrituras ante error.
3. Adaptar `binary/GestionDocumentosGLM.ps1` y `GenerarDocumentosGLM.cmd` para seleccionar cliente y ambiente antes del menú, mostrar el contexto activo, repetir el preflight al cambiarlo y derivar desde ese contexto todas las rutas que hoy son globales.
4. Elevar `binary/ManifiestoEjecucion.ps1` a `schemaVersion = 2`, incorporar la identidad y rutas contextuales, validar pertenencia y mantener funcionales la creación, actualización y eliminación atómica de cada ejecución. El manifiesto no contiene `inventoryPath`.
5. Adaptar `binary/ValidarXPZ.ps1`, `binary/CompletarXPZActivoGLM.ps1`, `binary/GenerarDocumento.ps1` y `binary/GenerarPdfServicios.ps1` para descubrir servicios HTTP en memoria desde el XPZ, sin leer inventarios, documentos, estado ni logs globales.
6. Adaptar `binary/ActualizarServicios.ps1` para derivar del contexto el directorio publicado, control, historial, review, logs y lock; verificar que el fast-path, la promoción Markdown/PDF, los pendientes, el reinicio y la reactivación solo afectan al ambiente activo.
7. Adaptar `binary/EjecutarExportacionGLM.ps1`, `binary/ExportarXPZSelectivo.ps1` y sus llamadores para escribir principales, complementos, reportes y logs en el ambiente activo, seleccionar por defecto el XPZ principal más reciente y no modificar la configuración central.
8. Adaptar `binary/ResumirOperacionPdf.ps1` y los llamadores de `binary/DiagnosticoIA.ps1` para usar el manifiesto, review, servicios y logs del contexto solicitado, sin búsquedas globales por el archivo más reciente.
9. Ampliar `test/Run-Tests.ps1` con dos clientes temporales, al menos dos ambientes, FQN coincidentes y ejecuciones separadas; verificar selección, preflight, publicación, hashes, versionado, logs, locks y ausencia de contaminación cruzada, y ejecutar la suite completa después de cada integración.
10. Actualizar `.gitignore` para ignorar el árbol mutable bajo `clientes/` sin afectar fixtures versionados, y actualizar `README.md` y `AGENTS.md` con el esquema, árbol, selección de XPZ, aislamiento y procedimiento para agregar clientes o ambientes.

## Criterios de aceptación

- [ ] `configuracion.json` usa el nuevo esquema y contiene el contexto inicial `trunk/testing` con los valores actuales de package, exclusiones y KB.
- [ ] El esquema anterior de configuración es rechazado con código `1` y un mensaje que indica que no es compatible.
- [ ] Agregar un cliente o ambiente válido requiere editar solo `configuracion.json`, sin copiar ni modificar scripts.
- [ ] Los IDs inválidos o duplicados se rechazan antes de crear el árbol contextual.
- [ ] Dos ambientes con el mismo `kbPath` normalizado se rechazan antes de crear el árbol contextual.
- [ ] Una ruta `clientesRoot` relativa se resuelve contra la raíz del repositorio y una absoluta se conserva.
- [ ] Un `kbPath` explícito se resuelve correctamente y nunca se deduce desde el nombre o ID.
- [ ] Al iniciar la consola se elige primero cliente y después ambiente entre los elementos configurados.
- [ ] El menú muestra cliente, ambiente y XPZ activo sin confundir el nombre visible con el ID de carpeta.
- [ ] La opción de cambiar contexto repite el preflight y ninguna operación posterior conserva rutas del contexto anterior.
- [ ] Un cliente, ambiente o KB inválido termina con código `1`, informa el dato exacto y no crea carpetas ni archivos.
- [ ] Un contexto válido crea exactamente `documentacionServicios`, `estado`, `xpz`, `Logs`, `test/fixtures` y `test/resultados` bajo su directorio.
- [ ] El XPZ predeterminado es el principal más reciente de la carpeta del ambiente según la lógica vigente.
- [ ] Seleccionar manualmente otro XPZ solo afecta la sesión y no modifica `configuracion.json` ni crea estado persistido adicional.
- [ ] Una exportación nueva escribe el XPZ principal y sus complementos únicamente dentro del ambiente activo.
- [ ] El manifiesto de esquema 2 contiene y valida `contextId`, cliente, ambiente, configuración, XPZ, inventario, servicios, estado, logs y staging.
- [ ] Mezclar en una ejecución el XPZ de un ambiente con rutas de otro se rechaza antes del análisis o la publicación.
- [ ] El inventario técnico se genera dentro del staging contextual, se consume por ruta explícita y se elimina al cerrar la ejecución.
- [ ] Ninguna ejecución contextual lee o escribe `xpz/`, `estado`, `documentacionServicios/` o `Logs/` globales.
- [ ] Los artefactos globales anteriores permanecen byte a byte sin cambios después de las pruebas del nuevo pipeline.
- [ ] Dos ambientes con el mismo FQN publican Markdown y PDF independientes sin reemplazarse.
- [ ] TESTING y PRODUCCIÓN mantienen controles, lineages, historiales, revisiones, pendientes y hashes independientes.
- [ ] Un reinicio de versionado afecta únicamente al ambiente activo.
- [ ] Dos actualizaciones de ambientes distintos pueden ejecutarse sin bloquearse entre sí.
- [ ] Una segunda actualización simultánea del mismo ambiente termina con código `1` por el lock contextual.
- [ ] Los códigos de salida `0`, `1`, `2` y `3` conservan su semántica vigente dentro de cada contexto.
- [ ] Un fallo conserva los Markdown, PDF y control anteriores del ambiente afectado y no modifica otro contexto.
- [ ] Los logs, review, diagnósticos y reportes de validación identifican `contextId` y quedan bajo el ambiente correspondiente.
- [ ] La lógica de análisis, tipos canónicos, obligatoriedad, errores HTTP, redacción y plantilla no cambia entre clientes.
- [ ] Los scripts y recursos compartidos permanecen en la raíz; no se copian dentro de carpetas de cliente o ambiente.
- [ ] `test/Run-Tests.ps1` incluye pruebas multicontexto, termina con código `0` y mantiene en verde todos los casos vigentes adaptados al nuevo contrato.
- [ ] `README.md`, `AGENTS.md` y `.gitignore` describen y protegen la nueva estructura.

## Decisiones

- **Sí:** una sola `configuracion.json` central con colecciones de clientes y ambientes. Evita archivos repetidos y permite listar todos los contextos al iniciar.
- **Sí:** herramientas globales. GeneXus, MSBuild, Pandoc y Typst pertenecen a la instalación, no a cada cliente.
- **Sí:** `packagename` y `serviciosIgnorados` por cliente. Los ambientes del mismo cliente comparten el contrato publicado y las exclusiones.
- **Sí:** `kbPath` explícito por ambiente. La ruta no se infiere desde nombres de carpetas.
- **Sí:** IDs estables separados de nombres visibles. Los IDs seguros forman rutas y los nombres se usan solo en la interfaz.
- **Sí:** raíz de clientes configurable y relativa al repositorio por defecto. El producto sigue siendo portable y puede apuntar a otra unidad sin mover scripts.
- **Sí:** árbol completo por ambiente. Documentos, estado, XPZ, logs y datos de prueba no se comparten.
- **Sí:** selección de cliente y ambiente antes del menú, con opción de cambio durante la sesión.
- **Sí:** XPZ más reciente como valor predeterminado y override manual no persistido. Conserva la lógica operativa actual sin mutar la configuración declarativa.
- **Sí:** inventario técnico contextual y efímero. Es necesario para la integridad del pipeline actual, pero no adelanta el proyecto web.
- **Sí:** manifiesto de esquema 2 como contrato de propagación. Evita combinaciones parciales de rutas independientes.
- **Sí:** lock por ambiente. Distintos clientes o ambientes pueden actualizarse en paralelo sin perder la exclusión dentro de un mismo estado.
- **Sí:** versiones independientes por ambiente. No se implementa promoción implícita entre TESTING y PRODUCCIÓN.
- **Sí:** comenzar limpio con `trunk/testing`. Los artefactos existentes se conservan como legado, pero no se migran ni se usan.
- **No:** configuración completa por ambiente. Duplicaría herramientas, package y exclusiones sin necesidad.
- **No:** carpeta XPZ compartida por cliente. Mezclaría exports de KB distintas y volvería ambigua la selección del más reciente.
- **No:** persistir el XPZ activo en configuración o estado. La convención del más reciente y el override de sesión cubren el flujo acordado.
- **No:** compatibilidad con el esquema antiguo. No hay consumidores externos confirmados y se acordó una transición limpia.
- **No:** componentes web en esta SPEC. Se definirán en una SPEC independiente.

## Riesgos

| Riesgo | Mitigación |
| ------ | ---------- |
| Un script conserva una ruta global y publica datos de otro contexto | El manifiesto de esquema 2 transporta rutas canónicas; pruebas con dos contextos y FQN iguales verifican que las rutas globales permanezcan intactas. |
| Un XPZ se combina con package, inventario o estado de otro ambiente | Validación de `contextId` y pertenencia de rutas antes de iniciar análisis, generación o promoción. |
| Dos contextos apuntan accidentalmente a la misma KB | Rechazo de `kbPath` duplicados después de normalizar las rutas. |
| Un cambio de contexto conserva el XPZ de la selección anterior | El selector reconstruye todo el objeto contextual y repite el preflight; no se reutilizan variables de rutas individuales. |
| Un lock global impide paralelismo o un lock parcial no protege el estado correcto | `actualizacion.lock` se deriva siempre de `DirectorioEstado` y las pruebas cubren concurrencia entre ambientes y dentro del mismo ambiente. |
| El inventario técnico global contamina nombres de archivo o servicios | Se genera en staging por ejecución y todos los consumidores reciben su ruta explícita. |
| La falta de migración parece haber eliminado versiones anteriores | Los artefactos globales no se borran ni modifican; la consola identifica claramente el contexto nuevo y su versión independiente. |
| Rutas absolutas impiden mover la instalación | Solo las rutas externas que el operador elija son absolutas; `clientesRoot` y herramientas portables admiten rutas relativas a la raíz. |
| Windows PowerShell 5.1 trata rutas e IDs sin distinguir mayúsculas | IDs obligatoriamente minúsculos, validación case-insensitive de unicidad y normalización de rutas antes de comparar. |

## Lo que **no** incluye esta SPEC

- Proyecto web ni publicación de inventarios para consumo web.
- Migración o eliminación de artefactos globales existentes.
- Promoción entre ambientes o versiones compartidas.
- Reglas documentales específicas por cliente.
- Herramientas diferentes por contexto.
- Compatibilidad final con la configuración monocliente anterior.

Cada uno de esos temas, si se aborda, va en su propia SPEC.
