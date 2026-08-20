# Validación inicial del lanzador unificado APIGLM (esquema multicliente).

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)][AllowEmptyString()][string]$Repositorio,
    [Parameter(Mandatory = $false)][AllowEmptyString()][string]$ConfigPath,
    [Parameter(Mandatory = $false)][AllowEmptyString()][string]$ClienteId,
    [Parameter(Mandatory = $false)][AllowEmptyString()][string]$AmbienteId
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Repositorio)) {
    Write-Host ''
    Write-Host '  [ERROR DE ARRANQUE] No se recibio la ruta del repositorio.' -ForegroundColor Red
    Write-Host '  Verifique que GenerarDocumentosGLM.cmd se ejecute desde una copia valida del proyecto.' -ForegroundColor Yellow
    exit 1
}

$raizRepositorio = [System.IO.Path]::GetFullPath($Repositorio)
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $rutaConfiguracion = Join-Path $raizRepositorio 'configuracion.json'
} else {
    $rutaConfiguracion = [System.IO.Path]::GetFullPath($ConfigPath)
}

. (Join-Path $PSScriptRoot 'GLMUtilidades.ps1')
. (Join-Path $PSScriptRoot 'CargarConfiguracion.ps1')

Inicializar-ConsolaUtf8

function Escribir-Estado {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('OK', 'ERROR', 'ADVERTENCIA', 'PENDIENTE')][string]$Estado,
        [Parameter(Mandatory = $true)][string]$Mensaje
    )

    $color = 'Gray'
    if ($Estado -eq 'OK') { $color = 'Green' }
    if ($Estado -eq 'ERROR') { $color = 'Red' }
    if ($Estado -eq 'ADVERTENCIA') { $color = 'Yellow' }
    if ($Estado -eq 'PENDIENTE') { $color = 'Yellow' }
    Write-Host ("  [{0}] {1}" -f $Estado, $Mensaje) -ForegroundColor $color
}

function Crear-ModeloConfiguracion {
    $modelo = @'
{
  "rutas": {
    "clientesRoot": "clientes"
  },
  "exportacion": {
    "onlyModuleAPIGLM": true
  },
  "herramientas": {
    "geneXusProgramDir": "",
    "msbuildPath": "",
    "pandocPath": "binary/tools/pandoc.exe",
    "typstPath": "binary/tools/typst.exe"
  },
  "clientes": []
}
'@
    Escribir-TextoUtf8SinBom -Ruta $rutaConfiguracion -Contenido (Normalizar-SaltosLineaLf -Texto $modelo)
}

function Crear-ArbolContextual {
    <#
    .SYNOPSIS
    Crea el arbol contextual de un ambiente valido bajo clientes/<clienteId>/<ambienteId>/.
    .DESCRIPTION
    Solo se ejecuta despues de que el esquema global, las herramientas, el cliente,
    el ambiente y la KB hayan pasado la validacion. Crea exactamente los seis
    directorios del contrato de la SPEC 19.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DirectorioContexto
    )
    $directorios = @(
        [System.IO.Path]::GetFullPath((Join-Path $DirectorioContexto 'documentacionServicios'))
        [System.IO.Path]::GetFullPath((Join-Path $DirectorioContexto 'estado'))
        [System.IO.Path]::GetFullPath((Join-Path $DirectorioContexto 'xpz'))
        [System.IO.Path]::GetFullPath((Join-Path $DirectorioContexto 'Logs'))
        [System.IO.Path]::GetFullPath((Join-Path $DirectorioContexto 'test\fixtures'))
        [System.IO.Path]::GetFullPath((Join-Path $DirectorioContexto 'test\resultados'))
    )
    foreach ($directorio in $directorios) {
        Asegurar-Directorio -Ruta $directorio
    }
    Escribir-Estado -Estado OK -Mensaje ("Arbol contextual creado en " + $DirectorioContexto + " (" + $directorios.Count + " directorios).")
}

Write-Host 'Validacion inicial de la aplicacion APIGLM' -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $rutaConfiguracion -PathType Leaf)) {
    Crear-ModeloConfiguracion
    Escribir-Estado -Estado PENDIENTE -Mensaje ("Se creo el modelo de configuracion en " + $rutaConfiguracion + ". Complete sus datos y vuelva a ejecutar el lanzador.")
    exit 1
}

