# CargarConfiguracion.ps1
# Modulo de carga de configuracion centralizada para el pipeline APIGLM.
# Se importa por dot-source desde los scripts que necesiten la configuracion.
# Resuelve las rutas relativas contra el directorio raiz del repositorio.
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'GLMUtilidades.ps1')

function Test-NombreSlugValido {
    <#
    .SYNOPSIS
    Comprueba que un id sigue la convencion de slug en minusculas.
    .DESCRIPTION
    Acepta solo minusculas, digitos y guiones, comenzando con una letra
    minuscula o un digito: ^[a-z0-9][a-z0-9-]*$. Los ids seguros forman
    nombres de carpeta, por eso no admiten mayusculas ni caracteres especiales.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$Valor
    )
    return ($Valor -cmatch '^[a-z0-9][a-z0-9-]*$')
}

function Clasificar-TipoAmbiente {
    <#
    .SYNOPSIS
    Normaliza el tipo de ambiente declarado en configuracion.json.
    .DESCRIPTION
    Acepta unicamente test y prod (sin distinguir mayusculas, con espacios
    recortados) y devuelve el valor canonico en minusculas. Cualquier otro
    valor devuelve nulo para que el validador lo rechace con un mensaje claro.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$Tipo
    )
    $normalizado = ([string]$Tipo).Trim().ToLowerInvariant()
    if ($normalizado -in @('test', 'prod')) { return $normalizado }
    return $null
}

function Obtener-PropiedadConfiguracionExacta {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Objeto,
        [Parameter(Mandatory = $true)][string]$Nombre
    )
    if ($null -eq $Objeto) { return $null }
    return @($Objeto.PSObject.Properties | Where-Object { $_.Name -ceq $Nombre }) | Select-Object -First 1
}

function Test-TienePropiedadConfiguracionExacta {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Objeto,
        [Parameter(Mandatory = $true)][string]$Nombre
    )
    if ($null -eq $Objeto) { return $false }
    return @($Objeto.PSObject.Properties | Where-Object { $_.Name -ceq $Nombre }).Count -gt 0
}

function Obtener-ModuloAmbienteConfigurado {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Ambiente,
        [Parameter(Mandatory = $true)][string]$Contexto
    )
    $propiedadModulo = Obtener-PropiedadConfiguracionExacta -Objeto $Ambiente -Nombre 'modulo'
    if ($null -eq $propiedadModulo) { return 'comercial' }
    $modulo = ([string]$propiedadModulo.Value).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($modulo) -or $modulo -notin @('comercial', 'erp')) {
        throw ($Contexto + " define un modulo invalido. Use comercial o erp.")
    }
    return $modulo
}

function Obtener-NombreModuloCanonico {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('comercial', 'erp')][string]$Modulo
    )
    if ($Modulo -eq 'erp') { return 'ERP' }
    return 'Comercial'
}

function Obtener-BaseUrlAmbienteConfigurado {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Ambiente,
        [Parameter(Mandatory = $true)][string]$Contexto
    )
    $propiedadBaseUrl = Obtener-PropiedadConfiguracionExacta -Objeto $Ambiente -Nombre 'baseUrl'
    $propiedadBaseUrlHeredada = Obtener-PropiedadConfiguracionExacta -Objeto $Ambiente -Nombre 'baseurl'
    $baseUrl = if ($null -ne $propiedadBaseUrl) { ([string]$propiedadBaseUrl.Value).Trim() } else { '' }
    $baseUrlHeredada = if ($null -ne $propiedadBaseUrlHeredada) { ([string]$propiedadBaseUrlHeredada.Value).Trim() } else { '' }
    if ($null -ne $propiedadBaseUrl -and $null -ne $propiedadBaseUrlHeredada -and -not [string]::IsNullOrWhiteSpace($baseUrl) -and -not [string]::IsNullOrWhiteSpace($baseUrlHeredada) -and $baseUrl -ne $baseUrlHeredada) {
        throw ($Contexto + ' define valores contradictorios para baseUrl y baseurl.')
    }
    if ($null -ne $propiedadBaseUrl) { return $baseUrl }
    if ($null -ne $propiedadBaseUrlHeredada) { return $baseUrlHeredada }
    return $null
}

