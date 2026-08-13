# Orquestador de exportacion completa, inventario, validacion y complementos XPZ.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Repositorio
)

$ErrorActionPreference = 'Stop'
$raizRepositorio = [System.IO.Path]::GetFullPath($Repositorio)
$rutaConfiguracion = Join-Path $raizRepositorio 'configuracion.json'
$rutaDirectorioXpz = Join-Path $raizRepositorio 'xpz'
$rutaDirectorioLogs = Join-Path $raizRepositorio 'Logs'
$rutaProyectoCompleto = Join-Path $raizRepositorio 'binary\ExportarXPZ.msbuild'
$rutaProyectoSelectivo = Join-Path $raizRepositorio 'binary\ExportarXPZSelectivo.msbuild'
$rutaScriptProgreso = Join-Path $raizRepositorio 'binary\ExportarXPZProgreso.ps1'
$rutaScriptInventario = Join-Path $raizRepositorio 'documentacion\Endpoints\binary\GenerarListaEndpoints.ps1'
$rutaScriptValidacion = Join-Path $raizRepositorio 'binary\ValidarXPZ.ps1'
$rutaScriptSelectivo = Join-Path $raizRepositorio 'binary\ExportarXPZSelectivo.ps1'
$rutaPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$maximoCiclos = 5

function Resolver-Ruta {
    param([Parameter(Mandatory = $true)][string]$Ruta)

    if ([System.IO.Path]::IsPathRooted($Ruta)) {
        return [System.IO.Path]::GetFullPath($Ruta)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $raizRepositorio $Ruta))
}

function Convertir-RutaRelativa {
    param([Parameter(Mandatory = $true)][string]$Ruta)

    $rutaAbsoluta = [System.IO.Path]::GetFullPath($Ruta)
    $raizAbsoluta = [System.IO.Path]::GetFullPath($raizRepositorio).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if ($rutaAbsoluta.StartsWith($raizAbsoluta, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ($rutaAbsoluta.Substring($raizAbsoluta.Length) -replace '\\', '/')
    }
    return $rutaAbsoluta -replace '\\', '/'
}

function Test-XpzValido {
    param([Parameter(Mandatory = $true)][string]$Ruta)

    if (-not (Test-Path -LiteralPath $Ruta -PathType Leaf)) { return $false }
    $zip = $null
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Ruta)
        $entradasXml = @($zip.Entries | Where-Object { $_.Name -like '*.xml' })
        if ($entradasXml.Count -ne 1) { return $false }
        $lector = New-Object System.IO.StreamReader($entradasXml[0].Open())
        try {
            $xml = New-Object System.Xml.XmlDocument
            $xml.LoadXml($lector.ReadToEnd())
            return ($xml.DocumentElement.LocalName -eq 'ExportFile')
        } finally {
            $lector.Dispose()
        }
    } catch {
        return $false
    } finally {
        if ($null -ne $zip) { $zip.Dispose() }
    }
}

function Guardar-XpzActivo {
    param(
        [Parameter(Mandatory = $true)]$Configuracion,
        [Parameter(Mandatory = $true)][string]$RutaXpz
    )

    $Configuracion.xpz = Convertir-RutaRelativa -Ruta $RutaXpz
    $json = $Configuracion | ConvertTo-Json -Depth 10
    $json = $json -replace "`r`n", "`n"
    $codificacion = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($rutaConfiguracion, $json, $codificacion)
}

function Obtener-UltimoReporteCompatible {
    param([Parameter(Mandatory = $true)][string]$RutaXpz)

    $rutaXpzEsperada = [System.IO.Path]::GetFullPath($RutaXpz)
    $reportes = @(Get-ChildItem -LiteralPath $rutaDirectorioLogs -Filter '*-validacion-xpz.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    foreach ($archivo in $reportes) {
        try {
            $reporte = Get-Content -LiteralPath $archivo.FullName -Raw | ConvertFrom-Json
            if (-not $reporte.ejecucion -or -not $reporte.ejecucion.xpz) { continue }
            $rutaReportada = Resolver-Ruta -Ruta ([string]$reporte.ejecucion.xpz)
            if ([System.StringComparer]::OrdinalIgnoreCase.Equals($rutaReportada, $rutaXpzEsperada)) {
                return [pscustomobject]@{
                    Datos = $reporte
                    Ruta = $archivo.FullName
                }
            }
        } catch {
        }
    }
    return $null
}

