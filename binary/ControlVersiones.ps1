# ControlVersiones.ps1
# Carga, compara y persiste el control local de versiones de servicios.

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'GLMUtilidades.ps1')

function Obtener-PropiedadControlVersiones {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$Objeto,
        [Parameter(Mandatory = $true)][string]$Nombre
    )

    if ($null -eq $Objeto) { return $null }
    if ($Objeto -is [System.Collections.IDictionary] -and $Objeto.Contains($Nombre)) {
        return ,$Objeto[$Nombre]
    }
    $propiedad = $Objeto.PSObject.Properties[$Nombre]
    if ($propiedad) { return ,$propiedad.Value }
    return $null
}

function Establecer-PropiedadObjetoControl {
    <#
    .SYNOPSIS
    Establece (o reemplaza) una propiedad de un objeto del control de versiones.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Objeto,
        [Parameter(Mandatory = $true)][string]$Nombre,
        [Parameter(Mandatory = $false)]$Valor
    )

    if ($Objeto -is [System.Collections.IDictionary]) {
        $Objeto[$Nombre] = $Valor
    } else {
        $Objeto | Add-Member -MemberType NoteProperty -Name $Nombre -Value $Valor -Force
    }
}

function Convertir-DiccionarioControlVersiones {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$Objeto
    )

    $diccionario = @{}
    if ($null -eq $Objeto) { return $diccionario }
    if ($Objeto -is [hashtable]) {
        foreach ($clave in $Objeto.Keys) { $diccionario[[string]$clave] = $Objeto[$clave] }
        return $diccionario
    }
    foreach ($propiedad in $Objeto.PSObject.Properties) {
        $diccionario[$propiedad.Name] = $propiedad.Value
    }
    return $diccionario
}

function Convertir-ListaControlVersiones {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$Objeto
    )

    if ($null -eq $Objeto) { return @() }
    return @($Objeto)
}

function New-ControlVersiones {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LineageId,
        [Parameter(Mandatory = $true)][string]$SourceFingerprint,
        [Parameter(Mandatory = $true)][string]$ProfileFingerprint,
        [Parameter(Mandatory = $false)]$Objects = @{},
        [Parameter(Mandatory = $false)]$Services = @{},
        [Parameter(Mandatory = $false)]$Pendientes = @{},
        [Parameter(Mandatory = $false)][string]$XpzSha256 = ''
    )

    return [ordered]@{
        schemaVersion = 2
        lineageId = $LineageId
        sourceFingerprint = $SourceFingerprint
        profileFingerprint = $ProfileFingerprint
        xpzSha256 = $XpzSha256
        objects = Convertir-DiccionarioControlVersiones -Objeto $Objects
        services = Convertir-DiccionarioControlVersiones -Objeto $Services
        pendientes = Convertir-DiccionarioControlVersiones -Objeto $Pendientes
    }
}

