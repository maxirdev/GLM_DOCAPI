[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)][int]$Port = 0,
    [Parameter(Mandatory = $false)][string]$RepositoryRoot = '',
    [Parameter(Mandatory = $false)][string]$ConfigPath = '',
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
} else {
    $RepositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $RepositoryRoot 'configuracion.json'
}

. (Join-Path $PSScriptRoot 'GLMUtilidades.ps1')
. (Join-Path $PSScriptRoot 'CargarConfiguracion.ps1')
. (Join-Path $PSScriptRoot 'AnalizarServicio.ps1')
. (Join-Path $PSScriptRoot 'CargarMultiXPZ.ps1')
. (Join-Path $PSScriptRoot 'ControlVersiones.ps1')
. (Join-Path $PSScriptRoot 'ManifiestoEjecucion.ps1')

Inicializar-ConsolaUtf8

$script:SessionToken = [Guid]::NewGuid().ToString('N')
$script:PanelServerVersion = '20260820-msbuild-timeout-cleanup-v5'
$script:ConfigurationRaw = $null
$script:ConfigurationErrors = New-Object System.Collections.Generic.List[string]
$script:ActiveContext = $null
$script:ActiveXpz = $null
$script:XpzOverride = $false
$script:CurrentWork = $null
$script:LastFinishedWork = $null
$script:Listener = $null
$script:WorkOutputTimestampCache = @{}
$script:XpzSha256ProcesadoCache = $null

function Read-PanelConfiguration {
    try {
        if (-not (Test-Path -LiteralPath $ConfigPath)) {
            throw ('No se encontro el archivo de configuracion: ' + $ConfigPath)
        }
        $script:ConfigurationRaw = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        Validar-ConfiguracionMulticliente -ConfiguracionRaw $script:ConfigurationRaw -RaizRepositorio $RepositoryRoot -ConfigPath $ConfigPath | Out-Null
    } catch {
        $script:ConfigurationErrors.Add($_.Exception.Message)
    }
}

function Get-ConfiguredContexts {
    $contexts = New-Object System.Collections.Generic.List[object]
    if ($null -eq $script:ConfigurationRaw -or $null -eq $script:ConfigurationRaw.clientes) {
        return @()
    }
    foreach ($client in @($script:ConfigurationRaw.clientes)) {
        foreach ($environment in @($client.ambientes)) {
            $contexts.Add([pscustomobject]@{
                clienteId = [string]$client.id
                clienteNombre = [string]$client.nombre
                ambienteId = [string]$environment.id
                ambienteNombre = Obtener-NombreAmbienteCanonico -Tipo (Clasificar-TipoAmbiente -Tipo ([string]$environment.tipo))
                ambienteTipo = Clasificar-TipoAmbiente -Tipo ([string]$environment.tipo)
                contextId = ([string]$client.id + '/' + [string]$environment.id)
            })
        }
    }
    return $contexts.ToArray()
}

function Get-ActiveXpzCandidates {
    if ($null -eq $script:ActiveContext) { return @() }
    return @(Obtener-XpzPrincipalesDesdeDirectorio -DirectorioXpz $script:ActiveContext.DirectorioXpz)
}

function Get-XpzSha256Procesado {
    if ($null -eq $script:ActiveContext) { return '' }
    $rutaControl = $script:ActiveContext.RutaControl
    if ([string]::IsNullOrWhiteSpace($rutaControl) -or -not (Test-Path -LiteralPath $rutaControl -PathType Leaf)) { return '' }
    try {
        $marca = (Get-Item -LiteralPath $rutaControl).LastWriteTimeUtc.Ticks
        if ($script:XpzSha256ProcesadoCache -and $script:XpzSha256ProcesadoCache.Marca -eq $marca) {
            return $script:XpzSha256ProcesadoCache.Valor
        }
        $control = Leer-ControlVersiones -RutaControl $rutaControl
        $sha = [string](Obtener-PropiedadControlVersiones -Objeto $control -Nombre 'xpzSha256')
        if ([string]::IsNullOrWhiteSpace($sha)) { $sha = '' }
        $script:XpzSha256ProcesadoCache = @{ Marca = $marca; Valor = $sha }
        return $sha
    } catch { return '' }
}

function Convert-XpzForResponse {
    param([Parameter(Mandatory = $true)]$Xpz)
    $procesado = $false
    $shaProcesado = Get-XpzSha256Procesado
    if (-not [string]::IsNullOrWhiteSpace($shaProcesado) -and -not [string]::IsNullOrWhiteSpace([string]$Xpz.Ruta) -and (Test-Path -LiteralPath $Xpz.Ruta -PathType Leaf)) {
        try { $procesado = (Obtener-Sha256Archivo -Ruta $Xpz.Ruta) -ceq $shaProcesado } catch { $procesado = $false }
    }
    return [pscustomobject]@{
        nombre = $Xpz.Nombre
        ruta = $Xpz.Ruta
        fecha = $Xpz.Fecha.ToUniversalTime().ToString('o')
        principal = [bool]$Xpz.EsPrincipal
        activo = ($null -ne $script:ActiveXpz -and $script:ActiveXpz.Ruta -eq $Xpz.Ruta)
        procesado = $procesado
    }
}

function Test-WorkInProgress {
    return ($null -ne $script:CurrentWork -and [string]$script:CurrentWork.estado -in @('QUEUED', 'RUNNING'))
}

function Get-PanelOperationTimeoutSeconds {
    $defaultTimeout = 300
    if ($null -eq $script:ConfigurationRaw -or $null -eq $script:ConfigurationRaw.panel) { return $defaultTimeout }
    $rawValue = $script:ConfigurationRaw.panel.timeoutOperacionSegundos
    $timeout = 0
    if ([int]::TryParse([string]$rawValue, [ref]$timeout) -and $timeout -gt 0) { return $timeout }
    return $defaultTimeout
}

function Get-PanelProcessTreeIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$RootProcessId
    )

    $ids = New-Object System.Collections.Generic.List[int]
    $pending = New-Object System.Collections.Generic.Queue[int]
    $pending.Enqueue($RootProcessId)
    $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $rootExists = @($processes | Where-Object { [int]$_.ProcessId -eq $RootProcessId }).Count -gt 0
    if ($rootExists) { [void]$ids.Add($RootProcessId) }

    while ($pending.Count -gt 0) {
        $parentId = $pending.Dequeue()
        foreach ($process in @($processes | Where-Object { [int]$_.ParentProcessId -eq $parentId })) {
            $childId = [int]$process.ProcessId
            if (-not $ids.Contains($childId)) {
                [void]$ids.Add($childId)
                $pending.Enqueue($childId)
            }
        }
    }

    return @($ids)
}

function Stop-PanelProcessTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$RootProcessId
    )

    if ($RootProcessId -le 0) { return @() }
    $knownIds = @(Get-PanelProcessTreeIds -RootProcessId $RootProcessId)
    if ($knownIds.Count -eq 0) { return @() }

    try {
        & taskkill.exe /PID $RootProcessId /T /F 2>&1 | Out-Null
    } catch { }

    # taskkill termina el arbol en condiciones normales. La segunda pasada
    # cubre procesos que hayan aparecido entre el relevamiento y el kill.
    $remainingIds = @()
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        Start-Sleep -Milliseconds 150
        $remainingIds = @(Get-PanelProcessTreeIds -RootProcessId $RootProcessId | Where-Object { $_ -ne $PID })
        if ($remainingIds.Count -eq 0) { break }
        foreach ($processId in ($remainingIds | Sort-Object -Descending)) {
            Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
        }
    }
    return @($remainingIds)
}

function Stop-PanelOrphanedMsbuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Context
    )

    $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) { return @() }
    $liveIds = @{}
    foreach ($process in $processes) { $liveIds[[int]$process.ProcessId] = $true }
    $markers = @(
        [string]$RepositoryRoot,
        [string]$Context.KbPath,
        'ExportarXPZ',
        'GenerarPdfServicios',
        'GenerarDocumento'
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $terminated = New-Object System.Collections.Generic.List[int]
    foreach ($process in @($processes | Where-Object { [string]$_.Name -ieq 'MSBuild.exe' })) {
        $commandLine = [string]$process.CommandLine
        if ([string]::IsNullOrWhiteSpace($commandLine) -or -not (@($markers | Where-Object { $commandLine.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -gt 0)) { continue }
        $parentId = [int]$process.ParentProcessId
        if ($parentId -gt 0 -and $liveIds.ContainsKey($parentId)) { continue }
        try {
            & taskkill.exe /PID ([int]$process.ProcessId) /T /F 2>&1 | Out-Null
            [void]$terminated.Add([int]$process.ProcessId)
        } catch { }
    }
    return @($terminated)
}

function Prepare-PanelOperationLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Context
    )

    # La limpieza se realiza en el proceso padre, antes de crear los archivos
    # de redireccion STDOUT/STDERR de la nueva operación. Los procesos hijos
    # no deben limpiar este directorio porque podrían borrar su propio .err.
    Stop-PanelOrphanedMsbuild -Context $Context | Out-Null
    Limpiar-LogsEjecucion -DirectorioLogs $Context.DirectorioLogs
}

function Get-WorkStatusFromExitCode {
    param([Parameter(Mandatory = $true)][int]$ExitCode)
    switch ($ExitCode) {
        0 { return 'COMPLETED' }
        2 { return 'PARTIAL' }
        3 { return 'ABORTED' }
        default { return 'FAILED' }
    }
}

function Get-VisibleWorkStatus {
    param(
        [Parameter(Mandatory = $true)][string]$TechnicalStatus,
        [Parameter(Mandatory = $false)][AllowNull()][int]$ExitCode
    )
    if ($TechnicalStatus -in @('QUEUED', 'RUNNING')) { return 'EN PROCESO' }
    switch ($TechnicalStatus) {
        'COMPLETED' { return 'COMPLETADO' }
        'PARTIAL' { return 'COMPLETADO PARCIALMENTE' }
        'ABORTED' { return 'CANCELADO' }
        default { return 'ERROR' }
    }
}

function Get-LatestValidXpz {
    if ($null -eq $script:ActiveContext) { return $null }
    foreach ($candidate in @(Get-ActiveXpzCandidates | Sort-Object Fecha -Descending)) {
        try {
            $validation = Test-XpzValido -Ruta $candidate.Ruta
            if ($validation.Valid) { return $candidate }
        } catch { }
    }
    return $null
}

function Get-TimestampedWorkLines {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $rawLines = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
    $key = [System.IO.Path]::GetFullPath($Path)
    if (-not $script:WorkOutputTimestampCache.ContainsKey($key) -or $script:WorkOutputTimestampCache[$key].Count -gt $rawLines.Count) {
        $script:WorkOutputTimestampCache[$key] = New-Object System.Collections.Generic.List[string]
    }
    $cached = $script:WorkOutputTimestampCache[$key]
    for ($index = $cached.Count; $index -lt $rawLines.Count; $index++) {
        $line = [string]$rawLines[$index]
        if ($line -match '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}\]') {
            [void]$cached.Add($line)
        } else {
            [void]$cached.Add(('[' + (Get-Date).ToString('yyyy-MM-dd HH:mm') + '] ' + $line))
        }
    }
    return @($cached.ToArray())
}

function Get-WorkTail {
    param([Parameter(Mandatory = $true)]$Work)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($Work.stdoutPath, $Work.stderrPath)) {
        if ([string]::IsNullOrWhiteSpace([string]$path)) { continue }
        foreach ($line in @(Get-TimestampedWorkLines -Path $path | Select-Object -Last 20)) { [void]$lines.Add([string]$line) }
    }
    return @($lines | Select-Object -Last 20)
}

function Get-WorkFullOutput {
    param([Parameter(Mandatory = $true)]$Work)
    $sections = New-Object System.Collections.Generic.List[string]
    foreach ($definition in @(
        [pscustomobject]@{ Nombre = 'STDOUT'; Ruta = $Work.stdoutPath },
        [pscustomobject]@{ Nombre = 'STDERR'; Ruta = $Work.stderrPath }
    )) {
        [void]$sections.Add('===== ' + $definition.Nombre + ' =====')
        if (Test-Path -LiteralPath $definition.Ruta -PathType Leaf) {
            [void]$sections.Add((Get-TimestampedWorkLines -Path $definition.Ruta) -join [Environment]::NewLine)
        }
    }
    return ($sections -join [Environment]::NewLine)
}

function Get-WorkRawOutput {
    param([Parameter(Mandatory = $true)]$Work)
    $sections = New-Object System.Collections.Generic.List[string]
    foreach ($definition in @(
        [pscustomobject]@{ Nombre = 'STDOUT'; Ruta = $Work.stdoutPath },
        [pscustomobject]@{ Nombre = 'STDERR'; Ruta = $Work.stderrPath }
    )) {
        [void]$sections.Add('===== ' + $definition.Nombre + ' =====')
        if (Test-Path -LiteralPath $definition.Ruta -PathType Leaf) {
            [void]$sections.Add((Get-Content -LiteralPath $definition.Ruta -Raw -ErrorAction SilentlyContinue).TrimEnd())
        }
    }
    return ($sections -join [Environment]::NewLine)
}

function Get-WorkHeartbeatUtc {
    param([Parameter(Mandatory = $true)]$Work)
    $heartbeat = $null
    try { $heartbeat = [datetime]::Parse([string]$Work.ultimaActividad).ToUniversalTime() } catch { }
    if ($null -eq $heartbeat) {
        try { $heartbeat = [datetime]::Parse([string]$Work.inicio).ToUniversalTime() } catch { }
    }
    return $heartbeat
}

function Complete-WorkAsAborted {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Work,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    $Work.codigoSalida = 3
    $Work.estado = 'ABORTED'
    $Work.error = $Reason
    $Work.fin = (Get-Date).ToUniversalTime().ToString('o')
    $Work.progreso = [pscustomobject]@{ indeterminado = $false; porcentaje = 100 }
    $fullOutput = Get-WorkFullOutput -Work $Work
    if ($Work.PSObject.Properties['operationLogPath'] -and -not [string]::IsNullOrWhiteSpace([string]$Work.operationLogPath)) {
        [System.IO.File]::WriteAllText($Work.operationLogPath, $fullOutput, (New-Object System.Text.UTF8Encoding($false)))
    }
    if ($Work.PSObject.Properties['operationManifestPath'] -and -not [string]::IsNullOrWhiteSpace([string]$Work.operationManifestPath)) {
        Write-OperationRecord -Work $Work
    }
    $script:LastFinishedWork = $Work
    $script:CurrentWork = $null
    return $Work
}

function Get-WorkOutputErrors {
    param(
        [Parameter(Mandatory = $true)][string]$Output
    )

    return @($Output -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object {
        $_ -and (
            $_ -match '(?i)^\s*(ERROR\b|FATAL\b|EXCEPTION\b|MSB\d{4}\b)' -or
            $_ -match '(?i)\b(ERROR|FATAL|EXCEPTION)\s*:' -or
            $_ -match '(?i)\bGenerarOpenApi:\s*' -or
            $_ -match '(?i)\b(RESULTADO|ESTADO)\s*:\s*(ERROR|FAILED|FATAL)\b'
        )
    } | Select-Object -Unique)
}

