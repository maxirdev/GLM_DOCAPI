# Documentación de servicios APIGLM

Esta carpeta reúne la metodología y los documentos generados para los servicios HTTP de APIGLM. Su objetivo es transformar la información técnica exportada desde GeneXus en documentación uniforme, verificable y comprensible para quienes necesitan consumir los servicios.

La fuente principal es el archivo [LPS_COM.xpz](../xpz/LPS_COM.xpz). El XPZ contiene el XML exportado de la base de conocimiento GeneXus: procedimientos, código fuente, reglas, variables, estructuras de datos, dominios y atributos. La documentación se obtiene de esa evidencia; no se completa por semejanza con otros servicios ni por suposiciones.

## Visión general del proceso

El proceso tiene dos etapas: primero se obtiene el inventario de endpoints activos y después se analiza individualmente cada servicio.

```text
XPZ
  └─ APIGLM.APIGLMMain
       └─ wrappers HTTP activos
            └─ inventario de endpoints
                 └─ análisis del programa principal
                      └─ ficha técnica
                           └─ documentación del servicio
```

El inventario indica qué servicios están activos. El análisis individual determina cómo se invoca cada uno, qué datos recibe, qué devuelve y qué errores HTTP puede generar.

## Componentes de la carpeta

| Recurso | Función |
|---|---|
| [Endpoint/analisisEndpoint.md](Endpoint/analisisEndpoint.md) | Explica cómo identificar los wrappers HTTP activos dentro del XPZ. |
| [Endpoint/endpoints.md](Endpoint/endpoints.md) | Contiene el inventario vigente de endpoints GeneXus confirmados. |
| [analisisXPZ.md](analisisXPZ.md) | Define cómo analizar un servicio y construir su ficha técnica. |
| [reglasEditoriales.md](reglasEditoriales.md) | Establece cómo presentar la información para el lector final. |
| [templateDoc.md](templateDoc.md) | Define la estructura obligatoria de cada documento de servicio. |
| [servicios](servicios/) | Contiene la documentación generada para los servicios analizados. |

Los tres documentos normativos se aplican en este orden: análisis técnico, reglas editoriales y plantilla final. Este README ofrece una introducción al proceso, pero no reemplaza esas reglas.

## Obtención del inventario de endpoints

El punto de partida es el objeto `APIGLM.APIGLMMain`, incluido en el XPZ. Su código fuente contiene las llamadas a los procedimientos `WS...` que forman el conjunto inicial de servicios activos.

La obtención del inventario sigue esta operatoria:

1. Abrir el XPZ como un contenedor de solo lectura y localizar su XML interno.
2. Buscar en el XML el objeto `APIGLM.APIGLMMain`.
3. Leer sus llamadas activas a procedimientos `WS...`, ignorando las llamadas completamente comentadas.
4. Resolver cada llamada contra un objeto exportado en el XPZ.
5. Confirmar que el objeto sea un procedimiento, tenga `IsMain=True` y utilice `CALL_PROTOCOL=HTTP`.
6. Incorporar una sola vez cada objeto confirmado en [Endpoints/endpoints.md](Endpoint/endpoints.md), respetando el orden de `APIGLMMain`.

Una llamada en `APIGLMMain` es inicialmente un candidato. Solo se considera endpoint confirmado cuando el objeto correspondiente existe en el XML y cumple las propiedades HTTP requeridas.

El inventario conserva el nombre completo de GeneXus, por ejemplo:

```text
APIGLM.Cotizacion.WSObtenerDatosProductor
```

Ese nombre identifica el wrapper dentro de la base de conocimiento, pero todavía no representa la dirección publicada que utilizará un consumidor.

## Análisis individual de un servicio

Una vez seleccionado un elemento de [Endpoint/endpoints.md](Endpoint/endpoints.md), se analiza su objeto `WS...`. Este objeto funciona como wrapper HTTP: recibe la solicitud, ejecuta controles generales y delega el procesamiento en un procedimiento separado.

El procedimiento separado que recibe `APIGLMRequestIn` y produce `APIGLMResponse` es el programa principal del servicio. Allí se busca la información necesaria para preparar la ficha técnica.

El análisis individual comprende:

1. Confirmar el wrapper HTTP y localizar su único programa principal.
2. Determinar el método del servicio:
   - En un GET, la entrada se obtiene de las posiciones de `APIGLMRequestIn.QueryParams`.
   - En un POST, la entrada se obtiene de la estructura deserializada desde `APIGLMRequestIn.Body` mediante `FromJson`.
