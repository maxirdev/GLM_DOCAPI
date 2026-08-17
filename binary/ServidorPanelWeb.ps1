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

. (Join-Path $PSScriptRoot 'CargarConfiguracion.ps1')
. (Join-Path $PSScriptRoot 'CargarMultiXPZ.ps1')
. (Join-Path $PSScriptRoot 'ManifiestoEjecucion.ps1')

$script:SessionToken = [Guid]::NewGuid().ToString('N')
$script:ConfigurationRaw = $null
$script:ConfigurationErrors = New-Object System.Collections.Generic.List[string]
$script:ActiveContext = $null
$script:ActiveXpz = $null
$script:XpzOverride = $false
$script:CurrentWork = $null
$script:LastFinishedWork = $null
$script:Listener = $null

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
                ambienteNombre = [string]$environment.nombre
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

function Convert-XpzForResponse {
    param([Parameter(Mandatory = $true)]$Xpz)
    return [pscustomobject]@{
        nombre = $Xpz.Nombre
        ruta = $Xpz.Ruta
        fecha = $Xpz.Fecha.ToUniversalTime().ToString('o')
        principal = [bool]$Xpz.EsPrincipal
        activo = ($null -ne $script:ActiveXpz -and $script:ActiveXpz.Ruta -eq $Xpz.Ruta)
    }
}

function Test-WorkInProgress {
    return ($null -ne $script:CurrentWork -and [string]$script:CurrentWork.estado -in @('QUEUED', 'RUNNING'))
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

function Get-WorkTail {
    param([Parameter(Mandatory = $true)]$Work)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($Work.stdoutPath, $Work.stderrPath)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            foreach ($line in @(Get-Content -LiteralPath $path -Tail 20 -ErrorAction SilentlyContinue)) { [void]$lines.Add([string]$line) }
        }
    }
    return @($lines | Select-Object -Last 20)
}

function Get-PublicWork {
    param([Parameter(Mandatory = $true)]$Work)
    [pscustomobject]@{
        id = $Work.id
        contextId = $Work.contextId
        operacion = $Work.operacion
        estado = $Work.estado
        log = $Work.log
        inicio = $Work.inicio
        fin = $Work.fin
        codigoSalida = $Work.codigoSalida
        progreso = $Work.progreso
        warnings = @($Work.warnings)
        error = $Work.error
        ultimasLineas = @(Get-WorkTail -Work $Work)
    }
}

function Update-CurrentWork {
    if ($null -eq $script:CurrentWork) { return }
    $work = $script:CurrentWork
    if ([string]$work.estado -notin @('QUEUED', 'RUNNING')) { return }
    if (-not $work.process.HasExited) {
        $work.estado = 'RUNNING'
        $work.progreso = [pscustomobject]@{ indeterminado = $true; porcentaje = $null }
        return
    }

    $work.codigoSalida = [int]$work.process.ExitCode
    $work.estado = Get-WorkStatusFromExitCode -ExitCode $work.codigoSalida
    $work.fin = (Get-Date).ToUniversalTime().ToString('o')
    $work.progreso = [pscustomobject]@{ indeterminado = $false; porcentaje = 100 }
    $output = Get-WorkTail -Work $work
    $header = 'Trabajo ' + $work.id + ' | ' + $work.operacion + ' | codigo ' + $work.codigoSalida
    [System.IO.File]::WriteAllLines($work.log, @($header) + $output, (New-Object System.Text.UTF8Encoding($false)))
    if ($work.codigoSalida -eq 1) { $work.error = 'El proceso hijo termino con errores.' }
    $script:LastFinishedWork = $work
    $script:CurrentWork = $null
}

