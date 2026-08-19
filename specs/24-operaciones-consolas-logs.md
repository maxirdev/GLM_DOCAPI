# SPEC 24 — Operaciones, consolas y trazabilidad del panel

> **Estado:** Aprobado
> **Depende de:** SPEC 22, SPEC 23
> **Fecha:** 2026-08-17
> **Objetivo:** Unificar la semántica de resultados operativos del panel, separar visualmente las consolas de Exportar y Generar PDF y registrar cada mutación con trazabilidad contextual completa.

## Por qué existe esta SPEC

El panel usa una única consola visual para procesos distintos y algunos tags describen la existencia de documentos en vez del resultado real de la operación mostrada. Esto puede presentar una consola terminada con error junto a un encabezado exitoso.

La exportación y la generación PDF deben mantener sus resultados independientes sin habilitar concurrencia. La solapa Logs también debe permitir reconstruir qué operación se ejecutó, en qué contexto, con qué XPZ y cuál fue su salida completa.

Esta SPEC no reemplaza el flujo de exportación y completitud existente. La exportación principal, la validación desde `APIGLM.APIGLMMain`, las exportaciones selectivas y la carga MultiXPZ continúan siendo responsabilidad exclusiva de los scripts actuales.

## Alcance

**Incluido:**

- Modificar `web/index.html`, `web/app.js`, `web/style.css`, `binary/ServidorPanelWeb.ps1`, los scripts operativos afectados y `test/Run-Tests.ps1`.
- Mantener un único trabajo activo global y el bloqueo de operaciones mutantes de SPEC 21.
- Crear una consola visual propia para `Exportar` y otra para `Generar PDF`.
- Conservar por solapa el último resultado y la última salida de su operación correspondiente.
- No mostrar en Exportar la consola de Generar PDF ni viceversa.
- Mostrar la consola de Generar PDF únicamente después de pulsar `Generar` y confirmar la operación.
- No mostrar consola en Documentación.
- Mantener en Documentación un aviso breve cuando una publicación en curso pueda cambiar los PDF.
- Simplificar los estados visibles a `EN PROCESO`, `COMPLETADO`, `COMPLETADO PARCIALMENTE` y `ERROR`.
- Mantener estados técnicos internos y códigos de salida para diagnóstico.
- Derivar tag, popup y consola del mismo resultado final de la operación.
- Mostrar `COMPLETADO PARCIALMENTE` cuando exista una salida utilizable con warnings o pendientes.
- Hacer que los procesos que continúan con pendientes devuelvan código `2` y no código `0`.
- Registrar una operación abortada internamente como `ABORTED` y mostrarla como `ERROR` con detalle `Operación abortada`.
- Mantener el flujo vigente de exportación XPZ, validación, exportación selectiva, revalidación y combinación MultiXPZ.
- Mantener un máximo de cinco ciclos de exportación selectiva según los scripts actuales.
- No trasladar al navegador la selección de objetos GeneXus ni las reglas de completitud.
- Mantener los complementos fuera de la lista de XPZ principales seleccionables.
- Activar automáticamente el XPZ producido cuando el archivo sea válido y la validación final confirme que está completo.
- Permitir que un XPZ completo permanezca activo aunque una etapa haya informado warnings; el tag conserva el resultado real de la operación.
- Limpiar siempre el XPZ activo cuando la operación no deje un XPZ válido o utilizable.
- Mostrar un warning cuando no se produzca un XPZ válido, indicando que puede exportarse manualmente y seleccionarse desde Generar PDF.
- Ofrecer en ese warning la acción `Ir a Generar PDF`.
- Mantener el resultado no exitoso en consola, tag y popup aunque exista otro XPZ anterior en la carpeta.
- Hacer que `Seleccionar` en Generar PDF únicamente active el XPZ en la sesión.
- No validar, completar, regenerar inventario ni generar PDF al pulsar `Seleccionar`.
- Mostrar la consola de ejecución solo después de iniciar la generación.
- Pedir confirmación antes de regenerar con el texto `¿Desea regenerar usando el XPZ activo <nombre>?`.
- Enviar al servidor el nombre y SHA-256 observados en la confirmación.
- Responder HTTP `409` y pedir una nueva confirmación si el XPZ activo o su hash cambió.
- Mostrar spinner y bloquear todo botón mientras espera su operación asincrónica.
- Registrar todas las mutaciones del panel, no las consultas GET.
- Incluir activación de contexto, CRUD de configuración, exportación, activación/validación de XPZ y generación PDF.
- Guardar por operación un manifiesto JSON y una salida completa en `Logs/operaciones/` del contexto.
- Permitir filtrar Logs por tipo de operación y severidad.
- Mostrar inicialmente el último registro de cada tipo del contexto activo.
- Permitir consultar el historial completo al elegir un tipo.
- No exponer rutas físicas locales en las respuestas de la API.
- Extender el harness con códigos de salida, estados, consolas, precondiciones XPZ, logs y aislamiento contextual.
- Verificar mediante Playwright MCP el servidor real, el fallo de GeneXus y una generación PDF real con Pandoc y Typst configurados.

