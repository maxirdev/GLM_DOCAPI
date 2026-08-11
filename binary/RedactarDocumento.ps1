# RedactarDocumento.ps1
# Modulo de redaccion de la documentacion tecnica de un servicio APIGLM.
# Renderiza el markdown segun templateDoc.md, conservando los bloques canonicos,
# la variante GET o POST unica y el JSON comun. Se importa por dot-source desde
# GenerarDocumento.ps1. Se importa despues de AnalizarServicio.ps1.

$ErrorActionPreference = 'Stop'

function Convertir-Celda {
    <#
    .SYNOPSIS
    Prepara un valor para ser insertado en una celda de tabla markdown.
    .DESCRIPTION
    Normaliza los valores nulos o vacios, escapa los caracteres de tuberia y
    normaliza los saltos de linea.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][string]$Texto = ''
    )

    if ($null -eq $Texto) { $Texto = '' }
    $celda = $Texto -replace '\|', '\|'
    $celda = $celda -replace "`r?`n", ' '
    return $celda
}

function Redactar-Documento {
    <#
    .SYNOPSIS
    Redacta el documento markdown de un servicio segun templateDoc.md.
    .DESCRIPTION
    Recibe la documentación técnica unica y produce el documento final respetando el orden
    de la plantilla: definicion, generalidades, entrada (variante GET o POST),
    salida exitosa y errores especificos con el JSON comun debajo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Documentacion
    )

    $documento = New-Object System.Text.StringBuilder
    function Agregar-Linea {
        param([string]$Texto = '')
        [void]$documento.Append($Texto)
        [void]$documento.Append("`n")
    }

    Agregar-Linea ('# ' + $Documentacion.NombreFuncional)
    Agregar-Linea ''
    Agregar-Linea ($Documentacion.Descripcion + '.')
    Agregar-Linea ''
    Agregar-Linea '## Definición del servicio'
    Agregar-Linea ''
    Agregar-Linea '| Dato | Valor |'
    Agregar-Linea '|---|---|'
    Agregar-Linea ('| Endpoint | `' + (Convertir-Celda $Documentacion.EndpointPublicado) + '` |')
    Agregar-Linea ('| Descripción | ' + (Convertir-Celda $Documentacion.Descripcion) + ' |')
    Agregar-Linea ('| Método HTTP | `' + $Documentacion.MetodoHttp + '` |')
    Agregar-Linea '| Autenticación | HTTP Basic mediante `Authorization` |'
    Agregar-Linea ''
    Agregar-Linea '## Generalidades'
    Agregar-Linea ''
    Agregar-Linea '### Autenticación'
    Agregar-Linea ''
    Agregar-Linea '```http'
    Agregar-Linea 'Authorization: Basic {Base64(usuario:contraseña)}'
    Agregar-Linea '```'
    Agregar-Linea ''
    Agregar-Linea 'No incluir credenciales reales.'
    Agregar-Linea ''
    Agregar-Linea '### Códigos HTTP comunes'
    Agregar-Linea ''
    Agregar-Linea '| Código | Significado |'
    Agregar-Linea '|---:|---|'
    Agregar-Linea '| 200 | Solicitud procesada correctamente. |'
    Agregar-Linea '| 400 | Faltan parámetros requeridos o son inválidos. |'
    Agregar-Linea '| 401 | Falló la autenticación. |'
    Agregar-Linea '| 500 | Error interno de Servicio. |'
    Agregar-Linea '| 501 | Servicio no implementado o sin configuración. |'
    Agregar-Linea '| 503 | Servicio no disponible o inactivo. |'
    Agregar-Linea ''
    Agregar-Linea '## Entrada'
    Agregar-Linea ''
    if ($Documentacion.MetodoHttp -eq 'GET') {
        if (@($Documentacion.Entrada).Count -eq 0) {
            Agregar-Linea 'Sin parámetros de entrada.'
        } else {
            $cantidad = @($Documentacion.Entrada).Count
            $textoCantidad = "$cantidad posiciones"
            if ($cantidad -eq 1) { $textoCantidad = "1 posición" }
            Agregar-Linea ('La consulta debe conservar exactamente ' + $textoCantidad + ' y respetar el orden indicado.')
            Agregar-Linea ''
            Agregar-Linea '| Posición | Parámetro | Tipo | Obligatorio | Descripción |'
            Agregar-Linea '|---:|---|---|---|---|'
            foreach ($campo in $Documentacion.Entrada) {
                Agregar-Linea ('| ' + $campo.Orden + ' | `' + (Convertir-Celda $campo.Campo) + '` | ' + (Convertir-Celda $campo.Tipo) + ' | ' + $campo.Obligatorio + ' | ' + (Convertir-Celda $campo.Descripcion) + ' |')
            }
        }
    } else {
        Agregar-Linea '| Parámetro o campo | Tipo | Obligatorio | Descripción |'
        Agregar-Linea '|---|---|---|---|'
        foreach ($campo in $Documentacion.Entrada) {
            Agregar-Linea ('| `' + (Convertir-Celda $campo.Campo) + '` | ' + (Convertir-Celda $campo.Tipo) + ' | ' + $campo.Obligatorio + ' | ' + (Convertir-Celda $campo.Descripcion) + ' |')
        }
        foreach ($estructura in $Documentacion.Estructuras) {
            Agregar-Linea ''
            Agregar-Linea ('**Estructura de ' + $estructura.RutaJson + '**')
            Agregar-Linea ''
            Agregar-Linea '| Campo | Tipo | Obligatorio | Descripción |'
            Agregar-Linea '|---|---|---|---|'
            foreach ($hijo in $estructura.Hijos) {
                Agregar-Linea ('| `' + (Convertir-Celda $hijo.Campo) + '` | ' + (Convertir-Celda $hijo.Tipo) + ' | ' + $hijo.Obligatorio + ' | ' + (Convertir-Celda $hijo.Descripcion) + ' |')
            }
        }
    }
    Agregar-Linea ''
    Agregar-Linea '## Salida exitosa'
    Agregar-Linea ''

    if ($Documentacion.TipoContenidoSalida -eq 'application/octet-stream') {
        Agregar-Linea 'Content-Type: `application/octet-stream`'
        Agregar-Linea ''
        Agregar-Linea 'Archivo binario.'
    } elseif ($Documentacion.SalidaVacia) {
        Agregar-Linea 'Sin mensaje explícito.'
    } elseif (@($Documentacion.MensajesSalida | Where-Object { $_ }).Count -gt 0) {
        $mensajes = @($Documentacion.MensajesSalida | Where-Object { $_ })
        if ($mensajes.Count -eq 1) {
            Agregar-Linea ('Mensaje: `' + (Convertir-Celda $mensajes[0]) + '`')
        } else {
            Agregar-Linea 'Mensajes posibles:'
            foreach ($mensaje in $mensajes) { Agregar-Linea ('- `' + (Convertir-Celda $mensaje) + '`') }
        }
    } elseif ($Documentacion.TipoColeccionPrimitiva -ne $null) {
        Agregar-Linea 'Colección: `SI`.'
        Agregar-Linea ''
        $tipoColeccion = $Documentacion.TipoColeccionPrimitiva
        if ([string]::IsNullOrWhiteSpace([string]$tipoColeccion)) { $tipoColeccion = 'Colección JSON' }
        else { $tipoColeccion = 'Colección de ' + $tipoColeccion }
        Agregar-Linea $tipoColeccion
    } else {
        $coleccion = 'NO'
        if ($Documentacion.SalidaColeccion) { $coleccion = 'SI' }
        Agregar-Linea ('Colección: `' + $coleccion + '`.')
        Agregar-Linea ''
        Agregar-Linea '| Campo | Tipo | Descripción |'
        Agregar-Linea '|---|---|---|'
        foreach ($campo in $Documentacion.Salida) {
            $nombreCampo = Convertir-Celda $campo.Campo
            if ($nombreCampo) { $nombreCampo = '`' + $nombreCampo + '`' }
            Agregar-Linea ('| ' + $nombreCampo + ' | ' + (Convertir-Celda $campo.Tipo) + ' | ' + (Convertir-Celda $campo.Descripcion) + ' |')
        }
        foreach ($estructura in $Documentacion.EstructurasSalida) {
            Agregar-Linea ''
            Agregar-Linea ('**Estructura de ' + $estructura.RutaJson + '**')
            Agregar-Linea ''
            Agregar-Linea '| Campo | Tipo | Descripción |'
            Agregar-Linea '|---|---|---|'
            foreach ($hijo in $estructura.Hijos) {
                $nombreCampo = Convertir-Celda $hijo.Campo
                if ($nombreCampo) { $nombreCampo = '`' + $nombreCampo + '`' }
                Agregar-Linea ('| ' + $nombreCampo + ' | ' + (Convertir-Celda $hijo.Tipo) + ' | ' + (Convertir-Celda $hijo.Descripcion) + ' |')
            }
        }
    }
    foreach ($notaSalida in @($Documentacion.NotasSalida | Where-Object { $_ })) {
        Agregar-Linea ''
        Agregar-Linea ('Nota: ' + (Convertir-Celda $notaSalida))
    }
    Agregar-Linea ''
    Agregar-Linea '## Errores específicos'
    Agregar-Linea ''
    if (@($Documentacion.Errores).Count -gt 0) {
        Agregar-Linea '| Código HTTP | Respuesta o mensaje |'
        Agregar-Linea '|---:|---|'
        foreach ($error in $Documentacion.Errores) {
            $codigoMostrado = $error.Codigo
            if ($error.Codigo -eq 0) {
                $codigoMostrado = 'PENDIENTE DE CONFIRMACIÓN'
            }
            Agregar-Linea ('| ' + $codigoMostrado + ' | `' + (Convertir-Celda $error.Mensaje) + '` |')
        }
    } else {
        Agregar-Linea 'No se identificaron errores específicos en el programa principal.'
    }
    Agregar-Linea ''
    Agregar-Linea '```json'
    Agregar-Linea '{'
    Agregar-Linea '  "status": <Código HTTP>,'
    Agregar-Linea '  "Description": "<descripción general>",'
    Agregar-Linea '  "detail": "<detalle>",'
    Agregar-Linea '  "JsonResult": ""'
    Agregar-Linea '}'
    Agregar-Linea '```'

    return $documento.ToString()
}
