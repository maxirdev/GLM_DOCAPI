# Obtener Totales Solicitud

Devuelve los totales de una solicitud de emisión: prima, bonificaciones, recargos, impuestos, premio, cuotas y comisión.

## Definición del servicio

| Dato | Valor |
|---|---|
| Endpoint | `ar.com.glmsa.seguros.comercial.apiglm.emision.awsobtenertotalessolicitud` |
| Descripción | Devuelve los totales de una solicitud de emisión: prima, bonificaciones, recargos, impuestos, premio, cuotas y comisión. |
| Método HTTP | `POST` |
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

| Parámetro o campo | Tipo | Obligatorio | Descripción |
|---|---|---|---|
| `Empresa` | Integer (2) | SI | Código de empresa |
| `Rama` | Integer (2) | SI | Rama |
| `Solicitud` | Integer (8) | SI | Solicitud |
| `Instalacion` | Integer (4) | SI | Instalación Distri |

## Salida exitosa

Colección: `NO`.

| Campo | Tipo | Descripción |
|---|---|---|
| `ImporteContado` | Decimal (16, 2) | Importe Contado |
| `CantidadCuotas` | Integer (2) | Cantidad Cuotas |
| `Comision` | Decimal (16, 2) | Comision |
| `ImporteRestoCuotas` | Decimal (16, 2) | Importe Resto Cuotas |
| `ImporteCuota1` | Decimal (16, 2) | Importe Cuota1 |
| `Premio` | Decimal (16, 2) | Premio |
| `Impuestos` | Decimal (16, 2) | Impuestos |
| `DerechoEmision` | Decimal (16, 2) | Derecho Emision |
| `RecargoFinanciero` | Decimal (16, 2) | Recargo Financiero |
| `RecargoAdministrativo` | Decimal (16, 2) | Recargo Administrativo |
| `PorcRecargoAdministrativo` | Decimal (6, 2) | Porc Recargo Administrativo |
| `Bonificacion` | Decimal (16, 2) | Bonificacion |
| `PorcBonificacion` | Decimal (6, 2) | Porc Bonificacion |
| `Prima` | Decimal (16, 2) | Prima |

## Errores específicos

| Código HTTP | Condición | Respuesta o mensaje |
|---:|---|---|
| 400 | El Body de la solicitud está vacío. | `Servicio invocado sin los parametros necesarios` |

```json
{
  "status": <Código HTTP>,
  "Description": "<descripción general>",
  "detail": "<detalle>",
  "JsonResult": ""
}
```
