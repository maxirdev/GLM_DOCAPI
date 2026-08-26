# SPEC 27 — Validación integral de configuración al iniciar

> **Estado:** Borrador
> **Depende de:** SPEC 23, SPEC 26
> **Fecha:** 2026-08-25
> **Objetivo:** Validar íntegramente el `configuracion.json` compartido antes de habilitar el panel y bloquear toda operación cuando algún contexto no pueda cargarse de forma coherente.

## Por qué existe esta SPEC

El panel puede iniciar con errores de configuración parciales y hoy la validación se detiene ante la primera excepción. Esto permite que problemas de clientes no seleccionados permanezcan ocultos hasta que se intenta activar su contexto.

Como `configuracion.json` es compartido por todos los clientes, un arranque confiable debe comprobar su sintaxis, esquema y la resolución completa de cada contexto antes de habilitar operaciones. La simulación no debe crear carpetas ni depender de que las KB o herramientas externas estén disponibles en ese momento.

## Alcance

**Incluido:**

- Aplicar la validación al inicio del panel web lanzado por `IniciarPanelWeb.cmd` y `binary/ServidorPanelWeb.ps1`.
- Comprobar que `configuracion.json` existe y contiene JSON sintácticamente válido.
- Validar el esquema global completo después del parseo.
- Validar todos los clientes, módulos y ambientes, no solo el contexto elegido.
- Simular la resolución de cada contexto `<cliente>/<modulo>/<ambiente>` con todas las variables que utiliza el panel y su pipeline.
- Ejecutar la simulación estrictamente en modo de solo lectura.
- No crear `documentacionServicios`, `estado`, `xpz`, `Logs`, `test` ni registros de operación durante la validación.
- Validar campos obligatorios, tipos, enums, slugs, cardinalidad, unicidad e identidad contextual.
- Validar `rutas.clientesRoot` y que todas las rutas configuradas puedan normalizarse de forma determinista.
- Validar las propiedades globales de herramientas, exportación y panel que consume la aplicación.
- Validar `packagenames`, `serviciosIgnorados`, `modulo`, `tipo`, `kbPath`, `host` y `baseUrl` según SPEC 26.
- Derivar en memoria `contextId`, directorios contextuales, `PackageName`, `ServerUrl` y rutas de artefactos para detectar combinaciones incoherentes.
- No exigir durante el arranque que una KB, GeneXus, MSBuild, Pandoc o Typst existan o estén accesibles físicamente.
- No validar contenido interno de una KB durante este preflight.
- Acumular todos los errores independientes que puedan identificarse después de parsear el JSON.
- Identificar cada error contextual con cliente, módulo y ambiente cuando corresponda.
- Si el JSON no puede parsearse, informar el error sintáctico y omitir la simulación contextual imposible.
- Iniciar el servidor HTTP aun cuando la configuración sea inválida.
- Exponer un estado explícito `configurationBlocked` en las respuestas de estado y configuración.
- Mostrar un popup modal bloqueante con todos los errores detectados.
- Impedir cerrar el popup para continuar usando una configuración inválida.
- Bloquear selección de contexto, navegación operativa y acciones mutantes mientras exista cualquier error.
- Mantener disponibles únicamente los recursos necesarios para cargar la interfaz y consultar el diagnóstico de configuración.
- Exigir corrección externa del archivo y reinicio del panel para salir del bloqueo inicial.
- Imponer el bloqueo también en el backend, sin depender de botones deshabilitados.
- Responder con un error uniforme a toda API operativa invocada durante el bloqueo.
- Volver a ejecutar la validación integral sobre el candidato completo antes de cada mutación de Configuración.
- Rechazar la mutación y conservar byte a byte el archivo vigente si el candidato completo tiene algún error.
- Mantener `configHash`, concurrencia optimista y escritura atómica de SPEC 23.
- Releer y validar el archivo publicado antes de considerar exitosa una mutación.
- Reiniciar contexto y XPZ activos después de toda mutación válida.
- Extender las pruebas con JSON corrupto, errores múltiples, ausencia de efectos laterales y bloqueo uniforme.
- Verificar con Playwright MCP el popup, el foco, la restricción operativa y la carga normal posterior a un reinicio con configuración válida.

**Fuera de alcance (para futuras SPEC):**

- Incorporar un editor de JSON crudo dentro del panel.
- Reparar automáticamente una configuración inválida.
- Reescribir el archivo durante el preflight inicial.
- Crear directorios contextuales como parte de la simulación.
- Exigir disponibilidad física de KB o herramientas externas al iniciar.
- Validar el contenido GeneXus de todas las KB.
- Revalidar el archivo completo ante cada consulta GET ordinaria.
- Aplicar este popup a la consola deprecada.
- Cambiar reglas de exportación, XPZ, documentación, OpenAPI o versionado.

