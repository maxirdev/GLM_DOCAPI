# ExportarXPZSelectivo.ps1
# Selecciona la receta de exportacion producida por ValidarXPZ.ps1.
# Ejecuta MSBuild, genera un complemento numerado y valida el XPZ resultante.

[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$XpzPath,
    [string]$ReportePath,
    [string]$MsbuildPath,
    [string]$ProjectFile,
    [string]$GxProgramDir,
    [string]$KbPath,
    [string]$XpzFile,
    [string]$LogFile,
    [string]$ManifiestoPath,
    [string]$ClienteId,
    [ValidateSet('comercial', 'erp')][string]$Modulo,
    [string]$AmbienteId,
    [ValidateSet('GX18', 'Evo3')]
    [string]$GeneXusExportProfile
)

$ErrorActionPreference = 'Stop'
$RaizRepositorio = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$DirectorioLogs = Join-Path $RaizRepositorio 'Logs'

. (Join-Path $PSScriptRoot 'GLMUtilidades.ps1')
. (Join-Path $PSScriptRoot 'CargarConfiguracion.ps1')
. (Join-Path $PSScriptRoot 'ManifiestoEjecucion.ps1')

function Obtener-RutaXpzReportada {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Reporte,
        [Parameter(Mandatory = $true)]$Configuracion
    )

    if (-not $Reporte.ejecucion -or -not $Reporte.ejecucion.xpz) {
        throw 'El reporte no contiene ejecucion.xpz.'
    }

    return Resolver-RutaRepositorio -Ruta ([string]$Reporte.ejecucion.xpz) -Raiz $Configuracion.RaizRepositorio
}

function Obtener-NombreLocalObjeto {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Valor
    )

    $nombre = $Valor.Trim()
    if ($nombre.Contains(':')) { $nombre = $nombre.Split(':', 2)[1].Trim() }
    if ($nombre.Contains('.')) { $nombre = $nombre.Split('.')[-1] }
    return $nombre
}

function Escribir-TrazaExportacionSelectiva {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaLog,
        [Parameter(Mandatory = $true)][string]$Mensaje
    )

    try {
        $linea = '[' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff') + '] ' + $Mensaje + [Environment]::NewLine
        [System.IO.File]::AppendAllText($RutaLog, $linea, (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

function Obtener-TimeoutMsbuildSegundos {
    param([string]$RutaConfiguracion)
    $defaultTimeout = 300
    if ([string]::IsNullOrWhiteSpace($RutaConfiguracion) -or -not (Test-Path -LiteralPath $RutaConfiguracion -PathType Leaf)) { return $defaultTimeout }
    try {
        $raw = Get-Content -LiteralPath $RutaConfiguracion -Raw -Encoding UTF8 | ConvertFrom-Json
        $value = 0
        if ($raw.panel -and [int]::TryParse([string]$raw.panel.timeoutMsbuildSegundos, [ref]$value) -and $value -gt 0) { return $value }
    } catch { }
    return $defaultTimeout
}

function Obtener-ObjetosDeReporte {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Reporte
    )

    $objetos = New-Object System.Collections.Generic.List[string]

    if ($Reporte.solicitudes) {
        foreach ($solicitud in @($Reporte.solicitudes)) {
            foreach ($objeto in @($solicitud.exportar)) {
                $valor = Obtener-NombreLocalObjeto -Valor ([string]$objeto)
                if ($valor -and $objetos -notcontains $valor) {
                    [void]$objetos.Add($valor)
                }
            }
        }
    }

    if ($objetos.Count -gt 0) {
        return @($objetos)
    }

    if ($Reporte.objectList) {
        foreach ($objeto in ([string]$Reporte.objectList -split ',')) {
            $nombre = Obtener-NombreLocalObjeto -Valor $objeto.Trim()
            if ($nombre -and $objetos -notcontains $nombre) {
                [void]$objetos.Add($nombre)
            }
        }
    }

    if ($objetos.Count -eq 0 -and $Reporte.solicitudes) {
        foreach ($solicitud in @($Reporte.solicitudes)) {
            foreach ($selector in @($solicitud.selectores)) {
                $partes = ([string]$selector).Split(':', 2)
                $nombre = Obtener-NombreLocalObjeto -Valor (if ($partes.Count -eq 2) { $partes[1].Trim() } else { ([string]$selector).Trim() })
                if ($nombre -and $objetos -notcontains $nombre) {
                    [void]$objetos.Add($nombre)
                }
            }
        }
    }

    return @($objetos)
}

function Validar-SelectoresExportacion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$Selectores
    )

    foreach ($selector in $Selectores) {
        if ($selector -notmatch '^(Procedure|SDT|Domain|Attribute):[^:]+$') {
            throw ('El reporte contiene un selector sin tipo y FQN: ' + $selector)
        }
    }
}

