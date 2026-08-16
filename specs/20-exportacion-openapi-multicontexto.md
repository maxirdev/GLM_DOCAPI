# SPEC 20 — Exportación OpenAPI multicontexto

> **Estado:** Borrador
> **Depende de:** SPEC 06, SPEC 16, SPEC 18, SPEC 19
> **Fecha:** 2026-08-16
> **Objetivo:** Generar y publicar un contrato OpenAPI 3.0.3 ejecutable por cliente y ambiente a partir del análisis técnico confirmado de los servicios activos.

## Por qué existe esta SPEC

El pipeline ya produce documentación Markdown con método HTTP, endpoint publicado, entrada, tipos, obligatoriedad, salida y errores confirmados. Esa información todavía no está disponible como contrato estructurado para una aplicación web local ni para herramientas como Postman.

El contrato debe generarse desde el resultado técnico de `Analizar-Servicio`, no desde el Markdown redactado. Así se conserva una única fuente de verdad y los cambios editoriales no alteran el contrato ejecutable.

Esta SPEC define únicamente la exportación OpenAPI. La aplicación web que lo consume, el proxy local, la ejecución de peticiones y la exportación Postman se definirán en una SPEC posterior.

## Alcance

**Incluido:**

- Extender cada ambiente del modelo de SPEC 19 con `host` y `baseUrl` obligatorios.
- Validar `host` como origen absoluto `http` o `https` sin path adicional.
- Validar `baseUrl` como ruta iniciada en `/`, separada del host.
- Propagar ambos valores en el contexto resuelto de SPEC 19.
- Crear `binary/GenerarOpenApi.ps1` como punto de entrada independiente y reutilizable.
- Generar un único `documentacion/OpenAPI/openapi.json` por cliente y ambiente.
- Usar OpenAPI `3.0.3` como versión del contrato.
- Incluir únicamente los servicios con estado `ACTIVO` en `controlVersiones.json`.
- Excluir servicios `ELIMINADO`, `OMITIDO`, ignorados o sin publicación documental activa.
- Reanalizar todos los servicios activos del contexto para construir el agregado completo.
- Convertir el resultado de `Analizar-Servicio` a operaciones OpenAPI sin parsear Markdown.
- Representar métodos `GET` y `POST`, entradas, estructuras, colecciones, respuestas, errores HTTP y autenticación HTTP Basic confirmados.
- Usar el endpoint publicado completo como resumen visible de cada operación, por ejemplo `glmsuit.comercial.apiglm.comun.awslistarbanco`.
- Usar el `fullyQualifiedName` como `operationId` estable.
- Agregar tags por módulo GeneXus y por método HTTP.
- Conservar para cada parámetro GET su posición mediante la extensión `x-glm-position`.
- Traducir `Obligatorio = SI` a `required`; no marcar como requeridos los campos `NO`.
- Convertir longitudes y decimales únicamente cuando la restricción sea segura y esté confirmada por el análisis.
- Generar ejemplos neutros por tipo, sin importar valores de las colecciones Postman.
- Representar estructuras recursivas mediante `$ref` sin expansión infinita.
- Representar salidas JSON, textuales, vacías y binarias fielmente al resultado del analizador.
- Usar un `info.title` derivado del prefijo publicado `APIGLM` y un resumen de operación con el endpoint completo.
- Incorporar solo metadatos de contexto no sensibles, sin rutas locales ni credenciales.
- Calcular `info.version` mediante un hash semántico abreviado del contrato.
- No reemplazar el contrato publicado cuando el hash semántico no cambió.
- Publicar el archivo mediante escritura atómica después de validar su estructura.
- Conservar el último `openapi.json` válido cuando la generación falle.
- Regenerar automáticamente OpenAPI después de una publicación documental transaccional de `ActualizarServicios.ps1`.
- Permitir regenerar el contrato manualmente con `binary/GenerarOpenApi.ps1`, incluso cuando solo cambien `host` o `baseUrl`.
- Terminar con código `1` si OpenAPI falla después de que los documentos ya fueron publicados, sin revertir esos documentos.
- Agregar fixtures y casos al harness existente de `test/Run-Tests.ps1`.
- Actualizar `README.md` y `AGENTS.md` con el artefacto y el contrato de configuración.

