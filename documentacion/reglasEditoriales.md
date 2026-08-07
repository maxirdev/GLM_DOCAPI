# Reglas editoriales para documentar servicios APIGLM

Este documento es la segunda fuente normativa. Se aplica después de completar la ficha técnica definida en [analisisXPZ.md](analisisXPZ.md) y regula únicamente la presentación del documento final.

## Audiencia y contenido

Escribir en español claro para el desarrollador que consumirá el servicio.

No incluir:

- GUID, tipos de `Part`, nodos XML ni metadatos internos del XPZ.
- La cadena de procedimientos GeneXus utilizada durante el análisis.
- Nombres internos de SDT de entrada o salida.
- Configuración interna de la envoltura de respuesta.
- Suposiciones presentadas como hechos.
- Credenciales reales.
- Ejemplos inventados presentados como solicitudes o respuestas reales.

## Reglas de presentación

- Consumir la ficha técnica sin recalcular programa principal, método, entrada, tipos, obligatoriedad, salida, errores ni endpoint.
- No iniciar la redacción si la ficha no identifica un programa principal separado y único.
- Mantener nombres de campos y mensajes con su grafía real.
- Usar únicamente `SI` o `NO` en la columna `Obligatorio`.
- Conservar la tipografía canónica recibida desde el análisis.
- Usar `YYYY-MM-DD` para fechas.
- Escribir descripciones funcionales y omitir conversiones, variables auxiliares o llamadas internas.
- No inventar una descripción cuando la función del campo no esté confirmada.
- No agregar una fila pendiente para una variable ausente de la ficha.
- En la salida, indicar únicamente si es una colección y enumerar sus campos.

### Estructuras compuestas

- Mantener cada estructura en la tabla que la contiene con su tipo canónico.
- Agregar una tabla independiente con los hijos directos de cada estructura o colección compuesta.
- Identificarla mediante la ruta JSON completa, por ejemplo `Estructura de RiesgoAUT.AcreedorPrendario`.
- Usar en cada tabla solo los nombres directos de sus hijos; no mezclar niveles.

### Bloques canónicos

Copiar desde [templateDoc.md](templateDoc.md), sin reescribirlos, la autenticación, la tabla de códigos HTTP comunes y la estructura JSON común.

- Conservar literalmente `Authorization: Basic {Base64(usuario:contraseña)}`.
- Conservar el texto `Error interno de Servicio.` para el código 500.
- Mantener `detail` en minúscula.
- Mostrar siempre la tabla completa de Generalidades.
- Agregar los códigos adicionales recibidos en la ficha sin duplicados y en orden numérico.
- Si un código común también tiene condiciones explícitas, mantener una sola fila en Generalidades y detallar sus condiciones únicamente en `Errores específicos`.

Un campo funcional como `Usuario` o `UsuCod` no reemplaza la autenticación del encabezado.

### Errores específicos

Documentar únicamente los rechazos HTTP explícitos recibidos en la ficha técnica. No publicar comprobaciones funcionales ni errores contenidos en una respuesta HTTP 200.

Cuando existan errores explícitos:

- Crear una sola tabla con código HTTP, condición y mensaje literal o patrón.
- Repetir una fila por cada condición, aunque varias usen el mismo código.
- Conservar el texto fijo y los marcadores descriptivos de mensajes dinámicos, por ejemplo `Consulte Log. <número>`.

Cuando no existan, mostrar `No se identificaron errores específicos en el programa principal.`.

En ambos casos, conservar debajo la estructura JSON común.

Los marcadores `<Código HTTP>`, `<descripción general>` y `<detalle>` dentro de esa estructura son parte del contrato documental y permanecen en el documento final. No representan pendientes.

## Orden y limpieza

Respetar el orden definido por [templateDoc.md](templateDoc.md). No agregar secciones entre `Salida exitosa` y `Errores específicos`.

Reemplazar los demás marcadores editoriales entre `< >` con datos confirmados o con:

```text
PENDIENTE DE CONFIRMACIÓN: <dato faltante>. Evidencia requerida: <fuente necesaria>.
```

Los marcadores descriptivos dentro de mensajes dinámicos también deben conservarse.

Usar el endpoint relativo recibido en la ficha, en minúsculas. No reconstruir host, base URL, package ni endpoint por analogía.

## Lista de verificación editorial

- [ ] El documento respeta el orden de la plantilla.
- [ ] Método, endpoint, entrada y salida coinciden con la ficha técnica.
- [ ] La obligatoriedad usa solo `SI` o `NO`.
- [ ] Los tipos conservan la tipografía canónica.
- [ ] Las estructuras compuestas están separadas por ruta JSON.
- [ ] Las descripciones son funcionales y no técnicas.
- [ ] La autenticación y los códigos comunes coinciden con la plantilla.
- [ ] `Errores específicos` contiene solo rechazos explícitos o la indicación estándar.
- [ ] La estructura JSON común permanece debajo de los errores.
- [ ] Los marcadores canónicos y dinámicos se conservaron; los demás fueron reemplazados.
- [ ] No hay credenciales, datos sensibles ni detalles internos de GeneXus.
- [ ] Cada pendiente indica la evidencia necesaria.

## Criterio de finalización

La documentación está lista cuando permite invocar el servicio y comprender su entrada, salida y errores HTTP sin consultar el código GeneXus. Si no se puede determinar la entrada, la salida o la autenticación, no declararla completa.

Siguiente paso obligatorio: [templateDoc.md](templateDoc.md).
