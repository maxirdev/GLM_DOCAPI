# GLMUtilidades.ps1
# Modulo comun de utilidades del pipeline APIGLM.
# Se importa por dot-source SIEMPRE PRIMERO, antes de cualquier otro script
# del proyecto. Es una hoja: no depende de otros scripts del repositorio.
# Solo define funciones; no ejecuta logica al cargarse.
# Las firmas canonicas conservan la forma de la implementacion vigente que
# reemplazan para preservar hashes y contratos byte a byte.

$ErrorActionPreference = 'Stop'

function Inicializar-ConsolaUtf8 {
    [CmdletBinding()]
    param()

    if (-not [Console]::IsOutputRedirected) {
        try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    }
    try { $OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
}

function Restaurar-ColorConsola {
    <#
    .SYNOPSIS
    Restaura el color de consola capturado antes de invocar un proceso hijo.
    .DESCRIPTION
    Un proceso hijo que escribe con colores a la consola compartida puede dejarla
    en su ultimo color (p. ej. Cyan). Esta funcion devuelve [Console]::ForegroundColor
    al valor capturado antes de la invocacion.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][System.ConsoleColor]$ColorBase
    )

    try {
        [Console]::ForegroundColor = $ColorBase
    } catch {
    }
}

function Normalizar-SaltosLineaLf {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Texto
    )

    return ($Texto -replace "`r`n", "`n") -replace "`r", "`n"
}

function Obtener-Sha256TextoNormalizado {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Texto
    )

    $textoNormalizado = Normalizar-SaltosLineaLf -Texto $Texto
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($textoNormalizado)
        return (([System.BitConverter]::ToString($sha256.ComputeHash($bytes))) -replace '-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function Obtener-Sha256ArchivoNormalizado {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Ruta
    )

    return Obtener-Sha256TextoNormalizado -Texto ([System.IO.File]::ReadAllText($Ruta))
}

function Obtener-Sha256Archivo {
    <#
    .SYNOPSIS
    Hash SHA256 hexadecimal en minusculas del contenido binario de un archivo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Ruta
    )

    $flujo = $null
    $sha256 = $null
    try {
        $flujo = [System.IO.File]::OpenRead($Ruta)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        return (([System.BitConverter]::ToString($sha256.ComputeHash($flujo))) -replace '-', '').ToLowerInvariant()
    } finally {
        if ($null -ne $flujo) { $flujo.Dispose() }
        if ($null -ne $sha256) { $sha256.Dispose() }
    }
}

function Asegurar-Directorio {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Ruta
    )

    if (-not (Test-Path -LiteralPath $Ruta -PathType Container)) {
        New-Item -ItemType Directory -Path $Ruta -Force | Out-Null
    }
}

function Resolver-RutaMsbuildPorPerfil {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$RutaConfigurada,
        [Parameter(Mandatory = $true)][ValidateSet('GX18', 'Evo3')][string]$Perfil
    )

    if ($Perfil -ne 'Evo3') {
        return $RutaConfigurada
    }

    # Evo3 requiere MSBuild 3.5. No reutilizar la ruta configurada para GX18:
    # MSBuild 3.5 no admite AfterTargets y necesita el proyecto Evo3 dedicado.
    $rutaEvo3 = Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v3.5\MSBuild.exe'
    if (-not (Test-Path -LiteralPath $rutaEvo3 -PathType Leaf)) {
        throw ('No se encontro MSBuild 3.5 requerido por Evo3: ' + $rutaEvo3)
    }
    return [System.IO.Path]::GetFullPath($rutaEvo3)
}

function Limpiar-LogsEjecucion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DirectorioLogs
    )

    if ([string]::IsNullOrWhiteSpace($DirectorioLogs)) {
        throw 'No se puede limpiar un directorio de logs vacio.'
    }
    $rutaCompleta = [System.IO.Path]::GetFullPath($DirectorioLogs)
    Asegurar-Directorio -Ruta $rutaCompleta
    foreach ($entrada in @(Get-ChildItem -LiteralPath $rutaCompleta -Force -ErrorAction Stop)) {
        Remove-Item -LiteralPath $entrada.FullName -Recurse -Force -ErrorAction Stop
    }
}

