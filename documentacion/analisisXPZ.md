# Análisis de servicios APIGLM desde XPZ

Este documento es la primera fuente normativa del proceso de documentación de servicios APIGLM. Define cómo obtener desde el XPZ la documentación técnica que consumen las reglas editoriales y la plantilla.

## Orden obligatorio

1. Analizar el servicio con este documento.
2. Aplicar [reglasEditoriales.md](reglasEditoriales.md).
3. Generar el documento con [templateDoc.md](templateDoc.md).

## Alcance

La metodología cubre dos patrones de entrada:

- GET mediante posiciones de `APIGLMRequestIn.QueryParams`.
- POST mediante una estructura deserializada desde `APIGLMRequestIn.Body` con `FromJson`.

Si el servicio combina ambas fuentes o usa otro mecanismo de entrada, detener el análisis y solicitar confirmación. Se prefiere un programa principal delegado y único; si no existe una delegación utilizable pero el wrapper contiene lógica REST reconocible, analizar el propio wrapper como programa principal.

## Evidencia y pendientes

Usar el XPZ como fuente principal para Source, Rules, variables, SDT, dominios, atributos y asignaciones. Usar información operativa, código generado, configuración desplegada o una respuesta real sanitizada únicamente cuando el XPZ no pueda confirmar un dato necesario para consumir el servicio.

La fuente de verdad es únicamente el XPZ indicado en `configuracion.json`. No buscar delegados, SDT ni procedimientos en otros XPZ disponibles localmente (p. ej. versiones viejas o de otros clientes): un objeto ausente en el XPZ configurado se trata como no exportado.

Los servicios listados en `serviciosIgnorados` de `configuracion.json` están referenciados en el inventario pero no se documentan. `GenerarDocumento.ps1` los informa al abrir la consola y los excluye del procesamiento con estado `OMITIDO`; no se genera su documento ni se registran como error.

Si las fuentes se contradicen, no elegir una por analogía. Registrar el dato como pendiente e indicar la evidencia necesaria:

```text
PENDIENTE DE CONFIRMACIÓN: <dato faltante>. Evidencia requerida: <fuente necesaria>.
```

No crear filas ficticias para variables que no forman parte de la entrada confirmada. En GET se documentan únicamente las posiciones resueltas por el parser de `QueryParams`; en POST se documenta la estructura completa deserializada mediante `FromJson`.

## Flujo de análisis

### 1. Identificar el wrapper y el programa principal

Usar `APIGLMMain` solo como inventario inicial de candidatos. Confirmar en el XPZ que el objeto `WS...` tiene `CALL_PROTOCOL=HTTP` y, cuando corresponda, `IsMain=True`.

En el Source del wrapper, localizar la única llamada a un procedimiento separado que recibe `in:&APIGLMRequestIn` y devuelve `out:&APIGLMResponse`. Confirmar la llamada real en el wrapper y la firma en la regla `parm(...)` del procedimiento llamado. Ese procedimiento separado es el programa principal preferido.

Si no existe esa delegación, usar el wrapper como programa principal únicamente cuando contenga lógica REST reconocible (`QueryParams`, `Body`, `GenerarAPIGLMResponse`, `HttpResponse.AddFile/AddString` o `GenerarHttpResponse`). Si hay más de un candidato no resoluble o tampoco existe lógica REST confirmada en el wrapper, detener el análisis.

Los códigos y mensajes presentes únicamente en el wrapper no son errores explícitos del programa principal. Todo servicio APIGLM con wrapper HTTP confirmado documenta HTTP 200 como respuesta satisfactoria por regla global.

### 2. Determinar el método y resolver la entrada

Leer Source, Rules y variables del programa principal.

#### GET

Clasificar como GET cuando el programa principal usa `APIGLMRequestIn.QueryParams` o no recibe parámetros funcionales.

Si el programa usa `QueryParams` y además deserializa una estructura con `FromJson` desde una posición de la URL (`&Sdt.FromJson(&colQueryParams.Item(N))`), el método es ambiguo (una estructura no viaja en la URL de un GET); detener el análisis y marcar error `Método ambiguo`.

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

Cuando una referencia `idBasedOn` de dominio (`Domain:Nombre`) venga sin calificar el módulo y existan dominios homónimos en módulos distintos, resolver al dominio de la raíz (aquel cuyo `fullyQualifiedName` coincide exactamente con el nombre de la referencia). Cuando se necesita un dominio de otro módulo, la referencia lo califica (`Domain:Nombre, Modulo`), y esa forma prevalece sobre la raíz. Si aun así la referencia no puede resolverse sin ambigüedad, no completar por analogía ni suposiciones.

