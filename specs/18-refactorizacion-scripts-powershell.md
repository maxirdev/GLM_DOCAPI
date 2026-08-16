# SPEC 18 — Refactorización de scripts PowerShell: módulo común de utilidades

> **Estado:** Implementado
> **Depende de:** SPEC 09, SPEC 16
> **Fecha:** 2026-08-15
> **Objetivo:** Reducir el tamaño y la duplicación de los scripts PowerShell con un módulo común de utilidades dot-sourceado, alta cohesión y bajo acoplamiento, sin cambiar ningún nombre de script, parámetro, código de salida, artefacto ni contrato persistido.

## Por qué existe esta SPEC

La auditoría del código PowerShell encontró duplicación sistemática: cuatro helpers de hash SHA256 con nombres distintos, tres wrappers de invocación de scripts hijo, cuatro resolutores de rutas relativas al repositorio, cuatro lectores directos de `configuracion.json` que ignoran `Cargar-Configuracion`, escritura atómica reimplementada cuatro veces, UTF-8 sin BOM inline en más de quince lugares, tres validadores de PDF `%PDF`, tres copias de `Quote-ProcessArgument`, tres lecturas del inventario `endpoints.json` y código muerto en `ValidarXPZ.ps1` (~170 líneas) que ya fue reemplazado por `CargarMultiXPZ.ps1`. `ExportarXPZSelectivo.ps1` es en gran parte una copia traducida de `ExportarXPZProgreso.ps1`, lo que facilita la divergencia silenciosa.

El refactor debe eliminar esa duplicación sin tocar la funcionalidad: la transaccionalidad de SPEC 16, el control de versiones con sus hashes publicados y las 138 pruebas de SPEC 09 deben seguir intactas.

## Alcance

**Incluido:**

- Nuevo `binary/GLMUtilidades.ps1`, dot-sourceado, hoja (sin dependencias de otros scripts del proyecto), con los helpers canónicos:
  - `Obtener-Sha256TextoNormalizado`, `Obtener-Sha256ArchivoNormalizado` (reemplazan `Obtener-Sha256TextoNormalizado` y `Obtener-Sha256ArchivoNormalizado` de `ActualizarServicios.ps1`, `Obtener-HashSha256Archivo` y `Obtener-ChecksumSemanticoObjeto` de `CargarMultiXPZ.ps1`, `Obtener-Sha256Archivo` de `GenerarPdfServicios.ps1` y los `Get-FileHash` inline).
  - `Normalizar-SaltosLineaLf`, `Escribir-TextoUtf8SinBom`, `Asegurar-Directorio`, `Escribir-ArchivoAtomico` (patrón tmp + guid, `.bak`, `File.Replace`, limpieza).
  - `Resolver-RutaRepositorio`, `Quote-ProcessArgument`, `Test-PdfValidoParaPromocion`, `Test-XpzValido` (apertura ZIP → XML único → raíz `ExportFile`), `Restaurar-ColorConsola`, `Inicializar-ConsolaUtf8`.
  - `Invocar-ScriptHijo` (unifica `Invocar-PowerShellScript`, `Invocar-Script` y `Invocar-ScriptPowerShell`, con normalización de códigos `0/1/2/3`).
  - `Leer-InventarioEndpoints`, `New-RegistroServicioControl`.
  - `Obtener-ReporteValidacionMasReciente`, `Obtener-ObjetosPendientes`, `Obtener-SignaturaPendientes`.
  - `Write-Step`, `Add-Line`.
