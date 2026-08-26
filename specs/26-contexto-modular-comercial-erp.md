# SPEC 26 — Configuración y contexto modular Comercial/ERP

> **Estado:** Aprobado
> **Depende de:** SPEC 19, SPEC 22, SPEC 23, SPEC 25
> **Fecha:** 2026-08-25
> **Objetivo:** Ampliar la configuración y el panel web para administrar y operar contextos aislados por cliente, módulo y ambiente, conservando las funciones vigentes del pipeline web.

## Por qué existe esta SPEC

El modelo actual admite solamente un ambiente TEST y uno PROD por cliente y resuelve cada contexto como `<cliente>/<ambiente>`. Esto impide administrar en un mismo cliente los módulos Comercial y ERP con ambientes homónimos e independientes.

La configuración actual también contiene datos heredados con la propiedad `baseurl`, mientras el servidor y el formulario consumen `baseUrl`. Esa diferencia provoca que el valor guardado no se recupere al editar el ambiente.

Esta SPEC reemplaza la identidad contextual de dos componentes por una identidad de tres componentes para el panel web y los procesos que este invoca. La aplicación de consola queda deprecada y no recibe nuevos selectores.

## Alcance

**Incluido:**

- Mantener un único archivo central `configuracion.json` para todos los clientes, módulos y ambientes.
- Agregar `modulo` a cada elemento de `clientes[].ambientes[]`.
- Admitir únicamente los valores canónicos `comercial` y `erp`.
- Mostrar los nombres visibles `Comercial` y `ERP`.
- Mantener una colección plana de ambientes dentro de cada cliente.
- Admitir como máximo cuatro ambientes por cliente: Comercial TEST, Comercial PROD, ERP TEST y ERP PROD.
- Rechazar más de un ambiente para la misma combinación `modulo` + `tipo`.
- Permitir que Comercial y ERP reutilicen el mismo `id` de ambiente.
- Mantener la unicidad del `id` de ambiente sin distinguir mayúsculas dentro de cada módulo.
- Incorporar `packagenames.comercial` y `packagenames.erp` en cada cliente.
- Exigir el package name de todo módulo que tenga al menos un ambiente.
- Mantener `serviciosIgnorados` compartido por cliente.
- Crear un cliente junto con su primer ambiente, su módulo y el package name correspondiente en una única mutación atómica.
- Solicitar el package name en el mismo popup que agrega el primer ambiente de un módulo todavía no configurado.
- Permitir editar desde el cliente los package names de los módulos configurados.
- Mantener inmutables el `id` y el `modulo` de un ambiente existente.
- Corregir la lectura de `baseurl` heredado y canonizarlo como `baseUrl`.
- Recuperar `host` y `baseUrl` al abrir la edición de un ambiente.
- Mostrar en cada tarjeta de ambiente tags de módulo y tipo.
- Mostrar `Host` y `Base URL` de forma independiente cuando el campo correspondiente tenga un valor no vacío.
- Agregar en Configuración el filtro por módulo con las opciones `Todos`, `Comercial` y `ERP`.
- Mantener el filtro textual de cliente y combinarlo con el filtro por módulo.
- Reemplazar la regla visual de dos ambientes por la disponibilidad de las cuatro combinaciones válidas.
- Agregar al header los selectores en orden Cliente, Módulo y Ambiente.
- Filtrar los ambientes por el cliente y módulo seleccionados.
- Aplicar autoselección en cascada cuando exista una única opción válida.
- Si el cliente tiene un único ambiente total, seleccionar su módulo y ambiente y activar el contexto automáticamente.
- Si el cliente tiene un único módulo, seleccionarlo automáticamente; si ese módulo tiene un único ambiente, seleccionarlo y activar el contexto.
- Mantener la activación automática al completar una selección contextual inequívoca.
- Definir `contextId` como `<clienteId>/<modulo>/<ambienteId>`.
- Derivar el árbol mutable bajo `clientes/<clienteId>/<modulo>/<ambienteId>/`.
- Mantener bajo la nueva ruta `documentacionServicios`, `estado`, `xpz`, `Logs` y `test/{fixtures,resultados}`.
- Actualizar APIs, sesión, trabajos, logs, inventarios, reportes, OpenAPI y scripts invocados por el panel para transportar la identidad triple.
- Subir el manifiesto de ejecución a `schemaVersion = 3` e incluir `modulo`.
- Rechazar manifiestos de esquema 2 en los flujos nuevos.
- Cambiar la persistencia del navegador a `glm-panel-context:v2`.
- Migrar `glm-panel-context:v1` únicamente cuando el ambiente anterior se resuelva de forma inequívoca como Comercial; en otro caso, eliminarlo y solicitar una selección nueva.
- Crear `binary/MigrarConfiguracionModulos.ps1` para migrar de forma explícita el esquema de `configuracion.json`.
- Proveer en el script de migración preflight, modo simulación, detección de conflictos, escritura atómica y restauración del archivo anterior ante un fallo.
- Interpretar durante la transición un ambiente sin `modulo` como Comercial.
- Interpretar `packagename` heredado como `packagenames.comercial`.
- Interpretar `baseurl` heredado como `baseUrl`.
- Canonizar las propiedades heredadas mediante el script de migración o la siguiente escritura atómica válida.
- No mover, leer ni eliminar los artefactos de las rutas contextuales anteriores.
- Iniciar vacías las nuevas rutas y regenerar XPZ, inventarios, documentación, control, OpenAPI y logs.
- Actualizar `README.md` y `AGENTS.md` con el nuevo modelo contextual.
- Extender `test/Run-Tests.ps1` y los fixtures afectados.
- Verificar con Playwright MCP el CRUD, los filtros, la selección contextual y el aislamiento en escritorio y móvil.