function Validar-ControlVersiones {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ControlVersiones
    )

    if ($null -eq $ControlVersiones) { throw 'El control de versiones es nulo.' }
    if ([int](Obtener-PropiedadControlVersiones -Objeto $ControlVersiones -Nombre 'schemaVersion') -ne 2) {
        throw 'El control de versiones tiene un schemaVersion no soportado.'
    }

    foreach ($nombrePropiedad in @('lineageId', 'sourceFingerprint', 'profileFingerprint')) {
        $valor = [string](Obtener-PropiedadControlVersiones -Objeto $ControlVersiones -Nombre $nombrePropiedad)
        if ([string]::IsNullOrWhiteSpace($valor)) {
            throw ('El control de versiones no contiene ' + $nombrePropiedad + '.')
        }
    }

    foreach ($nombreDiccionario in @('objects', 'services', 'pendientes')) {
        $valorDiccionario = Obtener-PropiedadControlVersiones -Objeto $ControlVersiones -Nombre $nombreDiccionario
        if ($null -eq $valorDiccionario) {
            throw ('El control de versiones no contiene ' + $nombreDiccionario + '.')
        }
    }

    $servicios = Convertir-DiccionarioControlVersiones -Objeto (Obtener-PropiedadControlVersiones -Objeto $ControlVersiones -Nombre 'services')
    foreach ($claveServicio in $servicios.Keys) {
        $servicio = $servicios[$claveServicio]
        $revision = Obtener-PropiedadControlVersiones -Objeto $servicio -Nombre 'revision'
        $version = [string](Obtener-PropiedadControlVersiones -Objeto $servicio -Nombre 'version')
        $documentHash = Obtener-PropiedadControlVersiones -Objeto $servicio -Nombre 'documentHash'
        $pdfHash = Obtener-PropiedadControlVersiones -Objeto $servicio -Nombre 'pdfHash'
        $dependencias = Obtener-PropiedadControlVersiones -Objeto $servicio -Nombre 'dependencies'
        $estado = [string](Obtener-PropiedadControlVersiones -Objeto $servicio -Nombre 'status')
        if ($null -eq $revision -or [int]$revision -lt 0) {
            throw ('El servicio ' + $claveServicio + ' tiene una revision invalida.')
        }
        if ($null -eq $documentHash) {
            throw ('El servicio ' + $claveServicio + ' no contiene documentHash.')
        }
        if ($null -eq $pdfHash) {
            throw ('El servicio ' + $claveServicio + ' no contiene pdfHash.')
        }
        if ([string]::IsNullOrWhiteSpace($version) -or $version -ne ('1.' + [int]$revision)) {
            throw ('El servicio ' + $claveServicio + ' tiene una version incoherente con revision.')
        }
        if ($null -eq $dependencias) {
            throw ('El servicio ' + $claveServicio + ' no contiene dependencies.')
        }
        if ($estado -notin @('ACTIVO', 'ELIMINADO', 'OMITIDO')) {
            throw ('El servicio ' + $claveServicio + ' tiene un status no soportado: ' + $estado)
        }
    }

    return $true
}

function Leer-ControlVersiones {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaControl
    )

    if (-not (Test-Path -LiteralPath $RutaControl -PathType Leaf)) { return $null }
    try {
        $contenido = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $RutaControl).Path)
        $controlVersiones = $contenido | ConvertFrom-Json
    } catch {
        throw ('No se pudo leer el control de versiones ' + $RutaControl + '. Motivo: ' + $_.Exception.Message)
    }
    Validar-ControlVersiones -ControlVersiones $controlVersiones | Out-Null
    return $controlVersiones
}

function Obtener-DependenciasServicioControlVersiones {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$Servicio
    )

    return @(Convertir-ListaControlVersiones -Objeto (Obtener-PropiedadControlVersiones -Objeto $Servicio -Nombre 'dependencies') | ForEach-Object { [string]$_ })
}

function Agregar-ValorUnicoControlVersiones {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Valores,
        [Parameter(Mandatory = $true)][string]$Clave,
        [Parameter(Mandatory = $true)][string]$Valor
    )

    if (-not $Valores.ContainsKey($Clave)) { $Valores[$Clave] = @{} }
    $Valores[$Clave][$Valor] = $true
}