## Modelo de datos

### Estado de configuración del servidor

```json
{
  "configurationValid": false,
  "configurationBlocked": true,
  "configurationErrors": [
    {
      "scope": "trunk/comercial/testing",
      "field": "baseUrl",
      "message": "El baseUrl debe comenzar con '/'."
    },
    {
      "scope": "providencia/erp/production",
      "field": "packagenames.erp",
      "message": "El módulo ERP tiene ambientes y no define su package name."
    }
  ]
}
```

Convenciones:

- `configurationValid` es verdadero únicamente cuando el parseo, el esquema y todas las simulaciones terminan sin errores.
- `configurationBlocked` es el inverso operativo de `configurationValid` durante el arranque.
- `scope` usa `global`, un cliente o el `contextId` completo según el origen.
- `field` contiene la propiedad lógica cuando puede identificarse.
- `message` es accionable y no incluye stack trace ni rutas físicas resueltas que no sean necesarias.
- Los errores se ordenan de forma determinista por scope, campo y mensaje.
- Errores equivalentes producidos por una misma causa no se duplican.

### Resultado de simulación contextual

La simulación construye en memoria el mismo contrato que usaría una activación, pero no crea el árbol:

```json
{
  "clienteId": "trunk",
  "modulo": "comercial",
  "ambienteId": "testing",
  "contextId": "trunk/comercial/testing",
  "packageName": "glmsuit.comercial.",
  "kbPathResolved": "C:/KBs/COMERCIAL_TEST",
  "serverUrl": "https://comercial-test.example.com/comercial-test/servlet/",
  "pathsResolved": true
}
```

`pathsResolved` indica que las rutas pudieron normalizarse. No expresa que existan en el sistema de archivos.

### Respuesta de API bloqueada

Las APIs operativas deben responder con un contrato uniforme y sin iniciar trabajos:

```json
{
  "ok": false,
  "blocked": true,
  "error": "La configuración global es inválida. Corrija configuracion.json y reinicie el panel."
}
```

El código HTTP debe ser consistente para todas las mutaciones bloqueadas. La implementación debe elegir un único código de conflicto de estado del servidor y cubrirlo en pruebas.

## Plan de implementación

1. Crear configuraciones temporales con JSON inválido, errores globales, errores en varios contextos y rutas válidas pero inexistentes.
2. Agregar pruebas que comparen bytes y árbol de directorios antes y después del preflight.
3. Separar en `binary/CargarConfiguracion.ps1` la validación estructural y la resolución contextual de cualquier creación de directorios.
4. Implementar en `binary/ServidorPanelWeb.ps1` una evaluación integral que acumule errores sin cambiar el comportamiento de los consumidores que todavía lanzan al primer error.
5. Ejecutar la evaluación antes de habilitar la sesión y conservar su resultado como estado explícito del servidor.
6. Incorporar `configurationValid`, `configurationBlocked` y `configurationErrors` a las respuestas necesarias del panel.
7. Agregar una barrera central en el servidor para rechazar todas las operaciones incompatibles con el modo bloqueado.
8. Aplicar la misma evaluación integral al candidato de cada mutación antes de su escritura atómica.
9. Releer y verificar el archivo escrito antes de limpiar errores y reiniciar la sesión.
10. Agregar en `web/index.html` el popup de configuración inválida y su estructura accesible.
11. Adaptar `web/app.js` para mostrar todos los errores, contener el foco y bloquear navegación, selectores y acciones.
12. Agregar en `web/style.css` los estados bloqueados y la presentación responsive del diagnóstico.
13. Ejecutar `test/Run-Tests.ps1` y comprobar que ninguna prueba usa el `configuracion.json` real para mutaciones.
14. Verificar mediante Playwright MCP el arranque bloqueado, la imposibilidad de continuar y el arranque normal después de corregir externamente el archivo y reiniciar.

## Criterios de aceptación

