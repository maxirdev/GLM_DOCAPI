# Contrato compartido del manifiesto de ejecucion no interactiva.

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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Manifiesto
    )

    $versionEsquema = [int]$Manifiesto.schemaVersion
    if ($versionEsquema -ne 1) {
        throw 'El manifiesto de ejecucion tiene un schemaVersion no soportado.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Manifiesto.ejecucionId)) {
        throw 'El manifiesto de ejecucion no contiene ejecucionId.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Manifiesto.xpz)) {
        throw 'El manifiesto de ejecucion no contiene xpz.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Manifiesto.staging)) {
        throw 'El manifiesto de ejecucion no contiene staging.'
    }
    if ($null -eq $Manifiesto.fullyQualifiedNames) {
        throw 'El manifiesto de ejecucion no contiene fullyQualifiedNames.'
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Xpz,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$FullyQualifiedNames,
        [Parameter(Mandatory = $false)][string]$DirectorioBase
    )

    if ([string]::IsNullOrWhiteSpace($DirectorioBase)) {
        $DirectorioBase = Join-Path ([System.IO.Path]::GetTempPath()) 'APIGLM-ejecuciones'
    }
    $ejecucionId = Obtener-NuevoIdentificadorEjecucion
    $directorioEjecucion = Join-Path $DirectorioBase $ejecucionId
    $directorioStaging = Join-Path $directorioEjecucion 'staging'
    New-Item -ItemType Directory -Path $directorioStaging -Force | Out-Null

    $manifiesto = [ordered]@{
        schemaVersion = 1
        ejecucionId = $ejecucionId
        xpz = [System.IO.Path]::GetFullPath($Xpz)
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
