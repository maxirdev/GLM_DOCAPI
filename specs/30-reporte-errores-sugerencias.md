# SPEC 30 — Reporte de errores y sugerencias

> **Estado:** Aprobado
> **Depende de:** SPEC 25, SPEC 26, SPEC 27, SPEC 28
> **Fecha:** 2026-08-26
> **Objetivo:** Permitir que el usuario registre desde el panel un error o una sugerencia asociado a un cliente, módulo y ambiente, con descripción e imágenes opcionales, y persistirlo localmente como Markdown catalogado.

## Por qué existe esta SPEC

El panel no ofrece actualmente un mecanismo para registrar problemas o comentarios durante su uso. Los reportes se comunican por canales externos y pueden perder el contexto operativo en el que ocurrió el problema.

La aplicación necesita una captura local sencilla que conserve la categoría, el contexto configurado, la descripción y una evidencia visual opcional sin incorporar servicios externos ni dependencias nuevas.

## Alcance

**Incluido:**

- Agregar en el header un botón con icono de bug inmediatamente antes del botón Configuración.
- Mantener el botón visible en escritorio y móvil.
- Habilitar el botón cuando `configuracion.json` sea válida y contenga al menos un contexto seleccionable.
- Deshabilitar el botón cuando la configuración esté bloqueada o no existan clientes y ambientes válidos.
- Explicar mediante `title` y texto accesible por qué el botón está deshabilitado.
- Abrir un popup accesible al pulsar el botón habilitado.
- Mostrar dentro del popup selectores en cascada para Cliente, Módulo y Ambiente.
- Obtener las opciones exclusivamente de los datos de configuración ya cargados por la aplicación.
- Precargar los tres selectores con el contexto activo cuando exista.
- Mantener los selectores sin una selección inventada cuando no exista contexto activo.
- Permitir elegir en el popup un contexto distinto sin activarlo como contexto operativo del panel.
- Exigir una combinación de Cliente, Módulo y Ambiente existente en la configuración vigente.
- Mostrar nombres legibles en los selectores y registrar nombres e IDs en el reporte.
- Incluir las categorías `Error` y `Sugerencia`.
- Preseleccionar la categoría `Error` al abrir un formulario nuevo.
- Exigir una descripción no vacía después de quitar espacios iniciales y finales.
- Limitar la descripción a 500 caracteres visibles Unicode.
- Mostrar un contador dinámico con formato `0/500`.
- Bloquear la entrada y el envío cuando se alcance o supere de manera inválida el límite acordado.
- Conservar saltos de línea y escapar sintaxis Markdown de la descripción para representarla como texto literal.
- Permitir adjuntar como máximo tres imágenes PNG, JPEG o WebP.
- Limitar cada imagen a 5 MiB decodificados.
- Validar en cliente y servidor el formato y el tamaño del adjunto.
- Enviar el formulario al servidor local mediante JSON y codificar las imágenes opcionales en Base64.
- Proteger la mutación con el token de sesión vigente del panel.
- Crear bajo demanda `reportes/errores/` o `reportes/sugerencias/` en la raíz del repositorio.
- Crear un archivo Markdown independiente por cada envío.
- Generar automáticamente un PDF independiente junto al Markdown de cada envío.
- Guardar las imágenes junto al Markdown correspondiente y referenciarlas mediante rutas relativas.
- Usar el mismo identificador base para el Markdown, el PDF y las imágenes.
- Nombrar cada reporte con timestamp UTC y un GUID de 32 caracteres hexadecimales.
- Mantener nombres que se ordenen alfabéticamente del reporte más antiguo al más reciente.
- Registrar en el Markdown ID, fecha UTC, categoría, cliente, módulo, ambiente, descripción y datos del adjunto cuando exista.
- Registrar los nombres originales de las imágenes únicamente como metadatos escapados.
- Escribir Markdown en UTF-8 sin BOM y con finales LF.
- Publicar Markdown, PDF e imágenes como una unidad y limpiar temporales o adjuntos huérfanos si falla la operación.
- Mostrar durante el envío un estado ocupado y evitar envíos duplicados.
- Reemplazar el formulario por una confirmación con check, el texto `El reporte se ha enviado con éxito` y un botón `Cerrar` después de persistirlo.
- Permitir cerrar la confirmación mediante el botón `Cerrar`, el control X y la tecla Escape.
- Reiniciar el formulario después de cerrar una confirmación exitosa.
- Conservar categoría, contexto, descripción e imágenes seleccionadas cuando la validación del servidor o la escritura fallen.
- Mostrar el error dentro del popup y permitir reintentar.
- Descartar sin confirmación los datos no enviados cuando el usuario cierre el formulario mediante X o Escape.
- Agregar `reportes/` a `.gitignore` como almacenamiento operativo local.
- Actualizar `web/version.md` con una nueva revisión que describa la incorporación de reportes.
- Extender `test/Run-Tests.ps1` con pruebas de API, validación, seguridad, persistencia y atomicidad.
- Verificar con Playwright MCP el popup en escritorio, móvil, tema claro y oscuro.