La resolución de SDT homónimos es análoga a la de dominios: una referencia `sdt:Nombre` sin calificador de módulo con varios candidatos se resuelve al SDT de la raíz (aquel cuyo `fullyQualifiedName` coincide exactamente con el nombre). Cuando se necesita un SDT de otro módulo, la referencia lo califica (`sdt:Nombre, Modulo`), y esa forma prevalece sin respaldo a la raíz. Si la referencia calificada no encuentra el SDT en ese módulo, no completar por analogía ni suposiciones.

Cuando la cadena de resolución llegue a un nodo hoja sin `ATTCUSTOMTYPE` ni `idBasedOn`, mapear el tipo con los datos presentes en el XPZ: la presencia de `Decimals` (incluso `0`) o de `Length`/`AttMaxLen` confirma `bas:Numeric` (tipo por defecto de GeneXus para dominios y atributos sin tipo declarado), produciendo `Integer (<longitud>)` o `Decimal (<longitud>, <decimales>)`. Solo cuando el nodo no exponga ningún dato de tipo (sin `bas:`, sin `idBasedOn`, sin `Length` ni `Decimals`) el tipo no puede confirmarse desde el XPZ: detener la generación del documento y registrar el dato con la evidencia requerida (configuración desplegada o respuesta real sanitizada). No usar `ATT_PICTURE` como evidencia de tipo.

Aplicar esta tipografía canónica:

- `bas:Numeric` con cero decimales: `Integer (<longitud>)`; si la longitud no está confirmada, `Integer`.
- `bas:Numeric` con decimales: `Decimal (<longitud>, <decimales>)`.
- `bas:Character`, `bas:VarChar` y GUID serializado: `String`. Para `Character` o `VarChar`, usar `String (<longitud>)` cuando la dimensión esté confirmada.
- `bas:LongVarChar`: `LongVarchar`.
- `bas:Boolean`: `Boolean`.
- `bas:Date`: `Date (YYYY-MM-DD)`.
- `bas:DateTime`: `DateTime`; agregar formato solo con evidencia.
- `bas:Blob` y `bas:Image` serializados: `Base64`.
- En GET, la declaración compatible de la variable tiene prioridad sobre la
  conversión del parser. Si solo se confirma la familia por `ToNumeric`,
  `ToString` o `Trim`, usar `Integer` o `String` sin dimensión.
- Objeto compuesto: `Estructura <nombre del atributo>`.
- Colección compuesta: `Colección de Estructura <nombre del atributo>`.
- Colección primitiva con tipo de elemento confirmado: `Colección de <tipo del elemento>`, por ejemplo `Colección de String (100)`.
- Colección primitiva cuyo tipo de elemento no se confirma: `Colección JSON`.

No usar como tipos finales `Texto`, `Numérico`, `Booleano`, `LongString`, `Objeto JSON` ni `Colección`. Si un tipo textual no tiene dimensión confirmada, usar `String`. Si `Length` y `AttMaxLen` difieren, usar `String` sin dimensión y sin registrar un pendiente por esa discrepancia.

Para cada estructura compuesta de entrada:

1. Mantener el campo en la tabla que lo contiene.
2. Resolver su SDT, `Level` o referencia equivalente.
3. Crear una tabla independiente con sus hijos directos.
4. Identificarla mediante la ruta JSON completa, por ejemplo `Estructura de RiesgoAUT.AcreedorPrendario`.
5. Repetir hasta alcanzar campos primitivos, dominios o atributos.

Los nombres internos de SDT sirven solo para localizar evidencia y no se publican. Si una referencia no puede localizarse, detener únicamente esa rama, registrar el pendiente y continuar con las demás. Una autorreferencia a un SDT exportado no es una estructura inválida: conservar el campo que produce la recursión, determinar si es colección también desde el nodo raíz del SDT referenciado, indicar que repite la misma estructura y detener allí su expansión. No generar tablas infinitas ni convertir una autorreferencia confirmada en error o pendiente.

Para asignaciones entre SDT, atributos y variables, conservar la ruta JSON completa
(`Variable.Ruta`) y resolver el RHS de esa ruta. En colecciones se sigue el SDT
temporal asociado al `Add`. Los campos homónimos de rutas distintas no comparten
tipos. Cuando una variable se pasa a un Procedure, mapear el argumento real con el
parámetro formal de su `parm(...)` y recorrer únicamente el destino exportado de
forma unívoca. El recorrido es transitivo, memoizado y protegido contra ciclos;
una rama ausente o ambigua queda pendiente con su cadena de evidencia.

Cuando el miembro continúe sin tipo, buscar evidencia en todos los Procedures del
XPZ mediante la identidad exacta del SDT y su ruta interna completa. El índice se
construye una vez y se memoiza. Se admiten asignaciones desde el miembro hacia un
destino tipado, asignaciones desde un origen tipado hacia el miembro y argumentos
reales vinculados con parámetros formales tipados. Solo resolver cuando todas las
evidencias confirmen un único tipo canónico. No compartir evidencia entre SDT
distintos aunque sus campos tengan el mismo nombre.