**Fuera de alcance (para futuras SPEC):**

- Aplicación web local consumidora del contrato.
- Proxy local para evitar CORS.
- Ejecución de peticiones desde navegador.
- Administración de usuarios, contraseñas o credenciales persistidas.
- Exportación de colecciones Postman v2.1.
- Edición de contratos OpenAPI desde una interfaz.
- Swagger UI, SwaggerHub u otro servicio externo.
- Dependencias pagas, CDN, frameworks frontend o gestores de paquetes.
- Modificación del panel web de SPEC 15.
- Generación de OpenAPI desde `GenerarDocumento.ps1` cuando publica Markdown sin actualizar el control de versiones.
- Importación automática de ejemplos desde `resources/LPS  PRUE JSON WS/`.
- Inferencia de `host`, `baseUrl`, tipos, obligatoriedad, respuestas o errores no confirmados.
- Publicación de contratos de servicios que no estén en estado `ACTIVO`.
- Cambio de las reglas normativas de análisis, redacción o plantilla.

## Modelo de datos

### Configuración de ambiente

La estructura de SPEC 19 agrega estas propiedades obligatorias a cada ambiente:

```json
{
  "id": "testing",
  "nombre": "Testing",
  "kbPath": "C:/KBs/SEGUROS_COMERCIAL_TRUNK",
  "host": "https://servidor.example.com",
  "baseUrl": "/testing/rest"
}
```

Convenciones:

- `host` debe ser una URL absoluta `http` o `https`.
- `host` no puede contener credenciales, query string, fragmento ni path distinto de `/`.
- `baseUrl` debe comenzar con `/`.
- `baseUrl` puede terminar o no con `/`; la combinación debe normalizar una sola barra.
- `host` y `baseUrl` se mantienen en `configuracion.json` junto con el ambiente al que pertenecen.
- Los valores reales de cada ambiente son datos operativos y no se infieren desde Postman, el XPZ ni el nombre del ambiente.
- Un ambiente sin cualquiera de los dos valores es inválido para generar un contrato ejecutable.

El contexto canónico de SPEC 19 expone:

```text
Host
BaseUrl
ServerUrl
```

`ServerUrl` se construye únicamente concatenando el `Host` y el `BaseUrl` validados. No se persiste como tercera fuente de configuración.

### Contrato OpenAPI agregado

La salida se publica en:

```text
<contexto>/documentacion/OpenAPI/openapi.json
```

La forma mínima del documento es:

```json
{
  "openapi": "3.0.3",
  "info": {
    "title": "APIGLM",
    "version": "<hash semántico abreviado>"
  },
  "servers": [
    {
      "url": "https://servidor.example.com/testing/rest"
    }
  ],
  "tags": [],
  "paths": {},
  "components": {
    "securitySchemes": {
      "basicAuth": {
        "type": "http",
        "scheme": "basic"
      }
    },
    "schemas": {}
  },
  "x-glm-context": {
    "contextId": "trunk/testing",
    "clienteId": "trunk",
    "ambienteId": "testing"
  }
}
```

Convenciones del contrato:

- `info.title` usa el prefijo publicado `APIGLM`.
- Cada operación usa como `summary` el endpoint publicado completo, por ejemplo `glmsuit.comercial.apiglm.comun.awslistarbanco`.
- Cada operación usa como `operationId` el FQN literal del inventario.
- Cada operación tiene un tag del módulo GeneXus y otro tag con el método HTTP.
- La ruta OpenAPI se deriva del endpoint publicado y se combina con el servidor del contexto.
- Todas las operaciones incluyen el esquema de seguridad HTTP Basic cuando corresponda al contrato vigente.
- `x-glm-context` solo contiene identidad contextual; no contiene rutas físicas, usuarios, contraseñas ni tokens.
- El hash de `info.version` se calcula sobre el contenido semántico del contrato, excluyendo `generatedAt` u otros campos volátiles.
- Un cambio confirmado en host, base URL, operaciones, parámetros, tipos, ejemplos o respuestas modifica el hash semántico.
- Una regeneración sin cambios semánticos no reescribe el archivo ni actualiza su fecha de modificación.

