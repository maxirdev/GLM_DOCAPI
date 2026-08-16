# Validación inicial del lanzador unificado APIGLM.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)][AllowEmptyString()][string]$Repositorio
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Repositorio)) {
    Write-Host ''
    Write-Host '  [ERROR DE ARRANQUE] No se recibio la ruta del repositorio.' -ForegroundColor Red
    Write-Host '  Verifique que GenerarDocumentosGLM.cmd se ejecute desde una copia valida del proyecto.' -ForegroundColor Yellow
    exit 1
}

$raizRepositorio = [System.IO.Path]::GetFullPath($Repositorio)
$rutaConfiguracion = Join-Path $raizRepositorio 'configuracion.json'
$rutaDirectorioXpz = Join-Path $raizRepositorio 'xpz'

. (Join-Path $PSScriptRoot 'GLMUtilidades.ps1')

function Escribir-Estado {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('OK', 'ERROR', 'ADVERTENCIA', 'PENDIENTE')][string]$Estado,
        [Parameter(Mandatory = $true)][string]$Mensaje
    )

    $color = 'Gray'
    if ($Estado -eq 'OK') { $color = 'Green' }
    if ($Estado -eq 'ERROR') { $color = 'Red' }
    if ($Estado -eq 'ADVERTENCIA') { $color = 'Yellow' }
    if ($Estado -eq 'PENDIENTE') { $color = 'DarkYellow' }
    Write-Host ("  [{0}] {1}" -f $Estado, $Mensaje) -ForegroundColor $color
}

function Crear-ModeloConfiguracion {
    $modelo = @'
{
  "xpz": "",
  "packagename": "",
  "cliente": "",
  "serviciosIgnorados": [],
  "herramientas": {
    "geneXusProgramDir": "",
    "kbPath": "",
    "msbuildPath": "",
    "pandocPath": "binary/tools/pandoc.exe",
    "typstPath": "binary/tools/typst.exe"
  }
}
'@
    Escribir-TextoUtf8SinBom -Ruta $rutaConfiguracion -Contenido (Normalizar-SaltosLineaLf -Texto $modelo)
}

Write-Host 'Validacion inicial de la aplicacion APIGLM' -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $rutaConfiguracion -PathType Leaf)) {
    Crear-ModeloConfiguracion
    Escribir-Estado -Estado PENDIENTE -Mensaje ("Se creo el modelo de configuracion en " + $rutaConfiguracion + ". Complete sus datos y vuelva a ejecutar el lanzador.")
    exit 1
}

try {
    $configuracion = Get-Content -LiteralPath $rutaConfiguracion -Raw | ConvertFrom-Json
} catch {
    Escribir-Estado -Estado ERROR -Mensaje ("configuracion.json no contiene JSON valido: " + $_.Exception.Message)
    exit 1
}

$xpzConfigurado = [string]$configuracion.xpz
$packageName = [string]$configuracion.packagename
$herramientas = $configuracion.herramientas

Escribir-Estado -Estado OK -Mensaje 'configuracion.json existe y puede leerse.'

if ([string]::IsNullOrWhiteSpace($packageName)) {
    Escribir-Estado -Estado ERROR -Mensaje 'La propiedad packagename no esta completada.'
    exit 1
}
Escribir-Estado -Estado OK -Mensaje ("PackageName: " + $packageName)

if (-not (Test-Path -LiteralPath $rutaDirectorioXpz -PathType Container)) {
    Escribir-Estado -Estado ADVERTENCIA -Mensaje ("No existe la carpeta de XPZ: " + $rutaDirectorioXpz)
    exit 2
}

$archivosXpz = @(Get-ChildItem -LiteralPath $rutaDirectorioXpz -Filter '*.xpz' -File -ErrorAction SilentlyContinue)
if ($archivosXpz.Count -eq 0) {
    Escribir-Estado -Estado ADVERTENCIA -Mensaje ("No hay archivos .xpz en " + $rutaDirectorioXpz)
    exit 2
}
Escribir-Estado -Estado OK -Mensaje ("Archivos XPZ disponibles: " + $archivosXpz.Count)

$rutaXpzAbsoluta = $xpzConfigurado
if ([string]::IsNullOrWhiteSpace($rutaXpzAbsoluta)) {
    Escribir-Estado -Estado ADVERTENCIA -Mensaje 'No hay un XPZ asociado en la configuracion.'
    $xpzActivo = $false
} else {
    if (-not [System.IO.Path]::IsPathRooted($rutaXpzAbsoluta)) {
        $rutaXpzAbsoluta = Join-Path $raizRepositorio $rutaXpzAbsoluta
    }

    if (-not (Test-Path -LiteralPath $rutaXpzAbsoluta -PathType Leaf)) {
        Escribir-Estado -Estado ADVERTENCIA -Mensaje ("El XPZ configurado no existe: " + $xpzConfigurado + ". No se seleccionara otro automaticamente.")
        $xpzActivo = $false
    } else {
        Escribir-Estado -Estado OK -Mensaje ("XPZ activo: " + ([System.IO.Path]::GetFullPath($rutaXpzAbsoluta)))
        $xpzActivo = $true
    }
}

$rutasHerramientas = @(
    [pscustomobject]@{ Nombre = 'GeneXus'; Propiedad = 'geneXusProgramDir'; Tipo = 'Container' },
    [pscustomobject]@{ Nombre = 'Knowledge Base'; Propiedad = 'kbPath'; Tipo = 'Container' },
    [pscustomobject]@{ Nombre = 'MSBuild'; Propiedad = 'msbuildPath'; Tipo = 'Leaf' },
    [pscustomobject]@{ Nombre = 'Pandoc'; Propiedad = 'pandocPath'; Tipo = 'Leaf' },
    [pscustomobject]@{ Nombre = 'Typst'; Propiedad = 'typstPath'; Tipo = 'Leaf' }
)

foreach ($rutaHerramienta in $rutasHerramientas) {
    $valor = ''
    if ($null -ne $herramientas) {
        $valor = [string]$herramientas.($rutaHerramienta.Propiedad)
    }

    if ([string]::IsNullOrWhiteSpace($valor)) {
        Escribir-Estado -Estado PENDIENTE -Mensaje ("Falta la ruta de " + $rutaHerramienta.Nombre + " en herramientas." + $rutaHerramienta.Propiedad)
        continue
    }

    $rutaResuelta = $valor
    if (-not [System.IO.Path]::IsPathRooted($rutaResuelta)) {
        $rutaResuelta = Join-Path $raizRepositorio $rutaResuelta
    }
    if (Test-Path -LiteralPath $rutaResuelta -PathType $rutaHerramienta.Tipo) {
        Escribir-Estado -Estado OK -Mensaje ($rutaHerramienta.Nombre + ': ' + $rutaResuelta)
    } else {
        Escribir-Estado -Estado ADVERTENCIA -Mensaje ($rutaHerramienta.Nombre + ' no se encontro en: ' + $valor)
    }
}

if ($xpzActivo) {
    exit 0
}

exit 2