function Obtener-PackageNamesCliente {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Cliente,
        [Parameter(Mandatory = $true)][string]$ClienteId
    )
    $packageNames = @{}
    $propiedadPackageNames = Obtener-PropiedadConfiguracionExacta -Objeto $Cliente -Nombre 'packagenames'
    if ($null -ne $propiedadPackageNames) {
        if ($null -eq $propiedadPackageNames.Value -or $propiedadPackageNames.Value -is [System.Array]) {
            throw ("El cliente '$ClienteId' define packagenames con un formato invalido.")
        }
        $modulosVistos = @{}
        foreach ($propiedadModulo in @($propiedadPackageNames.Value.PSObject.Properties)) {
            $modulo = ([string]$propiedadModulo.Name).Trim().ToLowerInvariant()
            if ($modulo -notin @('comercial', 'erp')) {
                throw ("El cliente '$ClienteId' define un modulo invalido en packagenames: '$modulo'.")
            }
            if ($modulosVistos.ContainsKey($modulo)) {
                throw ("El cliente '$ClienteId' define packagenames duplicados para el modulo '$modulo'.")
            }
            $modulosVistos[$modulo] = $true
            $packageName = ([string]$propiedadModulo.Value).Trim()
            if ([string]::IsNullOrWhiteSpace($packageName)) {
                throw ("El package name del modulo '$modulo' del cliente '$ClienteId' no puede estar vacio.")
            }
            $packageNames[$modulo] = $packageName
        }
    }

    $propiedadPackageNameHeredado = Obtener-PropiedadConfiguracionExacta -Objeto $Cliente -Nombre 'packagename'
    if ($null -ne $propiedadPackageNameHeredado) {
        $packageNameHeredado = ([string]$propiedadPackageNameHeredado.Value).Trim()
        if (-not [string]::IsNullOrWhiteSpace($packageNameHeredado)) {
            if ($packageNames.ContainsKey('comercial') -and $packageNames['comercial'] -ne $packageNameHeredado) {
                throw ("El cliente '$ClienteId' define valores contradictorios para packagename y packagenames.comercial.")
            }
            if (-not $packageNames.ContainsKey('comercial')) {
                $packageNames['comercial'] = $packageNameHeredado
            }
        }
    }
    return $packageNames
}

function Validar-HostAmbiente {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$HostUrl,
        [Parameter(Mandatory = $false)][string]$Contexto = 'El host del ambiente'
    )
    $valor = ([string]$HostUrl).Trim()
    $uri = $null
    if ([string]::IsNullOrWhiteSpace($valor) -or -not [System.Uri]::TryCreate($valor, [System.UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http', 'https') -or [string]::IsNullOrWhiteSpace($uri.Host) -or -not [string]::IsNullOrWhiteSpace($uri.UserInfo) -or -not [string]::IsNullOrWhiteSpace($uri.Query) -or -not [string]::IsNullOrWhiteSpace($uri.Fragment) -or $uri.AbsolutePath -ne '/') {
        throw ($Contexto + ' debe ser un origen absoluto http o https sin credenciales, query, fragmento ni path adicional.')
    }
    return $valor.TrimEnd('/')
}

function Validar-BaseUrlAmbiente {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $false)][string]$Contexto = 'El baseUrl del ambiente'
    )
    $valor = ([string]$BaseUrl).Trim()
    if ([string]::IsNullOrWhiteSpace($valor) -or -not $valor.StartsWith('/') -or $valor -match '[?#]' -or $valor -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        throw ($Contexto + " debe ser una ruta que comience con '/'; no puede contener query, fragmento ni host.")
    }
    return $valor
}

function Obtener-IdAmbienteCanonico {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('test', 'prod')][string]$Tipo
    )
    if ($Tipo -eq 'prod') { return 'produccion' }
    return 'testing'
}

function Obtener-NombreAmbienteCanonico {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('test', 'prod')][string]$Tipo
    )
    if ($Tipo -eq 'prod') { return 'PROD' }
    return 'TEST'
}

