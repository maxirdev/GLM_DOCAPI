# MigrarConfiguracionModulos.ps1
# Migra configuracion.json al esquema modular Comercial/ERP sin tocar artefactos.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)][string]$ConfigPath,
    [Parameter(Mandatory = $false)][switch]$Simular
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'GLMUtilidades.ps1')

$RaizRepositorio = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $RaizRepositorio 'configuracion.json'
}
$ConfigPath = Resolver-RutaRepositorio -Ruta $ConfigPath -Raiz $RaizRepositorio

function Obtener-PropiedadConfiguracion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Objeto,
        [Parameter(Mandatory = $true)][string]$Nombre
    )
    if ($null -eq $Objeto) { return $null }
    $propiedad = @($Objeto.PSObject.Properties | Where-Object { $_.Name -ceq $Nombre }) | Select-Object -First 1
    if ($null -eq $propiedad) { return $null }
    return $propiedad.Value
}

function Test-TienePropiedadConfiguracion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Objeto,
        [Parameter(Mandatory = $true)][string]$Nombre
    )
    if ($null -eq $Objeto) { return $false }
    return @($Objeto.PSObject.Properties | Where-Object { $_.Name -ceq $Nombre }).Count -gt 0
}

function Obtener-TextoConfiguracion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$Valor
    )
    if ($null -eq $Valor) { return '' }
    return ([string]$Valor).Trim()
}

function Obtener-ModuloCanonico {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$Valor,
        [Parameter(Mandatory = $true)][string]$Contexto
    )
    $modulo = Obtener-TextoConfiguracion -Valor $Valor
    if ([string]::IsNullOrWhiteSpace($modulo)) { return 'comercial' }
    $modulo = $modulo.ToLowerInvariant()
    if ($modulo -notin @('comercial', 'erp')) {
        throw ("$Contexto define un modulo invalido '$modulo'. Use comercial o erp.")
    }
    return $modulo
}

function Obtener-TipoCanonico {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Valor,
        [Parameter(Mandatory = $true)][string]$Contexto
    )
    $tipo = Obtener-TextoConfiguracion -Valor $Valor
    $tipo = $tipo.ToLowerInvariant()
    if ($tipo -notin @('test', 'prod')) {
        throw ("$Contexto define un tipo invalido '$tipo'. Use test o prod.")
    }
    return $tipo
}

function Test-IdCanonico {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Valor
    )
    return $Valor -cmatch '^[a-z0-9][a-z0-9-]*$'
}

function Convertir-PackageNamesCanonicos {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Cliente,
        [Parameter(Mandatory = $true)][string]$ClienteId
    )

    $packageNames = [ordered]@{}
    $packageNamesOriginales = Obtener-PropiedadConfiguracion -Objeto $Cliente -Nombre 'packagenames'
    if (Test-TienePropiedadConfiguracion -Objeto $Cliente -Nombre 'packagenames') {
        if ($null -eq $packageNamesOriginales -or $packageNamesOriginales -is [System.Array]) {
            throw ("El cliente '$ClienteId' define packagenames con un formato invalido.")
        }
        $modulosVistos = @{}
        foreach ($propiedadPackageName in @($packageNamesOriginales.PSObject.Properties)) {
            $modulo = ([string]$propiedadPackageName.Name).Trim().ToLowerInvariant()
            if ($modulo -notin @('comercial', 'erp')) {
                throw ("El cliente '$ClienteId' define un modulo de package name invalido '$modulo'.")
            }
            if ($modulosVistos.ContainsKey($modulo)) {
                throw ("El cliente '$ClienteId' define dos package names para el modulo '$modulo'.")
            }
            $modulosVistos[$modulo] = $true
            $packageName = Obtener-TextoConfiguracion -Valor $propiedadPackageName.Value
            if ([string]::IsNullOrWhiteSpace($packageName)) {
                throw ("El package name del modulo '$modulo' del cliente '$ClienteId' no puede estar vacio.")
            }
            $packageNames[$modulo] = $packageName
        }
    }

    if (Test-TienePropiedadConfiguracion -Objeto $Cliente -Nombre 'packagename') {
        $packageNameHeredado = Obtener-TextoConfiguracion -Valor (Obtener-PropiedadConfiguracion -Objeto $Cliente -Nombre 'packagename')
        if (-not [string]::IsNullOrWhiteSpace($packageNameHeredado)) {
            if ($packageNames.Contains('comercial') -and $packageNames['comercial'] -ne $packageNameHeredado) {
                throw ("El cliente '$ClienteId' define valores contradictorios para packagename y packagenames.comercial.")
            }
            if (-not $packageNames.Contains('comercial')) {
                $packageNames['comercial'] = $packageNameHeredado
            }
        }
    }
    return $packageNames
}

