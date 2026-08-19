# SPEC 25 — Mejora UX/UI y arquitectura modular del panel web

> **Estado:** Implementado
> **Depende de:** SPEC 21, SPEC 22, SPEC 23, SPEC 24
> **Fecha:** 2026-08-18
> **Objetivo:** Evolucionar la interfaz web del panel hacia una experiencia modular, responsive y mantenible mediante componentes nativos reutilizables, sin dependencias externas ni cambios en los contratos actuales de la API.

## Por qué existe esta SPEC

El panel ya contiene spinners, modales, consolas, filtros, tema claro/oscuro y CRUD de configuración, pero la implementación concentra la lógica en `web/app.js` y repite patrones visuales entre vistas.

La interfaz necesita una base común para mostrar tarjetas resumen, servicios expandibles, detalles documentales, estados de carga, errores, operaciones asincrónicas y formularios CRUD sin duplicar comportamiento.

Esta SPEC mejora la presentación y la organización del frontend. No modifica las reglas operativas del pipeline ni sustituye las decisiones de las SPEC 21, 22, 23 y 24.

## Alcance

**Incluido:**

- Mantener `web/index.html` y `web/style.css` como entradas públicas del panel.
- Migrar progresivamente la lógica de `web/app.js` a módulos ES nativos bajo `web/app/`.
- Implementar Web Components propios con light DOM y sin Shadow DOM.
- Mantener el panel como una SPA por solapas, sin agregar un router ni nuevas URLs de navegación.
- Aplicar la nueva base visual a Dashboard, Documentación/Endpoints, Logs y Configuración.
- Mantener la vista unificada actual de Documentación y Endpoints.
- Crear componentes reutilizables para tarjetas resumen, tarjetas expandibles, detalle documental, estados de carga, estados vacíos, errores, toasts, spinners y progreso.
- Crear un componente CRUD reutilizable únicamente para clientes y ambientes de Configuración.
- Mantener las reglas transaccionales, validaciones, concurrencia optimista y confirmaciones de SPEC 23.
- Mostrar en el detalle de un servicio su FQN, endpoint, estado, versión, disponibilidad documental y descarga directa del PDF cuando exista.
- Derivar las métricas y tarjetas exclusivamente de las respuestas actuales de las APIs.
- Mantener las consolas y estados operativos de Exportar y Generar PDF definidos por SPEC 24, reutilizando los componentes visuales comunes cuando corresponda.
- Persistir preferencias no sensibles en `localStorage` mediante la clave `glm-panel-ui:v1`.
- Persistir tema, solapa activa, modo de visualización, tamaño de página y filtros por vista.
- Descartar preferencias inválidas o incompatibles sin impedir la carga del panel.
- Conservar `web/example.html` como referencia técnica bajo `web/resources/example.html`, fuera de la navegación operativa.
- Ampliar únicamente la allowlist de archivos estáticos necesaria para servir los módulos y el recurso de referencia.
- Mantener Poppins local, los temas claro/oscuro y los tokens CSS existentes como base del sistema visual.
- Verificar escritorio y móvil, tema claro y oscuro, teclado, foco visible, `aria-live` y `prefers-reduced-motion`.

**Fuera de alcance (para futuras SPEC):**

- Incorporar Bootstrap, Alpine.js, Pico CSS, HTMX, React, Vue u otra dependencia de terceros.
- Incorporar Node.js, npm, bundler, gestor de paquetes o CDN.
- Modificar endpoints, payloads o respuestas de las APIs existentes.
- Crear APIs nuevas para métricas, preferencias, detalles o navegación.
- Cambiar el descubrimiento de servicios desde `APIGLM.APIGLMMain`.
- Cambiar las reglas de exportación, validación, completitud, análisis, versionado o publicación documental.
- Convertir servicios, documentos o logs en entidades editables mediante CRUD.
- Separar nuevamente Documentación y Endpoints en visores independientes.
- Introducir rutas nuevas o navegación basada en History API.
- Implementar autenticación, usuarios, permisos o colaboración multiusuario.
- Persistir datos operativos, credenciales, rutas físicas o contenido documental en `localStorage`.
- Ejecutar Exportar y Generar PDF simultáneamente.
- Agregar una suite Playwright versionada o capturas al repositorio.

## Modelo de datos

La SPEC no modifica el modelo de datos del servidor. Agrega únicamente estado efímero y preferencias visuales del navegador.

### Estado de preferencias de interfaz

La clave exacta de persistencia será `glm-panel-ui:v1`.

