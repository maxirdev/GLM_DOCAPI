[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$MsbuildPath,
    [Parameter(Mandatory = $true)][string]$ProjectFile,
    [Parameter(Mandatory = $true)][string]$GxProgramDir,
    [Parameter(Mandatory = $true)][string]$KbPath,
    [Parameter(Mandatory = $true)][string]$XpzFile,
    [Parameter(Mandatory = $true)][string]$LogFile,
    [ValidateSet('ExportarAPIGLM', 'ExportarTodaLaKB')]
    [string]$TargetName = 'ExportarAPIGLM'
)

$ErrorActionPreference = 'Stop'

$onlyModuleAPIGLM = ($TargetName -eq 'ExportarAPIGLM')

$instanciasGeneXus = @(Get-Process -Name 'GeneXus' -ErrorAction SilentlyContinue)
if ($instanciasGeneXus.Count -gt 0) {
    Write-Host ''
    Write-Host ('ADVERTENCIA: se detectaron ' + $instanciasGeneXus.Count + ' instancia(s) de GeneXus abierta(s).') -ForegroundColor Yellow
    Write-Host 'La exportacion continuara usando una sesion independiente de MSBuild.' -ForegroundColor Yellow
    Write-Host 'No edite objetos ni ejecute especificaciones, generaciones o reorganizaciones durante la exportacion.' -ForegroundColor Yellow
    Write-Host ''
}

function Quote-ProcessArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Start-Phase {
    param(
        [Parameter(Mandatory = $true)][int]$Number,
        [Parameter(Mandatory = $true)][string]$Name
    )

    # Cada fase debe terminar en salto de linea para que el proceso padre
    # la muestre inmediatamente, incluso cuando la salida esta redirigida.
    Write-Host ("[{0}/5] {1} ..." -f $Number, $Name)
}

function Update-Spinner {
    param([int]$Position)

    # No usar retrocesos ni -NoNewline: la salida se consume desde otro
    # proceso de PowerShell y esos caracteres retrasan la visualizacion.
}

function Finish-Phase {
    param([ValidateSet('OK', 'ERROR')][string]$Result)

    Write-Host ("    Resultado: " + $Result)
}

function Update-ProcessOutput {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][System.Text.StringBuilder]$Buffer
    )

    while ($null -ne $State.Task -and $State.Task.IsCompleted) {
        try {
            $line = $State.Task.GetAwaiter().GetResult()
        } catch {
            $line = $null
        }

        if ($null -eq $line) {
            $State.Task = $null
            break
        }

        [void]$Buffer.AppendLine($line)
        $State.Task = $State.Reader.ReadLineAsync()
    }
}

function Get-RecentOutputText {
    param([string[]]$Paths)

    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }

        $stream = $null
        try {
            $stream = [System.IO.File]::Open(
                $path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite)
            if ($stream.Length -eq 0) { continue }

            $start = [Math]::Max([int64]0, $stream.Length - 8192)
            $stream.Seek($start, [System.IO.SeekOrigin]::Begin) | Out-Null
            $buffer = New-Object byte[] ([int]($stream.Length - $start))
            $read = $stream.Read($buffer, 0, $buffer.Length)
            [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
        } catch {
        } finally {
            if ($null -ne $stream) { $stream.Dispose() }
        }
    }
}

