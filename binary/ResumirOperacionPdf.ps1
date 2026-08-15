# Resume la operacion PDF usando el reporte de revision mas reciente del generador.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Repositorio
)

$ErrorActionPreference = 'Stop'

$raizRepositorio = [System.IO.Path]::GetFullPath($Repositorio)
$rutaDirectorioLogs = Join-Path $raizRepositorio 'Logs'
$rutaReporte = $null

if (Test-Path -LiteralPath $rutaDirectorioLogs -PathType Container) {
    $reportes = @(Get-ChildItem -LiteralPath $rutaDirectorioLogs -Filter '*-review.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($reportes.Count -gt 0) { $rutaReporte = $reportes[0].FullName }
}

if (-not $rutaReporte) {
    Write-Host ''
    Write-Host 'Resumen de la operacion PDF:' -ForegroundColor Cyan
    Write-Host '  No hay reporte de revision del generador disponible.' -ForegroundColor DarkYellow
    exit 0
}

$reporte = Get-Content -LiteralPath $rutaReporte -Raw | ConvertFrom-Json

function Test-PdfPublicadoValido {
    param([Parameter(Mandatory = $true)][string]$Ruta)
    if (-not (Test-Path -LiteralPath $Ruta -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $Ruta).Length -lt 5) { return $false }
    $flujo = [System.IO.File]::OpenRead($Ruta)
    try {
        $cabecera = New-Object byte[] 4
        [void]$flujo.Read($cabecera, 0, 4)
        return ([System.Text.Encoding]::ASCII.GetString($cabecera) -eq '%PDF')
    } finally {
        $flujo.Dispose()
    }
}

$pdfValidos = New-Object System.Collections.Generic.List[object]
$pdfConservados = New-Object System.Collections.Generic.List[object]
$pdfFallidos = New-Object System.Collections.Generic.List[object]
$omitidos = @($reporte.servicios | Where-Object { $_.estado -in @('OMITIDO', 'ELIMINADO') -or $_.estadoPdf -eq 'NO_APLICA' })
foreach ($servicio in @($reporte.servicios)) {
    if ([string]$servicio.estado -in @('OMITIDO', 'ELIMINADO') -or [string]$servicio.estadoPdf -eq 'NO_APLICA') { continue }
    $rutaPdf = [string]$servicio.pdf
    if ([string]::IsNullOrWhiteSpace($rutaPdf)) {
        $nombreLocal = ([string]$servicio.fullyQualifiedName).Substring(([string]$servicio.fullyQualifiedName).LastIndexOf('.') + 1).ToLowerInvariant()
        $rutaPdf = Join-Path (Join-Path $raizRepositorio 'documentacion\servicios') ($nombreLocal + '.pdf')
    }
    if (Test-PdfPublicadoValido -Ruta $rutaPdf) {
        [void]$pdfValidos.Add($servicio)
        if ([string]$servicio.estadoPdf -eq 'CONSERVADO') { [void]$pdfConservados.Add($servicio) }
    } else {
        [void]$pdfFallidos.Add($servicio)
    }
}

Write-Host ''
Write-Host 'Resumen de la operacion PDF:' -ForegroundColor Cyan
Write-Host ("  [OK]      PDFs existentes y validos: " + $pdfValidos.Count) -ForegroundColor Green
Write-Host ("  [CONSERVADO] PDFs anteriores: " + $pdfConservados.Count) -ForegroundColor DarkYellow
Write-Host ("  [OMITIDO] Omitidos: " + $omitidos.Count) -ForegroundColor Yellow
Write-Host ("  [ERROR]   PDFs inexistentes o invalidos: " + $pdfFallidos.Count) -ForegroundColor Red

if ($omitidos.Count -gt 0) {
    Write-Host '    Omitidos:' -ForegroundColor Yellow
    foreach ($servicio in $omitidos) {
        Write-Host ('      - ' + $servicio.fullyQualifiedName) -ForegroundColor DarkYellow
    }
}

if ($pdfFallidos.Count -gt 0) {
    Write-Host '    PDFs fallidos:' -ForegroundColor Red
    foreach ($servicio in $pdfFallidos) {
        Write-Host ('      - ' + $servicio.fullyQualifiedName) -ForegroundColor Red
    }
}

exit 0