```js
const uiPreferences = {
  theme: "light",
  activeTab: "estado",
  views: {
    documentacion: "cards",
    logs: "list"
  },
  pageSize: {
    documentacion: 25
  },
  filters: {
    documentacion: "",
    logs: "todos"
  }
};
```

Convenciones:

- Solo se guardan preferencias de presentación y navegación.
- Los valores válidos se validan al cargar.
- Una estructura inválida se ignora y se reemplaza por valores predeterminados.
- Una versión futura debe utilizar una clave versionada distinta o una migración explícita.
- El estado de trabajos, resultados operativos, contextos, hashes y datos de configuración no se persiste en esta estructura.

### Estado interno de componentes

Los componentes mantienen su estado en memoria y lo exponen mediante atributos o propiedades públicas cuando sea necesario.

```js
const componentState = {
  loading: false,
  error: null,
  expanded: false,
  selectedId: null
};
```

Convenciones:

- `loading` bloquea solo las acciones afectadas, salvo el bloqueo global definido por SPEC 24.
- `error` contiene un mensaje visible y no una excepción serializada para el usuario.
- `expanded` controla tarjetas o paneles de detalle sin cambiar la URL.
- `selectedId` identifica el FQN del servicio o el ID de configuración correspondiente.

### Componentes públicos

Los nombres de los Web Components serán:

- `<glm-app-shell>`
- `<glm-stat-card>`
- `<glm-service-card>`
- `<glm-detail-dialog>`
- `<glm-loading-state>`
- `<glm-empty-state>`
- `<glm-error-state>`
- `<glm-toast>`
- `<glm-operation-console>`
- `<glm-crud-list>`

Los componentes usarán light DOM para consumir los tokens y reglas responsive de `web/style.css`.

## Plan de implementación

1. Crear la estructura `web/app/`, el módulo de entrada y un cliente común para mantener las consultas y mutaciones actuales sin cambiar sus contratos.
2. Separar el estado global existente, el estado de preferencias y las utilidades de renderizado en módulos independientes, manteniendo el panel ejecutable después de cada separación.
3. Implementar la lectura y escritura validada de `glm-panel-ui:v1`, incluyendo valores predeterminados, descarte de datos inválidos y persistencia del tema actual.
4. Crear los componentes base de estado: carga, skeleton, vacío, error, toast, spinner y progreso, con estados accesibles y soporte para `prefers-reduced-motion`.
5. Crear `glm-stat-card`, `glm-service-card` y `glm-detail-dialog` con datos derivados de `GET /api/servicios`, expansión, cierre accesible y descarga directa del PDF disponible.
6. Integrar las tarjetas y el detalle en la vista unificada de Documentación/Endpoints, conservando FQN, filtros, paginación y selección documental actuales.
7. Crear `glm-operation-console` y conectarlo a los resultados de Exportar y Generar PDF sin modificar la semántica ni el bloqueo global de SPEC 24.
8. Crear `glm-crud-list` y utilizarlo en Configuración para clientes y ambientes, conservando validaciones, `configHash`, popups, escritura atómica y confirmaciones de SPEC 23.
9. Separar las vistas Dashboard, Documentación, Logs y Configuración en módulos de presentación bajo `web/app/views/`, manteniendo la navegación actual por solapas.
10. Reorganizar `web/style.css` alrededor de tokens, componentes, estados y breakpoints sin cambiar la fuente Poppins ni eliminar los temas existentes.
11. Mover el prototipo a `web/resources/example.html`, actualizar sus referencias relativas y permitirlo únicamente como recurso técnico fuera del menú del panel.
12. Ajustar `binary/ServidorPanelWeb.ps1` para servir los módulos estáticos y `web/resources/example.html` mediante una allowlist explícita, sin habilitar rutas arbitrarias.
13. Ejecutar `test/Run-Tests.ps1` y comprobar que los contratos de las APIs, las mutaciones de configuración y los estados operativos de SPEC 23 y SPEC 24 permanecen intactos.
14. Verificar mediante Playwright MCP la navegación, las tarjetas, los detalles, los estados, el CRUD, la persistencia visual y la descarga documental en escritorio y móvil, en ambos temas.
15. Registrar los resultados de la revisión visual y de accesibilidad en la revisión de implementación sin agregar capturas, trazas, Node.js ni npm.

## Criterios de aceptación

