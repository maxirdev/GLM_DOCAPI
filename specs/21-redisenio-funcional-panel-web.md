# SPEC 21 — Rediseño funcional del panel web

> **Estado:** Implementado
> **Depende de:** SPEC 15
> **Fecha:** 2026-08-17
> **Objetivo:** Rediseñar y completar el panel web local para ofrecer un Dashboard contextual, una vista unificada de endpoints y documentación, y funcionalidad operativa consistente en todas sus solapas.

## Por qué existe esta SPEC

La SPEC 15 estableció el panel web y sus contratos operativos, pero la interfaz actual conserva solapas incompletas, separa Documentación y Documentos, y no presenta en una vista común el endpoint, su versión documental, su estado y su PDF.

Los mockups de `resources/mockups-panel-api/` definen una referencia visual más completa que la implementación vigente. Esta SPEC adapta ese sistema visual al producto real, incorpora Poppins desde los recursos locales del repositorio y completa los estados de contexto, trabajos, inventario obsoleto y configuración inválida.

## Alcance

**Incluido:**

- Rediseñar `web/index.html`, `web/app.js` y `web/style.css` tomando como base visual los mockups de `resources/mockups-panel-api/`.
- Usar el sistema visual base de los mockups, sin exigir una réplica literal de cada archivo.
- Usar Poppins desde `binary/fonts/Poppins-Regular.ttf`, `Poppins-SemiBold.ttf` y `Poppins-Bold.ttf`.
- Exponer las fuentes mediante una ruta estática allowlisted del servidor, sin CDN, fuentes remotas ni duplicación de los archivos.
- Cambiar la solapa `Estado` por `Dashboard`.
- Mantener las solapas `XPZ`, `Exportar`, `Endpoints`, `Logs` y `Configuración`.
- Unificar `Documentación` y `Documentos` en una única solapa `Documentación`.
- Eliminar la solapa independiente `Documentos` de la navegación.
- Mostrar en `Dashboard`, con contexto activo, el contexto, la KB, el inventario, los documentos, el último review, los XPZ disponibles y activo, el hash del XPZ, las herramientas y el trabajo en curso.
- Mostrar el trabajo activo en `Dashboard` y mediante un indicador compacto persistente en el encabezado.
- Mantener disponibles las consultas durante un trabajo, bloqueando selectores y operaciones mutantes según SPEC 15.
- Mostrar en `XPZ` únicamente los XPZ principales del ambiente activo.
- Permitir activar un XPZ principal solo durante la sesión.
- Ubicar `Validar XPZ` en la solapa `XPZ`.
- Mantener `Exportar` enfocada en exportar y completar el XPZ.
- No mostrar una política de exportación preseleccionada.
- Intentar la exportación normal al presionar `Exportar`.
- Si la exportación falla, mostrar una decisión explícita para seleccionar un XPZ principal existente o abortar.
- Al seleccionar un XPZ existente, activarlo en sesión y ejecutar su validación/completitud.
- No actualizar documentación automáticamente después de seleccionar un XPZ existente desde `Exportar`.
- Mostrar en `Exportar` el último resultado contextual, incluyendo estado, fecha, XPZ, warnings y pendientes.
- Mantener en `Endpoints` el inventario, los metadatos de generación, el estado de vigencia y la regeneración del inventario.
- Mostrar en cada fila de `Endpoints` el nombre, descripción, proceso, FQN, endpoint publicado, versión documental y acción de descarga PDF.
- Buscar en `Endpoints` por nombre, descripción y FQN.
- Permitir consultar versión y descargar PDF aunque el inventario esté obsoleto, mostrando claramente el estado `OBSOLETO`.
- Mostrar `SIN VERSIÓN` cuando no exista registro del endpoint en `controlVersiones.json`.
- Crear o extender `GET /api/servicios` para devolver la información enriquecida de cada servicio del contexto activo.
- Resolver en el servidor la relación entre servicio, inventario, control de versiones, estado documental y PDF publicado.
- Unificar en `Documentación` la selección y operación documental con una fila por endpoint.
- Mostrar en cada fila documental nombre/FQN, estado, versión, fecha, disponibilidad de PDF y acción de descarga.
- Buscar en `Documentación` por nombre, FQN y estado.
- Permitir seleccionar uno, varios o todos los endpoints filtrados.
- Mantener las acciones `Generar y publicar`, `Actualizar servicios` y `Reiniciar documentación`.
- Hacer que `Seleccionar todos` seleccione solo los endpoints visibles del filtro activo.
- Volver a la página 1 al cambiar el filtro y conservar la selección existente.
- No ofrecer acceso al Markdown desde `Documentación`.
- Descargar directamente el PDF cuando exista.
- Mostrar la descarga PDF deshabilitada cuando el archivo no exista.
- Implementar paginación cliente con 25 elementos iniciales y opciones 25, 50 y 100.
- Presentar endpoints y documentación como tarjetas en móvil, manteniendo visibles las acciones principales.
- Organizar `Logs` por tipos con filtros y visor inline para logs, último review, última validación e historial de versiones.
- Mantener el CRUD completo de `Configuración` definido por SPEC 15.
- Editar clientes y ambientes mediante listado y modales; las eliminaciones requieren confirmación.
- Mantener validación total, `configHash`, escritura atómica, modo solo lectura y conservación de artefactos definidos por SPEC 15.
- Permitir únicamente `Dashboard` y `Configuración` cuando no exista contexto activo o la configuración sea inválida.
- Mantener tema claro y oscuro.
- Usar `prefers-color-scheme` como tema inicial cuando no exista preferencia guardada.
- Persistir la elección manual del tema en `localStorage`.
- Mantener responsive, foco visible y `prefers-reduced-motion`.
- Extender `test/Run-Tests.ps1` con los contratos del rediseño y la API enriquecida.
- Verificar la interfaz mediante Playwright en escritorio y móvil, en ambos temas y en los estados principales.

