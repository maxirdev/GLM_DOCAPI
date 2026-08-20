# CompletarXPZActivoGLM.ps1
# Completa el XPZ activo antes de documentar: valida la completitud con el mismo
# control previo a la exportacion selectiva (ValidarXPZ.ps1) y, si el XPZ requiere
# componentes adicionales, exporta los elementos necesarios con ExportarXPZSelectivo.ps1.
# Si la exportacion falla o se detiene sin completar, pregunta si desea continuar de
# todas formas advirtiendo que algunos servicios no se documentaran.
# Codigos de salida: 0 = XPZ completo, 2 = continuar a pesar de pendientes,
# 3 = abortado por el usuario, 1 = error.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Repositorio,
    [Parameter(Mandatory = $true)][string]$XpzActivo,
    [Parameter(Mandatory = $true)][string]$ManifiestoPath,
    [ValidateSet('abort', 'continue')][string]$PoliticaPendientes = 'abort',
    [ValidateSet('FULL', 'SELECTIVE')][string]$Scope = 'FULL'
)

$ErrorActionPreference = 'Stop'

$raizRepositorio = [System.IO.Path]::GetFullPath($Repositorio)
$rutaScriptValidacion = Join-Path $raizRepositorio 'binary\ValidarXPZ.ps1'
$rutaScriptSelectivo = Join-Path $raizRepositorio 'binary\ExportarXPZSelectivo.ps1'
$rutaProyectoSelectivo = Join-Path $raizRepositorio 'binary\ExportarXPZSelectivo.msbuild'
$maximoCiclos = 5

$script:ultimaSalida = @()
$script:objetosPendientes = @()

. (Join-Path $PSScriptRoot 'GLMUtilidades.ps1')
. (Join-Path $PSScriptRoot 'ManifiestoEjecucion.ps1')
. (Join-Path $PSScriptRoot 'CargarConfiguracion.ps1')
. (Join-Path $PSScriptRoot 'AnalizarServicio.ps1')
. (Join-Path $PSScriptRoot 'CargarMultiXPZ.ps1')

Inicializar-ConsolaUtf8

function Invocar-Script {
    <#
    .SYNOPSIS
    Ejecuta un script PowerShell como proceso hijo mostrando su salida.
    .DESCRIPTION
    Wrapper de Invocar-ScriptHijo (GLMUtilidades.ps1) que conserva la ultima
    salida en $script:ultimaSalida y devuelve el codigo de salida.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$RutaScript,
        [string[]]$Argumentos = @()
    )

    $resultado = Invocar-ScriptHijo -RutaScript $RutaScript -Argumentos $Argumentos
    $script:ultimaSalida = @($resultado.Salida)
    return $resultado.CodigoSalida
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

function Test-ReporteValidacionReutilizable {
    param(
        [Parameter(Mandatory = $true)]$Reporte,
        [Parameter(Mandatory = $true)][string]$Xpz,
        [Parameter(Mandatory = $true)][string]$RutaConfiguracion,
        [Parameter(Mandatory = $true)][string]$Raiz
    )
    if ($null -eq $Reporte -or $null -eq $Reporte.Datos -or $null -eq $Reporte.Datos.ejecucion) { return $false }
    if ([string]$Reporte.Datos.ejecucion.scope -ne 'FULL') { return $false }
    if ([int]$Reporte.Datos.ejecucion.pendientes -ne 0) { return $false }
    if ([string]$Reporte.Datos.ejecucion.sourceFingerprint -notmatch '^[0-9a-fA-F]{64}$') { return $false }
    if ([string]$Reporte.Datos.ejecucion.configurationFingerprint -notmatch '^[0-9a-fA-F]{64}$') { return $false }
    $indiceFuente = Cargar-IndiceMultiXPZ -RutaXpzPrincipal $Xpz
    $sourceFingerprint = Obtener-Sha256TextoNormalizado -Texto ((@($indiceFuente.Manifiesto | Sort-Object Orden | ForEach-Object { '{0}|{1}|{2}' -f $_.Orden, $_.RutaRelativa, $_.Sha256 }) -join "`n") + "`n")
    $configurationFingerprint = Obtener-Sha256ArchivoNormalizado -Ruta $RutaConfiguracion
    return ([string]$Reporte.Datos.ejecucion.sourceFingerprint -ceq $sourceFingerprint -and [string]$Reporte.Datos.ejecucion.configurationFingerprint -ceq $configurationFingerprint)
}