Las operaciones aritméticas o comparaciones pueden confirmar que un valor pertenece
a la familia numérica. Si no permiten distinguir `Integer` de `Decimal` o no aportan
la precisión requerida, el campo permanece pendiente y el diagnóstico registra la
familia confirmada y la metadata faltante. No introducir `Numeric` como tipo final ni
forzar `Integer` por el nombre del campo.

### 4. Calcular `Obligatorio`

Analizar la obligatoriedad después de resolver la entrada completa. Ignorar la
asignación inicial del parser GET y marcar `SI` cuando el valor se valida, consume o
se pasa como argumento real. El flujo puede seguir el parámetro formal de Procedures
exportados de forma unívoca; un argumento directo conserva `SI` aunque el receptor
no esté exportado. No heredar obligatoriedad a hijos de un SDT completo cuando falta
el receptor. Las validaciones funcionales se inspeccionan únicamente para esta
columna y no se publican como contenido del servicio.

Usar `SI` cuando se confirme al menos una de estas evidencias:

1. Una comprobación explícita o condicional rechaza el campo vacío o inválido, agrega un error o interrumpe el proceso.
2. El campo se usa para filtrar datos o decidir una selección funcional (p. ej. en una cláusula `where`).
3. El campo se referencia en cualquier parte del flujo confirmado: asignación no
   perteneciente al parser, condición, filtro, consumo o paso como parámetro a otro
   procedimiento.

Usar `NO` cuando el campo no aparece referenciado en el programa principal.

Un parámetro exclusivamente `out:` no aporta obligatoriedad.

Si se pasa una estructura o colección completa como parámetro a otro procedimiento, marcar `SI` en la fila de esa estructura o colección. Sus hijos no heredan ese valor: cada uno requiere evidencia propia de uso en el programa principal.

Caso de control: en `ValidarDatosDeVehiculo`, la entrada raíz contiene `SistemaOrigen`, `Usuario`, `Rama`, `Solicitud`, `Instalacion` y `RiesgoAUT`, sin `EmpCod`. `Rama`, `Solicitud`, `Instalacion` y `RiesgoAUT` son `SI`; `SistemaOrigen` y `Usuario` son `NO`. `RiesgoAUT` y `RiesgoAUT.AcreedorPrendario` se expanden en tablas independientes y sus hijos requieren evidencia propia.

### 5. Resolver la salida

Seguir la construcción de la respuesta satisfactoria en el programa principal y confirmar:

- La variable enviada como payload.
- Si la salida es una colección.
- Los campos expuestos.
- Los tipos y descripciones de esos campos.

La salida satisfactoria usa HTTP 200. No publicar nombres internos de SDT ni la configuración de la envoltura. Si el `APIGLMResponse` se construye en un Procedure delegado, seguir exclusivamente el parámetro `out:` y el argumento real confirmado, con el mismo recorrido transitivo acotado usado para tipos.

La salida es una colección cuando el payload declara `AttCollection=True` (variable o SDT devuelto) o cuando el SDT está definido como colección en su nodo principal. Un payload escalar (`&X` o `&X.ToString()`) se documenta como un único campo con su tipo canónico. Un payload vacío (`''`) se documenta como `Sin mensaje explícito` sin generar pendiente. Un literal o concatenación explícita en el tercer argumento de `GenerarAPIGLMResponse(HttpCode.OK, ...)` se documenta como `Mensaje` (uno o varios mensajes normalizados), sin inventar un SDT. `HttpResponse.AddFile` se documenta como `Content-Type: application/octet-stream` y `Archivo binario`; no se afirma PDF, XLSX ni otra extensión.

Si el procedimiento principal de un servicio no está exportado en el XPZ configurado, detener el análisis con el mensaje `El programa principal <X> no está exportado en el XPZ configurado. No puede inferirse.` Igual criterio cuando la salida referencia un SDT ausente: `La salida del SDT <X> no está exportada en el XPZ configurado. No puede inferirse.` No completar la estructura por analogía.

Si tras los controles anteriores la salida no puede determinarse, detener el análisis y marcar error: no se genera un documento con salida vacía no confirmada.

### 6. Extraer errores HTTP explícitos

La única evidencia admitida es una llamada a `GenerarAPIGLMResponse` dentro del programa principal cuyo código sea distinto de 200.

Por cada llamada, registrar una sola vez:

- Código HTTP resuelto.
- Mensaje literal o patrón.

Cuando una parte del mensaje sea dinámica, conservar el texto fijo y representar la parte variable mediante un marcador descriptivo, por ejemplo `Consulte Log. <número>`.

