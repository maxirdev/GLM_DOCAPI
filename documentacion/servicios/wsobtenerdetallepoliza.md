# WS Obtener Detalle Poliza (Comun)

WS Obtener Detalle Poliza (Comun).

## Definición del servicio

| Dato | Valor |
|---|---|
| Endpoint | `ar.com.glmsa.seguros.comercial.apiglm.comun.awsobtenerdetallepoliza` |
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
| `Empresa` | PENDIENTE DE CONFIRMACIÓN: tipo del campo Empresa. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Empresa |
| `DscEmpresa` | String (60) | Descripción Empresa |
| `Rama` | PENDIENTE DE CONFIRMACIÓN: tipo del campo Rama. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Rama |
| `DscRama` | String (60) | Descripción Rama |
| `Poliza` | PENDIENTE DE CONFIRMACIÓN: tipo del campo Poliza. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Poliza |
| `DscRiesgo` | String (200) | Descripción Riesgo |
| `InicioVigencia` | Date (YYYY-MM-DD) | Inicio Vigencia |
| `FinVigencia` | Date (YYYY-MM-DD) | Fin Vigencia |
| `Productor` | PENDIENTE DE CONFIRMACIÓN: tipo del campo Productor. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Productor |
| `NombreProductor` | String (60) | Nombre Productor |
| `Tomador` | Estructura Tomador | Tomador |
| `DscMoneda` | String (60) | Descripción Moneda |
| `CantidadCuotas` | PENDIENTE DE CONFIRMACIÓN: tipo del campo CantidadCuotas. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Cantidad Cuotas |
| `ComboNro` | PENDIENTE DE CONFIRMACIÓN: tipo del campo ComboNro. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Combo Nro |
| `ComboSecuencia` | PENDIENTE DE CONFIRMACIÓN: tipo del campo ComboSecuencia. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Combo Secuencia |
| `ComboRamPolBase` | PENDIENTE DE CONFIRMACIÓN: tipo del campo ComboRamPolBase. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Rama |
| `ComboPolNroBase` | PENDIENTE DE CONFIRMACIÓN: tipo del campo ComboPolNroBase. Evidencia requerida: respuesta real sanitizada o configuración desplegada. | Combo Pol Nro Base |
| `RiesgosAuto` | Colección de Estructura RiesgosAuto | Riesgos Auto |
| `RiesgosVida` | Colección de Estructura RiesgosVida | Riesgos Vida |
| `Suplementos` | Colección de Estructura Suplementos | Suplementos |
| `Cuotas` | Colección de Estructura Cuotas | Cuotas |

## Errores específicos

| Código HTTP | Condición | Respuesta o mensaje |
|---:|---|---|
| 400 | no se cumple: &colQueryParams.Count = 4 | `Servicio invocado sin los parametros necesarios` |
| 400 | &SDTPolizaDetalle.Poliza = 0 | `La Póliza buscada no existe` |

```json
{
  "status": <Código HTTP>,
  "Description": "<descripción general>",
  "detail": "<detalle>",
  "JsonResult": ""
}
```
