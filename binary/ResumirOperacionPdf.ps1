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

$generados = @($reporte.servicios | Where-Object { $_.estado -eq 'OK' })
$omitidos = @($reporte.servicios | Where-Object { $_.estado -eq 'OMITIDO' })
$pendientes = @($reporte.servicios | Where-Object { $_.estado -eq 'WARNING' })
$fallados = @($reporte.servicios | Where-Object { $_.estado -eq 'ERROR' })

Write-Host ''
Write-Host 'Resumen de la operacion PDF:' -ForegroundColor Cyan
Write-Host ("  [OK]      PDFs generados: " + $generados.Count) -ForegroundColor Green
Write-Host ("  [OMITIDO] Omitidos: " + $omitidos.Count) -ForegroundColor Yellow
Write-Host ("  [WARNING] Pendientes: " + $pendientes.Count) -ForegroundColor Yellow
Write-Host ("  [ERROR]   Fallados: " + $fallados.Count) -ForegroundColor Red

if ($omitidos.Count -gt 0) {
    Write-Host '    Omitidos:' -ForegroundColor Yellow
    foreach ($servicio in $omitidos) {
        Write-Host ('      - ' + $servicio.fullyQualifiedName) -ForegroundColor DarkYellow
    }
}

if ($pendientes.Count -gt 0) {
    Write-Host '    Pendientes:' -ForegroundColor Yellow
    foreach ($servicio in $pendientes) {
        Write-Host ('      - ' + $servicio.fullyQualifiedName) -ForegroundColor DarkYellow
    }
}

if ($fallados.Count -gt 0) {
    Write-Host '    Fallados:' -ForegroundColor Red
    foreach ($servicio in $fallados) {
        Write-Host ('      - ' + $servicio.fullyQualifiedName) -ForegroundColor Red
    }
}

exit 0
