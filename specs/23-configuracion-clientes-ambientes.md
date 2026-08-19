# SPEC 23 — Configuración de clientes y ambientes

> **Estado:** Aprobado
> **Depende de:** SPEC 22
> **Fecha:** 2026-08-17
> **Objetivo:** Completar el CRUD web de clientes y ambientes con escritura atómica, concurrencia optimista, popups coherentes y pruebas que garanticen la actualización correcta de `configuracion.json`.

## Por qué existe esta SPEC

El panel presenta acciones para administrar clientes y ambientes, pero el alta de un cliente sin ambientes contradice la validación de SPEC 19. Además, el hash de concurrencia se muestra como dato técnico, las confirmaciones mezclan modales con mensajes de fondo y faltan pruebas de API que demuestren que una mutación válida actualiza el JSON sin corromperlo.

Esta SPEC mantiene el esquema vigente: un cliente se crea junto con su primer ambiente y nunca se persiste un estado intermedio inválido.

## Alcance

**Incluido:**

- Modificar `web/index.html`, `web/app.js`, `web/style.css`, `binary/ServidorPanelWeb.ps1` y `test/Run-Tests.ps1`.
- Limitar la pantalla al CRUD de clientes y ambientes.
- Crear un cliente y su primer ambiente mediante un único popup y una única escritura atómica.
- Exigir en el alta de cliente `id`, `nombre`, `packagename` y los datos completos del primer ambiente.
- Mantener `serviciosIgnorados` como colección vacía en un cliente nuevo.
- Permitir agregar un segundo ambiente únicamente si corresponde al tipo faltante entre `test` y `prod`.
- No mostrar la acción `Agregar ambiente` cuando el cliente ya tenga ambos tipos.
- Rechazar desde el servidor un tercer ambiente o un tipo duplicado aunque el cliente omita la validación del navegador.
- Mantener los IDs existentes inmutables durante la edición.
- Conservar el árbol contextual al eliminar clientes o ambientes.
- Mantener `configHash` como control de concurrencia optimista.
- No mostrar el hash, un resumen del hash ni atributos `data-hash` en la interfaz.
- Conservar el hash únicamente en el estado JavaScript y enviarlo en cada mutación.
- Reemplazar los mensajes de fondo y `window.confirm` de Configuración por popups propios.
- Mostrar en popup los formularios, confirmaciones, validaciones, resultados exitosos y errores.
- Mantener abierto el popup ante errores corregibles y conservar los valores ingresados.
- Ubicar las acciones de cada popup en un pie alineado abajo y a la derecha.
- Quitar el borde visual de Guardar, Cancelar, Confirmar y Cerrar dentro de los popups.
- Mantener foco visible, orden de tabulación, cierre accesible y retorno del foco al control que abrió el popup.
- Validar el candidato completo antes de escribir.
- Escribir `configuracion.json` atómicamente y recalcular `configHash` después de cada mutación válida.
- No modificar el archivo ante hash obsoleto, payload inválido, conflicto de IDs o error de escritura.
- Reiniciar el contexto y XPZ activos del servidor después de toda mutación válida.
- Eliminar `glm-panel-context:v1` después de toda mutación válida, aunque afecte otro contexto.
- Ejecutar pruebas de escritura contra copias temporales de `configuracion.json`, nunca contra el archivo real.
- Extender el harness con altas, ediciones, bajas, conflictos y conservación byte a byte ante errores.
- Verificar la experiencia completa mediante Playwright MCP.

**Fuera de alcance (para futuras SPEC):**

- Cambiar el esquema multicliente o admitir clientes sin ambientes.
- Editar herramientas globales, `clientesRoot`, `onlyModuleAPIGLM` o el puerto del panel.
- Editar `serviciosIgnorados` desde la interfaz.
- Cambiar rutas o mover artefactos al renombrar entidades.
- Borrar carpetas contextuales al eliminar una configuración.
- Mostrar `configHash` con fines diagnósticos.
- Agregar una suite Playwright versionada.
- Cambiar la exportación, generación PDF o catalogación de logs de SPEC 24.

