# SPEC 22 — Persistencia de contexto y ajustes del Dashboard

> **Estado:** Implementado
> **Depende de:** SPEC 21
> **Fecha:** 2026-08-17
> **Objetivo:** Persistir y restaurar de forma segura el contexto del panel y completar la respuesta visual del Dashboard durante la selección, validación y cambio de cliente y ambiente.

## Por qué existe esta SPEC

La sesión del servidor conserva un único contexto global, pero el navegador no recuerda la selección después de una recarga. Esto obliga a repetir la elección de cliente y ambiente y puede producir inconsistencias cuando otra pestaña cambia la sesión global.

El panel también necesita comunicar claramente las esperas, mostrar sin truncamiento la KB activa y eliminar mensajes que contradicen la existencia de un contexto válido.

## Alcance

**Incluido:**

- Modificar `web/index.html`, `web/app.js` y `web/style.css` sobre la implementación de SPEC 21.
- Persistir `clienteId` y `ambienteId` en `localStorage` después de activar correctamente un contexto.
- Usar la clave versionada `glm-panel-context:v1`.
- Restaurar automáticamente el contexto persistido al recargar la página.
- Validar el contexto persistido contra `GET /api/contextos` antes de intentar activarlo.
- Eliminar la clave persistida y pedir una nueva selección cuando el cliente o ambiente ya no exista o falle la activación.
- Mostrar un popup de error cuando no pueda restaurarse el contexto guardado.
- Comparar el contexto persistido con la sesión global devuelta por `GET /api/estado`.
- Mostrar un popup de decisión cuando el contexto del navegador y el contexto global del servidor sean distintos.
- Permitir elegir explícitamente cuál de los dos contextos debe prevalecer.
- No cargar datos dependientes del contexto hasta resolver el conflicto.
- Mantener la activación automática al elegir un ambiente; no agregar un botón `Activar contexto`.
- Limpiar inmediatamente la clave persistida y el estado visual dependiente al pulsar `Cambiar cliente`.
- Guardar el nuevo contexto únicamente después de que el servidor lo haya validado y activado.
- Bloquear los selectores durante la activación y mostrar un indicador de espera en el selector de ambiente.
- Mostrar spinner y estado ocupado en todos los botones cuya operación asincrónica requiera esperar una respuesta.
- Evitar dobles envíos mientras un selector o botón esté ocupado.
- Garantizar que `.spinner` y `.btn-spinner` giren mediante animación CSS.
- Respetar `prefers-reduced-motion` sin ocultar el estado ocupado.
- Mostrar el KPI `KB` completo, con el título en la primera línea y la ruta completa en la segunda.
- Permitir el ajuste de línea de la ruta de KB sin truncamiento horizontal ni superposición.
- Ocultar el mensaje `No existen servicios procesados en este ambiente` siempre que exista un contexto activo.
- Mantener los avisos específicos de ausencia de documentación o XPZ cuando correspondan.
- Agregar `margin-top: 10px` al contenido de las solapas que presentan tarjetas.
- Mantener el comportamiento responsive, los temas claro y oscuro y el foco visible de SPEC 21.
- Extender `test/Run-Tests.ps1` con los contratos estáticos y de API que puedan verificarse sin navegador.
- Verificar todos los criterios visuales e interactivos mediante Playwright MCP.

**Fuera de alcance (para futuras SPEC):**

- Cambiar el modelo multicliente de `configuracion.json`.
- Persistir el XPZ activo, consolas, filtros, paginación o selecciones documentales.
- Crear una sesión independiente del servidor por pestaña.
- Permitir trabajos simultáneos.
- Modificar los procesos de exportación, validación XPZ o generación PDF.
- Cambiar el CRUD de clientes y ambientes, que corresponde a SPEC 23.
- Cambiar las consolas operativas y la solapa Logs, que corresponden a SPEC 24.
- Agregar Node.js, npm o una suite Playwright versionada.

## Modelo de datos

### Contexto persistido

La única nueva persistencia del navegador usa esta clave:

```json
{
  "key": "glm-panel-context:v1",
  "value": {
    "clienteId": "trunk",
    "ambienteId": "testing"
  }
}
```

Convenciones:

