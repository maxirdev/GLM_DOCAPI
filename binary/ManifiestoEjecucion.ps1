# Contrato compartido del manifiesto de ejecucion no interactiva (esquema 2).

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'GLMUtilidades.ps1')

function Obtener-NuevoIdentificadorEjecucion {
    [CmdletBinding()]
    param()

    $marcaTemporal = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $sufijoAleatorio = [guid]::NewGuid().ToString('N').Substring(0, 8)
    return $marcaTemporal + '-' + $sufijoAleatorio
}

function Validar-ManifiestoEjecucion {
    <#
    .SYNOPSIS
    Valida el manifiesto de esquema 2 y la pertenencia de sus rutas al contexto.
    .DESCRIPTION
    Comprueba los campos de identidad y rutas contextuales, que contextId sea
    clienteId/ambienteId y que las rutas de servicios, estado, logs y XPZ deriven
    del mismo directorio de contexto. Rechaza combinaciones hibridas, como el XPZ
    de un ambiente con documentos o control de otro.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Manifiesto
    )

    $versionEsquema = [int]$Manifiesto.schemaVersion
    if ($versionEsquema -ne 2) {
        throw 'El manifiesto de ejecucion tiene un schemaVersion no soportado.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Manifiesto.ejecucionId)) {
        throw 'El manifiesto de ejecucion no contiene ejecucionId.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Manifiesto.contextId)) {
        throw 'El manifiesto de ejecucion no contiene contextId.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Manifiesto.clienteId)) {
        throw 'El manifiesto de ejecucion no contiene clienteId.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Manifiesto.ambienteId)) {
        throw 'El manifiesto de ejecucion no contiene ambienteId.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Manifiesto.configPath)) {
        throw 'El manifiesto de ejecucion no contiene configPath.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Manifiesto.xpz)) {
        throw 'El manifiesto de ejecucion no contiene xpz.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Manifiesto.servicesDirectory)) {
        throw 'El manifiesto de ejecucion no contiene servicesDirectory.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Manifiesto.stateDirectory)) {
        throw 'El manifiesto de ejecucion no contiene stateDirectory.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Manifiesto.logsDirectory)) {
        throw 'El manifiesto de ejecucion no contiene logsDirectory.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Manifiesto.staging)) {
        throw 'El manifiesto de ejecucion no contiene staging.'
    }
    if ($null -eq $Manifiesto.fullyQualifiedNames) {
        throw 'El manifiesto de ejecucion no contiene fullyQualifiedNames.'
    }
    $comparador = [System.StringComparer]::OrdinalIgnoreCase
    $tieneHost = -not [string]::IsNullOrWhiteSpace([string]$Manifiesto.host)
    $tieneBaseUrl = -not [string]::IsNullOrWhiteSpace([string]$Manifiesto.baseUrl)
    $tieneServerUrl = -not [string]::IsNullOrWhiteSpace([string]$Manifiesto.serverUrl)
    if ($tieneHost -or $tieneBaseUrl -or $tieneServerUrl) {
        if (-not ($tieneHost -and $tieneBaseUrl -and $tieneServerUrl)) { throw 'El manifiesto debe contener host, baseUrl y serverUrl juntos.' }
        $serverUrlEsperado = ([string]$Manifiesto.host).TrimEnd('/') + '/' + ([string]$Manifiesto.baseUrl).TrimStart('/').TrimStart('/')
        if (-not $comparador.Equals([string]$Manifiesto.serverUrl, $serverUrlEsperado)) {
            throw ('El serverUrl del manifiesto no coincide con host/baseUrl: ' + [string]$Manifiesto.serverUrl)
        }
    }

    $contextoEsperado = [string]$Manifiesto.clienteId + '/' + [string]$Manifiesto.ambienteId
    if (-not $comparador.Equals([string]$Manifiesto.contextId, $contextoEsperado)) {
        throw ("El contextId del manifiesto no coincide con clienteId/ambienteId: " + [string]$Manifiesto.contextId)
    }

    $directorioServiciosCompleto = [System.IO.Path]::GetFullPath([string]$Manifiesto.servicesDirectory)
    $directorioEstadoCompleto = [System.IO.Path]::GetFullPath([string]$Manifiesto.stateDirectory)
    $directorioLogsCompleto = [System.IO.Path]::GetFullPath([string]$Manifiesto.logsDirectory)
    $directorioXpzCompleto = [System.IO.Path]::GetFullPath((Split-Path -Parent ([System.IO.Path]::GetFullPath([string]$Manifiesto.xpz))))

    $contextoDesdeServicios = [System.IO.Path]::GetFullPath((Join-Path $directorioServiciosCompleto '..'))
    $contextoDesdeEstado = [System.IO.Path]::GetFullPath((Join-Path $directorioEstadoCompleto '..'))
    $contextoDesdeLogs = [System.IO.Path]::GetFullPath((Join-Path $directorioLogsCompleto '..'))
    $directorioXpzEsperado = [System.IO.Path]::GetFullPath((Join-Path $contextoDesdeServicios 'xpz'))

    if (-not $comparador.Equals($contextoDesdeServicios, $contextoDesdeEstado) -or
        -not $comparador.Equals($contextoDesdeServicios, $contextoDesdeLogs) -or
        -not $comparador.Equals($directorioXpzCompleto, $directorioXpzEsperado)) {
        throw 'Las rutas del manifiesto no pertenecen al mismo contexto (documentos, estado, logs o XPZ de otro ambiente).'
    }

    return $true
}

