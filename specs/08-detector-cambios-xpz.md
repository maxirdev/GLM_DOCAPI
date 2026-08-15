# SPEC 08 — Actualización de servicios por cambios en el XPZ

> **Estado:** Aprobado
> **Depende de:** SPEC 05, SPEC 06, SPEC 09, SPEC 11, SPEC 12, SPEC 13, SPEC 14
> **Fecha:** 2026-08-09
> **Revisado:** 2026-08-14
> **Objetivo:** Detectar los servicios cuya documentación cambió entre versiones del XPZ (principal + complementos), regenerar únicamente esos Markdown y PDF, y conservar un historial local simple de versiones sin agregar configuración ni pasos manuales.

## Motivo

El checksum del wrapper no cubre los cambios de los SDT, dominios, atributos y procedures auxiliares que forman la evidencia documentada. Comparar el XPZ completo por SHA forzaría a regenerar todo. El detector debe:

- comparar la **evidencia real** que utiliza `AnalizarServicio.ps1`, no un árbol teórico;
- identificar los **servicios dependientes** de los objetos modificados;
- validar contra el **Markdown resultante** para no regenerar cuando el cambio no altera el documento;
- integrarse en el circuito automático existente de la opción 1 del lanzador.

## Alcance

**Incluido:**

- Estado local `estado/controlVersiones.json`, ignorado por Git, por cliente y XPZ seleccionado.
- Comparación del **conjunto multi-XPZ** efectivo: principal + complementos `<base>_<N>.xpz` en orden de cascada.
- Checksum nativo de Procedure, SDT, Domain y Attribute cuando exista, y SHA256 semántico como respaldo (p. ej. dominios sin checksum).
- Índice inverso `objeto → servicios dependientes` para filtrar candidatos sin analizar todo.
- Trazabilidad opcional de evidencia en el analizador: programa principal, salida delegada, procedures alcanzables que aportan tipos u obligatoriedad.
- Validación final por **hash del Markdown generado en memoria**: solo se regenera cuando el documento cambia realmente.
- Detección de servicios modificados, nuevos, eliminados y pendientes.
- Detección de cambios del perfil documental (`packagename`, normas, plantilla y scripts relevantes de análisis/redacción).
- Versionado local simple por servicio: `1.0`, `1.1`, ..., `1.10`.
- Regeneración selectiva de Markdown y de PDF, con conservación del PDF vigente ante fallos.
- Actualización atómica de `estado/controlVersiones.json` una sola vez al finalizar.
- Opción 1 dinámica del lanzador: sin documentos previos exporta y genera todo; con PDF previos actúa como **Buscar actualización de servicios**.
- Inicialización automática del baseline en la primera generación completa.

**Fuera de alcance:**

- Grafo visual SVG, diagrama ni grafo individual bajo demanda.
- Commit en git.
- Control de ediciones manuales del Markdown mediante checksum del documento.
- Regeneración total automática de todos los documentos.
- Historial por versión de objeto (snapshots históricos completos).
- Cambios de presentación del PDF que no alteran el Markdown (no incrementan versión del contrato).

## Modelo de datos

Ubicación: `estado/controlVersiones.json`. El directorio `estado/` queda ignorado por Git.

```json
{
  "schemaVersion": 1,
  "lineageId": "d6e85f10-28f3-409e-afb1-4b38c19fc8af",
  "sourceFingerprint": "...",
  "profileFingerprint": "...",
  "objects": {
    "SDT:dca39cb3-d310-4b8d-acae-ffd19ce1e59d": "f26174dacc7afdcd7b3492a42daa1f37",
    "Procedure:142f76e8-6ea2-4d21-befb-f1f871d20ee6": "270fd77ba6287e47dc6e5f9bc1963bff"
  },
  "services": {
    "APIGLM.Comun.WSListarCaracterAbogado": {
      "wrapperGuid": "...",
      "revision": 1,
      "version": "1.1",
      "documentHash": "...",
      "dependencies": [
        "Procedure:...",
        "SDT:dca39cb3-d310-4b8d-acae-ffd19ce1e59d"
      ],
      "status": "ACTIVO"
    }
  }
}
```