function Quote-ProcessArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Start-ValidationWork {
    if ($null -eq $script:ActiveContext) { throw 'No hay un contexto activo.' }
    if ($null -eq $script:ActiveXpz) { throw 'No hay un XPZ activo en el contexto.' }
    $jobId = 'panel-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + ([Guid]::NewGuid().ToString('N').Substring(0, 8))
    $jobsDirectory = Join-Path $script:ActiveContext.DirectorioLogs 'panel-jobs'
    New-Item -ItemType Directory -Path $jobsDirectory -Force | Out-Null
    $logPath = Join-Path $script:ActiveContext.DirectorioLogs ($jobId + '.log')
    $stdoutPath = Join-Path $jobsDirectory ($jobId + '.out')
    $stderrPath = Join-Path $jobsDirectory ($jobId + '.err')
    $manifestBase = Join-Path $jobsDirectory $jobId
    $manifest = Crear-ManifiestoEjecucion -Xpz $script:ActiveXpz.Ruta -FullyQualifiedNames @() -DirectorioBase $manifestBase -Contexto $script:ActiveContext
    $powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $scriptPath = Join-Path $RepositoryRoot 'binary\ValidarXPZ.ps1'
    $argumentValues = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath, '-ConfigPath', $ConfigPath, '-XpzPath', $script:ActiveXpz.Ruta, '-ManifiestoPath', $manifest.Ruta)
    $argumentText = (($argumentValues | ForEach-Object { Quote-ProcessArgument -Value ([string]$_) }) -join ' ')
    $process = Start-Process -FilePath $powerShellPath -ArgumentList $argumentText -WorkingDirectory $RepositoryRoot -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru
    $script:CurrentWork = [pscustomobject]@{
        id = $jobId
        contextId = $script:ActiveContext.ContextId
        operacion = 'VALIDAR_XPZ'
        estado = 'RUNNING'
        log = $logPath
        inicio = (Get-Date).ToUniversalTime().ToString('o')
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

function Start-EndpointGenerationWork {
    if ($null -eq $script:ActiveContext) { throw 'No hay un contexto activo.' }
    if ($null -eq $script:ActiveXpz) { throw 'No hay un XPZ activo en el contexto.' }
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
        [Parameter(Mandatory = $true)]$Context
    )
    $jobId = 'panel-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + ([Guid]::NewGuid().ToString('N').Substring(0, 8))
    $jobsDirectory = Join-Path $Context.DirectorioLogs 'panel-jobs'
    New-Item -ItemType Directory -Path $jobsDirectory -Force | Out-Null
    $logPath = Join-Path $Context.DirectorioLogs ($jobId + '.log')
    $stdoutPath = Join-Path $jobsDirectory ($jobId + '.out')
    $stderrPath = Join-Path $jobsDirectory ($jobId + '.err')
    $powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argumentText = (($ArgumentValues | ForEach-Object { Quote-ProcessArgument -Value ([string]$_) }) -join ' ')
    $process = Start-Process -FilePath $powerShellPath -ArgumentList $argumentText -WorkingDirectory $RepositoryRoot -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru
    $script:CurrentWork = [pscustomobject]@{
        id = $jobId
        contextId = $Context.ContextId
        operacion = $Operation
        estado = 'RUNNING'
        log = $logPath
        inicio = (Get-Date).ToUniversalTime().ToString('o')
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

function Start-ExportWork {
    param([Parameter(Mandatory = $true)]$RequestBody)
    if ($null -eq $script:ActiveContext) { throw 'No hay un contexto activo.' }
    $policy = [string]$RequestBody.policy
    if ([string]::IsNullOrWhiteSpace($policy)) { $policy = 'abort' }
    if ($policy -notin @('abort', 'continue')) { throw 'policy debe ser abort o continue.' }
    $scriptPath = Join-Path $RepositoryRoot 'binary\EjecutarExportacionGLM.ps1'
    $arguments = @('-File', $scriptPath, '-Repositorio', $RepositoryRoot, '-ClienteId', $script:ActiveContext.ClienteId, '-AmbienteId', $script:ActiveContext.AmbienteId, '-ConfirmarExportacionCompleta', '-PoliticaPendientes', $policy)
    $work = Start-PanelChildWork -Operation 'EXPORTAR_XPZ' -ScriptPath $scriptPath -ArgumentValues $arguments -Context $script:ActiveContext
    if ($policy -eq 'continue') { $work.warnings = @('La politica continue permite conservar un XPZ incompleto y pendientes visibles.') }
    return $work
}

function Start-DocumentationWork {
    param([Parameter(Mandatory = $true)]$RequestBody)
    if ($null -eq $script:ActiveContext -or $null -eq $script:ActiveXpz) { throw 'No hay contexto y XPZ activos.' }
    $mode = [string]$RequestBody.mode
    $selectedNames = @($RequestBody.fullyQualifiedNames | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($mode -notin @('selected', 'all')) { throw 'mode debe ser selected o all.' }
    if ($mode -eq 'selected' -and $selectedNames.Count -eq 0) { throw 'selected exige al menos un FQN.' }
    if ($mode -eq 'all' -and $selectedNames.Count -gt 0) { throw 'all no admite FQN.' }
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
    $jobsDirectory = Join-Path $script:ActiveContext.DirectorioLogs 'panel-jobs'
    $manifest = Crear-ManifiestoEjecucion -Xpz $script:ActiveXpz.Ruta -FullyQualifiedNames $selectedNames -DirectorioBase (Join-Path $jobsDirectory ('documentacion-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))) -Contexto $script:ActiveContext
    $scriptPath = Join-Path $RepositoryRoot 'binary\ActualizarServicios.ps1'
    $arguments = @('-File', $scriptPath, '-ConfigPath', $ConfigPath, '-ManifiestoPath', $manifest.Ruta)
    if ($mode -eq 'all') { $arguments += '-ForzarRegeneracionCompleta' }
    return Start-PanelChildWork -Operation 'PUBLICAR_DOCUMENTACION' -ScriptPath $scriptPath -ArgumentValues $arguments -Context $script:ActiveContext
}

function Test-SafeLogicalName {
    param([Parameter(Mandatory = $true)][string]$Name)
    if ($Name.Length -gt 180 -or $Name -match '%|\.\.|[\\/:]' -or $Name -ne [System.Uri]::UnescapeDataString($Name)) { return $false }
    return ($Name -cmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$')
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

function Write-BytesResponse {
    param(
        [Parameter(Mandatory = $true)]$RequestContext,
        [Parameter(Mandatory = $true)][int]$StatusCode,
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$ContentType
    )
    $response = $RequestContext.Response
    $response.StatusCode = $StatusCode
    $response.ContentType = $ContentType
    $response.Headers['Cache-Control'] = 'no-store'
    $response.Headers['Content-Disposition'] = 'inline'
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
    return Join-Path $script:ActiveContext.DirectorioLogs $Name
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
    return (Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256).Hash.ToLowerInvariant()
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
    Validar-ConfiguracionMulticliente -ConfiguracionRaw $Candidate -RaizRepositorio $RepositoryRoot -ConfigPath $ConfigPath | Out-Null
}

function Reset-PanelSession {
    $script:ActiveContext = $null
    $script:ActiveXpz = $null
    $script:XpzOverride = $false
    $script:LastFinishedWork = $null
}

function Write-ConfigurationCandidate {
    param([Parameter(Mandatory = $true)]$Candidate)
    Test-ConfigurationCandidate -Candidate $Candidate
    $content = Normalizar-SaltosLineaLf -Texto ($Candidate | ConvertTo-Json -Depth 15)
    Escribir-ArchivoAtomico -Ruta $ConfigPath -Contenido $content | Out-Null
    $script:ConfigurationRaw = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $script:ConfigurationErrors.Clear()
    Reset-PanelSession
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
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Depth 12 -Compress))
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
    if ($logicalPath -notmatch '^/(index\.html|app\.js|style\.css|favicon\.svg)$') {
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
    $content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    if ([System.IO.Path]::GetFileName($path) -eq 'index.html') {
        $tokenScript = '<script>window.PANEL_TOKEN="' + $script:SessionToken + '";</script>'
        $content = $content.Replace('</head>', $tokenScript + '</head>')
    }
    Write-TextResponse -RequestContext $RequestContext -StatusCode 200 -Content $content -ContentType (Get-ContentType -Path $path)
}

function Get-StateData {
    Update-CurrentWork
    [pscustomobject]@{
        configurationValid = ($script:ConfigurationErrors.Count -eq 0)
        configurationErrors = @($script:ConfigurationErrors)
        context = $script:ActiveContext
        xpz = if ($script:ActiveXpz) { Convert-XpzForResponse -Xpz $script:ActiveXpz } else { $null }
        work = if ($script:CurrentWork) { Get-PublicWork -Work $script:CurrentWork } elseif ($script:LastFinishedWork) { Get-PublicWork -Work $script:LastFinishedWork } else { $null }
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
            $environment = [pscustomobject]@{ id = [string]$payload.id; nombre = [string]$payload.nombre; kbPath = [string]$payload.kbPath }
            $client.ambientes = @($client.ambientes) + $environment
            Write-ConfigurationCandidate -Candidate $candidate
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
            foreach ($propertyName in @('nombre', 'kbPath')) { if ($payload.PSObject.Properties[$propertyName]) { $environment.$propertyName = [string]$payload.$propertyName } }
            Write-ConfigurationCandidate -Candidate $candidate
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
            Write-ConfigurationCandidate -Candidate $candidate
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
            Write-ConfigurationCandidate -Candidate $candidate
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
            Write-ConfigurationCandidate -Candidate $candidate
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = @{ configHash = Get-ConfigurationHash } }
        } catch { $status = if ($_.Exception.Message -match 'cambio externamente') { 409 } else { 400 }; Write-JsonResponse -RequestContext $RequestContext -StatusCode $status -Payload @{ ok = $false; error = $_.Exception.Message } }
        return
    }
    if ($route -eq '/api/configuracion/clientes' -and $request.HttpMethod -eq 'POST') {
        if (-not (Test-SessionToken -Request $request)) { Write-JsonResponse -RequestContext $RequestContext -StatusCode 403 -Payload @{ ok = $false; error = 'Token de sesion invalido.' }; return }
        try {
            $body = Get-RequestBodyJson -Request $request; $payload = Get-MutationPayload -Body $body
            $candidate = ($script:ConfigurationRaw | ConvertTo-Json -Depth 15 | ConvertFrom-Json)
            $newClient = [pscustomobject]@{ id = [string]$payload.id; nombre = [string]$payload.nombre; packagename = [string]$payload.packagename; serviciosIgnorados = @($payload.serviciosIgnorados); ambientes = @($payload.ambientes) }
            $candidate.clientes = @($candidate.clientes) + $newClient
            Write-ConfigurationCandidate -Candidate $candidate
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
            Write-ConfigurationCandidate -Candidate $candidate
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
            $script:ActiveXpz = @(Get-ActiveXpzCandidates | Sort-Object Fecha | Select-Object -Last 1)
            if ($script:ActiveXpz.Count -eq 0) { $script:ActiveXpz = $null } else { $script:ActiveXpz = $script:ActiveXpz[0] }
            $script:XpzOverride = $false
            $contextData = [pscustomobject]@{
                contextId = $script:ActiveContext.ContextId
                clienteId = $script:ActiveContext.ClienteId
                clienteNombre = $script:ActiveContext.ClienteNombre
                ambienteId = $script:ActiveContext.AmbienteId
                ambienteNombre = $script:ActiveContext.AmbienteNombre
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
            $work = Start-ValidationWork
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
            $work = Start-ExportWork -RequestBody $body
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 202 -Payload @{ ok = $true; data = @{ jobId = $work.id } }
        } catch {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = $_.Exception.Message }
        }
        return
    }
    if ($route -eq '/api/documentos' -and $request.HttpMethod -eq 'GET') {
        if ($null -eq $script:ActiveContext) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'No hay un contexto activo.' }
            return
        }
        Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = @{ documentos = @(Get-ContextFileList -Directory $script:ActiveContext.DirectorioServicios -Extensions @('.md', '.pdf')) } }
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
        if ($extension -eq '.pdf') { Write-BytesResponse -RequestContext $RequestContext -StatusCode 200 -Bytes ([System.IO.File]::ReadAllBytes($documentPath)) -ContentType 'application/pdf' }
        else { Write-TextResponse -RequestContext $RequestContext -StatusCode 200 -Content ([System.IO.File]::ReadAllText($documentPath, [System.Text.Encoding]::UTF8)) -ContentType 'text/markdown; charset=utf-8' }
        return
    }
    if ($route -eq '/api/logs' -and $request.HttpMethod -eq 'GET') {
        if ($null -eq $script:ActiveContext) {
            Write-JsonResponse -RequestContext $RequestContext -StatusCode 409 -Payload @{ ok = $false; error = 'No hay un contexto activo.' }
            return
        }
        Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = @{ logs = @(Get-ContextFileList -Directory $script:ActiveContext.DirectorioLogs -Extensions @('.log', '.json', '.txt')) } }
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
        Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = @{ xpz = @(Get-ActiveXpzCandidates | ForEach-Object { Convert-XpzForResponse -Xpz $_ }); activo = if ($script:ActiveXpz) { Convert-XpzForResponse -Xpz $script:ActiveXpz } else { $null } } }
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
            $inventoryState = Get-EndpointInventoryState
            if (-not $inventoryState.vigente) {
                $regenerationWork = Start-EndpointGenerationWork
                Write-JsonResponse -RequestContext $RequestContext -StatusCode 202 -Payload @{ ok = $true; data = (Convert-XpzForResponse -Xpz $script:ActiveXpz); jobId = $regenerationWork.id; inventory = $inventoryState }
            } else {
                Write-JsonResponse -RequestContext $RequestContext -StatusCode 200 -Payload @{ ok = $true; data = (Convert-XpzForResponse -Xpz $script:ActiveXpz); inventory = $inventoryState }
            }
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
