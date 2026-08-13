# SPEC 13 — Lanzador unificado de exportación, Markdown y PDF bajo demanda

> **Estado:** Aprobado
> **Depende de:** SPEC 04, SPEC 11, SPEC 12
> **Fecha:** 2026-08-12
> **Objetivo:** Crear `GenerarDocumentosGLM.cmd` como entrada interactiva única para validar dependencias, completar el XPZ mediante exportación selectiva, generar la documentación de servicios en Markdown y convertirla a PDF bajo demanda.

## Por qué existe esta SPEC

El proyecto tiene varios `.cmd` relacionados que actualmente se ejecutan por separado. Se necesita una entrada única que mantenga el control de la operación completa, informe cada etapa y vuelva al menú después de finalizar cada proceso.

La documentación pública generada en `documentacion/servicios/` volverá a producir archivos Markdown por defecto. La conversión a PDF será una operación independiente y explícita del menú, usando los Markdown existentes como fuente. Las plantillas y normas internas continuarán siendo Markdown.

## Alcance

**Incluido:**

- `GenerarDocumentosGLM.cmd` como nuevo punto de entrada interactivo.
- Menú Batch implementado con `CHOICE`.
- Validación inicial de `configuracion.json`, rutas, XPZ y dependencias de herramientas.
- Creación de un modelo de configuración cuando `configuracion.json` no exista.
- Opción para exportar `APIGLMMain` y completar automáticamente la información faltante del XPZ.
- Activación automática del XPZ completo recién exportado.
- Ejecución encadenada de inventario, validación y exportación selectiva.
- Hasta cinco ciclos de validación y exportación selectiva por operación.
- Opción para generar la documentación de servicios en Markdown.
- Opción independiente para convertir bajo demanda los `.md` existentes a `.pdf`.
- Conversión temporal de Markdown a Typst y PDF mediante Pandoc + Typst portable, sin navegador, usando una plantilla visual versionada.
- Conservación de los `.md` junto con los `.pdf`; la conversión no elimina ni modifica el Markdown.
- Configuración centralizada de GeneXus, Knowledge Base, MSBuild y Edge.
- Resumen de resultados, pausa informativa y retorno al menú después de cada operación.
- Conservación temporal de los `.cmd` actuales sin modificarlos ni eliminarlos.

**Fuera de alcance:**

- Eliminación de los `.cmd` actuales en esta primera etapa.
- Rediseño o mejora del visor de endpoints.
- Publicación de servicios o despliegue en GeneXus.
- Fusión física de XPZ principal y complementos.
- Generación automática de documentación después de completar el XPZ.
- Cambio de las reglas técnicas de análisis, redacción o plantilla.

## Modelo de datos

### Configuración ampliada

`configuracion.json` conserva sus propiedades actuales y agrega las rutas necesarias para validar y ejecutar las herramientas:

```json
{
  "xpz": "xpz/SEGUROS_COMERCIAL_APIGLM_20260812_095637331.xpz",
  "packagename": "glmsuit.comercial.",
  "cliente": "Trunk",
  "serviciosIgnorados": [],
  "herramientas": {
    "geneXusProgramDir": "C:/Program Files (x86)/GeneXus/GeneXus18",
    "kbPath": "C:/KBs/SEGUROS_COMERCIAL_TRUNK",
    "msbuildPath": "C:/Windows/Microsoft.NET/Framework/v4.0.30319/MSBuild.exe",
    "pandocPath": "binary/tools/pandoc.exe",
    "typstPath": "binary/tools/typst.exe"
  }
}
```

Los nombres de las propiedades se mantienen en inglés para conservar la convención del archivo actual. Las rutas se normalizan antes de validarlas y antes de pasarlas a procesos externos.

### Modelo de configuración inicial

Cuando el archivo no existe, el lanzador crea un modelo con valores vacíos:

```json
{
  "xpz": "",
  "packagename": "",
  "cliente": "",
  "serviciosIgnorados": [],
  "herramientas": {
    "geneXusProgramDir": "",
    "kbPath": "",
    "msbuildPath": "",
    "pandocPath": "binary/tools/pandoc.exe",
    "typstPath": "binary/tools/typst.exe"
  }
}
```

