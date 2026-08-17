# Documentación de servicios APIGLM

Repositorio de documentación técnica para los servicios HTTP de APIGLM. El pipeline lee exportaciones XPZ de GeneXus, descubre los servicios activos desde `APIGLM.APIGLMMain`, analiza sus contratos y publica Markdown y PDF por cliente y ambiente.

La única fuente de evidencia es el XPZ del ambiente activo. No se completan datos por analogía, por otros XPZ ni por suposiciones: cuando falta o se contradice la evidencia, el análisis deja un pendiente o detiene el servicio según corresponda.

## Estado actual

- Pipeline PowerShell 5.1 operativo, sin build ni dependencias de Node.js o Pester.
- Configuración central multicliente y multiambiente implementada (SPEC 19).
- Exportación de `Module:APIGLM` o de toda la KB mediante GeneXus y MSBuild.
- Validación y completitud automática mediante XPZ principal y complementos numerados.
- Descubrimiento contextual de servicios HTTP, sin publicar ni consumir `endpoints.json` o `endpoints.md`.
- Generación de Markdown y PDF con publicación transaccional por servicio.
- Actualización incremental con control de versiones esquema 2, historial, fingerprints, dependencias y lock por ambiente.
- Diagnósticos estructurados y reviews por ejecución.
- El visor web de endpoints y la exportación OpenAPI no forman parte del pipeline implementado. La SPEC 20 de OpenAPI está en borrador.

## Requisitos

- Windows con Windows PowerShell 5.1.
- GeneXus 18 y MSBuild de 32 bits para exportar desde una Knowledge Base.
- Pandoc y Typst portables para generar PDF. Sus rutas se configuran en `configuracion.json`.
- Un XPZ válido contiene un ZIP con XML cuya raíz es `ExportFile`.
- `Out-GridView` solo es necesario para seleccionar múltiples servicios en el modo interactivo.

El repositorio auxiliar `GeneXus-XPZ-Skills-main/` es opcional. Su catálogo se usa para confirmar el tipo GeneXus `Procedure`; si no está disponible, el pipeline usa el GUID conocido y continúa.

## Inicio rápido

1. Revisar las rutas de GeneXus, MSBuild, Pandoc y Typst en `configuracion.json`.
2. Configurar al menos un cliente y un ambiente con un `kbPath` válido.
3. Ejecutar la entrada principal:

```powershell
.\GenerarDocumentosGLM.cmd
```

4. Seleccionar cliente y ambiente. El preflight valida el esquema, las herramientas y la Knowledge Base antes de crear el árbol contextual.
5. Seleccionar un XPZ principal existente o exportar uno nuevo.
6. Usar el menú para buscar actualizaciones, regenerar toda la documentación y PDF, cambiar de contexto o ejecutar las pruebas.

También se pueden ejecutar scripts directamente para automatización:

```powershell
.\test\Run-Tests.ps1
.\binary\ValidarXPZ.ps1
.\binary\GenerarDocumento.ps1
```

Los scripts directos no pausan para solicitar confirmaciones; el lanzador interactivo sí puede hacerlo.

## Configuración

`configuracion.json` es la única configuración operativa y no contiene una ruta global de XPZ:

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
      "serviciosIgnorados": [],
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

Reglas del esquema:

- `clientesRoot` puede ser relativo a la raíz del repositorio o absoluto.
- `id` de cliente y ambiente debe ser un slug minúsculo con formato `^[a-z0-9][a-z0-9-]*$`; es también el nombre de la carpeta.
- Los IDs son únicos sin distinguir mayúsculas dentro de su nivel.
- `kbPath` es obligatorio, explícito por ambiente y se resuelve contra la raíz cuando es relativo. Nunca se deduce del nombre o del ID.
- Dos ambientes no pueden resolver al mismo `kbPath`.
- `packagename` y `serviciosIgnorados` pertenecen al cliente y se comparten entre sus ambientes.
- `packagename` define el package publicado; no se confirma desde el XPZ.
- `serviciosIgnorados` contiene FQN del inventario que deben quedar en estado `OMITIDO`, sin generar documento ni error.
- Agregar un cliente o ambiente válido requiere editar solamente `configuracion.json`.

## Contextos y artefactos

Cada ejecución activa un contexto `<clienteId>/<ambienteId>`. Todo lo mutable queda aislado en:

```text
clientes/<clienteId>/<ambienteId>/
├── documentacionServicios/    # Markdown y PDF publicados
├── estado/                    # control, historial y lock
├── xpz/                       # XPZ principales y complementos _N
├── Logs/                      # review, diagnósticos y reportes
└── test/
    ├── fixtures/
    └── resultados/
```

