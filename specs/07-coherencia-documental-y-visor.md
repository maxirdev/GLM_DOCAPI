# SPEC 07 — Coherencia documental y robustez del visor

> **Estado:** Borrador
> **Depende de:** SPEC 05, SPEC 06
> **Fecha:** 2026-08-09
> **Objetivo:** Alinear las normas y salidas documentales con el pipeline real y mejorar la seguridad, accesibilidad, rendimiento y adaptación móvil del visor de endpoints.

## Alcance

**Incluido:**

- Renombrar `documentacion/Endpoints/assets/--analisisEndpoint.md--` a `analisisEndpoint.md`.
- Corregir referencias al XPZ de `configuracion.json` y eliminar referencias a `LPS_COM_v01.xpz`.
- Actualizar README, AGENTS y la tabla de specs para reflejar SPEC 05 a SPEC 09.
- Reconciliar las reglas de tipos sin longitud confirmada.
- Reconciliar los errores específicos sin condición GeneXus publicada.
- Documentar estados y rutas reales de logs.
- Normalizar todos los Markdown existentes a UTF-8 sin BOM y LF sin cambiar su contenido.
- Corregir el generador para escribir `1 posición` y `N posiciones` en nuevas salidas.
- No corregir masivamente documentos existentes con el texto antiguo.
- Escapar valores dinámicos al generar HTML.
- Incrustar JSON sin permitir cierre prematuro del elemento `script`.
- Mejorar filtro, toggle, estado vacío, foco, etiquetas y adaptación móvil.
- Precalcular valores normalizados de búsqueda y usar `DocumentFragment`.
- Verificar manualmente tres servicios sin regenerar todo.

**Fuera de alcance:**

- Regeneración completa de documentos.
- Implementación del detector de cambios de SPEC 08.
- Implementación del harness de SPEC 09.
- Frameworks, CDN, servidor web o backend.
- Corrección semántica del analizador XPZ.

## Modelo de datos

El visor seguirá consumiendo `endpoints.json`, con un valor de búsqueda preparado por fila:

```js
{
  nombre: "WS - Ejemplo",
  descripcion: "WSEjemplo",
  busqueda: "ws - ejemplo wsejemplo"
}
```

No se introducen estructuras persistentes nuevas.

## Plan de implementación

1. Renombrar la guía de endpoints y actualizar sus fuentes y rutas.
2. Actualizar README, AGENTS y referencias de specs.
3. Ajustar reglas sobre tipos, códigos comunes, errores y pendientes.
4. Normalizar todos los `.md` sin cambiar contenido salvo BOM y finales de línea.
5. Corregir la pluralización de posiciones en `RedactarDocumento.ps1`.
6. Añadir escape HTML y escape seguro del JSON en `GenerarVistaHTML.ps1`.
7. Modificar `app.js` para validar datos, precalcular búsqueda, usar `DocumentFragment` y manejar inventarios vacíos.
8. Mejorar ARIA, foco, texto del botón de tema y mensajes de resultados.
9. Ajustar `style.css` para tabla desplazable, columnas legibles y controles móviles.
10. Verificar `WSEjemplo`, `WSValidarDatosDeVehiculo` y `WSObtenerDetallePoliza` sin regenerar todo.

## Criterios de aceptación

- [ ] Existe `documentacion/Endpoints/assets/analisisEndpoint.md` con referencias válidas.
- [ ] No quedan referencias activas a `LPS_COM_v01.xpz`.
- [ ] README y AGENTS describen rutas y specs reales.
- [ ] Las reglas no exigen publicar condiciones GeneXus.
- [ ] Las reglas permiten `Integer` y `String` sin dimensión con tipo base confirmado.
- [ ] Todos los `.md` son UTF-8 sin BOM y LF.
- [ ] El generador escribe `1 posición` para una y `N posiciones` para varias.
- [ ] No se modifican masivamente los documentos antiguos.
- [ ] `cliente` y títulos se insertan con escape HTML.
- [ ] El JSON incrustado no puede cerrar prematuramente el script.
- [ ] El filtro ignora mayúsculas y acentos.
- [ ] El visor maneja inventario vacío sin excepción no controlada.
- [ ] Filtro y toggle son utilizables con teclado y tienen foco visible.
- [ ] La tabla no rompe el ancho móvil.
- [ ] La búsqueda usa valores normalizados precalculados.
- [ ] El renderizado usa `DocumentFragment` o equivalente.
- [ ] Las tres muestras manuales se visualizan correctamente.

## Decisiones

- **Sí:** conservar la tabla de códigos comunes actual.
- **Sí:** mostrar códigos adicionales solo en Errores específicos.
- **Sí:** normalizar formato sin alterar contenido.
- **Sí:** mejorar seguridad, accesibilidad, móvil y rendimiento.
- **No:** regenerar 208 documentos.
- **No:** corregir masivamente `1 posiciones` existente.
- **No:** introducir frameworks o dependencias web.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Escapado doble de una descripción | Escapar solo en el límite HTML y conservar original en JSON. |
| JSON que rompe `script` | Reemplazar de forma insensible a mayúsculas la secuencia de cierre. |
| Tabla ilegible en móvil | Usar contenedor desplazable y encabezados claros. |
| Normalización altera contenido | Comparar antes y después salvo BOM y finales de línea. |

## Lo que **no** incluye esta spec

- Regenerar todo el inventario documental.
- Implementar checksums o detección incremental.
- Implementar SPEC 08.
- Añadir Node.js, frameworks o servidor.
- Commit en git.