- [ ] El panel carga sin errores JavaScript ni recursos externos.
- [ ] La interfaz continúa funcionando sin Node.js, npm, CDN ni dependencias de terceros.
- [ ] `web/app.js` deja de concentrar toda la lógica de presentación y las vistas usan módulos bajo `web/app/`.
- [ ] Las vistas Dashboard, Documentación/Endpoints, Logs y Configuración usan la nueva base de componentes.
- [ ] Documentación y Endpoints continúan siendo una vista unificada.
- [ ] Las tarjetas resumen muestran métricas derivadas de datos reales de las APIs actuales.
- [ ] Las tarjetas de servicios pueden expandirse y contraerse sin cambiar la URL.
- [ ] Una tarjeta expandida muestra FQN, endpoint, estado, versión y disponibilidad documental.
- [ ] El detalle documental se abre en un dialog o panel accesible y puede cerrarse con el control de cierre y la tecla Escape.
- [ ] La descarga PDF solo aparece habilitada cuando el servicio tiene un PDF disponible.
- [ ] Los filtros y la paginación existentes continúan funcionando en la vista de servicios.
- [ ] Los estados de carga, vacío y error son visualmente distintos y contienen mensajes accionables.
- [ ] Los botones asincrónicos muestran spinner, se bloquean durante la operación y no permiten doble envío.
- [ ] Las consolas de Exportar y Generar PDF conservan los estados y la semántica definida por SPEC 24.
- [ ] El CRUD de Configuración continúa respetando las validaciones, el `configHash`, la escritura atómica y las confirmaciones de SPEC 23.
- [ ] Los servicios, documentos y logs no muestran acciones CRUD de edición o eliminación.
- [ ] La navegación continúa usando las solapas actuales sin agregar un router ni URLs nuevas.
- [ ] La clave `glm-panel-ui:v1` contiene únicamente preferencias visuales y de navegación permitidas.
- [ ] El tema, la solapa, el modo de visualización, el tamaño de página y los filtros se restauran después de recargar.
- [ ] Una preferencia inválida se descarta sin impedir la carga del panel.
- [ ] No se persisten credenciales, rutas físicas, hashes, trabajos, resultados operativos ni contenido documental en `localStorage`.
- [ ] `web/resources/example.html` queda accesible como recurso técnico y no aparece en la navegación del panel.
- [ ] El servidor solo sirve los módulos y recursos explícitamente incluidos en la allowlist.
- [ ] No se exponen rutas físicas mediante los recursos estáticos ni mediante APIs existentes.
- [ ] El light DOM permite que los componentes respeten los temas y tokens de `web/style.css`.
- [ ] La interfaz funciona a 390x844 y en escritorio sin textos cortados, superposiciones ni controles inaccesibles.
- [ ] La matriz visual se verifica en tema claro y oscuro.
- [ ] Todos los controles interactivos tienen foco visible y orden de tabulación utilizable.
- [ ] Los cambios de estado relevantes se anuncian mediante `aria-live` sin duplicar mensajes innecesarios.
- [ ] `prefers-reduced-motion` desactiva las animaciones no esenciales y mantiene visibles los estados de carga.
- [ ] `test/Run-Tests.ps1` permanece exitoso y cubre la regresión de los contratos afectados.
- [ ] Playwright MCP no detecta errores en la consola del navegador durante la navegación principal.
- [ ] Playwright MCP verifica tarjetas, expansión, detalle, filtros, CRUD, estados, persistencia visual y descarga PDF.

## Decisiones

