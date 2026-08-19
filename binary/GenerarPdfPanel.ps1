# Ejecuta el paso 3 del lanzador sin interacción de consola.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Repositorio,
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$XpzActivo,
    [Parameter(Mandatory = $true)][string]$ManifiestoPath
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($Repositorio)
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Invoke-Step {
    param([string]$ScriptPath, [string[]]$Arguments)
    & $ps -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Invoke-Step (Join-Path $root 'binary\CompletarXPZActivoGLM.ps1') @(
    '-Repositorio', $root, '-XpzActivo', $XpzActivo, '-ManifiestoPath', $ManifiestoPath,
    '-PoliticaPendientes', 'continue'
)
Invoke-Step (Join-Path $root 'binary\ActualizarServicios.ps1') @(
    '-ConfigPath', $ConfigPath, '-ManifiestoPath', $ManifiestoPath,
    '-ForzarRegeneracionCompleta', '-Inicializar'
)
Invoke-Step (Join-Path $root 'binary\ResumirOperacionPdf.ps1') @(
    '-Repositorio', $root, '-ManifiestoPath', $ManifiestoPath
)
exit 0