function Test-XpzFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ Valid = $false; Error = 'no se encontro el archivo XPZ esperado' }
    }

    $zip = $null
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $xmlEntries = @($zip.Entries | Where-Object { $_.Name -like '*.xml' })
        if ($xmlEntries.Count -ne 1) {
            return [pscustomobject]@{ Valid = $false; Error = "el XPZ contiene $($xmlEntries.Count) archivos XML; se esperaba uno" }
        }

        $reader = New-Object System.IO.StreamReader($xmlEntries[0].Open())
        try {
            $xml = New-Object System.Xml.XmlDocument
            $xml.LoadXml($reader.ReadToEnd())
        } finally {
            $reader.Dispose()
        }

        if ($xml.DocumentElement.LocalName -ne 'ExportFile') {
            return [pscustomobject]@{ Valid = $false; Error = "la raiz XML es $($xml.DocumentElement.LocalName); se esperaba ExportFile" }
        }

        return [pscustomobject]@{ Valid = $true; Error = '' }
    } catch {
        return [pscustomobject]@{ Valid = $false; Error = "el XPZ no es valido: $($_.Exception.Message)" }
    } finally {
        if ($null -ne $zip) { $zip.Dispose() }
    }
}

function Get-DescendantProcessIds {
    param(
        [Parameter(Mandatory = $true)][int]$RootProcessId,
        [Parameter(Mandatory = $true)][datetime]$StartedAfter
    )

    $result = New-Object System.Collections.Generic.List[int]
    $pending = New-Object System.Collections.Generic.Queue[int]
    $pending.Enqueue($RootProcessId)
    $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)

    while ($pending.Count -gt 0) {
        $parentId = $pending.Dequeue()
        foreach ($child in $processes | Where-Object { $_.ParentProcessId -eq $parentId }) {
            $created = $null
            try {
                if ($child.CreationDate -is [datetime]) {
                    $created = [datetime]$child.CreationDate
                } else {
                    $created = [System.Management.ManagementDateTimeConverter]::ToDateTime([string]$child.CreationDate)
                }
            } catch {}
            if ($null -ne $created -and $created -lt $StartedAfter.AddSeconds(-2)) { continue }
            if (-not $result.Contains([int]$child.ProcessId)) {
                $result.Add([int]$child.ProcessId)
                $pending.Enqueue([int]$child.ProcessId)
            }
        }
    }

    return @($result)
}

$targetName = $TargetName
Write-Host ('Target MSBuild: ' + $targetName) -ForegroundColor DarkGray
$arguments = @(
    (Quote-ProcessArgument $ProjectFile),
    "/t:$targetName",
    (Quote-ProcessArgument "/p:GX_PROGRAM_DIR=$GxProgramDir"),
    (Quote-ProcessArgument "/p:KBPath=$KbPath"),
    (Quote-ProcessArgument "/p:XPZFile=$XpzFile"),
    '/nologo',
    '/verbosity:minimal',
    '/fl',
    (Quote-ProcessArgument "/flp:logfile=$LogFile;verbosity=normal")
)

$phaseNames = @(
    'Iniciando MSBuild',
    'Abriendo la Knowledge Base',
    $(if ($onlyModuleAPIGLM) { 'Exportando APIGLM y sus referencias' } else { 'Exportando todos los objetos de la Knowledge Base' }),
    'Comprimiendo el XPZ',
    'Cerrando la Knowledge Base'
)
$phaseNumber = 1
$spinnerPosition = 0
$phaseCheckCounter = 0
$process = $null
$stdoutState = $null
$stderrState = $null
$processOutput = New-Object System.Text.StringBuilder
$processStartedAt = Get-Date
$lastProgressNoticeAt = $processStartedAt
$progressNoticeInterval = [TimeSpan]::FromMinutes(3)
$processId = 0
$scriptExitCode = 1