**Fuera de alcance (para futuras SPEC):**

- Cambiar las reglas de análisis XPZ, redacción documental, versionado o publicación del pipeline.
- Cambiar el esquema de configuración de SPEC 19.
- Agregar autenticación, autorización, HTTPS o acceso remoto.
- Incorporar frameworks, paquetes, Node.js, npm, CDN o fuentes remotas.
- Renderizar Markdown dentro del panel.
- Permitir edición del contenido de los documentos desde el navegador.
- Descargar o visualizar archivos distintos de los permitidos por SPEC 15.
- Crear una API pública o un servicio remoto para el inventario.
- Agregar OpenAPI, Swagger UI, ejecución de peticiones HTTP o proxy CORS.
- Incorporar paginación server-side.
- Cambiar la semántica de los estados del pipeline o de los códigos de salida.

## Modelo de datos

Esta SPEC no crea un almacenamiento persistente nuevo. Reutiliza la sesión, los artefactos y los controles de SPEC 15.

### Servicio enriquecido

`GET /api/servicios` debe devolver una colección contextual con la información necesaria para las solapas `Endpoints` y `Documentación`:

```json
{
  "fullyQualifiedName": "APIGLM.Cotizacion.WSObtenerProductor",
  "nombre": "WSObtenerProductor",
  "descripcion": "Consulta del productor",
  "proceso": "APIGLM.Cotizacion.WSObtenerProductor",
  "endpoint": "glmsuit.comercial.apiglm.cotizacion.awsobtenerproductor",
  "estado": "ACTIVO",
  "version": "1.3",
  "versionDisponible": true,
  "pdf": {
    "disponible": true,
    "nombre": "wsobtenerproductor.pdf"
  },
  "markdown": {
    "disponible": true,
    "nombre": "wsobtenerproductor.md"
  }
}
```

Convenciones:

- `fullyQualifiedName` es el identificador operativo y no puede ser sustituido por una ruta de archivo recibida del navegador.
- `version` se obtiene exclusivamente del control de versiones contextual.
- Cuando no exista control, `version` es `null` y `versionDisponible` es `false`.
- `estado` usa los estados persistidos `ACTIVO`, `ELIMINADO` y `OMITIDO` y los estados visuales derivados definidos por SPEC 15.
- `pdf.nombre` y `markdown.nombre` se resuelven mediante la misma función de nombres de servicio usada por el pipeline.
- Un PDF ausente no genera una ruta ficticia y produce `disponible: false`.
- La respuesta no expone rutas físicas locales.
- La respuesta pertenece siempre al contexto y XPZ activos de la sesión.