- Eliminar de `ValidarXPZ.ps1` el código muerto: `Descubrir-XPZComplementarios`, `Merge-ListaIndice` y `Construir-IndiceMultiXPZ`.
- Mover `Establecer-PropiedadObjetoControl` de `ActualizarServicios.ps1` a `ControlVersiones.ps1`, junto a su par lector.
- Extraer en `ManifiestoEjecucion.ps1` el helper interno `Escribir-ManifiestoEjecucion` (hoy la persistencia está triplicada).
- Eliminar en `EscribirSalidas.ps1` el fallback local de nombre de archivo; usar siempre `Obtener-NombreArchivoServicio`.
- Reemplazar el parseo manual de `configuracion.json` en `GenerarPdfServicios.ps1` y `GestionDocumentosGLM.ps1` por `Cargar-Configuracion`.
- Consumir el módulo desde `GenerarDocumento.ps1`, `ActualizarServicios.ps1`, `CargarMultiXPZ.ps1`, `CargarConfiguracion.ps1`, `ManifiestoEjecucion.ps1`, `ControlVersiones.ps1`, `EscribirSalidas.ps1`, `EjecutarExportacionGLM.ps1`, `CompletarXPZActivoGLM.ps1`, `GestionDocumentosGLM.ps1`, `ExportarXPZProgreso.ps1`, `ExportarXPZSelectivo.ps1`, `GenerarPdfServicios.ps1`, `RenderizarMarkdownTypstPdf.ps1`, `ResumirOperacionPdf.ps1`, `GenerarListaEndpoints.ps1` y `GenerarVistaHTML.ps1`, eliminando los duplicados locales.
- Guarda de regresión de equivalencia de hashes: un caso de prueba verifica que los helpers unificados producen exactamente los mismos hashes que las implementaciones anteriores, para que los `documentHash`/`pdfHash` de `estado/controlVersiones.json` sigan siendo válidos y no se disparen bumps espurios.
- Ampliar `test/Run-Tests.ps1`: registrar el módulo en `Cargar-ModulosProduccion`, nuevas suites `utilidades.*` y suites `proceso.*` que invoquen como proceso hijo (con fixtures) a `GenerarDocumento.ps1`, `GenerarListaEndpoints.ps1`, `GenerarPdfServicios.ps1` y `DiagnosticoIA.ps1`, hoy sin cobertura directa.
- Actualizar `AGENTS.md` (estructura de trabajo) y `README.md` (conteo de pruebas si cambia).

**Fuera de alcance (para futuras SPEC):**

- Fusionar `ExportarXPZProgreso.ps1` y `ExportarXPZSelectivo.ps1` en un solo script parametrizado.
- Renombrar, mover o eliminar scripts existentes, incluidos `documentacion/Endpoints/binary/*`.
- Cambiar a módulos `.psm1` con `Import-Module`.
- Cambiar las reglas normativas de análisis, redacción o plantilla documental.
- Cambiar el esquema del control de versiones, el manifiesto de ejecución ni los estados persistidos.
- Cambios funcionales en el menú del lanzador, sus mensajes o su secuencia.
- Reducción del tamaño de `AnalizarServicio.ps1` (solo recibe el consumo del módulo, sin reestructuración interna).

## Modelo de datos

Esta SPEC no introduce estructuras persistidas nuevas: reutiliza el modelo de SPEC 16 (control de versiones `schemaVersion = 2`, manifiesto de ejecución, staging, review) y el inventario `endpoints.json` de SPEC 04.

Contrato del módulo nuevo: `binary/GLMUtilidades.ps1` se carga siempre con dot-source y **primero** respecto de cualquier otro script del proyecto; define solo funciones y no ejecuta lógica al cargarse. Sus funciones no escriben en el alcance global salvo el estado de consola que cada una gestiona. Las firmas canónicas conservan la forma de la implementación vigente que reemplazan; cuando existían variantes (p. ej. `Test-XpzFile` en inglés y en español), la canónica conserva la salida `Valid`/`Error` y los dos puntos de consumo internos de `ExportarXPZSelectivo.ps1` se adaptan a esa forma.

## Plan de implementación