function Escribir-TextoUtf8SinBom {
    <#
    .SYNOPSIS
    Escribe un archivo de texto en UTF-8 sin BOM conservando los bytes del contenido.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Ruta,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Contenido
    )

    Asegurar-Directorio -Ruta ([System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Ruta)))
    $codificacion = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Ruta, $Contenido, $codificacion)
}

function Escribir-ArchivoAtomico {
    <#
    .SYNOPSIS
    Reemplaza un archivo de forma atomica: escritura temporal, respaldo y limpieza.
    .DESCRIPTION
    Escribe el contenido en <ruta>.<guid>.tmp en UTF-8 sin BOM. Si la ruta de
    destino existe, la reemplaza con File.Replace conservando un respaldo .bak
    que se elimina en el finally; si no existe, mueve el temporal. Si se indica
    -Validar, el scriptblock recibe la ruta temporal y puede lanzar una excepcion
    para abortar antes del reemplazo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Ruta,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Contenido,
        [Parameter(Mandatory = $false)][scriptblock]$Validar
    )

    $rutaCompleta = [System.IO.Path]::GetFullPath($Ruta)
    Asegurar-Directorio -Ruta ([System.IO.Path]::GetDirectoryName($rutaCompleta))
    $rutaTemporal = $rutaCompleta + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $rutaRespaldo = $rutaCompleta + '.' + [guid]::NewGuid().ToString('N') + '.bak'
    try {
        Escribir-TextoUtf8SinBom -Ruta $rutaTemporal -Contenido $Contenido
        if ($Validar) {
            & $Validar $rutaTemporal | Out-Null
        }
        if (Test-Path -LiteralPath $rutaCompleta -PathType Leaf) {
            [System.IO.File]::Replace($rutaTemporal, $rutaCompleta, $rutaRespaldo)
        } else {
            [System.IO.File]::Move($rutaTemporal, $rutaCompleta)
        }
    } finally {
        if (Test-Path -LiteralPath $rutaTemporal -PathType Leaf) {
            Remove-Item -LiteralPath $rutaTemporal -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $rutaRespaldo -PathType Leaf) {
            Remove-Item -LiteralPath $rutaRespaldo -Force -ErrorAction SilentlyContinue
        }
    }
    return $rutaCompleta
}

function Resolver-RutaRepositorio {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Ruta,
        [Parameter(Mandatory = $true)][string]$Raiz
    )

    if ([System.IO.Path]::IsPathRooted($Ruta)) {
        return [System.IO.Path]::GetFullPath($Ruta)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $Raiz $Ruta))
}

function Quote-ProcessArgument {
    param([Parameter(Mandatory = $true)][string]$Valor)
    return '"' + $Valor.Replace('"', '\"') + '"'
}

function Test-PdfValidoParaPromocion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Ruta
    )

    if (-not (Test-Path -LiteralPath $Ruta -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $Ruta).Length -lt 5) { return $false }
    $flujo = [System.IO.File]::OpenRead($Ruta)
    try {
        $cabecera = New-Object byte[] 4
        [void]$flujo.Read($cabecera, 0, 4)
        return ([System.Text.Encoding]::ASCII.GetString($cabecera) -eq '%PDF')
    } finally {
        $flujo.Dispose()
    }
}