**Fuera de alcance (para futuras SPEC):**

- Listar, buscar, abrir o descargar reportes desde el panel.
- Editar, reclasificar o eliminar reportes existentes.
- Enviar reportes a una API remota, correo electrónico, sistema de tickets o repositorio externo.
- Incorporar estados de seguimiento, responsables, prioridades o conversaciones.
- Activar en el panel el contexto elegido dentro del popup.
- Adjuntar más de tres imágenes u otros tipos de archivo.
- Comprimir, redimensionar, recortar o editar imágenes.
- Persistir borradores entre aperturas del popup o sesiones del navegador.
- Crear reportes cuando la configuración global sea inválida.
- Versionar en Git los Markdown o imágenes generados.
- Incorporar autenticación, usuarios o identificación de la persona que reporta.
- Agregar dependencias, CDN, npm o un proceso de build.

## Modelo de datos

### Solicitud de creación

La nueva mutación será `POST /api/reportes` y aceptará exclusivamente `application/json`.

```json
{
  "category": "error",
  "context": {
    "clientId": "trunk",
    "module": "comercial",
    "environmentId": "testing"
  },
  "description": "La generación no muestra el resultado esperado.",
  "images": [
    {
      "originalName": "captura.png",
      "mimeType": "image/png",
      "base64": "<contenido Base64>"
    }
  ]
}
```

Convenciones:

- `category` admite únicamente `error` o `sugerencia`.
- `context.clientId`, `context.module` y `context.environmentId` son obligatorios.
- El servidor resuelve los nombres desde `configuracion.json`; no acepta nombres enviados por el navegador como fuente de verdad.
- La combinación contextual debe existir en la configuración vigente, pero no necesita coincidir con el contexto operativo activo.
- `description` es obligatoria y contiene entre 1 y 500 caracteres visibles Unicode después de recortar extremos.
- Navegador y servidor cuentan grafemas, no bytes ni unidades UTF-16 aisladas.
- `images` es opcional y, cuando existe, debe ser una lista de una a tres imágenes; cada elemento requiere sus tres propiedades.
- `mimeType` admite `image/png`, `image/jpeg` o `image/webp`.
- `base64` no incluye un prefijo data URI.
- El límite de 5 MiB se aplica a los bytes decodificados de cada imagen.
- El endpoint puede aceptar hasta 24 MiB de cuerpo para contemplar la expansión Base64 de hasta tres imágenes sin ampliar el límite de las demás mutaciones JSON.
- El servidor valida Base64, MIME declarado, firma binaria y extensión normalizada antes de escribir.
- El nombre original nunca se usa para construir una ruta física.
- El PDF se genera con Pandoc y Typst usando las imágenes de la carpeta del reporte como recursos relativos.
- La mutación requiere loopback y un `X-Panel-Token` válido.

### Respuesta exitosa

```json
{
  "ok": true,
  "data": {
    "id": "20260826T153045123Z-a1b2c3d4e5f6478899aabbccddeeff00",
    "category": "error",
    "createdAt": "2026-08-26T15:30:45.123Z"
  }
}
```

La respuesta no expone rutas físicas ni el contenido Base64 recibido.

Los errores usan el contrato JSON vigente del panel:

```json
{
  "ok": false,
  "error": "La imagen supera el límite de 5 MiB."
}
```

### Identidad y rutas

El ID base tendrá este formato:

```text
yyyyMMddTHHmmssfffZ-<guid-n>
```

`<guid-n>` representa un GUID aleatorio en formato `N`, con 32 caracteres hexadecimales y sin guiones.

Ejemplo sin adjunto:

```text
reportes/
`-- errores/
    `-- 20260826T153045123Z-a1b2c3d4e5f6478899aabbccddeeff00.md
```

Ejemplo con adjunto:

```text
reportes/
`-- sugerencias/
    |-- 20260826T154812987Z-00112233445566778899aabbccddeeff.md
    `-- 20260826T154812987Z-00112233445566778899aabbccddeeff.webp
```

La extensión almacenada se deriva del formato validado y se normaliza a `.png`, `.jpg` o `.webp`. No se conserva una extensión aportada por el usuario si no coincide con el contenido real.

El prefijo temporal UTC permite que una ordenación alfabética ascendente muestre primero los reportes más antiguos. El GUID evita colisiones sin requerir un contador persistido.

### Formato del Markdown

Cada reporte usa esta estructura:

```markdown
# Reporte de error

- **ID:** `20260826T153045123Z-a1b2c3d4e5f6478899aabbccddeeff00`
- **Fecha UTC:** `2026-08-26T15:30:45.123Z`
- **Categoría:** Error
- **Cliente:** Trunk (`trunk`)
- **Módulo:** Comercial (`comercial`)
- **Ambiente:** Testing (`testing`)

## Descripción

La generación no muestra el resultado esperado\.

## Adjuntos

- **Imagen 1:** `captura.png`

![Imagen adjunta 1](20260826T153045123Z-a1b2c3d4e5f6478899aabbccddeeff00-1.png)
```

Convenciones:

- El título será `Reporte de error` o `Reporte de sugerencia`.
- Los nombres e IDs contextuales se obtienen de la configuración validada.
- Los valores variables se escapan para que no alteren la estructura Markdown.
- La descripción conserva sus saltos de línea y se representa como texto literal escapado.
- La sección `Adjuntos` se omite completamente cuando no existen imágenes.
- Cada referencia de imagen contiene solo el nombre relativo, nunca una ruta absoluta.
- El Markdown termina con una única línea vacía.

### Estado del popup

```js
const reportFormState = {
  status: "editing",
  category: "error",
  clientId: "trunk",
  module: "comercial",
  environmentId: "testing",
  description: "",
  characterCount: 0,
  images: [],
  error: null
};
```

Estados válidos:

- `editing`: permite modificar y validar el formulario.
- `submitting`: bloquea controles, muestra progreso y evita doble envío.
- `success`: oculta el formulario y muestra check, mensaje y cierre.
- `error`: conserva el formulario y presenta un mensaje accionable.

El popup no persiste este estado en `localStorage` ni lo incorpora a `glm-panel-ui:v1`.

## Plan de implementación

