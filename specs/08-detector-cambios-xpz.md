# SPEC 08 — Detector de cambios por árbol transitivo del XPZ

> **Estado:** Borrador
> **Depende de:** SPEC 05, SPEC 06
> **Fecha:** 2026-08-09
> **Objetivo:** Comparar la clausura transitiva del contrato de cada endpoint entre versiones del XPZ para regenerar únicamente los servicios afectados y conservar el historial explicable de cambios.

## Motivo

El checksum del wrapper no cubre por sí solo los cambios de los SDT, dominios y atributos que forman la entrada o la salida documentada. El detector debe comparar el árbol real de evidencia utilizado por el analizador, no únicamente el archivo XPZ completo ni el objeto wrapper.

## Alcance

**Incluido:**

- `documentacion/Generador/assets/controlVersiones.json` como registro global normalizado de snapshots de objetos, árboles por servicio, huellas compuestas, historial y tombstones.
- `DetectarCambios.ps1` para comparar el XPZ actual con el control maestro.
- `GenerarGrafoDependencias.ps1` para exportar bajo demanda el árbol de un endpoint.
- Clausura por endpoint: `APIGLMMain` → wrapper HTTP → programa principal delegado → SDT de entrada/salida → SDT anidados → Domain/Attribute.
- Checksum nativo de Procedure, SDT, Domain y Attribute cuando exista.
- SHA256 semántico como respaldo para nodos sin checksum nativo.
- Detección de endpoints modificados, nuevos, eliminados y duplicados omitidos.
- Detección de cambios del perfil documental: `packagename`, normas, plantilla y scripts de análisis/redacción.
- Regeneración bajo confirmación de los endpoints impactados, mostrando endpoint y nodos modificados.
- Actualización atómica de `controlVersiones.json` una vez finalizado el lote.
- Avance del SHA global aun con fallos parciales, conservando cambios pendientes para el siguiente intento.
- Opción 5 del menú para exportar un grafo JSON individual.
- Opción 6 del menú para detectar y regenerar servicios modificados.

**Fuera de alcance:**

- Grafo visual SVG o diagrama.
- Commit en git.
- Dependencias de Procedures auxiliares llamados por el programa principal.
- Control de ediciones manuales del Markdown mediante checksum del documento.
- Regeneración total automática de todos los documentos.

## Modelo de datos

```json
{
  "schemaVersion": 2,
  "xpzOrigen": "xpz/trunk.xpz",
  "checksumXpz": "e4a82c3f1b...",
  "profileChecksum": "a91d...",
  "pendingChanges": [],
  "snapshots": {
    "SDT:guid:checksum": {
      "tipo": "SDT",
      "guid": "...",
      "fullyQualifiedName": "APIGLM.Emision.SDT_Solicitud",
      "checksum": "...",
      "checksumSource": "native",
      "descriptor": {}
    }
  },
  "servicios": [
    {
      "fullyQualifiedName": "APIGLM.Emision.WSObtenerTotalesSolicitud",
      "endpoint": "glmsuit.comercial.emision.awsobtenertotalessolicitud",
      "guidWrapper": "...",
      "estado": "OK",
      "versionActual": "1.1",
      "fingerprintActual": "...",
      "snapshotActual": ["SDT:guid:checksum"],
      "aristasActuales": [],
      "historial": [
        {
          "version": "1.0",
          "descripcion": "Version Inicial",
          "fingerprint": "...",
          "snapshots": [],
          "aristas": [],
          "cambios": []
        },
        {
          "version": "1.1",
          "descripcion": "Se modificó la estructura RiesgoAUT",
          "fingerprint": "...",
          "snapshots": ["SDT:guid:checksum"],
          "aristas": [],
          "cambios": []
        }
      ]
    }
  ]
}
```

- `checksumXpz` es SHA256 del XPZ completo. El fast-path solo aplica si coincide, `profileChecksum` coincide y no existen pendientes.
- `profileChecksum` incluye `packagename`, `analisisXPZ.md`, `reglasEditoriales.md`, `templateDoc.md` y scripts relevantes de análisis/redacción.
- Cada snapshot se identifica por `tipo + guid + checksum` y se guarda una sola vez.
- `checksumSource` vale `native` o `semantic`.
- La versión es textual: `1.0`, `1.1`, ..., `1.10`.
- `historial` conserva todas las versiones y explica los nodos y aristas modificados.
- `pendingChanges` conserva el árbol objetivo de servicios que no pudieron regenerarse.

El árbol de un endpoint es:

```text
APIGLMMain
└── Wrapper HTTP
    └── Programa principal delegado
        ├── SDT de entrada
        │   └── SDT anidados
        │       └── Domain / Attribute
        └── SDT de salida
            └── SDT anidados
                └── Domain / Attribute
```

`APIGLMMain` delimita el inventario, pero su checksum no forma parte de la huella individual. No se siguen Procedures auxiliares llamados por el programa principal. `parentGuid` sirve para contexto jerárquico, no como única evidencia de dependencia funcional.

El XPZ local `trunk.xpz` mostró 593 Procedures, 457 SDT y 2.429 atributos raíz con checksum nativo. De 586 dominios, 574 tienen checksum nativo y 12 requieren checksum semántico de respaldo. La implementación debe conservar esta estrategia para otros XPZ.

**Grafo individual:** `documentacion/Generador/assets/grafo-<FQN-seguro>.json`:

```json
{
  "servicio": "APIGLM.Emision.WSObtenerTotalesSolicitud",
  "fingerprint": "...",
  "nodos": [
    {
      "fullyQualifiedName": "APIGLM.Emision.WSObtenerTotalesSolicitud",
      "tipo": "Procedure",
      "relacion": "wrapper",
      "checksumSource": "native"
    },
    {
      "fullyQualifiedName": "APIGLM.Emision.SDT_Solicitud",
      "tipo": "SDT",
      "relacion": "entrada",
      "checksumSource": "native"
    }
  ],
  "aristas": [
    {
      "desde": "APIGLM.APIGLMMain",
      "hacia": "APIGLM.Emision.WSObtenerTotalesSolicitud",
      "tipo": "inventario"
    },
    {
      "desde": "APIGLM.Emision.WSObtenerTotalesSolicitud",
      "hacia": "APIGLM.Emision.SDT_Solicitud",
      "tipo": "entrada"
    }
  ]
}
```

## Plan de implementación

1. Rediseñar `controlVersiones.json` con snapshots globales, servicios, historial, pendientes y `schemaVersion: 2`.
2. Crear índices por GUID, FQN, nombre, tipo e `idBasedOn`.
3. Calcular checksum nativo cuando exista y checksum semántico cuando falte, excluyendo `user`, `versionDate`, `lastUpdate` y `checksum` del fallback.
4. Construir el árbol desde `APIGLMMain` hasta wrapper, programa principal, entrada/salida y sus SDT, dominios y atributos.
5. Calcular la huella compuesta ordenando nodos y aristas de forma estable.
6. Generar descriptores para explicar cambios de Procedure, SDT, Domain, Attribute y aristas.
7. Comparar árboles y clasificar nodos agregados, eliminados, modificados y sin cambios.
8. Detectar altas y bajas del inventario. Un endpoint nuevo no recibe versión hasta generar OK. Un eliminado conserva tombstone.
9. Si un FQN reaparece con el mismo GUID, continuar su historial. Si reaparece con otro GUID, iniciar una línea en `1.0` y conservar el tombstone anterior.
10. Mostrar antes de regenerar el endpoint, estado y nodos cambiados. Regenerar solo modificados y pendientes confirmados.
11. Actualizar versión una sola vez por regeneración OK: `1.0` inicial, luego `1.1`, `1.2`, etc.
12. Escribir el control a un temporal y reemplazarlo una sola vez al finalizar. Los errores conservan el baseline y agregan `pendingChanges`.
13. Avanzar `checksumXpz` aunque existan fallos. El fast-path no debe omitir `pendingChanges`.
14. Crear la opción 5 para exportar un grafo individual y la opción 6 para detectar cambios.
15. Verificar con muestras sin regenerar todo: SDT compartido, dominio sin checksum nativo, fallo parcial y grafo individual.

## Criterios de aceptación

- [ ] El fast-path evita abrir el XML cuando coinciden XPZ, perfil y no hay pendientes.
- [ ] Un cambio de SDT compartido identifica todos los endpoints dependientes.
- [ ] Procedure, SDT y Attribute usan checksum nativo cuando está presente.
- [ ] Los dominios sin checksum nativo usan SHA256 semántico.
- [ ] La huella compuesta depende de nodos y aristas ordenados establemente.
- [ ] APIGLMMain aparece como raíz, pero su checksum no regenera todos los servicios.
- [ ] No se siguen Procedures auxiliares llamados por el programa principal.
- [ ] Un cambio de estructura explica campos, nodos o aristas agregados, eliminados o modificados.
- [ ] El control maestro conserva el historial completo de versiones.
- [ ] La versión inicial es `1.0` y cada regeneración OK incrementa una sola vez.
- [ ] El control se reemplaza atómicamente al final del lote.
- [ ] Un fallo conserva el baseline del servicio y registra un cambio pendiente.
- [ ] El SHA global avanza aun cuando existen fallos pendientes.
- [ ] El siguiente intento procesa pendientes aunque el SHA global coincida.
- [ ] Se detectan endpoints nuevos y eliminados.
- [ ] Las bajas conservan tombstone.
- [ ] Un FQN reactivado con el mismo GUID continúa su historial; con otro GUID inicia `1.0`.
- [ ] Los duplicados locales posteriores no se registran en el control maestro.
- [ ] El grafo individual usa un nombre derivado del FQN completo.
- [ ] Las opciones 5 y 6 producen las salidas descritas.

## Decisiones

- **Sí:** SHA256 global como fast-path, condicionado por perfil y pendientes.
- **Sí:** checksum nativo y checksum semántico de respaldo.
- **Sí:** árbol transitivo del contrato, no grafo indiscriminado de Procedures auxiliares.
- **Sí:** snapshots compartidos e historial completo por servicio.
- **Sí:** actualización atómica al final del lote.
- **Sí:** altas, bajas, reapariciones y tombstones.
- **Sí:** grafo individual bajo demanda.
- **No:** checksum del Markdown para controlar ediciones manuales.
- **No:** dependencia de Procedures auxiliares fuera del programa principal.
- **No:** regeneración total automática.
- **No:** commit en git.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Un checksum nativo cambia por metadata volátil | Comparar también descriptor semántico y registrar la diferencia. |
| Un nodo carece de checksum | Calcular SHA256 semántico o bloquear el servicio si no puede calcularse. |
| Un SDT compartido cambia durante un lote parcial | Conservar snapshots por tipo, GUID y checksum, baseline anterior y target pendiente. |
| El control maestro se corrompe | Escribir temporal y reemplazar atómicamente. |
| Aparece un ciclo SDT | Detectar GUID visitado, registrar ruta y fallar el servicio. |
| Cambia el perfil documental | Cambiar `profileChecksum` y marcar servicios documentados como impactados. |

## Lo que **no** incluye esta spec

- Grafo SVG o diagrama.
- Seguimiento de ediciones manuales del Markdown.
- Dependencias de Procedures auxiliares.
- Regeneración masiva automática.
- Commit en git.