### Paginación de interfaz

La paginación se conserva en memoria del navegador:

```js
const listState = {
  filter: "",
  page: 1,
  pageSize: 25,
  selectedFqns: []
};
```

Convenciones:

- `pageSize` acepta únicamente `25`, `50` o `100`.
- Cambiar el filtro establece `page = 1`.
- Cambiar el filtro no borra `selectedFqns`.
- `selectedFqns` contiene FQN, nunca nombres de archivos ni rutas.
- La selección se valida nuevamente contra los servicios del contexto antes de iniciar una operación.

### Fuentes tipográficas

El servidor debe permitir únicamente la lectura de estos archivos existentes:

```text
binary/fonts/Poppins-Regular.ttf
binary/fonts/Poppins-SemiBold.ttf
binary/fonts/Poppins-Bold.ttf
```

El CSS debe declarar pesos `400`, `600` y `700` mediante `@font-face`. La interfaz debe conservar un fallback local si una fuente no puede cargarse.

## Plan de implementación

1. Crear los fixtures de servicios enriquecidos, estados documentales, versiones ausentes, PDF ausente, inventario obsoleto y paginación; comprobar que el harness puede leerlos sin modificar artefactos reales.
2. Extender `binary/ServidorPanelWeb.ps1` para servir las tres fuentes Poppins mediante una ruta allowlisted y rechazar cualquier otra ruta bajo `binary/fonts/`.
3. Implementar `GET /api/servicios` usando el XPZ, el inventario, el control contextual y la función compartida de nombres de servicio; comprobar contexto, exclusiones, versiones y PDF.
4. Extender `GET /api/estado` con los datos agregados requeridos por `Dashboard`, sin activar automáticamente un contexto ni cambiar la sesión existente.
5. Rediseñar `web/style.css` con los tokens de los mockups, Poppins local, estados de badges, tarjetas móviles, paginación, modal, foco visible, tema y movimiento reducido.
6. Actualizar `web/index.html` para renombrar `Estado` a `Dashboard`, retirar `Documentos`, integrar la navegación unificada y declarar los paneles de todas las solapas.
7. Implementar en `web/app.js` el Dashboard completo, el indicador global de trabajo, el consumo de `/api/estado`, la recuperación de sesión y los estados sin contexto/configuración inválida.
8. Implementar la solapa `XPZ` con principales, activación de sesión y validación; conectar el trabajo asincrónico y regenerar la información dependiente cuando corresponda.
9. Adaptar `Exportar` para iniciar sin política seleccionada, presentar el fallo de exportación como decisión web, activar un XPZ elegido y ejecutar su completitud sin esperar stdin.
10. Implementar `Endpoints` con `/api/servicios`, filtros por nombre/descripción/FQN, metadatos, versiones, descarga PDF, estado obsoleto y paginación cliente.
11. Implementar `Documentación` con filas por endpoint, filtros por nombre/FQN/estado, selección visible, selección persistente, acciones masivas, estado documental y descarga PDF.
12. Implementar `Logs` con clasificación, filtros, acceso a review/validación/historial y visor inline seguro.
13. Implementar `Configuración` con listados, modales, CRUD completo, confirmaciones, errores de validación, `configHash` y reinicio de sesión después de guardar.
14. Extender `test/Run-Tests.ps1` para API, fuentes, rutas, servicio enriquecido, correlación de versiones/PDF, paginación, selección filtrada, exportación recuperable y configuración.
15. Ejecutar pruebas Playwright en escritorio y móvil, con tema claro/oscuro, sin contexto, contexto activo, trabajo activo, inventario obsoleto y configuración inválida; corregir errores de consola y accesibilidad básica.
16. Actualizar `README.md` y `AGENTS.md` para documentar la navegación, la ruta de fuentes, `GET /api/servicios` y la pantalla documental unificada.

## Criterios de aceptación

