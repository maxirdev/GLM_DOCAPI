# SPEC 06 — Analizador XPZ de contratos completos

> **Estado:** Implementado
> **Depende de:** SPEC 05
> **Fecha:** 2026-08-09
> **Objetivo:** Hacer que el analizador publique documentación solo cuando pueda confirmar tipos, salida y estructuras SDT completas, registrando con precisión los servicios que no puede resolver.

## Motivo

El analizador actual puede inferir tipos por heurística, omitir llamadas multilínea, resolver solo el primer nivel de salida y producir documentos con salida vacía o tipos pendientes.

## Alcance

**Incluido:**

- Cambios en `documentacion/Generador/binary/AnalizarServicio.ps1`.
- Cambios en `RedactarDocumento.ps1` y `EscribirSalidas.ps1` para transportar estructuras de salida y estados.
- Reconocimiento de llamadas HTTP y `FromJson` multilínea manteniendo la estrategia de expresiones regulares.
- Resolución estricta mediante `ATTCUSTOMTYPE`, `idBasedOn`, SDT, Domain y Attribute.
- Permitir `Integer` y `String` sin dimensión cuando el tipo base esté confirmado.
- Eliminar inferencias basadas exclusivamente en `ATT_PICTURE`, longitud o nombre.
- Expansión recursiva de SDT de entrada y salida.
- Detección de ciclos y referencias faltantes.
- Fallo del servicio cuando falta un tipo, salida o SDT necesario.
- `WARNING` cuando falta únicamente una descripción funcional.
- Mantener `SI`/`NO` según referencias o asignaciones del programa principal.
- Mantener la excepción normativa de `EmpCod`.
- Conservar en Generalidades solo `200`, `400`, `401`, `500`, `501` y `503`.
- Mostrar códigos adicionales exclusivamente en `Errores específicos`.
- No publicar la condición GeneXus de un error.

**Fuera de alcance:**

- Seguir Procedures auxiliares llamados por el programa principal.
- Construir un parser completo de GeneXus.
- Inferir contratos por analogía.
- Resolver evidencia externa no presente en el XPZ.

## Modelo de datos

```text
Documentacion
├── Entrada
├── EstructurasEntrada[]
├── Salida
├── EstructurasSalida[]
├── Errores[]
├── Pendientes[]
└── Estado: OK | WARNING | ERROR
```

Cada estructura contiene `RutaJson`, `EsColeccion` e hijos directos. La salida debe tener una tabla propia por cada estructura referenciada.

## Plan de implementación

1. Crear una utilidad que extraiga spans de llamadas balanceando paréntesis y uniendo líneas continuadas.
2. Aplicarla a `GenerarAPIGLMResponse`, `FromJson` y respuestas `HttpCode.OK`.
3. Eliminar inferencias por `ATT_PICTURE` o longitud aislada. Si no se confirma el tipo, producir error con servicio y campo.
4. Indexar Domains y Attributes por identidad y módulo para resolver `idBasedOn` sin ambigüedad.
5. Expandir recursivamente SDT de entrada y salida con GUID visitados y ruta JSON.
6. Si falta un SDT o existe un ciclo, registrar el nombre y la ruta y fallar el servicio.
7. Añadir `EstructurasSalida` y redactar un bloque `Estructura de <ruta>` por cada estructura.
8. Mantener en errores solo código y mensaje, sin publicar condiciones GeneXus.
9. Conservar la tabla canónica de Generalidades y colocar códigos adicionales solo en Errores específicos.
10. Calcular obligatoriedad por referencia del campo en el programa principal sin mezclar campos homónimos.
11. Propagar estados: descripción ausente es `WARNING`; tipo, salida o SDT ausente es `ERROR`.

## Criterios de aceptación

- [ ] Se detectan llamadas `GenerarAPIGLMResponse` multilínea.
- [ ] Se detectan respuestas `HttpCode.OK` multilínea.
- [ ] Se detectan `FromJson` multilínea.
- [ ] Un tipo sin evidencia suficiente produce `ERROR` y no genera documentación.
- [ ] `Integer` y `String` sin longitud se aceptan con tipo base confirmado.
- [ ] `ATT_PICTURE`, longitud aislada y nombre no bastan para inferir tipo.
- [ ] Los SDT anidados de entrada se documentan por ruta JSON.
- [ ] Los SDT anidados de salida se documentan por ruta JSON.
- [ ] La fila de una estructura indica si es colección.
- [ ] Un SDT ausente registra su nombre y produce `ERROR`.
- [ ] Un ciclo SDT registra su ruta y produce `ERROR`.
- [ ] Un error SDT elimina el documento previo del servicio seleccionado.
- [ ] Una descripción ausente produce documentación `WARNING` con pendiente.
- [ ] Se conserva el criterio actual de obligatoriedad.
- [ ] Los campos homónimos no comparten obligatoriedad accidentalmente.
- [ ] Generalidades conserva los seis códigos actuales.
- [ ] 404, 405 y otros códigos aparecen solo en Errores específicos.
- [ ] Las condiciones internas no se publican.
- [ ] Una salida no resuelta produce `ERROR`.
- [ ] No se siguen Procedures auxiliares fuera del programa principal.

## Decisiones

- **Sí:** regex con reconocimiento de spans multilínea.
- **Sí:** fallar ante tipo, salida o SDT no resuelto.
- **Sí:** advertir ante descripción faltante.
- **Sí:** estructuras de entrada y salida por rutas JSON.
- **Sí:** conservar la norma actual de obligatoriedad.
- **No:** publicar condiciones GeneXus.
- **No:** inferir tipos por nombre, longitud aislada o `ATT_PICTURE`.
- **No:** recorrer Procedures auxiliares.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Paréntesis dentro de literales | Reconocer literales antes de balancear. |
| SDT ambiguo | Resolver por módulo, tipo y FQN; fallar si persiste la ambigüedad. |
| Ciclo SDT | Mantener GUID visitados y registrar la ruta. |

## Lo que **no** incluye esta spec

- Detección de cambios entre XPZ, tratada en SPEC 08.
- Pruebas automatizadas, tratadas en SPEC 09.
- Rediseño del visor.
- Dependencias de Procedures auxiliares.
- Commit en git.