**Fuera de alcance (para futuras SPEC):**

- Cambiar las reglas de `ValidarXPZ.ps1` o la receta de `ExportarXPZSelectivo.ps1`.
- Cambiar el descubrimiento de servicios desde `APIGLM.APIGLMMain`.
- Cambiar cómo `CargarMultiXPZ.ps1` combina principal y complementos.
- Mostrar complementos como XPZ principales independientes.
- Ejecutar Exportar y Generar PDF simultáneamente.
- Registrar lecturas GET del Dashboard, servicios, documentos o logs.
- Persistir credenciales, rutas físicas o contenido sensible en los manifiestos públicos.
- Agregar Node.js, npm o una suite Playwright versionada.
- Cambiar las reglas de análisis, versionado o publicación documental.

## Modelo de datos

### Estados visibles y técnicos

| Estado técnico | Código | Estado visible | Condición |
|---|---:|---|---|
| `QUEUED` / `RUNNING` | `null` | `EN PROCESO` | El trabajo espera o está ejecutándose. |
| `COMPLETED` | `0` | `COMPLETADO` | Terminó correctamente sin pendientes aceptados. |
| `PARTIAL` | `2` | `COMPLETADO PARCIALMENTE` | Existe resultado utilizable con warnings o pendientes. |
| `ABORTED` | `3` | `ERROR` | La operación fue abortada; el detalle debe indicarlo. |
| `FAILED` | otro | `ERROR` | Fallo fatal o resultado inutilizable. |

Reglas:

- El estado visible nunca se deduce de la existencia previa de documentos o de un XPZ anterior.
- `COMPLETADO` exige código `0` y cumplimiento de las poscondiciones de la operación.
- Continuar con pendientes produce código `2`.
- Un XPZ completo y validado puede quedar activo aunque la operación conserve warnings visibles.
- El detalle técnico y el código permanecen disponibles en Logs.

### Resultado por consola

El navegador conserva en memoria un resultado por operación visual:

```js
const operationResults = {
  exportar: {
    operationId: "<guid>",
    status: "ERROR",
    output: []
  },
  generarPdf: {
    operationId: "<guid>",
    status: "COMPLETADO",
    output: []
  }
};
```

Este estado no habilita concurrencia y no se persiste en localStorage.

### Confirmación de generación

`POST /api/generar-pdf` debe recibir la precondición observada:

```json
{
  "confirmRestart": true,
  "xpz": {
    "nombre": "SEGUROS_COMERCIAL_APIGLM_20260817_120000000.xpz",
    "sha256": "<sha256 completo>"
  }
}
```

El servidor compara nombre, pertenencia al contexto, XPZ activo y SHA-256 inmediatamente antes de iniciar el hijo. Cualquier divergencia devuelve HTTP `409` sin crear un trabajo.

### Registro de operación

Cada mutación crea dos archivos contextuales:

```text
<contexto>/Logs/operaciones/<operationId>.json
<contexto>/Logs/operaciones/<operationId>.log
```

El manifiesto mínimo es:

```json
{
  "schemaVersion": 1,
  "operationId": "<guid>",
  "contextId": "trunk/testing",
  "tipo": "EXPORTAR_XPZ",
  "severidad": "ERROR",
  "xpz": {
    "nombre": null,
    "sha256": null
  },
  "inicio": "2026-08-17T12:00:00.000Z",
  "fin": "2026-08-17T12:01:00.000Z",
  "estadoTecnico": "FAILED",
  "estadoVisible": "ERROR",
  "codigoSalida": 1,
  "warnings": [],
  "error": "El proceso hijo terminó con errores.",
  "logNombre": "<operationId>.log"
}
```