function Obtener-SignaturaPendientes {
    param([Parameter(Mandatory = $true)]$Reporte)

    $lista = [string]$Reporte.objectList
    if ([string]::IsNullOrWhiteSpace($lista) -and $Reporte.solicitudes) {
        $lista = (@($Reporte.solicitudes | ForEach-Object { @($_.exportar) } | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join ',')
    }
    return $lista.Trim()
}

function Obtener-OnlyModuleAPIGLM {
    param([Parameter(Mandatory = $true)]$Configuracion)

    $propiedad = $null
    if ($null -ne $Configuracion.exportacion) {
        $propiedad = $Configuracion.exportacion.PSObject.Properties['onlyModuleAPIGLM']
    }
    if ($null -eq $propiedad) {
        return $true
    }
    if ($propiedad.Value -isnot [bool]) {
        throw 'La propiedad exportacion.onlyModuleAPIGLM debe ser un booleano JSON (true o false).'
    }
    return [bool]$propiedad.Value
}

try {
    if (-not (Test-Path -LiteralPath $rutaConfiguracion -PathType Leaf)) {
        throw 'No existe configuracion.json. Ejecute primero el lanzador para crear el modelo.'
    }

    if (-not (Test-Path -LiteralPath $rutaDirectorioLogs -PathType Container)) {
        New-Item -ItemType Directory -Path $rutaDirectorioLogs -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $rutaDirectorioXpz -PathType Container)) {
        New-Item -ItemType Directory -Path $rutaDirectorioXpz -Force | Out-Null
    }

    $configuracion = Get-Content -LiteralPath $rutaConfiguracion -Raw | ConvertFrom-Json
    $onlyModuleAPIGLM = Obtener-OnlyModuleAPIGLM -Configuracion $configuracion

    if (-not $onlyModuleAPIGLM) {
        Write-Host ''
        Write-Host 'ADVERTENCIA: se configuro la exportacion de toda la Knowledge Base.' -ForegroundColor Yellow
        Write-Host 'La operacion puede tardar aproximadamente entre 20 y 30 minutos.' -ForegroundColor Yellow
        Write-Host 'Se generara un XPZ nuevo y no se reemplazaran exportaciones anteriores.' -ForegroundColor Yellow
        $confirmacion = Read-Host 'Desea continuar? [S/N]'
        if ($confirmacion -notmatch '^(?i:s|si|sí|y|yes)$') {
            Write-Host 'Exportacion abortada por el usuario.' -ForegroundColor Yellow
            exit 3
        }
    }

    $herramientas = $configuracion.herramientas
    $rutaGeneXus = [string]$herramientas.geneXusProgramDir
    $rutaKb = [string]$herramientas.kbPath
    $rutaMsbuild = [string]$herramientas.msbuildPath

    foreach ($requerido in @(
        [pscustomobject]@{ Nombre = 'GeneXus'; Ruta = $rutaGeneXus; Tipo = 'Container' },
        [pscustomobject]@{ Nombre = 'Knowledge Base'; Ruta = $rutaKb; Tipo = 'Container' },
        [pscustomobject]@{ Nombre = 'MSBuild'; Ruta = $rutaMsbuild; Tipo = 'Leaf' },
        [pscustomobject]@{ Nombre = 'proyecto de exportacion'; Ruta = $rutaProyectoCompleto; Tipo = 'Leaf' },
        [pscustomobject]@{ Nombre = 'script de progreso'; Ruta = $rutaScriptProgreso; Tipo = 'Leaf' }
    )) {
        if ([string]::IsNullOrWhiteSpace($requerido.Ruta) -or -not (Test-Path -LiteralPath $requerido.Ruta -PathType $requerido.Tipo)) {
            throw ("No se encontro " + $requerido.Nombre + ': ' + $requerido.Ruta)
        }
    }

    $marcaTemporal = (Get-Date).ToString('yyyyMMdd_HHmmssfff')
    $etiquetaExportacion = if ($onlyModuleAPIGLM) { 'APIGLM' } else { 'KB' }
    $targetExportacion = if ($onlyModuleAPIGLM) { 'ExportarAPIGLM' } else { 'ExportarTodaLaKB' }
    $rutaXpzNuevo = Join-Path $rutaDirectorioXpz ('SEGUROS_COMERCIAL_' + $etiquetaExportacion + '_' + $marcaTemporal + '.xpz')
    $rutaLogExportacion = Join-Path $rutaDirectorioLogs ('exportarXPZ_' + $marcaTemporal + '.log')

    Write-Host ''
    if ($onlyModuleAPIGLM) {
        Write-Host '[1/4] Exportando Module:APIGLM...' -ForegroundColor Cyan
    } else {
        Write-Host '[1/4] Exportando todos los objetos de la Knowledge Base...' -ForegroundColor Cyan
    }
    Write-Host ('Alcance de exportacion: ' + $etiquetaExportacion) -ForegroundColor DarkGray
    & $rutaPowerShell -NoProfile -ExecutionPolicy Bypass -File $rutaScriptProgreso `
        -MsbuildPath $rutaMsbuild `
        -ProjectFile $rutaProyectoCompleto `
        -GxProgramDir $rutaGeneXus `
        -KbPath $rutaKb `
        -XpzFile $rutaXpzNuevo `
        -LogFile $rutaLogExportacion `
        -TargetName $targetExportacion 2>&1 | Out-Host
    $codigoExportacion = $LASTEXITCODE
    if ($codigoExportacion -ne 0 -or -not (Test-XpzValido -Ruta $rutaXpzNuevo)) {
        throw ('La exportacion completa fallo. Revise el log: ' + $rutaLogExportacion)
    }

    Guardar-XpzActivo -Configuracion $configuracion -RutaXpz $rutaXpzNuevo
    Write-Host ('XPZ activo: ' + $rutaXpzNuevo) -ForegroundColor Green

    $signaturaAnterior = ''
    for ($ciclo = 1; $ciclo -le $maximoCiclos; $ciclo++) {
        Write-Host ''
        Write-Host ("[2/4] Regenerando inventario (ciclo $ciclo de $maximoCiclos)...") -ForegroundColor Cyan
        & $rutaPowerShell -NoProfile -ExecutionPolicy Bypass -File $rutaScriptInventario `
            -ConfigPath $rutaConfiguracion 2>&1 | Out-Host
        $codigoInventario = $LASTEXITCODE
        if ($codigoInventario -ne 0) {
            throw 'No se pudo regenerar el inventario de endpoints.'
        }

        Write-Host ''
        Write-Host ("[3/4] Validando completitud del XPZ (ciclo $ciclo de $maximoCiclos)...") -ForegroundColor Cyan
        & $rutaPowerShell -NoProfile -ExecutionPolicy Bypass -File $rutaScriptValidacion `
            -ConfigPath $rutaConfiguracion 2>&1 | Out-Host
        $codigoValidacion = $LASTEXITCODE
        $seleccionReporte = Obtener-UltimoReporteCompatible -RutaXpz $rutaXpzNuevo
        if ($codigoValidacion -eq 0) {
            Write-Host 'XPZ completo y sin exportaciones adicionales.' -ForegroundColor Green
            exit 0
        }
        if ($null -eq $seleccionReporte) {
            throw 'La validacion solicito exportacion adicional, pero no se encontro su reporte compatible.'
        }

        $reporte = $seleccionReporte.Datos

        $signaturaActual = Obtener-SignaturaPendientes -Reporte $reporte
        if ([string]::IsNullOrWhiteSpace($signaturaActual)) {
            throw 'La validacion termino con pendientes, pero el reporte no contiene objetos exportables.'
        }
        if ($signaturaAnterior -and $signaturaAnterior -eq $signaturaActual) {
            Write-Host 'La validacion no produjo progreso; se detiene el ciclo automatico.' -ForegroundColor Yellow
            exit 1
        }
        if ($ciclo -eq $maximoCiclos) {
            Write-Host ('Se alcanzo el limite de ' + $maximoCiclos + ' ciclos. Pendientes: ' + $signaturaActual) -ForegroundColor Yellow
            exit 1
        }

        $signaturaAnterior = $signaturaActual
        Write-Host ''
        Write-Host ("[4/4] Exportando complemento selectivo (ciclo $ciclo de $maximoCiclos)...") -ForegroundColor Cyan
        & $rutaPowerShell -NoProfile -ExecutionPolicy Bypass -File $rutaScriptSelectivo `
            -ConfigPath $rutaConfiguracion `
            -ReportePath $seleccionReporte.Ruta `
            -MsbuildPath $rutaMsbuild `
            -ProjectFile $rutaProyectoSelectivo `
            -GxProgramDir $rutaGeneXus `
            -KbPath $rutaKb 2>&1 | Out-Host
        $codigoSelectivo = $LASTEXITCODE
        if ($codigoSelectivo -ne 0) {
            throw 'La exportacion selectiva fallo. Revise el log generado por el script.'
        }
    }

    exit 1
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
