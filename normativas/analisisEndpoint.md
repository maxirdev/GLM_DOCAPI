# Identificación de endpoints APIGLM desde el XPZ

Esta guía explica cómo un agente debe reproducir el inventario de [endpoints.md](endpoints.md) a partir del XPZ indicado en `configuracion.json` y del proceso `APIGLM.APIGLMMain`.

En este inventario, un endpoint es el nombre completo del procedimiento GeneXus que funciona como wrapper HTTP. No es una URL desplegada. La determinación del método HTTP, los datos de entrada y salida o la URL publicada pertenece al análisis individual definido en [analisisXPZ.md](analisisXPZ.md).

## Fuentes de evidencia

El agente debe usar estas fuentes:

1. El archivo XPZ configurado en `configuracion.json`.
2. Su XML interno (la primera entrada del ZIP cuyo nombre termina en `.xml`), cuya raíz es `ExportFile`.
3. El `Source` del objeto `APIGLM.APIGLMMain`, que delimita los candidatos activos.
4. Los objetos exportados dentro de `/ExportFile/Objects`.
5. El [catálogo de tipos GeneXus](../GeneXus-XPZ-Skills-main/scripts/gx-object-type-catalog.json), que permite confirmar que el valor de `Object/@type` corresponde a `Procedure`.

`APIGLMMain` es la fuente del alcance, pero una llamada presente allí es solamente un candidato hasta que el objeto correspondiente quede confirmado en el XML.

## Procedimiento de identificación

### 1. Validar y abrir el XPZ

Tratar el XPZ como un contenedor de solo lectura. Confirmar que puede abrirse, que contiene un XML interno y que ese archivo es XML bien formado con raíz `ExportFile`.

Si el contenedor no puede abrirse, el XML está ausente o su estructura no puede interpretarse, detener el análisis. No intentar reconstruir el inventario desde los documentos de servicios ni desde nombres recordados.

### 2. Localizar `APIGLMMain`

Buscar exactamente el objeto:

```text
/ExportFile/Objects/Object[@fullyQualifiedName="APIGLM.APIGLMMain"]
```

Dentro de ese objeto, identificar el único `Part/Source` no vacío. Ese bloque contiene las llamadas utilizadas como inventario inicial.

Si el objeto no existe, aparece más de una vez o no puede determinarse un único `Source` efectivo, detener el análisis y registrar el motivo.

### 3. Obtener los candidatos activos

Recorrer el `Source` línea por línea y conservar el orden original.

- Ignorar líneas vacías y texto que no sea una llamada a un procedimiento `WS...`.
- Omitir una línea cuando, después de quitar el espacio inicial, comienza con `//`.
- No omitir una llamada válida solo porque tiene un comentario después del cierre de la llamada.
- No incorporar nombres tomados de títulos de secciones o comentarios.

Esta distinción es obligatoria: un comentario inicial desactiva la llamada, mientras que un comentario posterior solamente describe una llamada activa.

### 4. Resolver el nombre completo

Cuando la llamada ya contiene un nombre completo, buscar un `Object` cuyo atributo `fullyQualifiedName` coincida exactamente.

Cuando la llamada contiene únicamente el nombre local, buscar objetos por el atributo `name`. Resolver el nombre solamente si existe una coincidencia única. No inferir el módulo desde la sección cercana, por semejanza con otros servicios ni por el nombre del procedimiento.

Si no existe coincidencia o aparecen varias, detener la resolución de ese candidato y registrar la ambigüedad. El candidato no puede incorporarse como endpoint confirmado.

### 5. Confirmar el wrapper HTTP

Para aceptar un candidato, verificar en el mismo `Object`:

- que `Object/@type` se corresponda con `Procedure` según el catálogo de tipos;
- que la propiedad de objeto `IsMain` sea `True`;
- que la propiedad de objeto `CALL_PROTOCOL` sea `HTTP`.

Las tres comprobaciones son necesarias. El prefijo `WS` o la presencia de una llamada en `APIGLMMain` no sustituyen la evidencia estructural.

Si alguna propiedad falta o tiene otro valor, no presentar el candidato como endpoint confirmado. Registrar la diferencia y detener la producción de un inventario limpio hasta que sea resuelta.

### 6. Formar el inventario

Agregar cada candidato confirmado una sola vez y en el mismo orden en que aparece en `APIGLMMain`.

Conservar literalmente el `fullyQualifiedName`, incluida su capitalización. No convertirlo a minúsculas, no anteponer `a`, no sustituir `WS` por `AWS` y no completar host, base URL o package.

No ampliar el alcance buscando todos los objetos que tengan `IsMain=True` y `CALL_PROTOCOL=HTTP`. Un procedimiento HTTP que no esté llamado activamente desde `APIGLMMain` queda fuera de este inventario.

## Casos ilustrativos

| Evidencia observada | Resultado | Motivo |
|---|---|---|
| `APIGLM.Cotizacion.WSCotizarSimple()` | Incluir `APIGLM.Cotizacion.WSCotizarSimple` | La llamada ya contiene el nombre completo y el objeto confirma las propiedades requeridas. |
| `APIGLM.Cobranzas.Planillas.WSGenerarPlanillaPago()` | Incluir `APIGLM.Cobranzas.Planillas.WSGenerarPlanillaPago` | Los módulos anidados forman parte del `fullyQualifiedName`. |
| `WSGrabarTramites()` | Incluir `APIGLM.Tramite.WSGrabarTramites` | El XML contiene una única coincidencia por `Object/@name="WSGrabarTramites"`. |
| `//APIGLM.Emision.Automotores.WSObtenerZonaTarifa()` | Excluir | El primer contenido de la línea es `//`; la llamada está comentada. |
| `APIGLM.Claims.WSCartaDanio() //webhook` | Incluir `APIGLM.Claims.WSCartaDanio` | El comentario aparece después de una llamada activa. |
| Objeto `APIGLM.Cotizacion.WSObtenerEspecificos` | Excluir | Aunque el objeto confirma `IsMain=True` y `CALL_PROTOCOL=HTTP`, no está llamado activamente desde `APIGLMMain`. |

## Control del resultado

El resultado esperado debe coincidir con el inventario vigente [endpoints.md](endpoints.md), que se regenera desde el XPZ configurado.

Antes de considerar válido el inventario, confirmar que:

- todas las entradas aparecen en el mismo orden que las llamadas activas de `APIGLMMain`;
- no hay nombres repetidos;
- todos los nombres resuelven a un único objeto;
- todos los objetos aceptados son `Procedure`, `IsMain=True` y `CALL_PROTOCOL=HTTP`;
- `APIGLM.Emision.Automotores.WSObtenerZonaTarifa` no fue incorporado;
- `WSGrabarTramites()` fue resuelto como `APIGLM.Tramite.WSGrabarTramites`;
- el resultado coincide exactamente con [endpoints.md](endpoints.md).

Si el conteo o el contenido no coincide, no corregir el resultado por analogía ni forzarlo a un número esperado. Determinar primero si cambió el XPZ, si cambió `APIGLMMain` o si `endpoints.md` quedó desactualizado, y comunicar la diferencia antes de modificar el inventario.

## Límites

Este procedimiento identifica únicamente los nombres GeneXus que forman el inventario de endpoints APIGLM. No determina:

- el método HTTP efectivo;
- la URL publicada;
- host, base URL o package;
- los parámetros de entrada;
- la estructura de salida;
- los códigos y mensajes HTTP del servicio.

Esos datos requieren el análisis individual del wrapper y de su programa principal conforme a [analisisXPZ.md](analisisXPZ.md).