- `lineageId` es el GUID de `APIGLM.APIGLMMain`. Si cambia, la comparación se bloquea y se solicita inicialización explícita; no se interpretan todos los servicios como eliminados.
- `sourceFingerprint` cubre el conjunto ordenado principal + complementos: ruta relativa, orden de cascada y SHA256 de cada archivo.
- `profileFingerprint` cubre `packagename`, `analisisXPZ.md`, `reglasEditoriales.md`, `templateDoc.md` y los scripts de análisis, redacción, escritura y carga multi-XPZ.
- `objects` conserva solo el checksum del objeto efectivo tras la cascada. La clave es `Tipo:guid`.
- `services` conserva el estado por servicio: versión, hash del Markdown vigente y dependencias de evidencia.
- `version` es una etiqueta de presentación derivada de `revision`: `1.0` para `revision = 0`, `1.10` para `revision = 10`.

El control puede contener además un bloque `pendientes`:

```json
{
  "pendientes": {
    "APIGLM.Emision.WSConsultarSolicitud": {
      "baselineFingerprint": "...",
      "targetFingerprint": "...",
      "reason": "GENERATION_ERROR",
      "attempts": 1,
      "lastError": "..."
    }
  }
}
```

Los servicios en `pendientes` se reintentan en la siguiente ejecución aunque el SHA global coincida.

## Plan de implementación

1. Actualizar `CargarMultiXPZ.ps1` para exponer el manifiesto efectivo (ruta, orden, SHA256) y un índice inverso de objetos.
2. Agregar a `AnalizarServicio.ps1` una traza opcional de evidencia: nodos consultados, aristas de resolución y su motivo.
3. Crear `ControlVersiones.ps1` con carga, validación, comparación, incremento de versión y escritura atómica.
4. Agregar a `GenerarDocumento.ps1` un modo no interactivo que acepte una lista explícita de FQN y devuelva una ruta de review conocida.
5. Agregar a `GenerarPdfServicios.ps1` un modo que acepte una lista explícita de Markdown.
6. Hacer que `RenderizarMarkdownTypstPdf.ps1` genere el PDF en un temporal y reemplace el vigente solo tras el éxito.
7. Crear `ActualizarServicios.ps1` como orquestador de la actualización incremental.
8. Modificar `GenerarDocumentosGLM.cmd` para que la opción 1 detecte si existen PDF y elija el circuito correspondiente.
9. Implementar el fast-path: si coinciden `sourceFingerprint`, `profileFingerprint` y no hay pendientes, terminar sin abrir el XML.
10. Implementar el filtro por objetos: abrir y fusionar cada XPZ una sola vez, comparar checksums y obtener servicios dependientes del índice inverso.
11. Validar con Markdown en memoria los candidatos y regenerar solo los que cambian.
12. Actualizar versiones una sola vez por servicio y lote, y escribir `estado/controlVersiones.json` atómicamente al final.
13. Avanzar `sourceFingerprint` aunque existan fallos, conservando `pendientes`.
14. Verificar el escenario `mod.xpz + mod_1.xpz` frente al baseline actual: exactamente 3 servicios afectados.

## Criterios de aceptación

