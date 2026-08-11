# SPEC 05 — Integridad del pipeline de generación

> **Estado:** Implementado
> **Depende de:** SPEC 04
> **Fecha:** 2026-08-09
> **Objetivo:** Hacer que el pipeline de inventario y documentos use una configuración única, evite sobrescrituras silenciosas y comunique de forma confiable los resultados parciales.

## Motivo

El pipeline actual puede seleccionar un XPZ distinto del configurado, volver a parsear el mismo archivo para cada servicio, sobrescribir documentos con nombres locales iguales y finalizar con un mensaje exitoso aunque existan fallos.

## Alcance

**Incluido:**

- Usar `configuracion.json` como XPZ predeterminado.
- Permitir `-XpzPath` como override explícito.
- Abrir y parsear el XPZ una sola vez por lote.
- Reutilizar índices de objetos, FQN, nombres, tipos y SDT.
- Detectar wrappers con nombre local duplicado de forma determinista.
- Hacer que el primer endpoint de `endpoints.json` gane; los siguientes se omiten como `WARNING`.
- Mantener el documento ganador ante un warning de duplicado.
- Usar estados `OK`, `WARNING` y `ERROR` por servicio.
- Eliminar el documento previo solo cuando un servicio seleccionado termina en `ERROR`.
- Continuar el lote después de un error.
- Devolver código 1 cuando existe un error real.
- Mostrar resumen amarillo cuando el lote termina con errores.
- Guardar logs históricos en `documentacion/Generador/Logs/`.
- Crear un JSON review agregado por ejecución con todos los servicios seleccionados.
- Crear un TXT de errores y warnings cuando existan.
- Actualizar los archivos CMD para preservar códigos de salida.

**Fuera de alcance:**

- Checksums transitivos y detección de cambios, tratados en SPEC 08.
- Corrección semántica del analizador, tratada en SPEC 06.
- Regeneración completa de los documentos existentes.
- Commit en git.

## Modelo de datos

El review se guarda como `documentacion/Generador/Logs/yyyyMMdd-HHmmss-review.json`:

```json
{
  "ejecucion": {
    "xpz": "xpz/trunk.xpz",
    "inicio": "2026-08-09T12:00:00",
    "fin": "2026-08-09T12:01:00",
    "seleccionados": 3,
    "ok": 1,
    "warning": 1,
    "error": 1
  },
  "servicios": [
    {
      "fullyQualifiedName": "APIGLM.Comun.WSEjemplo",
      "estado": "OK",
      "documento": "documentacion/servicios/wsejemplo.md",
      "pendientes": [],
      "mensajes": []
    }
  ]
}
```

El TXT se guarda como `documentacion/Generador/Logs/yyyyMMdd-HHmmss-errores.txt`. Las ejecuciones dentro del mismo segundo pueden sobrescribir el mismo nombre.

## Plan de implementación

1. Centralizar la carga de configuración y resolver las rutas relativas a la raíz.
2. Agregar `-XpzPath` a los scripts que abren el XPZ y eliminar la selección manual implícita.
3. Crear una apertura única que devuelva XML, ruta y nombre del XPZ.
4. Crear índices una sola vez y pasarlos a las funciones de análisis.
5. Detectar duplicados antes de procesar. El primero gana por orden del inventario.
6. Separar cada resultado en `OK`, `WARNING` o `ERROR` sin detener el lote.
7. Eliminar el documento previo solo del servicio seleccionado que terminó en `ERROR`.
8. Escribir review y TXT en `documentacion/Generador/Logs/`.
9. Devolver código 1 ante errores reales y código 0 cuando solo haya éxitos o warnings.
10. Ajustar `GenerarDocumentacion.cmd`, `GenerarDocumentoServicio.cmd`, `ObtenerEndpoints.cmd` y `ObtenerDocumento.cmd`.

## Criterios de aceptación

- [ ] Sin parámetros, el inventario usa exactamente el XPZ de `configuracion.json`.
- [ ] `-XpzPath` permite usar otro XPZ sin modificar la configuración.
- [ ] El package usado corresponde al XPZ seleccionado.
- [ ] El XML se abre una sola vez por lote.
- [ ] Los índices se construyen una sola vez y se reutilizan.
- [ ] Los wrappers duplicados se resuelven según el orden del inventario.
- [ ] El duplicado posterior queda como `WARNING` y no sobrescribe el documento ganador.
- [ ] Un servicio con `ERROR` elimina su documento previo únicamente si fue seleccionado.
- [ ] Un error no detiene los servicios siguientes.
- [ ] El review contiene todos los servicios seleccionados y sus estados.
- [ ] El TXT solo se crea cuando existen warnings o errores.
- [ ] Los logs se guardan en `documentacion/Generador/Logs/`.
- [ ] Un lote con errores muestra resumen amarillo y devuelve código 1.
- [ ] Un lote sin errores reales devuelve código 0.
- [ ] Los CMD preservan el código de salida de PowerShell.
- [ ] Ningún resultado fallido se presenta como generado correctamente.

## Decisiones

- **Sí:** configuración más override explícito para evitar mezclar XPZ y `packagename`.
- **Sí:** una apertura del XPZ por lote para reducir tiempo.
- **Sí:** primer duplicado según el orden del inventario.
- **Sí:** conservar éxitos aunque existan errores.
- **Sí:** eliminar el documento del servicio fallido seleccionado.
- **Sí:** logs históricos por ejecución.
- **No:** crear subcarpetas para separar wrappers duplicados.
- **No:** resolver duplicados por semejanza.
- **No:** convertir warnings en errores del lote.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Se selecciona un XPZ de otro cliente | Mostrar XPZ y `packagename` antes del proceso. |
| Un documento fallido permanece disponible | Eliminarlo y registrar el motivo inmediatamente. |
| Dos ejecuciones usan el mismo nombre de log | Mantener el comportamiento definido y documentarlo. |

## Lo que **no** incluye esta spec

- Checksums transitivos, árboles e historial de versiones.
- Corrección de tipos, SDT o llamadas multilínea.
- Rediseño del visor.
- Pruebas automatizadas de SPEC 09.
- Commit en git.