### Extensiones propias

Los parámetros GET conservan la posición confirmada por el analizador:

```json
{
  "name": "EmpCod",
  "in": "query",
  "required": true,
  "schema": {
    "type": "integer",
    "example": 0
  },
  "x-glm-position": 1
}
```

Las extensiones propias permitidas son:

- `x-glm-position` en parámetros GET.
- `x-glm-context` en el documento raíz.
- `x-glm-fqn` en una operación cuando sea necesario conservar el FQN sin depender de `operationId`.
- `x-glm-source` en el documento raíz para identificar el contexto y el XPZ sin exponer rutas locales.

No se agregarán extensiones para completar datos no confirmados.

### Mapeo de tipos

El exportador usa los tipos canónicos producidos por `Analizar-Servicio`:

| Tipo canónico | OpenAPI |
|---|---|
| `Integer` | `type: integer`, `format: int64` cuando corresponda |
| `Integer (<longitud>)` | `type: integer`, con restricciones seguras derivadas de la longitud |
| `Decimal` | `type: number` |
| `Decimal (<longitud>, <decimales>)` | `type: number`, `format: double` y precisión confirmada cuando sea segura |
| `String` | `type: string` |
| `String (<longitud>)` | `type: string`, `maxLength` confirmado |
| `LongVarchar` | `type: string` |
| `Boolean` | `type: boolean` |
| `Date (YYYY-MM-DD)` | `type: string`, `format: date` |
| `DateTime` | `type: string`, `format: date-time` |
| `Base64` | `type: string`, `format: byte` |
| `Estructura <attr>` | `type: object` mediante schema reutilizable |
| `Colección de Estructura <attr>` | `type: array` con `items` por `$ref` |
| `Colección JSON` | `type: array` sin inventar el esquema de sus elementos |

Reglas adicionales:

- Un tipo sin dimensión confirmada conserva solo su familia OpenAPI.
- `Obligatorio = SI` agrega el campo a `required` del objeto correspondiente.
- `Obligatorio = NO` no agrega el campo a `required`.
- Los ejemplos neutros se colocan en `example`, no en `default`.
- Los valores neutros son `""` para strings, `0` para números, `false` para booleanos, una fecha neutra válida para fechas, `null` solo cuando el esquema lo permita, objetos con su estructura y arrays vacíos para colecciones.
- Los ejemplos nunca se obtienen de las colecciones Postman.
- Las referencias recursivas usan `$ref` y no se expanden indefinidamente.
- Un tipo ejecutable no resuelto bloquea la publicación del contrato nuevo.

### Estados de generación

El proceso distingue:

- `PUBLICADO`: se validó y reemplazó el contrato porque cambió semánticamente.
- `SIN_CAMBIOS`: el contrato validado es semánticamente idéntico y se conserva el archivo.
- `CONSERVADO`: falló la nueva generación y se mantiene el último contrato válido.
- `ERROR`: no existe contrato válido previo o falló una condición fatal de configuración, análisis o publicación.

## Plan de implementación