function Validar-RutaKnowledgeBase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Ruta,
        [Parameter(Mandatory = $false)][string]$Contexto = 'La Knowledge Base'
    )
    if (-not (Test-Path -LiteralPath $Ruta -PathType Container)) {
        throw ($Contexto + ' no existe: ' + $Ruta)
    }
    if (@(Get-ChildItem -LiteralPath $Ruta -Filter '*.gxw' -File -ErrorAction SilentlyContinue).Count -eq 0) {
        throw ($Contexto + ' debe contener al menos un archivo .gxw: ' + $Ruta)
    }
    return $true
}

function Validar-ConfiguracionMulticliente {
    <#
    .SYNOPSIS
    Valida el esquema multicliente de configuracion.json.
    .DESCRIPTION
    Comprueba rutas.clientesRoot, herramientas globales y la coleccion clientes
    con sus ambientes. Exige ids en formato slug, unicos sin distinguir
    mayusculas en cada nivel, y rechaza dos ambientes que resuelvan a la misma
    ruta de Knowledge Base una vez normalizada. Lanza con el primer error y
    devuelve la configuracion cruda si es valida.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ConfiguracionRaw,
        [Parameter(Mandatory = $true)][string]$RaizRepositorio,
        [Parameter(Mandatory = $false)][string]$ConfigPath,
        [Parameter(Mandatory = $false)][switch]$ValidarContenidoKnowledgeBase
    )

    if ($null -eq $ConfiguracionRaw.rutas -or [string]::IsNullOrWhiteSpace([string]$ConfiguracionRaw.rutas.clientesRoot)) {
        throw 'La configuracion no define rutas.clientesRoot.'
    }
    if ($null -eq $ConfiguracionRaw.herramientas) {
        throw 'La configuracion no define la seccion herramientas.'
    }
    foreach ($propiedadHerramienta in @('geneXusProgramDir', 'msbuildPath', 'pandocPath', 'typstPath')) {
        if ([string]::IsNullOrWhiteSpace([string]$ConfiguracionRaw.herramientas.($propiedadHerramienta))) {
            throw ("La configuracion no define herramientas." + $propiedadHerramienta + ".")
        }
    }
    $perfilExportacion = 'GX18'
    $propiedadPerfil = Obtener-PropiedadConfiguracionExacta -Objeto $ConfiguracionRaw.herramientas -Nombre 'geneXusExportProfile'
    if ($null -ne $propiedadPerfil -and -not [string]::IsNullOrWhiteSpace([string]$propiedadPerfil.Value)) {
        $perfilExportacion = [string]$propiedadPerfil.Value
    }
    if ($perfilExportacion -notin @('GX18', 'Evo3')) {
        throw "El perfil de exportacion '$perfilExportacion' no es valido. Use GX18 o Evo3."
    }
    if ($null -eq $ConfiguracionRaw.clientes -or @($ConfiguracionRaw.clientes).Count -eq 0) {
        throw 'La configuracion no define la coleccion clientes.'
    }

    $clientesVistos = @{}
    $kbPathsVistos = @{}
    foreach ($cliente in @($ConfiguracionRaw.clientes)) {
        $clienteId = [string]$cliente.id
        if (-not (Test-NombreSlugValido -Valor $clienteId)) {
            throw ("El id de cliente '" + $clienteId + "' no es valido. Use minusculas, digitos y guiones con el formato ^[a-z0-9][a-z0-9-]*$.")
        }
        if ([string]::IsNullOrWhiteSpace([string]$cliente.nombre)) {
            throw ("El cliente '" + $clienteId + "' no define su nombre visible.")
        }
        $claveCliente = $clienteId.ToLowerInvariant()
        if ($clientesVistos.ContainsKey($claveCliente)) {
            throw ("El id de cliente '" + $clienteId + "' esta duplicado (sin distinguir mayusculas de minusculas).")
        }
        $clientesVistos[$claveCliente] = $true

        $packageNames = Obtener-PackageNamesCliente -Cliente $cliente -ClienteId $clienteId
        if ($null -eq $cliente.ambientes -or @($cliente.ambientes).Count -eq 0) {
            throw ("El cliente '" + $clienteId + "' no define ambientes.")
        }
        if (@($cliente.ambientes).Count -gt 4) {
            throw ("El cliente '" + $clienteId + "' no puede tener mas de cuatro ambientes (Comercial/ERP TEST/PROD).")
        }
        $ambientesVistosPorModulo = @{}
        $combinacionesVistas = @{}
        foreach ($ambiente in @($cliente.ambientes)) {
            $ambienteId = [string]$ambiente.id
            $contextoAmbiente = "El ambiente '$ambienteId' del cliente '$clienteId'"
            if (-not (Test-NombreSlugValido -Valor $ambienteId)) {
                throw ("$contextoAmbiente no es valido. Use minusculas, digitos y guiones con el formato ^[a-z0-9][a-z0-9-]*$.")
            }
            if ([string]::IsNullOrWhiteSpace([string]$ambiente.nombre)) {
                throw ("$contextoAmbiente no define su nombre visible.")
            }
            if ([string]::IsNullOrWhiteSpace([string]$ambiente.kbPath)) {
                throw ("$contextoAmbiente no define kbPath.")
            }
            $moduloAmbiente = Obtener-ModuloAmbienteConfigurado -Ambiente $ambiente -Contexto $contextoAmbiente
            $tipoAmbiente = Clasificar-TipoAmbiente -Tipo ([string]$ambiente.tipo)
            if ($null -eq $tipoAmbiente) {
                throw ("$contextoAmbiente no define un tipo valido (test o prod).")
            }
            if (-not $packageNames.ContainsKey($moduloAmbiente) -or [string]::IsNullOrWhiteSpace([string]$packageNames[$moduloAmbiente])) {
                throw ("El cliente '$clienteId' tiene ambientes del modulo '$moduloAmbiente' pero no define un package name para ese modulo.")
            }

            $propiedadHost = Obtener-PropiedadConfiguracionExacta -Objeto $ambiente -Nombre 'host'
            if ($null -ne $propiedadHost -and -not [string]::IsNullOrWhiteSpace([string]$propiedadHost.Value)) {
                Validar-HostAmbiente -HostUrl ([string]$propiedadHost.Value) -Contexto ("El host del ambiente '$ambienteId'") | Out-Null
            }
            $baseUrlAmbiente = Obtener-BaseUrlAmbienteConfigurado -Ambiente $ambiente -Contexto $contextoAmbiente
            if (-not [string]::IsNullOrWhiteSpace($baseUrlAmbiente)) {
                Validar-BaseUrlAmbiente -BaseUrl $baseUrlAmbiente -Contexto ("El baseUrl del ambiente '$ambienteId'") | Out-Null
            }

            if (-not $ambientesVistosPorModulo.ContainsKey($moduloAmbiente)) {
                $ambientesVistosPorModulo[$moduloAmbiente] = @{}
            }
            $claveAmbiente = $ambienteId.ToLowerInvariant()
            if ($ambientesVistosPorModulo[$moduloAmbiente].ContainsKey($claveAmbiente)) {
                throw ("El id de ambiente '$ambienteId' del modulo '$moduloAmbiente' del cliente '$clienteId' esta duplicado (sin distinguir mayusculas de minusculas).")
            }
            $ambientesVistosPorModulo[$moduloAmbiente][$claveAmbiente] = $true

            $claveCombinacion = $moduloAmbiente + '|' + $tipoAmbiente
            if ($combinacionesVistas.ContainsKey($claveCombinacion)) {
                throw ("El cliente '$clienteId' no puede tener mas de un ambiente para la combinacion $moduloAmbiente/$tipoAmbiente.")
            }
            $combinacionesVistas[$claveCombinacion] = $true

            $kbPathResuelto = Resolver-RutaRepositorio -Ruta ([string]$ambiente.kbPath) -Raiz $RaizRepositorio
            if ($ValidarContenidoKnowledgeBase) {
                Validar-RutaKnowledgeBase -Ruta $kbPathResuelto -Contexto ("La Knowledge Base del ambiente '$ambienteId' del cliente '$clienteId'") | Out-Null
            }
            $claveKb = $kbPathResuelto.ToLowerInvariant()
            if ($kbPathsVistos.ContainsKey($claveKb)) {
                throw ("Dos ambientes apuntan a la misma ruta de Knowledge Base: " + $kbPathResuelto)
            }
            $kbPathsVistos[$claveKb] = $true
        }
    }
    return $ConfiguracionRaw
}

