# SPEC 29 — Manual de usuario del panel web

> **Estado:** Borrador
> **Depende de:** SPEC 20, SPEC 23, SPEC 24, SPEC 25, SPEC 26, SPEC 27, SPEC 28
> **Fecha:** 2026-08-26
> **Objetivo:** Crear un manual Markdown breve e ilustrado que explique a operadores y administradores no técnicos cómo configurar y utilizar las funciones vigentes del Gestor Documentación GLM.

## Por qué existe esta SPEC

El panel reúne configuración, selección de contexto, exportación XPZ, generación documental, consulta de PDF y generación OpenAPI. Estas funciones no cuentan con un recorrido único orientado a usuarios no técnicos.

El manual debe explicar qué hace cada vista, cuándo usar sus acciones y qué resultado esperar. El contenido debe ser fácil de leer en pantalla y conservar legibilidad al imprimirse en formato A4.

## Alcance

**Incluido:**

- Crear `docs/manual-usuario.md` como instructivo operativo en español.
- Dirigir el contenido a operadores y administradores sin conocimientos técnicos del código fuente.
- Comenzar el recorrido con el panel ya abierto en el navegador.
- Explicar cómo seleccionar Cliente, Módulo y Ambiente antes de operar.
- Presentar Configuración como el primer apartado funcional del manual.
- Explicar el alta, edición y eliminación de clientes y ambientes desde la interfaz.
- Describir brevemente qué contiene y para qué sirve cada campo administrado desde la interfaz.
- Incluir un modelo conceptual de los datos ingresados desde Configuración, sin documentar propiedades globales que la interfaz no administra.
- Aclarar que un cliente nuevo se guarda junto con su primer ambiente.
- Aclarar que `host` y `baseUrl` son necesarios para generar un contrato OpenAPI ejecutable.
- Explicar el Dashboard y cada una de sus tarjetas: Cliente, Módulo, Ambiente, Documentos, KB y Últ. actualización.
- Explicar los estados `OK`, `ADVERTENCIA` y `ERROR` de las validaciones del Dashboard.
- Explicar la vista Exportar, la acción Exportar XPZ y el cambio a Actualizar servicios después de un procesamiento previo.
- Aclarar que Exportar obtiene o completa el XPZ y no genera documentación.
- Explicar la recuperación mediante selección y validación de un XPZ existente cuando corresponda.
- Explicar la vista Generar PDF y sus acciones Actualizar y Regenerar.
- Advertir que Regenerar reinicia el control de versionado y vuelve a generar todos los servicios.
- Explicar los estados visibles de una operación: en proceso, completado, completado parcialmente, cancelado y error.
- Explicar cómo filtrar servicios, cambiar el tamaño de página, navegar por resultados y abrir un PDF desde Documentación.
- Explicar que la descarga del PDF se realiza desde el visor del navegador porque la lista vigente no presenta un botón de descarga separado.
- Explicar la generación manual de OpenAPI mediante Generar OpenAPI.
- Explicar que OpenAPI también se actualiza automáticamente después de publicar documentación cuando `host` y `baseUrl` están completos.
- Aclarar que el panel vigente no ofrece un botón visible para abrir o descargar `openapi.json`.
- Incluir una tabla breve de problemas frecuentes para configuración bloqueada, exportación fallida, XPZ pendiente, generación parcial y OpenAPI no disponible.
- Incluir un resumen breve, sin captura propia, de Logs, tema visual y novedades de versión.
- Usar párrafos breves, pasos numerados, tablas compactas y términos visibles en la interfaz.
- Evitar explicaciones del código, endpoints HTTP internos y jerga innecesaria.
- Crear seis capturas PNG bajo `docs/images/manual-usuario/`.
- Usar el contexto actual `Trunk / Comercial / TEST` en las capturas operativas.
- Tomar las capturas con 1024 píxeles de ancho y recortarlas verticalmente al contenido relevante para mantener la legibilidad en A4.
- Usar exactamente los nombres `01-configuracion.png`, `02-dashboard.png`, `03-exportar.png`, `04-generar-pdf.png`, `05-documentacion.png` y `06-openapi.png`.
- Enlazar todas las imágenes mediante rutas relativas desde `docs/manual-usuario.md`.
- Verificar el texto y las capturas contra la interfaz vigente antes de publicar el manual.

**Fuera de alcance (para futuras SPEC):**