function Get-OperationType {
    param([Parameter(Mandatory = $true)][string]$Operation)
    return $Operation
}

function Get-OperationSeverity {
    param([Parameter(Mandatory = $true)][string]$TechnicalStatus)
    switch ($TechnicalStatus) {
        'PARTIAL' { return 'WARNING' }
        'COMPLETED' { return 'INFO' }
        'ABORTED' { return 'WARNING' }
        'QUEUED' { return 'INFO' }
        'RUNNING' { return 'INFO' }
        default { return 'ERROR' }
    }
}

function Write-OperationRecord {
    param([Parameter(Mandatory = $true)]$Work)
    $record = [ordered]@{
        schemaVersion = 1
        operationId = $Work.operationId
        contextId = $Work.contextId
        tipo = Get-OperationType -Operation $Work.operacion
        severidad = Get-OperationSeverity -TechnicalStatus $Work.estado
        xpz = [ordered]@{ nombre = $Work.xpzNombre; sha256 = $Work.xpzSha256 }
        inicio = $Work.inicio
        fin = $Work.fin
        estadoTecnico = $Work.estado
        estadoVisible = Get-VisibleWorkStatus -TechnicalStatus $Work.estado -ExitCode $Work.codigoSalida
        codigoSalida = $Work.codigoSalida
        warnings = @($Work.warnings)
        error = $Work.error
        rutaGenerada = if ($Work.PSObject.Properties['rutaGenerada']) { $Work.rutaGenerada } else { $null }
        logNombre = $Work.operationLogName
    }
    $json = $record | ConvertTo-Json -Depth 10
    $null = $json | ConvertFrom-Json
    [System.IO.File]::WriteAllText($Work.operationManifestPath, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-PanelMutationOperation {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $false)]$Xpz,
        [Parameter(Mandatory = $false)][string]$TechnicalStatus = 'COMPLETED',
        [Parameter(Mandatory = $false)][AllowNull()][int]$ExitCode = 0,
        [Parameter(Mandatory = $false)][string[]]$Warnings = @(),
        [Parameter(Mandatory = $false)][AllowNull()][string]$ErrorMessage = $null,
        [Parameter(Mandatory = $false)][string[]]$Output = @()
    )
    $operationsDirectory = Join-Path $Context.DirectorioLogs 'operaciones'
    New-Item -ItemType Directory -Path $operationsDirectory -Force | Out-Null
    $operationId = [Guid]::NewGuid().ToString('N')
    $logName = $operationId + '.log'
    $logPath = Join-Path $operationsDirectory $logName
    $manifestPath = Join-Path $operationsDirectory ($operationId + '.json')
    $start = (Get-Date).ToUniversalTime().ToString('o')
    $work = [pscustomobject]@{
        operationId = $operationId
        contextId = $Context.ContextId
        operacion = $Operation
        estado = $TechnicalStatus
        codigoSalida = $ExitCode
        inicio = $start
        fin = $start
        warnings = @($Warnings)
        error = $ErrorMessage
        operationLogName = $logName
        operationLogPath = $logPath
        operationManifestPath = $manifestPath
        xpzNombre = if ($Xpz) { [string]$Xpz.Nombre } else { $null }
        xpzSha256 = if ($Xpz -and (Test-Path -LiteralPath $Xpz.Ruta -PathType Leaf)) { Obtener-Sha256Archivo -Ruta $Xpz.Ruta } else { $null }
    }
    [System.IO.File]::WriteAllText($logPath, (($Output -join [Environment]::NewLine)), (New-Object System.Text.UTF8Encoding($false)))
    Write-OperationRecord -Work $work
    return $work
}

function New-ImmediateFailedWork {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$ErrorMessage,
        [Parameter(Mandatory = $false)]$Xpz
    )
    $work = Write-PanelMutationOperation -Operation $Operation -Context $Context -Xpz $Xpz -TechnicalStatus 'FAILED' -ExitCode 1 -ErrorMessage $ErrorMessage -Output @($ErrorMessage)
    $work | Add-Member -NotePropertyName id -NotePropertyValue $work.operationId
    $work | Add-Member -NotePropertyName progreso -NotePropertyValue ([pscustomobject]@{ indeterminado = $false; porcentaje = 100 })
    $work | Add-Member -NotePropertyName stdoutPath -NotePropertyValue $null
    $work | Add-Member -NotePropertyName stderrPath -NotePropertyValue $null
    $script:LastFinishedWork = $work
    return $work
}

function Get-PublicWork {
    param([Parameter(Mandatory = $true)]$Work)
    [pscustomobject]@{
        id = $Work.id
        contextId = $Work.contextId
        operacion = $Work.operacion
        estado = $Work.estado
        estadoTecnico = $Work.estado
        estadoVisible = Get-VisibleWorkStatus -TechnicalStatus $Work.estado -ExitCode $Work.codigoSalida
        logNombre = $Work.operationLogName
        operationId = $Work.operationId
        inicio = $Work.inicio
        fin = $Work.fin
        codigoSalida = $Work.codigoSalida
        progreso = $Work.progreso
        warnings = @($Work.warnings)
        error = $Work.error
        rutaGenerada = if ($Work.PSObject.Properties['rutaGenerada']) { $Work.rutaGenerada } else { $null }
        ultimasLineas = @(Get-WorkTail -Work $Work)
    }
}

function Update-CurrentWork {
    if ($null -eq $script:CurrentWork) { return }
    $work = $script:CurrentWork
    if ([string]$work.estado -notin @('QUEUED', 'RUNNING')) { return }
    $ultimaActividad = Get-WorkHeartbeatUtc -Work $work
    if ($null -ne $ultimaActividad -and ((Get-Date).ToUniversalTime() - $ultimaActividad).TotalSeconds -ge (Get-PanelOperationTimeoutSeconds)) {
        $rootProcessId = 0
        try { $rootProcessId = [int]$work.process.Id } catch { }
        $remainingIds = if ($rootProcessId -gt 0) { @(Stop-PanelProcessTree -RootProcessId $rootProcessId) } else { @(1) }
        if ($remainingIds.Count -eq 0) {
            if ($script:ActiveContext) { Stop-PanelOrphanedMsbuild -Context $script:ActiveContext | Out-Null }
                $timeout = Get-PanelOperationTimeoutSeconds
                $timeoutReason = ('La operaci' + [char]0xF3 + 'n super' + [char]0xF3 + ' el timeout configurado de ' + $timeout + ' segundos.')
                Complete-WorkAsAborted -Work $work -Reason $timeoutReason | Out-Null
            return
        }
        # Si todavía queda algún descendiente, se conserva el trabajo activo
        # para que la siguiente consulta vuelva a intentar el cierre del árbol.
        $work.estado = 'RUNNING'
        $work.progreso = [pscustomobject]@{ indeterminado = $true; porcentaje = $null }
        return
    }
    if (-not $work.process.HasExited) {
        $work.estado = 'RUNNING'
        $work.progreso = [pscustomobject]@{ indeterminado = $true; porcentaje = $null }
        return
    }

    $work.codigoSalida = [int]$work.process.ExitCode
    $work.estado = Get-WorkStatusFromExitCode -ExitCode $work.codigoSalida
    $fullOutput = Get-WorkFullOutput -Work $work
    $openApiPathMatch = [regex]::Match($fullOutput, '(?im)OPENAPI_GENERADO:\s*(.+)$')
    if ($openApiPathMatch.Success) {
        $work | Add-Member -NotePropertyName rutaGenerada -NotePropertyValue $openApiPathMatch.Groups[1].Value.Trim() -Force
    }
    # La salida con timestamps es solo para presentación. La clasificación
    # debe analizar el texto original producido por exportación/validación.
    $rawOutput = Get-WorkRawOutput -Work $work
    $outputErrors = @(Get-WorkOutputErrors -Output $rawOutput)
    if ($outputErrors.Count -gt 0) {
        if ($work.estado -ne 'FAILED') {
            $work.codigoSalida = 1
            $work.estado = 'FAILED'
        }
        if ([string]::IsNullOrWhiteSpace([string]$work.error)) {
            $work.error = ($outputErrors -join ' | ')
        }
    }
    if ([string]$work.operacion -eq 'EXPORTAR_XPZ') {
        $confirmoValidacionFinal = $rawOutput -match '(?im)^XPZ completo y sin exportaciones adicionales\.$'
        if ($work.codigoSalida -eq 0 -and -not $confirmoValidacionFinal) {
            $work.codigoSalida = 1
            $work.estado = 'FAILED'
            $work.error = 'La exportacion termino sin confirmar la validacion final del XPZ.'
        }
        $validXpz = if ($work.codigoSalida -eq 0) { Get-LatestValidXpz } else { $null }
        if ($null -ne $validXpz) {
            $script:ActiveXpz = $validXpz
            $script:XpzOverride = $false
        } else {
            $script:ActiveXpz = $null
            $script:XpzOverride = $false
            if ($work.codigoSalida -eq 0) {
                $work.codigoSalida = 1
                $work.estado = 'FAILED'
                $work.error = 'La exportacion termino sin producir un XPZ valido y utilizable.'
            }
        }
    }
    $work.fin = (Get-Date).ToUniversalTime().ToString('o')
    $work.progreso = [pscustomobject]@{ indeterminado = $false; porcentaje = 100 }
    [System.IO.File]::WriteAllText($work.operationLogPath, $fullOutput, (New-Object System.Text.UTF8Encoding($false)))
    if ($work.codigoSalida -eq 3) { $work.error = 'Operacion abortada.' }
    if ($work.codigoSalida -eq 1 -and [string]::IsNullOrWhiteSpace([string]$work.error)) { $work.error = 'El proceso hijo termino con errores.' }
    Write-OperationRecord -Work $work
    $script:LastFinishedWork = $work
    $script:CurrentWork = $null
}

function Cancel-CurrentWork {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$JobId
    )

    Update-CurrentWork
    $work = $script:CurrentWork
    if ($null -eq $work -or [string]$work.id -ne $JobId -or [string]$work.estado -notin @('QUEUED', 'RUNNING')) {
        throw 'No existe una operación activa con ese identificador.'
    }

    $rootProcessId = 0
    if ($work.process) {
        try { $rootProcessId = [int]$work.process.Id } catch { $rootProcessId = 0 }
    }
    if ($rootProcessId -le 0) { throw 'La operación no tiene un proceso raíz cancelable.' }

    $remainingIds = @(Stop-PanelProcessTree -RootProcessId $rootProcessId)
    if ($remainingIds.Count -gt 0) {
        throw ('No se pudo terminar completamente el árbol de procesos: ' + ($remainingIds -join ', ') + '.')
    }

    return Complete-WorkAsAborted -Work $work -Reason ('Operaci' + [char]0xF3 + 'n cancelada por el usuario.')
}

function Quote-ProcessArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Start-ValidationWork {
    param([Parameter(Mandatory = $false)]$RequestBody)
    if ($null -eq $script:ActiveContext) { throw 'No hay un contexto activo.' }
    if ($RequestBody -and $RequestBody.nombre) {
        $selected = @(Get-ActiveXpzCandidates | Where-Object { $_.Nombre -ceq [string]$RequestBody.nombre })
        if ($selected.Count -ne 1) { throw 'El XPZ indicado no pertenece al contexto activo.' }
        $script:ActiveXpz = $selected[0]
        $script:XpzOverride = $true
    }
    if ($null -eq $script:ActiveXpz) { throw 'No hay un XPZ activo en el contexto.' }
    Prepare-PanelOperationLogs -Context $script:ActiveContext
    $jobsDirectory = Join-Path $script:ActiveContext.DirectorioLogs 'panel-jobs'
    New-Item -ItemType Directory -Path $jobsDirectory -Force | Out-Null
    $manifestBase = Join-Path $jobsDirectory ('validation-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $manifest = Crear-ManifiestoEjecucion -Xpz $script:ActiveXpz.Ruta -FullyQualifiedNames @() -DirectorioBase $manifestBase -Contexto $script:ActiveContext
    $scriptPath = Join-Path $RepositoryRoot 'binary\ValidarXPZ.ps1'
    $argumentValues = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath, '-ConfigPath', $ConfigPath, '-XpzPath', $script:ActiveXpz.Ruta, '-ManifiestoPath', $manifest.Ruta)
    return Start-PanelChildWork -Operation 'VALIDAR_XPZ' -ScriptPath $scriptPath -ArgumentValues $argumentValues -Context $script:ActiveContext
}

