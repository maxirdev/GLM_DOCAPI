# SPEC 01 — Documentación técnica del servicio APIGLM.Emision.WSObtenerTotalesSolicitud

> **Estado:** Implementado
> **Depende de:** —
> **Fecha:** 2026-08-07
> **Objetivo:** Producir la documentación pública del servicio `APIGLM.Emision.WSObtenerTotalesSolicitud` en `documentacion/servicios/wsobtenertotalessolicitud.md` siguiendo el orden `analisisXPZ.md` → `reglasEditoriales.md` → `templateDoc.md`.

## Alcance

**Incluido:**

- Análisis del wrapper `APIGLM.Emision.WSObtenerTotalesSolicitud` (confirmado `IsMain=True`, `CALL_PROTOCOL=HTTP`) y del programa principal `APIGLM.Emision.ObtenerTotalesSolicitud` en `xpz/LPS_COM.xpz`, conforme a `normativas/analisisXPZ.md`.
- Aplicación de `normativas/reglasEditoriales.md`.
- Generación del documento final `documentacion/servicios/wsobtenertotalessolicitud.md` conforme a `normativas/templateDoc.md`.
- Registro de `PENDIENTE DE CONFIRMACIÓN: <dato>. Evidencia requerida: <fuente>.` cuando una evidencia no pueda confirmarse en el XPZ.
- Verificación contra las tres listas de control normativas.

**Excluido (para specs futuros):**

- Creación del inventario `Endpoints/endpoints.md` con los 135 endpoints.
- Documentación de cualquier otro servicio del catálogo.
- Conservar la documentación técnica interna intermedia como entregable (es material de trabajo del análisis).
- Commit en git.
- Corrección de referencias a `../recursos/LPS_COM_v01.xpz` ni de la convención `Endpoint/` del README.

## Modelo de datos

Esta spec no introduce estructuras de datos de código. El entregable es un documento Markdown cuya estructura es la plantilla obligatoria de `normativas/templateDoc.md`, guardado en `documentacion/servicios/wsobtenertotalessolicitud.md` (nombre GeneXus del wrapper en minúsculas).

## Plan de implementación

1. Abrir el XPZ como ZIP de solo lectura y localizar `APIGLM.Emision.WSObtenerTotalesSolicitud`; confirmar tipo Procedure, `IsMain=True`, `CALL_PROTOCOL=HTTP` y llamada activa (sin `//`) en `APIGLMMain`.
2. Localizar en el Source del wrapper la delegación única a `ObtenerTotalesSolicitud(in:&APIGLMRequestIn, out:&APIGLMResponse)` y confirmar la firma en la regla `parm(...)` del programa principal. Si no hay delegación única, detener.
3. Resolver el método desde el programa principal: GET por posiciones de `QueryParams` o POST por `FromJson` sobre `Body`, y documentar la entrada (sección 2 de `analisisXPZ.md`).
4. Expandir estructuras compuestas y resolver tipos con la tipografía canónica (sección 3).
5. Calcular la columna `Obligatorio` con el criterio de la sección 4.
6. Resolver la salida satisfactoria (sección 5).
7. Extraer errores HTTP explícitos: únicamente llamadas a `GenerarAPIGLMResponse` con código ≠ 200 en el programa principal (sección 6).
8. Confirmar el endpoint publicado `ar.com.glmsa.seguros.comercial.apiglm.emision.awsobtenertotalessolicitud` (packagename constante de `configuracion.json` + FQN en minúsculas con prefijo `a` para Procedures HTTP `Main`).
9. Preparar la documentación técnica interna del análisis (sección «Documentación técnica interna»).
10. Redactar `documentacion/servicios/wsobtenertotalessolicitud.md` trasladando la documentación sin recalcular, conservando bloques canónicos y el JSON común.
11. Verificar contra las tres listas de control; registrar cada dato no confirmado como pendiente con su evidencia requerida.

## Criterios de aceptación

- [ ] Existe `documentacion/servicios/wsobtenertotalessolicitud.md`.
- [ ] El documento respeta el orden exacto de `templateDoc.md` y conserva solo la variante GET o POST aplicable.
- [ ] El campo Endpoint es `ar.com.glmsa.seguros.comercial.apiglm.emision.awsobtenertotalessolicitud`.
- [ ] El método HTTP está confirmado desde el programa principal.
- [ ] La entrada documenta solo posiciones confirmadas de `QueryParams` o la estructura completa de `FromJson`.
- [ ] Los tipos usan exclusivamente la tipografía canónica.
- [ ] La columna `Obligatorio` contiene solo `SI` o `NO`.
- [ ] La salida indica si es colección y enumera sus campos con tipos y descripciones.
- [ ] `Errores específicos` contiene solo rechazos explícitos del programa principal o la indicación estándar; el JSON común permanece debajo.
- [ ] Autenticación y tabla de Generalidades conservadas literalmente.
- [ ] No hay GUID, nombres internos de SDT, credenciales ni detalles de implementación.
- [ ] Cada dato no confirmado aparece como `PENDIENTE DE CONFIRMACIÓN` con su evidencia requerida.
- [ ] No se creó commit en git.

## Decisiones

- **Sí:** Entregable único: documento público en `documentacion/servicios/wsobtenertotalessolicitud.md`. La documentación interna intermedia no se conserva.
- **Sí:** Nombre de archivo `wsobtenertotalessolicitud.md` (wrapper en minúsculas). Se acepta el riesgo de colisión con un WS homónimo de otro módulo; se migrará a FQN normalizado si ocurre.
- **Sí:** El campo Endpoint documenta el nombre completo publicado (package + módulo + procedimiento), en minúsculas, compuesto por el packagename constante de `configuracion.json`; no se construye por analogía.
- **Sí:** Ante evidencia insuficiente, registrar `PENDIENTE DE CONFIRMACIÓN` y continuar (regla de `AGENTS.md`). Nunca inferir por analogía.
- **Sí:** No crear commit; lo decide el usuario.
- **No:** Crear `Endpoints/endpoints.md`. Tarea de alcance distinto, spec futuro.
- **No:** Documentar otros servicios del catálogo.
- **No:** Corregir referencias del README o de `analisisEndpoint.md` (`Endpoint/` singular, rutas `../recursos/`).

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Evidencia insuficiente en el XPZ (SDT no localizado, ciclo, entrada no resoluble) | Registrar pendiente con la evidencia requerida; detener solo la rama afectada y continuar con el resto. |
| Packagename no confirmado desde el XPZ | Constante única definida en `configuracion.json` según el XPZ; nunca construir el prefijo por analogía. |
| Colisión futura del nombre de archivo con un WS homónimo de otro módulo | Migrar el archivo a `apiglm-<modulo>-wsobtenertotalessolicitud.md` si ocurre. |
| Discrepancia `Length` vs `AttMaxLen` en tipos textuales | Usar `String` sin dimensión, sin registrar pendiente (regla ya establecida). |

## Lo que **no** incluye esta spec

- Inventario `Endpoints/endpoints.md`.
- Documentación de otros servicios.
- Commit en git.
- Cambios en README ni en referencias a rutas.