function Convertir-AmbienteModular {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Ambiente,
        [Parameter(Mandatory = $true)][string]$ClienteId,
        [Parameter(Mandatory = $true)][int]$NumeroAmbiente
    )

    $ambienteId = Obtener-TextoConfiguracion -Valor (Obtener-PropiedadConfiguracion -Objeto $Ambiente -Nombre 'id')
    $contextoAmbiente = "El ambiente numero $NumeroAmbiente del cliente '$ClienteId'"
    if (-not (Test-IdCanonico -Valor $ambienteId)) {
        throw ("$contextoAmbiente tiene un id invalido '$ambienteId'.")
    }
    $nombreAmbiente = Obtener-TextoConfiguracion -Valor (Obtener-PropiedadConfiguracion -Objeto $Ambiente -Nombre 'nombre')
    if ([string]::IsNullOrWhiteSpace($nombreAmbiente)) {
        throw ("$contextoAmbiente no define nombre.")
    }
    $kbPath = Obtener-TextoConfiguracion -Valor (Obtener-PropiedadConfiguracion -Objeto $Ambiente -Nombre 'kbPath')
    if ([string]::IsNullOrWhiteSpace($kbPath)) {
        throw ("$contextoAmbiente no define kbPath.")
    }

    $moduloDeclarado = Obtener-PropiedadConfiguracion -Objeto $Ambiente -Nombre 'modulo'
    if ((Test-TienePropiedadConfiguracion -Objeto $Ambiente -Nombre 'modulo') -and [string]::IsNullOrWhiteSpace([string]$moduloDeclarado)) {
        throw ("$contextoAmbiente define un modulo vacio.")
    }
    $modulo = Obtener-ModuloCanonico -Valor $moduloDeclarado -Contexto $contextoAmbiente
    $tipo = Obtener-TipoCanonico -Valor (Obtener-PropiedadConfiguracion -Objeto $Ambiente -Nombre 'tipo') -Contexto $contextoAmbiente
    $ambienteCanonico = [ordered]@{}
    foreach ($propiedadAmbiente in @($Ambiente.PSObject.Properties)) {
        if ($propiedadAmbiente.Name -in @('modulo', 'tipo', 'baseurl', 'baseUrl')) { continue }
        $ambienteCanonico[$propiedadAmbiente.Name] = $propiedadAmbiente.Value
    }
    $ambienteCanonico['modulo'] = $modulo
    $ambienteCanonico['tipo'] = $tipo

    $tieneBaseUrl = Test-TienePropiedadConfiguracion -Objeto $Ambiente -Nombre 'baseUrl'
    $tieneBaseUrlHeredado = Test-TienePropiedadConfiguracion -Objeto $Ambiente -Nombre 'baseurl'
    $baseUrl = Obtener-TextoConfiguracion -Valor (Obtener-PropiedadConfiguracion -Objeto $Ambiente -Nombre 'baseUrl')
    $baseUrlHeredado = Obtener-TextoConfiguracion -Valor (Obtener-PropiedadConfiguracion -Objeto $Ambiente -Nombre 'baseurl')
    if ($tieneBaseUrl -and $tieneBaseUrlHeredado -and -not [string]::IsNullOrWhiteSpace($baseUrl) -and -not [string]::IsNullOrWhiteSpace($baseUrlHeredado) -and $baseUrl -ne $baseUrlHeredado) {
        throw ("$contextoAmbiente define valores contradictorios para baseUrl y baseurl.")
    }
    if ($tieneBaseUrl) {
        $ambienteCanonico['baseUrl'] = $baseUrl
    } elseif ($tieneBaseUrlHeredado) {
        $ambienteCanonico['baseUrl'] = $baseUrlHeredado
    }
    return [pscustomobject]@{
        Ambiente = [pscustomobject]$ambienteCanonico
        Id = $ambienteId
        Modulo = $modulo
        Tipo = $tipo
    }
}