function Start-PdfGenerationWork {
    param([Parameter(Mandatory = $true)]$RequestBody)
    if ($null -eq $script:ActiveContext -or $null -eq $script:ActiveXpz) { throw 'No hay contexto y XPZ activos.' }
    if ($RequestBody.confirmRestart -ne $true) { throw 'La regeneracion requiere confirmRestart=true.' }
    if ($null -eq $RequestBody.PSObject.Properties['xpz'] -or $null -eq $RequestBody.xpz) {
        throw 'PRECONDICION_XPZ: La confirmacion requiere nombre y SHA-256 del XPZ.'
    }
    $confirmedXpzName = [string]$RequestBody.xpz.nombre
    $confirmedXpzHash = [string]$RequestBody.xpz.sha256
    $currentXpzHash = if (Test-Path -LiteralPath $script:ActiveXpz.Ruta -PathType Leaf) { Obtener-Sha256Archivo -Ruta $script:ActiveXpz.Ruta } else { '' }
    if ($confirmedXpzName -cne [string]$script:ActiveXpz.Nombre -or
        $confirmedXpzHash -notmatch '^[0-9a-fA-F]{64}$' -or
        $confirmedXpzHash -ine $currentXpzHash) {
        throw 'PRECONDICION_XPZ: El XPZ activo o su SHA-256 cambio; confirme nuevamente.'
    }
    $scope = [string]$RequestBody.scope
    if ([string]::IsNullOrWhiteSpace($scope)) { $scope = 'BATCH' }
    if ($scope -notin @('BATCH', 'INDIVIDUAL')) { throw 'scope debe ser BATCH o INDIVIDUAL.' }
    $selectedNames = @()
    if ($scope -eq 'INDIVIDUAL') {
        $selectedName = [string]$RequestBody.fullyQualifiedName
        if ([string]::IsNullOrWhiteSpace($selectedName)) { throw 'INDIVIDUAL requiere fullyQualifiedName.' }
        $index = Cargar-IndiceMultiXPZ -RutaXpzPrincipal $script:ActiveXpz.Ruta
        $knownNames = @(Obtener-ServiciosHttpDesdeIndice -Indice $index | ForEach-Object { [string]$_.proceso })
        if ($knownNames -notcontains $selectedName) { throw ('El FQN no pertenece al inventario activo: ' + $selectedName) }
        if (@($script:ActiveContext.ServiciosIgnorados) -contains $selectedName) { throw ('El servicio esta ignorado: ' + $selectedName) }
        $selectedNames = @($selectedName)
    }
    Prepare-PanelOperationLogs -Context $script:ActiveContext
    $jobsDirectory = Join-Path $script:ActiveContext.DirectorioLogs 'panel-jobs'
    New-Item -ItemType Directory -Path $jobsDirectory -Force | Out-Null
    $manifest = Crear-ManifiestoEjecucion -Xpz $script:ActiveXpz.Ruta -FullyQualifiedNames $selectedNames -DirectorioBase (Join-Path $jobsDirectory ('pdf-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))) -Contexto $script:ActiveContext
    $scriptPath = Join-Path $RepositoryRoot 'binary\GenerarPdfPanel.ps1'
    $arguments = @('-File', $scriptPath, '-Repositorio', $RepositoryRoot, '-ConfigPath', $ConfigPath, '-XpzActivo', $script:ActiveXpz.Ruta, '-ManifiestoPath', $manifest.Ruta)
    return Start-PanelChildWork -Operation 'GENERAR_PDF' -ScriptPath $scriptPath -ArgumentValues $arguments -Context $script:ActiveContext
}

function Get-OpenApiState {
    if ($null -eq $script:ActiveContext) {
        return [pscustomobject]@{ disponible = $false; estado = 'ADVERTENCIA'; mensaje = 'No hay un contexto activo.'; hostConfigurado = $false; baseUrlConfigurado = $false; documentacionDisponible = $false; archivoDisponible = $false; nombre = $null }
    }
    $hostConfigurado = -not [string]::IsNullOrWhiteSpace([string]$script:ActiveContext.Host)
    $baseUrlConfigurado = -not [string]::IsNullOrWhiteSpace([string]$script:ActiveContext.BaseUrl)
    $documentosPublicados = @(Get-ContextFileList -Directory $script:ActiveContext.DirectorioServicios -Extensions @('.md', '.pdf'))
    $ruta = Join-Path $script:ActiveContext.DirectorioServicios 'OpenAPI\openapi.json'
    $documentacionDisponible = $documentosPublicados.Count -gt 0
    $archivoDisponible = Test-Path -LiteralPath $ruta -PathType Leaf
    $valido = $hostConfigurado -and $baseUrlConfigurado -and $documentacionDisponible
    $mensaje = if (-not $hostConfigurado -or -not $baseUrlConfigurado) { 'Faltan host y/o baseUrl; la generación automática está deshabilitada.' } elseif (-not $documentacionDisponible) { 'No existe documentación publicada para generar OpenAPI.' } elseif ($archivoDisponible) { 'OpenAPI configurado y generado.' } else { 'OpenAPI configurado; aún no se ha generado openapi.json.' }
    return [pscustomobject]@{ disponible = $valido; estado = if ($valido) { 'OK' } else { 'ADVERTENCIA' }; mensaje = $mensaje; hostConfigurado = $hostConfigurado; baseUrlConfigurado = $baseUrlConfigurado; documentacionDisponible = $documentacionDisponible; archivoDisponible = $archivoDisponible; nombre = if ($archivoDisponible) { 'openapi.json' } else { $null } }
}

function Start-OpenApiGenerationWork {
    if ($null -eq $script:ActiveContext) { throw 'No hay un contexto activo.' }
    $openApiState = Get-OpenApiState
    if (-not $openApiState.hostConfigurado -or -not $openApiState.baseUrlConfigurado) { throw 'OpenAPI requiere host y baseUrl configurados.' }
    if (-not $openApiState.documentacionDisponible) { throw 'No existe documentación Markdown o PDF publicada para generar OpenAPI.' }
    $sourceXpz = if ($script:ActiveXpz) { $script:ActiveXpz } else { @(Get-ActiveXpzCandidates | Sort-Object Fecha -Descending | Select-Object -First 1)[0] }
    if ($null -eq $sourceXpz) { throw 'No existe un XPZ fuente para el análisis técnico de OpenAPI.' }
    Prepare-PanelOperationLogs -Context $script:ActiveContext
    $jobsDirectory = Join-Path $script:ActiveContext.DirectorioLogs 'panel-jobs'
    New-Item -ItemType Directory -Path $jobsDirectory -Force | Out-Null
    $rutaOpenApi = [System.IO.Path]::GetFullPath((Join-Path $script:ActiveContext.DirectorioServicios 'OpenAPI\openapi.json'))
    $manifest = Crear-ManifiestoEjecucion -Xpz $sourceXpz.Ruta -FullyQualifiedNames @() -DirectorioBase (Join-Path $jobsDirectory ('openapi-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))) -Contexto $script:ActiveContext
    $scriptPath = Join-Path $RepositoryRoot 'binary\GenerarOpenApi.ps1'
    $arguments = @('-File', $scriptPath, '-ConfigPath', $ConfigPath, '-ManifiestoPath', $manifest.Ruta)
    return Start-PanelChildWork -Operation 'GENERAR_OPENAPI' -ScriptPath $scriptPath -ArgumentValues $arguments -Context $script:ActiveContext -GeneratedPath $rutaOpenApi
}

function Get-EndpointInventoryState {
    if ($null -eq $script:ActiveContext -or $null -eq $script:ActiveXpz) {
        return [pscustomobject]@{ disponible = $false; vigente = $false; obsoleto = $false; motivo = 'No hay contexto o XPZ activo.'; inventario = $null }
    }
    $endpointsRoot = Join-Path $script:ActiveContext.DirectorioServicios 'Endpoints'
    $pointerPath = Join-Path $endpointsRoot 'current.json'
    if (-not (Test-Path -LiteralPath $pointerPath -PathType Leaf)) {
        return [pscustomobject]@{ disponible = $false; vigente = $false; obsoleto = $false; motivo = 'No existe current.json.'; inventario = $null }
    }
    try {
        $pointer = Get-Content -LiteralPath $pointerPath -Raw | ConvertFrom-Json
        $generationId = [string]$pointer.generationId
        if ($generationId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw 'generationId invalido.' }
        $generationDirectory = Join-Path (Join-Path $endpointsRoot 'generations') $generationId
        $jsonPath = Join-Path $generationDirectory 'endpoints.json'
        $markdownPath = Join-Path $generationDirectory 'endpoints.md'
        if (-not (Test-Path -LiteralPath $jsonPath -PathType Leaf) -or -not (Test-Path -LiteralPath $markdownPath -PathType Leaf)) { throw 'La generacion no contiene el par completo.' }
        $inventory = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
        $activeXpzPath = [System.IO.Path]::GetFullPath($script:ActiveXpz.Ruta)
        $inventoryXpzPath = [System.IO.Path]::GetFullPath([string]$inventory.meta.xpz)
        $hashMatches = ([string]$inventory.meta.xpzSha256 -ieq (Obtener-Sha256Archivo -Ruta $activeXpzPath))
        $identityMatches = ([string]$inventory.meta.contextId -eq $script:ActiveContext.ContextId -and $inventoryXpzPath -eq $activeXpzPath -and [string]$inventory.meta.generationId -eq $generationId -and $hashMatches)
        return [pscustomobject]@{ disponible = $true; vigente = $identityMatches; obsoleto = (-not $identityMatches); motivo = if ($identityMatches) { '' } else { 'El inventario no coincide con el contexto o XPZ activo.' }; inventario = $inventory }
    } catch {
        return [pscustomobject]@{ disponible = $false; vigente = $false; obsoleto = $true; motivo = $_.Exception.Message; inventario = $null }
    }
}

function Get-EnrichedServices {
    if ($null -eq $script:ActiveContext -or $null -eq $script:ActiveXpz) { return @() }

    $index = Cargar-IndiceMultiXPZ -RutaXpzPrincipal $script:ActiveXpz.Ruta
    $inventoryServices = @(Obtener-ServiciosHttpDesdeIndice -Indice $index)
    $inventoryNames = @($inventoryServices | ForEach-Object { [string]$_.proceso })
    $ignoredServices = @($script:ActiveContext.ServiciosIgnorados)
    $controlServices = @{}
    if (Test-Path -LiteralPath $script:ActiveContext.RutaControl -PathType Leaf) {
        try {
            $control = Leer-ControlVersiones -RutaControl $script:ActiveContext.RutaControl
            $controlServices = Convertir-DiccionarioControlVersiones -Objeto $control.services
        } catch { $controlServices = @{} }
    }

    $enrichedServices = New-Object System.Collections.Generic.List[object]
    foreach ($inventoryService in $inventoryServices) {
        $fullyQualifiedName = [string]$inventoryService.proceso
        if ($ignoredServices -contains $fullyQualifiedName) { continue }
        $fileBaseName = Obtener-NombreArchivoServicio -FullyQualifiedName $fullyQualifiedName -FqnsInventario $inventoryNames
        $markdownName = $fileBaseName + '.md'
        $pdfName = $fileBaseName + '.pdf'
        $markdownPath = Join-Path $script:ActiveContext.DirectorioServicios $markdownName
        $pdfPath = Join-Path $script:ActiveContext.DirectorioServicios $pdfName
        $controlService = if ($controlServices.ContainsKey($fullyQualifiedName)) { $controlServices[$fullyQualifiedName] } else { $null }
        $version = if ($null -ne $controlService) { [string](Obtener-PropiedadControlVersiones -Objeto $controlService -Nombre 'version') } else { $null }
        if ([string]::IsNullOrWhiteSpace($version)) { $version = $null }
        $observacion = if (-not [string]::IsNullOrWhiteSpace($version)) { Get-ObservacionCambioServicioDesdeArchivo -RutaHistorial $script:ActiveContext.RutaHistorial -FullyQualifiedName $fullyQualifiedName -Version $version } else { $null }
        $status = if ($null -ne $controlService) { [string](Obtener-PropiedadControlVersiones -Objeto $controlService -Nombre 'status') } else { 'ACTIVO' }
        if ([string]::IsNullOrWhiteSpace($status)) { $status = 'ACTIVO' }
        $pdfExists = Test-Path -LiteralPath $pdfPath -PathType Leaf
        $markdownExists = Test-Path -LiteralPath $markdownPath -PathType Leaf
        $lastModified = $null
        foreach ($artifactPath in @($markdownPath, $pdfPath)) {
            if (Test-Path -LiteralPath $artifactPath -PathType Leaf) {
                $artifactDate = (Get-Item -LiteralPath $artifactPath).LastWriteTimeUtc
                if ($null -eq $lastModified -or $artifactDate -gt $lastModified) { $lastModified = $artifactDate }
            }
        }
        [void]$enrichedServices.Add([pscustomobject]@{
            fullyQualifiedName = $fullyQualifiedName
            nombre = [string]$inventoryService.nombre
            descripcion = [string]$inventoryService.descripcion
            proceso = $fullyQualifiedName
            endpoint = [string]$script:ActiveContext.PackageName + [string]$inventoryService.endpoint
            estado = $status
            version = $version
            versionDisponible = ($null -ne $version)
            observacion = $observacion
            fecha = if ($lastModified) { $lastModified.ToString('o') } else { $null }
            pdf = [pscustomobject]@{ disponible = $pdfExists; nombre = if ($pdfExists) { $pdfName } else { $null } }
            markdown = [pscustomobject]@{ disponible = $markdownExists; nombre = if ($markdownExists) { $markdownName } else { $null } }
        })
    }
    return @($enrichedServices.ToArray())
}

function Start-EndpointGenerationWork {
    if ($null -eq $script:ActiveContext) { throw 'No hay un contexto activo.' }
    if ($null -eq $script:ActiveXpz) { throw 'No hay un XPZ activo en el contexto.' }
    Prepare-PanelOperationLogs -Context $script:ActiveContext
    $jobId = 'panel-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + ([Guid]::NewGuid().ToString('N').Substring(0, 8))
    $jobsDirectory = Join-Path $script:ActiveContext.DirectorioLogs 'panel-jobs'
    New-Item -ItemType Directory -Path $jobsDirectory -Force | Out-Null
    $logPath = Join-Path $script:ActiveContext.DirectorioLogs ($jobId + '.log')
    $stdoutPath = Join-Path $jobsDirectory ($jobId + '.out')
    $stderrPath = Join-Path $jobsDirectory ($jobId + '.err')
    $manifestBase = Join-Path $jobsDirectory $jobId
    $manifest = Crear-ManifiestoEjecucion -Xpz $script:ActiveXpz.Ruta -FullyQualifiedNames @() -DirectorioBase $manifestBase -Contexto $script:ActiveContext
    $powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $scriptPath = Join-Path $RepositoryRoot 'binary\GenerarListaEndpoints.ps1'
    $argumentValues = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath, '-ManifiestoPath', $manifest.Ruta)
    $argumentText = (($argumentValues | ForEach-Object { Quote-ProcessArgument -Value ([string]$_) }) -join ' ')
    $process = Start-Process -FilePath $powerShellPath -ArgumentList $argumentText -WorkingDirectory $RepositoryRoot -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru
    $script:CurrentWork = [pscustomobject]@{
        id = $jobId
        contextId = $script:ActiveContext.ContextId
        operacion = 'REGENERAR_ENDPOINTS'
        estado = 'RUNNING'
        log = $logPath
        inicio = (Get-Date).ToUniversalTime().ToString('o')
        ultimaActividad = (Get-Date).ToUniversalTime().ToString('o')
        fin = $null
        codigoSalida = $null
        progreso = [pscustomobject]@{ indeterminado = $true; porcentaje = $null }
        warnings = @()
        error = $null
        stdoutPath = $stdoutPath
        stderrPath = $stderrPath
        process = $process
    }
    return $script:CurrentWork
}

function Start-PanelChildWork {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentValues,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $false)][string]$GeneratedPath = ''
    )
    if ($Context) { Stop-PanelOrphanedMsbuild -Context $Context | Out-Null }
    $jobId = 'panel-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + ([Guid]::NewGuid().ToString('N').Substring(0, 8))
    $jobsDirectory = Join-Path $Context.DirectorioLogs 'panel-jobs'
    $operationsDirectory = Join-Path $Context.DirectorioLogs 'operaciones'
    New-Item -ItemType Directory -Path $jobsDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $operationsDirectory -Force | Out-Null
    $operationId = [Guid]::NewGuid().ToString('N')
    $operationLogName = $operationId + '.log'
    $operationLogPath = Join-Path $operationsDirectory $operationLogName
    $operationManifestPath = Join-Path $operationsDirectory ($operationId + '.json')
    $stdoutPath = Join-Path $jobsDirectory ($jobId + '.out')
    $stderrPath = Join-Path $jobsDirectory ($jobId + '.err')
    $powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argumentText = (($ArgumentValues | ForEach-Object { Quote-ProcessArgument -Value ([string]$_) }) -join ' ')
    $process = Start-Process -FilePath $powerShellPath -ArgumentList $argumentText -WorkingDirectory $RepositoryRoot -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru
    $script:CurrentWork = [pscustomobject]@{
        id = $jobId
        operationId = $operationId
        contextId = $Context.ContextId
        operacion = $Operation
        estado = 'RUNNING'
        log = $operationLogPath
        operationLogPath = $operationLogPath
        operationManifestPath = $operationManifestPath
        operationLogName = $operationLogName
        inicio = (Get-Date).ToUniversalTime().ToString('o')
        ultimaActividad = (Get-Date).ToUniversalTime().ToString('o')
        fin = $null
        codigoSalida = $null
        progreso = [pscustomobject]@{ indeterminado = $true; porcentaje = $null }
        warnings = @()
        error = $null
        stdoutPath = $stdoutPath
        stderrPath = $stderrPath
        xpzNombre = if ($script:ActiveXpz) { [string]$script:ActiveXpz.Nombre } else { $null }
        xpzSha256 = if ($script:ActiveXpz -and (Test-Path -LiteralPath $script:ActiveXpz.Ruta -PathType Leaf)) { Obtener-Sha256Archivo -Ruta $script:ActiveXpz.Ruta } else { $null }
        rutaGenerada = if ([string]::IsNullOrWhiteSpace($GeneratedPath)) { $null } else { $GeneratedPath }
        process = $process
    }
    Write-OperationRecord -Work $script:CurrentWork
    return $script:CurrentWork
}