Convenciones:

- `operationId` correlaciona manifiesto, salida, API, consola y popup.
- `contextId` es obligatorio y coincide con el directorio dueño del registro.
- `tipo` admite como mínimo `ACTIVAR_CONTEXTO`, `CONFIGURACION_CLIENTE`, `CONFIGURACION_AMBIENTE`, `EXPORTAR_XPZ`, `ACTIVAR_XPZ`, `VALIDAR_XPZ` y `GENERAR_PDF`.
- Las eliminaciones y ediciones conservan el tipo de entidad y agregan la acción al detalle interno.
- `severidad` admite `INFO`, `WARNING` y `ERROR`.
- El `.log` contiene stdout y stderr completos, no solo las últimas veinte líneas.
- La API devuelve nombres lógicos, nunca rutas físicas.
- La vista inicial agrupa por `tipo` y elige el registro con `inicio` más reciente.

## Flujo XPZ y MultiXPZ que debe conservarse

1. `EjecutarExportacionGLM.ps1` exporta `Module:APIGLM` o toda la KB según `exportacion.onlyModuleAPIGLM`.
2. El XPZ principal debe ser un ZIP/XML válido antes de iniciar la completitud.
3. `ValidarXPZ.ps1` usa `APIGLM.APIGLMMain` para descubrir los servicios y detectar objetos faltantes.
4. Si existen faltantes exportables, el reporte produce los selectores confirmados.
5. `ExportarXPZSelectivo.ps1` genera el complemento junto al XPZ principal.
6. El proceso revalida y puede repetir hasta cinco ciclos mientras exista progreso.
7. `CargarMultiXPZ.ps1` combina el principal con sus complementos durante el análisis.
8. Si la validación final no tiene pendientes, la operación puede completar y el principal queda activo.
9. Si se acepta continuar con evidencia utilizable pero incompleta, el proceso termina con código `2`.
10. Si no existe un XPZ válido o una condición fatal impide continuar, termina con error y limpia la selección activa.

## Plan de implementación

1. Agregar fixtures y pruebas del mapeo técnico-visible, incluyendo códigos `0`, `2`, `3` y `1`.
2. Ajustar los scripts que hoy devuelven `0` al continuar con pendientes para que devuelvan `2`, sin cambiar la validación ni la exportación selectiva.
3. Extender `ServidorPanelWeb.ps1` para validar poscondiciones XPZ, publicar el estado semántico y activar únicamente resultados válidos según el flujo definido.
4. Implementar la selección pasiva de XPZ y retirar cualquier validación o regeneración automática disparada por `Seleccionar`.
5. Agregar la precondición nombre + SHA-256 a la confirmación y al endpoint de generación PDF.
6. Separar en HTML, JavaScript y CSS las consolas de Exportar y Generar PDF manteniendo el bloqueo global.
7. Unificar tag, popup y consola sobre el mismo resultado de trabajo y retirar la consola de Documentación.
8. Implementar `Logs/operaciones/`, escritura JSON validada y captura completa de stdout/stderr para trabajos y mutaciones sin proceso hijo.
9. Extender `GET /api/logs` para resumen del último registro por tipo, filtros por operación/severidad e historial, sin rutas físicas.
10. Agregar trazabilidad a activación de contexto, CRUD de configuración, exportación, activación/validación XPZ y generación PDF.
11. Ejecutar `test/Run-Tests.ps1` con dos contextos temporales y comprobar aislamiento, correlación y conservación del flujo MultiXPZ.
12. Ejecutar Playwright MCP contra el servidor real, provocar el fallo de GeneXus y comprobar consola, tag, popup, warning y navegación a Generar PDF.
13. Ejecutar mediante Playwright una generación PDF real con los Pandoc y Typst configurados y verificar resultado, log y descarga.
14. Completar la matriz visual y registrar sus resultados en la revisión de implementación.

## Criterios de aceptación

