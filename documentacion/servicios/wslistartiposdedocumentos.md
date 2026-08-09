# WSListar Tipos De Documentos

WSListar Tipos De Documentos.

## Definición del servicio

| Dato | Valor |
|---|---|
| Endpoint | `glmsuit.comercial.apiglm.comun.awslistartiposdedocumentos` |
| Descripción | WSListar Tipos De Documentos |
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

Sin parámetros de entrada.

## Salida exitosa

Colección: `SI`.

| Campo | Tipo | Descripción |
|---|---|---|
| `Codigo` | Integer (2) | Codigo |
| `Descripcion` | String (60) | Descripcion |

## Errores específicos

No se identificaron errores específicos en el programa principal.

```json
{
  "status": <Código HTTP>,
  "Description": "<descripción general>",
  "detail": "<detalle>",
  "JsonResult": ""
}
```