1. Crear `binary/GLMUtilidades.ps1` con el grupo base: hash texto/archivo, normalización LF, escritura UTF-8 sin BOM, `Asegurar-Directorio`, `Escribir-ArchivoAtomico`, `Resolver-RutaRepositorio`, `Quote-ProcessArgument`, `Test-PdfValidoParaPromocion`, `Restaurar-ColorConsola`, `Inicializar-ConsolaUtf8`, `Write-Step` y `Add-Line`. Agregar la suite `utilidades.*` en `test/Run-Tests.ps1` y ejecutar la suite completa.
2. Agregar al módulo `Test-XpzValido`, `Invocar-ScriptHijo`, `Leer-InventarioEndpoints`, `New-RegistroServicioControl`, `Obtener-ReporteValidacionMasReciente`, `Obtener-ObjetosPendientes` y `Obtener-SignaturaPendientes`, con sus pruebas.
3. Eliminar el código muerto de `ValidarXPZ.ps1` (`Descubrir-XPZComplementarios`, `Merge-ListaIndice`, `Construir-IndiceMultiXPZ`) y ejecutar la suite.
4. Refactorizar hoja por hoja, un script por paso y con ejecución de la suite después de cada uno: `CargarMultiXPZ.ps1`, `ManifiestoEjecucion.ps1`, `ControlVersiones.ps1` (absorbe `Establecer-PropiedadObjetoControl`), `EscribirSalidas.ps1`, `RenderizarMarkdownTypstPdf.ps1`, `ResumirOperacionPdf.ps1`, `GenerarPdfServicios.ps1`.
5. Refactorizar los exportadores: `ExportarXPZProgreso.ps1`, `ExportarXPZSelectivo.ps1`, `EjecutarExportacionGLM.ps1`, `CompletarXPZActivoGLM.ps1`, `GestionDocumentosGLM.ps1`.
6. Refactorizar los orquestadores: `GenerarDocumento.ps1`, `ActualizarServicios.ps1`, y los scripts de `documentacion/Endpoints/binary/`.
7. Agregar las suites `proceso.*` (invocación real con fixtures de `GenerarDocumento.ps1`, `GenerarListaEndpoints.ps1`, `GenerarPdfServicios.ps1` y `DiagnosticoIA.ps1`) y el caso de equivalencia de hashes contra la implementación anterior y contra los artefactos publicados.
8. Actualizar `AGENTS.md` y `README.md`; ejecutar la suite completa y medir las líneas PowerShell antes y después (registro en `Logs/`).

## Criterios de aceptación

- [x] La suite completa (`test/Run-Tests.ps1`) termina con `0`: los casos existentes (adaptados solo donde referencian código movido) y los nuevos casos quedan en verde. **Resultado: 116 PASS, 0 FAIL, 4 SKIP (120 casos; base previa 95).**
- [x] Ningún nombre de script, parámetro externo, código de salida ni artefacto cambia respecto de SPEC 13/16.
- [x] El caso de equivalencia de hashes pasa: los helpers unificados producen hashes byte-idénticos a las implementaciones anteriores sobre los mismos contenidos (`utilidades.hashEquivalenciaImplementacionAnterior`).
- [x] Los `documentHash`/`pdfHash` de `estado/controlVersiones.json` siguen siendo válidos para los artefactos publicados: **206 servicios ACTIVO verificados, 0 hashes incoherentes**.
- [x] `ValidarXPZ.ps1` ya no contiene `Descubrir-XPZComplementarios`, `Merge-ListaIndice` ni `Construir-IndiceMultiXPZ` y el flujo de las opciones 1 y 3 conserva su secuencia.
- [x] Las suites `proceso.*` invocan los cuatro scripts hoy sin cobertura (`GenerarDocumento`, `GenerarPdfServicios`, `GenerarListaEndpoints`, `DiagnosticoIA`) y validan códigos de salida, review, staging y diagnóstico.
- [x] La cantidad de líneas de los scripts productivos (`binary/` + `documentacion/Endpoints/binary/`) es menor que antes del refactor: **9.530 → 9.406 (-124), con ~600 líneas duplicadas deduplicadas en `GLMUtilidades.ps1`**. El total del repositorio crece solo por las suites de prueba nuevas (+312 líneas en `test/Run-Tests.ps1`, intencional por la exigencia de regresión exhaustiva). Métricas registradas en `Logs/20260815-refactorizacion-spec18-metricas.txt`.
- [x] `AGENTS.md` describe `binary/GLMUtilidades.ps1` y el orden de carga obligatorio.

## Verificación de implementación

- `Logs/20260815-refactorizacion-spec18-metricas.txt` — métricas antes/después y resultado de la verificación de hashes.
- Caso `utilidades.hashEquivalenciaImplementacionAnterior` — guarda permanente de equivalencia contra la implementación anterior.
- Casos `proceso.generarDocumento` / `proceso.generarPdf` — invocación real por proceso sobre el XPZ activo en staging, sin escritura en carpetas productivas.

## Decisiones