function Leer-ManifiestoEjecucion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaManifiesto
    )

    $rutaCompleta = [System.IO.Path]::GetFullPath($RutaManifiesto)
    if (-not (Test-Path -LiteralPath $rutaCompleta -PathType Leaf)) {
        throw ('No se encontro el manifiesto de ejecucion: ' + $rutaCompleta)
    }
    try {
        $manifiesto = [System.IO.File]::ReadAllText($rutaCompleta) | ConvertFrom-Json
    } catch {
        throw ('El manifiesto de ejecucion no contiene JSON valido: ' + $_.Exception.Message)
    }
    Validar-ManifiestoEjecucion -Manifiesto $manifiesto | Out-Null
    return $manifiesto
}

function Escribir-ManifiestoEjecucion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Manifiesto,
        [Parameter(Mandatory = $true)][string]$RutaManifiesto
    )

    Validar-ManifiestoEjecucion -Manifiesto ([pscustomobject]$Manifiesto) | Out-Null
    $contenido = $Manifiesto | ConvertTo-Json -Depth 10
    Escribir-TextoUtf8SinBom -Ruta ([System.IO.Path]::GetFullPath($RutaManifiesto)) -Contenido $contenido
    return $Manifiesto
}

function Crear-ManifiestoEjecucion {
    <#
    .SYNOPSIS
    Crea un manifiesto de ejecucion de esquema 2 con identidad y rutas contextuales.
    .DESCRIPTION
     Recibe el contexto canonico (Cargar-Configuracion) y construye el manifiesto
     con cliente, ambiente, config, XPZ, directorios de servicios, estado y logs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Xpz,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$FullyQualifiedNames,
        [Parameter(Mandatory = $false)][string]$DirectorioBase,
        [Parameter(Mandatory = $true)]$Contexto
    )

    if ([string]::IsNullOrWhiteSpace($DirectorioBase)) {
        $DirectorioBase = Join-Path ([System.IO.Path]::GetTempPath()) 'APIGLM-ejecuciones'
    }
    $ejecucionId = Obtener-NuevoIdentificadorEjecucion
    $directorioEjecucion = Join-Path $DirectorioBase $ejecucionId
    $directorioStaging = Join-Path $directorioEjecucion 'staging'
    New-Item -ItemType Directory -Path $directorioStaging -Force | Out-Null

    $hostValor = [string]$Contexto.Host
    $baseUrlValor = [string]$Contexto.BaseUrl
    $serverUrlValor = [string]$Contexto.ServerUrl
    $manifiesto = [ordered]@{
        schemaVersion = 2
        ejecucionId = $ejecucionId
        contextId = $Contexto.ContextId
        clienteId = $Contexto.ClienteId
        ambienteId = $Contexto.AmbienteId
        configPath = [System.IO.Path]::GetFullPath($Contexto.ConfigPath)
        xpz = [System.IO.Path]::GetFullPath($Xpz)
        host = $hostValor
        baseUrl = $baseUrlValor
        serverUrl = $serverUrlValor
        servicesDirectory = [System.IO.Path]::GetFullPath($Contexto.DirectorioServicios)
        stateDirectory = [System.IO.Path]::GetFullPath($Contexto.DirectorioEstado)
        logsDirectory = [System.IO.Path]::GetFullPath($Contexto.DirectorioLogs)
        fullyQualifiedNames = @($FullyQualifiedNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        versions = @{}
        staging = [System.IO.Path]::GetFullPath($directorioStaging)
    }

    $rutaManifiesto = Join-Path $directorioEjecucion 'ejecucion.json'
    Escribir-ManifiestoEjecucion -Manifiesto $manifiesto -RutaManifiesto $rutaManifiesto | Out-Null

    return [pscustomobject]@{
        Ruta = $rutaManifiesto
        Datos = [pscustomobject]$manifiesto
    }
}

function Establecer-VersionesManifiesto {
    <#
    .SYNOPSIS
    Persiste el mapa de versiones objetivo (FQN -> version) de la ejecucion no interactiva.
    .DESCRIPTION
    Complementa el manifiesto con la version que el control de versiones asignara a
    cada servicio a regenerar, para que el generador la incruste en la fila Version
    del documento. Es opcional y no cambia el esquema del manifiesto.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaManifiesto,
        [Parameter(Mandatory = $true)][hashtable]$Versiones
    )

    $manifiesto = Leer-ManifiestoEjecucion -RutaManifiesto $RutaManifiesto
    $manifiesto | Add-Member -MemberType NoteProperty -Name 'versions' -Value $Versiones -Force
    Escribir-ManifiestoEjecucion -Manifiesto $manifiesto -RutaManifiesto $RutaManifiesto | Out-Null
    return $manifiesto
}

function Eliminar-ManifiestoEjecucion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$RutaManifiesto
    )

    if ([string]::IsNullOrWhiteSpace($RutaManifiesto)) { return }
    $rutaCompleta = [System.IO.Path]::GetFullPath($RutaManifiesto)
    $directorioEjecucion = Split-Path -Parent $rutaCompleta
    if (Test-Path -LiteralPath $directorioEjecucion -PathType Container) {
        Remove-Item -LiteralPath $directorioEjecucion -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Establecer-FullyQualifiedNamesManifiesto {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaManifiesto,
        [Parameter(Mandatory = $true)][string[]]$FullyQualifiedNames
    )

    $manifiesto = Leer-ManifiestoEjecucion -RutaManifiesto $RutaManifiesto
    $manifiesto.fullyQualifiedNames = @($FullyQualifiedNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    Escribir-ManifiestoEjecucion -Manifiesto $manifiesto -RutaManifiesto $RutaManifiesto | Out-Null
    return $manifiesto
}
