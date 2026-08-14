# SPEC 09 — Pruebas locales del pipeline, analizador y visor

> **Estado:** Aprobado
> **Depende de:** SPEC 05, SPEC 06, SPEC 07
> **Fecha:** 2026-08-09
> **Nota (actualización):** 2026-08-13 — la spec cubre los cambios del pipeline desde su versión original: carga multi-XPZ (`CargarMultiXPZ.ps1`) con descubrimiento de complementos y cascada, el estado `OMITIDO` por `serviciosIgnorados`, la nueva ruta del visor (`documentacion/Endpoints/web/`) y el esquema ampliado de `configuracion.json` (`cliente`, `exportacion`, `herramientas`).
> **Objetivo:** Crear un harness manual y sin dependencias externas que verifique las regresiones críticas del pipeline, analizador XPZ y visor sin modificar las salidas reales.

## Alcance

**Incluido:**

- Carpeta `test/`.
- Script manual `test/Run-Tests.ps1` compatible con PowerShell 5.1.
- Fixtures XML, JSON y XPZ mínimos en `test/fixtures/`.
- Temporales aislados en `test/tmp/`.
- Logs de pruebas en `test/Logs/`.
- Casos de pipeline, analizador y visor.
- Casos de posiciones GET: para un servicio GET, todas las posiciones de `QueryParams` usadas en el programa principal aparecen en el Markdown con su orden correcto (columna `Posición`).
- Casos de validación estática de los Markdown de `documentacion/servicios/` contra `templateDoc.md` y `reglasEditoriales.md`: orden de secciones, sin comentarios ni filas de ejemplo, bloques canónicos literales, `Obligatorio` solo `SI`/`NO`, tipos canónicos, JSON común y coherencia de entrada/salida.
- Casos de multi-XPZ: descubrimiento de complementos `<base>_<N>.xpz` y cascada de resolución (primer XPZ gana ante FQN/guid duplicado) mediante `Cargar-IndiceMultiXPZ`.
- Caso del estado `OMITIDO` en el review del pipeline (servicios de `serviciosIgnorados`).
- Casos de configuración ampliada: `cliente`, `exportacion`, `herramientas` y override `-XpzPath`.
- Visor en su ruta actual `documentacion/Endpoints/web/` (`APIServicios.html`, `style.css`, `app.js`) e inventario en `documentacion/Endpoints/assets/endpoints.json`.
- Aserciones propias sin Pester ni módulos externos.
- Limpieza de `test/tmp/` siempre al finalizar.
- Log `test/Logs/yyyyMMdd-HHmmss-test.txt` con PASS, FAIL, SKIP y resumen.
- Código 0 sin fallos y código 1 con al menos un fallo.

**Fuera de alcance:**

- Node.js.
- Pester u otra dependencia instalada.
- Pruebas de red o servicios desplegados.
- Escritura en las carpetas productivas.
- Regeneración completa del repositorio.
- Cobertura de `ValidarXPZ.ps1` (SPEC 11), de la exportación selectiva (SPEC 12) ni del lanzador `GenerarDocumentosGLM.cmd` (SPEC 13).

## Modelo de datos

Cada caso tendrá identificador, resultado y detalle en memoria:

```powershell
[pscustomobject]@{
    Id = 'pipeline.duplicados'
    Estado = 'PASS'
    Detalle = 'El primer wrapper gana y el segundo queda como warning.'
}
```

Casos de ejemplo por área:

```powershell
[pscustomobject]@{
    Id = 'pipeline.multixpz.cascada'
    Estado = 'PASS'
    Detalle = 'Un objeto solo en el complemento _1.xpz se resuelve y el XPZ principal gana ante FQN/guid duplicado.'
}
[pscustomobject]@{
    Id = 'pipeline.omitido'
    Estado = 'PASS'
    Detalle = 'Un servicio en serviciosIgnorados entra al review con estado OMITIDO y no se documenta.'
}
```

El log de pruebas será texto legible y separado de los logs productivos.

## Plan de implementación