function Test-XpzValido {
    <#
    .SYNOPSIS
    Valida que un archivo XPZ sea un ZIP con un unico XML cuya raiz es ExportFile.
    .DESCRIPTION
    Devuelve un objeto con las propiedades Valid (bool) y Error (string), con los
    mismos mensajes que la implementacion vigente del pipeline de exportacion.
    #>
    param([Parameter(Mandatory = $true)][string]$Ruta)

    if (-not (Test-Path -LiteralPath $Ruta -PathType Leaf)) {
        return [pscustomobject]@{ Valid = $false; Error = 'no se encontro el archivo XPZ esperado' }
    }

    $zip = $null
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Ruta)
        $entradasXml = @($zip.Entries | Where-Object { $_.Name -like '*.xml' })
        if ($entradasXml.Count -ne 1) {
            return [pscustomobject]@{ Valid = $false; Error = "el XPZ contiene $($entradasXml.Count) archivos XML; se esperaba uno" }
        }

        $lector = New-Object System.IO.StreamReader($entradasXml[0].Open())
        try {
            $xml = New-Object System.Xml.XmlDocument
            $xml.LoadXml($lector.ReadToEnd())
        } finally {
            $lector.Dispose()
        }

        if ($xml.DocumentElement.LocalName -ne 'ExportFile') {
            return [pscustomobject]@{ Valid = $false; Error = "la raiz XML es $($xml.DocumentElement.LocalName); se esperaba ExportFile" }
        }

        return [pscustomobject]@{ Valid = $true; Error = '' }
    } catch {
        return [pscustomobject]@{ Valid = $false; Error = "el XPZ no es valido: $($_.Exception.Message)" }
    } finally {
        if ($null -ne $zip) { $zip.Dispose() }
    }
}

function Test-XpzContieneObjeto {
    param(
        [Parameter(Mandatory = $true)][string]$Ruta,
        [Parameter(Mandatory = $true)][string]$FullyQualifiedName
    )

    $validacion = Test-XpzValido -Ruta $Ruta
    if (-not $validacion.Valid) {
        return [pscustomobject]@{ Valid = $false; Error = $validacion.Error }
    }

    $zip = $null
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Ruta)
        $entradaXml = @($zip.Entries | Where-Object { $_.Name -like '*.xml' })[0]
        $lector = New-Object System.IO.StreamReader($entradaXml.Open())
        try {
            $xml = New-Object System.Xml.XmlDocument
            $xml.LoadXml($lector.ReadToEnd())
        } finally {
            $lector.Dispose()
        }
        $objeto = @($xml.SelectNodes("//*[local-name()='Object']") | Where-Object {
            [string]$_.GetAttribute('fullyQualifiedName') -eq $FullyQualifiedName
        }) | Select-Object -First 1
        if ($null -eq $objeto) {
            return [pscustomobject]@{ Valid = $false; Error = "no contiene el objeto '$FullyQualifiedName'" }
        }
        return [pscustomobject]@{ Valid = $true; Error = '' }
    } catch {
        return [pscustomobject]@{ Valid = $false; Error = "no se pudo inspeccionar el XPZ: $($_.Exception.Message)" }
    } finally {
        if ($null -ne $zip) { $zip.Dispose() }
    }
}