- [ ] Los únicos estados visibles de operaciones son `EN PROCESO`, `COMPLETADO`, `COMPLETADO PARCIALMENTE` y `ERROR`.
- [ ] Los estados técnicos y códigos de salida permanecen disponibles en la API y Logs.
- [ ] Código `0` se muestra como `COMPLETADO` solo si se cumplen las poscondiciones de la operación.
- [ ] Continuar con pendientes devuelve código `2` y se muestra como `COMPLETADO PARCIALMENTE`.
- [ ] Código `3` se registra como `ABORTED` y se muestra como `ERROR` con detalle de operación abortada.
- [ ] Un fallo fatal se registra como `FAILED` y se muestra como `ERROR`.
- [ ] Tag, popup y consola muestran el mismo resultado final.
- [ ] Exportar y Generar PDF tienen consolas visualmente independientes.
- [ ] Cambiar de solapa conserva el último resultado de cada consola.
- [ ] Sigue existiendo un único trabajo mutante activo en el servidor.
- [ ] La consola de Generar PDF permanece oculta hasta pulsar Generar y confirmar.
- [ ] Documentación no muestra consola ni salida de proceso.
- [ ] Documentación conserva un aviso breve cuando una publicación puede cambiar los PDF.
- [ ] La exportación continúa validando automáticamente el XPZ principal.
- [ ] Un XPZ incompleto dispara la exportación selectiva según el reporte de `ValidarXPZ.ps1`.
- [ ] La revalidación continúa hasta completar, detenerse sin progreso o alcanzar cinco ciclos.
- [ ] Los complementos se combinan mediante `CargarMultiXPZ.ps1` y no aparecen como principales seleccionables.
- [ ] El navegador no decide ni envía objetos GeneXus para la exportación selectiva.
- [ ] Un XPZ finalmente completo y válido queda activo para Generar PDF.
- [ ] Un resultado parcial utilizable conserva warnings y se muestra como `COMPLETADO PARCIALMENTE`.
- [ ] La ausencia de XPZ válido limpia siempre el XPZ activo.
- [ ] Cuando no existe XPZ válido se muestra un warning que explica la exportación manual.
- [ ] El warning ofrece `Ir a Generar PDF`.
- [ ] Pulsar `Seleccionar` solo activa el XPZ en sesión.
- [ ] Pulsar `Seleccionar` no valida, completa, regenera inventario ni genera PDF.
- [ ] Generar muestra el nombre del XPZ activo en el popup de confirmación.
- [ ] La confirmación envía nombre y SHA-256 completos.
- [ ] Un cambio de XPZ o hash produce HTTP `409` y no inicia un trabajo.
- [ ] Todo botón asincrónico muestra spinner, queda bloqueado y evita dobles envíos.
- [ ] Cada mutación crea `<operationId>.json` y `<operationId>.log` en `Logs/operaciones/` del contexto correcto.
- [ ] El manifiesto contiene identidad, tipo, severidad, XPZ, fechas, estados, código y nombre lógico del log.
- [ ] El `.log` conserva stdout y stderr completos.
- [ ] Las consultas GET no crean registros de operación.
- [ ] La vista inicial de Logs muestra el registro más reciente de cada tipo.
- [ ] Filtrar por tipo permite acceder a todo su historial.
- [ ] Los filtros combinan tipo de operación y severidad.
- [ ] La API de Logs no expone rutas físicas.
- [ ] Dos contextos no comparten manifiestos, salidas ni resúmenes.
- [ ] `test/Run-Tests.ps1` cubre estados, códigos, consolas, precondición XPZ, MultiXPZ, logs e aislamiento.
- [ ] Playwright verifica escritorio y móvil en tema claro y oscuro.
- [ ] Playwright verifica estados inicial, en proceso, completado, parcial y error.
- [ ] Playwright reproduce un fallo de GeneXus y valida la correspondencia entre consola, tag y popup.
- [ ] Playwright verifica el warning y la navegación hacia Generar PDF cuando no se produce un XPZ válido.
- [ ] Playwright ejecuta una generación PDF real con Pandoc y Typst configurados.
- [ ] Playwright verifica el PDF producido y su descarga desde el panel.
- [ ] Playwright no detecta errores en la consola del navegador.
- [ ] La revisión Playwright comprueba líneas incorrectas, títulos y descripciones incoherentes, textos cortados y elementos superpuestos.
- [ ] La matriz incluye foco visible y `prefers-reduced-motion`.
- [ ] Los resultados quedan consignados en la revisión sin agregar capturas, trazas, Node.js ni npm.

## Decisiones