- [ ] La nueva SPEC está en `specs/21-redisenio-funcional-panel-web.md`, depende de SPEC 15 y queda en estado `Borrador`.
- [ ] El panel usa como referencia visual el sistema base de `resources/mockups-panel-api/`.
- [ ] Poppins se carga desde `binary/fonts/` sin CDN ni fuente remota.
- [ ] El servidor rechaza solicitudes de fuentes fuera de la allowlist.
- [ ] La navegación muestra `Dashboard`, `XPZ`, `Exportar`, `Endpoints`, `Documentación`, `Logs` y `Configuración`.
- [ ] La navegación no muestra una solapa independiente `Documentos`.
- [ ] Sin contexto activo solo se pueden abrir `Dashboard` y `Configuración`.
- [ ] Con contexto activo, `Dashboard` muestra contexto, KB, inventario, documentos, último review, XPZ, hash, herramientas y estado del trabajo.
- [ ] Un trabajo activo aparece en Dashboard y en el indicador del encabezado.
- [ ] Durante un trabajo activo los selectores y controles mutantes quedan bloqueados.
- [ ] `XPZ` lista solo XPZ principales del ambiente activo.
- [ ] Activar otro XPZ no modifica `configuracion.json`.
- [ ] `Validar XPZ` se ejecuta desde `XPZ` como trabajo asincrónico.
- [ ] `Exportar` no presenta una política preseleccionada.
- [ ] Al pulsar `Exportar` se intenta el flujo normal antes de pedir una decisión alternativa.
- [ ] Ante un fallo de exportación se puede seleccionar un XPZ principal existente o abortar.
- [ ] Seleccionar un XPZ existente lo activa en sesión y ejecuta su validación/completitud sin esperar stdin.
- [ ] La selección de un XPZ existente desde Exportar no actualiza documentos automáticamente.
- [ ] `Exportar` muestra el último resultado, warnings y pendientes del contexto.
- [ ] `GET /api/servicios` devuelve servicio, FQN, estado, versión y disponibilidad de PDF sin exponer rutas físicas.
- [ ] Un servicio sin control de versiones muestra `SIN VERSIÓN` y no una versión inventada.
- [ ] `Endpoints` filtra por nombre, descripción y FQN.
- [ ] `Endpoints` muestra nombre, descripción, proceso, FQN, endpoint, versión y acción PDF.
- [ ] La descarga PDF inicia una descarga directa cuando el archivo existe.
- [ ] La acción PDF queda deshabilitada cuando no existe el archivo.
- [ ] Un inventario obsoleto conserva la consulta de versión y PDF, muestra `OBSOLETO` y permite regenerar.
- [ ] `Documentación` contiene una fila por endpoint y no requiere correlación de archivos en el navegador.
- [ ] `Documentación` muestra estado, versión, fecha y disponibilidad PDF por endpoint.
- [ ] `Documentación` filtra por nombre, FQN y estado.
- [ ] `Seleccionar todos` selecciona únicamente los elementos visibles del filtro.
- [ ] Cambiar el filtro vuelve a la página 1 y conserva la selección previa.
- [ ] La paginación inicia con 25 elementos y permite 25, 50 y 100.
- [ ] Las acciones de generar/publicar, actualizar y reiniciar conservan sus contratos de SPEC 15.
- [ ] `Documentación` no renderiza ni ofrece acceso al Markdown publicado.
- [ ] `Logs` permite filtrar por tipo y leer logs, review, validación e historial inline.
- [ ] `Configuración` implementa alta, edición y baja mediante listados y modales.
- [ ] Las bajas requieren confirmación y conservan el árbol de artefactos contextual.
- [ ] Una configuración inválida muestra errores concretos y bloquea operaciones fuera de Dashboard y Configuración.
- [ ] El tema inicial respeta `prefers-color-scheme` cuando no existe preferencia guardada.
- [ ] La elección manual del tema se conserva en `localStorage`.
- [ ] La interfaz funciona en escritorio y móvil y usa tarjetas para filas en móvil.
- [ ] La interfaz respeta foco visible y `prefers-reduced-motion`.
- [ ] Playwright no detecta errores de consola en los escenarios definidos.
- [ ] Las pruebas cubren fuentes, API, seguridad de rutas, trabajo asincrónico, selección filtrada, versiones, PDF, configuración y estados obsoletos.
- [ ] `README.md` y `AGENTS.md` describen el nuevo nombre Dashboard, la solapa documental unificada, las fuentes y `GET /api/servicios`.