function Obtener-ClientesConfigurados {
    <#
    .SYNOPSIS
    Devuelve los clientes configurados para el selector interactivo.
    .DESCRIPTION
    Devuelve un array de objetos con Id y Nombre visible, en el orden declarado
    en configuracion.json.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ConfiguracionRaw
    )
    $resultado = New-Object System.Collections.Generic.List[object]
    foreach ($cliente in @($ConfiguracionRaw.clientes)) {
        $resultado.Add([pscustomobject]@{
            Id = [string]$cliente.id
            Nombre = [string]$cliente.nombre
        })
    }
    return $resultado.ToArray()
}

function Obtener-AmbientesConfigurados {
    <#
    .SYNOPSIS
    Devuelve los ambientes de un cliente para el selector interactivo.
    .DESCRIPTION
    Devuelve ambientes con modulo, tipo e identidad logica. Si se indica modulo,
    filtra la coleccion plana del cliente por ese modulo. Si el cliente no existe,
    devuelve una coleccion vacia.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ConfiguracionRaw,
        [Parameter(Mandatory = $true)][string]$ClienteId,
        [Parameter(Mandatory = $false)][string]$Modulo
    )
    $cliente = @($ConfiguracionRaw.clientes | Where-Object { [string]$_.id -ieq $ClienteId }) | Select-Object -First 1
    if ($null -eq $cliente) {
        return @()
    }
    $resultado = New-Object System.Collections.Generic.List[object]
    foreach ($ambiente in @($cliente.ambientes)) {
        $moduloAmbiente = Obtener-ModuloAmbienteConfigurado -Ambiente $ambiente -Contexto ("El ambiente '" + [string]$ambiente.id + "' del cliente '" + $ClienteId + "'")
        if (-not [string]::IsNullOrWhiteSpace($Modulo) -and $moduloAmbiente -ine $Modulo) { continue }
        $tipoAmbiente = Clasificar-TipoAmbiente -Tipo ([string]$ambiente.tipo)
        $resultado.Add([pscustomobject]@{
            Id = [string]$ambiente.id
            Nombre = [string]$ambiente.nombre
            Modulo = $moduloAmbiente
            ModuloNombre = Obtener-NombreModuloCanonico -Modulo $moduloAmbiente
            Tipo = $tipoAmbiente
            TipoNombre = Obtener-NombreAmbienteCanonico -Tipo $tipoAmbiente
        })
    }
    return $resultado.ToArray()
}

