# WS Obtener Detalle Poliza (Comun)

WS Obtener Detalle Poliza (Comun).

## Definición del servicio

| Dato | Valor |
|---|---|
| Endpoint | `glmsuit.comercial.apiglm.comun.awsobtenerdetallepoliza` |
| Descripción | WS Obtener Detalle Poliza (Comun) |
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

La consulta debe conservar exactamente 4 posiciones y respetar el orden indicado.

| Posición | Parámetro | Tipo | Obligatorio | Descripción |
|---:|---|---|---|---|
| 1 | `EmpCod` | Integer | SI | Código de Empresa |
| 2 | `RamCod` | Integer | SI | Código de Rama |
| 3 | `PolNro` | Integer | SI | Nro. de Póliza |
| 4 | `PolNroRie` | Integer | SI | Item |

## Salida exitosa

Colección: `NO`.

| Campo | Tipo | Descripción |
|---|---|---|
| `Empresa` | Integer (2) | Empresa |
| `DscEmpresa` | String (60) | Descripción Empresa |
| `Rama` | Integer (2) | Rama |
| `DscRama` | String (60) | Descripción Rama |
| `Poliza` | Integer (10) | Poliza |
| `DscRiesgo` | String (200) | Descripción Riesgo |
| `InicioVigencia` | Date (YYYY-MM-DD) | Inicio Vigencia |
| `FinVigencia` | Date (YYYY-MM-DD) | Fin Vigencia |
| `Productor` | Integer (7) | Productor |
| `NombreProductor` | String (60) | Nombre Productor |
| `Tomador` | Estructura Tomador | Tomador |
| `DscMoneda` | String (60) | Descripción Moneda |
| `CantidadCuotas` | PENDIENTE DE CONFIRMACIÓN: tipo del campo CantidadCuotas. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Cantidad Cuotas |
| `FormaPago` | String (100) | Forma Pago |
| `Despacho` | String (100) | Despacho |
| `Premio` | Decimal (16, 2) | Premio |
| `TotalEnProcesoDeCobro` | Decimal (16, 2) | Total En Proceso De Cobro |
| `Riesgos` | Colección de Estructura Riesgos | Riesgos |
| `RiesgosAuto` | Colección de Estructura RiesgosAuto | Riesgos Auto |
| `RiesgosVida` | Colección de Estructura RiesgosVida | Riesgos Vida |
| `RiesgosRVarias` | Colección de Estructura RiesgosRVarias | Riesgos RVarias |
| `Suplementos` | Colección de Estructura Suplementos | Suplementos |
| `Cuotas` | Colección de Estructura Cuotas | Cuotas |
| `TipoCoaseguro` | String (1) | Tipo Coaseguro |

## Errores específicos

| Código HTTP | Respuesta o mensaje |
|---:|---|
| 400 | `Servicio invocado sin los parametros necesarios` |
| 400 | `La Póliza buscada no existe` |

```json
{
  "status": <Código HTTP>,
  "Description": "<descripción general>",
  "detail": "<detalle>",
  "JsonResult": ""
}
```