function Invocar-ScriptHijo {
    <#
    .SYNOPSIS
    Ejecuta un script PowerShell como proceso hijo capturando y coloreando la salida.
    .DESCRIPTION
    Invoca powershell.exe -NoProfile -ExecutionPolicy Bypass -File. La salida se
    escribe en consola (ErrorRecord y lineas 'error:' en rojo) salvo con
    -NoImprimir, y siempre se devuelve en la propiedad Salida. Con
    -NormalizarCodigo el codigo de salida se reduce a 0 (completo), 1 (error
    fatal), 2 (parcial) o 3 (abortado).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaScript,
        [Parameter(Mandatory = $false)][string[]]$Argumentos = @(),
        [switch]$NormalizarCodigo,
        [switch]$NoImprimir
    )

    $rutaPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $rutaPowerShell -PathType Leaf)) {
        throw ('No se encontro Windows PowerShell en: ' + $rutaPowerShell)
    }
    if (-not (Test-Path -LiteralPath $RutaScript -PathType Leaf)) {
        throw ('No se encontro el script: ' + $RutaScript)
    }

    $lineas = New-Object System.Collections.Generic.List[string]
    $preferenciaErrorPrevia = $ErrorActionPreference
    $colorBase = [Console]::ForegroundColor
    $proceso = $null
    $salidaBuilder = New-Object System.Text.StringBuilder
    $errorBuilder = New-Object System.Text.StringBuilder
    $inicio = Get-Date
    $ultimoHeartbeat = $inicio
    $codigoProceso = 1
    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $rutaPowerShell
        $startInfo.Arguments = ((@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $RutaScript) + @($Argumentos)) | ForEach-Object { Quote-ProcessArgument -Valor ([string]$_) }) -join ' '
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $proceso = New-Object System.Diagnostics.Process
        $proceso.StartInfo = $startInfo
        if (-not $proceso.Start()) { throw ('No se pudo iniciar el script hijo: ' + $RutaScript) }
        $stdout = [pscustomobject]@{ Reader = $proceso.StandardOutput; Task = $proceso.StandardOutput.ReadLineAsync(); LastLine = '' }
        $stderr = [pscustomobject]@{ Reader = $proceso.StandardError; Task = $proceso.StandardError.ReadLineAsync(); LastLine = '' }
        $leer = {
            param($estado, [System.Text.StringBuilder]$buffer, [bool]$esError)
            while ($null -ne $estado.Task -and $estado.Task.IsCompleted) {
                $texto = $estado.Task.GetAwaiter().GetResult()
                if ($null -eq $texto) { $estado.Task = $null; break }
                [void]$buffer.AppendLine($texto)
                [void]$lineas.Add($texto)
                $estado.LastLine = $texto
                if (-not $NoImprimir) {
                    Write-Host $texto -ForegroundColor $(if ($esError -or $texto -match '(?i)^\s*error\s*:') { 'Red' } else { $colorBase })
                }
                $estado.Task = $estado.Reader.ReadLineAsync()
            }
        }
        while (-not $proceso.HasExited) {
            & $leer $stdout $salidaBuilder $false
            & $leer $stderr $errorBuilder $true
            if (((Get-Date) - $ultimoHeartbeat).TotalSeconds -ge 30) {
                $nombreScript = [System.IO.Path]::GetFileName($RutaScript)
                $mensajeHeartbeat = switch -Regex ($nombreScript) {
                    '^ValidarXPZ\.ps1$' { 'Validando XPZ... se continua con la validacion.'; break }
                    '^GenerarDocumento\.ps1$' { 'Continua la generacion de los documentos Markdown. Aguarde...'; break }
                    '^GenerarPdfServicios\.ps1$' { 'Continua la generacion de los documentos PDF. Aguarde...'; break }
                    default { 'El proceso continua en ejecucion. Aguarde...'; break }
                }
                Write-Host $mensajeHeartbeat -ForegroundColor Cyan
                $ultimoHeartbeat = Get-Date
            }
            Start-Sleep -Milliseconds 250
            $proceso.Refresh()
        }
        $proceso.WaitForExit()
        while ($null -ne $stdout.Task -or $null -ne $stderr.Task) {
            & $leer $stdout $salidaBuilder $false
            & $leer $stderr $errorBuilder $true
            if ($null -ne $stdout.Task -or $null -ne $stderr.Task) { Start-Sleep -Milliseconds 10 }
        }
    } finally {
        if ($proceso) {
            try {
                if (-not $proceso.HasExited) {
                    & "$env:SystemRoot\System32\taskkill.exe" /PID $proceso.Id /T /F 2>&1 | Out-Null
                    $proceso.WaitForExit(5000) | Out-Null
                }
            } catch { }
            try { $codigoProceso = [int]$proceso.ExitCode } catch { $codigoProceso = 1 }
            $proceso.Dispose()
        }
        $ErrorActionPreference = $preferenciaErrorPrevia
        Restaurar-ColorConsola -ColorBase $colorBase
    }
    $codigoSalida = $codigoProceso
    if ($NormalizarCodigo) {
        if ($codigoSalida -notin @(0, 1, 2, 3)) { $codigoSalida = 1 }
    }
    return [pscustomobject]@{
        CodigoSalida = $codigoSalida
        Salida = @($lineas)
    }
}