function Comparar-ControlVersiones {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$ControlAnterior,
        [Parameter(Mandatory = $true)]$ControlObjetivo
    )

    Validar-ControlVersiones -ControlVersiones $ControlObjetivo | Out-Null
    if ($ControlAnterior) { Validar-ControlVersiones -ControlVersiones $ControlAnterior | Out-Null }

    $objetosObjetivo = Convertir-DiccionarioControlVersiones -Objeto (Obtener-PropiedadControlVersiones -Objeto $ControlObjetivo -Nombre 'objects')
    $serviciosObjetivo = Convertir-DiccionarioControlVersiones -Objeto (Obtener-PropiedadControlVersiones -Objeto $ControlObjetivo -Nombre 'services')
    $pendientesAnteriores = @{}
    $objetosAnteriores = @{}
    $serviciosAnteriores = @{}
    if ($ControlAnterior) {
        $pendientesAnteriores = Convertir-DiccionarioControlVersiones -Objeto (Obtener-PropiedadControlVersiones -Objeto $ControlAnterior -Nombre 'pendientes')
        $objetosAnteriores = Convertir-DiccionarioControlVersiones -Objeto (Obtener-PropiedadControlVersiones -Objeto $ControlAnterior -Nombre 'objects')
        $serviciosAnteriores = Convertir-DiccionarioControlVersiones -Objeto (Obtener-PropiedadControlVersiones -Objeto $ControlAnterior -Nombre 'services')
    }

    $objetosModificados = New-Object System.Collections.Generic.List[string]
    $clavesObjetos = @($objetosAnteriores.Keys + $objetosObjetivo.Keys | Select-Object -Unique)
    foreach ($claveObjeto in $clavesObjetos) {
        $checksumAnterior = if ($objetosAnteriores.ContainsKey($claveObjeto)) { [string]$objetosAnteriores[$claveObjeto] } else { $null }
        $checksumObjetivo = if ($objetosObjetivo.ContainsKey($claveObjeto)) { [string]$objetosObjetivo[$claveObjeto] } else { $null }
        if ($checksumAnterior -ne $checksumObjetivo) { [void]$objetosModificados.Add($claveObjeto) }
    }

    $serviciosAfectados = @{}
    # En una inicializacion no existe una linea anterior que pueda verse
    # afectada. Evitar el producto objetos x servicios reduce drasticamente
    # el costo inicial, especialmente en ejecuciones selectivas.
    if ($ControlAnterior) {
        foreach ($claveObjeto in $objetosModificados) {
            foreach ($claveServicio in $serviciosAnteriores.Keys) {
                if ((Obtener-DependenciasServicioControlVersiones -Servicio $serviciosAnteriores[$claveServicio]) -contains $claveObjeto) {
                    Agregar-ValorUnicoControlVersiones -Valores $serviciosAfectados -Clave 'afectados' -Valor $claveServicio
                }
            }
            foreach ($claveServicio in $serviciosObjetivo.Keys) {
                if ((Obtener-DependenciasServicioControlVersiones -Servicio $serviciosObjetivo[$claveServicio]) -contains $claveObjeto) {
                    Agregar-ValorUnicoControlVersiones -Valores $serviciosAfectados -Clave 'afectados' -Valor $claveServicio
                }
            }
        }
    }

    $sourceFingerprintAnterior = if ($ControlAnterior) { [string](Obtener-PropiedadControlVersiones -Objeto $ControlAnterior -Nombre 'sourceFingerprint') } else { $null }
    $profileFingerprintAnterior = if ($ControlAnterior) { [string](Obtener-PropiedadControlVersiones -Objeto $ControlAnterior -Nombre 'profileFingerprint') } else { $null }
    $sourceFingerprintObjetivo = [string](Obtener-PropiedadControlVersiones -Objeto $ControlObjetivo -Nombre 'sourceFingerprint')
    $profileFingerprintObjetivo = [string](Obtener-PropiedadControlVersiones -Objeto $ControlObjetivo -Nombre 'profileFingerprint')
    $cambioPerfil = $null -ne $ControlAnterior -and $profileFingerprintAnterior -ne $profileFingerprintObjetivo
    if ($cambioPerfil) {
        foreach ($claveServicio in $serviciosAnteriores.Keys) {
            $estado = [string](Obtener-PropiedadControlVersiones -Objeto $serviciosAnteriores[$claveServicio] -Nombre 'status')
            if ($estado -eq 'ACTIVO') { Agregar-ValorUnicoControlVersiones -Valores $serviciosAfectados -Clave 'afectados' -Valor $claveServicio }
        }
        foreach ($claveServicio in $serviciosObjetivo.Keys) {
            $estado = [string](Obtener-PropiedadControlVersiones -Objeto $serviciosObjetivo[$claveServicio] -Nombre 'status')
            if ($estado -eq 'ACTIVO') { Agregar-ValorUnicoControlVersiones -Valores $serviciosAfectados -Clave 'afectados' -Valor $claveServicio }
        }
    }

    $serviciosNuevos = @($serviciosObjetivo.Keys | Where-Object { -not $serviciosAnteriores.ContainsKey($_) })
    $serviciosEliminados = @($serviciosAnteriores.Keys | Where-Object { -not $serviciosObjetivo.ContainsKey($_) })
    $pendientes = @($pendientesAnteriores.Keys)
    foreach ($clavePendiente in $pendientes) {
        Agregar-ValorUnicoControlVersiones -Valores $serviciosAfectados -Clave 'afectados' -Valor $clavePendiente
    }

    $lineageIdAnterior = if ($ControlAnterior) { [string](Obtener-PropiedadControlVersiones -Objeto $ControlAnterior -Nombre 'lineageId') } else { $null }
    $lineageIdObjetivo = [string](Obtener-PropiedadControlVersiones -Objeto $ControlObjetivo -Nombre 'lineageId')
    $lineageCambiado = $null -ne $ControlAnterior -and $lineageIdAnterior -ne $lineageIdObjetivo
    $esInicializacion = $null -eq $ControlAnterior
    $esFastPath = -not $esInicializacion -and -not $lineageCambiado -and
        $sourceFingerprintAnterior -eq $sourceFingerprintObjetivo -and
        $profileFingerprintAnterior -eq $profileFingerprintObjetivo -and
        $pendientes.Count -eq 0

    return [pscustomobject]@{
        EsInicializacion = $esInicializacion
        EsFastPath = $esFastPath
        LineageCambiado = $lineageCambiado
        SourceFingerprintCambio = $sourceFingerprintAnterior -ne $sourceFingerprintObjetivo
        ProfileFingerprintCambio = $cambioPerfil
        BloqueadoPorLineage = $lineageCambiado
        ObjetosModificados = $objetosModificados.ToArray()
        ServiciosAfectados = if ($serviciosAfectados.ContainsKey('afectados')) { @($serviciosAfectados.afectados.Keys) } else { @() }
        ServiciosNuevos = $serviciosNuevos
        ServiciosEliminados = $serviciosEliminados
        Pendientes = $pendientes
        MotivoBloqueo = if ($lineageCambiado) { 'El lineageId del APIGLMMain cambio. Se requiere inicializacion explicita.' } else { '' }
    }
}

