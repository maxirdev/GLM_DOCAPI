# Análisis de servicios APIGLM desde XPZ

Este documento es la primera fuente normativa del proceso de documentación de servicios APIGLM. Define cómo obtener desde el XPZ la ficha técnica que consumen las reglas editoriales y la plantilla.

## Orden obligatorio

1. Analizar el servicio con este documento.
2. Aplicar [reglasEditoriales.md](reglasEditoriales.md).
3. Generar el documento con [templateDoc.md](templateDoc.md).

## Alcance

La metodología cubre dos patrones de entrada:

- GET mediante posiciones de `APIGLMRequestIn.QueryParams`.
- POST mediante una estructura deserializada desde `APIGLMRequestIn.Body` con `FromJson`.

Si el servicio combina ambas fuentes, usa otro mecanismo de entrada o no permite identificar un programa principal separado, detener el análisis y solicitar confirmación.

## Evidencia y pendientes

Usar el XPZ como fuente principal para Source, Rules, variables, SDT, dominios, atributos y asignaciones. Usar información operativa, código generado, configuración desplegada o una respuesta real sanitizada únicamente cuando el XPZ no pueda confirmar un dato necesario para consumir el servicio.

Si las fuentes se contradicen, no elegir una por analogía. Registrar el dato como pendiente e indicar la evidencia necesaria:

```text
PENDIENTE DE CONFIRMACIÓN: <dato faltante>. Evidencia requerida: <fuente necesaria>.
```

No crear filas ficticias para variables que no forman parte de la entrada confirmada. En GET se documentan únicamente las posiciones resueltas por el parser de `QueryParams`; en POST se documenta la estructura completa deserializada mediante `FromJson`.

## Flujo de análisis

### 1. Identificar el wrapper y el programa principal

Usar `APIGLMMain` solo como inventario inicial de candidatos. Confirmar en el XPZ que el objeto `WS...` tiene `CALL_PROTOCOL=HTTP` y, cuando corresponda, `IsMain=True`.

En el Source del wrapper, localizar la única llamada a un procedimiento separado que recibe `in:&APIGLMRequestIn` y devuelve `out:&APIGLMResponse`. Confirmar la llamada real en el wrapper y la firma en la regla `parm(...)` del procedimiento llamado. Ese procedimiento separado es el programa principal.

Si no existe esa delegación o hay más de un candidato no resoluble, detener el análisis. No tratar automáticamente al wrapper como programa principal.

Los códigos y mensajes presentes únicamente en el wrapper no son errores explícitos del programa principal. Todo servicio APIGLM con wrapper HTTP confirmado documenta HTTP 200 como respuesta satisfactoria por regla global.

### 2. Determinar el método y resolver la entrada

Leer Source, Rules y variables del programa principal.

#### GET

Clasificar como GET cuando el programa principal usa `APIGLMRequestIn.QueryParams` o no recibe parámetros funcionales.

Cuando exista un parser posicional:

- Documentar únicamente las variables asignadas desde cada posición.
- Conservar la cantidad y el orden exactos.
- Tratar los nombres del query string como etiquetas si el parser asigna por posición.
- Mantener las posiciones opcionales vacías en lugar de omitirlas.
- Documentar conversiones o formatos solo cuando estén confirmados.
- No crear una fila para una posición sin variable identificada.

Agregar `EmpCod` solo cuando una posición del query string se resuelva mediante `APIGLMRequestIn.EmpCod`. En ese caso usar `Integer` y la descripción `Código de empresa`. Una lectura independiente de `APIGLMRequestIn.EmpCod` no agrega una posición a la entrada.

#### POST

Clasificar como POST cuando el programa principal lee `APIGLMRequestIn.Body` y lo deserializa mediante `FromJson`.

- Identificar la variable destino de `FromJson`.
- Resolver la definición completa del SDT raíz.
- Documentar todos sus campos, aunque no vuelvan a usarse después de la deserialización.
- Conservar los nombres JSON exactos.
- No asignar posiciones: el orden de propiedades de un objeto JSON no forma parte del contrato.
- No agregar `EmpCod` salvo que pertenezca al SDT deserializado.

Confirmar además si el Body contiene un objeto o una colección. Si el mecanismo no puede resolverse, detener el análisis y solicitar confirmación.

### 3. Expandir estructuras y resolver tipos

Para cada campo de entrada y salida, resolver el tipo mediante `ATTCUSTOMTYPE`, `idBasedOn`, SDT, dominio o atributo. No inferirlo por el nombre.