- `clienteId` y `ambienteId` son IDs literales de `GET /api/contextos`.
- La clave no contiene nombres visibles, rutas físicas, XPZ, tokens ni datos derivados.
- Una estructura inválida se elimina sin intentar completarla ni migrarla.
- La clave se escribe solo después de una respuesta exitosa de `POST /api/contexto/activar`.
- Pulsar `Cambiar cliente` elimina la clave antes de habilitar los selectores.
- SPEC 23 eliminará la misma clave después de toda mutación válida de configuración.

### Conflicto de contexto

Existe conflicto cuando `GET /api/estado` informa un `contextId` distinto de la combinación válida almacenada en `glm-panel-context:v1`.

El popup debe ofrecer exactamente estas decisiones:

- `Usar contexto guardado`: invoca `POST /api/contexto/activar` con los IDs persistidos.
- `Usar contexto del servidor`: reemplaza la clave local con los IDs de la sesión global.

Cerrar el popup sin elegir no activa otro contexto ni carga artefactos contextuales.

### Estado ocupado

Los controles asincrónicos usan un estado común de interfaz:

```js
const pendingUi = {
  operation: "ACTIVAR_CONTEXTO",
  controlId: "environment-dropdown-trigger",
  pending: true
};
```

Este objeto es solo ilustrativo y vive en memoria. No se persiste entre recargas.

## Plan de implementación

1. Agregar al harness contratos para la clave `glm-panel-context:v1`, los textos del popup, el indicador ocupado, el KPI de KB y el espaciado de tarjetas.
2. Centralizar en `web/app.js` la lectura, validación, escritura y eliminación del contexto persistido.
3. Integrar la restauración con `loadContextsFromServer()` y `loadState()` sin cargar artefactos antes de resolver un conflicto.
4. Adaptar el cambio de cliente y la activación automática del ambiente para limpiar estado anterior, bloquear controles, mostrar espera y evitar solicitudes duplicadas.
5. Implementar el popup de conflicto y los errores de restauración reutilizando el sistema modal del panel.
6. Ajustar `renderDashboard()` y `renderGlobalNotices()` para mostrar la KB completa y retirar el mensaje de servicios cuando exista contexto.
7. Aplicar en `web/style.css` el espaciado de 10 px, el ajuste de línea de KB, los spinners animados y el comportamiento de movimiento reducido.
8. Ejecutar `test/Run-Tests.ps1` y corregir cualquier regresión de contratos del panel.
9. Ejecutar la matriz Playwright MCP contra `ServidorPanelWeb.ps1` y documentar los resultados en la revisión de implementación.

## Criterios de aceptación

- [ ] Activar correctamente un contexto guarda `clienteId` y `ambienteId` en `glm-panel-context:v1`.
- [ ] Recargar la página restaura automáticamente un contexto guardado y todavía válido.
- [ ] La restauración no infiere ni activa un XPZ.
- [ ] Un cliente o ambiente persistido que ya no existe elimina la clave y muestra un popup de error.
- [ ] Un fallo de `POST /api/contexto/activar` elimina la clave y deja los selectores disponibles para una nueva elección.
- [ ] Un conflicto entre localStorage y la sesión global muestra un popup antes de cargar datos contextuales.
- [ ] Elegir el contexto guardado activa ese contexto en el servidor y conserva la clave local.
- [ ] Elegir el contexto del servidor reemplaza la clave local sin activar un tercer contexto.
- [ ] Cerrar el popup sin decidir no mezcla datos de los dos contextos.
- [ ] Pulsar `Cambiar cliente` elimina inmediatamente la clave y limpia los datos visuales del contexto anterior.
- [ ] Elegir un ambiente continúa activando automáticamente el contexto, sin un botón adicional.
- [ ] Durante la activación, los selectores quedan bloqueados y el selector de ambiente indica la espera.
- [ ] Todo botón que inicia una operación asincrónica muestra spinner, queda bloqueado y evita dobles envíos hasta finalizar.
- [ ] Los spinners giran en condiciones normales.
- [ ] Con `prefers-reduced-motion`, el estado ocupado sigue siendo visible sin animación obligatoria.
- [ ] El KPI `KB` muestra su etiqueta en la primera línea y la ruta completa en la segunda.
- [ ] La ruta de KB no se trunca, no se superpone y se adapta al ancho disponible.
- [ ] Con contexto activo no aparece `No existen servicios procesados en este ambiente`.
- [ ] Sin contexto activo se conserva la indicación de seleccionar cliente y ambiente.
- [ ] Las solapas con tarjetas tienen 10 px de separación superior respecto de su encabezado o controles previos.
- [ ] El panel conserva foco visible y navegación por teclado durante selectores y popups.
- [ ] `test/Run-Tests.ps1` finaliza correctamente.
- [ ] Playwright verifica escritorio y móvil en tema claro y oscuro.
- [ ] Playwright verifica restauración válida, contexto obsoleto, fallo de activación y conflicto entre pestaña y servidor.
- [ ] Playwright verifica estados inicial, ocupado, exitoso y fallido de los controles afectados.
- [ ] Playwright no detecta errores en la consola del navegador.
- [ ] La revisión Playwright comprueba títulos, descripciones, líneas incorrectas, textos cortados y elementos superpuestos.
- [ ] Los resultados Playwright quedan consignados en la revisión sin agregar capturas, trazas ni dependencias al repositorio.