Las carpetas globales heredadas `xpz/`, `estado/`, `documentacionServicios/` y `Logs/` no forman parte del pipeline contextual. No se migran, leen ni escriben.

El XPZ no se persiste en la configuración. La sesión permite seleccionar explícitamente un XPZ principal del ambiente; los complementos con sufijo `_N.xpz` se descubren automáticamente. Una exportación nueva se guarda en el ambiente activo y queda disponible como principal más reciente. Cambiar de contexto reinicia todas las rutas y repite el preflight.

El manifiesto de ejecución usa `schemaVersion = 2`, transporta `contextId` y las rutas canónicas del contexto, y rechaza combinaciones híbridas, por ejemplo un XPZ de un ambiente con documentos o control de otro. El inventario técnico, cuando un proceso lo necesita, vive únicamente en el staging de esa ejecución y se elimina junto con el manifiesto.

## Flujo operativo

### Exportación

La opción 1 del lanzador ejecuta `binary/EjecutarExportacionGLM.ps1`:

- Con `exportacion.onlyModuleAPIGLM = true`, exporta `Module:APIGLM` con referencias mínimas.
- Con `false`, solicita confirmación y exporta toda la KB mediante `ExportAll=true`.
- Escribe el XPZ y los logs dentro del ambiente activo.
- Revalida y completa automáticamente los objetos faltantes hasta cinco ciclos.

La exportación selectiva usa `binary/ExportarXPZSelectivo.ps1` a partir del último reporte de `ValidarXPZ.ps1`. Nunca sobrescribe el XPZ principal ni complementos existentes.

### Descubrimiento y completitud

El inventario se obtiene desde el código fuente de `APIGLM.APIGLMMain`:

1. Se consideran llamadas activas a procedimientos `WS...`; una línea cuyo primer contenido sea `//` se ignora.
2. La llamada debe resolverse a un objeto `Procedure` con `IsMain=True` y `CALL_PROTOCOL=HTTP`.
3. Se conserva el FQN literal y la primera aparición de cada FQN.
4. `ValidarXPZ.ps1` revisa el XPZ principal y los complementos `_N.xpz`, construye un índice unificado y escribe el reporte de completitud en `Logs/`.

`GenerarListaEndpoints.ps1` continúa disponible como herramienta independiente heredada para exportar un inventario explícito, pero el pipeline contextual no depende de sus archivos.

### Generación y actualización

La generación aplica el orden fijo `AnalizarServicio.ps1` -> `RedactarDocumento.ps1` -> `EscribirSalidas.ps1`. El menú del generador ofrece servicio individual, selección múltiple con `Out-GridView` o todos los servicios.

La opción de actualización incremental usa `binary/ActualizarServicios.ps1`:

- Compara fingerprints del XPZ y del perfil documental.
- Reanaliza solo los servicios afectados y los servicios activos sin dependencias registradas cuando no puede vincular un cambio.
- Genera Markdown y PDF en staging.
- Publica ambos artefactos juntos después de validarlos.
- Actualiza atómicamente `estado/controlVersiones.json` y, después, el historial best-effort.
- Conserva los artefactos anteriores ante un fallo.

La regeneración completa de PDF solicita confirmación, valida la completitud del XPZ y reinicia explícitamente el versionado con `-Inicializar`; los servicios publicados comienzan en `1.0`.

## Reglas técnicas del análisis

- GET: entrada por posiciones de `APIGLMRequestIn.QueryParams`.
- POST: entrada mediante `FromJson` desde `APIGLMRequestIn.Body`.
- La combinación ambigua de ambos patrones detiene el análisis.
- Los tipos documentales son `Integer`, `Decimal`, `String`, `LongVarchar`, `Boolean`, `Date`, `DateTime`, `Base64`, estructuras y colecciones canónicas, con dimensiones solo cuando están confirmadas.
- `Obligatorio = SI` requiere evidencia de uso confirmada; sin evidencia es `NO`.
- Los SDT se expanden por identidad exacta y ruta JSON. Una autorreferencia válida conserva el campo recursivo y detiene la expansión infinita.
- Solo se documentan errores HTTP producidos por `GenerarAPIGLMResponse` con código distinto de 200 dentro del programa principal.
- El endpoint publicado se forma en minúsculas a partir del package, módulo y procedimiento; para procedures HTTP `Main` se antepone `a`.
- Si falta el programa principal delegado o el SDT necesario en el XPZ activo, no se busca en otro XPZ ni se infiere por analogía.

La redacción sigue las fuentes normativas, en este orden:

1. [`normativas/analisisXPZ.md`](normativas/analisisXPZ.md)
2. [`normativas/reglasEditoriales.md`](normativas/reglasEditoriales.md)
3. [`normativas/templateDoc.md`](normativas/templateDoc.md)