1. Adaptar `binary/CargarConfiguracion.ps1` y `binary/ValidarConfiguracionGLM.ps1` al modelo de SPEC 19 para leer y validar `host` y `baseUrl` por ambiente; agregar fixtures de configuración válidos, ausentes, mal formados y con combinaciones inválidas.
2. Extender el contexto y el manifiesto contextual de SPEC 19 con `Host`, `BaseUrl` y `ServerUrl`, sin duplicar la lógica de resolución de rutas ni permitir que un proceso hijo combine valores de otro ambiente.
3. Crear el contrato interno de conversión en `binary/GenerarOpenApi.ps1`, reutilizando `Analizar-Servicio`, `CargarMultiXPZ`, `GLMUtilidades` y las rutas del contexto; el script debe aceptar el manifiesto contextual y un modo independiente de regeneración.
4. Implementar el mapeo de operaciones GET y POST, parámetros, cuerpos, estructuras, colecciones, `$ref`, required, ejemplos neutros, tags, `operationId`, resumen y `x-glm-position`; comprobar cada caso con fixtures XML y XPZ existentes.
5. Implementar la conversión de respuestas y errores HTTP confirmados, incluyendo JSON estructurado, colecciones, texto, vacío y binario, sin fabricar esquemas ni códigos no presentes en el resultado técnico.
6. Implementar metadatos contextuales, `servers`, autenticación Basic, hash semántico, fast-path y validación propia de OpenAPI 3.0.3; rechazar referencias rotas, rutas duplicadas, `operationId` duplicados y documentos JSON inválidos.
7. Implementar la escritura atómica de `documentacion/OpenAPI/openapi.json`; ante un fallo conservar byte a byte el contrato anterior y generar diagnóstico; si no existe contrato anterior, terminar con código `1` sin publicar un archivo parcial.
8. Integrar `GenerarOpenApi.ps1` en `ActualizarServicios.ps1` después de publicar el lote documental y persistir el control; no invocarlo desde `Escribir-Salidas` ni desde una generación directa que opere sin control.
9. Agregar regeneración manual para cambios exclusivos de `host` o `baseUrl`, sin exigir cambios en Markdown y sin modificar versiones documentales cuando el contrato sea el único artefacto cambiado.
10. Ampliar `test/Run-Tests.ps1` con pruebas de configuración, mapeo, referencias, hash, fast-path, atomicidad, conservación del contrato anterior, servicios activos y aislamiento entre dos clientes y ambientes; ejecutar la suite completa.
11. Actualizar `README.md`, `AGENTS.md` y `.gitignore` para describir la configuración, la ruta contextual, el carácter generado de `openapi.json` y la separación respecto del futuro probador web.

## Criterios de aceptación

