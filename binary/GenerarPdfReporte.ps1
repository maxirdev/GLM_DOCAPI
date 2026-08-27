# Genera el PDF de un reporte Markdown y resuelve sus imagenes adyacentes.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$MarkdownPath,
    [Parameter(Mandatory = $false)][string]$PdfPath = '',
    [Parameter(Mandatory = $false)][string]$Repositorio = '',
    [Parameter(Mandatory = $false)][string]$ConfigPath = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Repositorio)) {
    $Repositorio = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
} else {
    $Repositorio = [System.IO.Path]::GetFullPath($Repositorio)
}
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $Repositorio 'configuracion.json'
}
if (-not [System.IO.Path]::IsPathRooted($MarkdownPath)) {
    $MarkdownPath = Join-Path $Repositorio $MarkdownPath
}
$MarkdownPath = [System.IO.Path]::GetFullPath($MarkdownPath)
if (-not (Test-Path -LiteralPath $MarkdownPath -PathType Leaf)) {
    throw ('No se encontro el Markdown del reporte: ' + $MarkdownPath)
}
if ([string]::IsNullOrWhiteSpace($PdfPath)) {
    $PdfPath = [System.IO.Path]::ChangeExtension($MarkdownPath, '.pdf')
} elseif (-not [System.IO.Path]::IsPathRooted($PdfPath)) {
    $PdfPath = Join-Path $Repositorio $PdfPath
}
$PdfPath = [System.IO.Path]::GetFullPath($PdfPath)

. (Join-Path $PSScriptRoot 'GLMUtilidades.ps1')
. (Join-Path $PSScriptRoot 'RenderizarMarkdownTypstPdf.ps1')
$configuracion = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$rutaPandoc = [string]$configuracion.herramientas.pandocPath
$rutaTypst = [string]$configuracion.herramientas.typstPath
if ([string]::IsNullOrWhiteSpace($rutaPandoc) -or [string]::IsNullOrWhiteSpace($rutaTypst)) {
    throw 'La configuracion no define Pandoc y Typst.'
}
if (-not [System.IO.Path]::IsPathRooted($rutaPandoc)) { $rutaPandoc = Join-Path $Repositorio $rutaPandoc }
if (-not [System.IO.Path]::IsPathRooted($rutaTypst)) { $rutaTypst = Join-Path $Repositorio $rutaTypst }

$markdown = [System.IO.File]::ReadAllText($MarkdownPath)
Convertir-MarkdownAPdf -Markdown $markdown -RutaSalida $PdfPath -RutaPandoc $rutaPandoc -RutaTypst $rutaTypst -RutaRecursos (Split-Path -Parent $MarkdownPath) | Out-Null
if (-not (Test-PdfValidoParaPromocion -Ruta $PdfPath)) {
    throw 'El PDF generado no supera la validacion de formato.'
}
Write-Output $PdfPath
