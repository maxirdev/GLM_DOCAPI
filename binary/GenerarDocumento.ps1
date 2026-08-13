# GenerarDocumento.ps1
# Orquestador del generador de documentacion de servicios APIGLM.
# Carga la configuracion, lee el inventario endpoints.json, presenta un menu
# con 3 modos (particular, multiple, todos) y encadena analisis -> redaccion -> Markdown.
# Requiere configuracion.json en la raiz del proyecto.

[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$XpzPath,
    [switch]$Todos
)

$ErrorActionPreference = 'Stop'
$StartTime = Get-Date
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '..\configuracion.json' }
$RaizRepositorio = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$DirectorioLogs = Join-Path $PSScriptRoot '..\Logs'
$diagnosticosIA = New-Object System.Collections.Generic.List[object]
$faseActual = 'inicio'
. (Join-Path $PSScriptRoot 'DiagnosticoIA.ps1')

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
        [Parameter(Mandatory = $true)]$ListaDiagnosticos,
        [Parameter(Mandatory = $true)][string]$RaizRepositorio,
        [switch]$Silencioso
    )

    $faseServicio = 'analisis'
    try {
        if (-not $Silencioso) { Write-Step 3 'Analizando el servicio desde el XPZ...' }
        $documentacion = Analizar-Servicio -Xml $Xml -NombreCompletoWrapper $Endpoint.proceso -PackageName $PackageName -Indice $Indice
        if (-not $Silencioso) {
            Write-Host ("  Programa principal: " + $documentacion.ProgramaPrincipal) -ForegroundColor DarkGray
            Write-Host ("  Metodo HTTP: " + $documentacion.MetodoHttp) -ForegroundColor DarkGray
            Write-Host ("  Endpoint: " + $documentacion.EndpointPublicado) -ForegroundColor DarkGray
        }

        $faseServicio = 'redaccion'
        if (-not $Silencioso) { Write-Step 4 'Redactando el documento segun la plantilla...' }
        $documento = Redactar-Documento -Documentacion $documentacion
        if (-not $Silencioso) { Write-Host ("  Documento redactado (" + $documento.Length + " caracteres)") -ForegroundColor DarkGray }

        $faseServicio = 'escritura'
        if (-not $Silencioso) { Write-Step 5 'Escribiendo las salidas...' }
        $rutaDocumento = Escribir-Salidas -Documentacion $documentacion -Documento $documento -DirectorioSalida $DirectorioSalida

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
        $ListaDiagnosticos.Add((New-DiagnosticoIAError -ErrorRecord $_ -Componente 'GenerarDocumento' -Fase $faseServicio -Servicio $Endpoint.proceso -RaizRepositorio $RaizRepositorio))
        return [pscustomobject]@{
            FullyQualifiedName = $Endpoint.proceso
            Estado = 'ERROR'
            Documento = ''
            Pendientes = @()
            Mensajes = @($_.Exception.Message)
        }
    }
}

$RutaInventario = Join-Path $PSScriptRoot '..\documentacion\Endpoints\assets\endpoints.json'
$DirectorioSalida = Join-Path $PSScriptRoot '..\documentacion\servicios'