- Modificar el comportamiento, los textos, las vistas o los estilos del panel web.
- Agregar un botón para visualizar o descargar OpenAPI.
- Agregar un botón separado para descargar PDF desde la lista de Documentación.
- Cambiar las reglas de exportación XPZ, análisis, versionado, publicación documental u OpenAPI.
- Documentar APIs HTTP internas, scripts PowerShell o procedimientos de desarrollo.
- Documentar la instalación, el arranque mediante `IniciarPanelWeb.cmd` o la preparación de herramientas externas.
- Explicar propiedades globales de `configuracion.json` que no se administran desde la interfaz.
- Incluir credenciales, secretos o datos de autenticación.
- Crear capturas móviles o una segunda serie para tema oscuro.
- Crear un manual interactivo, ayuda contextual dentro del panel o recorridos guiados.
- Incorporar generación automática de capturas o una herramienta adicional de documentación.
- Modificar `README.md`.

## Modelo de datos

Esta SPEC no introduce datos operativos ni modifica `configuracion.json`. Agrega únicamente un documento Markdown y seis imágenes estáticas versionadas en Git.

### Estructura documental

```text
docs/
|-- manual-usuario.md
`-- images/
    `-- manual-usuario/
        |-- 01-configuracion.png
        |-- 02-dashboard.png
        |-- 03-exportar.png
        |-- 04-generar-pdf.png
        |-- 05-documentacion.png
        `-- 06-openapi.png