function Start-ExportWork {
    param([Parameter(Mandatory = $true)]$RequestBody)
    if ($null -eq $script:ActiveContext) { throw 'No hay un contexto activo.' }
    $geneXus = Resolver-RutaRepositorio -Ruta ([string]$script:ActiveContext.Herramientas.GeneXusProgramDir) -Raiz $RepositoryRoot
    if ([string]::IsNullOrWhiteSpace($geneXus) -or -not (Test-Path -LiteralPath $geneXus -PathType Container)) {
        throw ('No se encontro GeneXus en: ' + $geneXus + '. Verifique herramientas.geneXusProgramDir en configuracion.json.')
    }
    $perfilExportacion = [string]$script:ActiveContext.Herramientas.GeneXusExportProfile
    $msbuildConfigurado = [string]$script:ActiveContext.Herramientas.MsbuildPath
    $msbuild = if ($perfilExportacion -eq 'Evo3') {
        Resolver-RutaMsbuildPorPerfil -RutaConfigurada $msbuildConfigurado -Perfil 'Evo3'
    } else {
        Resolver-RutaRepositorio -Ruta $msbuildConfigurado -Raiz $RepositoryRoot
    }
    if ([string]::IsNullOrWhiteSpace($msbuild) -or -not (Test-Path -LiteralPath $msbuild -PathType Leaf)) {
        throw ('No se encontro MSBuild en: ' + $msbuild + '. Verifique herramientas.msbuildPath en configuracion.json.')
    }
    if (-not (Test-Path -LiteralPath $script:ActiveContext.KbPath -PathType Container)) {
        throw ('No existe la Knowledge Base: ' + $script:ActiveContext.KbPath)
    }
    $policy = [string]$RequestBody.policy
    if ([string]::IsNullOrWhiteSpace($policy)) { $policy = 'abort' }
    if ($policy -notin @('abort', 'continue')) { throw 'policy debe ser abort o continue.' }
    Prepare-PanelOperationLogs -Context $script:ActiveContext
    $scriptPath = Join-Path $RepositoryRoot 'binary\EjecutarExportacionGLM.ps1'
    $arguments = @('-File', $scriptPath, '-Repositorio', $RepositoryRoot, '-ClienteId', $script:ActiveContext.ClienteId, '-AmbienteId', $script:ActiveContext.AmbienteId, '-ConfirmarExportacionCompleta', '-PoliticaPendientes', $policy)
    $work = Start-PanelChildWork -Operation 'EXPORTAR_XPZ' -ScriptPath $scriptPath -ArgumentValues $arguments -Context $script:ActiveContext
    if ($policy -eq 'continue') { $work.warnings = @('La politica continue permite conservar un XPZ incompleto y pendientes visibles.') }
    return $work
}

function Start-CompleteXpzWork {
    param([Parameter(Mandatory = $true)]$RequestBody)
    if ($null -eq $script:ActiveContext) { throw 'No hay un contexto activo.' }
    Prepare-PanelOperationLogs -Context $script:ActiveContext
    $name = [string]$RequestBody.nombre
    $selected = @(Get-ActiveXpzCandidates | Where-Object { $_.Nombre -ceq $name })
    if ($selected.Count -ne 1) { throw 'El XPZ indicado no pertenece al contexto activo.' }
    $script:ActiveXpz = $selected[0]
    $script:XpzOverride = $true
    Prepare-PanelOperationLogs -Context $script:ActiveContext
    $jobsDirectory = Join-Path $script:ActiveContext.DirectorioLogs 'panel-jobs'
    $manifest = Crear-ManifiestoEjecucion -Xpz $script:ActiveXpz.Ruta -FullyQualifiedNames @() -DirectorioBase (Join-Path $jobsDirectory ('completar-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))) -Contexto $script:ActiveContext
    $scriptPath = Join-Path $RepositoryRoot 'binary\CompletarXPZActivoGLM.ps1'
    $arguments = @('-File', $scriptPath, '-Repositorio', $RepositoryRoot, '-XpzActivo', $script:ActiveXpz.Ruta, '-ManifiestoPath', $manifest.Ruta, '-PoliticaPendientes', 'continue')
    return Start-PanelChildWork -Operation 'COMPLETAR_XPZ' -ScriptPath $scriptPath -ArgumentValues $arguments -Context $script:ActiveContext
}

function Start-DocumentationWork {
    param([Parameter(Mandatory = $true)]$RequestBody)
    if ($null -eq $script:ActiveContext -or $null -eq $script:ActiveXpz) { throw 'No hay contexto y XPZ activos.' }
    $mode = [string]$RequestBody.mode
    $selectedNames = @($RequestBody.fullyQualifiedNames | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($mode -notin @('selected', 'all', 'update')) { throw 'mode debe ser selected, update o all.' }
    if ($mode -eq 'selected' -and $selectedNames.Count -eq 0) { throw 'selected exige al menos un FQN.' }
    if ($mode -in @('all', 'update') -and $selectedNames.Count -gt 0) { throw ($mode + ' no admite FQN.') }
    if ($RequestBody.PSObject.Properties['xpz'] -and $RequestBody.xpz) {
        $confirmedName = [string]$RequestBody.xpz.nombre
        $confirmedHash = [string]$RequestBody.xpz.sha256
        $currentHash = if (Test-Path -LiteralPath $script:ActiveXpz.Ruta -PathType Leaf) { Obtener-Sha256Archivo -Ruta $script:ActiveXpz.Ruta } else { '' }
        if ($confirmedName -cne [string]$script:ActiveXpz.Nombre -or $confirmedHash -notmatch '^[0-9a-fA-F]{64}$' -or $confirmedHash -ine $currentHash) { throw 'PRECONDICION_XPZ: El XPZ activo o su SHA-256 cambio; confirme nuevamente.' }
    }
    $inventoryState = Get-EndpointInventoryState
    $knownNames = @()
    if ($inventoryState.inventario) { $knownNames = @($inventoryState.inventario.endpoints | ForEach-Object { [string]$_.proceso }) }
    if ($mode -eq 'selected') {
        $duplicates = @($selectedNames | Group-Object | Where-Object { $_.Count -gt 1 })
        if ($duplicates.Count -gt 0) { throw 'La seleccion contiene FQN duplicados.' }
        foreach ($name in $selectedNames) {
            if ($knownNames -notcontains $name) { throw ('El FQN no pertenece al inventario activo: ' + $name) }
            if (@($script:ActiveContext.ServiciosIgnorados) -contains $name) { throw ('El servicio esta ignorado: ' + $name) }
        }
    }
    Prepare-PanelOperationLogs -Context $script:ActiveContext
    $jobsDirectory = Join-Path $script:ActiveContext.DirectorioLogs 'panel-jobs'
    $manifest = Crear-ManifiestoEjecucion -Xpz $script:ActiveXpz.Ruta -FullyQualifiedNames $selectedNames -DirectorioBase (Join-Path $jobsDirectory ('documentacion-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))) -Contexto $script:ActiveContext
    $scriptPath = Join-Path $RepositoryRoot 'binary\ActualizarServicios.ps1'
    $arguments = @('-File', $scriptPath, '-ConfigPath', $ConfigPath, '-ManifiestoPath', $manifest.Ruta)
    if ($mode -eq 'all') { $arguments += '-ForzarRegeneracionCompleta' }
    if ($RequestBody.reiniciar -eq $true) { $arguments += '-Inicializar' }
    return Start-PanelChildWork -Operation 'PUBLICAR_DOCUMENTACION' -ScriptPath $scriptPath -ArgumentValues $arguments -Context $script:ActiveContext
}

function Test-SafeLogicalName {
    param([Parameter(Mandatory = $true)][string]$Name)
    if ($Name.Length -gt 180 -or $Name -match '%|\.\.|[\\/:]' -or $Name -ne [System.Uri]::UnescapeDataString($Name)) { return $false }
    return ($Name -cmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$')
}

function Get-ContextLogCatalog {
    param(
        [Parameter(Mandatory = $false)][int]$Limite = 200
    )
    if ($null -eq $script:ActiveContext -or -not (Test-Path -LiteralPath $script:ActiveContext.DirectorioLogs -PathType Container)) { return @() }
    $archivos = @(Get-ChildItem -LiteralPath $script:ActiveContext.DirectorioLogs -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension.ToLowerInvariant() -in @('.log', '.json', '.txt') } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First $Limite)
    $catalogo = New-Object System.Collections.Generic.List[object]
    foreach ($archivo in $archivos) {
        $categoria = 'ok'
        $colas = @(Get-Content -LiteralPath $archivo.FullName -Tail 40 -ErrorAction SilentlyContinue)
        $texto = ($colas -join ' ').ToLowerInvariant()
        if ($texto -match 'error|failed|termino con errores|exit code 1|codigo 1|codigo de salida 1') { $categoria = 'error' }
        elseif ($texto -match 'warning|advertencia|pendiente') { $categoria = 'advertencia' }
        [void]$catalogo.Add([pscustomobject]@{
            nombre = $archivo.Name
            extension = $archivo.Extension.ToLowerInvariant()
            bytes = $archivo.Length
            modificado = $archivo.LastWriteTimeUtc.ToString('o')
            categoria = $categoria
        })
    }
    return @($catalogo.ToArray())
}

function Get-QueryValue {
    param(
        [Parameter(Mandatory = $true)]$Request,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $query = [string]$Request.Url.Query
    foreach ($part in @($query.TrimStart('?').Split('&'))) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $separator = $part.IndexOf('=')
        $key = if ($separator -ge 0) { $part.Substring(0, $separator) } else { $part }
        if ($key -ieq $Name) {
            $value = if ($separator -ge 0) { $part.Substring($separator + 1) } else { '' }
            return [System.Uri]::UnescapeDataString($value.Replace('+', ' '))
        }
    }
    return ''
}

function Get-OperationLogCatalog {
    param(
        [Parameter(Mandatory = $false)][string]$OperationType = '',
        [Parameter(Mandatory = $false)][string]$Severity = '',
        [Parameter(Mandatory = $false)][bool]$History = $false
    )
    if ($null -eq $script:ActiveContext) { return @() }
    $operationsDirectory = Join-Path $script:ActiveContext.DirectorioLogs 'operaciones'
    if (-not (Test-Path -LiteralPath $operationsDirectory -PathType Container)) { return @() }
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($manifestFile in @(Get-ChildItem -LiteralPath $operationsDirectory -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try {
            $record = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json
            if ([string]$record.contextId -ne $script:ActiveContext.ContextId) { continue }
            if ($OperationType -and $OperationType -ne 'todos' -and [string]$record.tipo -ine $OperationType) { continue }
            if ($Severity -and $Severity -ne 'todos' -and [string]$record.severidad -ine $Severity) { continue }
            $logName = [string]$record.logNombre
            $logPath = if (Test-SafeLogicalName -Name $logName) { Join-Path $operationsDirectory $logName } else { $null }
            $logItem = if ($logPath -and (Test-Path -LiteralPath $logPath -PathType Leaf)) { Get-Item -LiteralPath $logPath -ErrorAction SilentlyContinue } else { $null }
            $categoriaSeveridad = switch ([string]$record.severidad) {
                'ERROR' { 'error' }
                'WARNING' { 'advertencia' }
                default { 'ok' }
            }
            [void]$records.Add([pscustomobject]@{
                nombre = $logName
                extension = '.log'
                bytes = if ($logItem) { $logItem.Length } else { 0 }
                modificado = if (-not [string]::IsNullOrWhiteSpace([string]$record.fin)) { [string]$record.fin } elseif ($record.inicio) { [string]$record.inicio } elseif ($logItem) { $logItem.LastWriteTimeUtc.ToString('o') } else { '' }
                categoria = $categoriaSeveridad
                operationId = [string]$record.operationId
                tipo = [string]$record.tipo
                severidad = [string]$record.severidad
                estadoTecnico = [string]$record.estadoTecnico
                estadoVisible = [string]$record.estadoVisible
                codigoSalida = $record.codigoSalida
                inicio = [string]$record.inicio
                fin = [string]$record.fin
                logNombre = $logName
                error = [string]$record.error
                warnings = @($record.warnings)
            })
        } catch { continue }
    }
    $sortedRecords = @($records | Sort-Object { [datetime]$_.inicio } -Descending)
    if ($History -or ($OperationType -and $OperationType -ne 'todos')) { return $sortedRecords }
    return @($sortedRecords | Group-Object tipo | ForEach-Object { $_.Group | Select-Object -First 1 })
}

function Get-ContextFileList {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string[]]$Extensions
    )
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue | Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() } | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{ nombre = $_.Name; extension = $_.Extension.ToLowerInvariant(); bytes = $_.Length; modificado = $_.LastWriteTimeUtc.ToString('o') }
    })
}

function Get-PublishedPdfCatalog {
    if ($null -eq $script:ActiveContext) { return @() }
    $pdfFiles = @(Get-ContextFileList -Directory $script:ActiveContext.DirectorioServicios -Extensions @('.pdf'))
    return @($pdfFiles | ForEach-Object {
        $pdf = $_
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($pdf.nombre)
        $markdownPath = Join-Path $script:ActiveContext.DirectorioServicios ($baseName + '.md')
        $serviceName = $baseName
        $description = 'Documento publicado'
        $version = $null
        $endpoint = $null
        if (Test-Path -LiteralPath $markdownPath -PathType Leaf) {
            $lines = @(Get-Content -LiteralPath $markdownPath -Encoding UTF8)
            $heading = $lines | Where-Object { $_ -match '^#\s+(.+)$' } | Select-Object -First 1
            if ($heading -and $heading -match '^#\s+(.+)$') { $serviceName = $Matches[1].Trim() }
            $descriptionRow = $lines | Where-Object { $_ -match '(?i)^\|\s*Descripci.n\s*\|\s*(.+?)\s*\|$' } | Select-Object -First 1
            if ($descriptionRow -and $descriptionRow -match '(?i)^\|\s*Descripci.n\s*\|\s*(.+?)\s*\|$') { $description = $Matches[1].Trim() }
            $versionRow = $lines | Where-Object { $_ -match '(?i)^\|\s*Versi.n\s*\|\s*(.+?)\s*\|$' } | Select-Object -First 1
            if ($versionRow -and $versionRow -match '(?i)^\|\s*Versi.n\s*\|\s*(.+?)\s*\|$') { $version = $Matches[1].Trim() }
            $endpointRow = $lines | Where-Object { $_ -match '(?i)^\|\s*Endpoint\s*\|\s*`?(.+?)`?\s*\|$' } | Select-Object -First 1
            if ($endpointRow -and $endpointRow -match '(?i)^\|\s*Endpoint\s*\|\s*`?(.+?)`?\s*\|$') { $endpoint = $Matches[1].Replace('`', '').Trim() }
        }
        [pscustomobject]@{ nombre = $pdf.nombre; extension = '.pdf'; bytes = $pdf.bytes; modificado = $pdf.modificado; servicioNombre = $serviceName; descripcion = $description; version = $version; endpoint = $endpoint }
    })
}

function Write-BytesResponse {
    param(
        [Parameter(Mandatory = $true)]$RequestContext,
        [Parameter(Mandatory = $true)][int]$StatusCode,
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$ContentType,
        [Parameter(Mandatory = $false)][ValidateSet('inline', 'attachment')][string]$ContentDisposition = 'inline',
        [Parameter(Mandatory = $false)][string]$DownloadName = ''
    )
    $response = $RequestContext.Response
    $response.StatusCode = $StatusCode
    $response.ContentType = $ContentType
    $response.Headers['Cache-Control'] = 'no-store'
    $safeDownloadName = if ([string]::IsNullOrWhiteSpace($DownloadName)) { '' } else { [System.IO.Path]::GetFileName($DownloadName) }
    $response.Headers['Content-Disposition'] = if ($safeDownloadName) { $ContentDisposition + '; filename="' + $safeDownloadName + '"' } else { $ContentDisposition }
    $response.ContentLength64 = $Bytes.Length
    $response.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $response.Close()
}

function Get-ContextDocumentPath {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Test-SafeLogicalName -Name $Name) -or [System.IO.Path]::GetExtension($Name).ToLowerInvariant() -notin @('.md', '.pdf')) { return $null }
    return Join-Path $script:ActiveContext.DirectorioServicios $Name
}