**Fuera de alcance (para futuras SPEC):**

- Crear un archivo de configuración independiente por módulo.
- Agregar módulos distintos de Comercial y ERP.
- Permitir más de un TEST o más de un PROD dentro del mismo módulo.
- Separar `serviciosIgnorados` por módulo.
- Mover `host`, `baseUrl` o `kbPath` fuera del ambiente.
- Mover `geneXusExportProfile` al cliente, módulo o ambiente.
- Adaptar los selectores de `GenerarDocumentosGLM.cmd` o `binary/GestionDocumentosGLM.ps1` al nuevo módulo.
- Migrar, copiar o eliminar automáticamente los artefactos existentes bajo `clientes/<cliente>/<ambiente>`.
- Reutilizar manifiestos, inventarios o reportes producidos con la identidad anterior.
- Cambiar las reglas de análisis XPZ, completitud, redacción, versionado o publicación documental.
- Agregar dependencias frontend, Node.js, npm o CDN.

## Modelo de datos

### Configuración canónica

Cada cliente conserva una colección plana de ambientes. El módulo es una propiedad obligatoria del ambiente y los package names pertenecen al cliente, separados por módulo.

```json
{
  "clientes": [
    {
      "id": "trunk",
      "nombre": "Trunk",
      "packagenames": {
        "comercial": "glmsuit.comercial.",
        "erp": "glmsuit.erp."
      },
      "serviciosIgnorados": [],
      "ambientes": [
        {
          "id": "testing",
          "nombre": "TEST",
          "modulo": "comercial",
          "tipo": "test",
          "kbPath": "C:/KBs/COMERCIAL_TEST",
          "host": "https://comercial-test.example.com",
          "baseUrl": "/comercial-test/servlet/"
        },
        {
          "id": "testing",
          "nombre": "TEST",
          "modulo": "erp",
          "tipo": "test",
          "kbPath": "C:/KBs/ERP_TEST",
          "host": "https://erp-test.example.com",
          "baseUrl": "/erp-test/servlet/"
        }
      ]
    }
  ]
}
```

Convenciones:

- `modulo` es obligatorio en el formato canónico y admite `comercial` o `erp`.
- `tipo` admite `test` o `prod`.
- La clave lógica de un ambiente es `cliente.id` + `ambiente.modulo` + `ambiente.id`.
- La restricción funcional es única por `cliente.id` + `ambiente.modulo` + `ambiente.tipo`.
- `packagenames.<modulo>` es obligatorio si existe al menos un ambiente de ese módulo.
- Un módulo sin ambientes puede omitir su clave de `packagenames`.
- `host` y `baseUrl` continúan siendo opcionales e independientes.
- La combinación para OpenAPI se forma únicamente cuando ambos campos son válidos.
- `baseurl` y `packagename` son alias heredados de lectura y no forman parte del formato canónico final.

### Contexto canónico

