# SPEC 28 — Versión y changelog del panel

> **Estado:** Borrador
> **Depende de:** SPEC 25, SPEC 26, SPEC 27
> **Fecha:** 2026-08-25
> **Objetivo:** Identificar el producto como Gestor Documentación GLM y publicar su versión y changelog desde un archivo Markdown local visible en el header del panel.

## Por qué existe esta SPEC

El header actual identifica la aplicación como Panel APIGLM y no informa qué versión funcional está desplegada. El lanzador y el servidor contienen además marcadores técnicos distintos que pueden provocar que una instancia vigente sea considerada obsoleta.

La aplicación necesita una versión funcional comprensible y un changelog mantenido por el programador, sin derivarlo de Git ni incorporar una herramienta de despliegue adicional.

## Alcance

**Incluido:**

- Cambiar el nombre visible del header a `Gestor Documentación GLM`.
- Cambiar el `<title>` del documento al mismo nombre.
- Actualizar la descripción HTML para reflejar el nombre vigente.
- Crear `web/version.md` como fuente versionada en Git de la versión funcional y su historial de cambios.
- Iniciar el archivo con la versión `V1.0`.
- Documentar en `V1.0` los cambios de SPEC 26, SPEC 27 y SPEC 28.
- Mantener las entradas en orden descendente, con la versión más reciente primero.
- Usar el formato de versión `V1.<revisión>`.
- Incrementar la revisión como un entero: `V1.8`, `V1.9`, `V1.10`, `V1.11`.
- No cambiar automáticamente a `V2.0` después de `V1.9` ni por alcanzar otra revisión.
- Permitir `V2.0` únicamente cuando el responsable del producto lo indique explícitamente.
- Incluir fecha y descripción verificable en cada entrada.
- Extraer la versión visible desde el primer encabezado de nivel uno de `web/version.md`.
- Mostrar la versión actual junto al nombre del producto en el header.
- Agregar junto a la versión un botón para abrir las novedades.
- Mostrar todo el changelog en un popup accesible.
- Renderizar el Markdown en lugar de mostrar un textarea.
- Admitir un subconjunto seguro y local de Markdown: encabezados, párrafos, listas, negrita y código inline.
- Escapar HTML crudo y no ejecutar enlaces, imágenes, scripts ni atributos provenientes del archivo.
- Implementar el renderizado sin librerías externas.
- Permitir cerrar el popup con su botón, la tecla Escape y las reglas de foco vigentes.
- Servir `version.md` únicamente mediante la allowlist estática explícita del servidor.
- Servir el archivo con tipo de contenido Markdown y `Cache-Control: no-store`.
- No bloquear el panel si `version.md` falta, no puede leerse o tiene una primera versión inválida.
- Mostrar `Versión no disponible` y deshabilitar el acceso al changelog cuando no exista contenido válido.
- Registrar el fallo como diagnóstico no bloqueante sin mezclarlo con la invalidez de `configuracion.json`.
- Mantener separada la versión funcional `V1.<revisión>` del marcador técnico usado para detectar compatibilidad entre lanzador y servidor.
- Corregir la divergencia actual entre el marcador esperado por `IniciarPanelWeb.cmd` y el publicado por `ServidorPanelWeb.ps1`.
- Mantener `web/version.md` bajo actualización manual del programador en cada subida o deploy.
- No agregar edición del changelog desde Configuración.
- Extender `test/Run-Tests.ps1` con serving, formato, degradación y seguridad del Markdown.
- Verificar con Playwright MCP el header y el popup en escritorio, móvil, tema claro y oscuro.

**Fuera de alcance (para futuras SPEC):**

- Generar la versión desde tags, commits, ramas o fechas de Git.
- Cambiar automáticamente la versión durante el arranque.
- Editar `version.md` desde el panel.
- Usar versionado semántico `X.Y.Z`.
- Inferir saltos de versión mayor.
- Incorporar un parser Markdown de terceros.
- Admitir HTML crudo, imágenes o enlaces ejecutables en el changelog.
- Usar la versión funcional para decidir si debe terminarse un proceso de servidor existente.
- Bloquear el arranque por ausencia o corrupción de `version.md`.
- Cambiar las reglas funcionales de configuración, contexto o pipeline definidas en otras SPEC.

