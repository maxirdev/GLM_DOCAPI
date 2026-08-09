# WSNovedad Operatia Detalle

WSNovedad Operatia Detalle.

## Definición del servicio

| Dato | Valor |
|---|---|
| Endpoint | `glmsuit.comercial.apiglm.comun.awsobtenernovedadoperativa` |
| Descripción | WSNovedad Operatia Detalle |
| Método HTTP | `GET` |
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

## Entrada

La consulta debe conservar exactamente 3 posiciones y respetar el orden indicado.

| Posición | Parámetro | Tipo | Obligatorio | Descripción |
|---:|---|---|---|---|
| 1 | `Empresa` | Integer | SI | Empresa |
| 2 | `Anio` | Integer | SI | Anio |
| 3 | `Id` | Integer | SI | Id Novedad Operativa |

## Salida exitosa

Colección: `NO`.

| Campo | Tipo | Descripción |
|---|---|---|
| `Empresa` | PENDIENTE DE CONFIRMACIÓN: tipo del campo Empresa. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Empresa |
| `Anio` | PENDIENTE DE CONFIRMACIÓN: tipo del campo Anio. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Año Novedad Operativa |
| `Id` | PENDIENTE DE CONFIRMACIÓN: tipo del campo Id. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Id Novedad Operativa |
| `Tipo` | PENDIENTE DE CONFIRMACIÓN: tipo del campo Tipo. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Tipo Novedad Operativa |
| `TipoDescripcion` | PENDIENTE DE CONFIRMACIÓN: tipo del campo TipoDescripcion. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Descripción Tipo Novedad Operativa |
| `Usuario` | PENDIENTE DE CONFIRMACIÓN: tipo del campo Usuario. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Usuario Novedad Operativa |
| `FechaHora` | PENDIENTE DE CONFIRMACIÓN: tipo del campo FechaHora. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Fecha Hora Novedad Operativa |
| `Titulo` | PENDIENTE DE CONFIRMACIÓN: tipo del campo Titulo. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Título Novedad Operativa |
| `Texto` | PENDIENTE DE CONFIRMACIÓN: tipo del campo Texto. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Texto Novedad Operativa |
| `FechaLeida` | PENDIENTE DE CONFIRMACIÓN: tipo del campo FechaLeida. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Fecha Hasta Leida Novedad Operativa |
| `FechaNoLeida` | PENDIENTE DE CONFIRMACIÓN: tipo del campo FechaNoLeida. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Fecha Hasta No Leida Novedad Operativa |
| `Estado` | PENDIENTE DE CONFIRMACIÓN: tipo del campo Estado. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Estado Novedad Operativa |
| `TipoIntermediario` | PENDIENTE DE CONFIRMACIÓN: tipo del campo TipoIntermediario. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Tipo Intermediario Novedad Operativa |
| `Intermediario` | PENDIENTE DE CONFIRMACIÓN: tipo del campo Intermediario. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Número Intermediario Novedad Operativa |
| `IntermediarioNombre` | PENDIENTE DE CONFIRMACIÓN: tipo del campo IntermediarioNombre. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Nombre Intermediario Novedad Operativa |
| `Rama` | PENDIENTE DE CONFIRMACIÓN: tipo del campo Rama. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Rama Novedad Operativa |
| `RamaDescripcion` | PENDIENTE DE CONFIRMACIÓN: tipo del campo RamaDescripcion. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Descripción Rama |
| `Poliza` | PENDIENTE DE CONFIRMACIÓN: tipo del campo Poliza. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Póliza Novedad Operativa |
| `Siniestro` | PENDIENTE DE CONFIRMACIÓN: tipo del campo Siniestro. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Siniestro Novedad Operativa |

## Errores específicos

| Código HTTP | Respuesta o mensaje |
|---:|---|
| 400 | `Servicio invocado sin los parametros necesarios` |

```json
{
  "status": <Código HTTP>,
  "Description": "<descripción general>",
  "detail": "<detalle>",
  "JsonResult": ""
}
```
