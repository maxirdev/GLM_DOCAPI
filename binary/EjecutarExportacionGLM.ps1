# Orquestador de exportacion completa, validacion y complementos XPZ (contextual).

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Repositorio,
    [Parameter(Mandatory = $true)][string]$ClienteId,
    [Parameter(Mandatory = $true)][ValidateSet('comercial', 'erp')][string]$Modulo,
    [Parameter(Mandatory = $true)][string]$AmbienteId,
    [switch]$ConfirmarExportacionCompleta,
    [ValidateSet('abort', 'continue')][string]$PoliticaPendientes = 'abort'
)

$ErrorActionPreference = 'Stop'
$raizRepositorio = [System.IO.Path]::GetFullPath($Repositorio)
$rutaConfiguracion = Join-Path $raizRepositorio 'configuracion.json'
$rutaProyectoCompletoGX18 = Join-Path $raizRepositorio 'binary\ExportarXPZ.msbuild'
$rutaProyectoCompletoEvo3 = Join-Path $raizRepositorio 'binary\ExportarXPZEvo3.msbuild'
$rutaProyectoSelectivoGX18 = Join-Path $raizRepositorio 'binary\ExportarXPZSelectivo.msbuild'
$rutaProyectoSelectivoEvo3 = Join-Path $raizRepositorio 'binary\ExportarXPZSelectivoEvo3.msbuild'
$rutaScriptProgreso = Join-Path $raizRepositorio 'binary\ExportarXPZProgreso.ps1'
$rutaScriptValidacion = Join-Path $raizRepositorio 'binary\ValidarXPZ.ps1'
$rutaScriptSelectivo = Join-Path $raizRepositorio 'binary\ExportarXPZSelectivo.ps1'
$rutaPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$maximoCiclos = 5

. (Join-Path $PSScriptRoot 'GLMUtilidades.ps1')
. (Join-Path $PSScriptRoot 'CargarConfiguracion.ps1')
. (Join-Path $PSScriptRoot 'ManifiestoEjecucion.ps1')

Inicializar-ConsolaUtf8

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