## Modelo de datos

### Formato de `web/version.md`

```markdown
# V1.0

**Fecha:** 2026-08-25

## Cambios

- Se incorporó el contexto Cliente, Módulo y Ambiente.
- Se agregó la validación integral de configuracion.json al iniciar.
- Se actualizó el header y se agregó este historial de cambios.
```

Las versiones posteriores se insertan antes de la entrada anterior:

```markdown
# V1.10

**Fecha:** 2026-10-01

## Cambios

- Descripción concreta del cambio desplegado.

# V1.9

**Fecha:** 2026-09-20

## Cambios

- Descripción de la versión anterior.
```

Convenciones:

- La primera línea significativa debe coincidir con `# V1.<entero no negativo>`.
- La versión visible conserva la `V` mayúscula.
- La revisión se compara como entero, no como decimal; `10` es posterior a `9`.
- Cada entrada contiene una fecha `YYYY-MM-DD` y al menos un cambio.
- El archivo conserva finales LF y UTF-8 sin BOM.
- La aplicación lee el archivo, pero nunca lo modifica.

### Estado de versión del frontend

```js
const applicationVersion = {
  available: true,
  version: "V1.0",
  markdown: "# V1.0\n...",
  error: null
};
```

Cuando el archivo no está disponible:

```js
const applicationVersion = {
  available: false,
  version: null,
  markdown: null,
  error: "No se pudo cargar el historial de versiones."
};
```

Este estado es independiente del contexto, los trabajos, la configuración y las preferencias persistidas.

### Subconjunto Markdown

El renderer admite únicamente:

- Encabezados `#`, `##` y `###`.
- Párrafos de texto.
- Listas no ordenadas con `-`.
- Negrita delimitada por `**`.
- Código inline delimitado por acentos graves.

Todo HTML se representa como texto escapado. La sintaxis de enlaces e imágenes no produce elementos navegables. No se admiten estilos, eventos ni atributos provenientes de Markdown.

## Plan de implementación

1. Crear fixtures válidos, ausentes, corruptos y maliciosos para el contrato de versión y renderer.
2. Crear `web/version.md` con `V1.0`, fecha y resumen de SPEC 26, SPEC 27 y SPEC 28.
3. Agregar `version.md` a la allowlist y el tipo MIME Markdown en `binary/ServidorPanelWeb.ps1`.
4. Mantener `Cache-Control: no-store` y restringir la entrega estática a los métodos permitidos.
5. Cambiar nombre, título, descripción y controles del header en `web/index.html`.
6. Implementar en las utilidades frontend un renderer seguro para el subconjunto Markdown acordado.
7. Cargar `/version.md` desde `web/app.js`, validar el primer encabezado y completar el estado degradado sin bloquear el resto del panel.
8. Implementar el popup de novedades con foco contenido, Escape y retorno del foco al botón de origen.
9. Agregar en `web/style.css` la versión, el botón y el changelog responsive para ambos temas.
10. Separar el marcador técnico del servidor de `V1.<revisión>` y sincronizar el contrato de compatibilidad entre `IniciarPanelWeb.cmd` y `ServidorPanelWeb.ps1`.
11. Extender `test/Run-Tests.ps1` con allowlist, MIME, formato, degradación y entradas Markdown hostiles.
12. Verificar mediante Playwright MCP la carga, apertura, scroll, cierre, foco y degradación en escritorio y móvil.

## Criterios de aceptación