```json
{
  "clienteId": "trunk",
  "clienteNombre": "Trunk",
  "modulo": "comercial",
  "moduloNombre": "Comercial",
  "ambienteId": "testing",
  "ambienteNombre": "TEST",
  "ambienteTipo": "test",
  "contextId": "trunk/comercial/testing",
  "directorioContexto": "clientes/trunk/comercial/testing",
  "packageName": "glmsuit.comercial."
}
```

Todas las rutas absolutas derivadas continúan construyéndose desde `directorioContexto`. Ningún consumidor debe localizar un ambiente únicamente por `ambienteId`.

### Contexto persistido en el navegador

```json
{
  "key": "glm-panel-context:v2",
  "value": {
    "clienteId": "trunk",
    "modulo": "comercial",
    "ambienteId": "testing"
  }
}
```

La clave se escribe solo después de activar correctamente el contexto triple. La clave `glm-panel-context:v1` se elimina después de migrarla o descartarla.

### Manifiesto de ejecución

```json
{
  "schemaVersion": 3,
  "contextId": "trunk/comercial/testing",
  "clienteId": "trunk",
  "modulo": "comercial",
  "ambienteId": "testing"
}
```

El manifiesto debe comprobar que la identidad y todas sus rutas pertenecen al mismo contexto triple. Un manifiesto de esquema 2 no se completa ni se interpreta por analogía.

### APIs contextuales

`GET /api/contextos`, `GET /api/estado` y `POST /api/contexto/activar` incorporan `modulo`. La activación recibe:

```json
{
  "clienteId": "trunk",
  "modulo": "comercial",
  "ambienteId": "testing"
}
```

Las mutaciones de ambiente deben identificar también el módulo para distinguir IDs homónimos. La forma canónica de sus rutas será:

```text
POST   /api/configuracion/clientes/{clienteId}/modulos/{modulo}/ambientes
PUT    /api/configuracion/clientes/{clienteId}/modulos/{modulo}/ambientes/{ambienteId}
DELETE /api/configuracion/clientes/{clienteId}/modulos/{modulo}/ambientes/{ambienteId}
```

El alta del primer ambiente de un módulo puede incluir el nuevo package name en el mismo payload y debe publicarse como una sola transacción.

## Plan de implementación

1. Ampliar los fixtures de configuración con ambientes homónimos entre módulos, las cuatro combinaciones válidas, módulos inválidos, combinaciones duplicadas, aliases heredados y package names faltantes.
2. Crear pruebas de migración en copias temporales que cubran simulación, canonización, conflictos, escritura atómica y restauración ante fallo.
3. Implementar `binary/MigrarConfiguracionModulos.ps1` sin tocar las carpetas contextuales anteriores.
4. Extender `binary/CargarConfiguracion.ps1` para validar `modulo`, `packagenames`, cardinalidad por módulo y resolución de ambientes por identidad triple.
5. Cambiar la derivación de rutas y el objeto contextual a `clientes/<cliente>/<modulo>/<ambiente>`.
6. Subir `binary/ManifiestoEjecucion.ps1` al esquema 3 y validar `clienteId`, `modulo`, `ambienteId`, `contextId` y rutas como una unidad.
7. Propagar `modulo` por los scripts reconstruidos desde el manifiesto o invocados directamente por el panel, incluyendo exportación, validación, completitud, actualización, generación PDF, inventario, resumen y OpenAPI.
8. Actualizar `binary/ServidorPanelWeb.ps1` para mantener una sesión triple, devolver contextos modulares y activar un contexto sin búsquedas ambiguas.
9. Adaptar el CRUD del servidor a `packagenames`, ambientes planos con módulo, cuatro combinaciones y URLs que incluyan módulo.
10. Actualizar los contratos derivados de trabajos, logs, inventarios, validaciones, reviews y OpenAPI para usar el nuevo `contextId` y regenerar los formatos no reutilizables.
11. Agregar el selector Módulo entre Cliente y Ambiente en `web/index.html` y aplicar en `web/app.js` el encadenamiento, bloqueo y autoselección definidos.
12. Reemplazar la persistencia contextual por `glm-panel-context:v2` e implementar la migración segura de `v1` solo cuando sea inequívoca.
13. Adaptar los popups de cliente y ambiente para capturar módulo y package name de forma transaccional y recuperar correctamente `host` y `baseUrl`.
14. Actualizar `web/app/components/crud-list.js`, la vista de Configuración y `web/style.css` para tags, datos opcionales, filtros combinados y layout responsive.
15. Actualizar `configuracion.json` mediante el script de migración y comprobar que el formato resultante vuelve a cargarse sin aliases heredados.
16. Actualizar `README.md` y `AGENTS.md`, declarando la consola como deprecada y el panel como entrada operativa modular.
17. Ejecutar `test/Run-Tests.ps1` y verificar aislamiento entre Comercial y ERP con el mismo `ambienteId`.
18. Verificar mediante Playwright MCP el alta, edición, filtros, autoselección, restauración, conflicto de contexto y operación de ambos módulos en escritorio y móvil.