## Decisiones

- **Sí:** crear una SPEC nueva dependiente de SPEC 15. La SPEC 15 ya está implementada y no se reabre ni se modifica.
- **Sí:** usar el sistema visual base de los mockups. Permite mantener coherencia sin imponer una réplica rígida.
- **Sí:** servir Poppins desde `binary/fonts/`. Los archivos ya existen y mantienen el requisito offline.
- **No:** cargar Poppins desde Google Fonts o cualquier CDN. Rompería el carácter autocontenido del panel.
- **Sí:** renombrar Estado a Dashboard. El contenido pasa a ser un resumen operativo de todo el contexto.
- **Sí:** unificar Documentación y Documentos. Evita separar la selección de servicios de la consulta de sus artefactos.
- **Sí:** usar una fila por endpoint en Documentación. Permite relacionar estado, versión y PDF sin navegar entre pantallas.
- **Sí:** agregar `GET /api/servicios`. El servidor es responsable de unir XPZ, inventario, control y archivos.
- **No:** unir inventario, control y documentos en el navegador. Expondría correlaciones de rutas y duplicaría lógica del servidor.
- **Sí:** mostrar `SIN VERSIÓN` cuando falta control. No se inventa una versión documental.
- **Sí:** permitir consulta documental con inventario obsoleto. La información anterior sigue siendo útil, pero se marca como histórica.
- **Sí:** descargar PDF directamente. Es la acción explícita solicitada y evita agregar un visor interno.
- **No:** ofrecer Markdown desde Documentación. El flujo solicitado prioriza la descarga PDF y no requiere renderizado.
- **Sí:** seleccionar todos los elementos filtrados. Evita operar accidentalmente sobre endpoints no visibles.
- **Sí:** conservar la selección al cambiar el filtro. La selección se identifica por FQN y se valida antes de publicar.
- **Sí:** paginación cliente con 25, 50 y 100. El volumen esperado no justifica modificar los contratos de consulta con paginación server-side.
- **Sí:** convertir el fallback de exportación en una decisión web explícita. Los procesos hijos no pueden esperar `Read-Host`.
- **Sí:** al elegir un XPZ existente, activarlo y completar. Reproduce el flujo operativo de consola sin actualizar documentos automáticamente.
- **Sí:** CRUD mediante listados y modales. Mantiene la pantalla compacta y separa edición de confirmaciones destructivas.
- **Sí:** verificar mediante Playwright todos los estados y tamaños relevantes. La mayor parte del alcance es visual e interactivo.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| La correlación entre endpoint, control y PDF produce datos de otro contexto | Resolver todo en `GET /api/servicios` y validar `contextId`, XPZ y rutas allowlisted. |
| El proceso de exportación queda esperando una respuesta interactiva | Pasar decisiones explícitas desde la API y rechazar hijos que soliciten stdin. |
| Un PDF descargado pertenece a una generación anterior | Validar que el archivo esté bajo el contexto activo y mostrar vigencia u obsolescencia de forma explícita. |
| La selección persistente incluye un endpoint que dejó de existir | Revalidar todos los FQN contra el XPZ activo antes de iniciar la operación. |
| La ruta de fuentes permite leer archivos arbitrarios | Servir únicamente los tres nombres allowlisted y rechazar traversal, extensiones y rutas no previstas. |
| La nueva interfaz rompe el modo solo lectura | Mantener la regla de disponibilidad de SPEC 15 y probar configuración inválida con Playwright. |
| La paginación oculta elementos seleccionados | Mostrar el contador global de selección y conservar la selección por FQN. |
| El rediseño visual pierde accesibilidad en móvil o tema oscuro | Ejecutar Playwright en ambos tamaños y temas, con foco visible y revisión de contraste. |

## Lo que **no** incluye esta SPEC

- Modificación de SPEC 15.
- Cambios en el análisis XPZ o en la generación documental.
- Acceso remoto, autenticación o HTTPS.
- Frameworks, paquetes, CDN o fuentes remotas.
- Renderizado o edición de Markdown.
- Paginación server-side.
- Ejecución de requests HTTP desde el panel.
- OpenAPI, Swagger UI o proxy CORS.

Cada uno de esos temas, si se aborda, va en su propia SPEC.