Aplicar esta tipografía canónica:

- `bas:Numeric` con cero decimales: `Integer (<longitud>)`; si la longitud no está confirmada, `Integer`.
- `bas:Numeric` con decimales: `Decimal (<longitud>, <decimales>)`.
- `bas:Character`, `bas:VarChar`, `bas:LongVarChar` y GUID serializado: `String`. Para `Character` o `VarChar`, usar `String (<longitud>)` cuando la dimensión esté confirmada.
- `bas:Boolean`: `Boolean`.
- `bas:Date`: `Date (YYYY-MM-DD)`.
- `bas:DateTime`: `DateTime`; agregar formato solo con evidencia.
- `bas:Blob` y `bas:Image` serializados: `Base64`.
- Objeto compuesto: `Estructura <nombre del atributo>`.
- Colección compuesta: `Colección de Estructura <nombre del atributo>`.
- Colección primitiva o todavía no resuelta: `Colección JSON`.

No usar como tipos finales `Texto`, `Numérico`, `Booleano`, `LongString`, `Objeto JSON` ni `Colección`. Si un tipo textual no tiene dimensión confirmada, usar `String`. Si `Length` y `AttMaxLen` difieren, usar `String` sin dimensión y sin registrar un pendiente por esa discrepancia.

Para cada estructura compuesta de entrada:

1. Mantener el campo en la tabla que lo contiene.
2. Resolver su SDT, `Level` o referencia equivalente.
3. Crear una tabla independiente con sus hijos directos.
4. Identificarla mediante la ruta JSON completa, por ejemplo `Estructura de RiesgoAUT.AcreedorPrendario`.
5. Repetir hasta alcanzar campos primitivos, dominios o atributos.

Los nombres internos de SDT sirven solo para localizar evidencia y no se publican. Si una referencia no puede localizarse o existe un ciclo, detener únicamente esa rama, registrar el pendiente y continuar con las demás.

### 4. Calcular `Obligatorio`

Analizar la obligatoriedad después de resolver la entrada completa. Las validaciones funcionales se inspeccionan únicamente para esta columna y no se publican como contenido del servicio.

Usar `SI` cuando se confirme al menos una de estas evidencias:

1. Una comprobación explícita o condicional rechaza el campo vacío o inválido, agrega un error o interrumpe el proceso.
2. El campo se usa para filtrar datos o decidir una selección funcional.
3. El campo se pasa directamente a otro proceso como `in:`, `inout:` o sin dirección especificada.
4. Su valor se copia a una variable primitiva y esa copia cumple alguna condición anterior.
5. El campo se referencia en una llamada cuyo procedimiento no está exportado.

Cuando un campo primitivo alcance `SI`, detener su recorrido: no es necesario seguir procedimientos posteriores para volver a confirmar la misma obligatoriedad.

Usar `NO` cuando no exista ninguna de esas evidencias. Un parámetro exclusivamente `out:` no aporta obligatoriedad.

Si se pasa una estructura o colección completa, marcar `SI` solo en su fila. Sus hijos no heredan ese valor. Recorrer el procedimiento llamado únicamente para resolver la obligatoriedad de los hijos todavía pendientes, aplicando el mismo criterio y deteniendo cada campo primitivo al obtener una respuesta.

Asignar varios campos a un SDT y pasar después el SDT completo tampoco convierte automáticamente en obligatorios a sus integrantes. Si el procedimiento llamado no está exportado, no se puede resolver o forma un ciclo, detener esa rama; los hijos sin evidencia individual quedan en `NO`.

Caso de control: en `ValidarDatosDeVehiculo`, la entrada raíz contiene `SistemaOrigen`, `Usuario`, `Rama`, `Solicitud`, `Instalacion` y `RiesgoAUT`, sin `EmpCod`. `Rama`, `Solicitud`, `Instalacion` y `RiesgoAUT` son `SI`; `SistemaOrigen` y `Usuario` son `NO`. `RiesgoAUT` y `RiesgoAUT.AcreedorPrendario` se expanden en tablas independientes y sus hijos requieren evidencia propia.

### 5. Resolver la salida

Seguir la construcción de la respuesta satisfactoria en el programa principal y confirmar:

- La variable enviada como payload.
- Si la salida es una colección.
- Los campos expuestos.
- Los tipos y descripciones de esos campos.

La salida satisfactoria usa HTTP 200. No publicar nombres internos de SDT ni la configuración de la envoltura.

### 6. Extraer errores HTTP explícitos

La única evidencia admitida es una llamada a `GenerarAPIGLMResponse` dentro del programa principal cuyo código sea distinto de 200.