function Preguntar-Continuar {
    param([string]$Motivo)

    if ($PoliticaPendientes -eq 'continue') {
        Write-Host 'La politica no interactiva permite continuar con la evidencia disponible.' -ForegroundColor Yellow
        return $true
    }
    if ($PoliticaPendientes -eq 'abort') {
        Write-Host 'La politica no interactiva aborta ante pendientes o falta de progreso.' -ForegroundColor Yellow
        return $false
    }
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
    $manifiestoEjecucion = Leer-ManifiestoEjecucion -RutaManifiesto $ManifiestoPath
    $rutaManifiestoEjecucion = [System.IO.Path]::GetFullPath($ManifiestoPath)
    $rutaConfiguracion = [System.IO.Path]::GetFullPath([string]$manifiestoEjecucion.configPath)
    $rutaDirectorioLogs = [System.IO.Path]::GetFullPath([string]$manifiestoEjecucion.logsDirectory)
    Asegurar-Directorio -Ruta $rutaDirectorioLogs
    Limpiar-LogsEjecucion -DirectorioLogs $rutaDirectorioLogs
    if (-not (Test-Path -LiteralPath $rutaConfiguracion -PathType Leaf)) {
        throw ('No existe la configuracion del manifiesto: ' + $rutaConfiguracion)
    }
    if (-not (Test-Path -LiteralPath $XpzActivo -PathType Leaf)) {
        throw ('No se encontro el XPZ activo: ' + $XpzActivo)
    }
    $rutaXpzManifiesto = [System.IO.Path]::GetFullPath([string]$manifiestoEjecucion.xpz)
    $rutaXpzActiva = [System.IO.Path]::GetFullPath($XpzActivo)
    if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($rutaXpzManifiesto, $rutaXpzActiva)) {
        throw ('El manifiesto corresponde a otro XPZ. Manifiesto: ' + $rutaXpzManifiesto + '. Activo: ' + $rutaXpzActiva + '.')
    }
    $contexto = Cargar-Configuracion -ConfigPath $rutaConfiguracion -ClienteId ([string]$manifiestoEjecucion.clienteId) -AmbienteId ([string]$manifiestoEjecucion.ambienteId)
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
    $reporteSeleccionado = Obtener-ReporteValidacionMasReciente -DirectorioLogs $rutaDirectorioLogs -RutaXpz $XpzActivo -RaizRepositorio $raizRepositorio
    $reporteReutilizable = if ($null -ne $reporteSeleccionado) { Test-ReporteValidacionReutilizable -Reporte $reporteSeleccionado -Xpz $XpzActivo -RutaConfiguracion $rutaConfiguracion -Raiz $raizRepositorio } else { $false }
    if ($reporteReutilizable) {
        Write-Host 'El XPZ ya cuenta con una validacion completa vigente; se reutiliza el reporte.' -ForegroundColor Green
        exit 0
    }
    $codigoValidacion = Invocar-Script -RutaScript $rutaScriptValidacion -Argumentos @('-ConfigPath', $rutaConfiguracion, '-XpzPath', $XpzActivo, '-ManifiestoPath', $rutaManifiestoEjecucion, '-Scope', $Scope)
    $reporteSeleccionado = Obtener-ReporteValidacionMasReciente -DirectorioLogs $rutaDirectorioLogs -RutaXpz $XpzActivo -RaizRepositorio $raizRepositorio -EjecucionId ([string]$manifiestoEjecucion.ejecucionId)
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

    $rutaMsbuild = [string]$contexto.Herramientas.MsbuildPath
    $rutaGeneXus = [string]$contexto.Herramientas.GeneXusProgramDir
    $rutaKb = [string]$contexto.KbPath
    $perfilExportacion = [string]$contexto.Herramientas.GeneXusExportProfile
    if ($perfilExportacion -notin @('GX18', 'Evo3')) { $perfilExportacion = 'GX18' }

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
            '-KbPath', $rutaKb,
            '-GeneXusExportProfile', $perfilExportacion
        )
        if ($codigoSelectivo -ne 0) {
            if (Preguntar-Continuar -Motivo (Obtener-MotivoError)) { exit 2 } else { exit 3 }
        }

        Write-Host ''
        Write-Host ("Revalidando completitud (ciclo " + $ciclo + " de " + $maximoCiclos + ")...") -ForegroundColor Cyan
        $codigoRevalidacion = Invocar-Script -RutaScript $rutaScriptValidacion -Argumentos @('-ConfigPath', $rutaConfiguracion, '-XpzPath', $XpzActivo, '-ManifiestoPath', $rutaManifiestoEjecucion, '-Scope', $Scope)
        $nuevoReporte = Obtener-ReporteValidacionMasReciente -DirectorioLogs $rutaDirectorioLogs -RutaXpz $XpzActivo -RaizRepositorio $raizRepositorio -EjecucionId ([string]$manifiestoEjecucion.ejecucionId)
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
            if (Preguntar-Continuar -Motivo 'La validacion no produjo progreso tras la exportacion selectiva.') { exit 2 } else { exit 3 }
        }
        if ($ciclo -eq $maximoCiclos) {
            if (Preguntar-Continuar -Motivo ('Se alcanzo el limite de ' + $maximoCiclos + ' ciclos y quedan objetos pendientes de exportacion.')) { exit 2 } else { exit 3 }
        }
        $signaturaAnterior = $signaturaActual
        $reporteSeleccionado = $nuevoReporte
    }

    exit 1
} catch {
    Write-Host ''
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
