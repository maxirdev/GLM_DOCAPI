# WSListar Riesgos

WSListar Riesgos.

## Definición del servicio

| Dato | Valor |
|---|---|
| Endpoint | `glmsuit.comercial.apiglm.comun.awslistarriesgos` |
| Descripción | WSListar Riesgos |
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
| `Empresa` | Integer (2) | NO | Empresa |
| `Rama` | Integer (2) | NO | Rama |
| `PolizaNumero` | Integer (10) | NO | Poliza Numero |
| `RiesgoNumero` | Integer (8) | NO | Riesgo Numero |
| `RiesgoDescripcion` | String (100) | NO | Riesgo Descripcion |
| `InicioVigenciaDesde` | Date (YYYY-MM-DD) | NO | Inicio Vigencia Desde |
| `InicioVigenciaHasta` | Date (YYYY-MM-DD) | NO | Inicio Vigencia Hasta |
| `FinVigenciaDesde` | Date (YYYY-MM-DD) | NO | Fin Vigencia Desde |
| `FinVigenciaHasta` | Date (YYYY-MM-DD) | NO | Fin Vigencia Hasta |

## Salida exitosa

Colección: `NO`.

| Campo | Tipo | Descripción |
|---|---|---|
| `Empresa` | Integer (2) | Empresa |
| `Rama` | Integer (2) | Rama |
| `RamaDsc` | String | Rama Dsc |
| `PolizaNumero` | Integer (10) | Poliza Numero |
| `RiesgoNumero` | Integer (8) | Riesgo Numero |
| `RiesgoDescripcion` | String (100) | Riesgo Descripcion |
| `InicioVigencia` | Date (YYYY-MM-DD) | Inicio Vigencia |
| `FinVigencia` | Date (YYYY-MM-DD) | Fin Vigencia |
| `Estado` | String (1) | Estado |
| `TipoDeRiesgo` | Integer (1) | Tipo De Riesgo |
| `TipoDeRiesgoDescripcion` | String | Tipo De Riesgo Descripcion |

## Errores específicos

| Código HTTP | Respuesta o mensaje |
|---:|---|
| 500 | `Ocurrio un error al recuperar los riesgos` |

```json
{
  "status": <Código HTTP>,
  "Description": "<descripción general>",
  "detail": "<detalle>",
  "JsonResult": ""
}
```