1. Agregar fixtures y utilidades de prueba para solicitudes válidas, categorías inválidas, contextos inexistentes, descripciones límite e imágenes PNG, JPEG y WebP.
2. Agregar `reportes/` a `.gitignore` sin crear todavía carpetas operativas vacías.
3. Implementar en `binary/ServidorPanelWeb.ps1` la validación aislada del cuerpo JSON de reportes con un límite máximo propio de 24 MiB.
4. Implementar en el servidor la resolución del contexto solicitado contra `configuracion.json`, sin activar ni modificar el contexto operativo.
5. Implementar el conteo de grafemas y la validación de categoría, descripción, Base64, tamaño, MIME y firma binaria.
6. Implementar la generación del timestamp UTC, GUID, nombres normalizados y contenido Markdown escapado.
7. Implementar la creación bajo demanda de la carpeta de categoría y la publicación atómica de Markdown e imágenes, incluyendo limpieza ante fallos.
8. Exponer `POST /api/reportes` con validación loopback, token de sesión y respuestas JSON sin rutas físicas.
9. Crear `web/app/components/report-dialog.js` con selectores contextuales en cascada, categoría, textarea, contador, selector de hasta tres imágenes y estados de envío.
10. Agregar el nuevo módulo a la allowlist estática de `binary/ServidorPanelWeb.ps1` y registrarlo desde `web/app/main.js`.
11. Agregar en `web/index.html` el botón de bug antes de Configuración y el componente de popup con sus etiquetas accesibles.
12. Integrar desde `web/app.js` los datos de configuración, el contexto activo y la mutación sin alterar la activación contextual vigente.
13. Implementar la lectura de hasta tres imágenes y el envío Base64 reutilizando el token y el manejo común de errores del cliente API.
14. Agregar en `web/style.css` los estados responsive del botón, formulario, contador, error y confirmación para tema claro y oscuro.
15. Agregar al inicio de `web/version.md` la revisión `V1.1` con fecha y descripción de la nueva captura local de errores y sugerencias.
16. Extender `test/Run-Tests.ps1` con casos de autenticación, límites, firmas, traversal, contexto, contenido Markdown, orden de nombres y limpieza transaccional.
17. Ejecutar `test/Run-Tests.ps1` y comprobar que las APIs, configuración, contexto y operaciones vigentes no presentan regresiones.
18. Verificar mediante Playwright MCP apertura, precarga, cascada, validación, contador, adjunto, error, éxito, foco y cierre en escritorio y 390x844, en ambos temas.

## Criterios de aceptación

- [ ] El header muestra un botón con icono de bug inmediatamente antes de Configuración.
- [ ] El botón tiene nombre accesible y tooltip comprensible.
- [ ] El botón permanece visible en escritorio y móvil.
- [ ] Una configuración bloqueada mantiene el botón deshabilitado.
- [ ] La ausencia de contextos válidos mantiene el botón deshabilitado.
- [ ] Una configuración válida con contextos permite abrir el popup.
- [ ] El popup contiene selectores para Cliente, Módulo y Ambiente.
- [ ] Los selectores se cargan exclusivamente desde la configuración vigente.
- [ ] Módulo depende del Cliente seleccionado y Ambiente depende de Cliente y Módulo.
- [ ] El contexto activo se precarga cuando existe.
- [ ] Sin contexto activo no se inventa una selección completa.
- [ ] Elegir otro contexto en el popup no cambia el contexto activo del panel.
- [ ] Enviar exige una combinación contextual existente.
- [ ] El selector de categoría ofrece únicamente Error y Sugerencia.
- [ ] Error aparece preseleccionado al abrir un formulario limpio.
- [ ] La descripción vacía o compuesta solo por espacios se rechaza.
- [ ] El contador comienza en `0/500` y se actualiza al escribir.
- [ ] Navegador y servidor aplican un máximo de 500 caracteres visibles Unicode.
- [ ] Emojis y secuencias Unicode compuestas se cuentan por grafema visible.
- [ ] La descripción conserva saltos de línea en el Markdown.
- [ ] La sintaxis Markdown ingresada se guarda escapada y no altera la plantilla.
- [ ] El formulario admite como máximo tres imágenes.
- [ ] Se aceptan PNG, JPEG y WebP válidos de hasta 5 MiB por imagen.
- [ ] Un archivo con extensión permitida y firma binaria incompatible se rechaza.
- [ ] Una imagen mayor de 5 MiB se rechaza antes de persistirse.
- [ ] Un cuerpo Base64 inválido se rechaza sin crear archivos.
- [ ] `POST /api/reportes` exige `application/json`.
- [ ] La mutación rechaza solicitudes sin un token de sesión válido.
- [ ] La mutación rechaza solicitudes que no sean loopback.
- [ ] El límite ampliado del cuerpo se aplica solo a reportes y no modifica las demás APIs JSON.
- [ ] El servidor valida el contexto contra la configuración y no confía en nombres enviados por el navegador.
- [ ] La primera entrega de un error crea `reportes/errores/` bajo demanda.
- [ ] La primera entrega de una sugerencia crea `reportes/sugerencias/` bajo demanda.
- [ ] Cada envío crea exactamente un Markdown independiente.
- [ ] Cada envío crea exactamente un PDF junto al Markdown.
- [ ] Un envío con imágenes crea exactamente un Markdown, un PDF y una imagen adyacente por cada adjunto.
- [ ] Markdown, PDF e imágenes comparten el mismo identificador base.
- [ ] El nombre base usa timestamp UTC seguido por un GUID de 32 caracteres hexadecimales.
- [ ] Ordenar los Markdown ascendentemente por nombre presenta primero los más antiguos.
- [ ] El Markdown registra ID, fecha UTC, categoría, nombre e ID de Cliente, Módulo y Ambiente.
- [ ] El Markdown incluye la descripción literal escapada.
- [ ] La sección Adjuntos aparece solo cuando existen imágenes.
- [ ] Las imágenes se referencian mediante nombres relativos sin rutas físicas.
- [ ] El nombre original se registra como metadato y nunca se utiliza como ruta de salida.
- [ ] Los Markdown se escriben en UTF-8 sin BOM y con finales LF.
- [ ] Un fallo de escritura no deja un Markdown parcial, temporales o imágenes huérfanas.
- [ ] Un fallo de generación PDF elimina también los artefactos Markdown e imágenes ya preparados.
- [ ] Durante el envío los controles quedan bloqueados y no se admite doble envío.
- [ ] Un envío exitoso muestra un check y el texto `El reporte se ha enviado con éxito`.
- [ ] La confirmación puede cerrarse con `Cerrar`, X y Escape.
- [ ] Cerrar la confirmación reinicia todos los campos del formulario.
- [ ] Un fallo conserva categoría, contexto, descripción e imágenes para reintentar.
- [ ] Cerrar un formulario no enviado descarta sus datos sin mostrar confirmación.
- [ ] Cerrar el popup devuelve el foco al botón de bug.
- [ ] El foco permanece contenido en el popup mientras está abierto.
- [ ] `reportes/` está incluido en `.gitignore`.
- [ ] Los reportes generados no aparecen como archivos pendientes de Git.
- [ ] `web/version.md` comienza con `V1.1` y describe la funcionalidad de reportes.
- [ ] El panel continúa funcionando sin npm, CDN ni dependencias de terceros.
- [ ] `test/Run-Tests.ps1` cubre validación, seguridad, persistencia y limpieza ante fallos.
- [ ] `test/Run-Tests.ps1` termina sin regresiones.
- [ ] Playwright MCP no detecta errores de consola durante el flujo.
- [ ] El popup funciona en escritorio y 390x844.
- [ ] Botón, formulario, errores y confirmación son legibles en tema claro y oscuro.

