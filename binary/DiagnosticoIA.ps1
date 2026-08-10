function Convertir-TextoDiagnosticoSeguro {
    param(
        [AllowNull()][string]$Texto,
        [Parameter(Mandatory = $true)][string]$RaizRepositorio
    )

    if ([string]::IsNullOrEmpty($Texto)) { return '' }

    $raizCompleta = [System.IO.Path]::GetFullPath($RaizRepositorio).TrimEnd('\', '/')
    $resultado = [regex]::Replace(
        $Texto,
        [regex]::Escape($raizCompleta + [System.IO.Path]::DirectorySeparatorChar),
        '',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    $resultado = $resultado.Replace('\', '/')
    $resultado = $resultado.Replace("`r`n", "`n")
    $resultado = [regex]::Replace($resultado, '(?i)\b[A-Z]:/[^\s\r\n]+', '[ruta-externa]')
    return $resultado
}

function Convertir-RutaDiagnostico {
    param(
        [AllowNull()][string]$Ruta,
        [Parameter(Mandatory = $true)][string]$RaizRepositorio
    )

    if ([string]::IsNullOrWhiteSpace($Ruta)) { return '' }

    try {
        $rutaCompleta = [System.IO.Path]::GetFullPath($Ruta)
        $raizCompleta = [System.IO.Path]::GetFullPath($RaizRepositorio).TrimEnd('\', '/')
        $prefijo = $raizCompleta + [System.IO.Path]::DirectorySeparatorChar
        if ($rutaCompleta.StartsWith($prefijo, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $rutaCompleta.Substring($prefijo.Length).Replace('\', '/')
        }
        return '[ruta-externa]/' + [System.IO.Path]::GetFileName($rutaCompleta)
    } catch {
        return '[ruta-no-resuelta]'
    }
}

function New-DiagnosticoIAError {
    param(
        [Parameter(Mandatory = $true)][System.Management.Automation.ErrorRecord]$ErrorRecord,
        [Parameter(Mandatory = $true)][string]$Componente,
        [Parameter(Mandatory = $true)][string]$Fase,
        [string]$Servicio = '',
        [Parameter(Mandatory = $true)][string]$RaizRepositorio
    )

    $invocacion = $ErrorRecord.InvocationInfo
    $rutaScript = $invocacion.ScriptName
    if (-not $rutaScript -and $invocacion.MyCommand) { $rutaScript = $invocacion.MyCommand.Path }

    $causas = New-Object System.Collections.Generic.List[object]
    $causa = $ErrorRecord.Exception.InnerException
    while ($causa) {
        $causas.Add([pscustomobject]@{
            tipo = $causa.GetType().FullName
            mensaje = Convertir-TextoDiagnosticoSeguro -Texto $causa.Message -RaizRepositorio $RaizRepositorio
        })
        $causa = $causa.InnerException
    }

    $sentencia = ''
    if ($invocacion.Line) { $sentencia = $invocacion.Line.Trim() }

    return [pscustomobject]@{
        componente = $Componente
        fase = $Fase
        servicio = $Servicio
        tipoExcepcion = $ErrorRecord.Exception.GetType().FullName
        mensaje = Convertir-TextoDiagnosticoSeguro -Texto $ErrorRecord.Exception.Message -RaizRepositorio $RaizRepositorio
        causas = $causas.ToArray()
        categoria = [pscustomobject]@{
            nombre = Convertir-TextoDiagnosticoSeguro -Texto ([string]$ErrorRecord.CategoryInfo.Category) -RaizRepositorio $RaizRepositorio
            actividad = Convertir-TextoDiagnosticoSeguro -Texto ([string]$ErrorRecord.CategoryInfo.Activity) -RaizRepositorio $RaizRepositorio
            motivo = Convertir-TextoDiagnosticoSeguro -Texto ([string]$ErrorRecord.CategoryInfo.Reason) -RaizRepositorio $RaizRepositorio
        }
        errorId = Convertir-TextoDiagnosticoSeguro -Texto ([string]$ErrorRecord.FullyQualifiedErrorId) -RaizRepositorio $RaizRepositorio
        origen = [pscustomobject]@{
            archivo = Convertir-RutaDiagnostico -Ruta $rutaScript -RaizRepositorio $RaizRepositorio
            linea = $invocacion.ScriptLineNumber
            columna = $invocacion.OffsetInLine
            sentencia = Convertir-TextoDiagnosticoSeguro -Texto $sentencia -RaizRepositorio $RaizRepositorio
        }
        scriptStackTrace = Convertir-TextoDiagnosticoSeguro -Texto $ErrorRecord.ScriptStackTrace -RaizRepositorio $RaizRepositorio
        dotNetStackTrace = Convertir-TextoDiagnosticoSeguro -Texto $ErrorRecord.Exception.StackTrace -RaizRepositorio $RaizRepositorio
    }
}

function Write-DiagnosticoIA {
    param(
        [Parameter(Mandatory = $true)]$Errores,
        [Parameter(Mandatory = $true)][string]$Pipeline,
        [Parameter(Mandatory = $true)][datetime]$Inicio,
        [Parameter(Mandatory = $true)][string]$DirectorioLogs,
        [Parameter(Mandatory = $true)][string]$RaizRepositorio,
        [string]$MarcaTemporal
    )

    $listaErrores = @($Errores | ForEach-Object { $_ })
    if ($listaErrores.Count -eq 0) { return $null }

    if (-not (Test-Path -LiteralPath $DirectorioLogs)) {
        New-Item -ItemType Directory -Path $DirectorioLogs -Force | Out-Null
    }
    $fin = Get-Date
    if (-not $MarcaTemporal) { $MarcaTemporal = $fin.ToString('yyyyMMdd-HHmmss') }

    $informe = [pscustomobject]@{
        schemaVersion = 1
        ejecucion = [pscustomobject]@{
            pipeline = $Pipeline
            inicio = $Inicio.ToString('s')
            fin = $fin.ToString('s')
            powerShell = $PSVersionTable.PSVersion.ToString()
            totalErrores = $listaErrores.Count
        }
        errores = $listaErrores
    }
    $ruta = Join-Path $DirectorioLogs ($MarcaTemporal + '-diagnostico-ia.json')
    $json = $informe | ConvertTo-Json -Depth 8
    $json = $json -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($ruta, $json, (New-Object System.Text.UTF8Encoding($false)))
    return $ruta
}
