# CargarConfiguracion.ps1
# Modulo de carga de configuracion centralizada para el pipeline APIGLM.
# Se importa por dot-source desde los scripts que necesiten la configuracion.
# Resuelve las rutas relativas contra el directorio raiz del repositorio.
$ErrorActionPreference = 'Stop'

function Cargar-Configuracion {
    <#
    .SYNOPSIS
    Carga configuracion.json desde la raiz del repositorio y resuelve las rutas.
    .DESCRIPTION
    Lee el archivo configuracion.json, resuelve la ruta del XPZ relativa a la
    raiz del proyecto contra una ruta absoluta, y permite un override explicito
    de XpzPath. Devuelve el objeto de configuracion con todas las rutas resueltas.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][string]$ConfigPath,
        [Parameter(Mandatory = $false)][string]$XpzPath
    )

    $raizRepositorio = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $raizRepositorio 'configuracion.json'
    }

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw ("No se encontro el archivo de configuracion: " + $ConfigPath)
    }

    $ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path

    $configuracionRaw = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

    $rutaXpzRelativa = [string]$configuracionRaw.xpz
    if (-not $rutaXpzRelativa) {
        throw 'La configuracion no define la propiedad xpz.'
    }

    $rutaXpzResuelta = (Resolve-Path (Join-Path $raizRepositorio $rutaXpzRelativa)).Path

    if ($XpzPath) {
        if (-not (Test-Path -LiteralPath $XpzPath)) {
            throw ("No se encontro el XPZ indicado en -XpzPath: " + $XpzPath)
        }
        $rutaXpzResuelta = (Resolve-Path -LiteralPath $XpzPath).Path
    }

    $packageName = [string]$configuracionRaw.packagename
    if (-not $packageName) {
        throw 'La configuracion no define packagename.'
    }

    $serviciosIgnorados = @()
    if ($configuracionRaw.serviciosIgnorados -and @($configuracionRaw.serviciosIgnorados).Count -gt 0) {
        $serviciosIgnorados = @($configuracionRaw.serviciosIgnorados | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
    }

    return [pscustomobject]@{
        ConfigPath = $ConfigPath
        XpzPath = $rutaXpzResuelta
        PackageName = $packageName
        Cliente = [string]$configuracionRaw.cliente
        ServiciosIgnorados = $serviciosIgnorados
        RaizRepositorio = $raizRepositorio
    }
}