function Obtener-VersionServicio {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$ServicioAnterior,
        [Parameter(Mandatory = $false)][switch]$Incrementar
    )

    if ($null -eq $ServicioAnterior) {
        return [pscustomobject]@{ Revision = 0; Version = '1.0' }
    }
    $revisionActual = [int](Obtener-PropiedadControlVersiones -Objeto $ServicioAnterior -Nombre 'revision')
    if ($Incrementar) { $revisionActual++ }
    return [pscustomobject]@{
        Revision = $revisionActual
        Version = '1.' + $revisionActual
    }
}

function Escribir-ControlVersionesAtomico {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ControlVersiones,
        [Parameter(Mandatory = $true)][string]$RutaControl
    )

    Validar-ControlVersiones -ControlVersiones $ControlVersiones | Out-Null
    $rutaCompleta = [System.IO.Path]::GetFullPath($RutaControl)
    $contenido = $ControlVersiones | ConvertTo-Json -Depth 20
    $bloqueValidar = {
        param($RutaTemporal)
        $contenidoValidado = [System.IO.File]::ReadAllText($RutaTemporal) | ConvertFrom-Json
        Validar-ControlVersiones -ControlVersiones $contenidoValidado | Out-Null
    }
    Escribir-ArchivoAtomico -Ruta $rutaCompleta -Contenido $contenido -Validar $bloqueValidar | Out-Null
    return $rutaCompleta
}