## Criterios de aceptación

- [ ] Toda configuración canónica usa un único `configuracion.json`.
- [ ] Cada ambiente contiene `modulo: "comercial"` o `modulo: "erp"`.
- [ ] Un cliente admite como máximo las cuatro combinaciones Comercial TEST/PROD y ERP TEST/PROD.
- [ ] El servidor rechaza una combinación módulo/tipo repetida.
- [ ] Comercial y ERP pueden tener ambientes con el mismo `id`.
- [ ] Dos ambientes del mismo módulo no pueden compartir `id` sin distinguir mayúsculas.
- [ ] Todo módulo con ambientes tiene un `packagenames.<modulo>` no vacío.
- [ ] Crear un cliente publica conjuntamente su primer ambiente, módulo y package name.
- [ ] Agregar el primer ambiente del segundo módulo publica conjuntamente su package name.
- [ ] Los package names configurados pueden editarse desde el popup de cliente.
- [ ] El `id` y el módulo de un ambiente existente permanecen inmutables.
- [ ] Un ambiente heredado sin módulo se interpreta como Comercial durante la transición.
- [ ] `packagename` heredado se interpreta como `packagenames.comercial`.
- [ ] `baseurl` heredado se recupera al editar y se canoniza como `baseUrl`.
- [ ] Abrir la edición de un ambiente recupera `kbPath`, `host`, `baseUrl`, tipo y módulo.
- [ ] Cada tarjeta muestra tags de módulo y tipo.
- [ ] La tarjeta muestra Host cuando tiene valor aunque Base URL esté vacío.
- [ ] La tarjeta muestra Base URL cuando tiene valor aunque Host esté vacío.
- [ ] Los campos opcionales vacíos no generan líneas vacías en la tarjeta.
- [ ] Configuración permite filtrar por Todos, Comercial y ERP.
- [ ] El filtro de módulo se combina con la búsqueda textual del cliente.
- [ ] El header presenta los selectores Cliente, Módulo y Ambiente en ese orden.
- [ ] Elegir cliente filtra módulos y elegir módulo filtra ambientes.
- [ ] Una única opción se selecciona automáticamente según la cascada definida.
- [ ] Un contexto inequívoco se activa sin agregar un botón de confirmación.
- [ ] `glm-panel-context:v2` guarda cliente, módulo y ambiente después de una activación válida.
- [ ] Una clave `v1` inequívoca se migra a Comercial y se elimina.
- [ ] Una clave `v1` ambigua u obsoleta se elimina y solicita una selección nueva.
- [ ] `contextId` usa exactamente `<cliente>/<modulo>/<ambiente>`.
- [ ] Todo artefacto nuevo queda bajo `clientes/<cliente>/<modulo>/<ambiente>`.
- [ ] Comercial y ERP con el mismo ID no comparten XPZ, documentos, control, locks, logs ni pruebas.
- [ ] El pipeline web no reconstruye un contexto buscando solo `ambienteId`.
- [ ] Los manifiestos nuevos usan esquema 3 e incluyen el módulo.
- [ ] Un manifiesto de esquema 2 es rechazado y no se completa implícitamente.
- [ ] OpenAPI usa el package name del módulo activo.
- [ ] Los scripts invocados por el panel reciben o leen el módulo antes de resolver rutas.
- [ ] Los artefactos anteriores no se mueven, leen ni eliminan automáticamente.
- [ ] Las rutas nuevas comienzan sin reutilizar documentación o XPZ heredados.
- [ ] El script de migración admite simulación y no modifica el archivo durante ella.
- [ ] Un conflicto detectado por la migración conserva byte a byte `configuracion.json`.
- [ ] Un fallo durante la migración restaura el archivo anterior.
- [ ] La aplicación de consola no recibe nuevos selectores ni forma parte de la verificación funcional.
- [ ] `test/Run-Tests.ps1` cubre esquema, migración, API, manifiestos, aislamiento y regresión del pipeline web.
- [ ] Playwright MCP verifica los dos módulos, los filtros y la selección automática sin errores de consola.
- [ ] El panel continúa funcionando en escritorio y 390x844, en tema claro y oscuro.

