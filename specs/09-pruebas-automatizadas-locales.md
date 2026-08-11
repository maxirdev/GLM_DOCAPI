# SPEC 09 — Pruebas locales del pipeline, analizador y visor

> **Estado:** Borrador
> **Depende de:** SPEC 05, SPEC 06, SPEC 07
> **Fecha:** 2026-08-09
> **Objetivo:** Crear un harness manual y sin dependencias externas que verifique las regresiones críticas del pipeline, analizador XPZ y visor sin modificar las salidas reales.

## Alcance

**Incluido:**

- Carpeta `test/`.
- Script manual `test/Run-Tests.ps1` compatible con PowerShell 5.1.
- Fixtures XML, JSON y XPZ mínimos en `test/fixtures/`.
- Temporales aislados en `test/tmp/`.
- Logs de pruebas en `test/Logs/`.
- Casos de pipeline, analizador y visor.
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

## Modelo de datos

Cada caso tendrá identificador, resultado y detalle en memoria:

```powershell
[pscustomobject]@{
    Id = 'pipeline.duplicados'
    Estado = 'PASS'
    Detalle = 'El primer wrapper gana y el segundo queda como warning.'
}
```

El log de pruebas será texto legible y separado de los logs productivos.

## Plan de implementación

1. Crear `test/Run-Tests.ps1` con funciones de aserción, registro de casos y limpieza en `finally`.
2. Crear fixtures XML para wrapper, programa principal, GET, POST, SDT anidado, tipo faltante, ciclo y llamada multilínea.
3. Crear fixtures JSON para inventario válido, duplicados y control de versiones mínimo.
4. Añadir casos de configuración, override, parseo único, duplicados, estados, borrado de documento fallido, review y código de salida.
5. Añadir casos de tipos, obligatoriedad, SDT de entrada/salida, ciclo, ausencia de SDT, llamadas multilínea y códigos HTTP.
6. Añadir validaciones estáticas del visor: escape HTML/JSON, referencias CSS/JS, atributos accesibles y adaptación móvil.
7. Ejecutar los casos en orden, escribir el TXT y devolver el código de salida.
8. Ejecutar manualmente el script en PowerShell 5.1 y revisar el log.

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
- [ ] Se prueba el review con servicios `OK`, `WARNING` y `ERROR`.
- [ ] Se prueba el tipo no resuelto como error.
- [ ] Se prueba la expansión de SDT anidado de entrada y salida.
- [ ] Se prueba la ausencia de SDT con nombre registrado.
- [ ] Se prueba un ciclo SDT con ruta registrada.
- [ ] Se prueba una llamada HTTP multilínea.
- [ ] Se prueba que las condiciones GeneXus no aparecen en Markdown.
- [ ] Se valida estáticamente el escape HTML y JSON del visor.
- [ ] Se valida estáticamente filtro, foco, ARIA y móvil.
- [ ] La ausencia de Node.js no afecta la ejecución porque no se utiliza.

## Decisiones

- **Sí:** carpeta singular `test/` para script, fixtures, temporales y logs.
- **Sí:** harness propio compatible con PowerShell 5.1.
- **Sí:** pruebas estáticas del visor sin Node.js ni navegador automatizado.
- **Sí:** limpiar temporales siempre y conservar detalles en el log.
- **Sí:** separar logs de prueba de logs productivos.
- **No:** probar todo el XPZ en cada ejecución.
- **No:** probar servicios desplegados o credenciales.
- **No:** modificar salidas reales durante los tests.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Un fixture no representa el XPZ real | Basar fixtures en fragmentos observados de `trunk.xpz`. |
| Un fallo deja temporales bloqueados | Limpiar en `finally` y registrar el fallo de limpieza. |
| La validación estática no detecta un fallo visual | Complementar con las muestras manuales de SPEC 07. |

## Lo que **no** incluye esta spec

- Node.js, navegador automatizado o Pester.
- Pruebas contra servicios reales.
- Regeneración masiva de documentos.
- Escritura en salidas productivas.
- Commit en git.
