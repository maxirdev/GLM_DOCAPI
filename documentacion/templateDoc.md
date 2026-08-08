# Plantilla de documentación de servicios APIGLM

Este documento es la tercera fuente normativa y contiene el formato final. Se utiliza después de completar [analisisXPZ.md](analisisXPZ.md) y aplicar [reglasEditoriales.md](reglasEditoriales.md).

## Instrucciones de uso

- Copiar la plantilla para cada servicio.
- Trasladar la única ficha técnica sin recalcular método, entrada, tipos, obligatoriedad, salida, errores ni endpoint.
- Usar la plantilla solo cuando exista un programa principal separado y único.
- Conservar únicamente la variante de entrada correspondiente.
- Reemplazar los marcadores editoriales con datos confirmados o pendientes.
- El campo Endpoint lleva el nombre completo publicado (package + módulo + procedimiento), en minúsculas, recibido en la ficha.
- Conservar en el JSON común `<Código HTTP>`, `<descripción general>` y `<detalle>`.
- Conservar los marcadores descriptivos de mensajes dinámicos, como `<número>`.
- Conservar literalmente `{Base64(usuario:contraseña)}` y no incluir credenciales reales.
- Eliminar filas de ejemplo, variantes y comentarios HTML que no correspondan.
- No incluir nombres internos de SDT ni detalles técnicos de GeneXus.

## Plantilla obligatoria

````markdown
# <Nombre funcional del servicio>

<Descripción funcional del servicio>.

## Definición del servicio

| Dato | Valor |
|---|---|
| Endpoint | `<nombre completo del endpoint publicado o PENDIENTE DE CONFIRMACIÓN>` |
| Descripción | <Descripción funcional> |
| Método HTTP | `<GET/POST>` |
| Autenticación | HTTP Basic mediante `Authorization` |

## Generalidades

### Autenticación

```http
Authorization: Basic {Base64(usuario:contraseña)}
```

No incluir credenciales reales.

### Códigos HTTP comunes

| Código | Significado |
|---:|---|
| 200 | Solicitud procesada correctamente. |
| 400 | Faltan parámetros requeridos o son inválidos. |
| 401 | Falló la autenticación. |
| 500 | Error interno de Servicio. |
| 501 | Servicio no implementado o sin configuración. |
| 503 | Servicio no disponible o inactivo. |
| <Código HTTP explícito> | <Significado confirmado> |

<!-- Repetir la fila anterior por cada código adicional recibido en la ficha, ordenar numéricamente y no duplicar códigos. Si no existen adicionales, eliminar la fila de ejemplo. -->

## Entrada

<!-- Variante GET: conservar este bloque y eliminar la variante POST. -->

La consulta debe conservar exactamente <cantidad> posiciones y respetar el orden indicado.

| Posición | Parámetro | Tipo | Obligatorio | Descripción |
|---:|---|---|---|---|
| <Posición> | `<Nombre>` | <Tipo canónico> | <SI/NO> | <Descripción funcional> |

<!-- Variante POST: conservar este bloque y eliminar la variante GET. -->

| Parámetro o campo | Tipo | Obligatorio | Descripción |
|---|---|---|---|
| `<Campo simple>` | <Tipo canónico> | <SI/NO> | <Descripción funcional> |
| `<Campo compuesto>` | Estructura <Campo compuesto> | <SI/NO> | <Descripción funcional> |
| `<Colección compuesta>` | Colección de Estructura <Colección compuesta> | <SI/NO> | <Descripción funcional> |
| `<Colección primitiva o no resuelta>` | Colección JSON | <SI/NO> | <Descripción funcional> |

<!-- Repetir el siguiente bloque por cada estructura o colección compuesta, usando siempre la ruta JSON completa. -->

**Estructura de `<ruta JSON>`**

| Campo | Tipo | Obligatorio | Descripción |
|---|---|---|---|
| `<Campo simple>` | <Tipo canónico> | <SI/NO> | <Descripción funcional> |
| `<Subestructura>` | Estructura <Subestructura> | <SI/NO> | <Descripción funcional> |
| `<Subcolección>` | Colección de Estructura <Subcolección> | <SI/NO> | <Descripción funcional> |

## Salida exitosa

Colección: `<SI/NO>`.

| Campo | Tipo | Descripción |
|---|---|---|
| `<Nombre>` | <Tipo canónico> | <Descripción funcional> |

## Errores específicos

<!-- Si existen errores explícitos, conservar la tabla y repetir una fila por cada condición. Si no existen, reemplazar la tabla por: No se identificaron errores específicos en el programa principal. En ambos casos, conservar el JSON común. -->

| Código HTTP | Condición | Respuesta o mensaje |
|---:|---|---|
| <Código explícito> | <Condición confirmada> | `<Mensaje literal o patrón>` |

```json
{
  "status": <Código HTTP>,
  "Description": "<descripción general>",
  "detail": "<detalle>",
  "JsonResult": ""
}
```
````

## Verificación final

- [ ] Conservar solo la variante GET o POST aplicable.
- [ ] Eliminar filas de ejemplo y comentarios HTML.
- [ ] Reemplazar los marcadores editoriales, salvo los canónicos del JSON y los marcadores dinámicos.
- [ ] Mantener la autenticación y la tabla completa de Generalidades.
- [ ] Trasladar tipos y obligatoriedad sin recalcularlos.
- [ ] Separar cada estructura compuesta mediante su ruta JSON.
- [ ] Incluir solo errores explícitos o la indicación estándar.
- [ ] Mantener el JSON común debajo de `Errores específicos`.
- [ ] Quitar credenciales, GUID, XML, nombres internos de SDT y detalles de implementación.