1. Crear `test/Run-Tests.ps1` con funciones de aserción, registro de casos y limpieza en `finally`.
2. Crear fixtures XML para wrapper, programa principal, GET, POST, SDT anidado, tipo faltante, ciclo y llamada multilínea.
3. Crear fixtures JSON para inventario válido, duplicados y control de versiones mínimo.
4. Crear fixtures XPZ mínimos basados en fragmentos de los XPZ reales de `xpz/` (patrón `SEGUROS_COMERCIAL_APIGLM_*`), incluido un complemento sintético `_1.xpz` para los casos de multi-XPZ.
5. Añadir casos de configuración, override, parseo único, duplicados, estados, borrado de documento fallido, review y código de salida.
6. Añadir casos de posiciones GET: fixture de un programa principal GET con varias posiciones de `QueryParams` (incluida al menos una posición no consecutiva) y aserción de que el Markdown documenta exactamente esas posiciones en orden ascendente.
7. Añadir casos de multi-XPZ: descubrimiento de complementos y cascada con FQN/guid duplicado.
8. Añadir casos de tipos, obligatoriedad, SDT de entrada/salida, ciclo, ausencia de SDT, llamadas multilínea y códigos HTTP.
9. Añadir validaciones estáticas de los Markdown de `documentacion/servicios/`: orden canónico de secciones, ausencia de comentarios HTML y filas de ejemplo, bloques canónicos literales, `Obligatorio` solo `SI`/`NO`, tipos canónicos, JSON común con claves exactas, coherencia de `Entrada` y `Salida exitosa`, y correspondencia del nombre de archivo con el wrapper del inventario.
10. Añadir validaciones estáticas del visor en `documentacion/Endpoints/web/`: escape HTML/JSON, referencias CSS/JS, atributos accesibles y adaptación móvil.
11. Ejecutar los casos en orden, escribir el TXT y devolver el código de salida.
12. Ejecutar manualmente el script en PowerShell 5.1 y revisar el log.

## Criterios de aceptación

- [ ] `test/Run-Tests.ps1` se ejecuta en PowerShell 5.1 sin módulos externos.
- [ ] El script crea y elimina `test/tmp/` mediante `finally`.
- [ ] Ningún caso escribe en carpetas productivas.
- [ ] Se genera un log TXT con timestamp, casos y resumen.
- [ ] El script devuelve 0 cuando todos los casos pasan.
- [ ] El script devuelve 1 cuando algún caso falla.
- [ ] Se prueba el XPZ configurado y el override explícito.
- [ ] Se prueba que el primer wrapper duplicado gana y el segundo se omite.
- [ ] Se prueba que un error elimina el documento previo solo del servicio seleccionado.
- [ ] Se prueba que, en un servicio GET, todas las posiciones de `QueryParams` presentes en el programa principal aparecen en el Markdown con su orden numérico ascendente.
- [ ] Se prueba que una posición no consecutiva (p. ej. posiciones 1 y 3 sin 2) se documenta tal cual, sin posiciones inventadas.
- [ ] Se prueba el review con servicios `OK`, `WARNING` y `ERROR`.
- [ ] Se prueba el review con estado `OMITIDO` para un servicio de `serviciosIgnorados`.
- [ ] Se prueba que `Cargar-IndiceMultiXPZ` descubre el complemento `<base>_1.xpz` del XPZ configurado.
- [ ] Se prueba que un objeto presente solo en el complemento `_1.xpz` se resuelve en el índice unificado.
- [ ] Se prueba que ante FQN (o guid) duplicado entre XPZ principal y complemento, gana el primer XPZ.
- [ ] Se prueba el tipo no resuelto como error.
- [ ] Se prueba la expansión de SDT anidado de entrada y salida.
- [ ] Se prueba la ausencia de SDT con nombre registrado.
- [ ] Se prueba un ciclo SDT con ruta registrada.
- [ ] Se prueba una llamada HTTP multilínea.
- [ ] Se prueba que las condiciones GeneXus no aparecen en Markdown.
- [ ] Se valida en los Markdown de `documentacion/servicios/` el orden canónico de secciones (Definición → Generalidades → Entrada → Salida exitosa → Errores específicos) sin secciones extra entre `Salida exitosa` y `Errores específicos`.
- [ ] Se valida que los Markdown no contienen comentarios HTML (`<!-- ... -->`) ni filas de ejemplo de la plantilla.
- [ ] Se valida que los Markdown conservan el JSON común bajo `Errores específicos` con las claves exactas `status`, `Description`, `detail` (en minúscula) y `JsonResult`.
- [ ] Se valida que los bloques canónicos son literales: autenticación `Authorization: Basic {Base64(usuario:contraseña)}` y tabla completa de Códigos HTTP comunes (200, 400, 401, 500, 501, 503).
- [ ] Se valida que `Obligatorio` usa solo `SI` o `NO`.
- [ ] Se valida que los tipos usan la tipografía canónica (`Integer (n)`, `Decimal (n, n)`, `String (n)`, `LongVarchar`, `Boolean`, `Date (YYYY-MM-DD)`, `DateTime`, `Base64`, `Estructura X`, `Colección de Estructura X`, `Colección JSON`) y no aparecen `Texto`, `Numérico` ni `Objeto JSON`.
- [ ] Se valida que las fechas usan `YYYY-MM-DD` y no aparecen GUID, XML, nombres internos de SDT ni credenciales.
- [ ] Se valida la coherencia de `Entrada` con el método: un GET muestra la frase de posiciones y la tabla con columna `Posición`; un POST muestra parámetros/estructuras y nunca ambas variantes.
- [ ] Se valida que `Errores específicos` muestra solo rechazos HTTP explícitos o el texto estándar, y que `Salida exitosa` es coherente (`Colección: SI/NO`, mensaje(s) o variante definida).
- [ ] Se valida que el nombre de archivo `<wrapper>.md` corresponde al último segmento del FQN del inventario en minúsculas.
- [ ] Se valida estáticamente el escape HTML y JSON del visor en `documentacion/Endpoints/web/`.
- [ ] Se valida estáticamente filtro, foco, ARIA y móvil del visor.
- [ ] La ausencia de Node.js no afecta la ejecución porque no se utiliza.

