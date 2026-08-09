# GenerarDocumento.ps1
# Orquestador del generador de documentacion de servicios APIGLM.
# Carga la configuracion, lee el inventario endpoints.json, presenta un menu
# con 3 modos (particular, multiple, todos) y encadena analisis -> redaccion -> salida.
# Requiere configuracion.json en la raiz del proyecto.

[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$XpzPath
)

$ErrorActionPreference = 'Stop'
$StartTime = Get-Date
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '..\..\..\configuracion.json' }
. (Join-Path $PSScriptRoot 'CargarConfiguracion.ps1')

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
        [Parameter(Mandatory = $true)][string]$PackageName,
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)]$Indice,
        [Parameter(Mandatory = $true)][string]$DirectorioSalida,
        [Parameter(Mandatory = $true)][string]$RutaInformeRevision,
        [Parameter(Mandatory = $true)]$ListaErrores,
        [switch]$Silencioso
    )

    try {
        if (-not $Silencioso) { Write-Step 3 'Analizando el servicio desde el XPZ...' }
        $documentacion = Analizar-Servicio -Xml $Xml -NombreCompletoWrapper $Endpoint.proceso -PackageName $PackageName -Indice $Indice
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

        $tienePendientes = @($documentacion.Pendientes).Count -gt 0
        $estado = 'OK'
        if ($tienePendientes) { $estado = 'WARNING' }

        return [pscustomobject]@{
            FullyQualifiedName = $Endpoint.proceso
            Estado = $estado
            Documento = $rutaDocumento
            Pendientes = @($documentacion.Pendientes)
            Mensajes = @()
        }
    } catch {
        $ListaErrores.Add([pscustomobject]@{
            servicio = $Endpoint.proceso
            error = $_.Exception.Message
        })
        return [pscustomobject]@{
            FullyQualifiedName = $Endpoint.proceso
            Estado = 'ERROR'
            Documento = ''
            Pendientes = @()
            Mensajes = @($_.Exception.Message)
        }
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
    $cargarConfiguracionParametros = @{ ConfigPath = $ConfigPath }
    if ($XpzPath) { $cargarConfiguracionParametros.XpzPath = $XpzPath }
    $configuracion = Cargar-Configuracion @cargarConfiguracionParametros
    Write-Host ("  XPZ: " + $configuracion.XpzPath) -ForegroundColor DarkGray
    Write-Host ("  PackageName: " + $configuracion.PackageName) -ForegroundColor DarkGray
    if ($configuracion.Cliente) {
        Write-Host ("  Cliente: " + $configuracion.Cliente) -ForegroundColor DarkGray
    }
    if (-not (Test-Path -LiteralPath $RutaInventario)) {
        throw ("No se encontro el inventario en: " + $RutaInventario + ". Ejecute primero GenerarDocumentacion.cmd para regenerarlo desde el XPZ.")
    }
    $inventario = Get-Content -LiteralPath $RutaInventario -Raw | ConvertFrom-Json
    $endpoints = @($inventario.endpoints)
    if ($endpoints.Count -eq 0) {
        throw 'El inventario endpoints.json no contiene endpoints.'
    }
    Write-Host ("  Inventario: " + $endpoints.Count + " endpoints") -ForegroundColor DarkGray

    Write-Step 2 'Abriendo XPZ y construyendo indices...'
    $aperturaXpz = Abrir-XPZ -RutaXpz $configuracion.XpzPath
    $indices = Construir-Indices -Xml $aperturaXpz.Xml
    Write-Host ("  XPZ abierto y " + $aperturaXpz.Xml.SelectNodes('//Object').Count + " objetos indexados") -ForegroundColor DarkGray

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

    $nombresLocalesVistos = @{}
    $serviciosParaProcesar = New-Object System.Collections.Generic.List[object]
    $duplicados = New-Object System.Collections.Generic.List[object]
    foreach ($servicio in $serviciosSeleccionados) {
        $ultimoPunto = $servicio.proceso.LastIndexOf('.')
        if ($ultimoPunto -gt 0) {
            $nombreLocal = $servicio.proceso.Substring($ultimoPunto + 1).ToLowerInvariant()
        } else {
            $nombreLocal = $servicio.proceso.ToLowerInvariant()
        }
        if ($nombresLocalesVistos.ContainsKey($nombreLocal)) {
            $duplicados.Add([pscustomobject]@{
                servicio = $servicio.proceso
                nombreLocal = $nombreLocal
                ganador = $nombresLocalesVistos[$nombreLocal]
            })
            Write-Host ("  [WARNING] Duplicado: " + $servicio.proceso + " -> " + $nombreLocal + " (ganador: " + $nombresLocalesVistos[$nombreLocal] + ")") -ForegroundColor Yellow
        } else {
            $nombresLocalesVistos[$nombreLocal] = $servicio.proceso
            $serviciosParaProcesar.Add($servicio)
        }
    }

    if ($duplicados.Count -gt 0) {
        Write-Host ("  Duplicados omitidos: " + $duplicados.Count + " servicio(s)") -ForegroundColor Yellow
    }

    $okCount = 0
    $warningCount = 0
    $errorCount = 0
    $errores = New-Object System.Collections.Generic.List[object]
    $resultados = New-Object System.Collections.Generic.List[object]
    $totalServicios = $serviciosParaProcesar.Count
    $contador = 0

    foreach ($servicio in $serviciosParaProcesar) {
        $contador++
        if ($modoSeleccionado -ne 1) {
            $progreso = [math]::Floor(($contador / $totalServicios) * 100)
            Write-Progress -Activity 'Generando documentacion de servicio' -PercentComplete $progreso -Status "Procesando $contador de $totalServicios"
        }
        $resultado = Procesar-Servicio -Endpoint $servicio -PackageName $configuracion.PackageName -Xml $aperturaXpz.Xml -Indice $indices -DirectorioSalida $DirectorioSalida -RutaInformeRevision $RutaInformeRevision -ListaErrores $errores -Silencioso:($modoSeleccionado -ne 1)
        $resultados.Add($resultado)
        if ($resultado.Estado -eq 'OK') {
            $okCount++
        } elseif ($resultado.Estado -eq 'WARNING') {
            $warningCount++
            Write-Host ("  [WARNING] " + $servicio.proceso + " — PENDIENTES: " + (@($resultado.Pendientes).Count)) -ForegroundColor Yellow
        } elseif ($resultado.Estado -eq 'ERROR') {
            $errorCount++
            Write-Host ("  [ERROR] " + $servicio.proceso) -ForegroundColor Red
        }
    }

    foreach ($dup in $duplicados) {
        $resultados.Add([pscustomobject]@{
            FullyQualifiedName = $dup.servicio
            Estado = 'WARNING'
            Documento = ''
            Pendientes = @()
            Mensajes = @("Nombre local duplicado '$($dup.nombreLocal)'. El ganador es '$($dup.ganador)'.")
        })
        $warningCount++
    }

    foreach ($resultado in $resultados) {
        if ($resultado.Estado -ne 'ERROR') { continue }
        if (-not $resultado.FullyQualifiedName) { continue }
        $ultimoPunto = $resultado.FullyQualifiedName.LastIndexOf('.')
        if ($ultimoPunto -le 0) { continue }
        $nombreArchivo = $resultado.FullyQualifiedName.Substring($ultimoPunto + 1).ToLowerInvariant() + '.md'
        $rutaDocumentoError = Join-Path $DirectorioSalida $nombreArchivo
        if (Test-Path -LiteralPath $rutaDocumentoError) {
            Remove-Item -LiteralPath $rutaDocumentoError -Force
            Write-Host ("  [ELIMINADO] " + $rutaDocumentoError + " (servicio en ERROR: " + $resultado.FullyQualifiedName + ")") -ForegroundColor Yellow
        }
    }

    Write-Host ''
    Write-Host ("Completado: $okCount OK, $warningCount WARNING, $errorCount ERROR.") -ForegroundColor Cyan

    $directorioLogs = Join-Path $PSScriptRoot '..\Logs'
    if (-not (Test-Path -LiteralPath $directorioLogs)) {
        New-Item -ItemType Directory -Path $directorioLogs -Force | Out-Null
    }

    $finEjecucion = Get-Date
    $marcaTemporal = $finEjecucion.ToString('yyyyMMdd-HHmmss')

    $revision = [pscustomobject]@{
        ejecucion = [pscustomobject]@{
            xpz = $configuracion.XpzPath
            inicio = $StartTime.ToString('s')
            fin = $finEjecucion.ToString('s')
            seleccionados = $serviciosSeleccionados.Count
            ok = $okCount
            warning = $warningCount
            error = $errorCount
        }
        servicios = @($resultados | ForEach-Object {
            [pscustomobject]@{
                fullyQualifiedName = $_.FullyQualifiedName
                estado = $_.Estado
                documento = $_.Documento
                pendientes = @($_.Pendientes)
                mensajes = @($_.Mensajes)
            }
        })
    }
    $rutaRevision = Join-Path $directorioLogs ($marcaTemporal + '-review.json')
    $jsonRevision = $revision | ConvertTo-Json -Depth 5
    $jsonRevision = $jsonRevision -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($rutaRevision, $jsonRevision, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("Review: " + $rutaRevision) -ForegroundColor DarkGray

    $tieneIncidencias = ($warningCount -gt 0 -or $errorCount -gt 0)
    if ($tieneIncidencias) {
        $lineasTxt = New-Object System.Collections.Generic.List[string]
        foreach ($resultado in $resultados) {
            if ($resultado.Estado -eq 'OK') { continue }
            foreach ($mensaje in $resultado.Mensajes) {
                $lineasTxt.Add($resultado.FullyQualifiedName + " | " + $resultado.Estado + " | " + $mensaje)
            }
            if ($resultado.Pendientes.Count -gt 0) {
                foreach ($pendiente in $resultado.Pendientes) {
                    $lineasTxt.Add($resultado.FullyQualifiedName + " | " + $resultado.Estado + " | PENDIENTE: " + $pendiente)
                }
            }
        }
        if ($lineasTxt.Count -gt 0) {
            $rutaErrores = Join-Path $directorioLogs ($marcaTemporal + '-errores.txt')
            $contenidoTxt = ($lineasTxt -join "`n") + "`n"
            [System.IO.File]::WriteAllText($rutaErrores, $contenidoTxt, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host ("Incidencias: " + $rutaErrores) -ForegroundColor DarkGray
        }
    }

    if ($errorCount -gt 0) {
        Write-Host ''
        Write-Host ("  ATENCION: La ejecucion termino con " + $errorCount + " error(es). Revise los logs.") -ForegroundColor Yellow
        $script:ExitCode = 1
    } else {
        $script:ExitCode = 0
    }
} catch {
    Write-Host ''
    Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    Write-Host ''
    Write-Host ("Fin: " + ((Get-Date) - $StartTime).ToString('mm\:ss')) -ForegroundColor DarkGray
    if ($script:ExitCode -eq 1) { exit 1 }
}