function Leer-ReporteValidacion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaReporte,
        [Parameter(Mandatory = $true)]$Configuracion,
        [Parameter(Mandatory = $false)][string]$EjecucionId = ''
    )

    if (-not (Test-Path -LiteralPath $RutaReporte -PathType Leaf)) {
        throw ('No se encontro el reporte de validacion: ' + $RutaReporte)
    }

    try {
        $contenido = Get-Content -LiteralPath $RutaReporte -Raw -Encoding UTF8
        $reporte = $contenido | ConvertFrom-Json
    } catch {
        throw ('El reporte de validacion no es JSON valido: ' + $RutaReporte + '. ' + $_.Exception.Message)
    }

    $rutaXpzReportada = Obtener-RutaXpzReportada -Reporte $reporte -Configuracion $Configuracion
    $rutaXpzConfigurada = [System.IO.Path]::GetFullPath($Configuracion.XpzPath)
    if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($rutaXpzReportada, $rutaXpzConfigurada)) {
        throw ('El reporte corresponde a otro XPZ. Reportado: ' + $rutaXpzReportada + '. Configurado: ' + $rutaXpzConfigurada + '.')
    }
    if ($EjecucionId -and [string]$reporte.ejecucion.id -ne $EjecucionId) {
        throw ('El reporte corresponde a otra ejecucion. Reportado: ' + [string]$reporte.ejecucion.id + '. Esperado: ' + $EjecucionId + '.')
    }

    $objetos = @(Obtener-ObjetosDeReporte -Reporte $reporte)
    if ($objetos.Count -eq 0) {
        throw ('El reporte no contiene objetos pendientes de exportacion: ' + $RutaReporte)
    }

    $selectoresDeclarados = @($reporte.solicitudes | ForEach-Object { @($_.selectores) } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($selectoresDeclarados.Count -gt 0) {
        Validar-SelectoresExportacion -Selectores $selectoresDeclarados
    } else {
        throw ('El reporte no contiene selectores calificados por tipo y FQN: ' + $RutaReporte)
    }

    return [pscustomobject]@{
        Ruta = (Resolve-Path -LiteralPath $RutaReporte).Path
        Reporte = $reporte
        Objetos = $objetos
        Selectores = $selectoresDeclarados
        XpzPrincipal = $rutaXpzConfigurada
    }
}

function Seleccionar-ReporteValidacion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Configuracion,
        [string]$RutaReporte,
        [string]$EjecucionId = ''
    )

    if ($RutaReporte) {
        $rutaExplicita = Resolver-RutaRepositorio -Ruta $RutaReporte -Raiz $Configuracion.RaizRepositorio
        return Leer-ReporteValidacion -RutaReporte $rutaExplicita -Configuracion $Configuracion -EjecucionId $EjecucionId
    }

    if (-not (Test-Path -LiteralPath $DirectorioLogs -PathType Container)) {
        throw ('No se encontro la carpeta de logs: ' + $DirectorioLogs)
    }

    $reportes = @(Get-ChildItem -LiteralPath $DirectorioLogs -Filter '*-validacion-xpz.json' -File | Sort-Object LastWriteTime -Descending)
    if ($reportes.Count -eq 0) {
        throw ('No se encontraron reportes *-validacion-xpz.json en: ' + $DirectorioLogs)
    }

    $errores = New-Object System.Collections.Generic.List[string]
    foreach ($archivo in $reportes) {
        try {
            return Leer-ReporteValidacion -RutaReporte $archivo.FullName -Configuracion $Configuracion -EjecucionId $EjecucionId
        } catch {
            [void]$errores.Add($archivo.Name + ': ' + $_.Exception.Message)
        }
    }

    throw ('No se encontro un reporte compatible con el XPZ configurado. ' + ($errores -join ' | '))
}