try {
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  GENERADOR DE DOCUMENTACION DE SERVICIO APIGLM' -ForegroundColor Cyan
    Write-Host ("  " + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan

    $faseActual = 'carga-modulos'
    . (Join-Path $PSScriptRoot 'CargarConfiguracion.ps1')
    . (Join-Path $PSScriptRoot 'AnalizarServicio.ps1')
    . (Join-Path $PSScriptRoot 'CargarMultiXPZ.ps1')
    . (Join-Path $PSScriptRoot 'RedactarDocumento.ps1')
    . (Join-Path $PSScriptRoot 'EscribirSalidas.ps1')

    $faseActual = 'configuracion-inventario'
    Write-Step 1 'Cargando configuracion e inventario...'
    $cargarConfiguracionParametros = @{ ConfigPath = $ConfigPath }
    if ($XpzPath) { $cargarConfiguracionParametros.XpzPath = $XpzPath }
    $configuracion = Cargar-Configuracion @cargarConfiguracionParametros
    $xpzComplementariosDetectados = @(Descubrir-XPZComplementariosCompartido -RutaXpzPrincipal $configuracion.XpzPath)
    if ($xpzComplementariosDetectados.Count -gt 0) {
        Write-Host ("  XPZ principal: " + $configuracion.XpzPath) -ForegroundColor DarkGray
        Write-Host ("  Fuente: multi-XPZ (" + ($xpzComplementariosDetectados.Count + 1) + " archivos)") -ForegroundColor DarkGray
        Write-Host ("  Complementos detectados: " + (($xpzComplementariosDetectados | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -join ', ')) -ForegroundColor DarkGray
    } else {
        Write-Host ("  XPZ: " + $configuracion.XpzPath + " (único archivo)") -ForegroundColor DarkGray
    }
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

    $ignoradosConfig = @($configuracion.ServiciosIgnorados)
    $ignoradosEnInventario = @($endpoints | Where-Object { $ignoradosConfig -contains $_.proceso })
    $ignoradosSinInventario = @($ignoradosConfig | Where-Object { $_ -notin @($endpoints | ForEach-Object { $_.proceso }) })
    if ($ignoradosConfig.Count -gt 0) {
        Write-Host ("  Servicios ignorados: " + $ignoradosConfig.Count) -ForegroundColor DarkGray
        foreach ($ignorado in $ignoradosEnInventario) {
            Write-Host ("    [IGNORADO] " + $ignorado.proceso) -ForegroundColor DarkYellow
        }
        foreach ($ignorado in $ignoradosSinInventario) {
            Write-Host ("    [IGNORADO] " + $ignorado + " (no esta en el inventario)") -ForegroundColor DarkYellow
        }
        $endpoints = @($endpoints | Where-Object { $ignoradosConfig -notcontains $_.proceso })
        Write-Host ("  Inventario efectivo: " + $endpoints.Count + " endpoints") -ForegroundColor DarkGray
    }

    $faseActual = 'apertura-xpz'
    Write-Step 2 'Abriendo XPZ y construyendo indices...'
    $indices = Cargar-IndiceMultiXPZ -RutaXpzPrincipal $configuracion.XpzPath
    $xmlAnalisis = $indices.XmlUnificado
    Write-Host ("  XPZ abierto y " + $xmlAnalisis.SelectNodes('//Object').Count + " objetos indexados") -ForegroundColor DarkGray
    if (@($indices.NombresXpz).Count -gt 1) {
        Write-Host ("  Complementos incluidos: " + ((@($indices.NombresXpz) | Select-Object -Skip 1) -join ', ')) -ForegroundColor DarkGray
    }

    $faseActual = 'seleccion-servicios'
    $modoSeleccionado = 0
    if ($Todos) {
        $modoSeleccionado = 3
        Write-Host ''
        Write-Host '  Modo automatico: TODOS los servicios.' -ForegroundColor DarkGray
    } else {
        Write-Host ''
        Write-Host '  Modos de generacion:' -ForegroundColor Cyan
        Write-Host '    1. Servicio particular (seleccion individual)'
        Write-Host '    2. Multiples servicios (seleccion con ventana grafica)'
        Write-Host '    3. TODOS los servicios (procesar el inventario completo)'
        Write-Host ''
        while ($modoSeleccionado -lt 1 -or $modoSeleccionado -gt 3) {
            $texto = Read-Host 'Seleccione un modo [1-3]'
            $modoSeleccionado = 0
            $parseado = 0
            if ([int]::TryParse($texto, [ref]$parseado)) { $modoSeleccionado = $parseado }
            if ($modoSeleccionado -lt 1 -or $modoSeleccionado -gt 3) {
                Write-Host ('  Seleccion invalida. Ingrese 1, 2 o 3.') -ForegroundColor Yellow
            }
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
    $omitidoCount = 0
    $resultados = New-Object System.Collections.Generic.List[object]
    foreach ($ignorado in $ignoradosEnInventario) {
        $resultados.Add([pscustomobject]@{
            FullyQualifiedName = $ignorado.proceso
            Estado = 'OMITIDO'
            Documento = ''
            Pendientes = @()
            Mensajes = @('Servicio en la lista de serviciosIgnorados de configuracion.json. No se documenta.')
        })
        $omitidoCount++
    }
    $totalServicios = $serviciosParaProcesar.Count
    $contador = 0

    foreach ($servicio in $serviciosParaProcesar) {
        $faseActual = 'procesamiento-servicios'
        $contador++
        if ($modoSeleccionado -ne 1) {
            $progreso = [math]::Floor(($contador / $totalServicios) * 100)
            Write-Progress -Activity 'Generando documentacion de servicio' -PercentComplete $progreso -Status "Procesando $contador de $totalServicios"
        }
        $resultado = Procesar-Servicio -Endpoint $servicio -PackageName $configuracion.PackageName -Xml $xmlAnalisis -Indice $indices -DirectorioSalida $DirectorioSalida -ListaDiagnosticos $diagnosticosIA -RaizRepositorio $RaizRepositorio -Silencioso:($modoSeleccionado -ne 1)
        $resultados.Add($resultado)
        if ($resultado.Estado -eq 'OK') {
            $okCount++
            Write-Host ("  [OK] " + $servicio.proceso + " — Documentacion generada correctamente.") -ForegroundColor Green
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

    # Un servicio que termina en ERROR no debe borrar su documentación previa.
    # Solo Escribir-Salidas reemplaza el archivo cuando el servicio seleccionado
    # pudo analizarse y redactarse correctamente.

    Write-Host ''
    Write-Host ("Completado: $okCount OK, $warningCount WARNING, $errorCount ERROR, $omitidoCount OMITIDO.") -ForegroundColor Cyan

    $faseActual = 'escritura-logs'
    if (-not (Test-Path -LiteralPath $DirectorioLogs)) {
        New-Item -ItemType Directory -Path $DirectorioLogs -Force | Out-Null
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
            omitido = $omitidoCount
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
    $rutaRevision = Join-Path $DirectorioLogs ($marcaTemporal + '-review.json')
    $jsonRevision = $revision | ConvertTo-Json -Depth 5
    $jsonRevision = $jsonRevision -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($rutaRevision, $jsonRevision, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("Review: " + $rutaRevision) -ForegroundColor DarkGray

    $tieneIncidencias = ($warningCount -gt 0 -or $errorCount -gt 0)
    if ($tieneIncidencias) {
        $lineasTxt = New-Object System.Collections.Generic.List[string]
        foreach ($resultado in $resultados) {
            if ($resultado.Estado -eq 'OK') { continue }

            $detalles = New-Object System.Collections.Generic.List[string]
            foreach ($mensaje in $resultado.Mensajes) {
                if ($mensaje) { $detalles.Add([string]$mensaje) }
            }
            if ($resultado.Pendientes.Count -gt 0) {
                $pendientes = @($resultado.Pendientes | Where-Object { $_ } | ForEach-Object { [string]$_ })
                if ($pendientes.Count -gt 0) {
                    $detalles.Add('PENDIENTE: ' + ($pendientes -join '; '))
                }
            }
            if ($detalles.Count -gt 0) {
                $lineasTxt.Add($resultado.FullyQualifiedName + " | " + $resultado.Estado + " | " + ($detalles -join '; '))
            }
        }
        if ($lineasTxt.Count -gt 0) {
            $rutaErrores = Join-Path $DirectorioLogs ($marcaTemporal + '-errores.txt')
            $contenidoTxt = ($lineasTxt -join "`n") + "`n"
            [System.IO.File]::WriteAllText($rutaErrores, $contenidoTxt, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host ("Incidencias: " + $rutaErrores) -ForegroundColor DarkGray
        }
    }

    if ($diagnosticosIA.Count -gt 0) {
        $rutaDiagnosticoIA = Write-DiagnosticoIA -Errores $diagnosticosIA -Pipeline 'generador-servicios' -Inicio $StartTime -DirectorioLogs $DirectorioLogs -RaizRepositorio $RaizRepositorio -MarcaTemporal $marcaTemporal
        Write-Host ("Diagnostico IA: " + $rutaDiagnosticoIA) -ForegroundColor DarkGray
    }

    if ($errorCount -gt 0) {
        Write-Host ''
        Write-Host ("  ATENCION: La ejecucion termino con " + $errorCount + " error(es). Revise los logs.") -ForegroundColor Yellow
        $script:ExitCode = 1
    } else {
        $script:ExitCode = 0
    }
} catch {
    $diagnosticosIA.Add((New-DiagnosticoIAError -ErrorRecord $_ -Componente 'GenerarDocumento' -Fase $faseActual -RaizRepositorio $RaizRepositorio))
    Write-Host ''
    Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
    try {
        $rutaDiagnosticoIA = Write-DiagnosticoIA -Errores $diagnosticosIA -Pipeline 'generador-servicios' -Inicio $StartTime -DirectorioLogs $DirectorioLogs -RaizRepositorio $RaizRepositorio -MarcaTemporal $marcaTemporal
        Write-Host ("Diagnostico IA: " + $rutaDiagnosticoIA) -ForegroundColor DarkGray
    } catch {
        Write-Host ("No se pudo escribir el diagnostico IA: " + $_.Exception.Message) -ForegroundColor DarkGray
    }
    exit 1
} finally {
    Write-Host ''
    Write-Host ("Fin: " + ((Get-Date) - $StartTime).ToString('mm\:ss')) -ForegroundColor DarkGray
    if ($script:ExitCode -eq 1) { exit 1 }
}