function Obtener-ModulosConfigurados {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ConfiguracionRaw,
        [Parameter(Mandatory = $true)][string]$ClienteId
    )
    $cliente = @($ConfiguracionRaw.clientes | Where-Object { [string]$_.id -ieq $ClienteId }) | Select-Object -First 1
    if ($null -eq $cliente) { return @() }
    $modulosVistos = @{}
    $resultado = New-Object System.Collections.Generic.List[object]
    foreach ($ambiente in @($cliente.ambientes)) {
        $moduloAmbiente = Obtener-ModuloAmbienteConfigurado -Ambiente $ambiente -Contexto ("El ambiente '" + [string]$ambiente.id + "' del cliente '" + $ClienteId + "'")
        if ($modulosVistos.ContainsKey($moduloAmbiente)) { continue }
        $modulosVistos[$moduloAmbiente] = $true
        $resultado.Add([pscustomobject]@{
            Id = $moduloAmbiente
            Nombre = Obtener-NombreModuloCanonico -Modulo $moduloAmbiente
        })
    }
    return $resultado.ToArray()
}

function Resolver-ContextoConfiguracion {
    <#
    .SYNOPSIS
    Construye el contexto canonico de cliente y ambiente.
    .DESCRIPTION
    Valida el esquema, localiza el cliente y el ambiente, resuelve clientesRoot
    contra la raiz del repositorio y deriva las rutas contextuales de documentos,
    estado, XPZ, logs y datos de prueba. Devuelve el objeto unico con las
    propiedades canonicas de la SPEC 19. Todas las rutas son absolutas.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ConfiguracionRaw,
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$RaizRepositorio,
        [Parameter(Mandatory = $true)][string]$ClienteId,
        [Parameter(Mandatory = $true)][string]$AmbienteId,
        [Parameter(Mandatory = $false)][string]$Modulo
    )

    Validar-ConfiguracionMulticliente -ConfiguracionRaw $ConfiguracionRaw -RaizRepositorio $RaizRepositorio -ConfigPath $ConfigPath | Out-Null

    $cliente = @($ConfiguracionRaw.clientes | Where-Object { [string]$_.id -ieq $ClienteId }) | Select-Object -First 1
    if ($null -eq $cliente) {
        $clientesDisponibles = ((@($ConfiguracionRaw.clientes) | ForEach-Object { [string]$_.id }) -join ', ')
        throw ("El cliente '" + $ClienteId + "' no existe en la configuracion. Clientes configurados: " + $clientesDisponibles + ".")
    }
    $ambientesCoincidentes = @($cliente.ambientes | Where-Object { [string]$_.id -ieq $AmbienteId })
    if (-not [string]::IsNullOrWhiteSpace($Modulo)) {
        $moduloSolicitado = $Modulo.Trim().ToLowerInvariant()
        if ($moduloSolicitado -notin @('comercial', 'erp')) {
            throw ("El modulo '$Modulo' no es valido. Use comercial o erp.")
        }
        $ambientesCoincidentes = @($ambientesCoincidentes | Where-Object {
            (Obtener-ModuloAmbienteConfigurado -Ambiente $_ -Contexto ("El ambiente '" + [string]$_.id + "' del cliente '" + $ClienteId + "'")) -eq $moduloSolicitado
        })
    }
    if ($ambientesCoincidentes.Count -eq 0) {
        $ambientesDisponibles = ((@($cliente.ambientes) | ForEach-Object { [string]$_.id }) -join ', ')
        throw ("El ambiente '" + $AmbienteId + "' no existe para el cliente '" + $ClienteId + "'. Ambientes configurados: " + $ambientesDisponibles + ".")
    }
    if ($ambientesCoincidentes.Count -gt 1) {
        throw ("El ambiente '" + $AmbienteId + "' del cliente '" + $ClienteId + "' es ambiguo. Requiere -Modulo para resolver la identidad triple.")
    }
    $ambiente = $ambientesCoincidentes[0]
    $clienteIdCanonico = [string]$cliente.id
    $moduloCanonico = Obtener-ModuloAmbienteConfigurado -Ambiente $ambiente -Contexto ("El ambiente '" + [string]$ambiente.id + "' del cliente '" + $clienteIdCanonico + "'")
    $ambienteIdCanonico = [string]$ambiente.id

    $clientesRoot = Resolver-RutaRepositorio -Ruta ([string]$ConfiguracionRaw.rutas.clientesRoot) -Raiz $RaizRepositorio
    $directorioContexto = [System.IO.Path]::GetFullPath((Join-Path (Join-Path (Join-Path $clientesRoot $clienteIdCanonico) $moduloCanonico) $ambienteIdCanonico))
    $directorioServicios = [System.IO.Path]::GetFullPath((Join-Path $directorioContexto 'documentacionServicios'))
    $directorioEstado = [System.IO.Path]::GetFullPath((Join-Path $directorioContexto 'estado'))
    $directorioXpz = [System.IO.Path]::GetFullPath((Join-Path $directorioContexto 'xpz'))
    $directorioLogs = [System.IO.Path]::GetFullPath((Join-Path $directorioContexto 'Logs'))
    $directorioTestFixtures = [System.IO.Path]::GetFullPath((Join-Path $directorioContexto 'test\fixtures'))
    $directorioTestResultados = [System.IO.Path]::GetFullPath((Join-Path $directorioContexto 'test\resultados'))

    $serviciosIgnorados = @()
    if ($cliente.serviciosIgnorados -and @($cliente.serviciosIgnorados).Count -gt 0) {
        $serviciosIgnorados = @($cliente.serviciosIgnorados | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
    }

    $perfilExportacion = 'GX18'
    $propiedadPerfil = Obtener-PropiedadConfiguracionExacta -Objeto $ConfiguracionRaw.herramientas -Nombre 'geneXusExportProfile'
    if ($null -ne $propiedadPerfil -and -not [string]::IsNullOrWhiteSpace([string]$propiedadPerfil.Value)) {
        $perfilExportacion = [string]$propiedadPerfil.Value
    }

    $herramientas = [pscustomobject]@{
        GeneXusProgramDir = [string]$ConfiguracionRaw.herramientas.geneXusProgramDir
        MsbuildPath = [string]$ConfiguracionRaw.herramientas.msbuildPath
        GeneXusExportProfile = $perfilExportacion
        PandocPath = [string]$ConfiguracionRaw.herramientas.pandocPath
        TypstPath = [string]$ConfiguracionRaw.herramientas.typstPath
    }

    $propiedadHost = Obtener-PropiedadConfiguracionExacta -Objeto $ambiente -Nombre 'host'
    $hostAmbiente = if ($null -ne $propiedadHost -and -not [string]::IsNullOrWhiteSpace([string]$propiedadHost.Value)) {
        Validar-HostAmbiente -HostUrl ([string]$propiedadHost.Value) -Contexto ("El host del ambiente '" + $ambienteIdCanonico + "'")
    } else { $null }
    $baseUrlDeclarado = Obtener-BaseUrlAmbienteConfigurado -Ambiente $ambiente -Contexto ("El ambiente '" + $ambienteIdCanonico + "' del cliente '" + $clienteIdCanonico + "'")
    $baseUrl = if (-not [string]::IsNullOrWhiteSpace($baseUrlDeclarado)) {
        Validar-BaseUrlAmbiente -BaseUrl $baseUrlDeclarado -Contexto ("El baseUrl del ambiente '" + $ambienteIdCanonico + "'")
    } else { $null }
    $serverUrl = if ($hostAmbiente -and $baseUrl) { $hostAmbiente.TrimEnd('/') + '/' + $baseUrl.TrimStart('/').TrimStart('/') } else { $null }
    $packageNames = Obtener-PackageNamesCliente -Cliente $cliente -ClienteId $clienteIdCanonico

    $contexto = [pscustomobject]@{
        ConfigPath = $ConfigPath
        RaizRepositorio = $RaizRepositorio
        ClientesRoot = $clientesRoot
        ClienteId = $clienteIdCanonico
        ClienteNombre = [string]$cliente.nombre
        Modulo = $moduloCanonico
        ModuloNombre = Obtener-NombreModuloCanonico -Modulo $moduloCanonico
        AmbienteId = $ambienteIdCanonico
        AmbienteNombre = Obtener-NombreAmbienteCanonico -Tipo (Clasificar-TipoAmbiente -Tipo ([string]$ambiente.tipo))
        AmbienteTipo = Clasificar-TipoAmbiente -Tipo ([string]$ambiente.tipo)
        ContextId = $clienteIdCanonico + '/' + $moduloCanonico + '/' + $ambienteIdCanonico
        DirectorioContexto = $directorioContexto
        KbPath = Resolver-RutaRepositorio -Ruta ([string]$ambiente.kbPath) -Raiz $RaizRepositorio
        Host = $hostAmbiente
        BaseUrl = $baseUrl
        ServerUrl = $serverUrl
        PackageName = [string]$packageNames[$moduloCanonico]
        PackageNames = $packageNames
        ServiciosIgnorados = $serviciosIgnorados
        DirectorioXpz = $directorioXpz
        DirectorioServicios = $directorioServicios
        DirectorioEstado = $directorioEstado
        RutaControl = [System.IO.Path]::GetFullPath((Join-Path $directorioEstado 'controlVersiones.json'))
        RutaHistorial = [System.IO.Path]::GetFullPath((Join-Path $directorioEstado 'historialVersiones.md'))
        RutaLock = [System.IO.Path]::GetFullPath((Join-Path $directorioEstado 'actualizacion.lock'))
        DirectorioLogs = $directorioLogs
        DirectorioTestFixtures = $directorioTestFixtures
        DirectorioTestResultados = $directorioTestResultados
        Herramientas = $herramientas
    }
    return $contexto
}