- **Sí:** cuatro estados visibles. Son suficientes para distinguir espera, éxito total, resultado utilizable incompleto y fallo.
- **Sí:** conservar estados técnicos. Los logs necesitan diferenciar aborto, parcial y error fatal.
- **No:** usar el estado documental como resultado de Exportar. Son conceptos diferentes.
- **Sí:** código `2` para continuar con pendientes. Evita presentar una ejecución incompleta como éxito total.
- **Sí:** consolas independientes solo en la interfaz. El bloqueo global continúa evitando procesos incompatibles.
- **No:** duplicar el algoritmo XPZ/MultiXPZ en el panel. Los scripts existentes siguen siendo la fuente operativa.
- **Sí:** mantener exportación selectiva automática. Es parte del flujo actual de exportación y validación.
- **Sí:** selección XPZ pasiva. Elegir un archivo no equivale a generar ni validar.
- **Sí:** confirmar nombre y hash antes de generar. Evita operar sobre contenido distinto del aceptado por el usuario.
- **Sí:** JSON y log completo por operación. Permite filtrar y reconstruir la ejecución sin parsear texto para obtener metadatos.
- **Sí:** registrar todas las mutaciones y omitir consultas. Mantiene trazabilidad sin ruido de navegación.
- **Sí:** mostrar el último registro por tipo y conservar el historial completo.
- **Sí:** probar Pandoc y Typst reales y el fallo de GeneXus mediante Playwright MCP.
- **No:** incorporar una suite Playwright versionada. El repositorio continúa sin gestor de paquetes.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Un código `0` oculta pendientes aceptados | Cambiar esas salidas a código `2` y probar cada rama. |
| El tag y la consola usan fuentes distintas | Derivar ambos del mismo resultado de operación correlacionado. |
| Seleccionar un XPZ inicia trabajo accidentalmente | Separar el endpoint de activación pasiva de validación y generación. |
| El XPZ cambia mientras el usuario confirma | Validar nombre y SHA-256 inmediatamente antes de iniciar el trabajo. |
| Los complementos aparecen como principales | Mantener la clasificación compartida de `CargarMultiXPZ.ps1`. |
| La captura completa expone rutas en la API | Guardar localmente el contenido y devolver solo nombres allowlisted. |
| Logs de dos ambientes se mezclan | Escribir siempre bajo `DirectorioLogs` del contexto y validar `contextId`. |
| La prueba PDF depende de herramientas locales | Validar las rutas configuradas y reportar como bloqueo si Pandoc o Typst no están disponibles. |

## Lo que **no** incluye esta SPEC

- Nuevas reglas de completitud XPZ.
- Nuevas recetas de exportación selectiva.
- Selección de objetos GeneXus desde el navegador.
- Complementos visibles como XPZ principales.
- Trabajos mutantes concurrentes.
- Consola en Documentación.
- Registro de consultas GET.
- Persistencia de credenciales o rutas físicas en respuestas públicas.
- Cambios en análisis, versionado o publicación documental.
- Una suite Playwright versionada.

Cada modificación del algoritmo XPZ/MultiXPZ requiere una SPEC independiente.

## Revisión de implementación

Fecha: 2026-08-18

- `test/Run-Tests.ps1`: 232 casos, 0 fallos.
- Servidor real en loopback verificado mediante Playwright MCP.
- Escritorio: contexto, Exportar, Generar PDF, Documentación y Logs verificados.
- Móvil (390 x 844): warning, navegación a Generar PDF, selección de XPZ y consola PDF verificados; las solapas permanecen desplazables horizontalmente sin superposición.
- Tema claro y oscuro verificados.
- Foco visible verificado en controles interactivos durante la navegación.
- `prefers-reduced-motion`: regla CSS existente verificada; los spinners permanecen presentes y la animación se desactiva.
- Fallo real de GeneXus reproducido: tag, popup y consola mostraron `ERROR` con el mismo detalle.
- Ausencia de XPZ válido verificada: warning con acción `Ir a Generar PDF` y navegación correcta.
- Generación PDF real verificada con Pandoc y Typst configurados: `COMPLETED`, código `0`, 206 PDF publicados.
- Manifiesto `GENERAR_PDF` y log completo de stdout/stderr verificados en `Logs/operaciones/`.
- Descarga real de `wsautenticarusuario.pdf` verificada; PDF válido de dos páginas con contenido documental.
- Consola del navegador sin errores en la ejecución final; el error observado durante el fallo de GeneXus correspondió a la respuesta HTTP esperada de la operación fallida.
