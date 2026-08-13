# Herramientas PDF portables

La conversión PDF bajo demanda utiliza dos ejecutables, sin Chrome ni Python:

- `pandoc.exe`
- `typst.exe`

Versiones incorporadas:

- Pandoc 3.10.1 — SHA-256: `5FA622F6DFD68AB43F2E28D671533384530408CF8A34D0BEC1C8CB0D57A8B775`
- Typst 0.15.1 — SHA-256: `081217A463ADB006F8894B44227FE4B9C9E91FC85F5463D5948E8370DB9BB31E`

Colocarlos en esta carpeta o actualizar `herramientas.pandocPath` y
`herramientas.typstPath` en `configuracion.json`.

Fuentes oficiales:

- https://github.com/jgm/pandoc/releases
- https://github.com/typst/typst/releases

El lanzador valida ambos archivos antes de iniciar la conversión. La generación
Markdown no depende de estas herramientas.

El aspecto del documento se mantiene en las plantillas del proyecto:

- `binary/templates/documentacion.css` para la salida HTML/Chromium.
- `binary/templates/documentacion.typ` para la salida PDF portable con Typst.
- `binary/fonts/` contiene Poppins Regular, SemiBold y Bold para mantener la misma tipografía en el PDF portable.
