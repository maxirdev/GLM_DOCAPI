# GenerarDocumento.ps1
# Orquestador del generador de documentacion de servicios APIGLM.
# Carga la configuracion, lee el inventario endpoints.json, presenta un menu
# con 3 modos (particular, multiple, todos) y encadena analisis -> redaccion -> salida.
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

function Procesar-Servicio {
    param(
        [Parameter(Mandatory = $true)][object]$Endpoint,
        [Parameter(Mandatory = $true)][object]$Configuracion,
        [Parameter(Mandatory = $true)][string]$RutaConfig,
        [Parameter(Mandatory = $true)][string]$DirectorioSalida,
        [Parameter(Mandatory = $true)][string]$RutaInformeRevision,
        [Parameter(Mandatory = $true)]$ListaErrores,
        [switch]$Silencioso
    )

    try {
        if (-not $Silencioso) { Write-Step 3 'Analizando el servicio desde el XPZ...' }
        if ([string]::IsNullOrWhiteSpace($Configuracion.packagename)) {
            throw 'La configuracion no define packagename.'
        }
        $packageName = [string]$Configuracion.packagename
        $xml = Abrir-XPZ -RutaXpz (Join-Path (Split-Path $RutaConfig -Parent) $Configuracion.xpz)
        $documentacion = Analizar-Servicio -Xml $xml -NombreCompletoWrapper $Endpoint.proceso -PackageName $packageName
        if (-not $Silencioso) {
            Write-Host ("  Programa principal: " + $documentacion.ProgramaPrincipal) -ForegroundColor DarkGray
            Write-Host ("  Metodo HTTP: " + $documentacion.MetodoHttp) -ForegroundColor DarkGray
            Write-Host ("  Endpoint: " + $documentacion.EndpointPublicado) -ForegroundColor DarkGray
        }

        if (-not $Silencioso) { Write-Step 4 'Redactando el documento segun la plantilla...' }
        $documento = Redactar-Documento -Documentacion $documentacion
        if (-not $Silencioso) { Write-Host ("  Documento redactado (" + $documento.Length + " caracteres)") -ForegroundColor DarkGray }

        if (-not $Silencioso) { Write-Step 5 'Escribiendo las salidas...' }
        $rutaDocumento = Escribir-Salidas -Documentacion $documentacion -Documento $documento -DirectorioSalida $DirectorioSalida -RutaInformeRevision $RutaInformeRevision

        return $true
    } catch {
        $ListaErrores.Add([pscustomobject]@{
            servicio = $Endpoint.proceso
            error = $_.Exception.Message
        })
        return $false
    }
}

$RutaInventario = Join-Path $PSScriptRoot '..\..\Endpoints\assets\endpoints.json'
$DirectorioSalida = Join-Path $PSScriptRoot '..\..\servicios'
$RutaInformeRevision = Join-Path $PSScriptRoot '..\assets\apiglm-doc-review.json'

try {
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  GENERADOR DE DOCUMENTACION DE SERVICIO APIGLM' -ForegroundColor Cyan
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

    Write-Host ''
    Write-Host '  Modos de generacion:' -ForegroundColor Cyan
    Write-Host '    1. Servicio particular (seleccion individual)'
    Write-Host '    2. Multiples servicios (seleccion con ventana grafica)'
    Write-Host '    3. TODOS los servicios (procesar el inventario completo)'
    Write-Host ''
    $modoSeleccionado = 0
    while ($modoSeleccionado -lt 1 -or $modoSeleccionado -gt 3) {
        $texto = Read-Host 'Seleccione un modo [1-3]'
        $modoSeleccionado = 0
        $parseado = 0
        if ([int]::TryParse($texto, [ref]$parseado)) { $modoSeleccionado = $parseado }
        if ($modoSeleccionado -lt 1 -or $modoSeleccionado -gt 3) {
            Write-Host ('  Seleccion invalida. Ingrese 1, 2 o 3.') -ForegroundColor Yellow
        }
    }
    Write-Host ("  Modo seleccionado: " + $modoSeleccionado) -ForegroundColor DarkGray

    $serviciosSeleccionados = @()

    if ($modoSeleccionado -eq 1) {
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
        $serviciosSeleccionados = @($servicio)
    }
    elseif ($modoSeleccionado -eq 2) {
        $seleccionadosGrid = $endpoints | Select-Object nombre, proceso | Out-GridView -OutputMode Multiple -Title 'Seleccione los servicios (Ctrl+Click para multiples)'
        if ($null -eq $seleccionadosGrid) {
            Write-Host '  Seleccion cancelada. No se genero ningun documento.' -ForegroundColor Yellow
            exit 0
        }
        $serviciosSeleccionados = @($endpoints | Where-Object { $_.proceso -in $seleccionadosGrid.proceso })
        Write-Host ("  Seleccionados: " + $serviciosSeleccionados.Count + " servicios") -ForegroundColor DarkGray
    }
    elseif ($modoSeleccionado -eq 3) {
        $serviciosSeleccionados = @($endpoints)
        Write-Host ("  Procesando " + $serviciosSeleccionados.Count + " servicios") -ForegroundColor DarkGray
    }

    $exitos = 0
    $fallos = 0
    $errores = New-Object System.Collections.Generic.List[object]
    $totalServicios = $serviciosSeleccionados.Count
    $contador = 0

    foreach ($servicio in $serviciosSeleccionados) {
        $contador++
        if ($modoSeleccionado -ne 1) {
            $progreso = [math]::Floor(($contador / $totalServicios) * 100)
            Write-Progress -Activity 'Generando documentacion de servicio' -PercentComplete $progreso -Status "Procesando $contador de $totalServicios"
        }
        if (Procesar-Servicio -Endpoint $servicio -Configuracion $config -RutaConfig $ConfigPath -DirectorioSalida $DirectorioSalida -RutaInformeRevision $RutaInformeRevision -ListaErrores $errores -Silencioso:($modoSeleccionado -ne 1)) {
            $exitos++
        } else {
            $fallos++
            Write-Host ("  Fallo: " + $servicio.proceso) -ForegroundColor Red
        }
    }

    Write-Host ''
    Write-Host ("Completado: $exitos exitos, $fallos fallos.") -ForegroundColor Cyan
    if ($fallos -gt 0) {
        $rutaLogErrores = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\logErrores.txt'))
        $directorioLogErrores = [System.IO.Path]::GetDirectoryName($rutaLogErrores)
        if (-not (Test-Path -LiteralPath $directorioLogErrores)) {
            New-Item -ItemType Directory -Path $directorioLogErrores -Force | Out-Null
        }
        $lineasLogErrores = $errores | ForEach-Object {
            $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            "$timestamp | " + $_.servicio + " | " + $_.error
        }
        $contenidoLogErrores = ($lineasLogErrores -join "`n")
        if ($contenidoLogErrores) { $contenidoLogErrores += "`n" }
        [System.IO.File]::WriteAllText($rutaLogErrores, $contenidoLogErrores, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host ("Log de errores: " + $rutaLogErrores) -ForegroundColor Yellow
    }
} catch {
    Write-Host ''
    Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    Write-Host ''
    Write-Host ("Fin: " + ((Get-Date) - $StartTime).ToString('mm\:ss')) -ForegroundColor DarkGray
}