## Decisiones

- **Sí:** carpeta singular `test/` para script, fixtures, temporales y logs.
- **Sí:** harness propio compatible con PowerShell 5.1.
- **Sí:** cubrir las posiciones GET verificando que el Markdown documenta exactamente las posiciones del programa principal, en orden ascendente.
- **Sí:** cubrir multi-XPZ en esta spec mediante fixtures sintéticos de complementos, sin tocar los XPZ reales de `xpz/`.
- **Sí:** cubrir el estado `OMITIDO` del review del pipeline.
- **Sí:** pruebas estáticas del visor sin Node.js ni navegador automatizado.
- **Sí:** validar estáticamente los Markdown de `documentacion/servicios/` contra `templateDoc.md` y `reglasEditoriales.md` sin regenerar documentos.
- **Sí:** limpiar temporales siempre y conservar detalles en el log.
- **Sí:** separar logs de prueba de logs productivos.
- **Sí:** apuntar las rutas del visor a `documentacion/Endpoints/web/` e inventario a `documentacion/Endpoints/assets/`.
- **Sí:** actualizar la cabecera con la nota de actualización sin cambiar dependencias.
- **No:** cubrir `ValidarXPZ.ps1`, la exportación selectiva ni el lanzador unificado en esta spec.
- **No:** probar todo el XPZ en cada ejecución.
- **No:** probar servicios desplegados o credenciales.
- **No:** modificar salidas reales durante los tests.
- **No:** regenerar los Markdown durante la validación; las pruebas son estáticas sobre los documentos existentes en `documentacion/servicios/`.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Un fixture no representa el XPZ real | Basar fixtures en fragmentos observados de los XPZ de `xpz/` (patrón `SEGUROS_COMERCIAL_APIGLM_*`). |
| Un complemento sintético no reproduce la cascada real | Derivar el fixture `_1.xpz` de la estructura real de un objeto exportado aparte. |
| Un fallo deja temporales bloqueados | Limpiar en `finally` y registrar el fallo de limpieza. |
| La validación estática no detecta un fallo visual | Complementar con las muestras manuales de SPEC 07. |
| Un Markdown de `documentacion/servicios/` no existe aún (carpeta vacía) | Las validaciones estáticas marcan SKIP si no hay documentos y el resto de los casos sigue corriendo. |
| Un Markdown con edición manual legítima incumple una regla editorial | Las validaciones son informativas de regresión; no modifican el archivo y el detalle queda en el log. |

## Lo que **no** incluye esta spec

- Node.js, navegador automatizado o Pester.
- Pruebas contra servicios reales.
- Regeneración masiva de documentos.
- Escritura en salidas productivas.
- ValidarXPZ.ps1, exportación selectiva ni lanzador unificado.
- Commit en git.