function Mostrar-RecetaSeleccionada {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Seleccion
    )

    Write-Host ('Reporte seleccionado: ' + $Seleccion.Ruta) -ForegroundColor DarkGray
    Write-Host ('Objetos pendientes: ' + $Seleccion.Objetos.Count) -ForegroundColor Yellow
    foreach ($objeto in $Seleccion.Objetos) {
        Write-Host ('  ' + $objeto) -ForegroundColor DarkGray
    }
}

function Seleccionar-SiguienteXpzComplementario {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaXpzPrincipal
    )

    $directorio = [System.IO.Path]::GetDirectoryName($RutaXpzPrincipal)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($RutaXpzPrincipal)
    $extension = [System.IO.Path]::GetExtension($RutaXpzPrincipal)
    if (-not $extension) { $extension = '.xpz' }

    $numero = 1
    while ($true) {
        $nombre = $base + '_' + $numero.ToString() + $extension
        $rutaCandidata = Join-Path $directorio $nombre
        if (-not (Test-Path -LiteralPath $rutaCandidata)) {
            return [pscustomobject]@{
                Ruta = [System.IO.Path]::GetFullPath($rutaCandidata)
                Nombre = $nombre
                Numero = $numero
            }
        }

        if ($numero -eq [int]::MaxValue) {
            throw ('No hay un numero disponible para un XPZ complementario junto a: ' + $RutaXpzPrincipal)
        }
        $numero++
    }
}

function Validar-RutasEjecucion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Configuracion,
        [Parameter(Mandatory = $true)][string]$RutaMsbuild,
        [Parameter(Mandatory = $true)][string]$RutaProyecto,
        [Parameter(Mandatory = $true)][string]$DirectorioGeneXus,
        [string]$RutaKnowledgeBase,
        [Parameter(Mandatory = $true)][string]$RutaXpzSalida,
        [Parameter(Mandatory = $true)][string]$RutaLog
    )

    $rutasArchivo = @(
        [pscustomobject]@{ Ruta = $RutaMsbuild; Descripcion = 'MSBuild' },
        [pscustomobject]@{ Ruta = $RutaProyecto; Descripcion = 'proyecto MSBuild' },
        [pscustomobject]@{ Ruta = (Join-Path $DirectorioGeneXus 'Genexus.Tasks.targets'); Descripcion = 'Genexus.Tasks.targets' }
    )

    foreach ($item in $rutasArchivo) {
        if (-not (Test-Path -LiteralPath $item.Ruta -PathType Leaf)) {
            throw ('No se encontro ' + $item.Descripcion + ': ' + $item.Ruta)
        }
    }

    if (-not (Test-Path -LiteralPath $RutaKnowledgeBase -PathType Container)) {
        throw ('No se encontro la carpeta de la Knowledge Base: ' + $RutaKnowledgeBase)
    }
    if (@(Get-ChildItem -LiteralPath $RutaKnowledgeBase -Filter '*.gxw' -File).Count -eq 0) {
        throw ('No se encontro ningun archivo .gxw en la Knowledge Base: ' + $RutaKnowledgeBase)
    }

    $directorioSalida = [System.IO.Path]::GetDirectoryName($RutaXpzSalida)
    if (-not (Test-Path -LiteralPath $directorioSalida -PathType Container)) {
        New-Item -ItemType Directory -Path $directorioSalida -Force | Out-Null
    }

    $directorioLog = [System.IO.Path]::GetDirectoryName($RutaLog)
    if (-not (Test-Path -LiteralPath $directorioLog -PathType Container)) {
        New-Item -ItemType Directory -Path $directorioLog -Force | Out-Null
    }
}

