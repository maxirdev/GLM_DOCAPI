[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$MsbuildPath,
    [Parameter(Mandatory = $true)][string]$ProjectFile,
    [Parameter(Mandatory = $true)][string]$GxProgramDir,
    [Parameter(Mandatory = $true)][string]$KbPath,
    [Parameter(Mandatory = $true)][string]$XpzFile,
    [Parameter(Mandatory = $true)][string]$LogFile
)

$ErrorActionPreference = 'Stop'

function Quote-ProcessArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Start-Phase {
    param(
        [Parameter(Mandatory = $true)][int]$Number,
        [Parameter(Mandatory = $true)][string]$Name
    )

    Write-Host ("[{0}/5] {1} ... |" -f $Number, $Name) -NoNewline
}

function Update-Spinner {
    param([int]$Position)

    $spinner = @('|', '/', '-', '\')
    Write-Host ("`b{0}" -f $spinner[$Position % $spinner.Count]) -NoNewline
}

function Finish-Phase {
    param([ValidateSet('OK', 'ERROR')][string]$Result)

    Write-Host ("`b{0}" -f $Result)
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

$stdoutFile = "$LogFile.stdout.tmp"
$stderrFile = "$LogFile.stderr.tmp"
$arguments = @(
    (Quote-ProcessArgument $ProjectFile),
    '/t:ExportarAPIGLM',
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
    'Exportando APIGLM y sus referencias',
    'Comprimiendo el XPZ',
    'Cerrando la Knowledge Base'
)
$phaseNumber = 1
$spinnerPosition = 0
$phaseCheckCounter = 0
$process = $null

try {
    Start-Phase -Number $phaseNumber -Name $phaseNames[$phaseNumber - 1]

    $process = Start-Process `
        -FilePath $MsbuildPath `
        -ArgumentList $arguments `
        -WorkingDirectory (Split-Path -Parent $ProjectFile) `
        -RedirectStandardOutput $stdoutFile `
        -RedirectStandardError $stderrFile `
        -WindowStyle Hidden `
        -PassThru

    while (-not $process.HasExited) {
        if ($phaseCheckCounter -eq 0) {
            $recentText = (Get-RecentOutputText -Paths @($stdoutFile, $stderrFile)) -join "`n"
            $nextPhase = $phaseNumber

            if ($recentText -match 'Open Knowledge Base Task started') {
                $nextPhase = [Math]::Max($nextPhase, 2)
            }
            if ($recentText -match 'Export started') {
                $nextPhase = [Math]::Max($nextPhase, 3)
            }
            if ($recentText -match 'Compressing output file') {
                $nextPhase = [Math]::Max($nextPhase, 4)
            }
            if ($recentText -match 'Close Knowledge Base Task started') {
                $nextPhase = [Math]::Max($nextPhase, 5)
            }

            while ($phaseNumber -lt $nextPhase) {
                Finish-Phase -Result 'OK'
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
    $allLines = @()
    foreach ($path in @($stdoutFile, $stderrFile)) {
        if (Test-Path -LiteralPath $path) {
            $allLines += @(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)
        }
    }

    $finalText = $allLines -join "`n"
    $finalPhase = $phaseNumber
    if ($finalText -match 'Open Knowledge Base Task started') { $finalPhase = [Math]::Max($finalPhase, 2) }
    if ($finalText -match 'Export started') { $finalPhase = [Math]::Max($finalPhase, 3) }
    if ($finalText -match 'Compressing output file') { $finalPhase = [Math]::Max($finalPhase, 4) }
    if ($finalText -match 'Close Knowledge Base Task started') { $finalPhase = [Math]::Max($finalPhase, 5) }
    while ($phaseNumber -lt $finalPhase) {
        Finish-Phase -Result 'OK'
        $phaseNumber++
        Start-Phase -Number $phaseNumber -Name $phaseNames[$phaseNumber - 1]
    }

    $successDetected = @($allLines | Where-Object { $_ -match 'Export Success' }).Count -gt 0
    $errors = @($allLines | Where-Object {
        $_ -match '(?i)^\s*(error\b|msb\d{4}\b|exception\b|fatal\b)' -or
        $_ -match '(?i)\s(error|fatal|exception)\s*:'
    } | Select-Object -Unique)
    $exitCode = if ($process.ExitCode -eq 0 -and $successDetected -and $errors.Count -eq 0) { 0 } else { 1 }

    if ($exitCode -eq 0) { Finish-Phase -Result 'OK' } else { Finish-Phase -Result 'ERROR' }

    if ($errors.Count -gt 0) {
        Write-Host 'Mensajes de error detectados:' -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    }

    exit $exitCode
} finally {
    if ($null -ne $process) {
        $process.Refresh()
        if (-not $process.HasExited) {
            $process.Kill()
            $process.WaitForExit()
        }
        $process.Dispose()
    }

    Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
}