function Obtener-ProcesosDescendientes {
    <#
    .SYNOPSIS
    Devuelve los IDs de los procesos descendientes de un proceso raiz creados
    despues de un instante dado.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$IdProcesoRaiz,
        [Parameter(Mandatory = $true)][datetime]$IniciadoDespues
    )

    $resultado = New-Object System.Collections.Generic.List[int]
    $pendientes = New-Object System.Collections.Generic.Queue[int]
    $pendientes.Enqueue($IdProcesoRaiz)
    $procesos = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)

    while ($pendientes.Count -gt 0) {
        $idPadre = $pendientes.Dequeue()
        foreach ($proceso in ($procesos | Where-Object { $_.ParentProcessId -eq $idPadre })) {
            $fechaCreacion = $null
            try {
                if ($proceso.CreationDate -is [datetime]) {
                    $fechaCreacion = [datetime]$proceso.CreationDate
                } else {
                    $fechaCreacion = [System.Management.ManagementDateTimeConverter]::ToDateTime([string]$proceso.CreationDate)
                }
            } catch {}

            if ($null -ne $fechaCreacion -and $fechaCreacion -lt $IniciadoDespues.AddSeconds(-2)) { continue }
            if (-not $resultado.Contains([int]$proceso.ProcessId)) {
                $resultado.Add([int]$proceso.ProcessId)
                $pendientes.Enqueue([int]$proceso.ProcessId)
            }
        }
    }

    return @($resultado)
}

function Avisar-InstanciasGeneXus {
    <#
    .SYNOPSIS
    Advierte en consola si hay instancias de GeneXus abiertas antes de exportar.
    #>
    [CmdletBinding()]
    param()

    $instanciasGeneXus = @(Get-Process -Name 'GeneXus' -ErrorAction SilentlyContinue)
    if ($instanciasGeneXus.Count -gt 0) {
        Write-Host ''
        Write-Host ('ADVERTENCIA: se detectaron ' + $instanciasGeneXus.Count + ' instancia(s) de GeneXus abierta(s).') -ForegroundColor Yellow
        Write-Host 'La exportacion continuara usando una sesion independiente de MSBuild.' -ForegroundColor Yellow
        Write-Host 'No edite objetos ni ejecute especificaciones, generaciones o reorganizaciones durante la exportacion.' -ForegroundColor Yellow
        Write-Host ''
    }
}

function Add-Line {
    param(
        [Parameter(Mandatory = $true)][System.Text.StringBuilder]$Builder,
        [string]$Text = ''
    )
    [void]$Builder.Append($Text)
    [void]$Builder.Append("`n")
}

function Leer-InventarioEndpoints {
    <#
    .SYNOPSIS
    Lee un inventario legado desde endpoints.json y devuelve sus entradas.
    No es utilizado por el pipeline contextual; el descubrimiento operativo se
    realiza en memoria desde el XPZ.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaInventario
    )

    if (-not (Test-Path -LiteralPath $RutaInventario -PathType Leaf)) {
        throw ('No se encontro el inventario en: ' + $RutaInventario)
    }
    $inventario = [System.IO.File]::ReadAllText($RutaInventario) | ConvertFrom-Json
    return @($inventario.endpoints)
}

function Leer-ConfiguracionCruda {
    <#
    .SYNOPSIS
    Lee configuracion.json sin resolver rutas ni validar el XPZ.
    .DESCRIPTION
    Para consumidores que solo necesitan propiedades crudas (herramientas,
    exportacion) y no requieren un XPZ activo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw ('No se encontro el archivo de configuracion: ' + $ConfigPath)
    }
    return ([System.IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json)
}