function Crear-ProyectoMsbuildTemporal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaProyectoBase,
        [Parameter(Mandatory = $true)][string[]]$NombresObjetos
    )

    $contenido = Get-Content -LiteralPath $RutaProyectoBase -Raw -Encoding UTF8
    $inicioProyecto = $contenido.IndexOf('<Project')
    $posicionCierreProyecto = if ($inicioProyecto -ge 0) { $contenido.IndexOf('>', $inicioProyecto) } else { -1 }
    if ($posicionCierreProyecto -lt 0) {
        throw ('El proyecto MSBuild no tiene una etiqueta Project valida: ' + $RutaProyectoBase)
    }

    $nombresLocales = @($NombresObjetos | ForEach-Object { Obtener-NombreLocalObjeto -Valor ([string]$_) } | Where-Object { $_ } | Select-Object -Unique)
    if ($nombresLocales.Count -eq 0) { throw 'La receta no contiene nombres locales para ObjectList.' }
    $listaEscapada = [System.Security.SecurityElement]::Escape(($nombresLocales -join ','))
    $propiedades = "`r`n  <PropertyGroup>`r`n    <ObjectList>$listaEscapada</ObjectList>`r`n  </PropertyGroup>"
    $contenido = $contenido.Insert($posicionCierreProyecto + 1, $propiedades)

    $nombreTemporal = 'ExportarXPZSelectivo_' + [System.Guid]::NewGuid().ToString('N') + '.msbuild'
    $rutaTemporal = Join-Path ([System.IO.Path]::GetTempPath()) $nombreTemporal
    Escribir-TextoUtf8SinBom -Ruta $rutaTemporal -Contenido $contenido
    return $rutaTemporal
}