Resolver `HttpCode.BadRequest` como 400, `HttpCode.NotFound` como 404 y `HttpCode.MethodNotAllowed` como 405. No asociar 403 con `BadRequest`; admitirlo solo cuando aparezca explícitamente en una llamada válida.

Excluir códigos provenientes únicamente del wrapper, procedimientos auxiliares, estados internos, campos del payload o evidencia de ejecución. Excluir también errores funcionales contenidos dentro de una respuesta HTTP 200.

La tabla canónica de Generalidades pertenece a [templateDoc.md](templateDoc.md). Agregar allí cada código adicional una sola vez y en orden numérico. Si varias llamadas generan el mismo código, conservar cada mensaje distinto como una fila independiente en `Errores específicos`. No publicar condiciones GeneXus: la condición interna no se documenta, solo código y mensaje.

Si no existen rechazos explícitos, registrar `No se identificaron errores específicos en el programa principal.`.

Casos de control:

- `ValidarDatosDeVehiculo`: registrar 400; ignorar como errores HTTP los resultados funcionales incluidos en `OK=false` bajo HTTP 200.
- `ObtenerVehiculoPorPatente`: registrar 400 y 404; Generalidades contiene una sola fila 404 y `Errores específicos` conserva sus distintas condiciones.
- Un wrapper sin delegación utilizable solo puede analizarse como programa principal cuando contiene lógica REST reconocible; en caso contrario, detener el análisis.

### 7. Resolver el endpoint publicado

Documentar el nombre completo del endpoint publicado, en minúsculas, incluido el packagename, por ejemplo `ar.com.glmsa.seguros.comercial.apiglm.emision.awsobtenertotalessolicitud`. Para Procedures HTTP configuradas como `Main`, anteponer `a` al nombre del proceso: `wslistarsolicitudes` se publica como `awslistarsolicitudes` dentro de su package.

El `packagename` es una constante única por XPZ definida en `configuracion.json` (raíz del repo): `ar.com.glmsa.seguros.comercial.` para LPS_COM.xpz, `glmsuit.comercial.` para versiones más nuevas como Trunk.xpz. No se confirma desde el XPZ; se toma tal cual de la configuración. No inferir el endpoint por semejanza con otro servicio ni construir host o base URL.

## Documentación técnica interna

Antes de redactar, preparar un único documento técnico con:

- Wrapper y programa principal identificados.
- Endpoint publicado y método HTTP.
- Entrada con campos, orden cuando corresponda, tipos y obligatoriedad.
- Árbol completo de estructuras compuestas de entrada.
- Salida con condición de colección, campos, tipos y descripciones.
- Las filas internas conservan `RutaJson` y, si corresponde, `DetallePendiente`.
- La salida interna conserva `MensajesSalida[]` separada de estructuras, escalares,
  payload vacío y archivo binario.
- Errores HTTP explícitos con código y mensaje o patrón.
- Pendientes y evidencia necesaria.

Esta documentación es la única transferencia hacia [reglasEditoriales.md](reglasEditoriales.md) y [templateDoc.md](templateDoc.md). No recalcular decisiones durante la redacción.

## Lista de verificación técnica

- [ ] El wrapper HTTP y un programa principal único, delegado o autocontenido, fueron confirmados.
- [ ] Si no existía una delegación única, se confirmó lógica REST en el propio wrapper o se detuvo el análisis.
- [ ] GET o POST se resolvió desde el programa principal.
- [ ] GET contiene únicamente posiciones confirmadas de `QueryParams`.
- [ ] POST contiene la estructura completa usada por `FromJson`.
- [ ] `EmpCod` se aplicó únicamente bajo la excepción definida.
- [ ] Cada estructura compuesta conserva su fila y tiene una tabla por ruta JSON.
- [ ] Las autorreferencias SDT se conservaron como referencias recursivas y no se expandieron indefinidamente.
- [ ] Los tipos usan exclusivamente la tipografía canónica.
- [ ] La evidencia global de tipos se aplicó únicamente por FQN de SDT y ruta interna exacta.
- [ ] `Obligatorio` ignoró la asignación del parser y siguió argumentos reales/formales unívocos de forma transitiva y acotada.
- [ ] Los campos sin consumo confirmado quedaron como `NO`.
- [ ] La salida indica colección, campos, tipos y descripciones, o mensaje textual/archivo binario genérico confirmado.
- [ ] Los errores explícitos provienen únicamente de `GenerarAPIGLMResponse` en el programa principal.
- [ ] Los errores funcionales bajo HTTP 200 y los códigos externos al programa principal fueron excluidos.
- [ ] Los mensajes dinámicos usan marcadores descriptivos.
- [ ] El endpoint publicado (nombre completo) está confirmado o marcado como pendiente.
- [ ] Toda incertidumbre indica la evidencia necesaria.

Siguiente paso obligatorio: [reglasEditoriales.md](reglasEditoriales.md).