- [ ] El fast-path evita abrir el XML cuando coinciden conjunto XPZ, perfil y no hay pendientes.
- [ ] El fast-path no omite `pendientes` aunque el SHA global coincida.
- [ ] Un cambio de SDT compartido identifica todos los servicios dependientes.
- [ ] Procedure, SDT y Attribute usan checksum nativo cuando está presente.
- [ ] Los dominios sin checksum nativo usan SHA256 semántico.
- [ ] Un cambio solo en un complemento `_N.xpz` se detecta.
- [ ] Un complemento con ZIP distinto pero XML idéntico no genera versiones falsas.
- [ ] El objeto sombreado por un duplicado en un XPZ anterior no genera cambios.
- [ ] La evidencia de procedures auxiliares que aportan tipos u obligatoriedad participa de la comparación.
- [ ] Un cambio que no altera el Markdown resultante no incrementa la versión.
- [ ] El hash del Markdown normalizado confirma el cambio documental.
- [ ] La versión inicial es `1.0` y cada actualización documental incrementa una sola vez.
- [ ] Un `WARNING` con documento escrito promueve baseline y versión.
- [ ] Un `ERROR` conserva PDF, Markdown y versión anteriores y queda en `pendientes`.
- [ ] Un servicio nuevo generado correctamente inicia en `1.0`.
- [ ] Un servicio eliminado del inventario se marca sin borrar el PDF ni el Markdown.
- [ ] Un servicio ignorado no se trata como eliminado.
- [ ] El control se reemplaza atómicamente al final del lote.
- [ ] `estado/` está ignorado por Git y no recibe commits automáticos.
- [ ] La opción 1 del lanzador cambia de nombre según existan PDF previos.
- [ ] `mod.xpz + mod_1.xpz` frente al baseline actual afecta exactamente `WSListarCaracterAbogado`, `WSValidarClausulasDeSubrogacion` y `WSPermitirModificacionRecargoBonificacion`.
- [ ] La actualización regenera solo los Markdown y PDF afectados.
- [ ] El PDF vigente no se elimina antes de que el nuevo sea válido.

## Decisiones

- **Sí:** estado local `estado/controlVersiones.json` ignorado por Git.
- **Sí:** comparación del conjunto multi-XPZ, no de un XPZ singular.
- **Sí:** índice inverso `objeto → servicios` como filtro rápido.
- **Sí:** validación final por hash del Markdown generado en memoria.
- **Sí:** checksum nativo con SHA256 semántico de respaldo.
- **Sí:** evidencia de procedures auxiliares realmente usados por el analizador.
- **Sí:** versionado simple por servicio, sin snapshots históricos completos.
- **Sí:** integración en la opción 1 como **Buscar actualización de servicios**.
- **Sí:** inicialización automática del baseline en la primera generación.
- **Sí:** actualización atómica del control al final del lote.
- **No:** grafo visual ni exportación de grafo individual bajo demanda.
- **No:** commit en git.
- **No:** checksum del Markdown para controlar ediciones manuales.
- **No:** regeneración total automática de todos los documentos.
- **No:** snapshots históricos por versión de objeto.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Un checksum nativo cambia por metadata volátil | Comparar también el descriptor semántico y el Markdown resultante. |
| Un nodo carece de checksum | Calcular SHA256 semántico o bloquear el servicio si no puede calcularse. |
| Un SDT compartido cambia | El índice inverso identifica todos los dependientes en una pasada. |
| Cambia solo el ZIP de un complemento sin cambio XML | El filtro semántico no genera versión ni regeneración. |
| Un cambio de procedure auxiliar altera obligatoriedad o salida | La traza de evidencia incluye los nodos efectivamente consultados. |
| El control maestro se corrompe | Escritura con temporal, validación y reemplazo atómico. |
| Aparece un ciclo SDT | La referencia recursiva se conserva como arista sin fallar el servicio. |
| Cambia el perfil documental | Cambia `profileFingerprint` y se marcan los servicios activos como impactados. |
| XPZ de otra KB o cliente | `lineageId` distinto bloquea la comparación y exige inicialización explícita. |
| Fallo parcial en el lote | El servicio conserva baseline y PDF anteriores y queda en `pendientes`. |

## Lo que **no** incluye esta spec

- Grafo SVG o diagrama.
- Exportación de grafo individual.
- Commit en git.
- Seguimiento de ediciones manuales del Markdown.
- Historial completo de snapshots por versión.
- Regeneración masiva automática de todos los documentos.