- [ ] Un `configuracion.json` ausente deja el servidor en modo bloqueado y muestra un diagnóstico.
- [ ] Un JSON sintácticamente inválido no impide servir la interfaz de diagnóstico.
- [ ] El popup informa el error sintáctico y no intenta inventar clientes o contextos.
- [ ] Un JSON parseable ejecuta la validación de todos sus clientes, módulos y ambientes.
- [ ] La validación no se detiene ante el primer error contextual.
- [ ] El popup muestra todos los errores independientes encontrados.
- [ ] Cada error contextual identifica cliente, módulo y ambiente.
- [ ] El orden de los errores es determinista y no contiene duplicados equivalentes.
- [ ] La simulación resuelve todas las propiedades que utilizaría una activación real.
- [ ] Una ruta normalizable pero físicamente ausente no bloquea el arranque por ese único motivo.
- [ ] La falta física de GeneXus, MSBuild, Pandoc o Typst no bloquea este preflight.
- [ ] El preflight no valida contenido interno de las KB.
- [ ] El preflight no crea ninguna carpeta contextual.
- [ ] El preflight no modifica `configuracion.json`.
- [ ] El preflight no crea logs ni registros de operación.
- [ ] `GET /api/estado` informa de forma explícita si la configuración está bloqueada.
- [ ] El popup bloqueante aparece antes de permitir una selección contextual.
- [ ] El popup no puede cerrarse para acceder a funciones operativas.
- [ ] Los selectores de cliente, módulo y ambiente permanecen deshabilitados durante el bloqueo.
- [ ] No puede accederse programáticamente a una vista operativa mientras el servidor esté bloqueado.
- [ ] Una llamada directa a cualquier API mutante bloqueada no inicia trabajos ni modifica archivos.
- [ ] Las APIs necesarias para obtener el diagnóstico siguen disponibles.
- [ ] Corregir externamente el archivo requiere reiniciar el panel para abandonar el bloqueo inicial.
- [ ] Cada mutación de Configuración valida el candidato global completo antes de escribir.
- [ ] Un error perteneciente a otro cliente también rechaza el candidato.
- [ ] Un candidato inválido conserva byte a byte el archivo anterior.
- [ ] Una mutación válida mantiene `configHash` y escritura atómica.
- [ ] El archivo publicado se relee y valida antes de responder éxito.
- [ ] Una mutación válida reinicia el contexto y XPZ activos.
- [ ] `test/Run-Tests.ps1` cubre JSON corrupto, errores múltiples, solo lectura, bloqueo backend y atomicidad.
- [ ] Playwright MCP confirma que el foco permanece dentro del popup bloqueante.
- [ ] Playwright MCP confirma que el diagnóstico es legible en escritorio y 390x844.
- [ ] Una configuración válida conserva todas las funciones existentes del panel.

## Decisiones

- **Sí:** validar el archivo compartido completo. Un cliente inválido vuelve insegura la configuración global aunque no esté seleccionado.
- **Sí:** simular todos los contextos. La validación debe cubrir las mismas variables que una activación real.
- **Sí:** mantener la simulación en solo lectura. Validar no equivale a inicializar contextos.
- **No:** exigir existencia física de rutas externas al iniciar. Una unidad desconectada o herramienta temporalmente ausente no vuelve inválido el esquema.
- **No:** validar el contenido de todas las KB. Esa comprobación pertenece al preflight operativo del contexto.
- **Sí:** acumular errores. Permite corregir el archivo en una sola iteración.
- **Sí:** iniciar el servidor en modo bloqueado. Es necesario para mostrar el popup web solicitado.
- **Sí:** bloquear también en backend. Ocultar botones no protege las APIs.
- **Sí:** exigir corrección externa y reinicio cuando el arranque encuentra JSON inválido. El CRUD estructurado no puede reparar un documento que no parsea.
- **Sí:** revalidar cada candidato antes de escribir. Ninguna mutación puede dejar inválido a otro cliente.
- **No:** revalidar en cada GET. Agregaría coste sin mejorar el contrato de arranque y mutaciones.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| La agregación cambia funciones compartidas que esperan la primera excepción | Mantener esos contratos y agregar un orquestador específico que capture errores por fase y contexto. |
| La simulación crea carpetas accidentalmente | Separar resolución de inicialización y comparar el árbol antes y después en pruebas. |
| El frontend parece bloqueado pero una API sigue activa | Aplicar una barrera común en el servidor y probar todas las mutaciones. |
| Un error repetido genera una lista inmanejable | Normalizar, deduplicar y ordenar errores por scope y campo. |
| Una herramienta no disponible impide consultar el panel | Validar formato y resolución, no existencia física, durante este preflight. |
| Una mutación válida localmente rompe otro contexto | Simular el candidato completo antes de la escritura atómica. |

## Lo que **no** incluye esta SPEC

- Editor de JSON crudo.
- Reparación automática de configuración.
- Creación de árboles contextuales durante el arranque.
- Validación física de todas las KB y herramientas.
- Validación de contenido GeneXus durante el preflight global.
- Revalidación completa en cada consulta GET.
- Cambios en el pipeline documental.
- Adaptación de la consola deprecada.

La disponibilidad operativa de una KB o herramienta se seguirá comprobando cuando la operación correspondiente la necesite.