## Modelo de datos

### Alta transaccional de cliente

El popup debe construir un único payload válido:

```json
{
  "configHash": "<sha256 vigente>",
  "id": "nuevo-cliente",
  "nombre": "Nuevo cliente",
  "packagename": "glmsuit.comercial.",
  "serviciosIgnorados": [],
  "ambientes": [
    {
      "id": "testing",
      "nombre": "Testing",
      "tipo": "test",
      "kbPath": "C:/KBs/NUEVO_CLIENTE"
    }
  ]
}
```

Convenciones:

- El cliente y su primer ambiente se validan y escriben en una sola transacción.
- `id` cumple `^[a-z0-9][a-z0-9-]*$`.
- `tipo` acepta únicamente `test` o `prod`.
- Los IDs son únicos sin distinguir mayúsculas en su nivel.
- `kbPath` no puede normalizar a la ruta de otro ambiente.
- No se crea una carpeta contextual hasta que el candidato completo sea válido.

### Estado interno de configuración

El navegador mantiene el hash sin renderizarlo:

```js
const configurationState = {
  configHash: "<sha256 completo>",
  configuration: {}
};
```

`configHash` no debe copiarse a `textContent`, atributos `data-*`, campos ocultos ni mensajes visibles.

### Resultado de mutación

Una respuesta exitosa devuelve la configuración validada y su hash nuevo. Una respuesta con conflicto devuelve HTTP `409` y no escribe archivos. Los errores de validación devuelven un mensaje concreto y tampoco escriben archivos.

## Plan de implementación

1. Crear fixtures temporales de configuración para alta conjunta, segundo ambiente, tipos completos, hash obsoleto, IDs duplicados y KB duplicada.
2. Extender el harness para iniciar `ServidorPanelWeb.ps1` con una copia temporal y comprobar el contenido del archivo después de cada request.
3. Ajustar el contrato de `POST /api/configuracion/clientes` para recibir y validar cliente y primer ambiente en una sola mutación.
4. Mantener la validación completa y la escritura atómica, demostrando que cualquier error conserva byte a byte el archivo anterior.
5. Retirar el badge y cualquier `data-hash` de `web/index.html` y mantener el hash solo en el estado de `web/app.js`.
6. Reorganizar los formularios y confirmaciones de Configuración como popups propios con gestión accesible del foco.
7. Implementar mensajes de éxito, error y validación dentro de popups, sin mensajes persistentes en el fondo de la aplicación.
8. Ajustar el pie de acciones y ocultar `Agregar ambiente` cuando existan TEST y PROD.
9. Limpiar la sesión del servidor y `glm-panel-context:v1` después de una mutación válida y recargar la configuración.
10. Ejecutar la suite PowerShell completa y verificar que el `configuracion.json` real no cambió.
11. Ejecutar la matriz Playwright MCP con configuración temporal y documentar los resultados en la revisión.

## Criterios de aceptación