function Cargar-Configuracion {
    <#
    .SYNOPSIS
    Carga configuracion.json y resuelve el contexto de cliente y ambiente.
    .DESCRIPTION
    Con el esquema multicliente (propiedad clientes), valida el esquema global y
    construye el contexto canonico de cliente, modulo y ambiente seleccionados.
    Una llamada sin modulo solo se acepta cuando el id de ambiente es inequivoco.
    Con el esquema anterior (propiedad xpz) conserva temporalmente el comportamiento
    historico para los consumidores de la consola.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][string]$ConfigPath,
        [Parameter(Mandatory = $false)][string]$ClienteId,
        [Parameter(Mandatory = $false)][string]$Modulo,
        [Parameter(Mandatory = $false)][string]$AmbienteId,
        [Parameter(Mandatory = $false)][string]$XpzPath,
        [Parameter(Mandatory = $false)][string]$RaizRepositorio
    )

    if ([string]::IsNullOrWhiteSpace($RaizRepositorio)) {
        $raizRepositorio = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    } else {
        $raizRepositorio = [System.IO.Path]::GetFullPath($RaizRepositorio)
    }

    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $raizRepositorio 'configuracion.json'
    }

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw ("No se encontro el archivo de configuracion: " + $ConfigPath)
    }

    $ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path

    $configuracionRaw = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

    if ($null -ne $configuracionRaw.clientes) {
        if ([string]::IsNullOrWhiteSpace($ClienteId) -or [string]::IsNullOrWhiteSpace($AmbienteId)) {
            throw 'La configuracion multicliente requiere -ClienteId y -AmbienteId para resolver el contexto.'
        }
        return Resolver-ContextoConfiguracion -ConfiguracionRaw $configuracionRaw -ConfigPath $ConfigPath -RaizRepositorio $raizRepositorio -ClienteId $ClienteId -AmbienteId $AmbienteId -Modulo $Modulo
    }

    if ($XpzPath) {
        if (-not (Test-Path -LiteralPath $XpzPath)) {
            throw ("No se encontro el XPZ indicado en -XpzPath: " + $XpzPath)
        }
        $rutaXpzResuelta = (Resolve-Path -LiteralPath $XpzPath).Path
    }
    else {
        $rutaXpzRelativa = [string]$configuracionRaw.xpz
        if (-not $rutaXpzRelativa) {
            throw 'La configuracion no define la propiedad xpz.'
        }

        $rutaXpzResuelta = (Resolve-Path (Join-Path $raizRepositorio $rutaXpzRelativa)).Path
    }

    $packageName = [string]$configuracionRaw.packagename
    if (-not $packageName) {
        throw 'La configuracion no define packagename.'
    }

    $serviciosIgnorados = @()
    if ($configuracionRaw.serviciosIgnorados -and @($configuracionRaw.serviciosIgnorados).Count -gt 0) {
        $serviciosIgnorados = @($configuracionRaw.serviciosIgnorados | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
    }

    $herramientasRaw = $configuracionRaw.herramientas
    $herramientas = [pscustomobject]@{
        GeneXusProgramDir = [string]$herramientasRaw.geneXusProgramDir
        KbPath = [string]$herramientasRaw.kbPath
        MsbuildPath = [string]$herramientasRaw.msbuildPath
        PandocPath = [string]$herramientasRaw.pandocPath
        TypstPath = [string]$herramientasRaw.typstPath
        EdgePath = [string]$herramientasRaw.edgePath
    }

    return [pscustomobject]@{
        ConfigPath = $ConfigPath
        XpzPath = $rutaXpzResuelta
        PackageName = $packageName
        Cliente = [string]$configuracionRaw.cliente
        ServiciosIgnorados = $serviciosIgnorados
        Herramientas = $herramientas
        RaizRepositorio = $raizRepositorio
    }
}