Después de crear el modelo, el lanzador informa los campos que el usuario debe completar y finaliza sin mostrar operaciones ejecutables.

### Estados de sesión

```text
SIN_CONFIGURACION
SIN_XPZ_ACTIVO
LISTO
OPERANDO
COMPLETADO
ERROR
PENDIENTE
SALIR
```

La sesión conserva si alguna operación falló o terminó con pendientes. Al seleccionar salir, devuelve código `0` si no hubo fallos, `1` si hubo una operación fallida o incompleta y `2` si no pudo inicializarse por configuración inválida.

## Menú e interacción

Con configuración válida y un XPZ activo, el menú muestra:

```text
1. Exportar APIGLMMain y completar el XPZ
2. Generar todos los Markdown y preguntar por PDF
3. Generar PDF desde Markdown existente
4. Salir
```

Si no existe el XPZ configurado, o la ruta configurada no apunta a un archivo existente, el menú conserva la conversión PDF porque puede operar sobre Markdown ya existentes y muestra:

```text
1. Exportar APIGLMMain
2. Generar PDF bajo demanda desde Markdown
3. Salir
```

Si existen otros `.xpz` en la carpeta pero el archivo configurado no existe, el lanzador no selecciona ninguno automáticamente. Informa la inconsistencia y deja que el usuario corrija la configuración o exporte uno nuevo.

Una operación permanece en primer plano hasta completar todos sus pasos. No se muestra el menú intermedio ni se permite iniciar otra operación en paralelo. Al terminar, se muestran el estado, los archivos generados, los reportes y los errores; luego se espera una tecla y se vuelve al menú.

## Flujo de exportación y completitud

La opción 1 ejecuta la siguiente secuencia:

1. Validar las dependencias específicas de GeneXus, Knowledge Base, MSBuild y los archivos de proyecto.
2. Invocar la exportación completa de `APIGLMMain` usando las rutas de `configuracion.json`.
3. Confirmar que el XPZ esperado existe y que es un ZIP legible con XML raíz `ExportFile`.
4. Actualizar automáticamente la propiedad `xpz` de `configuracion.json` para apuntar al XPZ recién generado.
5. Regenerar el inventario de endpoints desde el XPZ activo.
6. Ejecutar `ValidarXPZ.ps1` y localizar el reporte compatible más reciente.
7. Si no hay objetos pendientes, informar que el XPZ está completo y volver al menú.
8. Si hay objetos pendientes, invocar la exportación selectiva con los selectores del reporte.
9. Repetir la validación después de cada complemento generado.
10. Detener el ciclo al completar el XPZ, al alcanzar cinco ciclos o si una operación no produce progreso.

Los complementos se generan como `<base>_1.xpz`, `<base>_2.xpz`, etc. No se modifica `configuracion.json.xpz` para apuntar a los complementos; el validador los descubre por nomenclatura.

La opción 1 no inicia la generación de documentos automáticamente después de completar el XPZ.

## Flujo de documentación Markdown

La opción 2 ejecuta el flujo completo de `GenerarDocumento.ps1` en modo `TODOS`, por lo que genera primero todos los `.md` del inventario. Al finalizar correctamente, el lanzador pregunta si se desean convertir esos Markdown a PDF en la misma operación.

Antes de invocar el generador, el lanzador exige que exista el inventario `documentacion/Endpoints/assets/endpoints.json`. Si no existe, informa que debe ejecutarse la preparación del inventario y vuelve al menú sin generar documentos.

El generador conserva el orden `AnalizarServicio` → `RedactarDocumento` → `EscribirSalidas`. `RedactarDocumento` produce la representación Markdown en memoria y `EscribirSalidas` la escribe en `documentacion/servicios/<wrapper>.md` en UTF-8 sin BOM y con finales LF.

La generación Markdown no requiere Edge y no crea PDF automáticamente. Si el `.md` ya existe, se regenera conforme al comportamiento actual del pipeline.