## Estados y persistencia

| Estado | Resultado |
|---|---|
| `OK` | Documento completo; Markdown y PDF publicados. |
| `WARNING` | Documento publicado con pendientes de confirmación. |
| `ERROR` | No se publica el servicio; se conserva el documento anterior. |
| `OMITIDO` | FQN incluido en `serviciosIgnorados`; no genera ni elimina artefactos. |

El control de versiones usa `schemaVersion = 2`, versiones `1.<revisión>`, hashes de Markdown y PDF, dependencias, fingerprints, lineage y estados `ACTIVO`, `ELIMINADO` u `OMITIDO`. La fila `Versión` del Markdown se asigna desde el control y se excluye del `documentHash`.

`estado/historialVersiones.md` es derivado y best-effort. Registra cada bump, incluida la versión `1.0`, en modo append para lotes normales o reemplazo al reiniciar el control. Un fallo del historial solo emite una advertencia.

`estado/actualizacion.lock` es exclusivo por ambiente. Ambientes distintos pueden actualizarse en paralelo; una segunda actualización del mismo ambiente termina con código `1` sin alterar sus artefactos.

Los códigos de salida son:

- `0`: ejecución completa.
- `1`: error fatal o lock ocupado.
- `2`: ejecución parcial; algunos servicios fallaron y otros se publicaron.
- `3`: operación abortada por el usuario.

## Logs y diagnósticos

Los logs se escriben en el `Logs/` del contexto:

- `*-review.json`: estados, hashes, versiones y promoción de la ejecución.
- `*-errores.txt`: pendientes `WARNING`, `ERROR` y omisiones relevantes.
- `*-diagnostico-ia.json`: excepciones con fase, ruta relativa, sentencia y stack trace.
- `*-validacion-xpz.json`: objetos faltantes y receta de exportación.
- `exportarXPZ_*.log` y `exportarXPZSelectivo_*.log`: salida de MSBuild.

Un error fatal puede generar diagnóstico sin `review.json`. El staging y los manifiestos temporales se eliminan al finalizar.

## Pruebas locales

El harness no requiere instalación adicional:

```powershell
.\test\Run-Tests.ps1
```

Prueba configuración, selección de contextos, aislamiento multicliente y multiambiente, inventario desde XPZ, análisis de contratos, validación Markdown, staging y promoción Markdown/PDF, hashes, versionado, historial, locks, diagnósticos y códigos de salida. Los temporales se escriben en el contexto de pruebas y se limpian al finalizar; no se modifican artefactos productivos globales.

## Estructura principal

| Ruta | Propósito |
|---|---|
| `GenerarDocumentosGLM.cmd` | Entrada interactiva principal. |
| `configuracion.json` | Configuración central de clientes, ambientes, herramientas y exportación. |
| `binary/GLMUtilidades.ps1` | Utilidades comunes, hashes, rutas, escritura atómica, locks e invocación de procesos. |
| `binary/GestionDocumentosGLM.ps1` | Orquestador de selección, preflight, exportación, actualización y PDF. |
| `binary/CargarConfiguracion.ps1` | Validación del esquema y resolución del contexto. |
| `binary/CargarMultiXPZ.ps1` | Carga del XPZ y complementos, inventario contextual y nombres de archivos. |
| `binary/AnalizarServicio.ps1` | Análisis técnico del wrapper y su contrato. |
| `binary/RedactarDocumento.ps1` | Redacción del Markdown. |
| `binary/ActualizarServicios.ps1` | Actualización incremental y publicación transaccional. |
| `binary/GenerarPdfServicios.ps1` | Conversión de Markdown a PDF con Pandoc y Typst. |
| `binary/ControlVersiones.ps1` | Control, hashes, revisiones, estados y pendientes. |
| `binary/HistorialVersiones.ps1` | Historial derivado por servicio. |
| `binary/DiagnosticoIA.ps1` | Diagnóstico estructurado de excepciones. |
| `normativas/` | Reglas normativas de análisis, edición y plantilla. |
| `specs/` | Especificaciones del desarrollo. |
| `test/Run-Tests.ps1` | Harness local de pruebas. |

## Especificaciones

Las funcionalidades implementadas principales corresponden a las SPEC 01 a 14, 16, 17, 18 y 19. La SPEC 10 permanece como borrador de intención, la SPEC 15 está aprobada pero no implementada y la SPEC 20 de exportación OpenAPI permanece en borrador. Las specs históricas pueden mencionar inventarios globales o rutas monocliente que ya no describen el flujo contextual actual.

Para reglas no obvias y convenciones internas, consultar [`AGENTS.md`](AGENTS.md).
