# EscribirSalidas.ps1
# Modulo de escritura de las salidas del generador de documentacion APIGLM.
# Escribe el documento Markdown en documentacion/servicios/<wrapper>.md,
# reemplazando únicamente el servicio procesado. La conversión a PDF se
# realiza bajo demanda mediante GenerarPdfServicios.ps1.
# Se importa por dot-source desde GenerarDocumento.ps1, despues de
# AnalizarServicio.ps1 y RedactarDocumento.ps1.

$ErrorActionPreference = 'Stop'

function Escribir-Salidas {
    <#
    .SYNOPSIS
    Escribe el documento Markdown del servicio.
    .DESCRIPTION
    Escribe el documento en <directorioSalida>/<wrapper en minusculas>.md.
    Si el archivo ya existe, lo regenera.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Documentacion,
        [Parameter(Mandatory = $true)][string]$Documento,
        [Parameter(Mandatory = $true)][string]$DirectorioSalida,
        [Parameter(Mandatory = $false)][string]$NombreArchivo = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($NombreArchivo)) {
        $nombreWrapper = $NombreArchivo
    } else {
        $ultimoPunto = $Documentacion.FqWrapper.LastIndexOf('.')
        if ($ultimoPunto -le 0) {
            throw ('El wrapper ' + $Documentacion.FqWrapper + ' no tiene un nombre completo valido.')
        }
        $nombreWrapper = $Documentacion.FqWrapper.Substring($ultimoPunto + 1).ToLowerInvariant()
    }
    $rutaDocumento = Join-Path $DirectorioSalida ($nombreWrapper + '.md')

    if (-not (Test-Path -LiteralPath $DirectorioSalida)) {
        New-Item -ItemType Directory -Path $DirectorioSalida -Force | Out-Null
    }
    $contenido = $Documento -replace "`r`n", "`n" -replace "`r", "`n"
    $codificacion = New-Object System.Text.UTF8Encoding($false)
    $rutaTemporal = $rutaDocumento + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $rutaRespaldo = $rutaDocumento + '.' + [guid]::NewGuid().ToString('N') + '.bak'
    try {
        [System.IO.File]::WriteAllText($rutaTemporal, $contenido, $codificacion)
        if (Test-Path -LiteralPath $rutaDocumento -PathType Leaf) {
            [System.IO.File]::Replace($rutaTemporal, $rutaDocumento, $rutaRespaldo)
        } else {
            [System.IO.File]::Move($rutaTemporal, $rutaDocumento)
        }
    } finally {
        if (Test-Path -LiteralPath $rutaTemporal -PathType Leaf) {
            Remove-Item -LiteralPath $rutaTemporal -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $rutaRespaldo -PathType Leaf) {
            Remove-Item -LiteralPath $rutaRespaldo -Force -ErrorAction SilentlyContinue
        }
    }

    return $rutaDocumento
}
