# SPEC 02 — Visor web de los endpoints APIGLM

> **Estado:** Aprobado
> **Depende de:** —
> **Fecha:** 2026-08-07
> **Objetivo:** Crear un visor estático sin dependencias que muestre los endpoints de `documentacion/Endpoints/endpoints.json` en una grilla filtrable, con un script que se ejecuta en cascada con el inventario.

## Alcance

**Incluido:**

- `documentacion/Endpoints/GenerarVisor.ps1`: lee `endpoints.json` y escribe `index.html` incrustando el JSON tal cual (sin cifrado) en `<script type="application/json" id="endpoints-data">`. Sobrescribe siempre. UTF-8 sin BOM y LF.
- `documentacion/Endpoints/style.css` y `documentacion/Endpoints/app.js`: estáticos, sin frameworks, CDN ni build.
- `documentacion/Endpoints/GenerarDocumentacion.cmd`: ejecuta en secuencia `Invoke-EndpointInventory.ps1` y `GenerarVisor.ps1` y verifica el `%ERRORLEVEL%` de ambos.
- Encabezado con "Cliente: LPS_COM", fecha legible de `meta.generatedAt` y total de `meta.totalConfirmed`.
- Grilla con Nombre y Descripción alineadas a la izquierda, filtrable por ambas (insensible a mayúsculas y acentos).
- Toggle claro/oscuro con persistencia en `localStorage`.
- Entrada `documentacion/Endpoints/index.html` en `.gitignore`.

**Excluido (para specs futuros):**

- Cifrado de los datos (decisión: "por ahora sin encriptar").
- Modificar `ObtenerEndpoints.cmd` ni `Invoke-EndpointInventory.ps1`.
- Columnas `proceso` y `endpoint` en la grilla.
- Frameworks, CDN, librerías ni herramientas de build.
- Commit en git.

## Modelo de datos

Esta spec no introduce estructuras nuevas; consume el modelo existente de `endpoints.json` (generado por `Invoke-EndpointInventory.ps1`), incrustado íntegro en `index.html`:

```json
{
  "meta": { "generatedAt": "2026-08-07T22:27:45", "totalConfirmed": 135 },
  "endpoints": [
    { "nombre": "WS - ListarBanco", "descripcion": "WSListar Banco" }
  ]
}
```

`app.js` renderiza desde `endpoints[].nombre` y `endpoints[].descripcion`, y desde `meta.generatedAt` y `meta.totalConfirmed`.

## Plan de implementación

1. Crear `documentacion/Endpoints/GenerarVisor.ps1`: lee `endpoints.json` desde `$PSScriptRoot`, incrusta su contenido y escribe `index.html` (UTF-8 sin BOM, LF, sobrescritura total). Si falta el JSON, mensaje claro y salida ≠ 0. Verificación: ejecutar y abrir `index.html` con doble clic.
2. Crear `documentacion/Endpoints/style.css`: variables CSS para claro/oscuro vía `html[data-theme]`, estética SaaS, tabla, input de filtro y toggle.
3. Crear `documentacion/Endpoints/app.js`: parsear `#endpoints-data`, renderizar encabezado (cliente, fecha `DD/MM/AAAA HH:mm`, total), renderizar grilla, filtrar en vivo por Nombre o Descripción sin distinguir mayúsculas ni acentos (normalización NFD), y toggle de tema con persistencia.
4. Crear `documentacion/Endpoints/GenerarDocumentacion.cmd`: `chcp 65001`, correr ambos `.ps1`, abortar si alguno falla, `pause` final.
5. Agregar `documentacion/Endpoints/index.html` a `.gitignore`.
6. Regenerar y verificar el flujo completo ejecutando `GenerarDocumentacion.cmd` y probando el visor.

## Criterios de aceptación

- [ ] `GenerarDocumentacion.cmd` corre ambos scripts en secuencia y termina con `%ERRORLEVEL%` ≠ 0 si alguno falla.
- [ ] `GenerarVisor.ps1` sobrescribe `index.html` en cada ejecución.
- [ ] `index.html` abre con doble clic (file://) sin servidor ni peticiones de red y no arroja errores de consola.
- [ ] El encabezado muestra "Cliente: LPS_COM", la fecha de `meta.generatedAt` en formato `DD/MM/AAAA HH:mm` y el total de `meta.totalConfirmed`.
- [ ] La grilla muestra una fila por elemento de `endpoints` con Nombre y Descripción alineadas a la izquierda (135 con el inventario actual).
- [ ] El filtro reduce la grilla en vivo por Nombre o Descripción, sin distinguir mayúsculas ni acentos.
- [ ] El toggle cambia claro/oscuro y la elección persiste al recargar.
- [ ] No hay frameworks, CDN ni build.
- [ ] `index.html` está en `.gitignore`; `style.css`, `app.js`, `GenerarVisor.ps1` y `GenerarDocumentacion.cmd` quedan listos para commit.
- [ ] Archivos generados en UTF-8 sin BOM y LF.
- [ ] No se creó commit en git.

## Decisiones

- **Sí:** Datos incrustados sin cifrar en `<script type="application/json">`. Cifrado diferido a una spec futura (decisión del usuario).
- **Sí:** CSS y JS en archivos separados, elegido frente al HTML único.
- **Sí:** Nuevo orquestador `GenerarDocumentacion.cmd` que controla ambos scripts; no se toca `ObtenerEndpoints.cmd`.
- **Sí:** `GenerarVisor.ps1` siempre sobrescribe `index.html`.
- **Sí:** `index.html` en `.gitignore`, coherente con `endpoints.json` y `endpoints.md`.
- **Sí:** Fecha legible `DD/MM/AAAA HH:mm` y total de `meta.totalConfirmed` en el encabezado.
- **Sí:** Filtro insensible a mayúsculas y acentos.
- **Sí:** Tema por defecto según `prefers-color-scheme`, con override persistido en `localStorage`.
- **Sí:** Introducir archivos de código en un repo declarado solo-documentación; se documenta aquí y no se modifica `AGENTS.md` en esta spec.
- **No:** Cifrado XOR/AES por ahora.
- **No:** Columnas `proceso` y `endpoint`.
- **No:** Modificar `ObtenerEndpoints.cmd` ni `Invoke-EndpointInventory.ps1`.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| `localStorage` bloqueado (incógnito) | El toggle funciona en la sesión; solo se pierde la persistencia. |
| El JSON contenga `</script>` | `GenerarVisor.ps1` escapa `</script` → `<\/script` al incrustar. |
| Falte `endpoints.json` al ejecutar el generador | Salida ≠ 0 y mensaje claro; no se escribe `index.html` vacío. |
| Caracteres acentuados de los datos | `charset=utf-8` y escritura en UTF-8 sin BOM. |
| `file://` sin fetch/CORS | No se usa fetch; los datos van incrustados en el propio HTML. |

## Lo que **no** incluye esta spec

- Cifrado de los datos.
- Cambios en `ObtenerEndpoints.cmd` ni en `Invoke-EndpointInventory.ps1`.
- Columnas adicionales en la grilla.
- Frameworks, CDN o build.
- Commit en git.