$configuracionRaw = $null
try {
    $configuracionRaw = Get-Content -LiteralPath $rutaConfiguracion -Raw | ConvertFrom-Json
} catch {
    Escribir-Estado -Estado ERROR -Mensaje ("configuracion.json no contiene JSON valido: " + $_.Exception.Message)
    exit 1
}

if ($null -ne $configuracionRaw.xpz -and $null -eq $configuracionRaw.clientes) {
    Escribir-Estado -Estado ERROR -Mensaje 'La configuracion usa el esquema monocliente anterior, que no es compatible con este lanzador. Reemplace configuracion.json por el esquema multicliente de la SPEC 19.'
    exit 1
}

$configuracionValidada = $null
try {
    $configuracionValidada = Validar-ConfiguracionMulticliente -ConfiguracionRaw $configuracionRaw -RaizRepositorio $raizRepositorio -ConfigPath $rutaConfiguracion
} catch {
    Escribir-Estado -Estado ERROR -Mensaje ($_.Exception.Message)
    exit 1
}
Escribir-Estado -Estado OK -Mensaje 'configuracion.json usa el esquema multicliente y es valida.'

$rutasHerramientas = @(
    [pscustomobject]@{ Nombre = 'GeneXus'; Propiedad = 'geneXusProgramDir'; Tipo = 'Container' },
    [pscustomobject]@{ Nombre = 'MSBuild'; Propiedad = 'msbuildPath'; Tipo = 'Leaf' },
    [pscustomobject]@{ Nombre = 'Pandoc'; Propiedad = 'pandocPath'; Tipo = 'Leaf' },
    [pscustomobject]@{ Nombre = 'Typst'; Propiedad = 'typstPath'; Tipo = 'Leaf' }
)

foreach ($rutaHerramienta in $rutasHerramientas) {
    $valor = [string]$configuracionValidada.herramientas.($rutaHerramienta.Propiedad)
    $rutaResuelta = Resolver-RutaRepositorio -Ruta $valor -Raiz $raizRepositorio
    if (Test-Path -LiteralPath $rutaResuelta -PathType $rutaHerramienta.Tipo) {
        Escribir-Estado -Estado OK -Mensaje ($rutaHerramienta.Nombre + ': ' + $rutaResuelta)
    } else {
        Escribir-Estado -Estado ADVERTENCIA -Mensaje ($rutaHerramienta.Nombre + ' no se encontro en: ' + $valor)
    }
}

if ([string]::IsNullOrWhiteSpace($ClienteId) -or [string]::IsNullOrWhiteSpace($AmbienteId)) {
    Escribir-Estado -Estado PENDIENTE -Mensaje 'No se selecciono cliente y ambiente; se valido solo el esquema global. Seleccione un contexto para el preflight completo.'
    exit 0
}

$contexto = $null
try {
    $contexto = Resolver-ContextoConfiguracion -ConfiguracionRaw $configuracionValidada -ConfigPath $rutaConfiguracion -RaizRepositorio $raizRepositorio -ClienteId $ClienteId -AmbienteId $AmbienteId
} catch {
    Escribir-Estado -Estado ERROR -Mensaje ($_.Exception.Message)
    exit 1
}
Escribir-Estado -Estado OK -Mensaje ("Contexto: " + $contexto.ContextId + " (" + $contexto.ClienteNombre + " / " + $contexto.AmbienteNombre + ")")
Escribir-Estado -Estado OK -Mensaje ("Knowledge Base: " + $contexto.KbPath)

try {
    Validar-RutaKnowledgeBase -Ruta $contexto.KbPath -Contexto ("La Knowledge Base del ambiente " + $contexto.AmbienteId) | Out-Null
} catch {
    Escribir-Estado -Estado ERROR -Mensaje $_.Exception.Message
    exit 1
}

Escribir-Estado -Estado OK -Mensaje 'Contexto del cliente seteado correctamente.'
Crear-ArbolContextual -DirectorioContexto $contexto.DirectorioContexto

exit 0