function Convertir-ClienteModular {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Cliente,
        [Parameter(Mandatory = $true)][int]$NumeroCliente
    )

    $clienteId = Obtener-TextoConfiguracion -Valor (Obtener-PropiedadConfiguracion -Objeto $Cliente -Nombre 'id')
    if (-not (Test-IdCanonico -Valor $clienteId)) {
        throw ("El cliente numero $NumeroCliente tiene un id invalido '$clienteId'.")
    }
    $nombreCliente = Obtener-TextoConfiguracion -Valor (Obtener-PropiedadConfiguracion -Objeto $Cliente -Nombre 'nombre')
    if ([string]::IsNullOrWhiteSpace($nombreCliente)) {
        throw ("El cliente '$clienteId' no define nombre.")
    }
    $ambientesOriginales = Obtener-PropiedadConfiguracion -Objeto $Cliente -Nombre 'ambientes'
    if ($null -eq $ambientesOriginales -or @($ambientesOriginales).Count -eq 0) {
        throw ("El cliente '$clienteId' no define ambientes.")
    }
    if (@($ambientesOriginales).Count -gt 4) {
        throw ("El cliente '$clienteId' no puede tener mas de cuatro ambientes.")
    }

    $ambientesCanonicos = New-Object System.Collections.Generic.List[object]
    $combinacionesVistas = @{}
    $idsPorModulo = @{}
    $numeroAmbiente = 0
    foreach ($ambienteOriginal in @($ambientesOriginales)) {
        $numeroAmbiente++
        $ambienteConvertido = Convertir-AmbienteModular -Ambiente $ambienteOriginal -ClienteId $clienteId -NumeroAmbiente $numeroAmbiente
        $claveCombinacion = $ambienteConvertido.Modulo + '|' + $ambienteConvertido.Tipo
        if ($combinacionesVistas.ContainsKey($claveCombinacion)) {
            throw ("El cliente '$clienteId' define mas de un ambiente para la combinacion $($ambienteConvertido.Modulo)/$($ambienteConvertido.Tipo).")
        }
        $combinacionesVistas[$claveCombinacion] = $true
        if (-not $idsPorModulo.ContainsKey($ambienteConvertido.Modulo)) {
            $idsPorModulo[$ambienteConvertido.Modulo] = @{}
        }
        $claveId = $ambienteConvertido.Id.ToLowerInvariant()
        if ($idsPorModulo[$ambienteConvertido.Modulo].ContainsKey($claveId)) {
            throw ("El id de ambiente '$($ambienteConvertido.Id)' del modulo '$($ambienteConvertido.Modulo)' del cliente '$clienteId' esta duplicado.")
        }
        $idsPorModulo[$ambienteConvertido.Modulo][$claveId] = $true
        [void]$ambientesCanonicos.Add($ambienteConvertido.Ambiente)
    }

    $packageNames = Convertir-PackageNamesCanonicos -Cliente $Cliente -ClienteId $clienteId
    $modulosConfigurados = @($ambientesCanonicos | ForEach-Object { [string]$_.modulo } | Select-Object -Unique)
    foreach ($moduloConfigurado in $modulosConfigurados) {
        if (-not $packageNames.Contains($moduloConfigurado) -or [string]::IsNullOrWhiteSpace([string]$packageNames[$moduloConfigurado])) {
            throw ("El cliente '$clienteId' tiene ambientes del modulo '$moduloConfigurado' pero no define packagenames.$moduloConfigurado.")
        }
    }

    $clienteCanonico = [ordered]@{}
    foreach ($propiedadCliente in @($Cliente.PSObject.Properties)) {
        if ($propiedadCliente.Name -in @('packagename', 'packagenames', 'ambientes')) { continue }
        $clienteCanonico[$propiedadCliente.Name] = $propiedadCliente.Value
    }
    $clienteCanonico['packagenames'] = $packageNames
    $clienteCanonico['ambientes'] = @($ambientesCanonicos.ToArray())
    return [pscustomobject]@{
        Cliente = [pscustomobject]$clienteCanonico
        Id = $clienteId
    }
}

