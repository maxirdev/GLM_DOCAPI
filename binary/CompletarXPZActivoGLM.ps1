# CompletarXPZActivoGLM.ps1
# Completa el XPZ activo antes de documentar: valida la completitud con el mismo
# control previo a la exportacion selectiva (ValidarXPZ.ps1) y, si el XPZ requiere
# componentes adicionales, exporta los elementos necesarios con ExportarXPZSelectivo.ps1.
# Si la exportacion falla o se detiene sin completar, pregunta si desea continuar de
# todas formas advirtiendo que algunos servicios no se documentaran.
# Codigos de salida: 0 = listo (XPZ completo o continuar a pesar de pendientes),
# 3 = abortado por el usuario, 1 = error.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Repositorio,
    [Parameter(Mandatory = $true)][string]$XpzActivo,
    [string]$ManifiestoPath
)

$ErrorActionPreference = 'Stop'

$raizRepositorio = [System.IO.Path]::GetFullPath($Repositorio)
$rutaConfiguracion = Join-Path $raizRepositorio 'configuracion.json'
$rutaDirectorioLogs = Join-Path $raizRepositorio 'Logs'
$rutaPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$rutaScriptValidacion = Join-Path $raizRepositorio 'binary\ValidarXPZ.ps1'
$rutaScriptSelectivo = Join-Path $raizRepositorio 'binary\ExportarXPZSelectivo.ps1'
$rutaProyectoSelectivo = Join-Path $raizRepositorio 'binary\ExportarXPZSelectivo.msbuild'
$maximoCiclos = 5
$rutaManifiestoEjecucion = $ManifiestoPath
$manifiestoEjecucion = $null

$script:ultimaSalida = @()
$script:objetosPendientes = @()

. (Join-Path $PSScriptRoot 'ManifiestoEjecucion.ps1')

function Resolver-Ruta {
    param([Parameter(Mandatory = $true)][string]$Ruta)

    if ([System.IO.Path]::IsPathRooted($Ruta)) {
        return [System.IO.Path]::GetFullPath($Ruta)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $raizRepositorio $Ruta))
}

function Obtener-UltimoReporteCompatible {
    param(
        [Parameter(Mandatory = $true)][string]$RutaXpz,
        [Parameter(Mandatory = $true)][string]$EjecucionId
    )

    $rutaXpzEsperada = [System.IO.Path]::GetFullPath($RutaXpz)
    $reportes = @(Get-ChildItem -LiteralPath $rutaDirectorioLogs -Filter '*-validacion-xpz.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    foreach ($archivo in $reportes) {
        try {
            $reporte = Get-Content -LiteralPath $archivo.FullName -Raw | ConvertFrom-Json
            if (-not $reporte.ejecucion -or -not $reporte.ejecucion.xpz) { continue }
            if ([string]$reporte.ejecucion.id -ne $EjecucionId) { continue }
            $rutaReportada = Resolver-Ruta -Ruta ([string]$reporte.ejecucion.xpz)
            if ([System.StringComparer]::OrdinalIgnoreCase.Equals($rutaReportada, $rutaXpzEsperada)) {
                return [pscustomobject]@{ Datos = $reporte; Ruta = $archivo.FullName }
            }
        } catch {
        }
    }
    return $null
}

function Obtener-ObjetosPendientes {
    param([Parameter(Mandatory = $true)]$Reporte)

    $objetos = New-Object System.Collections.Generic.List[string]
    foreach ($solicitud in @($Reporte.solicitudes)) {
        foreach ($objeto in @($solicitud.exportar)) {
            $valor = ([string]$objeto).Trim()
            if ($valor -and $objetos -notcontains $valor) { [void]$objetos.Add($valor) }
        }
    }
    if ($objetos.Count -gt 0) { return @($objetos) }

    foreach ($objeto in ([string]$Reporte.objectList -split ',')) {
        $nombre = $objeto.Trim()
        if ($nombre -and $objetos -notcontains $nombre) { [void]$objetos.Add($nombre) }
    }
    return @($objetos)
}

function Obtener-SignaturaPendientes {
    param([Parameter(Mandatory = $true)]$Reporte)

    $lista = [string]$Reporte.objectList
    if ([string]::IsNullOrWhiteSpace($lista) -and $Reporte.solicitudes) {
        $lista = (@($Reporte.solicitudes | ForEach-Object { @($_.exportar) } | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join ',')
    }
    return $lista.Trim()
}

function Invocar-Script {
    param(
        [Parameter(Mandatory = $true)][string]$RutaScript,
        [string[]]$Argumentos = @()
    )

    $lineas = New-Object System.Collections.Generic.List[string]
    & $rutaPowerShell -NoProfile -ExecutionPolicy Bypass -File $RutaScript @Argumentos 2>&1 | ForEach-Object {
        $texto = $_.ToString()
        $lineas.Add($texto)
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            Write-Host $texto -ForegroundColor Red
        } elseif ($texto -match '(?i)^\s*error\s*:') {
            Write-Host $texto -ForegroundColor Red
        } else {
            Write-Host $texto
        }
    }
    $script:ultimaSalida = @($lineas)
    return $LASTEXITCODE
}