try {
    Start-Phase -Number $phaseNumber -Name $phaseNames[$phaseNumber - 1]

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $MsbuildPath
    $startInfo.Arguments = $arguments -join ' '
    $startInfo.WorkingDirectory = Split-Path -Parent $ProjectFile
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $processStartedAt = Get-Date
    if (-not $process.Start()) {
        throw 'No se pudo iniciar MSBuild.'
    }
    $processId = $process.Id
    $stdoutState = [pscustomobject]@{
        Reader = $process.StandardOutput
        Task = $process.StandardOutput.ReadLineAsync()
    }
    $stderrState = [pscustomobject]@{
        Reader = $process.StandardError
        Task = $process.StandardError.ReadLineAsync()
    }

    while (-not $process.HasExited) {
        Update-ProcessOutput -State $stdoutState -Buffer $processOutput
        Update-ProcessOutput -State $stderrState -Buffer $processOutput

        if (-not $onlyModuleAPIGLM) {
            $elapsed = (Get-Date) - $processStartedAt
            if (($elapsed - $lastProgressNoticeAt) -ge $progressNoticeInterval) {
                Write-Host ("La exportacion completa de la Knowledge Base continua en ejecucion. Tiempo transcurrido: {0:hh\:mm\:ss}." -f $elapsed) -ForegroundColor Cyan
                $lastProgressNoticeAt = Get-Date
            }
        }

        if ($phaseCheckCounter -eq 0) {
            $recentText = ((Get-RecentOutputText -Paths @($LogFile)) -join "`n") + "`n" + $processOutput.ToString()
            $nextPhase = $phaseNumber

            if ($recentText -match 'Open Knowledge Base Task started|Abriendo Knowledge Base:') {
                $nextPhase = [Math]::Max($nextPhase, 2)
            }
            if ($recentText -match 'Export started|Exportando Module:APIGLM|Exporting Module.*APIGLM') {
                $nextPhase = [Math]::Max($nextPhase, 3)
            }
            if ($recentText -match 'Compressing output file|Comprimiendo el archivo') {
                $nextPhase = [Math]::Max($nextPhase, 4)
            }
            if ($recentText -match 'Close Knowledge Base Task started|Cerrando Knowledge Base') {
                $nextPhase = [Math]::Max($nextPhase, 5)
            }

            while ($phaseNumber -lt $nextPhase) {
                $phaseResult = 'OK'
                if ($nextPhase -ge 5) {
                    if ($phaseNumber -eq 4 -and ($recentText -notmatch 'Export Success' -or -not (Test-Path -LiteralPath $XpzFile -PathType Leaf))) {
                        $phaseResult = 'ERROR'
                    } elseif ($phaseNumber -eq 3 -and $recentText -notmatch 'Compressing output file') {
                        $phaseResult = 'ERROR'
                    }
                }
                Finish-Phase -Result $phaseResult
                $phaseNumber++
                Start-Phase -Number $phaseNumber -Name $phaseNames[$phaseNumber - 1]
            }
        }

        $spinnerPosition++
        Update-Spinner -Position $spinnerPosition
        $phaseCheckCounter = ($phaseCheckCounter + 1) % 2
        Start-Sleep -Milliseconds 500
        $process.Refresh()
    }

    $process.WaitForExit()
    while ($null -ne $stdoutState.Task -or $null -ne $stderrState.Task) {
        Update-ProcessOutput -State $stdoutState -Buffer $processOutput
        Update-ProcessOutput -State $stderrState -Buffer $processOutput
        if ($null -ne $stdoutState.Task -or $null -ne $stderrState.Task) {
            Start-Sleep -Milliseconds 10
        }
    }
    $processExitCode = $process.ExitCode
    $allText = @($processOutput.ToString(), (Get-Content -LiteralPath $LogFile -Raw -ErrorAction SilentlyContinue)) -join "`n"
    $allLines = $allText -split "`r?`n"

    $finalText = $allText
    $finalPhase = $phaseNumber
    if ($finalText -match 'Open Knowledge Base Task started|Abriendo Knowledge Base:') { $finalPhase = [Math]::Max($finalPhase, 2) }
    if ($finalText -match 'Export started|Exportando Module:APIGLM|Exporting Module.*APIGLM') { $finalPhase = [Math]::Max($finalPhase, 3) }
    if ($finalText -match 'Compressing output file|Comprimiendo el archivo') { $finalPhase = [Math]::Max($finalPhase, 4) }
    if ($finalText -match 'Close Knowledge Base Task started|Cerrando Knowledge Base') { $finalPhase = [Math]::Max($finalPhase, 5) }
    while ($phaseNumber -lt $finalPhase) {
        $phaseResult = 'OK'
        if ($finalPhase -ge 5) {
            if ($phaseNumber -eq 4 -and ($finalText -notmatch 'Export Success' -or -not (Test-Path -LiteralPath $XpzFile -PathType Leaf))) {
                $phaseResult = 'ERROR'
            } elseif ($phaseNumber -eq 3 -and $finalText -notmatch 'Compressing output file') {
                $phaseResult = 'ERROR'
            }
        }
        Finish-Phase -Result $phaseResult
        $phaseNumber++
        Start-Phase -Number $phaseNumber -Name $phaseNames[$phaseNumber - 1]
    }

    $exportSuccess = $finalText -match 'Export Success'
    $closeSuccess = $finalText -match 'Close Knowledge Base Task Success'
    $xpzValidation = Test-XpzFile -Path $XpzFile
    $errors = @($allLines | Where-Object {
        $_ -match '(?i)^\s*(error\b|msb\d{4}\b|exception\b|fatal\b)' -or
        $_ -match '(?i)\s(error|fatal|exception)\s*:'
    } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
    $scriptExitCode = if ($processExitCode -eq 0 -and $exportSuccess -and $closeSuccess -and $xpzValidation.Valid -and $errors.Count -eq 0) { 0 } else { 1 }

    $lastPhaseResult = if ($phaseNumber -eq 5 -and $closeSuccess) { 'OK' } elseif ($scriptExitCode -eq 0) { 'OK' } else { 'ERROR' }
    Finish-Phase -Result $lastPhaseResult

    if ($processExitCode -ne 0) {
        Write-Host "MSBuild termino con codigo $processExitCode." -ForegroundColor Red
    }
    if (-not $exportSuccess) {
        Write-Host 'No se encontro la confirmacion de exportacion de GeneXus.' -ForegroundColor Red
    }
    if (-not $closeSuccess) {
        Write-Host 'No se encontro la confirmacion de cierre de la Knowledge Base.' -ForegroundColor Red
    }
    if (-not $xpzValidation.Valid) {
        Write-Host ("El XPZ no supero la validacion: " + $xpzValidation.Error + '.') -ForegroundColor Red
    }

    if ($errors.Count -gt 0) {
        Write-Host 'Mensajes de error detectados:' -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    }

} catch {
    if ($phaseNumber -ge 1) { Finish-Phase -Result 'ERROR' }
    Write-Host ("Error durante la exportacion: " + $_.Exception.Message) -ForegroundColor Red
    $scriptExitCode = 1
} finally {
    if ($null -ne $process) {
        if ($processId -gt 0) {
            if (-not $process.HasExited) {
                if (-not $process.WaitForExit(5000)) {
                    & "$env:SystemRoot\System32\taskkill.exe" /PID $processId /T /F 2>&1 | Out-Null
                    $process.WaitForExit(5000) | Out-Null
                }
            }
        }
        $process.Dispose()
    }

    if ($processId -gt 0) {
        $descendants = @(Get-DescendantProcessIds -RootProcessId $processId -StartedAfter $processStartedAt)
        foreach ($descendantId in ($descendants | Sort-Object -Descending)) {
            Stop-Process -Id $descendantId -Force -ErrorAction SilentlyContinue
        }

        if ($descendants.Count -gt 0) { Start-Sleep -Milliseconds 250 }
        $remainingDescendants = @(Get-DescendantProcessIds -RootProcessId $processId -StartedAfter $processStartedAt)
        if ($remainingDescendants.Count -gt 0) {
            Write-Host ("No se pudieron cerrar los procesos descendientes: " + ($remainingDescendants -join ', ') + '.') -ForegroundColor Red
            $scriptExitCode = 1
        }
    }
}

exit $scriptExitCode
