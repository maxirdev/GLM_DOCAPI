# V1.0

**Fecha:** 2026-08-25

## Cambios

- Texto con <script>alert('xss')</script> y <img src="x" onerror="alert(1)">
- [Enlace](javascript:alert('xss')) y ![Imagen](https://example.invalid/image.png)
- URL javascript:alert('xss') y `codigo <script>alert(1)</script>`