## Decisiones

- **Sí:** usar un botón con icono de bug antes de Configuración. Mantiene la acción global visible sin agregar otra solapa.
- **Sí:** mostrar selectores en cascada dentro del popup. El reporte puede referirse a un contexto configurado distinto del contexto operativo actual.
- **Sí:** precargar el contexto activo. Reduce pasos sin impedir una selección explícita diferente.
- **No:** activar el contexto elegido. Reportar no debe alterar el estado operativo ni interrumpir trabajos.
- **Sí:** deshabilitar el botón con configuración inválida o sin opciones. Los tres datos contextuales son obligatorios y no pueden inventarse.
- **Sí:** preseleccionar Error. Es la categoría inicial solicitada y Sugerencia permanece disponible.
- **Sí:** exigir categoría, contexto y descripción. Evita reportes sin información mínima para analizarlos.
- **Sí:** contar 500 caracteres visibles Unicode. El límite debe coincidir con lo que percibe el usuario.
- **Sí:** escapar la descripción como texto literal. El contenido del usuario no debe modificar la estructura del documento.
- **Sí:** admitir hasta tres imágenes PNG, JPEG o WebP de hasta 5 MiB cada una. Permite documentar un problema con varias capturas sin abrir otra mutación.
- **No:** admitir más de tres adjuntos, archivos generales o selección ilimitada. Aumentaría validaciones, almacenamiento y superficie de ataque sin necesidad actual.
- **Sí:** usar JSON con Base64. Reutiliza el cliente y el contrato de mutaciones vigente sin implementar un parser multipart propio en Windows PowerShell 5.1.
- **Sí:** aplicar 24 MiB solo al endpoint de reportes. Contempla la expansión Base64 de hasta tres imágenes sin relajar el límite global existente.
- **Sí:** usar una carpeta global `reportes/`. Los metadatos conservan el contexto y las categorías ofrecen la separación principal solicitada.
- **Sí:** usar `reportes/errores/` y `reportes/sugerencias/`. Los nombres corresponden a las dos categorías cerradas.
- **Sí:** crear las carpetas bajo demanda. Evita estructura operativa vacía antes del primer uso.
- **Sí:** crear un Markdown por envío. Simplifica atomicidad, adjuntos, orden y trazabilidad.
- **No:** agregar comentarios a un único archivo por categoría o contexto. Una escritura fallida o concurrente afectaría un historial compartido.
- **Sí:** usar timestamp UTC y GUID en formato `N`. El timestamp conserva orden y el GUID evita colisiones sin contador.
- **Sí:** guardar las imágenes junto al Markdown. Las referencias relativas permanecen simples y autocontenidas dentro de la categoría.
- **Sí:** registrar el nombre original como metadato. Aporta contexto sin confiar en él para construir rutas.
- **Sí:** ignorar `reportes/` en Git. Es información operativa local y potencialmente voluminosa.
- **Sí:** conservar el formulario ante fallos. El usuario puede corregir o reintentar sin volver a escribir la descripción.
- **Sí:** mostrar una confirmación dentro del popup. El check y el mensaje ofrecen un resultado explícito antes del cierre.
- **Sí:** descartar formularios no enviados sin confirmación. El contenido es breve, no se persisten borradores y se acordó un cierre directo.
- **No:** agregar consulta, edición, eliminación o envío remoto. Cada capacidad requiere reglas de seguridad y ciclo de vida propias.
- **Sí:** actualizar `web/version.md` a `V1.1`. La funcionalidad visible debe cumplir el contrato manual de versión de SPEC 28.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Una imagen falsa usa una extensión permitida | Validar MIME, Base64, firma binaria y tamaño decodificado en el servidor. |
| El nombre original intenta traversal o contiene Markdown | No usarlo en rutas y escaparlo antes de registrarlo como metadato. |
| Base64 aumenta el tamaño de la solicitud | Limitar cada adjunto a 5 MiB y el cuerpo exclusivo de esta API a 24 MiB. |
| Cliente y servidor cuentan distinto un emoji compuesto | Contar grafemas Unicode en ambos extremos y cubrirlos con casos compartidos. |
| Dos reportes se crean casi simultáneamente | Incorporar un GUID aleatorio de 32 caracteres al timestamp UTC. |
| Falla la escritura después de crear la imagen | Preparar temporales, publicar como unidad y eliminar cualquier adjunto huérfano. |
| Un contexto cambia o se elimina mientras el popup está abierto | Validar nuevamente la combinación contra la configuración al recibir el envío. |
| La descripción inyecta estructura o enlaces Markdown | Escapar caracteres estructurales y conservar el texto como contenido literal. |
| Las imágenes consumen espacio de disco sin mantenimiento | Mantener el límite por archivo y dejar consulta, retención y eliminación para una SPEC posterior. |
| Los reportes contienen información operativa sensible | Mantenerlos locales, ignorados por Git y sin exponer una API de lectura. |

## Lo que **no** incluye esta SPEC

- Una vista de reportes dentro del panel.
- Consulta, descarga, edición, reclasificación o eliminación.
- Estados, prioridades, responsables o seguimiento.
- Correos, webhooks, tickets o sincronización externa.
- Identificación o autenticación de usuarios.
- Activación del contexto seleccionado para reportar.
- Múltiples imágenes u otros adjuntos.
- Edición o compresión de imágenes.
- Borradores persistentes.
- Reportes sin configuración válida.
- Versionado de reportes en Git.
- npm, CDN, librerías o servicios de terceros.

Cada ampliación del ciclo de vida de los reportes debe definir en otra SPEC su acceso, retención, seguridad y comportamiento ante concurrencia.
