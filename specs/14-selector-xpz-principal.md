# SPEC 14 — Selector de XPZ principal en el lanzador

> **Estado:** Aprobado
> **Depende de:** SPEC 13
> **Fecha:** 2026-08-12
> **Objetivo:** Mostrar al inicio de pantalla el XPZ activo de la sesión y ofrecer una opción de menú para seleccionar cuál de los XPZ principales de la carpeta `xpz/` se usará para operar, listados del más viejo al más nuevo con nombre, fecha `DD-MM-YYYY HH:MM` y un tag que indique el último.

## Por qué existe esta SPEC

El lanzador `GenerarDocumentosGLM.cmd` (SPEC 13) selecciona el XPZ principal dentro de la opción de PDF y no informa al usuario cuál está activo. Se necesita que el encabezado muestre el XPZ en uso y que exista una opción de menú dedicada para elegirlo, de modo que la generación de PDF opere siempre con el XPZ seleccionado sin volver a preguntar.

## Alcance

**Incluido:**

- Mostrar en el encabezado del menú el XPZ activo de la sesión (inicialmente el configurado; si no existe, el más viejo de la lista de principales).
- Nueva opción de menú `2. Seleccionar XPZ principal` que lista los XPZ principales de `xpz/` ordenados del más viejo al más nuevo.
- Cada entrada muestra nombre, fecha `DD-MM-YYYY HH:MM` y un tag que identifica al XPZ más reciente (`ÚLTIMO`).
- Al elegir un XPZ se actualiza el activo de la sesión y se vuelve al menú.
- La opción de generación de PDF pasa a ser la opción 3 y usa el XPZ activo sin volver a preguntar.
- Exclusión de los XPZ complementarios selectivos (`<base>_<N>.xpz`) del listado.
- Detección de fecha: marca temporal del nombre (`_yyyyMMdd_HHmmssfff`); respaldo con fecha de modificación del archivo si el nombre no tiene marca.
- El procesamiento posterior usa el XPZ activo y descubre automáticamente sus complementos asociados `<base>_<N>.xpz` en el mismo directorio, mediante el mecanismo multi-XPZ existente.
- Creación de `binary/ListarXPZPrincipales.ps1` para descubrir, ordenar, fechar y marcar los XPZ principales.

**Fuera de alcance (para futuras SPEC):**

- Persistir la selección en `configuracion.json`; la selección vale solo para la sesión actual.
- Seleccionar XPZ complementarios o fusionar físicamente XPZ.
- Cambiar el mecanismo de exportación o la generación de inventario.
- Rediseñar el visor de endpoints ni las opciones de exportación.
- Modificar el `packagename` de `configuracion.json` al cambiar de XPZ.

## Modelo de datos

`binary/ListarXPZPrincipales.ps1` recibe el directorio `xpz/` y, opcionalmente, la ruta del XPZ configurado. Emite una lista ordenada de más viejo a más nuevo donde cada línea usa `|` como separador:

```text
<nombre>|<fecha DD-MM-YYYY HH:MM>|<esUltimo 1/0>
```

En el `.cmd`:

- `XPZ_ACTIVO` — ruta completa del XPZ activo de la sesión.
- `XPZ_ACTIVO_NOMBRE` — nombre del XPZ activo para el encabezado.
- `XPZ_ARCHIVO_<N>` — ruta completa de cada opción del listado.
- `XPZ_FECHA_<N>` — fecha formateada para mostrar.
- `XPZ_ULTIMO_<N>` — `1` si la entrada es la más reciente.

Inicialización del activo: si la ruta configurada existe, es el activo; si no existe, el activo es la primera entrada del listado (la más vieja).

## Plan de implementación