function Obtener-MotivoError {
    $lineasError = @($script:ultimaSalida | Where-Object { $_ -match '(?i)^\s*error\s*:' } | ForEach-Object { $_.Trim() })
    if ($lineasError.Count -gt 0) { return ($lineasError -join ' | ') }
    $lineasUltimas = @($script:ultimaSalida | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 3)
    if ($lineasUltimas.Count -gt 0) { return ($lineasUltimas -join ' | ') }
    return 'La exportacion selectiva fallo sin un mensaje especifico.'
}

function Obtener-DetalleSinReporte {
    $lineasUltimas = @($script:ultimaSalida | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 3)
    if ($lineasUltimas.Count -gt 0) { return (' Salida: ' + ($lineasUltimas -join ' | ')) }
    return ''
}

function Preguntar-Continuar {
    param([string]$Motivo)

    Write-Host ''
    Write-Host ('Motivo: ' + $Motivo) -ForegroundColor Red
    if ($script:objetosPendientes.Count -gt 0) {
        Write-Host 'Objetos que siguen pendientes de exportacion:' -ForegroundColor Yellow
        foreach ($objeto in $script:objetosPendientes) {
            Write-Host ('  ' + $objeto) -ForegroundColor DarkGray
        }
    }
    Write-Host ''
    Write-Host 'ADVERTENCIA: Algunos servicios no se documentaran por no contar con toda la informacion.' -ForegroundColor Yellow
    $respuesta = Read-Host 'Desea continuar de todas formas? [S/N]'
    if ($respuesta -match '^(?i:s|si|sí|y|yes)$') {
        Write-Host 'Continuando con la documentacion disponible.' -ForegroundColor Green
        return $true
    }
    Write-Host 'Operacion abortada. Se vuelve al menu sin generar la documentacion.' -ForegroundColor Yellow
    return $false
}