function Get-ContextLogPath {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Test-SafeLogicalName -Name $Name) -or [System.IO.Path]::GetExtension($Name).ToLowerInvariant() -notin @('.log', '.json', '.txt')) { return $null }
    $rutaDirecta = Join-Path $script:ActiveContext.DirectorioLogs $Name
    if (Test-Path -LiteralPath $rutaDirecta -PathType Leaf) { return $rutaDirecta }
    $rutaOperaciones = Join-Path $script:ActiveContext.DirectorioLogs ('operaciones\' + $Name)
    if (Test-Path -LiteralPath $rutaOperaciones -PathType Leaf) { return $rutaOperaciones }
    return $rutaDirecta
}

function Get-LatestContextReport {
    param([Parameter(Mandatory = $true)][ValidateSet('review', 'validation')][string]$Type)
    if ($null -eq $script:ActiveContext -or -not (Test-Path -LiteralPath $script:ActiveContext.DirectorioLogs -PathType Container)) { return $null }
    $pattern = if ($Type -eq 'review') { '*-actualizacion-review.json' } else { '*-validacion-xpz.json' }
    foreach ($file in @(Get-ChildItem -LiteralPath $script:ActiveContext.DirectorioLogs -Filter $pattern -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)) {
        try {
            $content = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            $execution = $content.ejecucion
            if ($null -ne $execution -and [string]$execution.contextId -eq $script:ActiveContext.ContextId) {
                if ($Type -eq 'validation' -and $script:ActiveXpz -and [string]$execution.xpz) {
                    if ([System.IO.Path]::GetFullPath([string]$execution.xpz) -ne [System.IO.Path]::GetFullPath($script:ActiveXpz.Ruta)) { continue }
                }
                return [pscustomobject]@{ nombre = $file.Name; modificado = $file.LastWriteTimeUtc.ToString('o'); contenido = $content }
            }
        } catch { continue }
    }
    return $null
}

function Get-ConfigurationHash {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return '' }
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.IO.File]::ReadAllBytes($ConfigPath)
        return (([System.BitConverter]::ToString($sha256.ComputeHash($bytes))) -replace '-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function Test-PanelPortValue {
    param($Configuration)
    if ($null -eq $Configuration.panel -or $null -eq $Configuration.panel.puerto) { return $true }
    $port = 0
    return ([int]::TryParse([string]$Configuration.panel.puerto, [ref]$port) -and $port -ge 1 -and $port -le 65535)
}

function Test-ConfigurationCandidate {
    param([Parameter(Mandatory = $true)]$Candidate)
    if (-not (Test-PanelPortValue -Configuration $Candidate)) { throw 'panel.puerto debe ser un entero entre 1 y 65535.' }
    Validar-ConfiguracionMulticliente -ConfiguracionRaw $Candidate -RaizRepositorio $RepositoryRoot -ConfigPath $ConfigPath -ValidarContenidoKnowledgeBase | Out-Null
}

function Normalize-CandidateEnvironmentNames {
    param([Parameter(Mandatory = $true)]$Candidate)
    foreach ($client in @($Candidate.clientes)) {
        foreach ($environment in @($client.ambientes)) {
            $environmentType = Clasificar-TipoAmbiente -Tipo ([string]$environment.tipo)
            if ($null -ne $environmentType) {
                $environment.nombre = Obtener-NombreAmbienteCanonico -Tipo $environmentType
            }
        }
    }
}

function Reset-PanelSession {
    $script:ActiveContext = $null
    $script:ActiveXpz = $null
    $script:XpzOverride = $false
    $script:LastFinishedWork = $null
}

function Write-ConfigurationCandidate {
    param(
        [Parameter(Mandatory = $true)]$Candidate,
        [Parameter(Mandatory = $false)][string]$Operation = 'CONFIGURACION_CLIENTE'
    )
    $contextBeforeWrite = $script:ActiveContext
    Normalize-CandidateEnvironmentNames -Candidate $Candidate
    # Las mutaciones validan el contenido de la KB afectada; el candidato completo
    # se valida aqui por esquema para no exigir acceso a todas las KB existentes.
    Validar-ConfiguracionMulticliente -ConfiguracionRaw $Candidate -RaizRepositorio $RepositoryRoot -ConfigPath $ConfigPath | Out-Null
    $content = Normalizar-SaltosLineaLf -Texto ($Candidate | ConvertTo-Json -Depth 15)
    Escribir-ArchivoAtomico -Ruta $ConfigPath -Contenido $content | Out-Null
    $script:ConfigurationRaw = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $script:ConfigurationErrors.Clear()
    Reset-PanelSession
    if ($contextBeforeWrite) {
        Write-PanelMutationOperation -Operation $Operation -Context $contextBeforeWrite -Output @('Configuracion actualizada correctamente.') | Out-Null
    }
}

function Get-MutationPayload {
    param([Parameter(Mandatory = $true)]$Body)
    $hash = [string]$Body.configHash
    if ([string]::IsNullOrWhiteSpace($hash)) { throw 'La mutacion requiere configHash.' }
    if ($hash.ToLowerInvariant() -ne (Get-ConfigurationHash)) { throw 'configuracion.json cambio externamente; vuelva a leerlo.' }
    if ($Body.PSObject.Properties['data']) { return $Body.data }
    return $Body
}

function Find-ConfiguredClient {
    param([Parameter(Mandatory = $true)]$Candidate, [Parameter(Mandatory = $true)][string]$ClientId)
    return @($Candidate.clientes | Where-Object { [string]$_.id -ceq $ClientId }) | Select-Object -First 1
}

function Find-ConfiguredEnvironment {
    param([Parameter(Mandatory = $true)]$Client, [Parameter(Mandatory = $true)][string]$EnvironmentId)
    return @($Client.ambientes | Where-Object { [string]$_.id -ceq $EnvironmentId }) | Select-Object -First 1
}

function Normalize-GeneXusExportProfile {
    param([AllowEmptyString()][string]$Value)
    switch ($Value.Trim().ToLowerInvariant()) {
        'gx18' { return 'Gx18' }
        'evo3' { return 'Evo3' }
        default { throw 'El entorno de exportacion debe ser Gx18 o Evo3.' }
    }
}

function Convert-MutationPayloadToNewClient {
    param([Parameter(Mandatory = $true)]$Payload)

    foreach ($propertyName in @('id', 'nombre', 'packagename')) {
        if (-not $Payload.PSObject.Properties[$propertyName] -or [string]::IsNullOrWhiteSpace([string]$Payload.$propertyName)) {
            throw ('El alta de cliente requiere el campo ' + $propertyName + '.')
        }
    }
    $clientId = ([string]$Payload.id).Trim().ToLowerInvariant()
    if (-not (Test-NombreSlugValido -Valor $clientId)) {
        throw 'El id de cliente no es valido. Use minusculas, digitos y guiones.'
    }
    if (-not $Payload.PSObject.Properties['ambientes'] -or @($Payload.ambientes).Count -ne 1) {
        throw 'El alta de cliente requiere exactamente un primer ambiente completo.'
    }
    if ($Payload.PSObject.Properties['serviciosIgnorados'] -and @($Payload.serviciosIgnorados).Count -gt 0) {
        throw 'Un cliente nuevo debe conservar serviciosIgnorados como coleccion vacia.'
    }

    $environmentPayload = @($Payload.ambientes)[0]
    foreach ($propertyName in @('tipo', 'kbPath')) {
        if (-not $environmentPayload.PSObject.Properties[$propertyName] -or [string]::IsNullOrWhiteSpace([string]$environmentPayload.$propertyName)) {
            throw ('El primer ambiente requiere el campo ' + $propertyName + '.')
        }
    }
    $environmentType = Clasificar-TipoAmbiente -Tipo ([string]$environmentPayload.tipo)
    if ($null -eq $environmentType) {
        throw 'El tipo del primer ambiente debe ser test o prod.'
    }
    $kbPathResuelto = Resolver-RutaRepositorio -Ruta ([string]$environmentPayload.kbPath) -Raiz $RepositoryRoot
    Validar-RutaKnowledgeBase -Ruta $kbPathResuelto -Contexto ("La Knowledge Base del primer ambiente del cliente '" + $clientId + "'") | Out-Null
    $environmentHost = if ($environmentPayload.PSObject.Properties['host'] -and -not [string]::IsNullOrWhiteSpace([string]$environmentPayload.host)) { Validar-HostAmbiente -HostUrl ([string]$environmentPayload.host) -Contexto 'El host del primer ambiente' } else { $null }
    $environmentBaseUrl = if ($environmentPayload.PSObject.Properties['baseUrl'] -and -not [string]::IsNullOrWhiteSpace([string]$environmentPayload.baseUrl)) { Validar-BaseUrlAmbiente -BaseUrl ([string]$environmentPayload.baseUrl) -Contexto 'El baseUrl del primer ambiente' } else { $null }

    return [pscustomobject]@{
        id = $clientId
        nombre = [string]$Payload.nombre
        packagename = [string]$Payload.packagename
        serviciosIgnorados = @()
        ambientes = @([pscustomobject]@{
            id = Obtener-IdAmbienteCanonico -Tipo $environmentType
            nombre = Obtener-NombreAmbienteCanonico -Tipo $environmentType
            tipo = $environmentType
            kbPath = [string]$environmentPayload.kbPath
            host = $environmentHost
            baseUrl = $environmentBaseUrl
        })
    }
}

function Get-PanelPort {
    if ($Port -ge 1 -and $Port -le 65535) {
        return $Port
    }
    $configuredPort = 0
    if ($script:ConfigurationRaw -and $script:ConfigurationRaw.panel -and [int]::TryParse([string]$script:ConfigurationRaw.panel.puerto, [ref]$configuredPort)) {
        if ($configuredPort -ge 1 -and $configuredPort -le 65535) {
            return $configuredPort
        }
    }
    return 8123
}

function Write-JsonResponse {
    param(
        [Parameter(Mandatory = $true)]$RequestContext,
        [Parameter(Mandatory = $true)][int]$StatusCode,
        [Parameter(Mandatory = $true)]$Payload
    )
    $bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Payload -Depth 12 -Compress))
    $response = $RequestContext.Response
    $response.StatusCode = $StatusCode
    $response.ContentType = 'application/json; charset=utf-8'
    $response.Headers['Cache-Control'] = 'no-store'
    $response.ContentLength64 = $bytes.Length
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
    $response.Close()
}

function Write-TextResponse {
    param(
        [Parameter(Mandatory = $true)]$RequestContext,
        [Parameter(Mandatory = $true)][int]$StatusCode,
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$ContentType
    )
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    $response = $RequestContext.Response
    $response.StatusCode = $StatusCode
    $response.ContentType = $ContentType
    $response.Headers['Cache-Control'] = 'no-store'
    $response.ContentLength64 = $bytes.Length
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
    $response.Close()
}

function Test-LoopbackRequest {
    param([Parameter(Mandatory = $true)]$Request)
    $hostName = [string]$Request.UserHostName
    return ($hostName -match '^(127\.0\.0\.1|localhost)(:\d+)?$')
}

function Test-SessionToken {
    param([Parameter(Mandatory = $true)]$Request)
    return ([string]$Request.Headers['X-Panel-Token'] -eq $script:SessionToken)
}

function Get-RequestBodyJson {
    param([Parameter(Mandatory = $true)]$Request)
    if ([string]::IsNullOrWhiteSpace([string]$Request.ContentType) -or $Request.ContentType -notmatch '^application/json(?:\s*;|$)') {
        throw 'La mutacion requiere Content-Type: application/json.'
    }
    if ($Request.ContentLength64 -gt 1048576) {
        throw 'El cuerpo de la peticion supera el limite de 1 MiB.'
    }
    $reader = New-Object System.IO.StreamReader($Request.InputStream, [System.Text.Encoding]::UTF8)
    try { return ($reader.ReadToEnd() | ConvertFrom-Json) } finally { $reader.Dispose() }
}

function Get-StaticPath {
    param([Parameter(Mandatory = $true)][string]$RequestPath)
    $logicalPath = $RequestPath
    if ($logicalPath -eq '/') { $logicalPath = '/index.html' }
    if ($logicalPath -match '^/fonts/Poppins-(Regular|SemiBold|Bold)\.ttf$') {
        return Join-Path (Join-Path $RepositoryRoot 'binary\fonts') ([System.IO.Path]::GetFileName($logicalPath))
    }
    if ($logicalPath -notmatch '^/(index\.html|style\.css|favicon\.svg|resources/example\.html|app\.js|app/(main|api-client|state|preferences|render-utils)\.js|app/components/(app-shell|base-states|service-components|operation-console|crud-list)\.js|app/views/(index|dashboard|documentation|logs|configuration)\.js)$') {
        return $null
    }
    return Join-Path (Join-Path $RepositoryRoot 'web') $logicalPath.TrimStart('/')
}