$manifiestoExportacion = $null
try {
    if (-not (Test-Path -LiteralPath $rutaConfiguracion -PathType Leaf)) {
        throw 'No existe configuracion.json. Ejecute primero el lanzador para crear el modelo.'
    }

    $contexto = Cargar-Configuracion -ConfigPath $rutaConfiguracion -ClienteId $ClienteId -Modulo $Modulo -AmbienteId $AmbienteId
    $rutaDirectorioXpz = $contexto.DirectorioXpz
    $rutaDirectorioLogs = $contexto.DirectorioLogs
    Asegurar-Directorio -Ruta $rutaDirectorioLogs
    Asegurar-Directorio -Ruta $rutaDirectorioXpz

    $configuracion = Leer-ConfiguracionCruda -ConfigPath $rutaConfiguracion
    $onlyModuleAPIGLM = Obtener-OnlyModuleAPIGLM -Configuracion $configuracion

        if (-not $onlyModuleAPIGLM -and -not $ConfirmarExportacionCompleta) {
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

    $rutaGeneXus = [string]$contexto.Herramientas.GeneXusProgramDir
    $rutaKb = [string]$contexto.KbPath
    $rutaMsbuild = [string]$contexto.Herramientas.MsbuildPath
    $perfilExportacion = [string]$contexto.Herramientas.GeneXusExportProfile
    if ($perfilExportacion -notin @('GX18', 'Evo3')) { $perfilExportacion = 'GX18' }
    $rutaMsbuild = Resolver-RutaMsbuildPorPerfil -RutaConfigurada $rutaMsbuild -Perfil $perfilExportacion
    $rutaProyectoCompleto = if ($perfilExportacion -eq 'Evo3') { $rutaProyectoCompletoEvo3 } else { $rutaProyectoCompletoGX18 }
    $rutaProyectoSelectivo = if ($perfilExportacion -eq 'Evo3') { $rutaProyectoSelectivoEvo3 } else { $rutaProyectoSelectivoGX18 }

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
        -GeneXusExportProfile $perfilExportacion `
        -Modulo $Modulo `
        -TargetName $targetExportacion 2>&1 | Out-Host
    $codigoExportacion = $LASTEXITCODE
    $validacionXpz = Test-XpzValido -Ruta $rutaXpzNuevo
    if ($codigoExportacion -ne 0 -or -not $validacionXpz.Valid) {
        throw ('La exportacion completa fallo. Revise el log: ' + $rutaLogExportacion)
    }
    if ($onlyModuleAPIGLM -and $perfilExportacion -eq 'Evo3') {
        $validacionRaiz = Test-XpzContieneObjeto -Ruta $rutaXpzNuevo -FullyQualifiedName 'APIGLM.APIGLMMain'
        if (-not $validacionRaiz.Valid) {
            throw ('La exportacion de APIGLM genero un XPZ incompleto: ' + $validacionRaiz.Error + '. Revise el log: ' + $rutaLogExportacion)
        }
    }

    Write-Host ('XPZ exportado: ' + $rutaXpzNuevo) -ForegroundColor Green
    Write-Host ('El XPZ recien exportado pasa a ser el principal mas reciente del ambiente ' + $contexto.ContextId + '.') -ForegroundColor DarkGray

    $manifiestoExportacion = Crear-ManifiestoEjecucion -Xpz $rutaXpzNuevo -FullyQualifiedNames @() -Contexto $contexto
    $rutaManifiestoExportacion = $manifiestoExportacion.Ruta

    $signaturaAnterior = ''
    for ($ciclo = 1; $ciclo -le $maximoCiclos; $ciclo++) {
        Write-Host ''
        Write-Host ''
        Write-Host ("[2/3] Validando completitud del XPZ (ciclo $ciclo de $maximoCiclos)...") -ForegroundColor Cyan
        & $rutaPowerShell -NoProfile -ExecutionPolicy Bypass -File $rutaScriptValidacion `
            -ConfigPath $rutaConfiguracion `
            -ManifiestoPath $rutaManifiestoExportacion 2>&1 | Out-Host
        $codigoValidacion = $LASTEXITCODE
        $seleccionReporte = Obtener-ReporteValidacionMasReciente -DirectorioLogs $rutaDirectorioLogs -RutaXpz $rutaXpzNuevo -RaizRepositorio $raizRepositorio -EjecucionId ([string]$manifiestoExportacion.Datos.ejecucionId)
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
            if ($PoliticaPendientes -eq 'continue') { exit 2 } else { exit 1 }
        }
        if ($ciclo -eq $maximoCiclos) {
            Write-Host ('Se alcanzo el limite de ' + $maximoCiclos + ' ciclos. Pendientes: ' + $signaturaActual) -ForegroundColor Yellow
            if ($PoliticaPendientes -eq 'continue') { exit 2 } else { exit 1 }
        }

        $signaturaAnterior = $signaturaActual
        Write-Host ''
        Write-Host ("[3/3] Exportando complemento selectivo (ciclo $ciclo de $maximoCiclos)...") -ForegroundColor Cyan
        & $rutaPowerShell -NoProfile -ExecutionPolicy Bypass -File $rutaScriptSelectivo `
            -ConfigPath $rutaConfiguracion `
            -ReportePath $seleccionReporte.Ruta `
            -MsbuildPath $rutaMsbuild `
            -ProjectFile $rutaProyectoSelectivo `
            -GxProgramDir $rutaGeneXus `
            -KbPath $rutaKb `
            -GeneXusExportProfile $perfilExportacion `
            -ManifiestoPath $rutaManifiestoExportacion 2>&1 | Out-Host
        $codigoSelectivo = $LASTEXITCODE
        if ($codigoSelectivo -ne 0) {
            if ($PoliticaPendientes -eq 'continue') { exit 2 }
            throw 'La exportacion selectiva fallo. Revise el log generado por el script.'
        }
    }

    exit 1
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if ($manifiestoExportacion) {
        try { Eliminar-ManifiestoEjecucion -RutaManifiesto $manifiestoExportacion.Ruta } catch { }
    }
}