## Decisiones

- **Sí:** persistir `modulo` en cada ambiente del `configuracion.json` compartido. No se crean archivos separados por módulo.
- **Sí:** mantener una lista plana de ambientes. El módulo forma parte de la identidad lógica.
- **Sí:** usar `comercial` y `erp` como valores canónicos. La presentación usa Comercial y ERP.
- **Sí:** permitir IDs de ambiente homónimos entre módulos. La identidad completa evita colisiones.
- **Sí:** limitar por combinación módulo/tipo. El máximo de cuatro surge de dos módulos por dos tipos.
- **Sí:** usar `packagenames` por módulo. Comercial y ERP pueden publicar prefijos distintos.
- **No:** duplicar el package name en cada ambiente. Evita divergencias entre TEST y PROD del mismo módulo.
- **Sí:** mantener `serviciosIgnorados` por cliente. Separarlo no forma parte del pedido.
- **Sí:** mantener módulo e ID inmutables. Ambos determinan la ruta contextual.
- **Sí:** canonizar `baseUrl`. Coincide con los contratos actuales del servidor y corrige la pérdida del valor `baseurl`.
- **Sí:** usar `cliente/modulo/ambiente` para identidad y ruta. Aísla explícitamente módulos homónimos.
- **Sí:** usar `glm-panel-context:v2`. El contrato persistido agrega una dimensión obligatoria.
- **Sí:** subir el manifiesto a esquema 3. El módulo cambia la identidad y no puede añadirse silenciosamente al esquema 2.
- **Sí:** migrar solo la configuración y regenerar artefactos. Evita atribuir documentación o XPZ anteriores a un contexto nuevo sin reprocesarlos.
- **No:** mover o borrar las carpetas contextuales anteriores. La aplicación nueva simplemente no las consume.
- **Sí:** adaptar solo el panel y los procesos que invoca. La consola queda deprecada.
- **No:** mover Gx18/Evo3 al módulo. Los radios Comercial/ERP reutilizan el patrón visual, no la semántica del perfil de exportación.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Una búsqueda por ambiente selecciona el módulo equivocado | Exigir cliente, módulo y ambiente en API, sesión, manifiestos y scripts. |
| Una migración parcial corrompe la configuración | Ejecutar preflight, escribir atómicamente y restaurar el archivo anterior ante fallo. |
| Un alias heredado oculta host o Base URL | Aceptar `baseurl` solo al leer y canonizar siempre como `baseUrl`. |
| Un package incorrecto publica endpoints de otro módulo | Resolver `PackageName` desde `packagenames.<modulo>` y probar OpenAPI por módulo. |
| El navegador restaura un ambiente homónimo incorrecto | Versionar localStorage y migrar `v1` solo con una coincidencia inequívoca. |
| Un manifiesto anterior mezcla rutas nuevas y antiguas | Subir a esquema 3 y rechazar esquema 2. |
| Los artefactos antiguos parecen desaparecer | Declarar su descarte operativo y exigir regeneración en las nuevas rutas. |
| La consola deprecada resuelve contextos incompletos | Excluirla del flujo soportado y documentar que el panel es la entrada modular vigente. |

## Lo que **no** incluye esta SPEC

- Archivos `configuracion.json` separados por módulo.
- Módulos adicionales a Comercial y ERP.
- Más de cuatro combinaciones por cliente.
- Servicios ignorados por módulo.
- Perfil GeneXus por módulo o ambiente.
- Adaptación de la consola deprecada.
- Migración o eliminación de artefactos anteriores.
- Reutilización de manifiestos esquema 2.
- Cambios en reglas funcionales del analizador XPZ o del control de versiones.
- Dependencias frontend o una cadena de build.

Toda ampliación a nuevos módulos o reactivación de la consola requiere una SPEC independiente.