function Ejecutar-ExportacionSelectiva {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaMsbuild,
        [Parameter(Mandatory = $true)][string]$RutaProyecto,
        [Parameter(Mandatory = $true)][string]$DirectorioGeneXus,
        [string]$RutaKnowledgeBase,
        [Parameter(Mandatory = $true)][string[]]$NombresObjetos,
        [Parameter(Mandatory = $true)][string]$RutaXpzSalida,
        [Parameter(Mandatory = $true)][string]$RutaLog,
        [string]$RutaConfiguracion,
        [ValidateSet('GX18', 'Evo3')]
        [string]$GeneXusExportProfile = 'GX18'
    )

    if ([string]::IsNullOrWhiteSpace($RutaKnowledgeBase)) {
        throw 'No se indico la ruta de la Knowledge Base para la exportacion selectiva.'
    }

    Escribir-TrazaExportacionSelectiva -RutaLog $RutaLog -Mensaje 'Comenzando armado del proyecto temporal.'
    Write-Host 'Armando proyecto temporal para la exportacion selectiva...' -ForegroundColor Gray
    $rutaProyectoTemporal = Crear-ProyectoMsbuildTemporal -RutaProyectoBase $RutaProyecto -NombresObjetos $NombresObjetos
    Escribir-TrazaExportacionSelectiva -RutaLog $RutaLog -Mensaje 'Proyecto temporal armado correctamente.'
    Write-Host 'Proyecto temporal de exportacion armado.' -ForegroundColor Gray
    $argumentos = @(
        (Quote-ProcessArgument -Valor $rutaProyectoTemporal),
        '/t:ExportarObjetosSelectivos',
        (Quote-ProcessArgument -Valor ("/p:GX_PROGRAM_DIR=$DirectorioGeneXus")),
        (Quote-ProcessArgument -Valor ("/p:KBPath=$RutaKnowledgeBase")),
        (Quote-ProcessArgument -Valor ("/p:XPZFile=$RutaXpzSalida")),
        (Quote-ProcessArgument -Valor ("/p:GeneXusExportProfile=$GeneXusExportProfile")),
        '/nologo',
        '/verbosity:minimal',
        '/fl',
        (Quote-ProcessArgument -Valor ("/flp:logfile=$RutaLog;verbosity=normal"))
    )

    $proceso = $null
    $idProceso = 0
    $horaInicio = Get-Date
    $salida = ''
    $errorSalida = ''
    $timeoutMsbuild = Obtener-TimeoutMsbuildSegundos -RutaConfiguracion $RutaConfiguracion
    $salidaBuilder = New-Object System.Text.StringBuilder
    $errorBuilder = New-Object System.Text.StringBuilder

    try {
        Escribir-TrazaExportacionSelectiva -RutaLog $RutaLog -Mensaje 'Iniciando proceso MSBuild.'
        Write-Host 'Iniciando exportacion selectiva en GeneXus...' -ForegroundColor Gray
        $horaInicio = Get-Date
        $informacionInicio = New-Object System.Diagnostics.ProcessStartInfo
        $informacionInicio.FileName = $RutaMsbuild
        $informacionInicio.Arguments = $argumentos -join ' '
        $informacionInicio.WorkingDirectory = Split-Path -Parent $RutaProyecto
        $informacionInicio.UseShellExecute = $false
        $informacionInicio.CreateNoWindow = $true
        $informacionInicio.RedirectStandardOutput = $true
        $informacionInicio.RedirectStandardError = $true
        $proceso = New-Object System.Diagnostics.Process
        $proceso.StartInfo = $informacionInicio
        if (-not $proceso.Start()) { throw 'No se pudo iniciar MSBuild.' }
        $idProceso = $proceso.Id
        Escribir-TrazaExportacionSelectiva -RutaLog $RutaLog -Mensaje ('MSBuild iniciado. PID ' + $idProceso + '.')

        $estadoSalida = [pscustomobject]@{ Reader = $proceso.StandardOutput; Task = $proceso.StandardOutput.ReadLineAsync(); Builder = $salidaBuilder; LastActivity = Get-Date }
        $estadoError = [pscustomobject]@{ Reader = $proceso.StandardError; Task = $proceso.StandardError.ReadLineAsync(); Builder = $errorBuilder; LastActivity = Get-Date }
        $leerSalida = {
            param($estado)
            while ($null -ne $estado.Task -and $estado.Task.IsCompleted) {
                $linea = $estado.Task.GetAwaiter().GetResult()
                if ($null -eq $linea) {
                    $estado.Task = $null
                    break
                }
                [void]$estado.Builder.AppendLine($linea)
                $estado.LastActivity = Get-Date
                $estado.Task = $estado.Reader.ReadLineAsync()
            }
        }
        while (-not $proceso.HasExited) {
            & $leerSalida $estadoSalida
            & $leerSalida $estadoError
            $ultimaActividadMsbuild = @($estadoSalida.LastActivity, $estadoError.LastActivity) | Sort-Object | Select-Object -Last 1
            if (((Get-Date) - $ultimaActividadMsbuild).TotalSeconds -ge $timeoutMsbuild) {
                throw ('MSBuild supero el timeout de inactividad configurado de ' + $timeoutMsbuild + ' segundos.')
            }
            Start-Sleep -Milliseconds 500
            $proceso.Refresh()
        }
        $proceso.WaitForExit()
        while ($null -ne $estadoSalida.Task -or $null -ne $estadoError.Task) {
            & $leerSalida $estadoSalida
            & $leerSalida $estadoError
            if ($null -ne $estadoSalida.Task -or $null -ne $estadoError.Task) { Start-Sleep -Milliseconds 20 }
        }
        Escribir-TrazaExportacionSelectiva -RutaLog $RutaLog -Mensaje ('MSBuild finalizo con codigo ' + $proceso.ExitCode + '.')
        $salida = $salidaBuilder.ToString()
        $errorSalida = $errorBuilder.ToString()

        $textoLog = @($salida, $errorSalida, (Get-Content -LiteralPath $RutaLog -Raw -ErrorAction SilentlyContinue)) -join "`n"
        $validacionXpz = Test-XpzValido -Ruta $RutaXpzSalida
        $exportacionConfirmada = $textoLog -match 'Export Success'
        $cierreConfirmado = $textoLog -match 'Close Knowledge Base Task Success'
        $mensajesError = @($textoLog -split "`r?`n" | Where-Object {
            $_ -match '(?i)^\s*(error\b|msb\d{4}\b|exception\b|fatal\b)' -or
            $_ -match '(?i)\s(error|fatal|exception)\s*:'
        } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
        $objetosNoEncontrados = @($textoLog -split "`r?`n" | Where-Object {
            $_ -match '(?i)(was not found in the Knowledge Base|no se encontr[oó].*Knowledge Base|no se encontr[oó].*base de conocimiento)'
        } | ForEach-Object { $_.Trim() } | Select-Object -Unique)

        if ($salida -or $errorSalida) {
            [System.IO.File]::AppendAllText($RutaLog, (@($salida, $errorSalida) -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
        }

        if ($proceso.ExitCode -ne 0 -or -not $exportacionConfirmada -or -not $cierreConfirmado -or -not $validacionXpz.Valid -or $mensajesError.Count -gt 0 -or $objetosNoEncontrados.Count -gt 0) {
            $detalle = if ($objetosNoEncontrados.Count -gt 0) { $objetosNoEncontrados -join ' | ' } elseif ($mensajesError.Count -gt 0) { $mensajesError -join ' | ' } elseif (-not $validacionXpz.Valid) { $validacionXpz.Error } else { 'GeneXus no confirmo una exportacion completa.' }
            throw ('La exportacion selectiva fallo: ' + $detalle)
        }

        Write-Host 'Exportacion selectiva finalizada correctamente.' -ForegroundColor Green
        return $validacionXpz
    } finally {
        if ($idProceso -gt 0) {
            if (-not $proceso.HasExited) {
                if (-not $proceso.WaitForExit(5000)) {
                    & "$env:SystemRoot\System32\taskkill.exe" /PID $idProceso /T /F 2>&1 | Out-Null
                    $proceso.WaitForExit(5000) | Out-Null
                }
            }

            $descendientes = @(Obtener-ProcesosDescendientes -IdProcesoRaiz $idProceso -IniciadoDespues $horaInicio)
            foreach ($idDescendiente in ($descendientes | Sort-Object -Descending)) {
                Stop-Process -Id $idDescendiente -Force -ErrorAction SilentlyContinue
            }
        }
        if ($proceso) { $proceso.Dispose() }
        if (Test-Path -LiteralPath $rutaProyectoTemporal -PathType Leaf) {
            Remove-Item -LiteralPath $rutaProyectoTemporal -Force -ErrorAction SilentlyContinue
        }
    }
}

try {
    $ejecucionId = ''
    $clienteId = $ClienteId
    $modulo = $Modulo
    $ambienteId = $AmbienteId
    if ($ManifiestoPath) {
        $manifiestoEjecucion = Leer-ManifiestoEjecucion -RutaManifiesto $ManifiestoPath
        $XpzPath = [string]$manifiestoEjecucion.xpz
        $ejecucionId = [string]$manifiestoEjecucion.ejecucionId
        $clienteId = [string]$manifiestoEjecucion.clienteId
        $modulo = [string]$manifiestoEjecucion.modulo
        $ambienteId = [string]$manifiestoEjecucion.ambienteId
        $DirectorioLogs = [System.IO.Path]::GetFullPath([string]$manifiestoEjecucion.logsDirectory)
        Asegurar-Directorio -Ruta $DirectorioLogs
    }
    $parametrosConfiguracion = @{ ConfigPath = $ConfigPath }
    if ($XpzPath) { $parametrosConfiguracion.XpzPath = $XpzPath }
    if ($clienteId) {
        $parametrosConfiguracion.ClienteId = $clienteId
        $parametrosConfiguracion.Modulo = $modulo
        $parametrosConfiguracion.AmbienteId = $ambienteId
    }
    $configuracion = Cargar-Configuracion @parametrosConfiguracion
    if ($XpzPath) {
        $configuracion | Add-Member -MemberType NoteProperty -Name 'XpzPath' -Value $XpzPath -Force
    }
    if (-not $GeneXusExportProfile) { $GeneXusExportProfile = [string]$configuracion.Herramientas.GeneXusExportProfile }
    if ($GeneXusExportProfile -notin @('GX18', 'Evo3')) { $GeneXusExportProfile = 'GX18' }
    $seleccion = Seleccionar-ReporteValidacion -Configuracion $configuracion -RutaReporte $ReportePath -EjecucionId $ejecucionId
    Mostrar-RecetaSeleccionada -Seleccion $seleccion
    $complemento = Seleccionar-SiguienteXpzComplementario -RutaXpzPrincipal $seleccion.XpzPrincipal
    $rutaMsbuildEfectiva = if ($GeneXusExportProfile -eq 'Evo3') {
        Resolver-RutaMsbuildPorPerfil -RutaConfigurada $MsbuildPath -Perfil $GeneXusExportProfile
    } elseif ($MsbuildPath) { $MsbuildPath } else {
        $directorioMsbuild = if ($GeneXusExportProfile -eq 'Evo3') { 'v3.5' } else { 'v4.0.30319' }
        Join-Path $env:SystemRoot ('Microsoft.NET\Framework\' + $directorioMsbuild + '\MSBuild.exe')
    }
    $rutaProyectoEfectiva = if ($GeneXusExportProfile -eq 'Evo3') {
        Join-Path $PSScriptRoot 'ExportarXPZSelectivoEvo3.msbuild'
    } elseif ($ProjectFile) { $ProjectFile } else { Join-Path $PSScriptRoot 'ExportarXPZSelectivo.msbuild' }
    if (-not $GxProgramDir) { throw 'Debe indicar -GxProgramDir para ejecutar la exportacion selectiva.' }
    if (-not $KbPath) { throw 'Debe indicar -KbPath para ejecutar la exportacion selectiva.' }
    $rutaXpzSalida = if ($XpzFile) { [System.IO.Path]::GetFullPath($XpzFile) } else { $complemento.Ruta }
    if ($XpzFile) {
        $directorioPrincipal = [System.IO.Path]::GetFullPath([System.IO.Path]::GetDirectoryName($seleccion.XpzPrincipal))
        $directorioSalidaExplicito = [System.IO.Path]::GetFullPath([System.IO.Path]::GetDirectoryName($rutaXpzSalida))
        if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($directorioPrincipal, $directorioSalidaExplicito)) {
            throw ('El XPZ selectivo debe quedar junto al XPZ principal: ' + $directorioPrincipal)
        }
        if (Test-Path -LiteralPath $rutaXpzSalida) {
            throw ('El archivo de salida ya existe y no se sobrescribira: ' + $rutaXpzSalida)
        }
    }
    $marcaTemporal = (Get-Date).ToString('yyyyMMdd_HHmmssfff')
    $rutaLogEfectiva = if ($LogFile) { [System.IO.Path]::GetFullPath($LogFile) } else { Join-Path $DirectorioLogs ('exportarXPZSelectivo_' + $marcaTemporal + '.log') }
    Validar-RutasEjecucion -Configuracion $configuracion -RutaMsbuild $rutaMsbuildEfectiva -RutaProyecto $rutaProyectoEfectiva -DirectorioGeneXus $GxProgramDir -RutaKnowledgeBase $KbPath -RutaXpzSalida $rutaXpzSalida -RutaLog $rutaLogEfectiva
    Avisar-InstanciasGeneXus
    Write-Host ('Complemento de salida: ' + $rutaXpzSalida) -ForegroundColor DarkGray
    Write-Host ('Log de ejecucion: ' + $rutaLogEfectiva) -ForegroundColor DarkGray
    Write-Host ('ObjectList (nombres GeneXus): ' + ($seleccion.Objetos -join ',')) -ForegroundColor DarkGray
    Escribir-TrazaExportacionSelectiva -RutaLog $rutaLogEfectiva -Mensaje ('ObjectList recibido: ' + ($seleccion.Objetos -join ','))
    Ejecutar-ExportacionSelectiva -RutaMsbuild $rutaMsbuildEfectiva -RutaProyecto $rutaProyectoEfectiva -DirectorioGeneXus $GxProgramDir -RutaKnowledgeBase $KbPath -NombresObjetos $seleccion.Objetos -RutaXpzSalida $rutaXpzSalida -RutaLog $rutaLogEfectiva -RutaConfiguracion $ConfigPath -GeneXusExportProfile $GeneXusExportProfile | Out-Null
    Write-Host ('XPZ complementario generado correctamente: ' + $rutaXpzSalida) -ForegroundColor Green
    exit 0
} catch {
    if ($rutaXpzSalida -and (Test-Path -LiteralPath $rutaXpzSalida -PathType Leaf)) {
        Remove-Item -LiteralPath $rutaXpzSalida -Force -ErrorAction SilentlyContinue
    }
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