- [ ] La SPEC declara explícitamente dependencia de SPEC 06, SPEC 16, SPEC 18 y SPEC 19.
- [ ] Cada ambiente válido contiene `host` y `baseUrl` obligatorios.
- [ ] Un `host` sin esquema HTTP(S), con credenciales, path, query o fragmento es rechazado antes de escribir archivos.
- [ ] Un `baseUrl` que no empieza con `/` es rechazado antes de escribir archivos.
- [ ] La combinación normalizada de `host` y `baseUrl` produce una única URL de servidor sin barras duplicadas.
- [ ] El contexto resuelto expone `Host`, `BaseUrl` y `ServerUrl` del ambiente seleccionado.
- [ ] El contrato se publica en `<contexto>/documentacion/OpenAPI/openapi.json`.
- [ ] El documento publicado declara `openapi` igual a `3.0.3`.
- [ ] El contrato contiene un único `servers.url` correspondiente al ambiente activo.
- [ ] Solo los servicios `ACTIVO` del control aparecen como operaciones.
- [ ] Los servicios `ELIMINADO`, `OMITIDO`, ignorados o no publicados no aparecen.
- [ ] El exportador reanaliza todos los servicios activos y no construye el agregado leyendo Markdown.
- [ ] Cada operación conserva el FQN literal como `operationId`.
- [ ] Cada operación muestra el endpoint publicado completo como `summary`.
- [ ] Cada operación contiene un tag del módulo GeneXus y otro del método HTTP.
- [ ] Los GET conservan las posiciones confirmadas mediante `x-glm-position`.
- [ ] Los POST representan el cuerpo JSON con sus estructuras y colecciones confirmadas.
- [ ] Solo los campos con `Obligatorio = SI` aparecen en `required`.
- [ ] Las longitudes y decimales confirmados se convierten únicamente en restricciones seguras.
- [ ] Los tipos canónicos se convierten al tipo OpenAPI correspondiente sin inventar dimensiones.
- [ ] Las estructuras recursivas se representan con `$ref` sin expansión infinita.
- [ ] Los ejemplos son neutros y no provienen de las colecciones Postman.
- [ ] El contrato no contiene credenciales, tokens, rutas locales ni secretos.
- [ ] Las respuestas JSON, textuales, vacías y binarias se representan según la evidencia técnica disponible.
- [ ] Los códigos HTTP específicos solo aparecen cuando fueron confirmados por el analizador.
- [ ] La autenticación HTTP Basic se representa con un esquema `securitySchemes` válido.
- [ ] `info.version` cambia cuando cambia semánticamente el contrato y no cambia por campos volátiles.
- [ ] Una regeneración sin cambios semánticos conserva el archivo byte a byte y no modifica su fecha.
- [ ] Un JSON con referencias rotas, rutas duplicadas u `operationId` duplicados no se publica.
- [ ] Un fallo de generación conserva byte a byte el último `openapi.json` válido.
- [ ] Si no existe contrato previo y la generación falla, no se crea un archivo parcial y el proceso termina con código `1`.
- [ ] La publicación válida se realiza mediante escritura atómica.
- [ ] `ActualizarServicios.ps1` regenera OpenAPI después de publicar el lote documental y persistir el control.
- [ ] `Escribir-Salidas.ps1` no dispara OpenAPI desde staging ni desde una publicación directa sin control.
- [ ] El cambio exclusivo de `host` o `baseUrl` puede regenerarse mediante `binary/GenerarOpenApi.ps1`.
- [ ] Si OpenAPI falla después de publicar documentos, los documentos no se revierten y el proceso termina con código `1`.
- [ ] La salida de generación distingue `PUBLICADO`, `SIN_CAMBIOS`, `CONSERVADO` y `ERROR`.
- [ ] Dos clientes o ambientes con los mismos FQN producen contratos aislados y no se reemplazan entre sí.
- [ ] El archivo generado queda ignorado por Git según la política de artefactos mutables de SPEC 19.
- [ ] Las pruebas del harness cubren configuración, mapeo OpenAPI, atomicidad, fast-path, fallos y aislamiento contextual.
- [ ] `README.md` y `AGENTS.md` documentan el contrato y no presentan el probador web como parte de esta SPEC.

## Decisiones

