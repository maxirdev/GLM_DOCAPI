# SPEC 04 — Menú interactivo con modos de generación y barra de progreso

> **Estado:** Implementado
> **Depende de:** SPEC 03
> **Fecha:** 2026-08-09
> **Objetivo:** Modificar `GenerarDocumentoServicio.cmd` y `GenerarDocumento.ps1` para ofrecer un menú previo con tres modos (servicio individual, selección múltiple vía `Out-GridView`, o lote completo), barra de progreso global, regeneración sin confirmación de archivos existentes, y log de errores al finalizar.

## Alcance

**Incluido:**

- Menú interactivo de 3 opciones al inicio de `GenerarDocumento.ps1`, antes de listar endpoints.
- Modo 1 — "Servicio particular": lista numerada + `Read-Host` (comportamiento actual, sin cambios funcionales salvo la sobrescritura).
- Modo 2 — "Múltiples servicios": `Out-GridView -OutputMode Multiple` con columnas `nombre` y `proceso`; selección con Ctrl+Click o Shift+Click; botón Aceptar confirma.
- Modo 3 — "TODOS": procesa la totalidad de `endpoints.json` sin interacción adicional.
- Barra de progreso global: contador `N/M` + porcentaje `XX%` que se actualiza por cada documento generado, aplicable a los modos 2 y 3. En modo 1 se omite (es un solo archivo).
- Sobrescritura siempre activa: `EscribirSalidas.ps1` ya no aborta si el archivo existe; lo regenera.
- Log de errores `documentacion/Generador/assets/logErrores.txt`: se crea solo si hubo al menos un fallo, con timestamp, `fullyQualifiedName` del servicio y mensaje del error.
- Contador final de éxito/fallos impreso en consola al terminar el lote.
- `GenerarDocumentoServicio.cmd` adaptado: el mensaje `[ 1/1 ] Generando documentación del servicio seleccionado...` se reemplaza por una línea genérica que refleje el modo elegido.
- Si el usuario cierra `Out-GridView` sin seleccionar (o Cancela), el script termina sin error.

**Excluido (para specs futuros):**

- Persistencia del menú entre sesiones (siempre arranca mostrando las 3 opciones).
- Ejecución desatendida con parámetros por línea de comandos.
- Filtro predefinido en `Out-GridView` (solo columnas, sin filtro inicial).
- Commit en git.

## Modelo de datos

Esta spec no introduce estructuras de datos persistentes nuevas. Los cambios son sobre los objetos en memoria dentro de `GenerarDocumento.ps1`:

```
$modoSeleccionado = 1 | 2 | 3
$serviciosSeleccionados = @(endpoint)  // array de objetos del inventario
$totalServicios = $serviciosSeleccionados.Count
$exitos = 0
$fallos = 0
$errores = @( <servicio, error> )  // solo en memoria; se vuelca al log si $fallos > 0
```

**Archivo de log (`documentacion/Generador/assets/logErrores.txt`):**

```
2026-08-09 14:30:12 | APIGLM.Emision.WSObtenerTotalesSolicitud | No se encontro el programa principal en el XPZ.
2026-08-09 14:30:15 | APIGLM.Siniestros.WSConsultarCobertura | El wrapper no cumple IsMain=True.
```

Cada línea es `timestamp | fullyQualifiedName | mensaje de error`. Se escribe en UTF-8 sin BOM, LF. Si el archivo ya existe de una ejecución anterior, se pisa (no se concatena).

## Plan de implementación

1. En `GenerarDocumento.ps1`, mover el encabezado y la carga de configuración + inventario antes del paso "Selección del servicio". Agregar el menú de 3 opciones con `Write-Host` + `Read-Host`. Validar entrada (1, 2 o 3). Si el usuario ingresa un valor inválido, repetir.

2. Implementar modo 1 — Servicio particular: mantener la lista numerada + `Read-Host` actual (paso `Write-Step 2` existente, sin cambios de lógica). Procesar un solo endpoint con la función `Procesar-Servicio` (nueva, ver paso 5).

3. Implementar modo 2 — Múltiples servicios: lanzar `$inventario.endpoints | Select-Object nombre, proceso | Out-GridView -OutputMode Multiple -Title "Seleccione los servicios (Ctrl+Click para múltiples)"`. Si el resultado es `$null` (usuario canceló), terminar sin error. Convertir los seleccionados de vuelta a objetos completos del inventario.

4. Implementar modo 3 — TODOS: `$serviciosSeleccionados = @($endpoints)`.

5. Extraer el bloque de procesamiento individual (análisis → redacción → escritura) a una función `Procesar-Servicio` que recibe un objeto endpoint y devuelve `$true`/`$false` (éxito/fallo). Internamente hace `try/catch`; en caso de error, registra en la lista `$errores` y retorna `$false` sin detener.

6. Agregar el bucle de procesamiento posterior al menú: iterar `$serviciosSeleccionados`, llamar a `Procesar-Servicio`, actualizar contadores `$exitos`/`$fallos`, y mostrar barra de progreso con `Write-Progress -Activity "Generando documentación de servicios" -PercentComplete (($i/$total)*100) -Status "Procesando $i de $total"`. En modo 1, saltar `Write-Progress` (es redundante para un solo archivo).

7. Modificar `EscribirSalidas.ps1`: eliminar las líneas 157–159 (bloque `if (Test-Path ...) { throw ... }`). El archivo se regenera siempre sin abortar.

8. Al final del bucle, imprimir resumen: `"Completado: $exitos exitos, $fallos fallos."`. Si `$fallos -gt 0`, escribir `logErrores.txt` en `documentacion/Generador/assets/` con el formato `timestamp | servicio | error` y mostrar su ruta.

