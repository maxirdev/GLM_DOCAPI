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
        [Parameter(Mandatory = $true)][string]$DirectorioSalida
    )

    $ultimoPunto = $Documentacion.FqWrapper.LastIndexOf('.')
    if ($ultimoPunto -le 0) {
        throw ('El wrapper ' + $Documentacion.FqWrapper + ' no tiene un nombre completo valido.')
    }
    $nombreWrapper = $Documentacion.FqWrapper.Substring($ultimoPunto + 1).ToLowerInvariant()
    $rutaDocumento = Join-Path $DirectorioSalida ($nombreWrapper + '.md')

    if (-not (Test-Path -LiteralPath $DirectorioSalida)) {
        New-Item -ItemType Directory -Path $DirectorioSalida -Force | Out-Null
    }
    $contenido = $Documento -replace "`r`n", "`n" -replace "`r", "`n"
    $codificacion = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($rutaDocumento, $contenido, $codificacion)

    return $rutaDocumento
}