function Get-ContentType {
    param([Parameter(Mandatory = $true)][string]$Path)
    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.html' { return 'text/html; charset=utf-8' }
        '.js' { return 'text/javascript; charset=utf-8' }
        '.css' { return 'text/css; charset=utf-8' }
        '.svg' { return 'image/svg+xml' }
        '.ttf' { return 'font/ttf' }
        default { return 'application/octet-stream' }
    }
}

function Send-StaticFile {
    param([Parameter(Mandatory = $true)]$RequestContext)
    $path = Get-StaticPath -RequestPath $RequestContext.Request.Url.AbsolutePath
    if ($null -eq $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-TextResponse -RequestContext $RequestContext -StatusCode 404 -Content 'Recurso no encontrado.' -ContentType 'text/plain; charset=utf-8'
        return
    }
    if ([System.IO.Path]::GetExtension($path).ToLowerInvariant() -eq '.ttf') {
        Write-BytesResponse -RequestContext $RequestContext -StatusCode 200 -Bytes ([System.IO.File]::ReadAllBytes($path)) -ContentType (Get-ContentType -Path $path)
        return
    }
    $content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    if ([System.IO.Path]::GetFileName($path) -eq 'index.html') {
        $tokenScript = '<script>window.PANEL_TOKEN="' + $script:SessionToken + '";</script>'
        $content = $content.Replace('</head>', $tokenScript + '</head>')
    }
    Write-TextResponse -RequestContext $RequestContext -StatusCode 200 -Content $content -ContentType (Get-ContentType -Path $path)
}

function Get-ObservacionCambioServicioDesdeArchivo {
    param(
        [Parameter(Mandatory = $true)][string]$RutaHistorial,
        [Parameter(Mandatory = $true)][string]$FullyQualifiedName,
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$Version = ''
    )
    if (-not (Test-Path -LiteralPath $RutaHistorial -PathType Leaf)) { return $null }
    if ([string]::IsNullOrWhiteSpace($Version)) { return $null }
    $lineas = @([System.IO.File]::ReadAllLines($RutaHistorial, (New-Object System.Text.UTF8Encoding($false))))
    $seccionEsperada = '## ' + $FullyQualifiedName
    $patronVersion = [regex]::new('^-\s+\*\*' + [regex]::Escape($Version) + '\*\*')
    $enSeccion = $false
    for ($i = 0; $i -lt $lineas.Count; $i++) {
        $linea = [string]$lineas[$i]
        if ($linea -match '^##\s+') {
            if ($enSeccion) { break }
            if ($linea.TrimEnd() -eq $seccionEsperada) { $enSeccion = $true }
            continue
        }
        if (-not $enSeccion) { continue }
        if ($patronVersion.IsMatch($linea)) {
            $textoEntrada = New-Object System.Collections.Generic.List[string]
            [void]$textoEntrada.Add($linea.Trim())
            for ($j = $i + 1; $j -lt $lineas.Count; $j++) {
                $siguiente = [string]$lineas[$j]
                if ($siguiente -match '^-\s+\*\*' -or $siguiente -match '^##\s+') { break }
                if ([string]::IsNullOrWhiteSpace($siguiente)) { continue }
                [void]$textoEntrada.Add($siguiente.Trim())
            }
            return (($textoEntrada.ToArray()) -join ' ')
        }
    }
    return $null
}

function Get-ContextValidaciones {
    $validaciones = New-Object System.Collections.Generic.List[object]
    if ($null -eq $script:ActiveContext) { return @($validaciones.ToArray()) }
    if ($script:ConfigurationErrors.Count -eq 0) {
        [void]$validaciones.Add([pscustomobject]@{ item = 'Configuracion'; estado = 'OK'; mensaje = 'Esquema multicliente valido.' })
    } else {
        [void]$validaciones.Add([pscustomobject]@{ item = 'Configuracion'; estado = 'ERROR'; mensaje = ($script:ConfigurationErrors -join '; ') })
    }
    $herramientasDefinidas = @(
        [pscustomobject]@{ nombre = 'GeneXus'; propiedad = 'geneXusProgramDir'; tipo = 'Container' },
        [pscustomobject]@{ nombre = 'MSBuild'; propiedad = 'msbuildPath'; tipo = 'Leaf' },
        [pscustomobject]@{ nombre = 'Pandoc'; propiedad = 'pandocPath'; tipo = 'Leaf' },
        [pscustomobject]@{ nombre = 'Typst'; propiedad = 'typstPath'; tipo = 'Leaf' }
    )
    foreach ($herramienta in $herramientasDefinidas) {
        $valor = $null
        if ($script:ConfigurationRaw -and $script:ConfigurationRaw.herramientas) { $valor = [string]$script:ConfigurationRaw.herramientas.($herramienta.propiedad) }
        if ([string]::IsNullOrWhiteSpace($valor)) {
            [void]$validaciones.Add([pscustomobject]@{ item = $herramienta.nombre; estado = 'ADVERTENCIA'; mensaje = 'No configurado.' })
            continue
        }
        $rutaResuelta = Resolver-RutaRepositorio -Ruta $valor -Raiz $RepositoryRoot
        if (Test-Path -LiteralPath $rutaResuelta -PathType $herramienta.tipo) {
            [void]$validaciones.Add([pscustomobject]@{ item = $herramienta.nombre; estado = 'OK'; mensaje = $rutaResuelta })
        } else {
            [void]$validaciones.Add([pscustomobject]@{ item = $herramienta.nombre; estado = 'ADVERTENCIA'; mensaje = ('No se encontro en: ' + $valor) })
        }
    }
    $hostConfigurado = -not [string]::IsNullOrWhiteSpace([string]$script:ActiveContext.Host)
    $baseUrlConfigurado = -not [string]::IsNullOrWhiteSpace([string]$script:ActiveContext.BaseUrl)
    $faltantesOpenApi = New-Object System.Collections.Generic.List[string]
    if (-not $hostConfigurado) { [void]$faltantesOpenApi.Add('host') }
    if (-not $baseUrlConfigurado) { [void]$faltantesOpenApi.Add('baseUrl') }
    [void]$validaciones.Add([pscustomobject]@{
        item = 'OpenAPI'
        estado = if ($faltantesOpenApi.Count -eq 0) { 'OK' } else { 'ADVERTENCIA' }
        mensaje = if ($faltantesOpenApi.Count -eq 0) { 'Host y baseUrl configurados.' } else { 'Falta(n): ' + ($faltantesOpenApi -join ', ') + '.' }
    })
    [void]$validaciones.Add([pscustomobject]@{ item = 'Contexto'; estado = 'OK'; mensaje = ($script:ActiveContext.ContextId + ' (' + $script:ActiveContext.ClienteNombre + ' / ' + $script:ActiveContext.AmbienteNombre + ')') })
    try {
        Validar-RutaKnowledgeBase -Ruta $script:ActiveContext.KbPath -Contexto 'La Knowledge Base del ambiente' | Out-Null
        [void]$validaciones.Add([pscustomobject]@{ item = 'Knowledge Base'; estado = 'OK'; mensaje = $script:ActiveContext.KbPath })
    } catch {
        [void]$validaciones.Add([pscustomobject]@{ item = 'Knowledge Base'; estado = 'ERROR'; mensaje = $_.Exception.Message })
    }
    return @($validaciones.ToArray())
}

function Get-StateData {
    Update-CurrentWork
    $inventoryState = if ($script:ActiveContext -and $script:ActiveXpz) { Get-EndpointInventoryState } else { $null }
    $documentFiles = if ($script:ActiveContext) { @(Get-ContextFileList -Directory $script:ActiveContext.DirectorioServicios -Extensions @('.pdf')) } else { @() }
    $ultimaActualizacion = $null
    if ($documentFiles.Count -gt 0) {
        $maximaFecha = $documentFiles | ForEach-Object { [datetime]$_.modificado } | Measure-Object -Maximum
        if ($null -ne $maximaFecha) { $ultimaActualizacion = $maximaFecha.Maximum.ToString('o') }
    }
    $xpzCandidates = @()
    if ($script:ActiveContext) {
        $xpzCandidates = @(foreach ($candidatoXpz in @(Get-ActiveXpzCandidates)) { Convert-XpzForResponse -Xpz $candidatoXpz })
    }
    $activeXpzHash = if ($script:ActiveXpz -and (Test-Path -LiteralPath $script:ActiveXpz.Ruta -PathType Leaf)) { (Obtener-Sha256Archivo -Ruta $script:ActiveXpz.Ruta) } else { $null }
    $lastReview = if ($script:ActiveContext) { Get-LatestContextReport -Type review } else { $null }
    $publicWork = if ($script:CurrentWork) { Get-PublicWork -Work $script:CurrentWork } elseif ($script:LastFinishedWork) { Get-PublicWork -Work $script:LastFinishedWork } else { $null }
    $processedCount = 0
    $processingState = 'NUNCA_PROCESADO'
    $ultimaProcesamiento = $null
    if ($script:ActiveContext -and (Test-Path -LiteralPath $script:ActiveContext.RutaControl -PathType Leaf)) {
        $ultimaProcesamiento = (Get-Item -LiteralPath $script:ActiveContext.RutaControl).LastWriteTimeUtc.ToString('o')
        try {
            $control = Leer-ControlVersiones -RutaControl $script:ActiveContext.RutaControl
            $processedCount = @($control.services.PSObject.Properties).Count
            if ($processedCount -gt 0) { $processingState = 'PROCESADO' }
        } catch { $processingState = 'INCONSISTENTE' }
    }
    $dashboard = [pscustomobject]@{
        contexto = $script:ActiveContext
        kb = if ($script:ActiveContext) { [pscustomobject]@{ path = $script:ActiveContext.KbPath; disponible = (Test-Path -LiteralPath $script:ActiveContext.KbPath -PathType Container) } } else { $null }
        inventario = $inventoryState
        documentos = [pscustomobject]@{ total = $documentFiles.Count; archivos = $documentFiles; ultimaActualizacion = $ultimaActualizacion }
        procesamiento = [pscustomobject]@{ procesado = ($processedCount -gt 0); serviciosProcesados = $processedCount; estado = $processingState; pdfDisponibles = $documentFiles.Count; ultimaActualizacion = $ultimaProcesamiento }
        ultimoReview = $lastReview
        validaciones = @(Get-ContextValidaciones)
        xpz = [pscustomobject]@{ disponibles = $xpzCandidates; activo = if ($script:ActiveXpz) { Convert-XpzForResponse -Xpz $script:ActiveXpz } else { $null }; sha256 = $activeXpzHash }
        herramientas = if ($script:ConfigurationRaw) { $script:ConfigurationRaw.herramientas } else { $null }
        openApi = Get-OpenApiState
        trabajo = $publicWork
    }
    [pscustomobject]@{
        panelVersion = $script:PanelServerVersion
        configurationValid = ($script:ConfigurationErrors.Count -eq 0)
        configurationErrors = @($script:ConfigurationErrors)
        context = $script:ActiveContext
        xpz = if ($script:ActiveXpz) { Convert-XpzForResponse -Xpz $script:ActiveXpz } else { $null }
        work = $publicWork
        dashboard = $dashboard
    }
}