9. Modificar `GenerarDocumentoServicio.cmd`: reemplazar la línea `echo [ 1/1 ] Generando documentación del servicio seleccionado...` por `echo Seleccione el modo de generacion en el menu interactivo.`.

10. Agregar `documentacion/Generador/assets/logErrores.txt` a `.gitignore`.

11. Verificación manual: ejecutar `GenerarDocumentoServicio.cmd` y probar los tres modos — particular (1 endpoint), múltiple (3 endpoints), TODOS (todos). Confirmar que la barra de progreso aparece en modos 2 y 3, que los archivos se regeneran aunque ya existan, y que el log de errores se genera solo cuando hay fallos.

## Criterios de aceptación

- [ ] Al ejecutar `GenerarDocumentoServicio.cmd` aparece un menú con 3 opciones numeradas antes de cualquier listado de endpoints.
- [ ] Opción 1 — Servicio particular: muestra la lista numerada actual y genera un solo documento, igual que antes, pero sobrescribe si el archivo ya existe.
- [ ] Opción 2 — Múltiples servicios: abre `Out-GridView` con columnas `nombre` y `proceso`; permite seleccionar múltiples filas con Ctrl+Click o Shift+Click; al confirmar, genera solo los documentos seleccionados.
- [ ] Opción 2 — Si el usuario cierra `Out-GridView` sin seleccionar (resultado `$null`), el script termina sin error y sin generar nada.
- [ ] Opción 3 — TODOS: genera documentos para todos los endpoints de `endpoints.json` sin interacción adicional.
- [ ] La barra de progreso `Write-Progress` aparece en modos 2 y 3, mostrando `N/M` y porcentaje; no aparece en modo 1.
- [ ] Al finalizar modos 2 o 3, se imprime en consola el resumen `"Completado: X exitos, Y fallos."`.
- [ ] Si hubo al menos un fallo, se genera `documentacion/Generador/assets/logErrores.txt` con timestamp, servicio y mensaje de error, UTF-8 sin BOM y LF.
- [ ] Si no hubo fallos, no se crea `logErrores.txt`.
- [ ] Un endpoint con error no detiene el procesamiento de los restantes.
- [ ] Los documentos ya existentes se regeneran sin preguntar (no hay `Test-Path` que aborte en `EscribirSalidas.ps1`).
- [ ] El menú acepta solo 1, 2 o 3; cualquier otra entrada repite la pregunta.
- [ ] `GenerarDocumentoServicio.cmd` muestra un mensaje genérico en lugar del antiguo `[ 1/1 ]`.
- [ ] `documentacion/Generador/assets/logErrores.txt` está en `.gitignore`.
- [ ] Los archivos generados son UTF-8 sin BOM con finales LF.
- [ ] No se creó commit en git.

## Decisiones

- **Sí:** `Out-GridView -OutputMode Multiple` para multi-selección. Es nativo de PowerShell 5.1, ofrece filtro en vivo y no requiere código de `ReadKey`. La contrapartida de requerir GUI se documenta como limitación conocida.
- **Sí:** Sobrescritura siempre activa (los 3 modos). El usuario decide regenerar; los pendientes editoriales ya están confirmados. Si quiere conservar una edición manual, usa git.
- **Sí:** Barra de progreso global (`Write-Progress`). Refleja el avance total del lote; en modo 1 se omite porque un solo archivo no la justifica.
- **Sí:** Log de errores en `documentacion/Generador/assets/logErrores.txt`, generado solo si hay fallos. Formato simple: `timestamp | servicio | error`. Se pisa en cada ejecución, no se concatena.
- **Sí:** Continuar ante errores. Un endpoint roto no debe bloquear la generación del resto; el fallo se registra y se sigue.
- **Sí:** Función `Procesar-Servicio` extraída del flujo actual. Evita duplicar las etapas de análisis → redacción → escritura en cada modo.
- **Sí:** Modificar `GenerarDocumentoServicio.cmd` y ambos `.ps1` (`GenerarDocumento.ps1`, `EscribirSalidas.ps1`). El menú vive en el orquestador PS; el `.cmd` solo cambia su mensaje.
- **No:** Parámetros por línea de comandos para modo desatendido (spec futura si se necesita).
- **No:** `Out-GridView` con preselección o filtros predefinidos.
- **No:** Commit en git.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| `Out-GridView` no disponible (sesión sin GUI, Core, SSH, CI/CD) | Se documenta como limitación: el modo 2 requiere entorno gráfico. Si falla, PowerShell arroja error claro; el usuario puede usar modo 1 o 3. |
| `Write-Progress` interfiere con `Out-GridView` si se invoca antes | `Out-GridView` se abre antes del bucle de procesamiento; `Write-Progress` solo corre durante la generación, después de cerrar la ventana. |
| El inventario `endpoints.json` tiene 135 endpoints; el lote completo puede tardar | El usuario es quien decide ejecutar "TODOS"; la barra de progreso muestra el avance. |
| `logErrores.txt` pisa ejecuciones anteriores | Es comportamiento deseado: cada ejecución es independiente. Si se necesita historial, usar git. |

## Lo que **no** incluye esta spec

- Persistencia de la opción de menú entre sesiones.
- Ejecución desatendida con parámetros (`-Modo 3`).
- Filtros predefinidos en `Out-GridView`.
- Commit en git.
- Cambios en `AnalizarServicio.ps1`, `RedactarDocumento.ps1` ni en los `.md` normativos.