- [ ] `Agregar cliente` abre un popup que incluye los datos del cliente y de su primer ambiente.
- [ ] No es posible enviar el alta sin un primer ambiente completo.
- [ ] Una única respuesta exitosa agrega el cliente y su ambiente a la copia de `configuracion.json`.
- [ ] El cliente nuevo contiene `serviciosIgnorados: []`.
- [ ] El JSON escrito puede volver a cargarse mediante `Cargar-Configuracion.ps1`.
- [ ] Un cliente con solo TEST ofrece agregar únicamente PROD.
- [ ] Un cliente con solo PROD ofrece agregar únicamente TEST.
- [ ] Un cliente con TEST y PROD no muestra `Agregar ambiente`.
- [ ] El servidor rechaza un tercer ambiente o un tipo repetido aunque se invoque la API directamente.
- [ ] Editar cliente o ambiente conserva su ID original.
- [ ] Eliminar requiere una confirmación en popup y no usa `window.confirm`.
- [ ] Cancelar una eliminación no envía una mutación.
- [ ] Eliminar configuración no borra el árbol contextual existente.
- [ ] No existe un badge, texto visible, campo oculto ni atributo `data-hash` con `configHash`.
- [ ] Cada mutación continúa enviando el `configHash` completo desde el estado JavaScript.
- [ ] Un hash obsoleto produce HTTP `409` y conserva byte a byte el archivo anterior.
- [ ] Un payload inválido conserva byte a byte el archivo anterior.
- [ ] Una KB duplicada o un ID duplicado se rechaza antes de escribir.
- [ ] Una mutación válida usa escritura atómica y devuelve un hash diferente cuando cambió el contenido.
- [ ] Todo éxito, error, validación y confirmación de Configuración se muestra en un popup propio.
- [ ] Un error corregible conserva el popup y los valores introducidos.
- [ ] Las acciones de popup están alineadas abajo a la derecha y no tienen borde visual.
- [ ] El foco queda contenido correctamente en el popup y vuelve al control de origen al cerrarlo.
- [ ] Toda mutación válida reinicia contexto y XPZ de la sesión del servidor.
- [ ] Toda mutación válida elimina `glm-panel-context:v1`.
- [ ] Las pruebas de escritura usan una copia temporal y no modifican `configuracion.json` real.
- [ ] `test/Run-Tests.ps1` cubre alta, edición, baja, hash obsoleto, candidato inválido y atomicidad.
- [ ] Playwright verifica altas, ediciones, bajas, cancelaciones y errores en escritorio y móvil.
- [ ] Playwright ejecuta la matriz en tema claro y oscuro y con movimiento normal y reducido.
- [ ] Playwright no detecta errores en la consola del navegador.
- [ ] La revisión Playwright detecta textos incorrectos, títulos o descripciones incoherentes, desbordamientos y superposiciones.
- [ ] Los resultados Playwright quedan consignados en la revisión sin versionar capturas ni trazas.

## Decisiones

- **Sí:** crear cliente y primer ambiente juntos. El esquema nunca admite un cliente temporalmente inválido.
- **No:** relajar SPEC 19 para permitir clientes sin ambientes. Introduciría estados que el pipeline no puede resolver.
- **Sí:** limitar esta pantalla a clientes y ambientes. Las opciones globales quedan fuera del pedido actual.
- **Sí:** conservar `configHash` internamente. Evita sobrescribir cambios concurrentes.
- **No:** mostrar el hash o guardarlo en el DOM. Es un detalle técnico sin valor operativo para el usuario.
- **Sí:** usar popups propios para todos los mensajes y decisiones de Configuración. Mantiene el contexto de la acción y una respuesta visual uniforme.
- **No:** usar `window.confirm`. No respeta el sistema visual ni permite presentar detalles suficientes.
- **Sí:** limpiar siempre el contexto persistido después de guardar. La mutación reinicia también la sesión global.
- **Sí:** probar contra copias temporales. La suite nunca debe alterar la configuración operativa real.
- **Sí:** verificar con Playwright MCP sin incorporar Node.js ni npm.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Una prueba modifica la configuración real | Exigir `-ConfigPath` temporal y comprobar el hash del archivo real antes y después. |
| Dos pestañas sobrescriben cambios | Mantener `configHash` obligatorio y responder `409` sin escritura. |
| El frontend oculta una opción pero la API permite un tercer ambiente | Revalidar siempre el candidato completo en el servidor. |
| Se crea un cliente sin ambiente por una escritura parcial | Enviar una sola mutación y publicar únicamente el JSON completo validado. |
| El popup pierde foco o queda fuera de pantalla | Aplicar gestión de foco y verificar escritorio y móvil con Playwright. |

## Lo que **no** incluye esta SPEC

- Clientes sin ambientes.
- Edición de herramientas o rutas globales.
- Edición de servicios ignorados.
- Eliminación de artefactos contextuales.
- Visualización de `configHash`.
- Cambios en exportación o generación PDF.
- Cambios en Logs.
- Una suite Playwright versionada.

Cada ampliación de la configuración global requiere una SPEC posterior.
