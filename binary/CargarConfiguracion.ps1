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
    $propiedadPerfil = $ConfiguracionRaw.herramientas.PSObject.Properties['geneXusExportProfile']
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
        if ([string]::IsNullOrWhiteSpace([string]$cliente.packagename)) {
            throw ("El cliente '" + $clienteId + "' no define packagename.")
        }
        $claveCliente = $clienteId.ToLowerInvariant()
        if ($clientesVistos.ContainsKey($claveCliente)) {
            throw ("El id de cliente '" + $clienteId + "' esta duplicado (sin distinguir mayusculas de minusculas).")
        }
        $clientesVistos[$claveCliente] = $true

        if ($null -eq $cliente.ambientes -or @($cliente.ambientes).Count -eq 0) {
            throw ("El cliente '" + $clienteId + "' no define ambientes.")
        }
        if (@($cliente.ambientes).Count -gt 2) {
            throw ("El cliente '" + $clienteId + "' no puede tener mas de dos ambientes (un TEST y un PROD).")
        }
        $ambientesVistos = @{}
        $tiposAmbiente = @{}
        foreach ($ambiente in @($cliente.ambientes)) {
            $ambienteId = [string]$ambiente.id
            if (-not (Test-NombreSlugValido -Valor $ambienteId)) {
                throw ("El id de ambiente '" + $ambienteId + "' del cliente '" + $clienteId + "' no es valido. Use minusculas, digitos y guiones con el formato ^[a-z0-9][a-z0-9-]*$.")
            }
            if ([string]::IsNullOrWhiteSpace([string]$ambiente.nombre)) {
                throw ("El ambiente '" + $ambienteId + "' del cliente '" + $clienteId + "' no define su nombre visible.")
            }
            if ([string]::IsNullOrWhiteSpace([string]$ambiente.kbPath)) {
                throw ("El ambiente '" + $ambienteId + "' del cliente '" + $clienteId + "' no define kbPath.")
            }
            $claveAmbiente = $ambienteId.ToLowerInvariant()
            if ($ambientesVistos.ContainsKey($claveAmbiente)) {
                throw ("El id de ambiente '" + $ambienteId + "' del cliente '" + $clienteId + "' esta duplicado (sin distinguir mayusculas de minusculas).")
            }
            $ambientesVistos[$claveAmbiente] = $true

            $kbPathResuelto = Resolver-RutaRepositorio -Ruta ([string]$ambiente.kbPath) -Raiz $RaizRepositorio
            if ($ValidarContenidoKnowledgeBase) {
                Validar-RutaKnowledgeBase -Ruta $kbPathResuelto -Contexto ("La Knowledge Base del ambiente '" + $ambienteId + "' del cliente '" + $clienteId + "'") | Out-Null
            }
            $claveKb = $kbPathResuelto.ToLowerInvariant()
            if ($kbPathsVistos.ContainsKey($claveKb)) {
                throw ("Dos ambientes apuntan a la misma ruta de Knowledge Base: " + $kbPathResuelto)
            }
            $kbPathsVistos[$claveKb] = $true

            $tipoAmbiente = Clasificar-TipoAmbiente -Tipo ([string]$ambiente.tipo)
            if ($null -eq $tipoAmbiente) {
                throw ("El ambiente '" + $ambienteId + "' del cliente '" + $clienteId + "' no define un tipo valido (test o prod).")
            }
            if ($tiposAmbiente.ContainsKey($tipoAmbiente)) {
                throw ("El cliente '" + $clienteId + "' no puede tener mas de un ambiente de tipo " + $tipoAmbiente + ".")
            }
            $tiposAmbiente[$tipoAmbiente] = $true
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
    Devuelve un array de objetos con Id y Nombre visible para el cliente indicado.
    Si el cliente no existe, devuelve una coleccion vacia.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ConfiguracionRaw,
        [Parameter(Mandatory = $true)][string]$ClienteId
    )
    $cliente = @($ConfiguracionRaw.clientes | Where-Object { [string]$_.id -ieq $ClienteId }) | Select-Object -First 1
    if ($null -eq $cliente) {
        return @()
    }
    $resultado = New-Object System.Collections.Generic.List[object]
    foreach ($ambiente in @($cliente.ambientes)) {
        $resultado.Add([pscustomobject]@{
            Id = [string]$ambiente.id
            Nombre = [string]$ambiente.nombre
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
        [Parameter(Mandatory = $true)][string]$AmbienteId
    )

    Validar-ConfiguracionMulticliente -ConfiguracionRaw $ConfiguracionRaw -RaizRepositorio $RaizRepositorio -ConfigPath $ConfigPath | Out-Null

    $cliente = @($ConfiguracionRaw.clientes | Where-Object { [string]$_.id -ieq $ClienteId }) | Select-Object -First 1
    if ($null -eq $cliente) {
        $clientesDisponibles = ((@($ConfiguracionRaw.clientes) | ForEach-Object { [string]$_.id }) -join ', ')
        throw ("El cliente '" + $ClienteId + "' no existe en la configuracion. Clientes configurados: " + $clientesDisponibles + ".")
    }
    $ambiente = @($cliente.ambientes | Where-Object { [string]$_.id -ieq $AmbienteId }) | Select-Object -First 1
    if ($null -eq $ambiente) {
        $ambientesDisponibles = ((@($cliente.ambientes) | ForEach-Object { [string]$_.id }) -join ', ')
        throw ("El ambiente '" + $AmbienteId + "' no existe para el cliente '" + $ClienteId + "'. Ambientes configurados: " + $ambientesDisponibles + ".")
    }

    $clientesRoot = Resolver-RutaRepositorio -Ruta ([string]$ConfiguracionRaw.rutas.clientesRoot) -Raiz $RaizRepositorio
    $directorioContexto = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $clientesRoot $ClienteId) $AmbienteId))
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
    $propiedadPerfil = $ConfiguracionRaw.herramientas.PSObject.Properties['geneXusExportProfile']
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

    return [pscustomobject]@{
        ConfigPath = $ConfigPath
        RaizRepositorio = $RaizRepositorio
        ClientesRoot = $clientesRoot
        ClienteId = $ClienteId
        ClienteNombre = [string]$cliente.nombre
        AmbienteId = $AmbienteId
        AmbienteNombre = Obtener-NombreAmbienteCanonico -Tipo (Clasificar-TipoAmbiente -Tipo ([string]$ambiente.tipo))
        AmbienteTipo = Clasificar-TipoAmbiente -Tipo ([string]$ambiente.tipo)
        ContextId = $ClienteId + '/' + $AmbienteId
        DirectorioContexto = $directorioContexto
        KbPath = Resolver-RutaRepositorio -Ruta ([string]$ambiente.kbPath) -Raiz $RaizRepositorio
        PackageName = [string]$cliente.packagename
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
}

function Cargar-Configuracion {
    <#
    .SYNOPSIS
    Carga configuracion.json y resuelve el contexto de cliente y ambiente.
    .DESCRIPTION
    Con el esquema multicliente (propiedad clientes), valida el esquema global y
    construye el contexto canonico del cliente y ambiente seleccionados. Con el
    esquema anterior (propiedad xpz) conserva temporalmente el comportamiento
    historico: resuelve el XPZ y devuelve el objeto plano, para no interrumpir
    los consumidores mientras se migra la seleccion de contexto.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][string]$ConfigPath,
        [Parameter(Mandatory = $false)][string]$ClienteId,
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
        return Resolver-ContextoConfiguracion -ConfiguracionRaw $configuracionRaw -ConfigPath $ConfigPath -RaizRepositorio $raizRepositorio -ClienteId $ClienteId -AmbienteId $AmbienteId
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