- **Sí:** módulo común como `.ps1` dot-sourceado, no `.psm1`. Es consistente con el estilo actual y con el harness de pruebas, que ya dot-sourcea por nombre.
- **Sí:** alcance conservador. No se fusionan ni renombran scripts: el ahorro proviene de eliminar duplicación y código muerto, no de reestructurar la topología de procesos del menú.
- **Sí:** ampliar la cobertura de pruebas con invocación real por proceso para los cuatro scripts sin cobertura directa.
- **No:** fusión de `ExportarXPZProgreso.ps1` y `ExportarXPZSelectivo.ps1`. El riesgo de regresión en la exportación GeneXus es alto y el beneficio se evalúa en una SPEC futura dedicada.
- **No:** renombrar las funciones que las pruebas referencian por regex (`Promover-ServicioArtefactos`, `Marcar-ServicioSinPublicar`, `Quitar-FilaVersionDocumento`). Los cuerpos cambian; los nombres permanecen.
- **No:** reestructurar internamente `AnalizarServicio.ps1`. Solo consume el módulo para helpers compartidos; su refactor interno es otra SPEC.
- **Sí:** conservar las firmas canónicas vigentes; cuando existían variantes de la misma utilidad, prevalece la forma usada por el pipeline transaccional.
- **Sí (desviación registrada):** `Write-Step` permanece local en cada script. Las tres variantes imprimen formatos distintos (`[ n/5 ]`, texto plano, `[ n/3 ]`); unificarlas cambiaría la salida de consola. `Add-Line` sí se unificó.
- **Sí (desviación registrada):** `Obtener-ObjetosPendientes` unificado con la variante completa de `ExportarXPZSelectivo` (solicitudes.exportar → objectList → selectores). En `CompletarXPZActivoGLM` agrega el último recurso de selectores para reportes que no contienen `exportar` ni `objectList`.
- **Sí (corrección registrada):** `Invocar-ScriptHijo` corrige un bug latente del patrón original: con `$ErrorActionPreference = 'Stop'`, la primera línea de stderr de un proceso hijo nativo terminaba el pipeline padre con `NativeCommandError`; ahora la invocación captura y colorea la salida (el comportamiento que los wrappers originales declaraban) y normaliza opcionalmente los códigos `0/1/2/3`.
- **Sí (desviación registrada):** las lecturas directas de `configuracion.json` se reemplazaron por `Leer-ConfiguracionCruda` (módulo), no por `Cargar-Configuracion`, porque este último exige un XPZ activo y rompería flujos que solo necesitan propiedades crudas (`GestionDocumentosGLM` al arrancar, `GenerarPdfServicios` standalone).
- **Sí:** `binary/GLMUtilidades.ps1` se agregó a las rutas del perfil documental (`Obtener-FingerprintPerfilDocumental`) porque sus funciones participan del cálculo de hashes; el cambio de perfil regenera servicios sin bump cuando el contenido no cambia.

## Riesgos

| Riesgo | Mitigación |
| ------ | ---------- |
| Cambio sutil en hashes o normalización invalide `documentHash`/`pdfHash` existentes y dispare bumps espurios | Caso de equivalencia de hashes (implementación anterior vs. unificada) y verificación de solo lectura contra `estado/controlVersiones.json` antes de dar por terminada la SPEC |
| Aserciones por regex del harness apuntan a contenido interno de `ActualizarServicios.ps1` y `GestionDocumentosGLM.ps1` | Los nombres de funciones y marcadores persisten; se revisan los casos `integridad.*` y `estadoControl.contenido*` después de cada paso con la suite completa |
| Orden de dot-source incorrecto deje funciones sin definir | El módulo se carga primero en todos los consumidores; la suite carga `GLMUtilidades.ps1` como primer elemento de `Cargar-ModulosProduccion` |
| Divergencia entre variantes al unificar (p. ej. `Test-XpzFile` inglés/español) | La forma canónica conserva `Valid`/`Error`; los dos consumidores internos de `ExportarXPZSelectivo.ps1` se adaptan y la suite `utilidades.*` cubre el caso |
| Compatibilidad con Windows PowerShell 5.1 | Sin sintaxis nueva; toda función se escribe con los cmdlets y tipos ya usados en el repo |

## Lo que **no** incluye esta SPEC

- Fusión de scripts exportadores.
- Renombrado o reubicación de scripts.
- Módulos `.psm1`.
- Refactor interno de `AnalizarServicio.ps1`.
- Cambios en reglas normativas, plantilla, esquema de control o manifiesto.

Cada uno de esos temas, si se aborda, va en su propia SPEC.