try {
    if (-not (Test-Path -LiteralPath $rutaConfiguracion -PathType Leaf)) {
        throw 'No existe configuracion.json.'
    }
    if (-not (Test-Path -LiteralPath $XpzActivo -PathType Leaf)) {
        throw ('No se encontro el XPZ activo: ' + $XpzActivo)
    }
    if ($ManifiestoPath) {
        $manifiestoEjecucion = Leer-ManifiestoEjecucion -RutaManifiesto $ManifiestoPath
        $rutaXpzManifiesto = Resolver-Ruta -Ruta ([string]$manifiestoEjecucion.xpz)
        $rutaXpzActiva = [System.IO.Path]::GetFullPath($XpzActivo)
        if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($rutaXpzManifiesto, $rutaXpzActiva)) {
            throw ('El manifiesto corresponde a otro XPZ. Manifiesto: ' + $rutaXpzManifiesto + '. Activo: ' + $rutaXpzActiva + '.')
        }
        $rutaManifiestoEjecucion = [System.IO.Path]::GetFullPath($ManifiestoPath)
    } else {
        $manifiestoEjecucion = Crear-ManifiestoEjecucion -Xpz $XpzActivo -FullyQualifiedNames @()
        $rutaManifiestoEjecucion = $manifiestoEjecucion.Ruta
    }
    foreach ($requerido in @(
        [pscustomobject]@{ Nombre = 'validador de completitud'; Ruta = $rutaScriptValidacion; Tipo = 'Leaf' },
        [pscustomobject]@{ Nombre = 'exportador selectivo'; Ruta = $rutaScriptSelectivo; Tipo = 'Leaf' },
        [pscustomobject]@{ Nombre = 'proyecto selectivo MSBuild'; Ruta = $rutaProyectoSelectivo; Tipo = 'Leaf' }
    )) {
        if (-not (Test-Path -LiteralPath $requerido.Ruta -PathType $requerido.Tipo)) {
            throw ('No se encontro ' + $requerido.Nombre + ': ' + $requerido.Ruta)
        }
    }

    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  VALIDACION Y COMPLETITUD DEL XPZ ACTIVO' -ForegroundColor Cyan
    Write-Host ('  ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host ('  XPZ activo: ' + $XpzActivo) -ForegroundColor DarkGray

    Write-Host ''
    Write-Host 'Validando completitud del XPZ...' -ForegroundColor Cyan
    $codigoValidacion = Invocar-Script -RutaScript $rutaScriptValidacion -Argumentos @('-ConfigPath', $rutaConfiguracion, '-XpzPath', $XpzActivo, '-ManifiestoPath', $rutaManifiestoEjecucion)
    $reporteSeleccionado = Obtener-UltimoReporteCompatible -RutaXpz $XpzActivo -EjecucionId $manifiestoEjecucion.ejecucionId
    if ($codigoValidacion -eq 0) {
        Write-Host ''
        Write-Host 'El XPZ esta completo; no se requieren exportaciones adicionales.' -ForegroundColor Green
        exit 0
    }
    if ($null -eq $reporteSeleccionado) {
        throw ('La validacion termino con codigo ' + $codigoValidacion + ' y no se encontro un reporte compatible con el XPZ activo.' + (Obtener-DetalleSinReporte))
    }

    $script:objetosPendientes = @(Obtener-ObjetosPendientes -Reporte $reporteSeleccionado.Datos)
    if ($script:objetosPendientes.Count -eq 0) {
        throw 'La validacion informo pendientes, pero el reporte no contiene objetos exportables.'
    }

    Write-Host ''
    Write-Host 'El XPZ seleccionado requiere componentes adicionales.' -ForegroundColor Yellow
    Write-Host 'Comenzando la exportacion de los elementos necesarios...' -ForegroundColor Yellow
    foreach ($objeto in $script:objetosPendientes) {
        Write-Host ('  ' + $objeto) -ForegroundColor DarkGray
    }

    $configuracion = Get-Content -LiteralPath $rutaConfiguracion -Raw | ConvertFrom-Json
    $rutaMsbuild = [string]$configuracion.herramientas.msbuildPath
    $rutaGeneXus = [string]$configuracion.herramientas.geneXusProgramDir
    $rutaKb = [string]$configuracion.herramientas.kbPath

    $signaturaAnterior = ''
    for ($ciclo = 1; $ciclo -le $maximoCiclos; $ciclo++) {
        Write-Host ''
        Write-Host ("Exportando complemento selectivo (ciclo " + $ciclo + " de " + $maximoCiclos + ")...") -ForegroundColor Cyan
        $codigoSelectivo = Invocar-Script -RutaScript $rutaScriptSelectivo -Argumentos @(
            '-ConfigPath', $rutaConfiguracion,
            '-XpzPath', $XpzActivo,
            '-ReportePath', $reporteSeleccionado.Ruta,
            '-ManifiestoPath', $rutaManifiestoEjecucion,
            '-MsbuildPath', $rutaMsbuild,
            '-ProjectFile', $rutaProyectoSelectivo,
            '-GxProgramDir', $rutaGeneXus,
            '-KbPath', $rutaKb
        )
        if ($codigoSelectivo -ne 0) {
            if (Preguntar-Continuar -Motivo (Obtener-MotivoError)) { exit 0 } else { exit 3 }
        }

        Write-Host ''
        Write-Host ("Revalidando completitud (ciclo " + $ciclo + " de " + $maximoCiclos + ")...") -ForegroundColor Cyan
        $codigoRevalidacion = Invocar-Script -RutaScript $rutaScriptValidacion -Argumentos @('-ConfigPath', $rutaConfiguracion, '-XpzPath', $XpzActivo, '-ManifiestoPath', $rutaManifiestoEjecucion)
        $nuevoReporte = Obtener-UltimoReporteCompatible -RutaXpz $XpzActivo -EjecucionId $manifiestoEjecucion.ejecucionId
        if ($codigoRevalidacion -eq 0) {
            Write-Host ''
            Write-Host 'El XPZ esta completo; no se requieren exportaciones adicionales.' -ForegroundColor Green
            exit 0
        }
        if ($null -eq $nuevoReporte) {
            throw ('La revalidacion termino con codigo ' + $codigoRevalidacion + ' y no se encontro un reporte compatible con el XPZ activo.' + (Obtener-DetalleSinReporte))
        }
        $script:objetosPendientes = @(Obtener-ObjetosPendientes -Reporte $nuevoReporte.Datos)
        $signaturaActual = Obtener-SignaturaPendientes -Reporte $nuevoReporte.Datos
        if ($signaturaAnterior -and $signaturaAnterior -eq $signaturaActual) {
            if (Preguntar-Continuar -Motivo 'La validacion no produjo progreso tras la exportacion selectiva.') { exit 0 } else { exit 3 }
        }
        if ($ciclo -eq $maximoCiclos) {
            if (Preguntar-Continuar -Motivo ('Se alcanzo el limite de ' + $maximoCiclos + ' ciclos y quedan objetos pendientes de exportacion.')) { exit 0 } else { exit 3 }
        }
        $signaturaAnterior = $signaturaActual
        $reporteSeleccionado = $nuevoReporte
    }

    exit 1
} catch {
    Write-Host ''
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if ($rutaManifiestoEjecucion -and -not $ManifiestoPath) {
        try { Eliminar-ManifiestoEjecucion -RutaManifiesto $rutaManifiestoEjecucion } catch { }
    }
}