Por cada llamada, registrar una sola vez:

- Código HTTP resuelto.
- Condición que conduce a la llamada.
- Mensaje literal o patrón.

Cuando una parte del mensaje sea dinámica, conservar el texto fijo y representar la parte variable mediante un marcador descriptivo, por ejemplo `Consulte Log. <número>`.

Resolver `HttpCode.BadRequest` como 400, `HttpCode.NotFound` como 404 y `HttpCode.MethodNotAllowed` como 405. No asociar 403 con `BadRequest`; admitirlo solo cuando aparezca explícitamente en una llamada válida.

Excluir códigos provenientes únicamente del wrapper, procedimientos auxiliares, estados internos, campos del payload o evidencia de ejecución. Excluir también errores funcionales contenidos dentro de una respuesta HTTP 200.

La tabla canónica de Generalidades pertenece a [templateDoc.md](templateDoc.md). Agregar allí cada código adicional una sola vez y en orden numérico. Si varias condiciones generan el mismo código, conservar cada condición como una fila independiente en `Errores específicos`.

Si no existen rechazos explícitos, registrar `No se identificaron errores específicos en el programa principal.`.

Casos de control:

- `ValidarDatosDeVehiculo`: registrar 400; ignorar como errores HTTP los resultados funcionales incluidos en `OK=false` bajo HTTP 200.
- `ObtenerVehiculoPorPatente`: registrar 400 y 404; Generalidades contiene una sola fila 404 y `Errores específicos` conserva sus distintas condiciones.
- `WSImprimirCotizacion`: detener el análisis porque no delega en un programa principal separado.

### 7. Resolver el endpoint publicado

Documentar el nombre completo del endpoint publicado, en minúsculas, incluida la base del package, por ejemplo `ar.com.glmsa.seguros.comercial.apiglm.emision.awsobtenertotalessolicitud`. Para Procedures HTTP configuradas como `Main`, anteponer `a` al nombre del proceso: `wslistarsolicitudes` se publica como `awslistarsolicitudes` dentro de su package.

La base del package no se confirma desde el XPZ; requiere evidencia operativa (configuración desplegada o una respuesta real sanitizada) y puede variar entre servicios. No inferir el endpoint por semejanza con otro servicio ni construir host o base URL. Si el nombre completo no puede confirmarse, registrarlo como pendiente indicando la evidencia necesaria.

## Ficha técnica interna

Antes de redactar, preparar una única ficha con:

- Wrapper y programa principal identificados.
- Endpoint publicado y método HTTP.
- Entrada con campos, orden cuando corresponda, tipos y obligatoriedad.
- Árbol completo de estructuras compuestas de entrada.
- Salida con condición de colección, campos, tipos y descripciones.
- Errores HTTP explícitos con código, condición y mensaje o patrón.
- Pendientes y evidencia necesaria.

Esta ficha es la única transferencia hacia [reglasEditoriales.md](reglasEditoriales.md) y [templateDoc.md](templateDoc.md). No recalcular decisiones durante la redacción.

## Lista de verificación técnica

- [ ] El wrapper HTTP y el programa principal separado fueron confirmados.
- [ ] Si no existía una delegación única, el análisis se detuvo.
- [ ] GET o POST se resolvió desde el programa principal.
- [ ] GET contiene únicamente posiciones confirmadas de `QueryParams`.
- [ ] POST contiene la estructura completa usada por `FromJson`.
- [ ] `EmpCod` se aplicó únicamente bajo la excepción definida.
- [ ] Cada estructura compuesta conserva su fila y tiene una tabla por ruta JSON.
- [ ] Los tipos usan exclusivamente la tipografía canónica.
- [ ] Cada campo primitivo dejó de recorrerse al confirmar `Obligatorio`.
- [ ] Solo se recorrieron procedimientos posteriores para hijos pendientes de estructuras compuestas.
- [ ] La salida indica colección, campos, tipos y descripciones.
- [ ] Los errores explícitos provienen únicamente de `GenerarAPIGLMResponse` en el programa principal.
- [ ] Los errores funcionales bajo HTTP 200 y los códigos externos al programa principal fueron excluidos.
- [ ] Los mensajes dinámicos usan marcadores descriptivos.
- [ ] El endpoint publicado (nombre completo) está confirmado o marcado como pendiente.
- [ ] Toda incertidumbre indica la evidencia necesaria.

Siguiente paso obligatorio: [reglasEditoriales.md](reglasEditoriales.md).