- **Sí:** OpenAPI 3.0.3. Tiene compatibilidad amplia con Postman y herramientas locales sin agregar dependencias.
- **Sí:** un único `openapi.json` por ambiente. Simplifica la carga del futuro probador y evita sincronizar un archivo por endpoint.
- **Sí:** generar desde `Analizar-Servicio`. Es la fuente técnica confirmada y evita depender del formato editorial Markdown.
- **Sí:** usar solo servicios `ACTIVO`. El contrato debe reflejar lo publicado, no todo lo descubierto en el XPZ.
- **Sí:** reanalizar todos los servicios activos. Es más mantenible que persistir fragmentos técnicos intermedios y permite reconstruir el agregado desde la fuente.
- **Sí:** mantener `host` y `baseUrl` en la configuración de cada ambiente. Son datos operativos del servidor y no forman parte de la evidencia del XPZ.
- **Sí:** exigir ambos valores. Un contrato sin servidor no es ejecutable por el futuro probador.
- **Sí:** usar `operationId` igual al FQN. Conserva el vínculo estable con el inventario, el control y el análisis.
- **Sí:** usar el endpoint completo como `summary`. Es la forma publicada que el usuario reconocerá y copiará.
- **Sí:** usar tags por módulo y método HTTP. Permite navegación simple sin categorías manuales.
- **Sí:** conservar la posición GET con `x-glm-position`. El orden de `QueryParams` forma parte del contrato vigente.
- **Sí:** usar ejemplos neutros. Evita trasladar datos de negocio o credenciales de las colecciones Postman.
- **Sí:** usar `$ref` para estructuras recursivas. OpenAPI permite expresar el contrato sin truncar evidencia confirmada.
- **Sí:** bloquear solo pendientes ejecutables. Un tipo, método, endpoint o estructura no confirmados hacen inseguro el contrato; una descripción pendiente no cambia la ejecución.
- **Sí:** conservar el contrato anterior ante fallo. Un artefacto válido anterior es preferible a publicar un contrato parcial.
- **Sí:** terminar con código `1` cuando OpenAPI falla después de publicar documentos. El contrato derivado es obligatorio para completar la operación, aunque los documentos ya publicados no se reviertan.
- **Sí:** usar un script independiente. Facilita regenerar por cambio de servidor, diagnosticar y probar sin ejecutar todo el pipeline.
- **Sí:** ignorar `openapi.json` en Git. Es un artefacto contextual generado desde XPZ y configuración.
- **No:** parsear Markdown. Introduciría una segunda fuente de verdad y dependería de texto editorial.
- **No:** importar automáticamente colecciones Postman. Contienen ejemplos de negocio y credenciales con apariencia real; quedan como referencia manual.
- **No:** generar desde `GenerarDocumento.ps1` sin control. Esa vía puede publicar Markdown sin establecer el estado contractual completo.
- **No:** modificar SPEC 15. El panel web y el futuro probador son aplicaciones distintas.
- **No:** incluir el proxy, CORS, ejecución HTTP o exportación Postman. Esos temas pertenecen a la SPEC de la aplicación web.
- **No:** persistir credenciales. El futuro probador deberá mantenerlas solo en memoria de sesión.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Un contrato se genera con documentos de un ambiente y servidor de otro | Propagar `contextId`, `Host`, `BaseUrl` y `ServerUrl` mediante el contexto y validar pertenencia antes de ejecutar. |
| El agregado queda incompleto después de una actualización incremental | Reanalizar todos los servicios `ACTIVO` antes de construir el documento. |
| Un cambio de host deja el contrato apuntando al servidor anterior | Permitir regeneración manual independiente y calcular el hash incluyendo `servers.url`. |
| Un fallo publica JSON parcial o referencias rotas | Validar completamente en staging y publicar atómicamente solo después de pasar todas las comprobaciones. |
| Se pierde un contrato válido por una regeneración fallida | Conservar byte a byte el archivo anterior y registrar el diagnóstico. |
| El contrato expone credenciales o datos de Postman | No importar colecciones ni ejemplos reales; generar únicamente valores neutros y omitir secretos. |
| La conversión de tipos introduce restricciones inventadas | Aplicar restricciones de longitud y precisión solo con evidencia confirmada y segura. |
| Una estructura recursiva causa expansión infinita | Generar schemas reutilizables y referencias `$ref`. |
| La generación directa y la actualización producen contratos distintos | Definir `ActualizarServicios.ps1` como único disparador automático y usar el mismo script reutilizable para regeneración manual. |
| El archivo generado contamina el control de Git | Ignorar la ruta contextual `documentacion/OpenAPI/openapi.json` junto con los demás artefactos mutables. |

## Lo que **no** incluye esta SPEC

- Aplicación web local.
- UI moderna para explorar y ejecutar endpoints.
- Proxy local o solución CORS.
- Ejecución de requests desde el navegador.
- Manejo persistente de credenciales.
- Exportación Postman v2.1.
- Swagger UI, SwaggerHub o servicios pagos.
- Edición manual del contrato desde una interfaz.
- Integración con el panel web de SPEC 15.
- Importación automática de colecciones Postman.
- Contratos por servicio separados.
- Publicación de servicios que no estén `ACTIVO`.

Cada uno de esos temas, si se aborda, va en su propia SPEC.