1. Crear `binary/ListarXPZPrincipales.ps1`: descubre los `.xpz` de `xpz/`, excluye los `<base>_<N>.xpz`, calcula la fecha (marca del nombre; respaldo `LastWriteTime`), ordena de más viejo a más nuevo, marca el último y emite las líneas separadas por `|`.
2. Integrar en `GenerarDocumentosGLM.cmd` la inicialización de `XPZ_ACTIVO` durante el preflight (configurado si existe; si no, el más viejo de la lista) y mostrarlo en `:mostrar_encabezado`.
3. Agregar la opción `2. Seleccionar XPZ principal` que invoca `ListarXPZPrincipales.ps1`, presenta las opciones numeradas con nombre, fecha y tag, y actualiza `XPZ_ACTIVO` al elegir, volviendo al menú. Al cambiar de XPZ, advertir que el `packagename` de `configuracion.json` no se modifica.
4. Renumerar el menú a `1. Exportar APIGLMMain y completar el XPZ | 2. Seleccionar XPZ principal | 3. Generar PDF con el XPZ seleccionado | 4. Salir`.
5. Modificar `:ejecutar_pdf` para operar con `XPZ_ACTIVO` y eliminar el selector interno que preguntaba por el XPZ. El análisis multi-XPZ descubrirá los complementos `<base>_<N>.xpz` del XPZ activo.
6. Conservar los estados `menu_sin_xpz` y `menu_solo_salida`, y la exclusión de complementos selectivos.

Cada paso deja el lanzador operativo para el paso siguiente.

## Criterios de aceptación

- [ ] El encabezado del menú muestra el nombre del XPZ activo de la sesión.
- [ ] Con el XPZ configurado existente, el activo inicial es el configurado.
- [ ] Con el XPZ configurado inexistente, el activo inicial es el más viejo de la lista de principales.
- [ ] La opción 2 lista únicamente XPZ principales, sin `_<N>.xpz`.
- [ ] La lista se muestra del más viejo al más nuevo.
- [ ] Cada entrada muestra nombre y fecha `DD-MM-YYYY HH:MM`.
- [ ] La fecha se deriva de la marca del nombre; si no hay marca, de la fecha de modificación.
- [ ] La entrada más reciente lleva el tag que la identifica como última.
- [ ] Con un único XPZ principal, la opción 2 aparece igualmente y muestra esa entrada.
- [ ] Al elegir un XPZ se actualiza el activo y se vuelve al menú.
- [ ] La opción 3 (Generar PDF) usa el XPZ activo sin volver a preguntar.
- [ ] La selección no modifica `configuracion.json`.
- [ ] Al seleccionar un XPZ principal, sus complementos `<base>_<N>.xpz` asociados se incluyen en el análisis multi-XPZ.
- [ ] El selector advierte cuando el XPZ elegido podría no corresponder al `packagename` de `configuracion.json`.

## Decisiones

- **Sí:** la selección del XPZ es solo de sesión; no se escribe en `configuracion.json`.
- **Sí:** la opción 2 queda dedicada a seleccionar el XPZ; la generación de PDF usa el activo sin selector interno.
- **Sí:** la fecha se toma de la marca del nombre, con respaldo de la fecha de modificación para nombres sin marca.
- **Sí:** el tag de último corresponde a la entrada de mayor marca temporal (o mayor fecha de modificación).
- **Sí:** con el configurado inexistente, el activo inicial es la primera entrada del listado.
- **Sí:** el análisis posterior usa el XPZ activo y descubre sus complementos asociados con el mecanismo multi-XPZ existente.
- **Sí:** se crea `binary/ListarXPZPrincipales.ps1` para el descubrimiento, ordenamiento, formato y marcado, en lugar de extender el batch.
- **No:** no se persiste la selección entre sesiones.
- **No:** no se listan XPZ complementarios ni se fusionan archivos.
- **No:** no se ajusta el `packagename` al cambiar de XPZ; solo se advierte.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Dos XPZ comparten la misma marca temporal y el tag de último es ambiguo. | El tag se asigna a la última entrada del orden estable; la ambigüedad es solo informativa. |
| Un XPZ con nombre sin marca se ordena por fecha de modificación, que puede no reflejar su contenido. | Documentar el respaldo en la interfaz y conservar la marca del nombre como fuente primaria. |
| El listado en batch depende de la salida del script PowerShell. | `ListarXPZPrincipales.ps1` emite formato estable por líneas separadas con `|` y devuelve código distinto de cero ante error. |
| El XPZ elegido pertenece a otro cliente y el `packagename` configurado no corresponde. | Advertir en el selector que `configuracion.json` no se modifica; el endpoint publicado podría no coincidir. |

## Lo que **no** incluye esta SPEC

- Persistencia de la selección del XPZ en `configuracion.json`.
- Selección de XPZ complementarios o fusión física de XPZ.
- Cambios en la exportación, el inventario o la validación de completitud.
- Cambios en el visor de endpoints ni en las reglas de análisis/redacción.
- Ajuste automático del `packagename` al cambiar de XPZ.