function Invoke-ApiRequest {
    param([Parameter(Mandatory = $true)]$RequestContext)
    $request = $RequestContext.Request
    $route = $request.Url.AbsolutePath.TrimEnd('/')
    if ($route -eq '') { $route = '/' }

    if (-not (Test-LoopbackRequest -Request $request)) {
        Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'El panel solo acepta solicitudes loopback.' }
        return
    }
    if ($request.HttpMethod -eq 'GET' -and $route -match '^/api/trabajos/([^/]+)$') {
        $heartbeatJobId = [System.Uri]::UnescapeDataString($Matches[1])
        if ($script:CurrentWork -and [string]$script:CurrentWork.id -eq $heartbeatJobId -and [string]$script:CurrentWork.estado -in @('QUEUED', 'RUNNING')) {
            $script:CurrentWork.ultimaActividad = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
    Update-CurrentWork

    if ($route -eq '/api/configuracion' -and $request.HttpMethod -eq 'GET') {
        Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = @{ configuracion = $script:ConfigurationRaw; configHash = Get-ConfigurationHash; valida = ($script:ConfigurationErrors.Count -eq 0); errores = @($script:ConfigurationErrors) } }
        return
    }
    if ($route -match '^/api/configuracion/clientes/([^/]+)/ambientes$' -and $request.HttpMethod -eq 'POST') {
        if (-not (Test-SessionToken -Request $request)) { Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'Token de sesion invalido.' }; return }
        try {
            $body = Get-RequestBodyJson -Request $request
            $payload = Get-MutationPayload -Body $body
            $candidate = ($script:ConfigurationRaw | ConvertTo-Json -Depth 15 | ConvertFrom-Json)
            $client = Find-ConfiguredClient -Candidate $candidate -ClientId ([System.Uri]::UnescapeDataString($Matches[1]))
            if ($null -eq $client) { throw 'Cliente no encontrado.' }
            $tipoNormalizado = Clasificar-TipoAmbiente -Tipo ([string]$payload.tipo)
            if ($null -eq $tipoNormalizado) { throw 'El tipo de ambiente debe ser test o prod.' }
            foreach ($propertyName in @('tipo', 'kbPath')) {
                if (-not $payload.PSObject.Properties[$propertyName] -or [string]::IsNullOrWhiteSpace([string]$payload.$propertyName)) {
                    throw ('El ambiente requiere el campo ' + $propertyName + '.')
                }
            }
            Validar-RutaKnowledgeBase -Ruta (Resolver-RutaRepositorio -Ruta ([string]$payload.kbPath) -Raiz $RepositoryRoot) -Contexto ("La Knowledge Base del ambiente '" + (Obtener-IdAmbienteCanonico -Tipo $tipoNormalizado) + "'") | Out-Null
            $hostAmbiente = if ($payload.PSObject.Properties['host'] -and -not [string]::IsNullOrWhiteSpace([string]$payload.host)) { Validar-HostAmbiente -HostUrl ([string]$payload.host) } else { $null }
            $baseUrl = if ($payload.PSObject.Properties['baseUrl'] -and -not [string]::IsNullOrWhiteSpace([string]$payload.baseUrl)) { Validar-BaseUrlAmbiente -BaseUrl ([string]$payload.baseUrl) } else { $null }
            $environment = [pscustomobject]@{ id = (Obtener-IdAmbienteCanonico -Tipo $tipoNormalizado); nombre = (Obtener-NombreAmbienteCanonico -Tipo $tipoNormalizado); tipo = $tipoNormalizado; kbPath = [string]$payload.kbPath; host = $hostAmbiente; baseUrl = $baseUrl }
            $client.ambientes = @($client.ambientes) + $environment
            Write-ConfigurationCandidate -Candidate $candidate -Operation 'CONFIGURACION_AMBIENTE'
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = @{ configHash = Get-ConfigurationHash } }
        } catch { $status = if ($_.Exception.Message -match 'cambio externamente') { 409 } else { 400 }; Write-JsonResponse -RequestContext $RequestContext -StatusCode $status -Payload @{ ok = $false; error = $_.Exception.Message } }
        return
    }
    if ($route -match '^/api/configuracion/clientes/([^/]+)/ambientes/([^/]+)$' -and $request.HttpMethod -eq 'PUT') {
        if (-not (Test-SessionToken -Request $request)) { Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'Token de sesion invalido.' }; return }
        try {
            $body = Get-RequestBodyJson -Request $request; $payload = Get-MutationPayload -Body $body
            $candidate = ($script:ConfigurationRaw | ConvertTo-Json -Depth 15 | ConvertFrom-Json)
            $client = Find-ConfiguredClient -Candidate $candidate -ClientId ([System.Uri]::UnescapeDataString($Matches[1]))
            if ($null -eq $client) { throw 'Cliente no encontrado.' }
            $environment = Find-ConfiguredEnvironment -Client $client -EnvironmentId ([System.Uri]::UnescapeDataString($Matches[2]))
            if ($null -eq $environment) { throw 'Ambiente no encontrado.' }
            $tipoActual = Clasificar-TipoAmbiente -Tipo ([string]$environment.tipo)
            if ($payload.PSObject.Properties['tipo']) {
                $tipoNormalizado = Clasificar-TipoAmbiente -Tipo ([string]$payload.tipo)
                if ($null -eq $tipoNormalizado) { throw 'El tipo de ambiente debe ser test o prod.' }
                $tiposConfigurados = @($client.ambientes | ForEach-Object { Clasificar-TipoAmbiente -Tipo ([string]$_.tipo) })
                $clienteTieneAmbosTipos = $tiposConfigurados -contains 'test' -and $tiposConfigurados -contains 'prod'
                if ($clienteTieneAmbosTipos -and $tipoNormalizado -ne $tipoActual) {
                    throw 'No se puede modificar el tipo de un ambiente cuando el cliente ya tiene TEST y PROD.'
                }
                $tipoActual = $tipoNormalizado
            }
            if (-not $payload.PSObject.Properties['kbPath'] -or [string]::IsNullOrWhiteSpace([string]$payload.kbPath)) { throw 'El ambiente requiere el campo kbPath.' }
            Validar-RutaKnowledgeBase -Ruta (Resolver-RutaRepositorio -Ruta ([string]$payload.kbPath) -Raiz $RepositoryRoot) -Contexto ("La Knowledge Base del ambiente '" + [string]$environment.id + "'") | Out-Null
            $environment.host = if ($payload.PSObject.Properties['host'] -and -not [string]::IsNullOrWhiteSpace([string]$payload.host)) { Validar-HostAmbiente -HostUrl ([string]$payload.host) } else { $null }
            $environment.baseUrl = if ($payload.PSObject.Properties['baseUrl'] -and -not [string]::IsNullOrWhiteSpace([string]$payload.baseUrl)) { Validar-BaseUrlAmbiente -BaseUrl ([string]$payload.baseUrl) } else { $null }
            $environment.tipo = $tipoActual
            $environment.nombre = Obtener-NombreAmbienteCanonico -Tipo $tipoActual
            $environment.kbPath = [string]$payload.kbPath
            Write-ConfigurationCandidate -Candidate $candidate -Operation 'CONFIGURACION_AMBIENTE'
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = @{ configHash = Get-ConfigurationHash } }
        } catch { $status = if ($_.Exception.Message -match 'cambio externamente') { 409 } else { 400 }; Write-JsonResponse -RequestContext $RequestContext -StatusCode $status -Payload @{ ok = $false; error = $_.Exception.Message } }
        return
    }
    if ($route -match '^/api/configuracion/clientes/([^/]+)/ambientes/([^/]+)$' -and $request.HttpMethod -eq 'DELETE') {
        if (-not (Test-SessionToken -Request $request)) { Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'Token de sesion invalido.' }; return }
        try {
            $body = Get-RequestBodyJson -Request $request; if ($body.confirmDelete -ne $true) { throw 'La eliminacion requiere confirmDelete=true.' }
            $null = Get-MutationPayload -Body $body
            $candidate = ($script:ConfigurationRaw | ConvertTo-Json -Depth 15 | ConvertFrom-Json)
            $client = Find-ConfiguredClient -Candidate $candidate -ClientId ([System.Uri]::UnescapeDataString($Matches[1]))
            if ($null -eq $client) { throw 'Cliente no encontrado.' }
            $environmentId = [System.Uri]::UnescapeDataString($Matches[2])
            $client.ambientes = @($client.ambientes | Where-Object { [string]$_.id -cne $environmentId })
            Write-ConfigurationCandidate -Candidate $candidate -Operation 'CONFIGURACION_AMBIENTE'
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = @{ configHash = Get-ConfigurationHash } }
        } catch { $status = if ($_.Exception.Message -match 'cambio externamente') { 409 } else { 400 }; Write-JsonResponse -RequestContext $RequestContext -StatusCode $status -Payload @{ ok = $false; error = $_.Exception.Message } }
        return
    }
    if ($route -match '^/api/configuracion/clientes/([^/]+)$' -and $request.HttpMethod -eq 'PUT') {
        if (-not (Test-SessionToken -Request $request)) { Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'Token de sesion invalido.' }; return }
        try {
            $body = Get-RequestBodyJson -Request $request; $payload = Get-MutationPayload -Body $body
            $candidate = ($script:ConfigurationRaw | ConvertTo-Json -Depth 15 | ConvertFrom-Json)
            $client = Find-ConfiguredClient -Candidate $candidate -ClientId ([System.Uri]::UnescapeDataString($Matches[1]))
            if ($null -eq $client) { throw 'Cliente no encontrado.' }
            foreach ($propertyName in @('nombre', 'packagename', 'serviciosIgnorados')) { if ($payload.PSObject.Properties[$propertyName]) { $client.$propertyName = $payload.$propertyName } }
            Write-ConfigurationCandidate -Candidate $candidate -Operation 'CONFIGURACION_CLIENTE'
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = @{ configHash = Get-ConfigurationHash } }
        } catch { $status = if ($_.Exception.Message -match 'cambio externamente') { 409 } else { 400 }; Write-JsonResponse -RequestContext $RequestContext -StatusCode $status -Payload @{ ok = $false; error = $_.Exception.Message } }
        return
    }
    if ($route -match '^/api/configuracion/clientes/([^/]+)$' -and $request.HttpMethod -eq 'DELETE') {
        if (-not (Test-SessionToken -Request $request)) { Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'Token de sesion invalido.' }; return }
        try {
            $body = Get-RequestBodyJson -Request $request; if ($body.confirmDelete -ne $true) { throw 'La eliminacion requiere confirmDelete=true.' }
            $null = Get-MutationPayload -Body $body
            $candidate = ($script:ConfigurationRaw | ConvertTo-Json -Depth 15 | ConvertFrom-Json)
            $clientId = [System.Uri]::UnescapeDataString($Matches[1])
            $candidate.clientes = @($candidate.clientes | Where-Object { [string]$_.id -cne $clientId })
            Write-ConfigurationCandidate -Candidate $candidate -Operation 'CONFIGURACION_CLIENTE'
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = @{ configHash = Get-ConfigurationHash } }
        } catch { $status = if ($_.Exception.Message -match 'cambio externamente') { 409 } else { 400 }; Write-JsonResponse -RequestContext $RequestContext -StatusCode $status -Payload @{ ok = $false; error = $_.Exception.Message } }
        return
    }
    if ($route -eq '/api/configuracion/clientes' -and $request.HttpMethod -eq 'POST') {
        if (-not (Test-SessionToken -Request $request)) { Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'Token de sesion invalido.' }; return }
        try {
            $body = Get-RequestBodyJson -Request $request; $payload = Get-MutationPayload -Body $body
            $candidate = ($script:ConfigurationRaw | ConvertTo-Json -Depth 15 | ConvertFrom-Json)
            $newClient = Convert-MutationPayloadToNewClient -Payload $payload
            $perfilSolicitado = if ($payload.PSObject.Properties['geneXusExportProfile']) { [string]$payload.geneXusExportProfile } elseif ($candidate.herramientas.PSObject.Properties['geneXusExportProfile']) { [string]$candidate.herramientas.geneXusExportProfile } else { 'Gx18' }
            $perfilNormalizado = Normalize-GeneXusExportProfile -Value $perfilSolicitado
            if ($null -eq $candidate.herramientas) { throw 'La configuracion no define herramientas para guardar el entorno de exportacion.' }
            if ($candidate.herramientas.PSObject.Properties['geneXusExportProfile']) { $candidate.herramientas.geneXusExportProfile = $perfilNormalizado } else { $candidate.herramientas | Add-Member -MemberType NoteProperty -Name geneXusExportProfile -Value $perfilNormalizado }
            $candidate.clientes = @($candidate.clientes) + $newClient
            Write-ConfigurationCandidate -Candidate $candidate -Operation 'CONFIGURACION_CLIENTE'
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = @{ configHash = Get-ConfigurationHash } }
        } catch { $status = if ($_.Exception.Message -match 'cambio externamente') { 409 } else { 400 }; Write-JsonResponse -RequestContext $RequestContext -StatusCode $status -Payload @{ ok = $false; error = $_.Exception.Message } }
        return
    }
    if ($route -eq '/api/configuracion/global' -and $request.HttpMethod -eq 'PUT') {
        if (-not (Test-SessionToken -Request $request)) { Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'Token de sesion invalido.' }; return }
        try {
            $body = Get-RequestBodyJson -Request $request; $payload = Get-MutationPayload -Body $body
            $candidate = ($script:ConfigurationRaw | ConvertTo-Json -Depth 15 | ConvertFrom-Json)
            foreach ($propertyName in @('rutas', 'herramientas', 'exportacion', 'panel')) { if ($payload.PSObject.Properties[$propertyName]) { $candidate.$propertyName = $payload.$propertyName } }
            Write-ConfigurationCandidate -Candidate $candidate -Operation 'CONFIGURACION_GLOBAL'
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = @{ configHash = Get-ConfigurationHash } }
        } catch { $status = if ($_.Exception.Message -match 'cambio externamente') { 409 } else { 400 }; Write-JsonResponse -RequestContext $RequestContext -StatusCode $status -Payload @{ ok = $false; error = $_.Exception.Message } }
        return
    }

    if ($route -eq '/api/estado' -and $request.HttpMethod -eq 'GET') {
        Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = (Get-StateData) }
        return
    }
    if ($route -eq '/api/contextos' -and $request.HttpMethod -eq 'GET') {
        Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = @{ contextos = @(Get-ConfiguredContexts); configurationValid = ($script:ConfigurationErrors.Count -eq 0); errors = @($script:ConfigurationErrors) } }
        return
    }
    if ($route -eq '/api/contexto/activar' -and $request.HttpMethod -eq 'POST') {
        if (-not (Test-SessionToken -Request $request)) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'Token de sesion invalido.' }
            return
        }
        if (Test-WorkInProgress) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'No se puede cambiar el contexto mientras hay un trabajo activo.' }
            return
        }
        try {
            $body = Get-RequestBodyJson -Request $request
            if ($script:ConfigurationErrors.Count -gt 0) { throw 'La configuracion no es valida; el panel permanece en solo lectura.' }
            $script:ActiveContext = Resolver-ContextoConfiguracion -ConfiguracionRaw $script:ConfigurationRaw -ConfigPath $ConfigPath -RaizRepositorio $RepositoryRoot -ClienteId ([string]$body.clienteId) -AmbienteId ([string]$body.ambienteId)
            $script:ActiveXpz = $null
            $script:XpzOverride = $false
            Write-PanelMutationOperation -Operation 'ACTIVAR_CONTEXTO' -Context $script:ActiveContext -Output @('Contexto activo: ' + $script:ActiveContext.ContextId) | Out-Null
            $contextData = [pscustomobject]@{
                contextId = $script:ActiveContext.ContextId
                clienteId = $script:ActiveContext.ClienteId
                clienteNombre = $script:ActiveContext.ClienteNombre
                ambienteId = $script:ActiveContext.AmbienteId
                ambienteNombre = $script:ActiveContext.AmbienteNombre
                ambienteTipo = $script:ActiveContext.AmbienteTipo
                kbPath = $script:ActiveContext.KbPath
                xpzDirectory = $script:ActiveContext.DirectorioXpz
                xpz = if ($script:ActiveXpz) { Convert-XpzForResponse -Xpz $script:ActiveXpz } else { $null }
            }
            $inventoryState = Get-EndpointInventoryState
            if ($script:ActiveXpz -and -not $inventoryState.vigente -and -not (Test-WorkInProgress)) {
                $regenerationWork = Start-EndpointGenerationWork
                Write-JsonResponse -RequestContext $RequestContext -StatusCode 202 -Payload @{ ok = $true; data = $contextData; jobId = $regenerationWork.id; inventory = $inventoryState }
            } else {
                Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = $contextData; inventory = $inventoryState }
            }
        } catch {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 400 -Payload @{ ok = $false; error = $_.Exception.Message }
        }
        return
    }
    if ($route -eq '/api/validar' -and $request.HttpMethod -eq 'POST') {
        if (-not (Test-SessionToken -Request $request)) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'Token de sesion invalido.' }
            return
        }
        if (Test-WorkInProgress) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'Ya existe un trabajo activo.' }
            return
        }
        try {
            $body = Get-RequestBodyJson -Request $request
            $work = Start-ValidationWork -RequestBody $body
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 202 -Payload @{ ok = $true; data = @{ jobId = $work.id } }
        } catch {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = $_.Exception.Message }
        }
        return
    }
    if ($route -eq '/api/exportar' -and $request.HttpMethod -eq 'POST') {
        if (-not (Test-SessionToken -Request $request)) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'Token de sesion invalido.' }
            return
        }
        if (Test-WorkInProgress) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'Ya existe un trabajo activo.' }
            return
        }
        try {
            $body = Get-RequestBodyJson -Request $request
            $work = if ([string]$body.modo -eq 'completar') { Start-CompleteXpzWork -RequestBody $body } else { Start-ExportWork -RequestBody $body }
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 202 -Payload @{ ok = $true; data = @{ jobId = $work.id } }
        } catch {
            $errorMessage = $_.Exception.Message
            if ($errorMessage -match 'No se encontro GeneXus|No se encontro MSBuild|No existe la Knowledge Base|Knowledge Base.*no existe|\.gxw') {
                $failedWork = New-ImmediateFailedWork -Operation 'EXPORTAR_XPZ' -Context $script:ActiveContext -ErrorMessage $errorMessage
                Write-JsonResponse -RequestContext $RequestContext -StatusCode 202 -Payload @{ ok = $true; data = @{ jobId = $failedWork.id } }
            } else {
                Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = $errorMessage }
            }
        }
        return
    }
    if ($route -eq '/api/generar-pdf' -and $request.HttpMethod -eq 'POST') {
        if (-not (Test-SessionToken -Request $request)) { Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'Token de sesion invalido.' }; return }
        if (Test-WorkInProgress) { Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'Ya existe un trabajo activo.' }; return }
        try { $body = Get-RequestBodyJson -Request $request; $work = Start-PdfGenerationWork -RequestBody $body; Write-JsonResponse -RequestContext $RequestContext -StatusCode 202 -Payload @{ ok = $true; data = @{ jobId = $work.id } } }
        catch {
            $statusCode = if ($_.Exception.Message -match '^PRECONDICION_XPZ:') { 409 } else { 400 }
            Write-JsonResponse -RequestContext $RequestContext -StatusCode $statusCode -Payload @{ ok = $false; error = $_.Exception.Message }
        }
        return
    }
    if ($route -eq '/api/openapi' -and $request.HttpMethod -eq 'POST') {
        if (-not (Test-SessionToken -Request $request)) { Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'Token de sesion invalido.' }; return }
        if (Test-WorkInProgress) { Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'Ya existe un trabajo activo.' }; return }
        try {
            $work = Start-OpenApiGenerationWork
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 202 -Payload @{ ok = $true; data = @{ jobId = $work.id } }
        } catch { Write-JsonResponse -RequestContext $RequestContext -StatusCode 400 -Payload @{ ok = $false; error = $_.Exception.Message } }
        return
    }
    if ($route -eq '/api/openapi' -and $request.HttpMethod -eq 'GET') {
        if ($null -eq $script:ActiveContext) { Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'No hay un contexto activo.' }; return }
        $openApiPath = Join-Path $script:ActiveContext.DirectorioServicios 'OpenAPI\openapi.json'
        if (-not (Test-Path -LiteralPath $openApiPath -PathType Leaf)) { Write-JsonResponse -RequestContext $RequestContext -StatusCode 404 -Payload @{ ok = $false; error = 'openapi.json no encontrado.' }; return }
        Write-TextResponse -RequestContext $RequestContext -StatusCode 200 -Content ([System.IO.File]::ReadAllText($openApiPath, [System.Text.Encoding]::UTF8)) -ContentType 'application/json; charset=utf-8'
        return
    }
    if ($route -eq '/api/documentos' -and $request.HttpMethod -eq 'GET') {
        if ($null -eq $script:ActiveContext) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'No hay un contexto activo.' }
            return
        }
        Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = @{ documentos = @(Get-PublishedPdfCatalog) } }
        return
    }
    if ($route -eq '/api/servicios' -and $request.HttpMethod -eq 'GET') {
        if ($null -eq $script:ActiveContext -or $null -eq $script:ActiveXpz) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'No hay un contexto y XPZ activos.' }
            return
        }
        try {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = @{ servicios = @(Get-EnrichedServices) } }
        } catch {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 500 -Payload @{ ok = $false; error = $_.Exception.Message }
        }
        return
    }
    if ($route -match '^/api/documentos/([^/]+)$' -and $request.HttpMethod -eq 'GET') {
        if ($null -eq $script:ActiveContext) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'No hay un contexto activo.' }
            return
        }
        $documentName = [System.Uri]::UnescapeDataString($Matches[1])
        $documentPath = Get-ContextDocumentPath -Name $documentName
        if ($null -eq $documentPath) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 400 -Payload @{ ok = $false; error = 'Nombre de documento no permitido.' }
            return
        }
        if (-not (Test-Path -LiteralPath $documentPath -PathType Leaf)) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 404 -Payload @{ ok = $false; error = 'Documento no encontrado.' }
            return
        }
        $extension = [System.IO.Path]::GetExtension($documentPath).ToLowerInvariant()
        $downloadRequested = (Get-QueryValue -Request $request -Name 'download') -match '^(?i:true|1|si|sí|yes)$'
        if ($extension -eq '.pdf') {
            $contentType = if ($downloadRequested) { 'application/octet-stream' } else { 'application/pdf' }
            $contentDisposition = if ($downloadRequested) { 'attachment' } else { 'inline' }
            $downloadName = Get-QueryValue -Request $request -Name 'filename'
            if ([string]::IsNullOrWhiteSpace($downloadName)) { $downloadName = $documentName }
            Write-BytesResponse -RequestContext $RequestContext -StatusCode 200 -Bytes ([System.IO.File]::ReadAllBytes($documentPath)) -ContentType $contentType -ContentDisposition $contentDisposition -DownloadName $downloadName
        }
        else { Write-TextResponse -RequestContext $RequestContext -StatusCode 200 -Content ([System.IO.File]::ReadAllText($documentPath, [System.Text.Encoding]::UTF8)) -ContentType 'text/markdown; charset=utf-8' }
        return
    }
    if ($route -eq '/api/logs' -and $request.HttpMethod -eq 'GET') {
        if ($null -eq $script:ActiveContext) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'No hay un contexto activo.' }
            return
        }
        $operationType = Get-QueryValue -Request $request -Name 'tipo'
        $severity = Get-QueryValue -Request $request -Name 'severidad'
        $historyValue = Get-QueryValue -Request $request -Name 'historial'
        $history = $historyValue -match '^(?i:true|1|si|sí|yes)$'
        $operationLogs = @(Get-OperationLogCatalog -OperationType $operationType -Severity $severity -History $history)
        $contextFiles = @(Get-ContextLogCatalog)
        $logs = @($operationLogs) + @($contextFiles)
        Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = @{ logs = $logs; resumen = $logs; historial = $history; filtros = @{ tipo = $operationType; severidad = $severity } } }
        return
    }
    if ($route -match '^/api/logs/([^/]+)$' -and $request.HttpMethod -eq 'GET') {
        if ($null -eq $script:ActiveContext) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'No hay un contexto activo.' }
            return
        }
        $logName = [System.Uri]::UnescapeDataString($Matches[1])
        $logPath = Get-ContextLogPath -Name $logName
        if ($null -eq $logPath) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 400 -Payload @{ ok = $false; error = 'Nombre de log no permitido.' }
            return
        }
        if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 404 -Payload @{ ok = $false; error = 'Log no encontrado.' }
            return
        }
        Write-TextResponse -RequestContext $RequestContext -StatusCode 200 -Content ([System.IO.File]::ReadAllText($logPath, [System.Text.Encoding]::UTF8)) -ContentType 'text/plain; charset=utf-8'
        return
    }
    if ($route -eq '/api/reportes/historial' -and $request.HttpMethod -eq 'GET') {
        if ($null -eq $script:ActiveContext) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'No hay un contexto activo.' }
            return
        }
        $historyPath = $script:ActiveContext.RutaHistorial
        $history = if (Test-Path -LiteralPath $historyPath -PathType Leaf) { [System.IO.File]::ReadAllText($historyPath, [System.Text.Encoding]::UTF8) } else { '' }
        Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = @{ disponible = (-not [string]::IsNullOrWhiteSpace($history)); contenido = $history } }
        return
    }
    if ($route -eq '/api/reportes/review-ultimo' -and $request.HttpMethod -eq 'GET') {
        if ($null -eq $script:ActiveContext) { Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'No hay un contexto activo.' }; return }
        Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = (Get-LatestContextReport -Type review) }
        return
    }
    if ($route -eq '/api/reportes/validacion-ultima' -and $request.HttpMethod -eq 'GET') {
        if ($null -eq $script:ActiveContext) { Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'No hay un contexto activo.' }; return }
        Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = (Get-LatestContextReport -Type validation) }
        return
    }
    if ($route -eq '/api/documentos' -and $request.HttpMethod -eq 'POST') {
        if (-not (Test-SessionToken -Request $request)) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'Token de sesion invalido.' }
            return
        }
        if (Test-WorkInProgress) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'Ya existe un trabajo activo.' }
            return
        }
        try {
            $body = Get-RequestBodyJson -Request $request
            $work = Start-DocumentationWork -RequestBody $body
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 202 -Payload @{ ok = $true; data = @{ jobId = $work.id } }
        } catch {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 400 -Payload @{ ok = $false; error = $_.Exception.Message }
        }
        return
    }
    if ($route -eq '/api/actualizar' -and $request.HttpMethod -eq 'POST') {
        if (-not (Test-SessionToken -Request $request)) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'Token de sesion invalido.' }
            return
        }
        if (Test-WorkInProgress) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'Ya existe un trabajo activo.' }
            return
        }
        try {
            $body = Get-RequestBodyJson -Request $request
            if ($null -eq $body.mode) { $body | Add-Member -MemberType NoteProperty -Name mode -Value 'all' }
            $work = Start-DocumentationWork -RequestBody $body
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 202 -Payload @{ ok = $true; data = @{ jobId = $work.id } }
        } catch {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 400 -Payload @{ ok = $false; error = $_.Exception.Message }
        }
        return
    }
    if ($route -eq '/api/reiniciar' -and $request.HttpMethod -eq 'POST') {
        if (-not (Test-SessionToken -Request $request)) { Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'Token de sesion invalido.' }; return }
        if (Test-WorkInProgress) { Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'Ya existe un trabajo activo.' }; return }
        try {
            $body = Get-RequestBodyJson -Request $request
            $body | Add-Member -MemberType NoteProperty -Name mode -Value 'all' -Force
            $body | Add-Member -MemberType NoteProperty -Name reiniciar -Value $true -Force
            $work = Start-DocumentationWork -RequestBody $body
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 202 -Payload @{ ok = $true; data = @{ jobId = $work.id } }
        } catch { Write-JsonResponse -RequestContext $RequestContext -StatusCode 400 -Payload @{ ok = $false; error = $_.Exception.Message } }
        return
    }
    if ($route -eq '/api/endpoints' -and $request.HttpMethod -eq 'GET') {
        if ($null -eq $script:ActiveContext) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'No hay un contexto activo.' }
            return
        }
        $inventoryState = Get-EndpointInventoryState
        Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = $inventoryState }
        return
    }
    if ($route -eq '/api/endpoints/regenerar' -and $request.HttpMethod -eq 'POST') {
        if (-not (Test-SessionToken -Request $request)) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'Token de sesion invalido.' }
            return
        }
        if (Test-WorkInProgress) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'Ya existe un trabajo activo.' }
            return
        }
        try {
            $work = Start-EndpointGenerationWork
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 202 -Payload @{ ok = $true; data = @{ jobId = $work.id } }
        } catch {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = $_.Exception.Message }
        }
        return
    }
    if ($route -match '^/api/trabajos/([^/]+)/cancelar$' -and $request.HttpMethod -eq 'POST') {
        if (-not (Test-SessionToken -Request $request)) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'Token de sesion invalido.' }
            return
        }
        try {
            $jobId = [System.Uri]::UnescapeDataString($Matches[1])
            $work = Cancel-CurrentWork -JobId $jobId
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = (Get-PublicWork -Work $work) }
        } catch {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = $_.Exception.Message }
        }
        return
    }
    if ($route -match '^/api/trabajos/([^/]+)$' -and $request.HttpMethod -eq 'GET') {
        Update-CurrentWork
        $jobId = [System.Uri]::UnescapeDataString($Matches[1])
        $work = if ($script:CurrentWork -and $script:CurrentWork.id -eq $jobId) { $script:CurrentWork } elseif ($script:LastFinishedWork -and $script:LastFinishedWork.id -eq $jobId) { $script:LastFinishedWork } else { $null }
        if ($null -eq $work) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 404 -Payload @{ ok = $false; error = 'Trabajo no encontrado en la sesion.' }
        } else {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = (Get-PublicWork -Work $work) }
        }
        return
    }
    if ($route -eq '/api/xpz' -and $request.HttpMethod -eq 'GET') {
        if ($null -eq $script:ActiveContext) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'No hay un contexto activo.' }
            return
        }
        Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = @{ xpz = @(foreach ($candidatoXpz in @(Get-ActiveXpzCandidates)) { Convert-XpzForResponse -Xpz $candidatoXpz }); activo = if ($script:ActiveXpz) { Convert-XpzForResponse -Xpz $script:ActiveXpz } else { $null } } }
        return
    }
    if ($route -eq '/api/xpz/activar' -and $request.HttpMethod -eq 'POST') {
        if (-not (Test-SessionToken -Request $request)) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'Token de sesion invalido.' }
            return
        }
        if (Test-WorkInProgress) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'No se puede cambiar el XPZ mientras hay un trabajo activo.' }
            return
        }
        try {
            if ($null -eq $script:ActiveContext) { throw 'No hay un contexto activo.' }
            $body = Get-RequestBodyJson -Request $request
            $selected = @(Get-ActiveXpzCandidates | Where-Object { $_.Nombre -ceq [string]$body.nombre })
            if ($selected.Count -ne 1) { throw 'El XPZ indicado no pertenece al contexto activo.' }
            $script:ActiveXpz = $selected[0]
            $script:XpzOverride = $true
            Write-PanelMutationOperation -Operation 'ACTIVAR_XPZ' -Context $script:ActiveContext -Xpz $script:ActiveXpz -Output @('XPZ activo: ' + $script:ActiveXpz.Nombre) | Out-Null
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = (Convert-XpzForResponse -Xpz $script:ActiveXpz) }
        } catch {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 400 -Payload @{ ok = $false; error = $_.Exception.Message }
        }
        return
    }
    Write-JsonResponse -RequestContext $RequestContext -StatusCode 404 -Payload @{ ok = $false; error = 'Ruta API no encontrada.' }
}