3. Resolver los tipos de los campos a través de sus variables, dominios, atributos o estructuras de datos.
4. Expandir las estructuras compuestas hasta identificar sus campos simples.
5. Determinar qué campos son obligatorios a partir del uso confirmado en el proceso.
6. Identificar la estructura devuelta cuando la operación finaliza correctamente.
7. Registrar únicamente los errores HTTP explícitos generados por `GenerarAPIGLMResponse` dentro del programa principal.
8. Resolver el endpoint publicado y preparar la ficha técnica que utilizarán las reglas editoriales y la plantilla.

Las validaciones funcionales pueden servir para determinar si un campo es obligatorio, pero no se publican como una sección independiente. Los errores incluidos dentro de una respuesta HTTP 200 tampoco se presentan como errores HTTP del servicio.

## Nombre GeneXus y endpoint publicado

El inventario y la documentación final muestran identificadores diferentes porque cumplen funciones distintas.

| Concepto | Ejemplo | Uso |
|---|---|---|
| Nombre GeneXus | `APIGLM.Cotizacion.WSObtenerDatosProductor` | Localiza el wrapper dentro del XPZ. |
| Endpoint publicado | `apiglm.cotizacion.awsobtenerdatosproductor` | Identifica la ruta relativa documentada para consumir el servicio. |

El endpoint publicado se confirma durante el análisis individual. Se escribe en minúsculas y, para los procedimientos HTTP principales contemplados por la metodología, el nombre publicado incorpora el prefijo `a`. No se agregan host, base URL ni package cuando esos datos no están confirmados.

## Ejemplo resumido

Para `APIGLM.Cotizacion.WSObtenerDatosProductor`, el proceso permite establecer lo siguiente:

1. `WSObtenerDatosProductor` es el wrapper HTTP incluido en el inventario.
2. El wrapper delega en `ObtenerDatosProductor`, que es el programa principal.
3. El programa principal interpreta una única posición de `QueryParams`, correspondiente al código de productor.
4. La respuesta satisfactoria contiene los datos del productor y su código postal.
5. El programa principal genera explícitamente respuestas 400 cuando la cantidad de parámetros es incorrecta y 404 cuando no encuentra al productor.
6. La ficha resultante se presenta en [servicios/WSObtenerDatosProductor.md](servicios/WSObtenerDatosProductor.md).

Este ejemplo muestra la trazabilidad esperada: cada dato publicado debe poder relacionarse con una definición o una instrucción concreta del XPZ.

## Cómo documentar un nuevo servicio

Para agregar la documentación de otro servicio:

1. Elegir el nombre completo desde [Endpoints/endpoints.md](Endpoint/endpoints.md).
2. Aplicar el flujo técnico de [analisisXPZ.md](analisisXPZ.md) y preparar una única ficha con método, endpoint, entrada, obligatoriedad, salida, errores y pendientes.
3. Aplicar [reglasEditoriales.md](reglasEditoriales.md) sin volver a interpretar la evidencia técnica.
4. Copiar la estructura de [templateDoc.md](templateDoc.md), conservar únicamente los bloques aplicables y reemplazar sus marcadores editoriales.
5. Guardar el resultado en [servicios](servicios/) con un nombre que permita reconocer el wrapper documentado.
6. Verificar enlaces, formato Markdown, codificación UTF-8 sin BOM y finales de línea LF.

## Cuándo detener el análisis

La documentación no debe completarse mediante estimaciones. El análisis se detiene y se registra un pendiente cuando, entre otros casos:

- el wrapper no delega en un programa principal separado y único;
- no se puede determinar si la entrada es GET o POST conforme a los patrones admitidos;
- una estructura o un tipo necesario no puede resolverse dentro del XPZ;
- el endpoint publicado no está confirmado;
- distintas fuentes presentan información contradictoria.

Cuando falta evidencia, el documento debe indicar qué dato está pendiente y qué fuente permitiría confirmarlo. De esta manera, la documentación diferencia claramente los hechos comprobados de la información todavía no disponible.

## Resultado esperado

Cada archivo de [servicios](servicios/) debe permitir que una persona comprenda, sin consultar directamente el código GeneXus:

- cuál es el propósito del servicio;
- qué endpoint y método debe utilizar;
- cómo autenticarse;
- qué parámetros o campos debe enviar;
- qué estructura recibe como respuesta satisfactoria;
- qué errores HTTP explícitos puede devolver.

El resultado final es una documentación orientada al consumidor del servicio, respaldada por la evidencia técnica contenida en el XPZ.