## Decisiones

- **Sí:** usar `localStorage`. La selección debe sobrevivir a una recarga del navegador.
- **Sí:** usar `glm-panel-context:v1`. La versión permite invalidar de forma segura un formato futuro.
- **Sí:** persistir cliente y ambiente. Ambos son necesarios para identificar un contexto canónico.
- **No:** persistir el XPZ activo. SPEC 19 exige una selección explícita por sesión.
- **Sí:** pedir una decisión ante conflicto con la sesión global. Ninguno de los dos contextos prevalece silenciosamente.
- **Sí:** mantener la activación automática al elegir ambiente. No se agrega un paso de confirmación nuevo.
- **Sí:** limpiar al pulsar `Cambiar cliente`. Evita presentar datos anteriores durante la nueva selección.
- **Sí:** mostrar espera en todo control asincrónico. El usuario debe reconocer que su acción sigue en curso.
- **No:** crear sesiones independientes por pestaña. El servidor conserva su contrato de sesión global.
- **Sí:** verificar con Playwright MCP. El repositorio continúa sin Node.js, npm ni paquetes frontend.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Dos pestañas alternan la sesión global | Detectar la divergencia al cargar y pedir una decisión explícita. |
| Un contexto eliminado queda guardado | Validarlo contra `GET /api/contextos` y eliminar la clave inválida. |
| Se muestran artefactos del contexto anterior durante una activación | Limpiar la vista antes de activar y no cargar artefactos hasta resolver el contexto. |
| Una respuesta lenta provoca envíos duplicados | Bloquear selectores y botones mientras exista una solicitud pendiente. |
| La ruta extensa de KB rompe el layout móvil | Permitir ajuste de línea y verificar bounding boxes con Playwright. |

## Lo que **no** incluye esta SPEC

- Persistencia del XPZ activo.
- Sesiones de servidor por pestaña.
- CRUD de configuración.
- Consolas independientes.
- Nuevos estados operativos.
- Catálogo estructurado de logs.
- Cambios en exportación, validación o generación PDF.
- Una suite Playwright versionada.

Cada uno de esos temas se mantiene en la SPEC correspondiente.

## Revisión de implementación

Fecha: 2026-08-17

- `test/Run-Tests.ps1`: 214 casos, 0 fallos.
- Escritorio (1249 x 800): carga del panel, restauración, Dashboard y ausencia de desbordamiento horizontal verificados.
- Móvil (390 x 844): ruta de KB ajustable, sin desbordamiento del documento y solapas desplazables verificadas.
- Tema claro y oscuro verificados.
- `prefers-reduced-motion` verificado: los spinners permanecen visibles sin animación.
- Restauración válida y contexto obsoleto verificados.
- Conflicto local/servidor verificado: decisiones guardada/servidor y cierre sin cargar artefactos.
- Fallo de activación verificado: clave eliminada y selectores liberados.
- Activación ocupada verificada: selectores bloqueados, `aria-busy` y spinner visibles.
- Cambio de cliente verificado: limpieza de estado y eliminación inmediata de la clave.
- Foco visible por teclado verificado.
- Consola del navegador sin errores en la ejecución final; el único error observado durante la matriz provino de la respuesta 400 simulada para probar el fallo de activación.