function Invoke-PanelRequest {
    param([Parameter(Mandatory = $true)]$RequestContext)
    if ($RequestContext.Request.Url.AbsolutePath.StartsWith('/api/', [System.StringComparison]::OrdinalIgnoreCase)) {
        Invoke-ApiRequest -RequestContext $RequestContext
    } else {
        Send-StaticFile -RequestContext $RequestContext
    }
}

Read-PanelConfiguration
$portToUse = Get-PanelPort
$script:Listener = New-Object System.Net.HttpListener
$script:Listener.Prefixes.Add(('http://127.0.0.1:' + $portToUse + '/'))
try {
    $script:Listener.Start()
} catch {
    Write-Error ('No se pudo iniciar el panel en 127.0.0.1:' + $portToUse + '. El puerto puede estar ocupado. ' + $_.Exception.Message)
    exit 1
}

Write-Host ('Panel web escuchando en http://127.0.0.1:' + $portToUse + '/')
if (-not $NoBrowser) { Start-Process ('http://127.0.0.1:' + $portToUse + '/') }

try {
    while ($script:Listener.IsListening) {
        try {
            $requestContext = $script:Listener.GetContext()
            Invoke-PanelRequest -RequestContext $requestContext
        } catch [System.Net.HttpListenerException] {
            if ($script:Listener.IsListening) { Write-Warning $_.Exception.Message }
        } catch {
            if ($requestContext) {
                try { Write-JsonResponse -RequestContext $requestContext -StatusCode 500 -Payload @{ ok = $false; error = 'Error interno del panel.' } } catch { }
            }
        }
    }
} finally {
    if ($script:CurrentWork -and $script:CurrentWork.process -and -not $script:CurrentWork.process.HasExited) {
        $shutdownLog = [string]$script:CurrentWork.log
        try {
            & taskkill.exe /PID $script:CurrentWork.process.Id /T /F 2>&1 | Out-File -FilePath $shutdownLog -Append -Encoding utf8
            Add-Content -LiteralPath $shutdownLog -Value 'El servidor termino el arbol del proceso hijo al cerrarse.'
        } catch {
            Add-Content -LiteralPath $shutdownLog -Value ('No se pudo terminar el proceso hijo al cerrar: ' + $_.Exception.Message)
        }
    }
    if ($script:Listener) { $script:Listener.Close() }
}
