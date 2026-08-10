# EscribirSalidas.ps1
# Modulo de escritura de las salidas del generador de documentacion APIGLM.
# Escribe el documento markdown en documentacion/servicios/<wrapper>.md (UTF-8
# sin BOM y finales LF) sin sobrescribir.
# Se importa por dot-source desde GenerarDocumento.ps1, despues de
# AnalizarServicio.ps1 y RedactarDocumento.ps1.

$ErrorActionPreference = 'Stop'

function Escribir-Salidas {
    <#
    .SYNOPSIS
    Escribe el documento markdown del servicio.
    .DESCRIPTION
    Escribe el documento en <directorioSalida>/<wrapper en minusculas>.md con
    UTF-8 sin BOM y finales LF. Si el archivo ya existe, lo regenera.
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
    $documentoNormalizado = $Documento -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($rutaDocumento, $documentoNormalizado, (New-Object System.Text.UTF8Encoding($false)))

    return $rutaDocumento
}