Si el usuario responde que sí, la conversión se ejecuta únicamente sobre los `.md` de `documentacion/servicios/`. Si responde que no, la operación termina conservando los Markdown y vuelve al menú.

## Flujo de PDF bajo demanda

La opción 3 invoca `GenerarPdfServicios.ps1` y opera exclusivamente sobre los `.md` existentes en `documentacion/servicios/`. Conserva la selección de un documento, múltiples documentos o todos los documentos.

La conversión utiliza estas etapas:

1. Leer el `.md` seleccionado sin modificarlo.
2. Convertir el Markdown a HTML con soporte para encabezados, párrafos, tablas, código, listas y texto inline.
3. Aplicar una hoja de estilos HTML para página A4, márgenes, tipografía, tablas y saltos de página.
4. Invocar Pandoc y Typst con archivos temporales para convertir Markdown a PDF sin navegador, fecha, hora, URL ni rutas temporales automáticas.
5. Validar que el PDF exista, tenga tamaño mayor que cero y sea legible.
6. Mantener el `.md` junto al PDF generado.

El archivo final conserva el nombre local del wrapper y cambia únicamente la extensión:

```text
documentacion/servicios/wsobtenerpolizasasegurado.pdf
```

Si Pandoc o Typst no están disponibles en `binary/tools/`, la operación PDF se bloquea antes de producir PDFs y se informa la herramienta faltante. La generación Markdown no depende de estas herramientas. Los archivos normativos `documentacion/analisisXPZ.md`, `documentacion/reglasEditoriales.md` y `documentacion/templateDoc.md` no se eliminan.

## Plan de implementación

1. Crear `GenerarDocumentosGLM.cmd` con el ciclo de menú, `CHOICE`, mensajes de estado, pausa entre operaciones y código de salida acumulado.
2. Crear en el lanzador la carga inicial de configuración, creación del modelo faltante y validación de la carpeta `xpz/`.
3. Ampliar `CargarConfiguracion.ps1` para leer y validar el bloque `herramientas`.
4. Modificar el flujo de exportación para recibir desde el lanzador las rutas de GeneXus, KB y MSBuild, sin depender de los `.cmd` antiguos.
5. Integrar en la opción 1 la exportación completa, activación del XPZ, generación de inventario, validación y exportación selectiva con límite de cinco ciclos.
6. Agregar detección de falta de progreso y resumen de pendientes cuando el límite de ciclos se alcance.
7. Modificar `EscribirSalidas.ps1` para escribir `<wrapper>.md` como salida predeterminada.
8. Adaptar `GenerarDocumento.ps1` para conservar el procesamiento individual, múltiple y total en Markdown.
9. Crear `GenerarPdfServicios.ps1` para seleccionar Markdown existentes y convertirlos bajo demanda mediante Pandoc + Typst portable.
10. Validar el PDF generado sin eliminar ni modificar el Markdown de origen.
11. Verificar manualmente ambos flujos y los estados de error definidos.

Cada paso debe dejar disponible el flujo que ya estaba operativo o un punto de entrada funcional para el siguiente paso. Los `.cmd` existentes no se eliminarán durante esta SPEC.

## Criterios de aceptación

