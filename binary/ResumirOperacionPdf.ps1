# Resume la operacion PDF de la ejecucion contextual usando el review del manifiesto.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Repositorio,
    [Parameter(Mandatory = $true)][string]$ManifiestoPath
)

$ErrorActionPreference = 'Stop'

$raizRepositorio = [System.IO.Path]::GetFullPath($Repositorio)
. (Join-Path $PSScriptRoot 'GLMUtilidades.ps1')
. (Join-Path $PSScriptRoot 'AnalizarServicio.ps1')
. (Join-Path $PSScriptRoot 'CargarMultiXPZ.ps1')
. (Join-Path $PSScriptRoot 'ManifiestoEjecucion.ps1')
. (Join-Path $PSScriptRoot 'CargarConfiguracion.ps1')

Inicializar-ConsolaUtf8

$manifiestoEjecucion = Leer-ManifiestoEjecucion -RutaManifiesto $ManifiestoPath
$contexto = Cargar-Configuracion -ConfigPath ([string]$manifiestoEjecucion.configPath) -ClienteId ([string]$manifiestoEjecucion.clienteId) -AmbienteId ([string]$manifiestoEjecucion.ambienteId)
$rutaDirectorioLogs = $contexto.DirectorioLogs
$rutaDirectorioServicios = $contexto.DirectorioServicios
$rutaReporte = Join-Path $rutaDirectorioLogs ([string]$manifiestoEjecucion.ejecucionId + '-actualizacion-review.json')

if (-not (Test-Path -LiteralPath $rutaReporte -PathType Leaf)) {
    Write-Host ''
    Write-Host 'Resumen de la operacion PDF:' -ForegroundColor Cyan
    Write-Host '  No hay reporte de revision del generador disponible para esta ejecucion.' -ForegroundColor DarkYellow
    exit 0
}

$reporte = Get-Content -LiteralPath $rutaReporte -Raw | ConvertFrom-Json

$pdfValidos = New-Object System.Collections.Generic.List[object]
$pdfConservados = New-Object System.Collections.Generic.List[object]
$pdfFallidos = New-Object System.Collections.Generic.List[object]
$omitidos = @($reporte.servicios | Where-Object { $_.estado -in @('OMITIDO', 'ELIMINADO') -or $_.estadoPdf -eq 'NO_APLICA' })
$indiceResumen = Cargar-IndiceMultiXPZ -RutaXpzPrincipal ([string]$manifiestoEjecucion.xpz)
$fqnsInventario = @(Obtener-ServiciosHttpDesdeIndice -Indice $indiceResumen | ForEach-Object { [string]$_.proceso })
foreach ($servicio in @($reporte.servicios)) {
    if ([string]$servicio.estado -in @('OMITIDO', 'ELIMINADO') -or [string]$servicio.estadoPdf -eq 'NO_APLICA') { continue }
    $rutaPdf = [string]$servicio.pdf
    if ([string]::IsNullOrWhiteSpace($rutaPdf)) {
        $nombreLocal = Obtener-NombreArchivoServicio -FullyQualifiedName ([string]$servicio.fullyQualifiedName) -FqnsInventario $fqnsInventario
        $rutaPdf = Join-Path $rutaDirectorioServicios ($nombreLocal + '.pdf')
    }
    if (Test-PdfValidoParaPromocion -Ruta $rutaPdf) {
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