function Convertir-ConfiguracionModular {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ConfiguracionRaw
    )

    $clientesOriginales = Obtener-PropiedadConfiguracion -Objeto $ConfiguracionRaw -Nombre 'clientes'
    if ($null -eq $clientesOriginales -or @($clientesOriginales).Count -eq 0) {
        throw 'La configuracion no define la coleccion clientes.'
    }
    $clientesVistos = @{}
    $clientesCanonicos = New-Object System.Collections.Generic.List[object]
    $numeroCliente = 0
    foreach ($clienteOriginal in @($clientesOriginales)) {
        $numeroCliente++
        $clienteConvertido = Convertir-ClienteModular -Cliente $clienteOriginal -NumeroCliente $numeroCliente
        $claveCliente = $clienteConvertido.Id.ToLowerInvariant()
        if ($clientesVistos.ContainsKey($claveCliente)) {
            throw ("El id de cliente '$($clienteConvertido.Id)' esta duplicado.")
        }
        $clientesVistos[$claveCliente] = $true
        [void]$clientesCanonicos.Add($clienteConvertido.Cliente)
    }

    $configuracionCanonica = [ordered]@{}
    foreach ($propiedadConfiguracion in @($ConfiguracionRaw.PSObject.Properties)) {
        if ($propiedadConfiguracion.Name -eq 'clientes') { continue }
        $configuracionCanonica[$propiedadConfiguracion.Name] = $propiedadConfiguracion.Value
    }
    $configuracionCanonica['clientes'] = @($clientesCanonicos.ToArray())
    return [pscustomobject]$configuracionCanonica
}

function Validar-ConfiguracionMigradaEnArchivo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Ruta
    )
    $contenido = [System.IO.File]::ReadAllText($Ruta)
    $configuracion = $contenido | ConvertFrom-Json
    if ($null -eq $configuracion -or $null -eq (Obtener-PropiedadConfiguracion -Objeto $configuracion -Nombre 'clientes')) {
        throw 'La configuracion migrada no contiene clientes.'
    }
    return $true
}

$contenidoOriginal = $null
$intentoEscritura = $false
try {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw ("No se encontro el archivo de configuracion: $ConfigPath")
    }
    $contenidoOriginal = [System.IO.File]::ReadAllText($ConfigPath)
    $configuracionOriginal = $contenidoOriginal | ConvertFrom-Json
    $configuracionMigrada = Convertir-ConfiguracionModular -ConfiguracionRaw $configuracionOriginal
    $contenidoMigrado = Normalizar-SaltosLineaLf -Texto ($configuracionMigrada | ConvertTo-Json -Depth 30)

    if ($Simular) {
        Write-Output ("Simulacion completada. No se modifico: " + $ConfigPath)
        exit 0
    }

    $intentoEscritura = $true
    $validarCandidato = {
        param($rutaTemporal)
        Validar-ConfiguracionMigradaEnArchivo -Ruta $rutaTemporal | Out-Null
    }
    Escribir-ArchivoAtomico -Ruta $ConfigPath -Contenido $contenidoMigrado -Validar $validarCandidato | Out-Null
    Validar-ConfiguracionMigradaEnArchivo -Ruta $ConfigPath | Out-Null
    $intentoEscritura = $false
    Write-Output ("Migracion completada: " + $ConfigPath)
    exit 0
} catch {
    $mensajeError = $_.Exception.Message
    if ($intentoEscritura -and $null -ne $contenidoOriginal) {
        try {
            Escribir-ArchivoAtomico -Ruta $ConfigPath -Contenido $contenidoOriginal | Out-Null
        } catch {
            $mensajeError = $mensajeError + ' No se pudo restaurar la configuracion anterior: ' + $_.Exception.Message
        }
    }
    Write-Error ('Migracion rechazada: ' + $mensajeError) -ErrorAction Continue
    exit 1
}
