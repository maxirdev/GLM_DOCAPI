# GenerarDocumento.ps1
# Orquestador del generador de fichas de servicios APIGLM.
# Carga la configuracion, lee el inventario endpoints.json, muestra la lista
# numerada, pide el numero por Read-Host y encadena analisis -> redaccion -> salida.
# Requiere configuracion.json en la raiz del proyecto.

[CmdletBinding()]
param(
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
$StartTime = Get-Date
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '..\..\..\configuracion.json' }

if (-not [Console]::IsOutputRedirected) {
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
}

function Write-Step {
    param(
        [Parameter(Mandatory = $true)][int]$Number,
        [string]$Text = ''
    )
    Write-Host ''
    Write-Host ("[ {0}/5 ] {1}" -f $Number, $Text) -ForegroundColor Cyan
}

$RutaInventario = Join-Path $PSScriptRoot '..\..\Endpoints\assets\endpoints.json'
$DirectorioSalida = Join-Path $PSScriptRoot '..\..\servicios'
$RutaInformeRevision = Join-Path $PSScriptRoot '..\assets\apiglm-doc-review.json'

try {
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  GENERADOR DE FICHA DE SERVICIO APIGLM' -ForegroundColor Cyan
    Write-Host ("  " + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan

    . (Join-Path $PSScriptRoot 'AnalizarServicio.ps1')
    . (Join-Path $PSScriptRoot 'RedactarDocumento.ps1')
    . (Join-Path $PSScriptRoot 'EscribirSalidas.ps1')

    Write-Step 1 'Cargando configuracion e inventario...'
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw ("No se encontro el archivo de configuracion: " + $ConfigPath)
    }
    $ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    if (-not (Test-Path -LiteralPath $RutaInventario)) {
        throw ("No se encontro el inventario en: " + $RutaInventario + ". Ejecute primero GenerarDocumentacion.cmd para regenerarlo desde el XPZ.")
    }
    $inventario = Get-Content -LiteralPath $RutaInventario -Raw | ConvertFrom-Json
    $endpoints = @($inventario.endpoints)
    if ($endpoints.Count -eq 0) {
        throw 'El inventario endpoints.json no contiene endpoints.'
    }
    Write-Host ("  Inventario: " + $endpoints.Count + " endpoints") -ForegroundColor DarkGray

    Write-Step 2 'Seleccion del servicio...'
    for ($i = 0; $i -lt $endpoints.Count; $i++) {
        Write-Host ('  {0,3}. {1}  ({2})' -f ($i + 1), $endpoints[$i].nombre, $endpoints[$i].proceso) -ForegroundColor White
    }
    Write-Host ''
    $seleccion = 0
    while ($seleccion -lt 1 -or $seleccion -gt $endpoints.Count) {
        $texto = Read-Host ('Seleccione un servicio [1-' + $endpoints.Count + ']')
        $seleccion = 0
        $parseado = 0
        if ([int]::TryParse($texto, [ref]$parseado)) { $seleccion = $parseado }
        if ($seleccion -lt 1 -or $seleccion -gt $endpoints.Count) {
            Write-Host ('  Seleccion invalida. Ingrese un numero entre 1 y ' + $endpoints.Count + '.') -ForegroundColor Yellow
        }
    }
    $servicio = $endpoints[$seleccion - 1]
    Write-Host ("  Seleccionado: " + $servicio.proceso) -ForegroundColor DarkGray

    Write-Step 3 'Analizando el servicio desde el XPZ...'
    if ([string]::IsNullOrWhiteSpace($config.packagename)) {
        throw 'La configuracion no define packagename.'
    }
    $packageName = [string]$config.packagename
    $xml = Abrir-XPZ -RutaXpz (Join-Path (Split-Path $ConfigPath -Parent) $config.xpz)
    $ficha = Analizar-Servicio -Xml $xml -NombreCompletoWrapper $servicio.proceso -PackageName $packageName
    Write-Host ("  Programa principal: " + $ficha.ProgramaPrincipal) -ForegroundColor DarkGray
    Write-Host ("  Metodo HTTP: " + $ficha.MetodoHttp) -ForegroundColor DarkGray
    Write-Host ("  Endpoint: " + $ficha.EndpointPublicado) -ForegroundColor DarkGray

    Write-Step 4 'Redactando el documento segun la plantilla...'
    $documento = Redactar-Documento -Ficha $ficha
    Write-Host ("  Documento redactado (" + $documento.Length + " caracteres)") -ForegroundColor DarkGray

    Write-Step 5 'Escribiendo las salidas...'
    $rutaDocumento = Escribir-Salidas -Ficha $ficha -Documento $documento -DirectorioSalida $DirectorioSalida -RutaInformeRevision $RutaInformeRevision
    Write-Host ''
    Write-Host ("Documento generado: " + $rutaDocumento) -ForegroundColor Cyan
    Write-Host ("Informe de revision: " + $RutaInformeRevision) -ForegroundColor White
} catch {
    Write-Host ''
    Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    Write-Host ''
    Write-Host ("Fin: " + ((Get-Date) - $StartTime).ToString('mm\:ss')) -ForegroundColor DarkGray
}