```

### Orden del manual

`docs/manual-usuario.md` debe conservar este recorrido:

1. Propósito y público del manual.
2. Configuración inicial.
3. Selección del contexto.
4. Dashboard.
5. Exportar.
6. Generar PDF.
7. Visualizar la documentación.
8. Generar OpenAPI.
9. Problemas frecuentes.
10. Logs, tema y novedades.

Cada flujo principal debe contener, cuando corresponda:

- Una descripción de una o dos frases.
- Una indicación breve de cuándo utilizarlo.
- Pasos numerados con los nombres visibles de los controles.
- El resultado esperado.
- Una advertencia breve cuando la acción pueda reiniciar versiones o dependa de configuración previa.
- La captura correspondiente.

### Modelo explicado de Configuración

El manual debe representar únicamente los datos que el usuario carga o modifica desde la interfaz:

```json
{
  "cliente": {
    "id": "trunk",
    "nombre": "Trunk",
    "packagenames": {
      "comercial": "<package comercial>",
      "erp": "<package ERP>"
    }
  },
  "ambiente": {
    "id": "testing",
    "nombre": "Testing",
    "modulo": "comercial",
    "tipo": "test",
    "kbPath": "<ruta de la Knowledge Base>",
    "host": "https://servidor.example.com",
    "baseUrl": "/testing/rest"
  }
}
```

El ejemplo es conceptual y no sustituye el archivo completo `configuracion.json`. Debe acompañarse con una tabla que explique de forma breve:

| Campo visible | Descripción para el usuario |
|---|---|
| ID cliente | Identificador corto y único del cliente. |
| Nombre | Nombre que se muestra en el panel. |
| Módulo | Área funcional Comercial o ERP. |
| Package name | Prefijo usado para identificar los servicios publicados del módulo. |
| ID ambiente | Identificador corto y único del ambiente. |
| Tipo | Indica si el ambiente es Testing o Producción. |
| Kb Path | Ruta de la Knowledge Base desde la que se obtiene el XPZ. |
| Host | Dirección principal del servidor del ambiente. |
| Base URL | Ruta base que completa la dirección de los servicios. |

El texto debe aclarar que Host y Base URL pueden no ser necesarios para consultar PDF, pero ambos deben estar completos para generar OpenAPI.

### Reglas de las capturas

- Las imágenes usan formato PNG.
- El navegador se captura con 1024 píxeles de ancho.
- Cada imagen se recorta al contenido de su sección y evita espacio vacío innecesario.
- El texto visible debe poder leerse al ajustar la imagen al ancho útil de una página A4.
- Las capturas muestran la interfaz vigente y el contexto `Trunk / Comercial / TEST` cuando exista un contexto operativo activo.
- No se activan Exportar, Actualizar, Regenerar ni Generar OpenAPI únicamente para obtener una captura.
- No se incluyen credenciales, tokens ni información ajena a la interfaz solicitada.

## Plan de implementación

1. Crear `docs/images/manual-usuario/` y preparar los seis nombres de imagen acordados sin modificar la aplicación.
2. Abrir el panel en el navegador, activar `Trunk / Comercial / TEST` y capturar Configuración y Dashboard a 1024 píxeles de ancho.
3. Capturar Exportar y Generar PDF mostrando sus acciones y estados vigentes, sin iniciar operaciones mutantes para producir contenido visual.
4. Capturar Documentación y el control Generar OpenAPI, recortando cada imagen al contenido relevante para A4.
5. Crear `docs/manual-usuario.md` con el orden documental acordado y comenzar por Configuración después de la introducción.
6. Documentar los campos administrados desde la interfaz mediante el modelo conceptual y la tabla breve, incluyendo alta, edición y eliminación.
7. Documentar selección de contexto, Dashboard y las seis tarjetas con lenguaje directo y términos idénticos a los del panel.
8. Documentar Exportar, recuperación con XPZ existente y los resultados visibles sin atribuirle generación documental.
9. Documentar Generar PDF, diferenciando Actualizar de Regenerar e incluyendo la advertencia sobre reinicio del versionado.
10. Documentar la consulta de servicios y PDF, incluyendo filtros, paginación, visor y descarga desde el visor del navegador.
11. Documentar la generación OpenAPI manual y automática, sus requisitos y la ausencia vigente de un botón para abrir o descargar el contrato.
12. Agregar problemas frecuentes y un resumen breve de Logs, tema y novedades sin ampliar el alcance técnico.
13. Insertar las seis imágenes mediante rutas relativas y revisar su tamaño y legibilidad en una representación A4.
14. Comparar nombres, pasos, estados y advertencias con `web/index.html`, `web/app.js` y la interfaz ejecutada; corregir cualquier diferencia antes de finalizar.
15. Renderizar el Markdown, comprobar que no existan enlaces rotos ni imágenes faltantes y realizar una lectura final orientada a un usuario no técnico.

## Criterios de aceptación

- [ ] Existe `docs/manual-usuario.md` en español.
- [ ] El manual identifica como público a operadores y administradores no técnicos.
- [ ] El manual comienza con el panel ya abierto en el navegador y no incluye instrucciones de instalación o arranque.
- [ ] Configuración es el primer apartado funcional después de la introducción.
- [ ] Configuración explica alta, edición y eliminación de clientes y ambientes.
- [ ] El manual aclara que un cliente nuevo se crea junto con su primer ambiente.
- [ ] El modelo conceptual contiene únicamente los campos administrados desde la interfaz.
- [ ] Cada campo de cliente y ambiente tiene una descripción breve de su contenido y finalidad.
- [ ] El manual diferencia Cliente, Módulo y Ambiente y explica el orden de selección.
- [ ] El Dashboard explica las tarjetas Cliente, Módulo, Ambiente, Documentos, KB y Últ. actualización.
- [ ] El manual explica los estados OK, ADVERTENCIA y ERROR sin describir su implementación interna.
- [ ] Exportar se describe como obtención o completado del XPZ y no como generación de documentos.
- [ ] El manual explica cómo seleccionar y validar un XPZ existente cuando el flujo lo solicita.
- [ ] Generar PDF diferencia claramente Actualizar de Regenerar.
- [ ] La acción Regenerar incluye una advertencia visible sobre el reinicio del control de versionado.
- [ ] Los estados en proceso, completado, completado parcialmente, cancelado y error se explican con frases breves.
- [ ] Documentación explica filtro, tamaño de página, navegación y apertura de un PDF.
- [ ] El manual indica que el PDF se descarga desde el visor del navegador y no promete un botón inexistente en la lista.
- [ ] OpenAPI explica la generación manual mediante Generar OpenAPI.
- [ ] OpenAPI explica la actualización automática posterior a la publicación documental cuando Host y Base URL están completos.
- [ ] El manual indica que Host y Base URL son necesarios para generar OpenAPI.
- [ ] El manual aclara que no existe un botón visible para abrir o descargar `openapi.json`.
- [ ] La tabla de problemas frecuentes cubre configuración bloqueada, exportación fallida, XPZ pendiente, generación parcial y OpenAPI no disponible.
- [ ] Logs, tema y novedades tienen una descripción breve sin captura propia.
- [ ] Existen exactamente las seis imágenes PNG acordadas bajo `docs/images/manual-usuario/`.
- [ ] Las seis imágenes usan los nombres establecidos en esta SPEC.
- [ ] Las capturas operativas corresponden a `Trunk / Comercial / TEST`.
- [ ] Cada captura fue tomada con 1024 píxeles de ancho y recortada al contenido relevante.
- [ ] Las capturas mantienen texto legible al ajustarse al ancho útil de una página A4.
- [ ] Todas las rutas relativas de imágenes resuelven desde `docs/manual-usuario.md`.
- [ ] Ninguna captura contiene credenciales, tokens o secretos.
- [ ] El manual usa los nombres visibles vigentes de vistas, controles y estados.
- [ ] Los párrafos son breves y los procedimientos usan pasos numerados.
- [ ] Los términos técnicos inevitables, como XPZ, KB y OpenAPI, se explican la primera vez que aparecen.
- [ ] El Markdown renderiza sin enlaces rotos ni imágenes faltantes.
- [ ] No se modifica código, configuración operativa, API ni comportamiento del panel.

## Decisiones

- **Sí:** crear `docs/manual-usuario.md`. Mantiene el instructivo separado del README y permite ampliarlo sin recargar la portada del repositorio.
- **Sí:** escribir para operadores y administradores no técnicos. El manual debe priorizar acciones y resultados sobre detalles de implementación.
- **Sí:** usar descripciones breves, pasos numerados y tablas compactas. Favorece la lectura rápida y la impresión.
- **Sí:** comenzar desde el navegador. El arranque y la instalación no forman parte del recorrido solicitado.
- **Sí:** presentar Configuración primero. Los datos de cliente, módulo y ambiente condicionan el resto de las operaciones.
- **Sí:** explicar solo los parámetros administrados desde la interfaz. Las propiedades globales del archivo quedan fuera del uso cotidiano cubierto.
- **Sí:** documentar alta, edición y baja. El público incluye administradores responsables del mantenimiento de contextos.
- **Sí:** incluir seis capturas del contexto actual `Trunk / Comercial / TEST`. Mantiene continuidad visual entre los flujos principales.
- **Sí:** usar PNG a 1024 píxeles de ancho con recorte por sección. Esta combinación prioriza legibilidad en A4 sobre una captura completa de toda la pantalla.
- **No:** incluir una segunda serie móvil o de tema oscuro. Duplicaría el mantenimiento sin aportar un flujo funcional distinto.
- **Sí:** documentar Actualizar y Regenerar. Son acciones vigentes con efectos diferentes que el usuario debe distinguir.
- **Sí:** advertir sobre Regenerar. Reiniciar el versionado no debe presentarse como una acción cotidiana equivalente a Actualizar.
- **Sí:** explicar OpenAPI manual y automático. Ambos comportamientos son vigentes y dependen de la configuración del ambiente.
- **No:** describir una descarga OpenAPI desde el panel. La interfaz actual no ofrece ese control.
- **Sí:** incluir problemas frecuentes. Los estados degradados forman parte del uso real y requieren una respuesta breve y accionable.
- **Sí:** resumir Logs, tema y novedades sin capturas. Son funciones secundarias que ayudan a orientarse, pero no justifican ampliar los seis flujos principales.
- **No:** modificar la aplicación para que coincida con el manual. El documento debe reflejar el producto vigente y no crear comportamiento nuevo.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Las capturas quedan obsoletas cuando cambia la interfaz | Comparar el manual con la interfaz vigente durante cada cambio funcional relevante. |
| Una captura ancha pierde legibilidad al imprimirse | Usar 1024 píxeles de ancho y recortar cada imagen al contenido de la sección. |
| El contexto actual expone información operativa visible | Limitar las capturas a datos ya presentados por el panel y excluir credenciales, tokens y secretos. |
| Un usuario confunde Exportar con generar documentos | Indicar de forma explícita que Exportar obtiene o completa el XPZ y no produce PDF. |
| Un usuario usa Regenerar como actualización cotidiana | Mostrar una advertencia antes de los pasos y explicar el reinicio del versionado. |
| El manual promete descargar OpenAPI desde un control inexistente | Describir solo la generación vigente y declarar expresamente la limitación de visualización y descarga. |
| La terminología técnica dificulta la lectura | Definir XPZ, KB y OpenAPI en su primera aparición y usar luego frases cortas. |
| Las rutas de imágenes se rompen al mover archivos | Usar rutas relativas estables y verificarlas mediante renderizado Markdown. |

## Lo que **no** incluye esta SPEC

- Cambios funcionales o visuales en el panel.
- Instalación o arranque de la aplicación.
- Documentación de APIs internas o scripts PowerShell.
- Parámetros globales que no puedan editarse desde Configuración.
- Descarga o visualización nueva de OpenAPI.
- Un botón nuevo de descarga PDF.
- Capturas móviles o en tema oscuro.
- Ayuda interactiva dentro de la aplicación.
- Cambios en `README.md`.
- Datos sensibles o credenciales.

Cada cambio futuro en nombres, flujos o estados visibles debe revisar si `docs/manual-usuario.md` y sus capturas continúan representando la aplicación vigente.