- [ ] El header muestra exactamente `Gestor Documentación GLM`.
- [ ] El `<title>` del documento muestra `Gestor Documentación GLM`.
- [ ] Existe `web/version.md` y está incluido en Git.
- [ ] La primera entrada de `web/version.md` es `V1.0`.
- [ ] La entrada `V1.0` incluye fecha y cambios de SPEC 26, SPEC 27 y SPEC 28.
- [ ] La versión mostrada se obtiene del primer encabezado de nivel uno del archivo.
- [ ] El formato válido es `V1.<entero>`.
- [ ] `V1.10` se considera posterior a `V1.9`.
- [ ] La aplicación no cambia a `V2.0` sin una decisión explícita.
- [ ] Las versiones nuevas se agregan antes de las anteriores.
- [ ] La versión aparece junto al nombre del producto.
- [ ] El botón de novedades aparece junto a la versión disponible.
- [ ] Pulsar el botón abre un popup con todo el historial.
- [ ] El popup renderiza encabezados, párrafos, listas, negrita y código inline.
- [ ] HTML crudo se muestra escapado y nunca se ejecuta.
- [ ] Enlaces, imágenes y URLs `javascript:` no producen elementos ejecutables.
- [ ] El renderer no usa CDN ni dependencias de terceros.
- [ ] El popup puede cerrarse mediante botón y Escape.
- [ ] Al cerrar, el foco vuelve al botón que abrió el popup.
- [ ] `GET /version.md` responde únicamente para la ruta allowlisted.
- [ ] `GET /version.md` usa un tipo de contenido Markdown con UTF-8.
- [ ] La respuesta usa `Cache-Control: no-store`.
- [ ] Rutas similares y traversal no permiten leer otros archivos Markdown.
- [ ] Si falta `version.md`, el panel continúa cargando contextos y vistas.
- [ ] Si la primera versión es inválida, se muestra `Versión no disponible`.
- [ ] Sin una versión válida, la apertura del changelog queda deshabilitada.
- [ ] Un fallo de versión no activa `configurationBlocked`.
- [ ] La versión funcional no se usa para decidir compatibilidad del proceso servidor.
- [ ] El marcador técnico esperado por el lanzador coincide con el publicado por el servidor.
- [ ] `test/Run-Tests.ps1` cubre formato, serving, degradación y Markdown malicioso.
- [ ] Playwright MCP no detecta errores de consola durante la carga y apertura del popup.
- [ ] Header y popup funcionan en escritorio y 390x844.
- [ ] Header y popup son legibles en tema claro y oscuro.

## Decisiones

- **Sí:** renombrar el producto a Gestor Documentación GLM. Es el nombre visible solicitado.
- **Sí:** usar `web/version.md` como fuente única de versión funcional y descripción de cambios.
- **Sí:** mantener el archivo manualmente. El programador controla qué cambios pertenecen a cada deploy.
- **Sí:** usar `V1.<revisión>` con revisión entera. Esto permite `V1.10` después de `V1.9`.
- **No:** aplicar SemVer. El producto no cambiará a `V2.0` salvo indicación explícita.
- **Sí:** conservar todas las entradas en orden descendente. El popup funciona como control histórico de versiones.
- **Sí:** renderizar Markdown seguro. Reemplaza la idea inicial del textarea y mejora la lectura.
- **No:** permitir HTML, imágenes o enlaces ejecutables. El changelog no necesita contenido activo.
- **No:** usar una librería Markdown. El subconjunto es pequeño y el panel continúa sin dependencias.
- **Sí:** degradar sin bloquear. La versión es informativa y no debe impedir operaciones.
- **Sí:** separar versión funcional y marcador técnico. Cumplen propósitos distintos.
- **No:** editar el changelog desde Configuración. `version.md` permanece bajo control del programador y Git.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Markdown local inyecta HTML o scripts | Escapar contenido y admitir únicamente un subconjunto cerrado. |
| El navegador conserva una versión anterior | Servir con `no-store` y solicitar el archivo sin caché. |
| La versión funcional se confunde con compatibilidad técnica | Mantener campos y contratos separados. |
| El lanzador termina una instancia vigente por marcadores divergentes | Sincronizar el marcador técnico y cubrirlo con pruebas. |
| El archivo falta durante un deploy | Mostrar Versión no disponible sin afectar contexto ni operaciones. |
| Las revisiones se ordenan como decimales | Parsear el sufijo como entero y documentar `V1.10` después de `V1.9`. |

## Lo que **no** incluye esta SPEC

- Versionado semántico automático.
- Generación desde Git o desde la fecha del sistema.
- Editor de changelog en el panel.
- HTML, imágenes o enlaces activos en Markdown.
- Dependencias de terceros.
- Bloqueo del panel por ausencia del changelog.
- Uso de `V1.<revisión>` como marcador técnico del servidor.
- Cambios funcionales fuera del header y la publicación del historial.

Cada cambio desplegado posterior debe agregar una entrada al inicio de `web/version.md` y aumentar manualmente la revisión acordada.