function New-RegistroServicioControl {
    <#
    .SYNOPSIS
    Fabrica el registro base de un servicio para el control de versiones.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$WrapperGuid = '',
        [Parameter(Mandatory = $false)][int]$Revision = 0,
        [Parameter(Mandatory = $false)][string]$Version = '1.0',
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$DocumentHash = '',
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$PdfHash = '',
        [Parameter(Mandatory = $false)]$Dependencias = $null,
        [Parameter(Mandatory = $false)][string]$Status = 'ACTIVO'
    )

    $listaDependencias = New-Object System.Collections.ArrayList
    foreach ($dependencia in @($Dependencias | Where-Object { $null -ne $_ })) {
        [void]$listaDependencias.Add($dependencia)
    }
    return [ordered]@{
        wrapperGuid = $WrapperGuid
        revision = $Revision
        version = $Version
        documentHash = $DocumentHash
        pdfHash = $PdfHash
        dependencies = $listaDependencias
        status = $Status
    }
}

function Obtener-ReporteValidacionMasReciente {
    <#
    .SYNOPSIS
    Busca el reporte *-validacion-xpz.json mas reciente compatible con un XPZ.
    .DESCRIPTION
    Devuelve un objeto con Datos (reporte JSON) y Ruta, o $null. Si se indica
    -EjecucionId, el reporte debe pertenecer a esa ejecucion.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DirectorioLogs,
        [Parameter(Mandatory = $true)][string]$RutaXpz,
        [Parameter(Mandatory = $true)][string]$RaizRepositorio,
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$EjecucionId = ''
    )

    $rutaXpzEsperada = [System.IO.Path]::GetFullPath($RutaXpz)
    $reportes = @(Get-ChildItem -LiteralPath $DirectorioLogs -Filter '*-validacion-xpz.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    foreach ($archivo in $reportes) {
        try {
            $reporte = Get-Content -LiteralPath $archivo.FullName -Raw | ConvertFrom-Json
            if (-not $reporte.ejecucion -or -not $reporte.ejecucion.xpz) { continue }
            if ($EjecucionId -and [string]$reporte.ejecucion.id -ne $EjecucionId) { continue }
            $rutaReportada = Resolver-RutaRepositorio -Ruta ([string]$reporte.ejecucion.xpz) -Raiz $RaizRepositorio
            if ([System.StringComparer]::OrdinalIgnoreCase.Equals($rutaReportada, $rutaXpzEsperada)) {
                return [pscustomobject]@{
                    Datos = $reporte
                    Ruta = $archivo.FullName
                }
            }
        } catch {
        }
    }
    return $null
}

function Obtener-ObjetosPendientes {
    <#
    .SYNOPSIS
    Extrae los nombres de objetos pendientes de exportacion desde un reporte de
    validacion, priorizando solicitudes.exportar, luego objectList y finalmente
    los selectores como ultimo recurso.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Reporte
    )

    $objetos = New-Object System.Collections.Generic.List[string]

    if ($Reporte.solicitudes) {
        foreach ($solicitud in @($Reporte.solicitudes)) {
            foreach ($objeto in @($solicitud.exportar)) {
                $valor = ([string]$objeto).Trim()
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
            $nombre = $objeto.Trim()
            if ($nombre -and $objetos -notcontains $nombre) {
                [void]$objetos.Add($nombre)
            }
        }
    }

    if ($objetos.Count -eq 0 -and $Reporte.solicitudes) {
        foreach ($solicitud in @($Reporte.solicitudes)) {
            foreach ($selector in @($solicitud.selectores)) {
                $partes = ([string]$selector).Split(':', 2)
                $nombre = if ($partes.Count -eq 2) { $partes[1].Trim().Split('.')[-1] } else { ([string]$selector).Trim() }
                if ($nombre -and $objetos -notcontains $nombre) {
                    [void]$objetos.Add($nombre)
                }
            }
        }
    }

    return @($objetos)
}

function Obtener-SignaturaPendientes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Reporte
    )

    $lista = [string]$Reporte.objectList
    if ([string]::IsNullOrWhiteSpace($lista) -and $Reporte.solicitudes) {
        $lista = (@($Reporte.solicitudes | ForEach-Object { @($_.exportar) } | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join ',')
    }
    return $lista.Trim()
}
