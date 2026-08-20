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
. (Join-Path $root 'binary\GLMUtilidades.ps1')
. (Join-Path $root 'binary\ManifiestoEjecucion.ps1')
$manifiestoEjecucion = Leer-ManifiestoEjecucion -RutaManifiesto $ManifiestoPath

function Invoke-Step {
    param([string]$ScriptPath, [string[]]$Arguments)
    & $ps -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Invoke-Step (Join-Path $root 'binary\CompletarXPZActivoGLM.ps1') @(
    '-Repositorio', $root, '-XpzActivo', $XpzActivo, '-ManifiestoPath', $ManifiestoPath,
    '-PoliticaPendientes', 'continue', '-Scope', $(if (@($manifiestoEjecucion.fullyQualifiedNames).Count -gt 0) { 'SELECTIVE' } else { 'FULL' })
)
$argumentosActualizar = @(
    '-ConfigPath', $ConfigPath, '-ManifiestoPath', $ManifiestoPath, '-XpzPath', $XpzActivo
)
if (@($manifiestoEjecucion.fullyQualifiedNames).Count -eq 0) {
    $argumentosActualizar += @('-ForzarRegeneracionCompleta', '-Inicializar')
}
Invoke-Step (Join-Path $root 'binary\ActualizarServicios.ps1') $argumentosActualizar
Invoke-Step (Join-Path $root 'binary\ResumirOperacionPdf.ps1') @(
    '-Repositorio', $root, '-ManifiestoPath', $ManifiestoPath
)
exit 0