- [ ] Existe `GenerarDocumentosGLM.cmd` y presenta un menú con exportación, documentación Markdown, PDF bajo demanda y salida cuando el XPZ está disponible.
- [ ] Si no existe un XPZ activo, el menú ofrece exportación, PDF bajo demanda y salida.
- [ ] Si falta `configuracion.json`, se crea un modelo con los campos requeridos, se informa al usuario y no se ejecutan procesos.
- [ ] El lanzador valida las rutas de configuración y las dependencias antes de ejecutar cada operación.
- [ ] Las rutas de GeneXus, KB, MSBuild y Edge se leen desde `configuracion.json`.
- [ ] La exportación completa activa automáticamente el XPZ generado.
- [ ] La exportación completa ejecuta inventario y validación antes de decidir si necesita complementos.
- [ ] Los objetos faltantes provocan exportación selectiva automática mediante el reporte de validación.
- [ ] El ciclo automático se detiene al completar, al no producir progreso o después de cinco ciclos.
- [ ] Los complementos conservan la nomenclatura `<base>_N.xpz` y el XPZ principal sigue siendo el configurado.
- [ ] La opción de documentación no continúa si falta `endpoints.json`.
- [ ] La generación normal produce documentos `.md` en `documentacion/servicios/`.
- [ ] La opción principal genera primero todos los `.md` antes de preguntar por PDF.
- [ ] Si el usuario responde que no, no se inicia Edge ni se genera ningún PDF.
- [ ] La opción PDF utiliza los `.md` existentes como fuente y conserva esos archivos.
- [ ] La opción PDF permite seleccionar un documento, múltiples documentos o todos.
- [ ] La ausencia de Pandoc o Typst bloquea únicamente la generación PDF.
- [ ] La generación Markdown funciona sin Edge.
- [ ] Cada PDF generado puede abrirse y contiene el contenido del documento redactado.
- [ ] Una operación en curso no permite iniciar otra operación.
- [ ] Después de cada operación se muestra un resumen, se espera una tecla y se vuelve al menú.
- [ ] El visor mejorado no forma parte de esta implementación.
- [ ] Los `.cmd` antiguos permanecen sin cambios durante esta etapa.

## Decisiones

- **Sí:** `GenerarDocumentosGLM.cmd` será la nueva entrada principal.
- **Sí:** el menú se implementará en Batch con `CHOICE`; PowerShell conservará la lógica especializada.
- **Sí:** el menú tendrá exportación completa, documentación Markdown, PDF bajo demanda y salida.
- **Sí:** la opción de exportación ejecutará automáticamente inventario, validación y exportación selectiva.
- **Sí:** se permitirán como máximo cinco ciclos de exportación selectiva.
- **Sí:** el XPZ completo recién exportado se activará automáticamente en la configuración.
- **Sí:** los complementos no reemplazarán el XPZ principal configurado.
- **Sí:** la documentación normal se generará como Markdown en `documentacion/servicios/`.
- **Sí:** el PDF será una operación independiente y bajo demanda a partir del Markdown.
- **Sí:** Pandoc + Typst portable serán el conversor PDF configurado.
- **Sí:** la ausencia de Pandoc o Typst bloqueará únicamente la operación PDF.
- **Sí:** los `.md` se conservarán junto con los PDF.
- **Sí:** la opción de documentación no regenerará automáticamente el inventario faltante.
- **Sí:** los `.cmd` actuales se conservarán sin cambios durante la primera etapa.
- **No:** no se seleccionará automáticamente otro XPZ si la ruta configurada es inválida.
- **No:** no se iniciará automáticamente la documentación al completar el XPZ.
- **No:** no se incluirá el visor mejorado.
- **No:** no se eliminarán todavía los puntos de entrada antiguos.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| La exportación selectiva puede requerir más información después de cada complemento. | Revalidar después de cada ciclo y detenerse después de cinco ciclos o sin progreso. |
| Edge puede no estar instalado o la ruta puede ser incorrecta. | Validar la ruta antes de generar PDFs y mostrar una instrucción concreta. |
| La conversión Markdown a HTML puede alterar tablas o bloques de código. | Usar un conversor limitado a las construcciones de la plantilla y verificar visualmente PDFs renderizados. |
| La activación automática puede apuntar a un XPZ inesperado. | Activar únicamente el archivo recién generado y registrar la ruta anterior y la nueva. |
| Un Markdown puede contener ediciones manuales que no coincidan con el XPZ actual. | La conversión PDF usa explícitamente el Markdown existente y no lo sobrescribe. |

## Lo que **no** incluye esta SPEC

- Eliminación inmediata de los `.cmd` actuales.
- Rediseño del visor de endpoints.
- Generación automática de PDF después de producir Markdown.
- Generación automática de documentación después de la exportación.
- Fusión física de XPZ.
- Despliegue de servicios.
- Cambios en las reglas de análisis o en la plantilla normativa.