- **Sí:** usar módulos ES nativos y Web Components propios. Encapsulan responsabilidades sin introducir una cadena de build.
- **Sí:** usar light DOM. Mantiene centralizados los temas, Poppins, tokens, breakpoints y estados CSS.
- **No:** usar Shadow DOM inicialmente. Aumentaría el coste de compartir estilos y revisar la interfaz completa.
- **No:** incorporar Bootstrap, Alpine.js, Pico CSS, HTMX o frameworks de componentes. La ganancia no justifica introducir dependencias en el panel local.
- **Sí:** mantener una SPA por solapas. Conserva la navegación actual y evita cambios en el servidor.
- **No:** agregar History API o rutas nuevas. No forma parte de la mejora UX/UI solicitada.
- **Sí:** reutilizar los contratos actuales de las APIs. Las tarjetas derivan métricas en el frontend y no duplican lógica del servidor.
- **Sí:** mantener Documentación y Endpoints unificados. Es la decisión vigente de SPEC 19, SPEC 21 y SPEC 24.
- **Sí:** limitar el CRUD genérico a Configuración. Servicios, documentos y logs son datos operativos o derivados y no deben editarse desde esta SPEC.
- **Sí:** usar `glm-panel-ui:v1`. Permite persistencia controlada y una evolución explícita del formato.
- **No:** persistir datos operativos o sensibles. El navegador no debe convertirse en otra fuente de verdad del pipeline.
- **Sí:** conservar `web/example.html` bajo `web/resources/`. Sirve como referencia visual y técnica sin mezclar prototipos con la navegación productiva.
- **Sí:** extender únicamente la allowlist estática. El servidor continúa rechazando recursos no declarados.
- **Sí:** verificar mediante el harness existente y Playwright MCP. Se cubren regresión funcional y experiencia real sin agregar herramientas instalables.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| La migración modular rompe referencias globales existentes | Migrar por vista, mantener un punto de entrada estable y ejecutar el harness después de cada etapa. |
| Los Web Components no comparten correctamente el tema | Usar light DOM, tokens CSS globales y pruebas en claro y oscuro. |
| La persistencia conserva una estructura incompatible | Versionar la clave, validar cada campo y descartar estructuras inválidas. |
| Una tarjeta presenta datos distintos de la API | Derivar la representación desde los contratos actuales y probar FQN, estado, versión y disponibilidad. |
| El CRUD genérico relaja reglas específicas de Configuración | Mantener validación y payload final en la vista y en el servidor según SPEC 23. |
| Los componentes ocultan estados operativos definidos por SPEC 24 | Reutilizar el resultado semántico existente y no inferir estados por la presencia de documentos. |
| La allowlist permite acceso accidental a archivos | Mantener una expresión explícita de nombres permitidos y probar respuestas 404 para rutas no declaradas. |
| El diseño móvil pierde información o acciones | Verificar 390x844, usar detalle bajo demanda y mantener acciones accesibles por teclado. |
| Las animaciones afectan a usuarios con movimiento reducido | Aplicar `prefers-reduced-motion` y conservar el significado mediante texto y estados ARIA. |

## Lo que **no** incluye esta SPEC

- Bootstrap, Alpine.js, Pico CSS, HTMX u otra dependencia externa.
- Node.js, npm, CDN o un proceso de build.
- Cambios en las APIs, contratos, reglas del pipeline o modelo de configuración.
- Nuevas entidades editables fuera de clientes y ambientes.
- Un visor separado de Endpoints.
- Un router o URLs nuevas para las vistas.
- Persistencia de información operativa o sensible en el navegador.
- Concurrencia entre Exportar y Generar PDF.
- Cambios en el análisis XPZ, versionado, publicación documental o logs operativos.
- Una suite Playwright versionada, capturas o trazas commiteadas.

Cada cambio que amplíe el contrato del servidor, introduzca autenticación o altere la operación del pipeline requiere una SPEC independiente.

## Revisión de implementación

### Verificación funcional

- `test/Run-Tests.ps1`: 232 casos PASS, 0 FAIL y 21 SKIP.
- Playwright MCP confirmó la carga de `app/main.js`, los módulos ES y los Web Components sin errores de consola durante la navegación principal.
- Se verificaron Dashboard, Documentación, Logs y Configuración, incluyendo tarjetas, filtros, paginación, detalle documental y renderizado del CRUD.
- Se verificó la persistencia de tema y solapa activa mediante `glm-panel-ui:v1` después de recargar.
- Se verificó que `/resources/example.html` responde 200 y que un módulo no incluido en la allowlist responde 404.
- Se comprobó el cierre del detalle documental mediante Escape.

### Matriz visual y accesibilidad

| Dimensión | Resultado |
|---|---|
| Escritorio | Conforme; navegación, tarjetas, controles y configuración visibles sin superposición. |
| 390x844 | Conforme; la navegación y los controles principales permanecen utilizables. |
| Tema claro | Conforme; tokens y componentes usan la base visual existente. |
| Tema oscuro | Conforme; el tema se restaura después de recargar. |
| Teclado y foco | Conforme; controles nativos y reglas `:focus-visible` mantienen foco identificable. |
| Anuncios | Conforme; estados operativos, paginación y consolas usan `aria-live` o roles apropiados. |
| Escape | Conforme; el detalle documental se cierra con la tecla Escape. |
| Movimiento reducido | Conforme; `prefers-reduced-motion` desactiva animaciones no esenciales. |

No se agregaron capturas, trazas, Node.js, npm ni dependencias externas. Las mutaciones destructivas del CRUD no se ejecutaron durante la revisión; el harness cubre sus contratos transaccionales.
