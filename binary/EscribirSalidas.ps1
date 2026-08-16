# EscribirSalidas.ps1
# Modulo de escritura de las salidas del generador de documentacion APIGLM.
# Escribe el documento Markdown en documentacion/servicios/<wrapper>.md,
# reemplazando únicamente el servicio procesado. La conversión a PDF se
# realiza bajo demanda mediante GenerarPdfServicios.ps1.
# Se importa por dot-source desde GenerarDocumento.ps1, despues de
# AnalizarServicio.ps1 y RedactarDocumento.ps1.

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'GLMUtilidades.ps1')

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
        $nombreWrapper = Obtener-NombreArchivoServicio -FullyQualifiedName $Documentacion.FqWrapper -FqnsInventario @()
    }
    $rutaDocumento = Join-Path $DirectorioSalida ($nombreWrapper + '.md')

    $contenido = Normalizar-SaltosLineaLf -Texto $Documento
    Escribir-ArchivoAtomico -Ruta $rutaDocumento -Contenido $contenido | Out-Null

    return $rutaDocumento
}
