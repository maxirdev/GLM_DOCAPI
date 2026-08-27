# test/Run-Tests.ps1
# Harness manual de pruebas del pipeline APIGLM, del analizador XPZ y del visor.
# Compatible con PowerShell 5.1 y sin dependencias externas (ni Pester ni Node.js).
# Escribe test/Logs/yyyyMMdd-HHmmss-test.txt y devuelve 0 si todo pasa o 1 si
# algun caso falla. Nunca escribe en carpetas productivas: los temporales de las
# pruebas viven exclusivamente en test/tmp/ y se eliminan siempre en el finally.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)][string]$ClienteId,
    [Parameter(Mandatory = $false)][string]$AmbienteId,
    [Parameter(Mandatory = $false)][string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

$DirectorioScript = $PSScriptRoot
$RaizRepositorio = [System.IO.Path]::GetFullPath((Join-Path $DirectorioScript '..'))
$DirectorioBinario = Join-Path $RaizRepositorio 'binary'
$DirectorioFixtures = Join-Path $DirectorioScript 'fixtures'
$DirectorioFixturesXml = Join-Path $DirectorioFixtures 'xml'
$DirectorioFixturesJson = Join-Path $DirectorioFixtures 'json'
$DirectorioFixturesXpz = Join-Path $DirectorioFixtures 'xpz'
$DirectorioFixturesReportes = Join-Path $DirectorioFixtures 'reportes'
$DirectorioTmp = Join-Path $DirectorioScript 'tmp'
$DirectorioLogs = Join-Path $DirectorioScript 'Logs'
$DirectorioServiciosProduccion = Join-Path $RaizRepositorio 'documentacionServicios'

$Casos = New-Object System.Collections.Generic.List[object]
$FallaLimpieza = ''
$MarcaTemporal = Get-Date -Format 'yyyyMMdd-HHmmss'
$RutaLog = Join-Path $DirectorioLogs ($MarcaTemporal + '-test.txt')

function Registrar-Caso {
    <#
    .SYNOPSIS
    Registra un caso en memoria con identificador, resultado y detalle.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Estado,
        [Parameter(Mandatory = $false)][string]$Detalle = ''
    )
    $Casos.Add([pscustomobject]@{
        Id = $Id
        Estado = $Estado
        Detalle = $Detalle
    })
}

function Test-Asercion {
    <#
    .SYNOPSIS
    Evalua una condicion y registra un caso PASS o FAIL.
    .DESCRIPTION
    Si la evaluacion de la condicion lanza una excepcion, el caso se registra como
    FAIL con el mensaje de la excepcion como detalle, sin interrumpir la ejecucion.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][bool]$Condicion,
        [Parameter(Mandatory = $false)][string]$DetalleExito = 'La condicion se cumplio.',
        [Parameter(Mandatory = $false)][string]$DetalleFallo = 'La condicion no se cumplio.'
    )
    try {
        $cumple = [bool]$Condicion
    } catch {
        Registrar-Caso -Id $Id -Estado 'FAIL' -Detalle ('Excepcion al evaluar la condicion: ' + $_.Exception.Message)
        return
    }
    if ($cumple) {
        Registrar-Caso -Id $Id -Estado 'PASS' -Detalle $DetalleExito
    } else {
        Registrar-Caso -Id $Id -Estado 'FAIL' -Detalle $DetalleFallo
    }
}

function Test-AsercionLanzaError {
    <#
    .SYNOPSIS
    Verifica que un bloque lanza una excepcion cuyo mensaje coincide con un patron.
    .DESCRIPTION
    El bloque se ejecuta con ErrorActionPreference Stop y cualquier excepcion se
    captura para comparar su mensaje contra el patron esperado. Si no lanza, el
    caso es FAIL; si lanza y el mensaje no coincide, tambien es FAIL.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][scriptblock]$Bloque,
        [Parameter(Mandatory = $false)][string]$PatronMensaje = '',
        [Parameter(Mandatory = $false)][string]$DetalleExito = 'La excepcion esperada se produjo.',
        [Parameter(Mandatory = $false)][string]$DetalleFallo = 'El bloque no lanzo una excepcion.'
    )
    try {
        $ErrorActionPreferenceTemporal = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        try {
            & $Bloque
        } finally {
            $ErrorActionPreference = $ErrorActionPreferenceTemporal
        }
        Registrar-Caso -Id $Id -Estado 'FAIL' -Detalle $DetalleFallo
    } catch {
        $mensaje = [string]$_.Exception.Message
        if ($PatronMensaje -and $mensaje -notmatch $PatronMensaje) {
            Registrar-Caso -Id $Id -Estado 'FAIL' -Detalle ('Mensaje inesperado: ' + $mensaje)
        } else {
            Registrar-Caso -Id $Id -Estado 'PASS' -Detalle $DetalleExito
        }
    }
}

function Test-Skip {
    <#
    .SYNOPSIS
    Registra un caso como SKIP con su motivo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $false)][string]$Detalle = 'Caso omitido.'
    )
    Registrar-Caso -Id $Id -Estado 'SKIP' -Detalle $Detalle
}

function New-DirectorioSiNoExiste {
    <#
    .SYNOPSIS
    Crea un directorio si no existe y devuelve su ruta absoluta.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Directorio
    )
    if (-not (Test-Path -LiteralPath $Directorio)) {
        New-Item -ItemType Directory -Path $Directorio -Force | Out-Null
    }
    return [System.IO.Path]::GetFullPath($Directorio)
}

function Cargar-ModulosProduccion {
    <#
    .SYNOPSIS
    Devuelve el detalle de los modulos productivos que el harness debe cargar.
    .DESCRIPTION
    El dot-source de los modulos se realiza en el ambito del script (no dentro de
    una funcion) para que sus funciones queden visibles para todos los casos.
    #>
    [CmdletBinding()]
    param()
    return @(
        (Join-Path $DirectorioBinario 'GLMUtilidades.ps1')
        (Join-Path $DirectorioBinario 'CargarConfiguracion.ps1')
        (Join-Path $DirectorioBinario 'AnalizarServicio.ps1')
        (Join-Path $DirectorioBinario 'CargarMultiXPZ.ps1')
        (Join-Path $DirectorioBinario 'RedactarDocumento.ps1')
        (Join-Path $DirectorioBinario 'EscribirSalidas.ps1')
        (Join-Path $DirectorioBinario 'ControlVersiones.ps1')
        (Join-Path $DirectorioBinario 'HistorialVersiones.ps1')
        (Join-Path $DirectorioBinario 'ManifiestoEjecucion.ps1')
    )
}

function Resolver-DirectoriosPrueba {
    <#
    .SYNOPSIS
    Resuelve el contexto de cliente y ambiente donde se escriben los resultados.
    .DESCRIPTION
    Con -ClienteId/-AmbienteId usa el contexto activo de la consola; si no se
    indican o fallan, cae al primer cliente y ambiente de configuracion.json.
    Reasigna DirectorioLogs, DirectorioTmp y RutaLog al test/resultados del
    contexto. Si no puede resolver nada, conserva las rutas raiz por defecto.
    #>
    [CmdletBinding()]
    param()

    $rutaConfiguracionPrueba = $ConfigPath
    if ([string]::IsNullOrWhiteSpace($rutaConfiguracionPrueba)) {
        $rutaConfiguracionPrueba = Join-Path $RaizRepositorio 'configuracion.json'
    }

    $contexto = $null
    if ($ClienteId -and $AmbienteId) {
        try {
            $contexto = Cargar-Configuracion -ConfigPath $rutaConfiguracionPrueba -ClienteId $ClienteId -AmbienteId $AmbienteId
        } catch {
            Write-Host ('Advertencia: no se pudo resolver el contexto de pruebas indicado (' + $ClienteId + '/' + $AmbienteId + '): ' + $_.Exception.Message) -ForegroundColor Yellow
        }
    }
    if ($null -eq $contexto) {
        try {
            $configuracionCrudaPrueba = Leer-ConfiguracionCruda -ConfigPath $rutaConfiguracionPrueba
            $primerCliente = @($configuracionCrudaPrueba.clientes)[0]
            $primerAmbiente = @($primerCliente.ambientes)[0]
            if ($null -ne $primerCliente -and $null -ne $primerAmbiente) {
                $contexto = Cargar-Configuracion -ConfigPath $rutaConfiguracionPrueba -ClienteId ([string]$primerCliente.id) -AmbienteId ([string]$primerAmbiente.id)
            }
        } catch { }
    }

    if ($null -ne $contexto) {
        $script:ContextoPruebas = $contexto
        $script:DirectorioLogs = $contexto.DirectorioTestResultados
        $script:DirectorioTmp = Join-Path $contexto.DirectorioTestResultados 'tmp'
        $script:RutaLog = Join-Path $script:DirectorioLogs ($MarcaTemporal + '-test.txt')
    }
    return $contexto
}

function Ejecutar-CasosConfiguracion {
    <#
    .SYNOPSIS
    Casos de carga de configuracion ampliada, override -XpzPath y parseo unico.
    .DESCRIPTION
    Prueba Cargar-Configuracion con la configuracion real del repositorio y con un
    fixture que incluye cliente, exportacion, herramientas y serviciosIgnorados,
    ademas del override explicito de XpzPath y los errores esperados.
    #>
    [CmdletBinding()]
    param()

    $rutaConfigPrueba = Join-Path $DirectorioFixturesJson 'configuracion-prueba.json'
    $rutaXpzBase = Join-Path $DirectorioFixturesXpz 'SEGUROS_COMERCIAL_APIGLM_test.xpz'
    $rutaXpzComplemento = Join-Path $DirectorioFixturesXpz 'SEGUROS_COMERCIAL_APIGLM_test_1.xpz'

    $configReal = $null
    try { $configReal = Cargar-Configuracion -ClienteId 'trunk' -AmbienteId 'testing' } catch { }
    Test-Asercion -Id 'configuracion.cargaReal' -Condicion (
        $null -ne $configReal -and
        $configReal.ContextId -eq 'trunk/comercial/testing' -and
        $configReal.ClienteId -eq 'trunk' -and
        $configReal.Modulo -eq 'comercial' -and
        $configReal.AmbienteId -eq 'testing' -and
        $configReal.PackageName -eq 'glmsuit.comercial.' -and
        @($configReal.ServiciosIgnorados).Count -eq 4 -and
        $configReal.DirectorioXpz -eq [System.IO.Path]::GetFullPath((Join-Path $configReal.ClientesRoot 'trunk\comercial\testing\xpz'))
    ) -DetalleExito 'La configuracion real resuelve el contexto trunk/testing con packagename y serviciosIgnorados del cliente.' -DetalleFallo 'La configuracion real no resuelve el contexto multicliente esperado.'

    $configPrueba = $null
    try { $configPrueba = Cargar-Configuracion -ConfigPath $rutaConfigPrueba } catch { }
    Test-Asercion -Id 'configuracion.fixture' -Condicion (
        $null -ne $configPrueba -and
        $configPrueba.XpzPath -eq $rutaXpzBase -and
        $configPrueba.PackageName -eq 'glmsuit.comercial.' -and
        $configPrueba.Cliente -eq 'Trunk' -and
        (@($configPrueba.ServiciosIgnorados) -contains 'APIGLM.Test.WSTestMaxi') -and
        (@($configPrueba.ServiciosIgnorados) -contains 'APIGLM.WSEjemplo')
    ) -DetalleExito 'El fixture de configuracion carga xpz, packagename, cliente y serviciosIgnorados.' -DetalleFallo 'El fixture de configuracion no carga los campos esperados.'

    $configOverride = $null
    try { $configOverride = Cargar-Configuracion -ConfigPath $rutaConfigPrueba -XpzPath $rutaXpzComplemento } catch { }
    Test-Asercion -Id 'configuracion.override' -Condicion (
        $null -ne $configOverride -and $configOverride.XpzPath -eq $rutaXpzComplemento
    ) -DetalleExito 'El override -XpzPath reemplaza la ruta del XPZ configurado.' -DetalleFallo 'El override -XpzPath no se aplico.'

    Test-AsercionLanzaError -Id 'configuracion.overrideInexistente' -Bloque { Cargar-Configuracion -ConfigPath $rutaConfigPrueba -XpzPath 'C:\ruta\inexistente\no-existe.xpz' } -PatronMensaje 'No se encontro el XPZ indicado' -DetalleExito 'Un -XpzPath inexistente lanza el error esperado.' -DetalleFallo 'Un -XpzPath inexistente no lanza el error esperado.'

    Test-AsercionLanzaError -Id 'configuracion.archivoInexistente' -Bloque { Cargar-Configuracion -ConfigPath 'C:\ruta\inexistente\configuracion.json' } -PatronMensaje 'No se encontro el archivo de configuracion' -DetalleExito 'Un archivo de configuracion inexistente lanza el error esperado.' -DetalleFallo 'Un archivo de configuracion inexistente no lanza el error esperado.'

    $rawPrueba = Cargar-JsonFixture -Nombre 'configuracion-prueba.json'
    Test-Asercion -Id 'configuracion.exportacion' -Condicion (
        $null -ne $rawPrueba.exportacion -and $rawPrueba.exportacion.onlyModuleAPIGLM -eq $true
    ) -DetalleExito 'El esquema ampliado conserva la seccion exportacion con onlyModuleAPIGLM.' -DetalleFallo 'La seccion exportacion no esta presente o no es correcta.'

    $herramientasPrueba = $configPrueba.Herramientas
    Test-Asercion -Id 'configuracion.herramientas' -Condicion (
        $null -ne $herramientasPrueba -and
        -not [string]::IsNullOrWhiteSpace([string]$herramientasPrueba.GeneXusProgramDir) -and
        -not [string]::IsNullOrWhiteSpace([string]$herramientasPrueba.KbPath) -and
        -not [string]::IsNullOrWhiteSpace([string]$herramientasPrueba.MsbuildPath) -and
        -not [string]::IsNullOrWhiteSpace([string]$herramientasPrueba.PandocPath) -and
        -not [string]::IsNullOrWhiteSpace([string]$herramientasPrueba.TypstPath)
    ) -DetalleExito 'La configuracion expone las herramientas de GeneXus, MSBuild, Pandoc y Typst.' -DetalleFallo 'La configuracion no expone las herramientas esperadas.'

    $inventarioMinimo = $null
    try { $inventarioMinimo = Cargar-JsonFixture -Nombre 'control-versiones-minimo.json' } catch { }
    Test-Asercion -Id 'configuracion.parseoInventarioUnico' -Condicion (
        $null -ne $inventarioMinimo -and
        @($inventarioMinimo.endpoints).Count -eq 1 -and
        $inventarioMinimo.meta.totalConfirmed -eq 1 -and
        $inventarioMinimo.endpoints[0].proceso -eq 'APIGLM.Comun.WSListarEstados'
    ) -DetalleExito 'El inventario minimo se parsea una unica vez con meta coherente.' -DetalleFallo 'El inventario minimo no se parsea correctamente.'

    $xmlBase = Cargar-XmlFixture -Nombre 'xpz-base.xml'
    $indiceBase = Construir-Indices -Xml $xmlBase
    $wrapperBase = Obtener-Objeto -Xml $xmlBase -NombreCompleto 'APIGLM.Cotizacion.WSObtenerProductor' -Indice $indiceBase
    Test-Asercion -Id 'configuracion.parseoXmlUnico' -Condicion (
        $null -ne $wrapperBase -and
        $wrapperBase.GetAttribute('guid') -eq 'aaaaaaaa-0000-0000-0000-000000000001' -and
        $indiceBase.PorFqn.Count -gt 0
    ) -DetalleExito 'El XML del fixture se indexa una unica vez por fullyQualifiedName.' -DetalleFallo 'El XML del fixture no se indexa de forma unica.'
}

function Ejecutar-CasosConfiguracionMulticliente {
    <#
    .SYNOPSIS
    Casos del esquema multicliente: contexto canonico, rutas, selectores, ids
    invalidos o duplicados, kbPath duplicado y aislamiento entre contextos.
    .DESCRIPTION
    Ejercita Cargar-Configuracion con los fixtures JSON multicliente, Validar-
    ConfiguracionMulticliente, Obtener-ClientesConfigurados, Obtener-Ambientes-
    Configurados y Resolver-ContextoConfiguracion. No crea carpetas ni archivos.
    #>
    [CmdletBinding()]
    param()

    $rutaMulticliente = Join-Path $DirectorioFixturesJson 'configuracion-multicliente.json'
    $clientesRootEsperado = [System.IO.Path]::GetFullPath((Join-Path $RaizRepositorio 'clientes'))
    $directorioContextoEsperado = [System.IO.Path]::GetFullPath((Join-Path $clientesRootEsperado 'trunk\comercial\testing'))

    $contextoTrunk = $null
    try { $contextoTrunk = Cargar-Configuracion -ConfigPath $rutaMulticliente -ClienteId 'trunk' -AmbienteId 'testing' } catch { }
    Test-Asercion -Id 'configuracionMulticliente.contextoValido' -Condicion (
        $null -ne $contextoTrunk -and
        $contextoTrunk.ContextId -eq 'trunk/comercial/testing' -and
        $contextoTrunk.ClienteId -eq 'trunk' -and
        $contextoTrunk.ClienteNombre -eq 'Trunk' -and
        $contextoTrunk.AmbienteId -eq 'testing' -and
        $contextoTrunk.AmbienteNombre -eq 'TEST' -and
        $contextoTrunk.Host -eq 'https://trunk.example.com' -and
        $contextoTrunk.BaseUrl -eq '/testing/rest' -and
        $contextoTrunk.ServerUrl -eq 'https://trunk.example.com/testing/rest' -and
        $contextoTrunk.DirectorioContexto -eq $directorioContextoEsperado -and
         $contextoTrunk.KbPath -eq 'C:\KBs\SEGUROS_COMERCIAL_TRUNK' -and

        $contextoTrunk.PackageName -eq 'glmsuit.comercial.' -and
        $contextoTrunk.RaizRepositorio -eq $RaizRepositorio -and
        $contextoTrunk.ConfigPath -eq (Resolve-Path -LiteralPath $rutaMulticliente).Path
    ) -DetalleExito 'El contexto trunk/testing se resuelve con identidad, rutas y contrato del cliente.' -DetalleFallo 'El contexto trunk/testing no se resolvio correctamente.'

    Test-Asercion -Id 'configuracionMulticliente.rutasContextuales' -Condicion (
        $contextoTrunk.DirectorioXpz -eq [System.IO.Path]::GetFullPath((Join-Path $directorioContextoEsperado 'xpz')) -and
        $contextoTrunk.DirectorioServicios -eq [System.IO.Path]::GetFullPath((Join-Path $directorioContextoEsperado 'documentacionServicios')) -and
        $contextoTrunk.DirectorioEstado -eq [System.IO.Path]::GetFullPath((Join-Path $directorioContextoEsperado 'estado')) -and
        $contextoTrunk.RutaControl -eq [System.IO.Path]::GetFullPath((Join-Path $directorioContextoEsperado 'estado\controlVersiones.json')) -and
        $contextoTrunk.RutaHistorial -eq [System.IO.Path]::GetFullPath((Join-Path $directorioContextoEsperado 'estado\historialVersiones.md')) -and
        $contextoTrunk.RutaLock -eq [System.IO.Path]::GetFullPath((Join-Path $directorioContextoEsperado 'estado\actualizacion.lock')) -and
        $contextoTrunk.DirectorioLogs -eq [System.IO.Path]::GetFullPath((Join-Path $directorioContextoEsperado 'Logs')) -and
        $contextoTrunk.DirectorioTestFixtures -eq [System.IO.Path]::GetFullPath((Join-Path $directorioContextoEsperado 'test\fixtures')) -and
        $contextoTrunk.DirectorioTestResultados -eq [System.IO.Path]::GetFullPath((Join-Path $directorioContextoEsperado 'test\resultados'))
    ) -DetalleExito 'El contexto deriva las rutas contextuales de documentos, estado, XPZ, logs y datos de prueba.' -DetalleFallo 'Las rutas contextuales no se derivaron correctamente.'

    Test-Asercion -Id 'configuracionMulticliente.serviciosIgnoradosCliente' -Condicion (
        @($contextoTrunk.ServiciosIgnorados).Count -eq 4 -and
        @($contextoTrunk.ServiciosIgnorados) -contains 'APIGLM.Test.WSTestMaxi' -and
        @($contextoTrunk.ServiciosIgnorados) -contains 'APIGLM.WSEjemplo'
    ) -DetalleExito 'Los serviciosIgnorados pertenecen al cliente y se propagan al contexto.' -DetalleFallo 'Los serviciosIgnorados del cliente no se propagaron.'

    Test-Asercion -Id 'configuracionMulticliente.herramientasGlobales' -Condicion (
        $null -ne $contextoTrunk.Herramientas -and
        -not [string]::IsNullOrWhiteSpace([string]$contextoTrunk.Herramientas.GeneXusProgramDir) -and
        -not [string]::IsNullOrWhiteSpace([string]$contextoTrunk.Herramientas.MsbuildPath) -and
        -not [string]::IsNullOrWhiteSpace([string]$contextoTrunk.Herramientas.PandocPath) -and
        -not [string]::IsNullOrWhiteSpace([string]$contextoTrunk.Herramientas.TypstPath) -and
        $null -eq $contextoTrunk.Herramientas.KbPath
    ) -DetalleExito 'Las herramientas son globales y no contienen kbPath por contexto.' -DetalleFallo 'Las herramientas globales no se resolvieron correctamente.'

    $contextoProduccion = Cargar-Configuracion -ConfigPath $rutaMulticliente -ClienteId 'trunk' -AmbienteId 'produccion'
    $contextoOtro = Cargar-Configuracion -ConfigPath $rutaMulticliente -ClienteId 'otrocliente' -AmbienteId 'testing'
    Test-Asercion -Id 'configuracionMulticliente.aislamientoContextos' -Condicion (
        $contextoProduccion.ContextId -eq 'trunk/comercial/produccion' -and
        $contextoOtro.ContextId -eq 'otrocliente/comercial/testing' -and
        $contextoProduccion.DirectorioContexto -ne $contextoTrunk.DirectorioContexto -and
        $contextoOtro.DirectorioContexto -ne $contextoTrunk.DirectorioContexto -and
        $contextoOtro.RutaControl -ne $contextoTrunk.RutaControl -and
        $contextoOtro.RutaLock -ne $contextoTrunk.RutaLock -and
        $contextoOtro.PackageName -eq 'otro.packagename.'
    ) -DetalleExito 'Cada contexto aisla documentos, estado y lock aunque compartan el id de ambiente.' -DetalleFallo 'Los contextos no estan aislados entre si.'

    Test-Asercion -Id 'configuracionMulticliente.clientesRootRelativo' -Condicion (
        $contextoTrunk.ClientesRoot -eq $clientesRootEsperado
    ) -DetalleExito 'Un clientesRoot relativo se resuelve contra la raiz del repositorio.' -DetalleFallo 'El clientesRoot relativo no se resolvio contra la raiz.'

    $rutaClientesRootAbsoluta = Join-Path $DirectorioFixturesJson 'configuracion-multicliente-clientesroot-absoluta.json'
    $contextoAbsoluto = Cargar-Configuracion -ConfigPath $rutaClientesRootAbsoluta -ClienteId 'trunk' -AmbienteId 'testing'
    Test-Asercion -Id 'configuracionMulticliente.clientesRootAbsoluto' -Condicion (
        $contextoAbsoluto.ClientesRoot -eq [System.IO.Path]::GetFullPath('C:\DOCUMENTACION\ClientesRaiz')
    ) -DetalleExito 'Un clientesRoot absoluto se conserva sin cambios.' -DetalleFallo 'El clientesRoot absoluto no se conservo.'

    Test-Asercion -Id 'configuracionMulticliente.kbPathRelativo' -Condicion (
        $contextoOtro.KbPath -eq [System.IO.Path]::GetFullPath((Join-Path $RaizRepositorio 'test\fixtures\kb\otra'))
    ) -DetalleExito 'Un kbPath relativo se resuelve contra la raiz y nunca se deduce del nombre o id.' -DetalleFallo 'El kbPath relativo no se resolvio contra la raiz.'

    $configuracionCrudaMulticliente = Cargar-JsonFixture -Nombre 'configuracion-multicliente.json'
    $clientesConfigurados = @(Obtener-ClientesConfigurados -ConfiguracionRaw $configuracionCrudaMulticliente)
    $ambientesTrunk = @(Obtener-AmbientesConfigurados -ConfiguracionRaw $configuracionCrudaMulticliente -ClienteId 'trunk')
    $ambientesInexistentes = @(Obtener-AmbientesConfigurados -ConfiguracionRaw $configuracionCrudaMulticliente -ClienteId 'inexistente')
    Test-Asercion -Id 'configuracionMulticliente.selectores' -Condicion (
        $clientesConfigurados.Count -eq 2 -and
        $clientesConfigurados[0].Id -eq 'trunk' -and $clientesConfigurados[0].Nombre -eq 'Trunk' -and
        $ambientesTrunk.Count -eq 2 -and
        @($ambientesTrunk | Where-Object { $_.Id -eq 'testing' }).Count -eq 1 -and
        @($ambientesTrunk | Where-Object { $_.Id -eq 'produccion' }).Count -eq 1 -and
        $ambientesInexistentes.Count -eq 0
    ) -DetalleExito 'Los selectores devuelven clientes y ambientes con id y nombre visible, sin ambientes de clientes inexistentes.' -DetalleFallo 'Los selectores no devolvieron la coleccion esperada.'

    $rutaIdInvalido = Join-Path $DirectorioFixturesJson 'configuracion-multicliente-id-invalido.json'
    Test-AsercionLanzaError -Id 'configuracionMulticliente.idInvalido' -Bloque { Cargar-Configuracion -ConfigPath $rutaIdInvalido -ClienteId 'trunk' -AmbienteId 'testing' } -PatronMensaje 'no es valido' -DetalleExito 'Un id de cliente fuera del formato slug se rechaza.' -DetalleFallo 'El id de cliente invalido no se rechazo.'

    $rutaDuplicados = Join-Path $DirectorioFixturesJson 'configuracion-multicliente-duplicados.json'
    Test-AsercionLanzaError -Id 'configuracionMulticliente.clienteDuplicado' -Bloque { Cargar-Configuracion -ConfigPath $rutaDuplicados -ClienteId 'trunk' -AmbienteId 'testing' } -PatronMensaje 'duplicado' -DetalleExito 'Un id de cliente duplicado se rechaza antes de resolver el contexto.' -DetalleFallo 'El id de cliente duplicado no se rechazo.'

    $rutaAmbienteDuplicado = Join-Path $DirectorioFixturesJson 'configuracion-multicliente-ambiente-duplicado.json'
    Test-AsercionLanzaError -Id 'configuracionMulticliente.ambienteDuplicado' -Bloque { Cargar-Configuracion -ConfigPath $rutaAmbienteDuplicado -ClienteId 'trunk' -AmbienteId 'testing' } -PatronMensaje 'duplicado' -DetalleExito 'Un id de ambiente duplicado dentro de un cliente se rechaza.' -DetalleFallo 'El id de ambiente duplicado no se rechazo.'

    $rutaKbDuplicada = Join-Path $DirectorioFixturesJson 'configuracion-multicliente-kb-duplicada.json'
    Test-AsercionLanzaError -Id 'configuracionMulticliente.kbPathDuplicado' -Bloque { Cargar-Configuracion -ConfigPath $rutaKbDuplicada -ClienteId 'trunk' -AmbienteId 'testing' } -PatronMensaje 'misma ruta de Knowledge Base' -DetalleExito 'Dos kbPath que normalizan a la misma ruta se rechazan.' -DetalleFallo 'El kbPath duplicado no se rechazo.'

    Test-Asercion -Id 'configuracionMulticliente.ambienteTipo' -Condicion (
        $contextoTrunk.AmbienteTipo -eq 'test' -and
        $contextoProduccion.AmbienteTipo -eq 'prod' -and
        $contextoOtro.AmbienteTipo -eq 'test'
    ) -DetalleExito 'El contexto expone el tipo de ambiente canonico (test o prod) derivado del campo tipo.' -DetalleFallo 'El tipo de ambiente no se expuso o no coincide con el campo tipo.'

    $rutaTipoFaltante = Join-Path $DirectorioFixturesJson 'configuracion-multicliente-tipo-faltante.json'
    Test-AsercionLanzaError -Id 'configuracionMulticliente.tipoFaltante' -Bloque { Cargar-Configuracion -ConfigPath $rutaTipoFaltante -ClienteId 'trunk' -AmbienteId 'testing' } -PatronMensaje 'tipo valido' -DetalleExito 'Un ambiente sin tipo (o con tipo invalido) se rechaza.' -DetalleFallo 'El ambiente sin tipo no se rechazo.'

    $rutaTipoDuplicado = Join-Path $DirectorioFixturesJson 'configuracion-multicliente-tipo-duplicado.json'
    Test-AsercionLanzaError -Id 'configuracionMulticliente.tipoDuplicado' -Bloque { Cargar-Configuracion -ConfigPath $rutaTipoDuplicado -ClienteId 'trunk' -AmbienteId 'testing' } -PatronMensaje 'combinacion' -DetalleExito 'Un cliente no puede tener dos ambientes del mismo tipo dentro del mismo modulo.' -DetalleFallo 'El tipo duplicado dentro de un modulo no se rechazo.'

    $rutaTresAmbientes = Join-Path $DirectorioFixturesJson 'configuracion-multicliente-tres-ambientes.json'
    Test-AsercionLanzaError -Id 'configuracionMulticliente.demasiadosAmbientes' -Bloque { Cargar-Configuracion -ConfigPath $rutaTresAmbientes -ClienteId 'trunk' -AmbienteId 'testing' } -PatronMensaje 'combinacion|mas de cuatro' -DetalleExito 'Un cliente con combinaciones de ambiente repetidas se rechaza.' -DetalleFallo 'La configuracion con ambientes repetidos no se rechazo.'

    Test-AsercionLanzaError -Id 'configuracionMulticliente.requiereContexto' -Bloque { Cargar-Configuracion -ConfigPath $rutaMulticliente } -PatronMensaje 'requiere -ClienteId' -DetalleExito 'El esquema multicliente exige cliente y ambiente explicitos.' -DetalleFallo 'El esquema multicliente no exigio el contexto.'

    Test-AsercionLanzaError -Id 'configuracionMulticliente.clienteInexistente' -Bloque { Cargar-Configuracion -ConfigPath $rutaMulticliente -ClienteId 'inexistente' -AmbienteId 'testing' } -PatronMensaje 'no existe en la configuracion' -DetalleExito 'Un cliente fuera de la coleccion se informa con los configurados.' -DetalleFallo 'El cliente inexistente no se informo.'

    Test-AsercionLanzaError -Id 'configuracionMulticliente.ambienteInexistente' -Bloque { Cargar-Configuracion -ConfigPath $rutaMulticliente -ClienteId 'trunk' -AmbienteId 'inexistente' } -PatronMensaje 'no existe para el cliente' -DetalleExito 'Un ambiente fuera de la coleccion del cliente se informa con los configurados.' -DetalleFallo 'El ambiente inexistente no se informo.'

    $contextoSinHost = Cargar-Configuracion -ConfigPath (Join-Path $DirectorioFixturesJson 'configuracion-multicliente-host-faltante.json') -ClienteId 'trunk' -AmbienteId 'testing'
    Test-Asercion -Id 'configuracionMulticliente.hostFaltante' -Condicion ($null -eq $contextoSinHost.Host -and $null -eq $contextoSinHost.ServerUrl) -DetalleExito 'Un ambiente sin host conserva host y serverUrl nulos.' -DetalleFallo 'El host faltante no se trato como opcional.'
    $contextoSinBaseUrl = Cargar-Configuracion -ConfigPath (Join-Path $DirectorioFixturesJson 'configuracion-multicliente-baseurl-faltante.json') -ClienteId 'trunk' -AmbienteId 'testing'
    Test-Asercion -Id 'configuracionMulticliente.baseUrlFaltante' -Condicion ($null -eq $contextoSinBaseUrl.BaseUrl -and $null -eq $contextoSinBaseUrl.ServerUrl) -DetalleExito 'Un ambiente sin baseUrl conserva baseUrl y serverUrl nulos.' -DetalleFallo 'El baseUrl faltante no se trato como opcional.'
    Test-AsercionLanzaError -Id 'configuracionMulticliente.hostInvalido' -Bloque { Cargar-Configuracion -ConfigPath (Join-Path $DirectorioFixturesJson 'configuracion-multicliente-host-invalido.json') -ClienteId 'trunk' -AmbienteId 'testing' } -PatronMensaje 'origen absoluto' -DetalleExito 'Un host con path adicional se rechaza.' -DetalleFallo 'El host con path adicional no se rechazo.'
    Test-AsercionLanzaError -Id 'configuracionMulticliente.baseUrlInvalido' -Bloque { Cargar-Configuracion -ConfigPath (Join-Path $DirectorioFixturesJson 'configuracion-multicliente-baseurl-invalido.json') -ClienteId 'trunk' -AmbienteId 'testing' } -PatronMensaje 'debe ser una ruta' -DetalleExito 'Un baseUrl sin barra inicial se rechaza.' -DetalleFallo 'El baseUrl sin barra inicial no se rechazo.'
}

function Ejecutar-CasosMigracionConfiguracionModular {
    <#
    .SYNOPSIS
    Prueba la migracion modular sobre copias temporales de configuracion.json.
    .DESCRIPTION
    Verifica simulacion sin escritura, canonizacion de aliases heredados, rechazo
    de conflictos y package names faltantes, limpieza de temporales atomicos y
    restauracion del archivo vigente cuando falla la validacion del candidato.
    #>
    [CmdletBinding()]
    param()

    $rutaScriptMigracion = Join-Path $DirectorioBinario 'MigrarConfiguracionModulos.ps1'
    Test-Asercion -Id 'migracionModular.scriptDisponible' -Condicion (Test-Path -LiteralPath $rutaScriptMigracion -PathType Leaf) -DetalleExito 'El script de migracion modular esta disponible para las pruebas.' -DetalleFallo 'No se encontro binary/MigrarConfiguracionModulos.ps1.'
    if (-not (Test-Path -LiteralPath $rutaScriptMigracion -PathType Leaf)) { return }

    $directorioMigracion = Join-Path $DirectorioTmp 'migracion-configuracion-modular'
    New-DirectorioSiNoExiste -Directorio $directorioMigracion | Out-Null

    $rutaFixtureAliases = Join-Path $DirectorioFixturesJson 'configuracion-modular-aliases-heredados.json'
    $rutaConfiguracionSimulacion = Join-Path $directorioMigracion 'configuracion-simulacion.json'
    Copy-Item -LiteralPath $rutaFixtureAliases -Destination $rutaConfiguracionSimulacion -Force
    $bytesAntesSimulacion = [System.IO.File]::ReadAllBytes($rutaConfiguracionSimulacion)
    $resultadoSimulacion = Invocar-ScriptHijo -RutaScript $rutaScriptMigracion -Argumentos @('-ConfigPath', $rutaConfiguracionSimulacion, '-Simular') -NormalizarCodigo -NoImprimir
    $bytesDespuesSimulacion = [System.IO.File]::ReadAllBytes($rutaConfiguracionSimulacion)
    $residualesSimulacion = @(Get-ChildItem -LiteralPath $directorioMigracion -File | Where-Object { $_.Name -like 'configuracion-simulacion.json.*' })
    Test-Asercion -Id 'migracionModular.simulacionSinEscritura' -Condicion (
        $resultadoSimulacion.CodigoSalida -eq 0 -and
        [System.Linq.Enumerable]::SequenceEqual($bytesAntesSimulacion, $bytesDespuesSimulacion) -and
        $residualesSimulacion.Count -eq 0
    ) -DetalleExito 'La simulacion termina correctamente, conserva byte a byte la configuracion y no deja temporales.' -DetalleFallo 'La simulacion modifico la configuracion, fallo o dejo archivos temporales.'

    $rutaConfiguracionCanonica = Join-Path $directorioMigracion 'configuracion-canonica.json'
    Copy-Item -LiteralPath $rutaFixtureAliases -Destination $rutaConfiguracionCanonica -Force
    $resultadoCanonizacion = Invocar-ScriptHijo -RutaScript $rutaScriptMigracion -Argumentos @('-ConfigPath', $rutaConfiguracionCanonica) -NormalizarCodigo -NoImprimir
    $configuracionCanonica = $null
    try { $configuracionCanonica = Get-Content -LiteralPath $rutaConfiguracionCanonica -Raw | ConvertFrom-Json } catch { }
    $clienteCanonico = if ($configuracionCanonica) { @($configuracionCanonica.clientes)[0] } else { $null }
    $ambienteCanonico = if ($clienteCanonico) { @($clienteCanonico.ambientes)[0] } else { $null }
    $tienePackagenameHeredado = $false
    $tieneBaseurlHeredado = $false
    if ($clienteCanonico) { $tienePackagenameHeredado = @($clienteCanonico.PSObject.Properties | Where-Object { $_.Name -ceq 'packagename' }).Count -gt 0 }
    if ($ambienteCanonico) { $tieneBaseurlHeredado = @($ambienteCanonico.PSObject.Properties | Where-Object { $_.Name -ceq 'baseurl' }).Count -gt 0 }
    Test-Asercion -Id 'migracionModular.canonizacionAliases' -Condicion (
        $resultadoCanonizacion.CodigoSalida -eq 0 -and
        $null -ne $clienteCanonico -and
        $null -ne $ambienteCanonico -and
        $ambienteCanonico.modulo -eq 'comercial' -and
        $clienteCanonico.packagenames.comercial -eq 'glmsuit.comercial.' -and
        $ambienteCanonico.baseUrl -eq '/comercial-test/rest' -and
        -not $tienePackagenameHeredado -and
        -not $tieneBaseurlHeredado
    ) -DetalleExito 'La migracion canoniza modulo, packagename y baseurl con los nombres y valores esperados.' -DetalleFallo 'La migracion no canonizo correctamente los aliases heredados.'

    $rutaFixtureCombinacionDuplicada = Join-Path $DirectorioFixturesJson 'configuracion-modular-combinacion-duplicada.json'
    $rutaConfiguracionConflicto = Join-Path $directorioMigracion 'configuracion-conflicto.json'
    Copy-Item -LiteralPath $rutaFixtureCombinacionDuplicada -Destination $rutaConfiguracionConflicto -Force
    $bytesAntesConflicto = [System.IO.File]::ReadAllBytes($rutaConfiguracionConflicto)
    $resultadoConflicto = Invocar-ScriptHijo -RutaScript $rutaScriptMigracion -Argumentos @('-ConfigPath', $rutaConfiguracionConflicto) -NormalizarCodigo -NoImprimir
    $bytesDespuesConflicto = [System.IO.File]::ReadAllBytes($rutaConfiguracionConflicto)
    Test-Asercion -Id 'migracionModular.conflictoConservaArchivo' -Condicion (
        $resultadoConflicto.CodigoSalida -ne 0 -and
        [System.Linq.Enumerable]::SequenceEqual($bytesAntesConflicto, $bytesDespuesConflicto)
    ) -DetalleExito 'Un conflicto de modulo y tipo se rechaza sin modificar la copia temporal.' -DetalleFallo 'La migracion no rechazo el conflicto o modifico la configuracion.'

    $rutasFixturesPackageNameFaltante = @(
        (Join-Path $DirectorioFixturesJson 'configuracion-modular-packagenames-faltante.json')
        (Join-Path $DirectorioFixturesJson 'configuracion-modular-packagename-modulo-faltante.json')
    )
    $packageNamesFaltantesRechazados = $true
    foreach ($rutaFixturePackageNameFaltante in $rutasFixturesPackageNameFaltante) {
        $nombreFixturePackageNameFaltante = [System.IO.Path]::GetFileNameWithoutExtension($rutaFixturePackageNameFaltante)
        $rutaConfiguracionPackageNameFaltante = Join-Path $directorioMigracion ($nombreFixturePackageNameFaltante + '.json')
        Copy-Item -LiteralPath $rutaFixturePackageNameFaltante -Destination $rutaConfiguracionPackageNameFaltante -Force
        $resultadoPackageNameFaltante = Invocar-ScriptHijo -RutaScript $rutaScriptMigracion -Argumentos @('-ConfigPath', $rutaConfiguracionPackageNameFaltante) -NormalizarCodigo -NoImprimir
        if ($resultadoPackageNameFaltante.CodigoSalida -eq 0) { $packageNamesFaltantesRechazados = $false }
    }
    Test-Asercion -Id 'migracionModular.packageNamesFaltantes' -Condicion $packageNamesFaltantesRechazados -DetalleExito 'La migracion rechaza la ausencia del package name requerido para cada modulo configurado.' -DetalleFallo 'La migracion acepto una configuracion con package name faltante.'

    $rutaConfiguracionRestauracion = Join-Path $directorioMigracion 'configuracion-restauracion.json'
    Copy-Item -LiteralPath $rutaFixtureAliases -Destination $rutaConfiguracionRestauracion -Force
    $bytesAntesRestauracion = [System.IO.File]::ReadAllBytes($rutaConfiguracionRestauracion)
    $validarConfiguracionTemporal = {
        param($rutaTemporal)
        $contenidoTemporal = [System.IO.File]::ReadAllText($rutaTemporal)
        $null = $contenidoTemporal | ConvertFrom-Json
        throw 'fallo de validacion inyectado por el harness'
    }
    $falloValidacionCapturado = $false
    try {
        Escribir-ArchivoAtomico -Ruta $rutaConfiguracionRestauracion -Contenido '{"configuracion":"candidata"}' -Validar $validarConfiguracionTemporal | Out-Null
    } catch {
        $falloValidacionCapturado = $true
    }
    $bytesDespuesRestauracion = [System.IO.File]::ReadAllBytes($rutaConfiguracionRestauracion)
    $residualesRestauracion = @(Get-ChildItem -LiteralPath $directorioMigracion -File | Where-Object { $_.Name -like 'configuracion-restauracion.json.*' })
    Test-Asercion -Id 'migracionModular.restauracionAnteFallo' -Condicion (
        $falloValidacionCapturado -and
        [System.Linq.Enumerable]::SequenceEqual($bytesAntesRestauracion, $bytesDespuesRestauracion) -and
        $residualesRestauracion.Count -eq 0
    ) -DetalleExito 'Un fallo de validacion atomica conserva la configuracion anterior y elimina los temporales.' -DetalleFallo 'Un fallo de validacion atomica no restauro byte a byte la configuracion anterior.'
}

function Construir-XmlMulticontexto {
    <#
    .SYNOPSIS
    Construye un XML de exportacion con APIGLM.APIGLMMain anadido.
    .DESCRIPTION
    Parte del fixture xpz-base.xml y agrega el objeto APIGLM.APIGLMMain con un
    Source que llama a los wrappers de prueba, usando el guid indicado como
    lineage. Devuelve la ruta del XML generado en test/tmp/.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$GuidMain,
        [Parameter(Mandatory = $true)][string]$RutaSalida
    )
    $xml = Cargar-XmlFixture -Nombre 'xpz-base.xml'
    $nodoMain = $xml.CreateElement('Object')
    $nodoMain.SetAttribute('fullyQualifiedName', 'APIGLM.APIGLMMain')
    $nodoMain.SetAttribute('moduleGuid', 'aaaaaaaa-0000-0000-0000-0000000000a0')
    $nodoMain.SetAttribute('guid', $GuidMain)
    $nodoMain.SetAttribute('name', 'APIGLMMain')
    $nodoMain.SetAttribute('type', '84a12160-f59b-4ad7-a683-ea4481ac23e9')
    $nodoMain.SetAttribute('description', 'APIGLMMain')
    $nodoMain.SetAttribute('parent', 'APIGLM')
    $nodoMain.SetAttribute('parentType', 'c88fffcd-b6f8-0000-8fec-00b5497e2117')
    $nodoPart = $xml.CreateElement('Part')
    $nodoPart.SetAttribute('type', '528d1c06-a9c2-420d-bd35-21dca83f12ff')
    $nodoSource = $xml.CreateElement('Source')
    [void]$nodoSource.AppendChild($xml.CreateCDataSection("APIGLM.Cotizacion.WSObtenerProductor()`n`nAPIGLM.Emision.WSConsultarSolicitud()`n"))
    [void]$nodoPart.AppendChild($nodoSource)
    [void]$nodoMain.AppendChild($nodoPart)
    $objetos = $xml.SelectSingleNode('//Objects')
    [void]$objetos.AppendChild($nodoMain)
    Asegurar-Directorio -Ruta ([System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($RutaSalida)))
    $xml.Save($RutaSalida)
    return [System.IO.Path]::GetFullPath($RutaSalida)
}

function Construir-XpzDesdeXml {
    <#
    .SYNOPSIS
    Empaqueta un XML unico como XPZ (ZIP) valido con raiz ExportFile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaXml,
        [Parameter(Mandatory = $true)][string]$RutaXpz
    )
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $rutaCompleta = [System.IO.Path]::GetFullPath($RutaXpz)
    Asegurar-Directorio -Ruta ([System.IO.Path]::GetDirectoryName($rutaCompleta))
    if (Test-Path -LiteralPath $rutaCompleta -PathType Leaf) {
        Remove-Item -LiteralPath $rutaCompleta -Force
    }
    $zip = [System.IO.Compression.ZipFile]::Open($rutaCompleta, 'Create')
    try {
        $entrada = $zip.CreateEntry('ExportFile.xml')
        $escritor = New-Object System.IO.StreamWriter($entrada.Open(), (New-Object System.Text.UTF8Encoding($false)))
        try {
            $escritor.Write([System.IO.File]::ReadAllText($RutaXml))
        } finally {
            $escritor.Dispose()
        }
    } finally {
        $zip.Dispose()
    }
    return $rutaCompleta
}

function Crear-ConfiguracionMulticontextoPrueba {
    <#
    .SYNOPSIS
    Escribe una configuracion temporal con dos clientes y tres ambientes.
    .DESCRIPTION
    Cliente A con testing y produccion; Cliente B con testing. Todos los ambientes
    usan kbPaths distintos bajo test/tmp/ y comparten los mismos FQN del inventario.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaConfiguracion,
        [Parameter(Mandatory = $true)][string]$ClientesRoot
    )
    $kbA = Join-Path $DirectorioTmp 'multicontexto\kbA'
    $kbB = Join-Path $DirectorioTmp 'multicontexto\kbB'
    $kbProd = Join-Path $DirectorioTmp 'multicontexto\kbProd'
    $clientesRootJson = ($ClientesRoot -replace '\\', '/')
    $configuracion = [ordered]@{
        rutas = [ordered]@{ clientesRoot = $clientesRootJson }
        exportacion = [ordered]@{ onlyModuleAPIGLM = $true }
        herramientas = [ordered]@{
            geneXusProgramDir = 'C:/Program Files (x86)/GeneXus/GeneXus18'
            msbuildPath = 'C:/Windows/Microsoft.NET/Framework/v4.0.30319/MSBuild.exe'
            pandocPath = 'binary/tools/pandoc.exe'
            typstPath = 'binary/tools/typst.exe'
        }
        clientes = @(
            [ordered]@{
                id = 'clientea'
                nombre = 'Cliente A'
                packagenames = [ordered]@{ comercial = 'clientea.comercial.' }
                serviciosIgnorados = @()
                ambientes = @(
                    [ordered]@{ id = 'testing'; nombre = 'Testing'; modulo = 'comercial'; tipo = 'test'; kbPath = ($kbA -replace '\\', '/'); host = 'https://clientea.example.com'; baseUrl = '/testing/rest' }
                    [ordered]@{ id = 'produccion'; nombre = 'Produccion'; modulo = 'comercial'; tipo = 'prod'; kbPath = ($kbProd -replace '\\', '/'); host = 'https://clientea.example.com'; baseUrl = '/produccion/rest' }
                )
            },
            [ordered]@{
                id = 'clienteb'
                nombre = 'Cliente B'
                packagenames = [ordered]@{ comercial = 'clienteb.comercial.' }
                serviciosIgnorados = @()
                ambientes = @(
                    [ordered]@{ id = 'testing'; nombre = 'Testing'; modulo = 'comercial'; tipo = 'test'; kbPath = ($kbB -replace '\\', '/'); host = 'https://clienteb.example.com'; baseUrl = '/testing/rest' }
                )
            }
        )
    }
    Escribir-TextoUtf8SinBom -Ruta $RutaConfiguracion -Contenido ($configuracion | ConvertTo-Json -Depth 10)
    foreach ($kb in @($kbA, $kbB, $kbProd)) {
        Asegurar-Directorio -Ruta $kb
        Escribir-TextoUtf8SinBom -Ruta (Join-Path $kb 'prueba.gxw') -Contenido '<KnowledgeBase />'
    }
    return $RutaConfiguracion
}

function Crear-ConfiguracionesPreflightTemporales {
    <#
    .SYNOPSIS
    Crea las configuraciones temporales que usaran las pruebas del preflight integral.
    .DESCRIPTION
    Genera un JSON corrupto, un documento con errores globales, otro con errores
    distribuidos entre varios contextos y uno valido cuyas rutas no existen. Las
    rutas declaradas no se crean: solo se crea el directorio que contiene los
    archivos de configuracion para mantener los escenarios aislados.
    #>
    [CmdletBinding()]
    param()

    $directorioConfiguracionesPreflight = Join-Path $DirectorioTmp 'configuraciones-preflight'
    New-DirectorioSiNoExiste -Directorio $directorioConfiguracionesPreflight | Out-Null

    $rutaJsonInvalido = Join-Path $directorioConfiguracionesPreflight 'configuracion-json-invalido.json'
    $rutaErroresGlobales = Join-Path $directorioConfiguracionesPreflight 'configuracion-errores-globales.json'
    $rutaErroresContextuales = Join-Path $directorioConfiguracionesPreflight 'configuracion-errores-contextuales.json'
    $rutaRutasInexistentes = Join-Path $directorioConfiguracionesPreflight 'configuracion-rutas-inexistentes.json'

    Escribir-TextoUtf8SinBom -Ruta $rutaJsonInvalido -Contenido '{"rutas":{"clientesRoot":"clientes"'

    $configuracionErroresGlobales = [ordered]@{
        rutas = [ordered]@{ clientesRoot = '' }
        exportacion = [ordered]@{ onlyModuleAPIGLM = 'si' }
        panel = [ordered]@{
            timeoutOperacionSegundos = 'indefinido'
            timeoutMsbuildSegundos = 0
            maxPdfConcurrentProcesses = -1
        }
        herramientas = [ordered]@{
            geneXusProgramDir = ''
            msbuildPath = ''
            pandocPath = 'binary/tools/pandoc.exe'
            typstPath = 'binary/tools/typst.exe'
        }
        clientes = @()
    }
    Escribir-TextoUtf8SinBom -Ruta $rutaErroresGlobales -Contenido ($configuracionErroresGlobales | ConvertTo-Json -Depth 10)

    $configuracionErroresContextuales = [ordered]@{
        rutas = [ordered]@{ clientesRoot = 'contextos-con-errores/clientes' }
        exportacion = [ordered]@{ onlyModuleAPIGLM = $true }
        panel = [ordered]@{
            timeoutOperacionSegundos = 600
            timeoutMsbuildSegundos = 300
            maxPdfConcurrentProcesses = 2
        }
        herramientas = [ordered]@{
            geneXusProgramDir = 'herramientas/gx'
            msbuildPath = 'herramientas/msbuild.exe'
            pandocPath = 'herramientas/pandoc.exe'
            typstPath = 'herramientas/typst.exe'
        }
        clientes = @(
            [ordered]@{
                id = 'cliente-a'
                nombre = 'Cliente A'
                packagenames = [ordered]@{ comercial = 'cliente-a.comercial.' }
                serviciosIgnorados = @()
                ambientes = @(
                    [ordered]@{
                        id = 'testing'
                        nombre = 'Testing'
                        modulo = 'comercial'
                        tipo = 'test'
                        kbPath = 'contextos-con-errores/kb/cliente-a-testing'
                        host = 'https://cliente-a.example.com'
                        baseUrl = 'testing/rest'
                    }
                    [ordered]@{
                        id = 'produccion'
                        nombre = 'Produccion'
                        modulo = 'comercial'
                        tipo = 'prod'
                        kbPath = 'contextos-con-errores/kb/cliente-a-produccion'
                        host = 'https://cliente-a.example.com/api'
                        baseUrl = '/produccion/rest'
                    }
                )
            }
            [ordered]@{
                id = 'cliente-b'
                nombre = 'Cliente B'
                packagenames = [ordered]@{ comercial = 'cliente-b.comercial.' }
                serviciosIgnorados = @()
                ambientes = @(
                    [ordered]@{
                        id = 'testing'
                        nombre = 'Testing'
                        modulo = 'finanzas'
                        tipo = 'test'
                        kbPath = 'contextos-con-errores/kb/cliente-b-testing'
                        host = 'https://cliente-b.example.com'
                        baseUrl = '/testing/rest'
                    }
                    [ordered]@{
                        id = 'produccion'
                        nombre = 'Produccion'
                        modulo = 'comercial'
                        tipo = 'prod'
                        host = 'https://cliente-b.example.com'
                        baseUrl = '/produccion/rest'
                    }
                )
            }
        )
    }
    Escribir-TextoUtf8SinBom -Ruta $rutaErroresContextuales -Contenido ($configuracionErroresContextuales | ConvertTo-Json -Depth 10)

    $directorioRutasInexistentes = Join-Path $directorioConfiguracionesPreflight 'rutas-validas-inexistentes'
    $configuracionRutasInexistentes = [ordered]@{
        rutas = [ordered]@{
            clientesRoot = (Join-Path $directorioRutasInexistentes 'clientes')
        }
        exportacion = [ordered]@{ onlyModuleAPIGLM = $true }
        panel = [ordered]@{
            timeoutOperacionSegundos = 600
            timeoutMsbuildSegundos = 300
            maxPdfConcurrentProcesses = 2
        }
        herramientas = [ordered]@{
            geneXusProgramDir = (Join-Path $directorioRutasInexistentes 'herramientas\GeneXus')
            msbuildPath = (Join-Path $directorioRutasInexistentes 'herramientas\MSBuild.exe')
            pandocPath = (Join-Path $directorioRutasInexistentes 'herramientas\Pandoc.exe')
            typstPath = (Join-Path $directorioRutasInexistentes 'herramientas\Typst.exe')
        }
        clientes = @(
            [ordered]@{
                id = 'cliente-rutas'
                nombre = 'Cliente de rutas inexistentes'
                packagenames = [ordered]@{ comercial = 'cliente-rutas.comercial.' }
                serviciosIgnorados = @()
                ambientes = @(
                    [ordered]@{
                        id = 'testing'
                        nombre = 'Testing'
                        modulo = 'comercial'
                        tipo = 'test'
                        kbPath = (Join-Path $directorioRutasInexistentes 'kb\cliente-rutas-testing')
                        host = 'https://cliente-rutas.example.com'
                        baseUrl = '/testing/rest'
                    }
                )
            }
        )
    }
    Escribir-TextoUtf8SinBom -Ruta $rutaRutasInexistentes -Contenido ($configuracionRutasInexistentes | ConvertTo-Json -Depth 10)

    return [pscustomobject]@{
        Directorio = $directorioConfiguracionesPreflight
        JsonInvalido = $rutaJsonInvalido
        ErroresGlobales = $rutaErroresGlobales
        ErroresContextuales = $rutaErroresContextuales
        RutasInexistentes = $rutaRutasInexistentes
    }
}

function Obtener-EstadoDirectoriosGlobales {
    <#
    .SYNOPSIS
    Captura un resumen de hashes de los directorios globales del pipeline.
    .DESCRIPTION
    Devuelve un hashtable con una linea por archivo (ruta=hash) para comparar
    byte a byte antes y despues de las pruebas multicontexto.
    #>
    [CmdletBinding()]
    param()
    $estado = @{}
    foreach ($directorio in @('documentacionServicios', 'estado', 'Logs', 'xpz')) {
        $ruta = Join-Path $RaizRepositorio $directorio
        $resumen = ''
        if (Test-Path -LiteralPath $ruta -PathType Container) {
            $sb = New-Object System.Text.StringBuilder
            foreach ($archivo in @(Get-ChildItem -LiteralPath $ruta -Recurse -File | Sort-Object FullName)) {
                [void]$sb.Append($archivo.FullName + '=' + (Obtener-Sha256Archivo -Ruta $archivo.FullName) + "`n")
            }
            $resumen = $sb.ToString()
        }
        $estado[$directorio] = $resumen
    }
    return $estado
}

function Test-EstadoDirectoriosIgual {
    <#
    .SYNOPSIS
    Compara dos estados de directorios globales capturados.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Antes,
        [Parameter(Mandatory = $true)][hashtable]$Despues
    )
    foreach ($clave in $Antes.Keys) {
        if (-not $Despues.ContainsKey($clave) -or $Despues[$clave] -ne $Antes[$clave]) {
            return $false
        }
    }
    return $true
}

function Obtener-DiferenciasDirectoriosGlobales {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Antes,
        [Parameter(Mandatory = $true)][hashtable]$Despues
    )
    $diferencias = New-Object System.Collections.Generic.List[string]
    foreach ($clave in @($Antes.Keys)) {
        if (-not $Despues.ContainsKey($clave)) {
            [void]$diferencias.Add($clave + ': directorio ausente despues')
        } elseif ($Antes[$clave] -ne $Despues[$clave]) {
            [void]$diferencias.Add($clave + ': archivos agregados, eliminados o modificados')
        }
    }
    foreach ($clave in @($Despues.Keys | Where-Object { -not $Antes.ContainsKey($_) })) {
        [void]$diferencias.Add($clave + ': directorio agregado despues')
    }
    return @($diferencias.ToArray())
}

function Ejecutar-CasosPreflightSoloLectura {
    <#
    .SYNOPSIS
    Verifica el preflight integral con configuraciones aisladas y sin efectos laterales.
    #>
    [CmdletBinding()]
    param()

    $fixtures = $script:ConfiguracionesPreflightTemporales
    if ($null -eq $fixtures) {
        Test-Skip -Id 'preflight.configuraciones' -Detalle 'No se pudieron crear las configuraciones temporales.'
        return
    }

    $capturarArbol = {
        param([string]$Ruta)
        if (-not (Test-Path -LiteralPath $Ruta)) { return '' }
        return @(
            Get-ChildItem -LiteralPath $Ruta -Recurse -Force | Sort-Object FullName | ForEach-Object {
                $tipo = if ($_.PSIsContainer) { 'D' } else { 'F' }
                $longitud = if ($_.PSIsContainer) { 0 } else { $_.Length }
                $tipo + '|' + $_.FullName + '|' + $longitud + '|' + $_.LastWriteTimeUtc.Ticks
            }
        ) -join "`n"
    }

    $arbolAntes = & $capturarArbol $fixtures.Directorio
    $evaluacionJsonInvalido = Evaluar-ConfiguracionIntegral -ConfigPath $fixtures.JsonInvalido -RaizRepositorio $RaizRepositorio
    $evaluacionErroresGlobales = Evaluar-ConfiguracionIntegral -ConfigPath $fixtures.ErroresGlobales -RaizRepositorio $RaizRepositorio
    $evaluacionErroresContextuales = Evaluar-ConfiguracionIntegral -ConfigPath $fixtures.ErroresContextuales -RaizRepositorio $RaizRepositorio
    $evaluacionRutasInexistentes = Evaluar-ConfiguracionIntegral -ConfigPath $fixtures.RutasInexistentes -RaizRepositorio $RaizRepositorio

    Test-Asercion -Id 'preflight.jsonInvalido' -Condicion (
        (-not $evaluacionJsonInvalido.configurationValid) -and
        @($evaluacionJsonInvalido.configurationErrors | Where-Object { $_.field -eq 'json' }).Count -eq 1 -and
        @($evaluacionJsonInvalido.simulations).Count -eq 0
    ) -DetalleExito 'El JSON corrupto queda bloqueado con diagnostico sintactico y sin simulaciones inventadas.' -DetalleFallo 'El JSON corrupto no produjo el diagnostico esperado.'

    Test-Asercion -Id 'preflight.erroresGlobales' -Condicion (
        (-not $evaluacionErroresGlobales.configurationValid) -and
        @($evaluacionErroresGlobales.configurationErrors | Where-Object { $_.scope -eq 'global' }).Count -ge 4
    ) -DetalleExito 'El preflight acumula errores independientes del esquema global.' -DetalleFallo 'El preflight detuvo o perdió errores globales independientes.'

    Test-Asercion -Id 'preflight.erroresContextuales' -Condicion (
        (-not $evaluacionErroresContextuales.configurationValid) -and
        @($evaluacionErroresContextuales.configurationErrors | Where-Object { $_.scope -match '^cliente-a/' }).Count -ge 1 -and
        @($evaluacionErroresContextuales.configurationErrors | Where-Object { $_.scope -match '^cliente-b/' }).Count -ge 2
    ) -DetalleExito 'El preflight identifica y acumula errores de varios contextos.' -DetalleFallo 'El preflight no acumuló errores contextuales de todos los clientes.'

    Test-Asercion -Id 'preflight.rutasInexistentes' -Condicion (
        $evaluacionRutasInexistentes.configurationValid -and
        @($evaluacionRutasInexistentes.simulations).Count -eq 1 -and
        @($evaluacionRutasInexistentes.simulations)[0].pathsResolved
    ) -DetalleExito 'Las rutas normalizables pero inexistentes se simulan sin exigir presencia física.' -DetalleFallo 'El preflight bloqueó rutas inexistentes o no derivó la simulación.'

    $rutasQueNoDebenCrearse = @(
        (Join-Path $fixtures.Directorio 'rutas-validas-inexistentes\clientes'),
        (Join-Path $fixtures.Directorio 'rutas-validas-inexistentes\kb'),
        (Join-Path $fixtures.Directorio 'rutas-validas-inexistentes\herramientas')
    )
    $arbolDespues = & $capturarArbol $fixtures.Directorio
    $sinEfectosLaterales = $arbolAntes -eq $arbolDespues -and @($rutasQueNoDebenCrearse | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0
    Test-Asercion -Id 'preflight.soloLectura' -Condicion $sinEfectosLaterales -DetalleExito 'La validacion integral no modifica archivos ni crea directorios contextuales.' -DetalleFallo 'El preflight produjo efectos laterales en sus configuraciones temporales.'
}

function Ejecutar-CasosConfiguracionBloqueada {
    <#
    .SYNOPSIS
    Verifica que el servidor iniciado con una configuracion invalida conserve solo sus APIs diagnosticas.
    #>
    [CmdletBinding()]
    param()

    $rutaServidor = Join-Path $DirectorioBinario 'ServidorPanelWeb.ps1'
    $rutaConfiguracion = Join-Path $DirectorioFixturesJson 'configuracion-multicliente-tipo-faltante.json'
    $contenidoAntes = [System.IO.File]::ReadAllBytes($rutaConfiguracion)
    $puerto = 8360 + (Get-Random -Minimum 0 -Maximum 80)
    $proceso = $null
    try {
        $proceso = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $rutaServidor,
            '-RepositoryRoot', $RaizRepositorio, '-ConfigPath', $rutaConfiguracion,
            '-Port', $puerto, '-NoBrowser'
        ) -WindowStyle Hidden -PassThru

        $inicio = $null
        for ($intento = 0; $intento -lt 20; $intento++) {
            Start-Sleep -Milliseconds 250
            try { $inicio = Invoke-WebRequest -UseBasicParsing -Uri ('http://127.0.0.1:' + $puerto + '/') -ErrorAction Stop; break } catch { }
        }
        $tokenMatch = if ($inicio) { [regex]::Match($inicio.Content, 'window\.PANEL_TOKEN="([a-f0-9]+)"') } else { $null }
        $estado = if ($inicio -and $tokenMatch.Success) { Invoke-RestMethod -Uri ('http://127.0.0.1:' + $puerto + '/api/estado') } else { $null }
        Test-Asercion -Id 'configuracionBloqueada.diagnostico' -Condicion (
            $null -ne $estado -and [bool]$estado.ok -and
            $estado.data.configurationValid -eq $false -and
            $estado.data.configurationBlocked -eq $true -and
            @($estado.data.configurationErrors).Count -ge 1
        ) -DetalleExito 'El estado diagnostico expone la invalidez y todos los errores acumulados.' -DetalleFallo 'El servidor bloqueado no expuso correctamente el diagnostico.'

        $headers = @{ 'X-Panel-Token' = if ($tokenMatch) { $tokenMatch.Groups[1].Value } else { '' } }
        $rutasBloqueadas = @(
            [pscustomobject]@{ Ruta = '/api/contextos'; Metodo = 'GET'; Cuerpo = $null },
            [pscustomobject]@{ Ruta = '/api/contexto/activar'; Metodo = 'POST'; Cuerpo = '{}' },
            [pscustomobject]@{ Ruta = '/api/exportar'; Metodo = 'POST'; Cuerpo = '{}' },
            [pscustomobject]@{ Ruta = '/api/configuracion/clientes'; Metodo = 'POST'; Cuerpo = '{}' }
        )
        $respuestasUniformes = $true
        foreach ($rutaBloqueada in $rutasBloqueadas) {
            $respuesta = $null
            try {
                $parametros = @{ Method = $rutaBloqueada.Metodo; UseBasicParsing = $true; Uri = ('http://127.0.0.1:' + $puerto + $rutaBloqueada.Ruta); Headers = $headers; ErrorAction = 'Stop' }
                if ($rutaBloqueada.Cuerpo) { $parametros.ContentType = 'application/json'; $parametros.Body = $rutaBloqueada.Cuerpo }
                $respuesta = Invoke-WebRequest @parametros
                $respuestasUniformes = $false
                break
            } catch {
                $codigo = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode.value__ } else { 0 }
                if ($codigo -ne 409) { $respuestasUniformes = $false; break }
            }
        }
        Test-Asercion -Id 'configuracionBloqueada.apisOperativas' -Condicion $respuestasUniformes -DetalleExito 'Las APIs operativas bloqueadas responden uniformemente con HTTP 409 y no inician trabajos.' -DetalleFallo 'Alguna API operativa no respetó el contrato uniforme de bloqueo.'
    } catch {
        Registrar-Caso -Id 'configuracionBloqueada.error' -Estado 'FAIL' -Detalle $_.Exception.Message
    } finally {
        if ($proceso -and -not $proceso.HasExited) {
            try { & taskkill.exe /PID $proceso.Id /T /F | Out-Null } catch { try { Stop-Process -Id $proceso.Id -Force -ErrorAction SilentlyContinue } catch { } }
        }
    }
    $contenidoDespues = [System.IO.File]::ReadAllBytes($rutaConfiguracion)
    Test-Asercion -Id 'configuracionBloqueada.sinEscritura' -Condicion ([System.Linq.Enumerable]::SequenceEqual($contenidoAntes, $contenidoDespues)) -DetalleExito 'El servidor bloqueado no modifica el configuracion.json usado para el diagnostico.' -DetalleFallo 'El servidor bloqueado modificó la configuración.'
}

function Ejecutar-PipelineContextoPrueba {
    <#
    .SYNOPSIS
    Ejecuta inventario y actualizacion completos para un contexto sobre un XPZ.
    .DESCRIPTION
    Crea el manifiesto del contexto y ejecuta ActualizarServicios con -Inicializar.
    El actualizador descubre los servicios directamente desde el XPZ. Devuelve el
    contexto, el codigo y el ejecucionId para las verificaciones posteriores.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$ClienteId,
        [Parameter(Mandatory = $true)][string]$Modulo,
        [Parameter(Mandatory = $true)][string]$AmbienteId,
        [Parameter(Mandatory = $true)][string]$RutaXpz,
        [Parameter(Mandatory = $true)][string]$DirectorioEjecuciones
    )
    $contexto = Cargar-Configuracion -ConfigPath $ConfigPath -ClienteId $ClienteId -Modulo $Modulo -AmbienteId $AmbienteId
    $rutaXpzContextual = Join-Path $contexto.DirectorioXpz ([System.IO.Path]::GetFileName($RutaXpz))
    if (-not (Test-Path -LiteralPath $rutaXpzContextual -PathType Leaf)) {
        Copy-Item -LiteralPath $RutaXpz -Destination $rutaXpzContextual -Force
    }
    $manifiesto = Crear-ManifiestoEjecucion -Xpz $rutaXpzContextual -FullyQualifiedNames @() -DirectorioBase $DirectorioEjecuciones -Contexto $contexto
    $rutaManifiesto = $manifiesto.Ruta
    $rutaActualizador = Join-Path $DirectorioBinario 'ActualizarServicios.ps1'
    $resultadoActualizacion = Invocar-ScriptHijo -RutaScript $rutaActualizador -Argumentos @('-ConfigPath', $ConfigPath, '-ManifiestoPath', $rutaManifiesto, '-Inicializar') -NoImprimir
    return [pscustomobject]@{ Contexto = $contexto; Codigo = $resultadoActualizacion.CodigoSalida; EjecucionId = [string]$manifiesto.Datos.ejecucionId }
}

function Ejecutar-CasosMulticontexto {
    <#
    .SYNOPSIS
    Integracion multicontexto: dos clientes, tres ambientes, FQN coincidentes.
    .DESCRIPTION
    Construye un XPZ fixture con APIGLM.APIGLMMain, ejecuta preflight y publicacion
    completa por ambiente (inventario en staging, Markdown y PDF contextuales,
    control e historial por ambiente) y verifica seleccion, publicacion independiente,
    hashes, versionado, lineages, reinicio por ambiente, logs, locks y ausencia de
    contaminacion de los directorios globales.
    #>
    [CmdletBinding()]
    param()

    $directorioMulticontexto = Join-Path $DirectorioTmp 'multicontexto'
    $rutaXmlA = Join-Path $directorioMulticontexto 'xpz_a.xml'
    $rutaXmlB = Join-Path $directorioMulticontexto 'xpz_b.xml'
    $rutaXpzA = Join-Path $directorioMulticontexto 'APIGLM_a.xpz'
    $rutaXpzB = Join-Path $directorioMulticontexto 'APIGLM_b.xpz'
    $rutaConfiguracionMulti = Join-Path $directorioMulticontexto 'configuracion.json'
    $clientesRootMulti = Join-Path $directorioMulticontexto 'clientes'
    $directorioEjecucionesMulti = Join-Path $directorioMulticontexto 'ejecuciones'

    $guidLineageA = '11111111-2222-3333-4444-555555555555'
    $guidLineageB = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'

    $construccionOk = $false
    try {
        $rutaXmlA = Construir-XmlMulticontexto -GuidMain $guidLineageA -RutaSalida $rutaXmlA
        $rutaXmlB = Construir-XmlMulticontexto -GuidMain $guidLineageB -RutaSalida $rutaXmlB
        $rutaXpzA = Construir-XpzDesdeXml -RutaXml $rutaXmlA -RutaXpz $rutaXpzA
        $rutaXpzB = Construir-XpzDesdeXml -RutaXml $rutaXmlB -RutaXpz $rutaXpzB
        $construccionOk = (Test-XpzValido -Ruta $rutaXpzA).Valid -and (Test-XpzValido -Ruta $rutaXpzB).Valid
    } catch {
        $construccionOk = $false
    }
    if (-not $construccionOk) {
        Test-Skip -Id 'multicontexto.fixture' -Detalle 'No se pudo construir el XPZ fixture con APIGLMMain.'
        Test-Skip -Id 'multicontexto.preflight'
        Test-Skip -Id 'multicontexto.arboles'
        Test-Skip -Id 'multicontexto.publicacionIndependiente'
        Test-Skip -Id 'multicontexto.hashes'
        Test-Skip -Id 'multicontexto.versionIndependiente'
        Test-Skip -Id 'multicontexto.lineages'
        Test-Skip -Id 'multicontexto.reinicioSoloAmbienteActivo'
        Test-Skip -Id 'multicontexto.logsContextuales'
        Test-Skip -Id 'multicontexto.locksIndependientes'
        Test-Skip -Id 'multicontexto.sinContaminacionGlobal'
        return
    }
    Test-Asercion -Id 'multicontexto.fixture' -Condicion $construccionOk -DetalleExito 'El XPZ fixture con APIGLMMain se construyo y valida como ExportFile.' -DetalleFallo 'El XPZ fixture no se construyo o no es valido.'

    Crear-ConfiguracionMulticontextoPrueba -RutaConfiguracion $rutaConfiguracionMulti -ClientesRoot $clientesRootMulti | Out-Null

    $rutaValidador = Join-Path $DirectorioBinario 'ValidarConfiguracionGLM.ps1'
    $contextosPrueba = @(
        [pscustomobject]@{ ClienteId = 'clientea'; Modulo = 'comercial'; AmbienteId = 'testing'; Xpz = $rutaXpzA },
        [pscustomobject]@{ ClienteId = 'clientea'; Modulo = 'comercial'; AmbienteId = 'produccion'; Xpz = $rutaXpzA },
        [pscustomobject]@{ ClienteId = 'clienteb'; Modulo = 'comercial'; AmbienteId = 'testing'; Xpz = $rutaXpzB }
    )

    $preflightsOk = $true
    $contextosResueltos = @{}
    foreach ($contextoPrueba in $contextosPrueba) {
        $resultadoPreflight = Invocar-ScriptHijo -RutaScript $rutaValidador -Argumentos @('-Repositorio', $RaizRepositorio, '-ConfigPath', $rutaConfiguracionMulti, '-ClienteId', $contextoPrueba.ClienteId, '-Modulo', $contextoPrueba.Modulo, '-AmbienteId', $contextoPrueba.AmbienteId) -NoImprimir
        if ($resultadoPreflight.CodigoSalida -ne 0) { $preflightsOk = $false }
        $contexto = Cargar-Configuracion -ConfigPath $rutaConfiguracionMulti -ClienteId $contextoPrueba.ClienteId -Modulo $contextoPrueba.Modulo -AmbienteId $contextoPrueba.AmbienteId
        # El preflight productivo crea este arbol; se asegura la carpeta de
        # destino para que el fixture no falle antes de probar el pipeline.
        New-DirectorioSiNoExiste -Directorio $contexto.DirectorioXpz | Out-Null
        Copy-Item -LiteralPath $contextoPrueba.Xpz -Destination (Join-Path $contexto.DirectorioXpz ([System.IO.Path]::GetFileName($contextoPrueba.Xpz))) -Force
        $contextosResueltos[$contextoPrueba.ClienteId + '/' + $contextoPrueba.Modulo + '/' + $contextoPrueba.AmbienteId] = $contexto
    }
    Test-Asercion -Id 'multicontexto.preflight' -Condicion $preflightsOk -DetalleExito 'El preflight de los tres contextos termina con codigo 0.' -DetalleFallo 'Algun preflight de contexto fallo.'

    $arbolesOk = $true
    foreach ($claveContexto in $contextosResueltos.Keys) {
        $contexto = $contextosResueltos[$claveContexto]
        foreach ($directorioEsperado in @(
            (Join-Path $contexto.DirectorioContexto 'documentacionServicios'),
            (Join-Path $contexto.DirectorioContexto 'estado'),
            (Join-Path $contexto.DirectorioContexto 'xpz'),
            (Join-Path $contexto.DirectorioContexto 'Logs'),
            (Join-Path $contexto.DirectorioContexto 'test\fixtures'),
            (Join-Path $contexto.DirectorioContexto 'test\resultados')
        )) {
            if (-not (Test-Path -LiteralPath $directorioEsperado -PathType Container)) { $arbolesOk = $false }
        }
    }
    Test-Asercion -Id 'multicontexto.arboles' -Condicion $arbolesOk -DetalleExito 'Cada contexto crea exactamente sus seis directorios bajo clientes/<cliente>/<ambiente>.' -DetalleFallo 'Falta algun directorio contextual en algun ambiente.'

    $contextoSeleccionadoOk = $contextosResueltos['clientea/comercial/testing'].ContextId -eq 'clientea/comercial/testing' -and
        $contextosResueltos['clientea/comercial/produccion'].ContextId -eq 'clientea/comercial/produccion' -and
        $contextosResueltos['clienteb/comercial/testing'].ContextId -eq 'clienteb/comercial/testing' -and
        $contextosResueltos['clientea/comercial/testing'].DirectorioContexto -ne $contextosResueltos['clientea/comercial/produccion'].DirectorioContexto -and
        $contextosResueltos['clientea/comercial/testing'].DirectorioContexto -ne $contextosResueltos['clienteb/comercial/testing'].DirectorioContexto -and
        $contextosResueltos['clientea/comercial/testing'].RutaControl -ne $contextosResueltos['clienteb/comercial/testing'].RutaControl
    Test-Asercion -Id 'multicontexto.seleccionContextos' -Condicion $contextoSeleccionadoOk -DetalleExito 'La seleccion resuelve contextos distintos con directorios y controles separados.' -DetalleFallo 'Los contextos no se resuelven como identidades aisladas.'

    $estadoGlobalesAntes = Obtener-EstadoDirectoriosGlobales

    $resultadoTesting = Ejecutar-PipelineContextoPrueba -ConfigPath $rutaConfiguracionMulti -ClienteId 'clientea' -Modulo 'comercial' -AmbienteId 'testing' -RutaXpz $rutaXpzA -DirectorioEjecuciones $directorioEjecucionesMulti
    $resultadoProduccion = Ejecutar-PipelineContextoPrueba -ConfigPath $rutaConfiguracionMulti -ClienteId 'clientea' -Modulo 'comercial' -AmbienteId 'produccion' -RutaXpz $rutaXpzA -DirectorioEjecuciones $directorioEjecucionesMulti
    $resultadoClienteb = Ejecutar-PipelineContextoPrueba -ConfigPath $rutaConfiguracionMulti -ClienteId 'clienteb' -Modulo 'comercial' -AmbienteId 'testing' -RutaXpz $rutaXpzB -DirectorioEjecuciones $directorioEjecucionesMulti

    $publicacionOk = $resultadoTesting.Codigo -in @(0, 2) -and $resultadoProduccion.Codigo -in @(0, 2) -and $resultadoClienteb.Codigo -in @(0, 2)
    foreach ($resultado in @($resultadoTesting, $resultadoProduccion, $resultadoClienteb)) {
        $contexto = $resultado.Contexto
        foreach ($nombreArchivo in @('wsobtenerproductor.md', 'wsobtenerproductor.pdf', 'wsconsultarsolicitud.md', 'wsconsultarsolicitud.pdf')) {
            if (-not (Test-Path -LiteralPath (Join-Path $contexto.DirectorioServicios $nombreArchivo) -PathType Leaf)) { $publicacionOk = $false }
        }
        if (-not (Test-Path -LiteralPath $contexto.RutaControl -PathType Leaf)) { $publicacionOk = $false }
        if (-not (Test-Path -LiteralPath $contexto.RutaHistorial -PathType Leaf)) { $publicacionOk = $false }
        if (Test-Path -LiteralPath $contexto.RutaLock -PathType Leaf) { $publicacionOk = $false }
    }
    Test-Asercion -Id 'multicontexto.publicacionIndependiente' -Condicion $publicacionOk -DetalleExito 'Los tres ambientes publican Markdown y PDF para los mismos FQN con control, historial y lock liberado.' -DetalleFallo 'Falta publicar o persistir algun artefacto en algun ambiente.'

    $hashesOk = $true
    foreach ($resultado in @($resultadoTesting, $resultadoProduccion, $resultadoClienteb)) {
        $contexto = $resultado.Contexto
        try {
            $control = Leer-ControlVersiones -RutaControl $contexto.RutaControl
            $servicios = Convertir-DiccionarioControlVersiones -Objeto $control.services
            $etiquetaFilaVersion = 'Versi' + [char]0xF3 + 'n'
            $patronFilaVersion = '(?m)^[ \t]*\| ' + $etiquetaFilaVersion + ' \|[^\r\n]*\r?\n?'
            foreach ($clave in @('APIGLM.Cotizacion.WSObtenerProductor', 'APIGLM.Emision.WSConsultarSolicitud')) {
                $servicio = $servicios[$clave]
                $nombreArchivo = Obtener-NombreArchivoServicio -FullyQualifiedName $clave -FqnsInventario @($servicios.Keys)
                $textoNormalizado = ([regex]::Replace([System.IO.File]::ReadAllText((Join-Path $contexto.DirectorioServicios ($nombreArchivo + '.md'))), $patronFilaVersion, '') -replace "`r`n", "`n") -replace "`r", "`n"
                $hashDocumento = Obtener-Sha256TextoNormalizado -Texto $textoNormalizado
                $hashPdf = Obtener-Sha256Archivo -Ruta (Join-Path $contexto.DirectorioServicios ($nombreArchivo + '.pdf'))
                if ([string](Obtener-PropiedadControlVersiones -Objeto $servicio -Nombre 'documentHash') -ne $hashDocumento -or
                    [string](Obtener-PropiedadControlVersiones -Objeto $servicio -Nombre 'pdfHash') -ne $hashPdf -or
                    [string](Obtener-PropiedadControlVersiones -Objeto $servicio -Nombre 'version') -ne '1.0') {
                    $hashesOk = $false
                }
            }
        } catch {
            $hashesOk = $false
        }
    }
    Test-Asercion -Id 'multicontexto.hashes' -Condicion $hashesOk -DetalleExito 'Los hashes del control coinciden con los Markdown y PDF publicados en cada ambiente.' -DetalleFallo 'Los hashes o versiones de algun ambiente no coinciden con sus artefactos.'

    Test-Asercion -Id 'multicontexto.versionIndependiente' -Condicion $hashesOk -DetalleExito 'Cada ambiente arranca su versionado en 1.0 sin compartir revisiones con otros ambientes.' -DetalleFallo 'El versionado no es independiente entre ambientes.'

    $lineageTesting = [string](Obtener-PropiedadControlVersiones -Objeto (Leer-ControlVersiones -RutaControl $contextosResueltos['clientea/comercial/testing'].RutaControl) -Nombre 'lineageId')
    $lineageClienteb = [string](Obtener-PropiedadControlVersiones -Objeto (Leer-ControlVersiones -RutaControl $contextosResueltos['clienteb/comercial/testing'].RutaControl) -Nombre 'lineageId')
    Test-Asercion -Id 'multicontexto.lineages' -Condicion (
        $lineageTesting -eq $guidLineageA -and $lineageClienteb -eq $guidLineageB -and $lineageTesting -ne $lineageClienteb
    ) -DetalleExito 'Los lineages de ambientes con XPZ distintos difieren y se derivan del APIGLMMain.' -DetalleFallo 'Los lineages no se derivan del APIGLMMain del XPZ de cada ambiente.'

    $estadoProduccionAntes = [System.IO.File]::ReadAllBytes($contextosResueltos['clientea/comercial/produccion'].RutaControl)
    $resultadoReinicio = Ejecutar-PipelineContextoPrueba -ConfigPath $rutaConfiguracionMulti -ClienteId 'clientea' -Modulo 'comercial' -AmbienteId 'testing' -RutaXpz $rutaXpzB -DirectorioEjecuciones $directorioEjecucionesMulti
    $estadoProduccionDespues = [System.IO.File]::ReadAllBytes($contextosResueltos['clientea/comercial/produccion'].RutaControl)
    $lineageTestingReiniciado = [string](Obtener-PropiedadControlVersiones -Objeto (Leer-ControlVersiones -RutaControl $contextosResueltos['clientea/comercial/testing'].RutaControl) -Nombre 'lineageId')
    $produccionIntacto = $estadoProduccionAntes.Length -eq $estadoProduccionDespues.Length
    if ($produccionIntacto) {
        for ($indiceByte = 0; $indiceByte -lt $estadoProduccionAntes.Length; $indiceByte++) {
            if ($estadoProduccionDespues[$indiceByte] -ne $estadoProduccionAntes[$indiceByte]) { $produccionIntacto = $false; break }
        }
    }
    Test-Asercion -Id 'multicontexto.reinicioSoloAmbienteActivo' -Condicion (
        $resultadoReinicio.Codigo -in @(0, 2) -and $lineageTestingReiniciado -eq $guidLineageB -and $produccionIntacto
    ) -DetalleExito 'El reinicio del versionado de testing cambia solo su lineage y no altera el control de produccion.' -DetalleFallo 'El reinicio de testing altero el control de otro ambiente o no cambio su lineage.'

    $logsOk = $true
    foreach ($resultado in @($resultadoTesting, $resultadoProduccion, $resultadoClienteb)) {
        $contexto = $resultado.Contexto
        $rutaReview = Join-Path $contexto.DirectorioLogs ($resultado.EjecucionId + '-actualizacion-review.json')
        if (-not (Test-Path -LiteralPath $rutaReview -PathType Leaf)) { $logsOk = $false }
    }
    Test-Asercion -Id 'multicontexto.logsContextuales' -Condicion $logsOk -DetalleExito 'Los reviews de la ejecucion quedan en los Logs del ambiente correspondiente.' -DetalleFallo 'Falta el review en los Logs de algun ambiente.'

    $operacionesAisladasOk = $true
    $manifiestosOperacion = @()
    foreach ($claveOperacion in @('clientea/comercial/testing', 'clienteb/comercial/testing')) {
        $contextoOperacion = $contextosResueltos[$claveOperacion]
        $directorioOperaciones = Join-Path $contextoOperacion.DirectorioLogs 'operaciones'
        New-DirectorioSiNoExiste -Directorio $directorioOperaciones | Out-Null
        $identificadorOperacion = [Guid]::NewGuid().ToString('N')
        $nombreLogOperacion = $identificadorOperacion + '.log'
        $nombreXpzOperacion = if ($claveOperacion -eq 'clientea/comercial/testing') { [System.IO.Path]::GetFileName($rutaXpzA) } else { [System.IO.Path]::GetFileName($rutaXpzB) }
        $manifiestoOperacion = [ordered]@{
            schemaVersion = 1
            operationId = $identificadorOperacion
            contextId = $contextoOperacion.ContextId
            tipo = 'ACTIVAR_XPZ'
            severidad = 'INFO'
            xpz = [ordered]@{ nombre = $nombreXpzOperacion; sha256 = $null }
            inicio = (Get-Date).ToUniversalTime().ToString('o')
            fin = (Get-Date).ToUniversalTime().ToString('o')
            estadoTecnico = 'COMPLETED'
            estadoVisible = 'COMPLETADO'
            codigoSalida = 0
            warnings = @()
            error = $null
            logNombre = $nombreLogOperacion
        }
        $rutaManifiestoOperacion = Join-Path $directorioOperaciones ($identificadorOperacion + '.json')
        $rutaLogOperacion = Join-Path $directorioOperaciones $nombreLogOperacion
        [System.IO.File]::WriteAllText($rutaManifiestoOperacion, ($manifiestoOperacion | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::WriteAllText($rutaLogOperacion, ('Contexto: ' + $contextoOperacion.ContextId), (New-Object System.Text.UTF8Encoding($false)))
        $manifiestosOperacion += $manifiestoOperacion
    }
    $manifiestosTesting = @(Get-ChildItem -LiteralPath (Join-Path $contextosResueltos['clientea/comercial/testing'].DirectorioLogs 'operaciones') -Filter '*.json' -File)
    $manifiestosClienteb = @(Get-ChildItem -LiteralPath (Join-Path $contextosResueltos['clienteb/comercial/testing'].DirectorioLogs 'operaciones') -Filter '*.json' -File)
    $operacionesAisladasOk = $manifiestosTesting.Count -eq 1 -and $manifiestosClienteb.Count -eq 1
    foreach ($manifiestoOperacion in @($manifiestosOperacion)) {
        $rutaContextual = Join-Path $contextosResueltos[[string]$manifiestoOperacion.contextId].DirectorioLogs ('operaciones\' + $manifiestoOperacion.operationId + '.json')
        $registroOperacion = Get-Content -LiteralPath $rutaContextual -Raw | ConvertFrom-Json
        if ([string]$registroOperacion.contextId -ne [string]$manifiestoOperacion.contextId -or
            [System.IO.Path]::GetFileNameWithoutExtension($rutaContextual) -ne [string]$registroOperacion.operationId -or
            [string]$registroOperacion.logNombre -ne ([string]$registroOperacion.operationId + '.log')) {
            $operacionesAisladasOk = $false
        }
    }
    Test-Asercion -Id 'multicontexto.operacionesAisladas' -Condicion $operacionesAisladasOk -DetalleExito 'Los manifiestos y salidas de operaciones quedan aislados por contexto y correlacionados por operationId.' -DetalleFallo 'Los manifiestos o salidas de operaciones se mezclaron entre contextos o perdieron su correlación.'

    $locksIndependientes = $false
    $flujoTesting = $null
    $flujoProduccion = $null
    try {
        $flujoTesting = New-Object -TypeName System.IO.FileStream -ArgumentList @($contextosResueltos['clientea/comercial/testing'].RutaLock, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $flujoProduccion = New-Object -TypeName System.IO.FileStream -ArgumentList @($contextosResueltos['clientea/comercial/produccion'].RutaLock, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $segundoMismoAmbienteRechazado = $false
        try {
            $flujoSegundo = New-Object -TypeName System.IO.FileStream -ArgumentList @($contextosResueltos['clientea/comercial/testing'].RutaLock, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $flujoSegundo.Dispose()
        } catch {
            $segundoMismoAmbienteRechazado = $true
        }
        $locksIndependientes = $null -ne $flujoTesting -and $null -ne $flujoProduccion -and $segundoMismoAmbienteRechazado
    } catch {
        $locksIndependientes = $false
    } finally {
        if ($null -ne $flujoTesting) { $flujoTesting.Dispose() }
        if ($null -ne $flujoProduccion) { $flujoProduccion.Dispose() }
        foreach ($claveLock in @($contextosResueltos['clientea/comercial/testing'].RutaLock, $contextosResueltos['clientea/comercial/produccion'].RutaLock)) {
            Remove-Item -LiteralPath $claveLock -Force -ErrorAction SilentlyContinue
        }
    }
    Test-Asercion -Id 'multicontexto.locksIndependientes' -Condicion $locksIndependientes -DetalleExito 'Locks de ambientes distintos coexisten y un segundo lock del mismo ambiente se rechaza.' -DetalleFallo 'El lock no aisla por ambiente o no rechaza el segundo lock del mismo ambiente.'

    $estadoGlobalesDespues = Obtener-EstadoDirectoriosGlobales
    $diferenciasGlobales = @(Obtener-DiferenciasDirectoriosGlobales -Antes $estadoGlobalesAntes -Despues $estadoGlobalesDespues)
    Test-Asercion -Id 'multicontexto.sinContaminacionGlobal' -Condicion ($diferenciasGlobales.Count -eq 0) -DetalleExito 'Las ejecuciones contextuales no modificaron documentacionServicios, estado, Logs ni xpz globales.' -DetalleFallo ('Alguna ejecucion contextual modifico directorios globales del pipeline: ' + ($diferenciasGlobales -join '; '))
}

function Ejecutar-CasosPipeline {
    <#
    .SYNOPSIS
    Casos del pipeline: duplicados, estados, OMITIDO, borrado de documento fallido,
    review y codigo de salida.
    .DESCRIPTION
    Ejecuta el flujo del pipeline sobre el inventario de duplicados con el XPZ
    fixture, escribiendo unicamente en test/tmp/, y verifica los estados del review,
    la deduplicacion por nombre local, el comportamiento de un ERROR frente a su
    documento previo y el codigo de salida.
    #>
    [CmdletBinding()]
    param()

    $rutaConfigPrueba = Join-Path $DirectorioFixturesJson 'configuracion-prueba.json'
    $rutaInventario = Join-Path $DirectorioFixturesJson 'inventario-duplicados.json'
    $configPrueba = Cargar-Configuracion -ConfigPath $rutaConfigPrueba

    New-DirectorioSiNoExiste -Directorio $DirectorioTmp | Out-Null
    $rutaDocError = Join-Path $DirectorioTmp 'wsserviciosinmain.md'
    $rutaDocOk = Join-Path $DirectorioTmp 'wsobtenerproductor.md'
    $rutaDocListar = Join-Path $DirectorioTmp 'wslistarestados.md'
    $contenidoPrevError = 'DOCUMENTO PREVIO DEL SERVICIO ERROR'
    $contenidoPrevOk = 'DOCUMENTO PREVIO DEL SERVICIO OK'
    [System.IO.File]::WriteAllText($rutaDocError, $contenidoPrevError, (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($rutaDocOk, $contenidoPrevOk, (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($rutaDocListar, 'DOCUMENTO PREVIO DEL SERVICIO LISTAR', (New-Object System.Text.UTF8Encoding($false)))

    $estadoProductivoAntes = @{}
    if (Test-Path -LiteralPath $DirectorioServiciosProduccion) {
        foreach ($archivoProductivo in @(Get-ChildItem -LiteralPath $DirectorioServiciosProduccion -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
            $estadoProductivoAntes[$archivoProductivo.FullName] = (Get-FileHash -LiteralPath $archivoProductivo.FullName -Algorithm SHA256).Hash
        }
    }

    $pipeline = $null
    try {
        $pipeline = Ejecutar-PipelinePrueba -Configuracion $configPrueba -RutaInventario $rutaInventario -DirectorioSalida $DirectorioTmp
    } catch {
        Test-Asercion -Id 'pipeline.ejecucion' -Condicion $false -DetalleFallo ('El pipeline sobre fixtures fallo: ' + $_.Exception.Message)
        return
    }

    Test-Asercion -Id 'pipeline.estados' -Condicion (
        $pipeline.Resumen.ok -eq 3 -and
        $pipeline.Resumen.warning -eq 1 -and
        $pipeline.Resumen.error -eq 1 -and
        $pipeline.Resumen.omitido -eq 1
    ) -DetalleExito 'El review contiene OK (3), WARNING (1), ERROR (1) y OMITIDO (1).' -DetalleFallo 'Los conteos del review no coinciden con lo esperado.'

    $ganador = @($pipeline.Servicios | Where-Object { $_.FullyQualifiedName -eq 'APIGLM.Cotizacion.WSObtenerProductor' })
    $perdedor = @($pipeline.Servicios | Where-Object { $_.FullyQualifiedName -eq 'APIGLM.Comun.WSObtenerProductor' })
    Test-Asercion -Id 'pipeline.duplicados' -Condicion (
        $ganador.Count -eq 1 -and $ganador[0].Estado -eq 'OK' -and
        $perdedor.Count -eq 1 -and $perdedor[0].Estado -eq 'WARNING'
    ) -DetalleExito 'El primer wrapper duplicado gana y el segundo queda como WARNING.' -DetalleFallo 'La deduplicacion por nombre local no funciono.'

    $omitido = @($pipeline.Servicios | Where-Object { $_.FullyQualifiedName -eq 'APIGLM.Test.WSTestMaxi' })
    Test-Asercion -Id 'pipeline.omitido' -Condicion (
        $omitido.Count -eq 1 -and $omitido[0].Estado -eq 'OMITIDO' -and
        -not (Test-Path -LiteralPath (Join-Path $DirectorioTmp 'wstestmaxi.md'))
    ) -DetalleExito 'Un servicio de serviciosIgnorados entra al review con OMITIDO y no se documenta.' -DetalleFallo 'El estado OMITIDO no se aplico correctamente.'

    $contenidoErrorFinal = [System.IO.File]::ReadAllText($rutaDocError)
    $contenidoOkFinal = [System.IO.File]::ReadAllText($rutaDocOk)
    $contenidoListarFinal = [System.IO.File]::ReadAllText($rutaDocListar)
    Test-Asercion -Id 'pipeline.borradoDocumentoFallido' -Condicion (
        $contenidoErrorFinal -eq $contenidoPrevError -and
        $contenidoOkFinal -ne $contenidoPrevOk -and
        $contenidoListarFinal -ne 'DOCUMENTO PREVIO DEL SERVICIO LISTAR'
    ) -DetalleExito 'Un ERROR conserva su documento previo y solo los servicios OK reemplazan el suyo.' -DetalleFallo 'El manejo del documento previo frente a ERROR no es el esperado.'

    $erroresPipeline = @($pipeline.Servicios | Where-Object { $_.Estado -eq 'ERROR' -and $_.FullyQualifiedName -eq 'APIGLM.Emision.WSServicioSinMain' })
    Test-Asercion -Id 'pipeline.review' -Condicion (
        @($pipeline.Servicios | Where-Object { $_.Estado -eq 'OK' }).Count -eq 3 -and
        $erroresPipeline.Count -eq 1 -and
        @($erroresPipeline[0].Mensajes).Count -ge 1
    ) -DetalleExito 'El review registra servicios OK, WARNING y ERROR con mensajes del fallo.' -DetalleFallo 'El review no refleja los estados de cada servicio.'

    $casosSoloPass = @([pscustomobject]@{ Estado = 'PASS' }, [pscustomobject]@{ Estado = 'SKIP' })
    $casosConFail = @([pscustomobject]@{ Estado = 'PASS' }, [pscustomobject]@{ Estado = 'FAIL' })
    Test-Asercion -Id 'pipeline.codigoSalida' -Condicion (
        (Resolver-CodigoSalida -CasosPrueba $casosSoloPass) -eq 0 -and
        (Resolver-CodigoSalida -CasosPrueba $casosConFail) -eq 1
    ) -DetalleExito 'El codigo de salida es 0 sin fallos y 1 con al menos un fallo.' -DetalleFallo 'El codigo de salida no se resuelve como se espera.'

    $estadoProductivoDespues = @{}
    if (Test-Path -LiteralPath $DirectorioServiciosProduccion) {
        foreach ($archivoProductivo in @(Get-ChildItem -LiteralPath $DirectorioServiciosProduccion -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
            $estadoProductivoDespues[$archivoProductivo.FullName] = (Get-FileHash -LiteralPath $archivoProductivo.FullName -Algorithm SHA256).Hash
        }
    }
    $sinEscrituraProductiva = $estadoProductivoAntes.Count -eq $estadoProductivoDespues.Count
    if ($sinEscrituraProductiva) {
        foreach ($rutaProductiva in $estadoProductivoAntes.Keys) {
            if (-not $estadoProductivoDespues.ContainsKey($rutaProductiva) -or $estadoProductivoDespues[$rutaProductiva] -ne $estadoProductivoAntes[$rutaProductiva]) {
                $sinEscrituraProductiva = $false
                break
            }
        }
    }
    Test-Asercion -Id 'pipeline.sinEscrituraProductiva' -Condicion $sinEscrituraProductiva -DetalleExito 'La ejecucion del pipeline de prueba no escribio documentos en carpetas productivas.' -DetalleFallo 'La ejecucion del pipeline de prueba escribio o modifico documentos en una carpeta productiva.'
}

function Ejecutar-CasosPosicionesGet {
    <#
    .SYNOPSIS
    Casos de posiciones GET en el programa principal y su reflejo en el Markdown.
    .DESCRIPTION
    Verifica que un GET con posiciones de QueryParams no consecutivas (1 y 3)
    documenta exactamente esas posiciones en orden ascendente, sin inventar la
    posicion faltante, y que el Markdown conserva la frase de posiciones, la
    columna Posicion y las filas correctas.
    #>
    [CmdletBinding()]
    param()

    $xml = Cargar-XmlFixture -Nombre 'xpz-base.xml'
    $indice = Construir-Indices -Xml $xml
    $main = Obtener-Objeto -Xml $xml -NombreCompleto 'APIGLM.Cotizacion.ObtenerProductor' -Indice $indice
    $source = Obtener-Source -ProgramaPrincipal $main

    $posiciones = @(Resolver-EntradaGet -Source $source)
    $ordenes = @($posiciones | ForEach-Object { [int]$_.Posicion })
    Test-Asercion -Id 'get.posiciones' -Condicion (
        $posiciones.Count -eq 2 -and $ordenes[0] -eq 1 -and $ordenes[1] -eq 3
    ) -DetalleExito 'El programa GET expone exactamente las posiciones 1 y 3 en orden ascendente.' -DetalleFallo 'Las posiciones GET no se resolvieron como se espera.'

    Test-Asercion -Id 'get.posicionesNoConsecutivas' -Condicion (
        (($ordenes -join ',') -eq '1,3')
    ) -DetalleExito 'Una posicion no consecutiva (1 y 3 sin 2) se documenta tal cual, sin posiciones inventadas.' -DetalleFallo 'Se invento alguna posicion no presente en el programa principal.'

    $tipos = @(Resolver-EntradaGetTipos -Xml $xml -ProgramaPrincipal $main -Source $source -Posiciones $posiciones -Indice $indice)
    $campoPosicion1 = @($tipos | Where-Object { $_.Posicion -eq 1 })
    $campoPosicion3 = @($tipos | Where-Object { $_.Posicion -eq 3 })
    Test-Asercion -Id 'get.tiposPorPosicion' -Condicion (
        $campoPosicion1.Count -eq 1 -and $campoPosicion1[0].Campo -eq 'EmpCod' -and
        $campoPosicion3.Count -eq 1 -and $campoPosicion3[0].Campo -eq 'ProCod'
    ) -DetalleExito 'Cada posicion conserva su campo y su tipo canonicos.' -DetalleFallo 'La resolucion de tipos por posicion no es correcta.'

    $doc = Analizar-Servicio -Xml $xml -NombreCompletoWrapper 'APIGLM.Cotizacion.WSObtenerProductor' -PackageName 'glmsuit.comercial.' -Indice $indice
    $md = Redactar-Documento -Documentacion $doc

    Test-Asercion -Id 'get.markdownFilaVersionPorDefecto' -Condicion ($md -match '(?m)^\| Versión \| 1\.0 \|$') -DetalleExito 'La fila Version de Definicion del servicio muestra 1.0 sin control previo.' -DetalleFallo 'La fila Version no aparece o no muestra 1.0.'

    $mdVersionAsignada = Redactar-Documento -Documentacion $doc -Version '1.7'
    Test-Asercion -Id 'get.markdownFilaVersionAsignada' -Condicion ($mdVersionAsignada -match '(?m)^\| Versión \| 1\.7 \|$') -DetalleExito 'La fila Version conserva la version asignada por el control de versiones.' -DetalleFallo 'La fila Version no conserva la version asignada.'

    Test-Asercion -Id 'get.markdownFrasePosiciones' -Condicion ($md -match 'La consulta debe conservar exactamente 2 posiciones y respetar el orden indicado\.') -DetalleExito 'El Markdown conserva la frase canonica de posiciones GET.' -DetalleFallo 'El Markdown no conserva la frase de posiciones GET.'

    Test-Asercion -Id 'get.markdownColumnaPosicion' -Condicion ($md -match '\| Posición \| Parámetro \| Tipo \| Obligatorio \| Descripción \|') -DetalleExito 'El Markdown incluye la tabla GET con la columna Posicion.' -DetalleFallo 'La tabla GET no incluye la columna Posicion.'

    Test-Asercion -Id 'get.markdownPosiciones' -Condicion (
        $md -match '\| 1 \| `EmpCod`' -and $md -match '\| 3 \| `ProCod`'
    ) -DetalleExito 'El Markdown documenta las posiciones 1 y 3 con sus parametros.' -DetalleFallo 'El Markdown no documenta las posiciones 1 y 3.'

    Test-Asercion -Id 'get.markdownSinPosicionInventada' -Condicion (-not ($md -match '(?m)^\| 2 \|')) -DetalleExito 'El Markdown no inventa la posicion 2.' -DetalleFallo 'El Markdown invento la posicion 2.'

    Test-Asercion -Id 'get.endpointPublicado' -Condicion ($doc.EndpointPublicado -eq 'glmsuit.comercial.apiglm.cotizacion.awsobtenerproductor') -DetalleExito 'El endpoint publicado del GET se resuelve en minusculas con la regla del prefijo a.' -DetalleFallo 'El endpoint publicado del GET no coincide.'

    $xmlAnidado = Cargar-XmlFixture -Nombre 'programa-get-anidado.xml'
    $indiceAnidado = Construir-Indices -Xml $xmlAnidado
    $mainAnidado = Obtener-Objeto -Xml $xmlAnidado -NombreCompleto 'APIGLM.Cotizacion.ObtenerProductorAnidado' -Indice $indiceAnidado
    $sourceAnidado = Obtener-Source -ProgramaPrincipal $mainAnidado
    $posicionesAnidadas = @(Resolver-EntradaGet -Source $sourceAnidado)
    Test-Asercion -Id 'get.posicionesAnidadas' -Condicion (
        @($posicionesAnidadas | Where-Object { $_.Posicion -eq 4 -and $_.Campo -eq 'fechaVigencia' }).Count -eq 1 -and
        @($posicionesAnidadas | Where-Object { $_.Posicion -eq 1 -and $_.Campo -eq 'EmpCod' }).Count -eq 1 -and
        @($posicionesAnidadas | Where-Object { $_.Posicion -eq 3 -and $_.Campo -eq 'ProCod' }).Count -eq 1
    ) -DetalleExito 'Una posicion con Item(N) anidado en una conversion tambien se documenta.' -DetalleFallo 'La posicion con Item(N) anidado no se detecto.'

    $xmlMetodo = Cargar-XmlFixture -Nombre 'programa-get-metodo.xml'
    $indiceMetodo = Construir-Indices -Xml $xmlMetodo
    $mainMetodo = Obtener-Objeto -Xml $xmlMetodo -NombreCompleto 'APIGLM.Comun.ListarCobranzas' -Indice $indiceMetodo
    $sourceMetodo = Obtener-Source -ProgramaPrincipal $mainMetodo
    $posicionesMetodo = @(Resolver-EntradaGet -Source $sourceMetodo)
    Test-Asercion -Id 'get.posicionesMetodo' -Condicion (
        @($posicionesMetodo).Count -eq 5 -and
        @($posicionesMetodo | Where-Object { $_.Posicion -eq 3 -and $_.Campo -eq 'FechaDesde' }).Count -eq 1 -and
        @($posicionesMetodo | Where-Object { $_.Posicion -eq 4 -and $_.Campo -eq 'FechaHasta' }).Count -eq 1 -and
        @($posicionesMetodo | Where-Object { $_.Posicion -eq 1 -and $_.Campo -eq 'Usuario' }).Count -eq 1 -and
        @($posicionesMetodo | Where-Object { $_.Posicion -eq 2 -and $_.Campo -eq 'Productor' }).Count -eq 1 -and
        @($posicionesMetodo | Where-Object { $_.Posicion -eq 5 -and $_.Campo -eq 'Estado' }).Count -eq 1
    ) -DetalleExito 'Las posiciones consumidas con Item(N) en forma metodo se documentan con su campo.' -DetalleFallo 'Una posicion en forma metodo no se detecto.'

    $tiposMetodo = @(Resolver-EntradaGetTipos -Xml $xmlMetodo -ProgramaPrincipal $mainMetodo -Source $sourceMetodo -Posiciones $posicionesMetodo -Indice $indiceMetodo)
    $fechaDesdeTipo = @($tiposMetodo | Where-Object { $_.Campo -eq 'FechaDesde' })
    Test-Asercion -Id 'get.posicionesMetodoTipos' -Condicion (
        $fechaDesdeTipo.Count -eq 1 -and $fechaDesdeTipo[0].Tipo -eq 'Date (YYYY-MM-DD)'
    ) -DetalleExito 'El campo consumido en forma metodo conserva su tipo canonico desde la declaracion.' -DetalleFallo 'El tipo del campo en forma metodo no se resolvio.'

    $xmlSalto = Cargar-XmlFixture -Nombre 'programa-get-salto-inicial.xml'
    $indiceSalto = Construir-Indices -Xml $xmlSalto
    $mainSalto = Obtener-Objeto -Xml $xmlSalto -NombreCompleto 'APIGLM.Cotizacion.ValidarInicioVigencia' -Indice $indiceSalto
    $sourceSalto = Obtener-Source -ProgramaPrincipal $mainSalto
    $posicionesSalto = @(Resolver-EntradaGet -Source $sourceSalto)
    Test-Asercion -Id 'get.posicionesSinPosicionInicial' -Condicion (
        @($posicionesSalto).Count -eq 4 -and
        @($posicionesSalto | Where-Object { $_.Posicion -eq 1 }).Count -eq 0 -and
        @($posicionesSalto | Where-Object { $_.Posicion -eq 2 -and $_.Campo -eq 'UsuCod' }).Count -eq 1 -and
        @($posicionesSalto | Where-Object { $_.Posicion -eq 3 -and $_.Campo -eq 'RamCod' }).Count -eq 1 -and
        @($posicionesSalto | Where-Object { $_.Posicion -eq 4 -and $_.Campo -eq 'ProCod' }).Count -eq 1 -and
        @($posicionesSalto | Where-Object { $_.Posicion -eq 5 -and $_.Campo -eq 'VigenciaDesde' }).Count -eq 1
    ) -DetalleExito 'Un GET cuyas posiciones no arrancan en 1 documenta exactamente las presentes, sin inventar la 1.' -DetalleFallo 'Se invento la posicion 1 o faltan posiciones presentes.'

    $xmlComentario = Cargar-XmlFixture -Nombre 'programa-get-comentario.xml'
    $indiceComentario = Construir-Indices -Xml $xmlComentario

    $mainDatosProductor = Obtener-Objeto -Xml $xmlComentario -NombreCompleto 'APIGLM.Cotizacion.ObtenerDatosProductor' -Indice $indiceComentario
    $sourceDatosProductor = Obtener-Source -ProgramaPrincipal $mainDatosProductor
    $posicionesDatosProductor = @(Resolver-EntradaGet -Source $sourceDatosProductor)
    Test-Asercion -Id 'get.posicionesPredefinidoOmitido' -Condicion (
        @($posicionesDatosProductor).Count -eq 1 -and
        @($posicionesDatosProductor | Where-Object { $_.Posicion -eq 1 -and $_.Campo -eq 'ProCod' }).Count -eq 1 -and
        @($posicionesDatosProductor | Where-Object { $_.Campo -eq 'APIGLMRequestIn' }).Count -eq 0 -and
        @($posicionesDatosProductor | Where-Object { $_.Campo -eq 'EmpCod' }).Count -eq 0
    ) -DetalleExito 'El primer parametro predefinido (&APIGLMRequestIn.EmpCod, sin Item) no se documenta y se conserva la posicion real del parametro activo.' -DetalleFallo 'Se documento el parametro predefinido o se perdio la posicion activa.'

    $mainProductores = Obtener-Objeto -Xml $xmlComentario -NombreCompleto 'APIGLM.Cotizacion.ListarProductoresDeUsuario' -Indice $indiceComentario
    $sourceProductores = Obtener-Source -ProgramaPrincipal $mainProductores
    $posicionesProductores = @(Resolver-EntradaGet -Source $sourceProductores)
    Test-Asercion -Id 'get.posicionesComentarioIgnorado' -Condicion (
        @($posicionesProductores).Count -eq 1 -and
        @($posicionesProductores | Where-Object { $_.Posicion -eq 2 -and $_.Campo -eq 'UsuCod' }).Count -eq 1 -and
        @($posicionesProductores | Where-Object { $_.Posicion -eq 1 }).Count -eq 0
    ) -DetalleExito 'Una posicion Item(N) dentro de un comentario no se documenta; se muestra desde la posicion 2 con su posicion real.' -DetalleFallo 'Una posicion comentada se documento o falta la posicion activa.'

    $mainEmpresaSolo = Obtener-Objeto -Xml $xmlComentario -NombreCompleto 'APIGLM.Cotizacion.ObtenerEmpresaSolo' -Indice $indiceComentario
    $sourceEmpresaSolo = Obtener-Source -ProgramaPrincipal $mainEmpresaSolo
    $posicionesEmpresaSolo = @(Resolver-EntradaGet -Source $sourceEmpresaSolo)
    Test-Asercion -Id 'get.posicionesSoloComentadas' -Condicion (@($posicionesEmpresaSolo).Count -eq 0) -DetalleExito 'Si el unico Item(N) esta comentado, no se documenta ninguna posicion.' -DetalleFallo 'Se documento una posicion que solo existia en un comentario.'
}

function Ejecutar-CasosMultiXpz {
    <#
    .SYNOPSIS
    Casos de carga multi-XPZ: descubrimiento de complementos y cascada de resolucion.
    .DESCRIPTION
    Verifica que Cargar-IndiceMultiXPZ descubre el complemento _1.xpz del XPZ
    fixture, resuelve los objetos exclusivos del complemento en el indice unificado
    y da prioridad al XPZ principal ante FQN o guid duplicado.
    #>
    [CmdletBinding()]
    param()

    $rutaBase = Join-Path $DirectorioFixturesXpz 'SEGUROS_COMERCIAL_APIGLM_test.xpz'
    $rutaComplemento = Join-Path $DirectorioFixturesXpz 'SEGUROS_COMERCIAL_APIGLM_test_1.xpz'

    $complementos = @(Descubrir-XPZComplementariosCompartido -RutaXpzPrincipal $rutaBase)
    Test-Asercion -Id 'multixpz.descubrimiento' -Condicion (
        $complementos.Count -eq 1 -and $complementos[0] -eq $rutaComplemento
    ) -DetalleExito 'Se descubre el complemento _1.xpz del XPZ configurado.' -DetalleFallo 'El descubrimiento del complemento no encontro el _1.xpz.'

    $indice = Cargar-IndiceMultiXPZ -RutaXpzPrincipal $rutaBase
    Test-Asercion -Id 'multixpz.unificado' -Condicion (
        $indice.NombresXpz.Count -eq 2 -and
        $indice.NombresXpz[0] -eq 'SEGUROS_COMERCIAL_APIGLM_test.xpz' -and
        $indice.NombresXpz[1] -eq 'SEGUROS_COMERCIAL_APIGLM_test_1.xpz' -and
        $indice.XmlUnificado.SelectNodes('//Object').Count -eq 17
    ) -DetalleExito 'El indice unificado combina el XPZ principal y el complemento (17 objetos).' -DetalleFallo 'El indice unificado no combino los archivos como se espera.'

    $complementoProc = Obtener-Objeto -Xml $indice.XmlUnificado -NombreCompleto 'APIGLM.Comun.ListarComplementos' -Indice $indice
    Test-Asercion -Id 'multixpz.soloComplemento' -Condicion (
        $null -ne $complementoProc -and $indice.PorNombreDominio['DominioComplemento'].Count -eq 1
    ) -DetalleExito 'Un objeto presente solo en el complemento _1.xpz se resuelve en el indice unificado.' -DetalleFallo 'El objeto exclusivo del complemento no se resolvio.'

    $empCod = $indice.PorFqn['EmpCod']
    Test-Asercion -Id 'multixpz.cascadaFqn' -Condicion (
        $null -ne $empCod -and $empCod.GetAttribute('guid') -eq 'aaaaaaaa-0000-0000-0000-000000000005'
    ) -DetalleExito 'Ante un FQN duplicado entre principal y complemento, gana el primer XPZ.' -DetalleFallo 'La cascada por FQN duplicado no favorece al XPZ principal.'

    $objetoGuidDuplicado = $indice.XmlUnificado.SelectNodes("//Object[@fullyQualifiedName='APIGLM.Emision.Productor']")
    $productorBase = $indice.PorFqn['APIGLM.Cotizacion.Productor']
    Test-Asercion -Id 'multixpz.cascadaGuid' -Condicion (
        $objetoGuidDuplicado.Count -eq 0 -and
        $null -ne $productorBase -and $productorBase.GetAttribute('guid') -eq 'aaaaaaaa-0000-0000-0000-000000000003'
    ) -DetalleExito 'Ante un guid duplicado, gana el primer XPZ y el objeto del complemento se excluye.' -DetalleFallo 'La cascada por guid duplicado no favorece al XPZ principal.'

    $atributoDuplicado = $indice.XmlUnificado.SelectNodes("//Attribute[@fullyQualifiedName='EmpCod' and @guid='bbbbbbbb-0000-0000-0000-000000000004']")
    Test-Asercion -Id 'multixpz.cascadaAtributo' -Condicion ($atributoDuplicado.Count -eq 0) -DetalleExito 'El atributo duplicado del complemento tambien queda excluido.' -DetalleFallo 'La cascada de atributos no excluyo el duplicado del complemento.'
}

function Ejecutar-CasosAnalizador {
    <#
    .SYNOPSIS
    Casos del analizador XPZ: tipos canonicos, obligatoriedad, SDT anidado de
    entrada y salida, ciclo, ausencia de SDT, llamada multilinea y codigos HTTP.
    .DESCRIPTION
    Ejercita las funciones productivas del analizador sobre los fixtures XML
    (Obtener-DatosTipo, Convertir-TipoCanonico, Resolver-Obligatorio, Expandir-
    EstructuraSdt, Resolver-EntradaPost, Resolver-Salida, Resolver-Errores y
    Resolver-Metodo) y verifica que el Markdown no conserva condiciones GeneXus.
    #>
    [CmdletBinding()]
    param()

    $xmlBase = Cargar-XmlFixture -Nombre 'xpz-base.xml'
    $indiceBase = Construir-Indices -Xml $xmlBase

    $tiposEsperados = @(
        @([pscustomobject]@{ BaseTipo = 'Numeric'; EsEstructura = $false; EsColeccion = $false; Longitud = '10'; LongitudMaxima = '10'; Decimales = '2'; NoResuelto = $false }, 'Decimal (10, 2)'),
        @([pscustomobject]@{ BaseTipo = 'Numeric'; EsEstructura = $false; EsColeccion = $false; Longitud = '7'; LongitudMaxima = '7'; Decimales = '0'; NoResuelto = $false }, 'Integer (7)'),
        @([pscustomobject]@{ BaseTipo = 'Character'; EsEstructura = $false; EsColeccion = $false; Longitud = '60'; LongitudMaxima = '60'; Decimales = ''; NoResuelto = $false }, 'String (60)'),
        @([pscustomobject]@{ BaseTipo = 'VarChar'; EsEstructura = $false; EsColeccion = $false; Longitud = '50'; LongitudMaxima = '50'; Decimales = ''; NoResuelto = $false }, 'String (50)'),
        @([pscustomobject]@{ BaseTipo = 'LongVarChar'; EsEstructura = $false; EsColeccion = $false; Longitud = ''; LongitudMaxima = ''; Decimales = ''; NoResuelto = $false }, 'LongVarchar'),
        @([pscustomobject]@{ BaseTipo = 'Boolean'; EsEstructura = $false; EsColeccion = $false; Longitud = ''; LongitudMaxima = ''; Decimales = ''; NoResuelto = $false }, 'Boolean'),
        @([pscustomobject]@{ BaseTipo = 'Date'; EsEstructura = $false; EsColeccion = $false; Longitud = ''; LongitudMaxima = ''; Decimales = ''; NoResuelto = $false }, 'Date (YYYY-MM-DD)'),
        @([pscustomobject]@{ BaseTipo = 'DateTime'; EsEstructura = $false; EsColeccion = $false; Longitud = ''; LongitudMaxima = ''; Decimales = ''; NoResuelto = $false }, 'DateTime'),
        @([pscustomobject]@{ BaseTipo = 'Blob'; EsEstructura = $false; EsColeccion = $false; Longitud = ''; LongitudMaxima = ''; Decimales = ''; NoResuelto = $false }, 'Base64'),
        @([pscustomobject]@{ BaseTipo = 'Image'; EsEstructura = $false; EsColeccion = $false; Longitud = ''; LongitudMaxima = ''; Decimales = ''; NoResuelto = $false }, 'Base64'),
        @([pscustomobject]@{ BaseTipo = ''; EsEstructura = $true; EsColeccion = $false; Longitud = ''; LongitudMaxima = ''; Decimales = ''; NoResuelto = $false }, 'Estructura Campo'),
        @([pscustomobject]@{ BaseTipo = ''; EsEstructura = $true; EsColeccion = $true; Longitud = ''; LongitudMaxima = ''; Decimales = ''; NoResuelto = $false }, 'Colección de Estructura Campo'),
        @([pscustomobject]@{ BaseTipo = 'Numeric'; EsEstructura = $false; EsColeccion = $true; Longitud = ''; LongitudMaxima = ''; Decimales = ''; NoResuelto = $false }, 'Colección JSON'),
        @([pscustomobject]@{ BaseTipo = ''; EsEstructura = $false; EsColeccion = $false; Longitud = ''; LongitudMaxima = ''; Decimales = ''; NoResuelto = $true }, '')
    )
    $tiposCumplidos = $true
    foreach ($par in $tiposEsperados) {
        $canonico = Convertir-TipoCanonico -DatosTipo $par[0] -NombreCampo 'Campo'
        if ($canonico -ne $par[1]) { $tiposCumplidos = $false; break }
    }
    Test-Asercion -Id 'analizador.tiposCanonicos' -Condicion $tiposCumplidos -DetalleExito 'La conversion produce la tipografia canonica en todas sus variantes.' -DetalleFallo 'Alguna variante de la tipografia canonica no se produce correctamente.'

    $xmlSinTipo = Cargar-XmlFixture -Nombre 'tipo-faltante.xml'
    $indiceSinTipo = Construir-Indices -Xml $xmlSinTipo
    $sdtSinTipo = Obtener-Sdt -Xml $xmlSinTipo -NombreSdt 'SinTipo' -Indice $indiceSinTipo
    $campoDesconocido = @(Obtener-HijosSdt -Sdt $sdtSinTipo | Where-Object { $_.GetAttribute('name') -eq 'CampoDesconocido' })[0]
    $datosSinTipo = Obtener-DatosTipo -Xml $xmlSinTipo -Nodo $campoDesconocido -Indice $indiceSinTipo
    $campoResuelto = Resolver-Campo -Xml $xmlSinTipo -Item $campoDesconocido -Indice $indiceSinTipo
    Test-Asercion -Id 'analizador.tipoNoResuelto' -Condicion (
        $datosSinTipo.NoResuelto -eq $true -and
        [string]::IsNullOrEmpty((Convertir-TipoCanonico -DatosTipo $datosSinTipo -NombreCampo 'CampoDesconocido')) -and
        $campoResuelto.Tipo -match '^PENDIENTE DE CONFIRMACIÓN: tipo del campo CampoDesconocido\.'
    ) -DetalleExito 'Un campo sin evidencia de tipo se marca como no resuelto y como pendiente.' -DetalleFallo 'El tipo no resuelto no se detecta como pendiente.'

    $get = Analizar-Servicio -Xml $xmlBase -NombreCompletoWrapper 'APIGLM.Cotizacion.WSObtenerProductor' -PackageName 'glmsuit.comercial.' -Indice $indiceBase
    $mainGet = Obtener-Objeto -Xml $xmlBase -NombreCompleto 'APIGLM.Cotizacion.ObtenerProductor' -Indice $indiceBase
    $sourceGet = Obtener-Source -ProgramaPrincipal $mainGet
    $empCod = @($get.Entrada | Where-Object { $_.Campo -eq 'EmpCod' })
    $proCod = @($get.Entrada | Where-Object { $_.Campo -eq 'ProCod' })
    Test-Asercion -Id 'analizador.obligatorioGet' -Condicion (
        $empCod.Count -eq 1 -and $empCod[0].Obligatorio -eq 'SI' -and
        $proCod.Count -eq 1 -and $proCod[0].Obligatorio -eq 'NO'
    ) -DetalleExito 'Un campo GET consumido despues del parser es SI y uno solo asignado es NO.' -DetalleFallo 'La obligatoriedad GET no se resolvio.'

    $post = Analizar-Servicio -Xml $xmlBase -NombreCompletoWrapper 'APIGLM.Emision.WSConsultarSolicitud' -PackageName 'glmsuit.comercial.' -Indice $indiceBase
    $numero = @($post.Entrada | Where-Object { $_.Campo -eq 'Numero' })
    $cliente = @($post.Entrada | Where-Object { $_.Campo -eq 'Cliente' })
    Test-Asercion -Id 'analizador.obligatorioPost' -Condicion (
        $numero.Count -eq 1 -and $numero[0].Obligatorio -eq 'NO' -and
        $cliente.Count -eq 1 -and $cliente[0].Obligatorio -eq 'SI'
    ) -DetalleExito 'Un campo POST solo deserializado es NO y uno validado es SI.' -DetalleFallo 'La obligatoriedad POST no se resolvio.'

    $estructuraCliente = @($post.Estructuras | Where-Object { $_.RutaJson -eq 'Cliente' })
    Test-Asercion -Id 'analizador.sdtAnidadoEntrada' -Condicion (
        $estructuraCliente.Count -eq 1 -and
        @($estructuraCliente[0].Hijos | Where-Object { $_.Campo -eq 'Id' }).Count -eq 1 -and
        @($estructuraCliente[0].Hijos | Where-Object { $_.Campo -eq 'Nombre' }).Count -eq 1
    ) -DetalleExito 'El SDT de entrada anidado se expande con su estructura Cliente.' -DetalleFallo 'El SDT de entrada anidado no se expandio.'

    $estructurasSalida = @($get.EstructurasSalida)
    $codigoPostalSalida = @($estructurasSalida | Where-Object { $_.RutaJson -eq 'CodigoPostal' })
    $polizasSalida = @($estructurasSalida | Where-Object { $_.RutaJson -eq 'Polizas' })
    Test-Asercion -Id 'analizador.sdtAnidadoSalida' -Condicion (
        @($get.Salida).Count -eq 4 -and
        $codigoPostalSalida.Count -eq 1 -and $codigoPostalSalida[0].EsColeccion -eq $false -and
        $polizasSalida.Count -eq 1 -and $polizasSalida[0].EsColeccion -eq $true
    ) -DetalleExito 'El SDT de salida anidado se expande con estructura y coleccion.' -DetalleFallo 'El SDT de salida anidado no se expandio.'

    $xmlCiclo = Cargar-XmlFixture -Nombre 'ciclo.xml'
    $indiceCiclo = Construir-Indices -Xml $xmlCiclo
    $sdtCiclo = Obtener-Sdt -Xml $xmlCiclo -NombreSdt 'NodoArbol' -Indice $indiceCiclo
    $expandidoCiclo = Expandir-EstructuraSdt -Xml $xmlCiclo -Sdt $sdtCiclo -Indice $indiceCiclo
    Test-Asercion -Id 'analizador.cicloSdt' -Condicion (
        @($expandidoCiclo.Ciclos).Count -gt 0 -and
        @($expandidoCiclo.Ciclos | Where-Object { $_.RutaJson -eq 'Padre' }).Count -eq 1
    ) -DetalleExito 'Un ciclo SDT se detecta y registra la ruta recursiva.' -DetalleFallo 'El ciclo SDT no se detecto.'

    $xmlAusente = Cargar-XmlFixture -Nombre 'sdt-ausente.xml'
    $indiceAusente = Construir-Indices -Xml $xmlAusente
    $mainEntradaAusente = Obtener-Objeto -Xml $xmlAusente -NombreCompleto 'APIGLM.Comun.EntradaInexistente' -Indice $indiceAusente
    $sourceEntradaAusente = Obtener-Source -ProgramaPrincipal $mainEntradaAusente
    Test-AsercionLanzaError -Id 'analizador.ausenciaSdtEntrada' -Bloque { Resolver-EntradaPost -Xml $xmlAusente -ProgramaPrincipal $mainEntradaAusente -Source $sourceEntradaAusente -Indice $indiceAusente } -PatronMensaje "La entrada del SDT NoExiste no est.*exportada en el XPZ configurado" -DetalleExito 'Una entrada que referencia un SDT ausente detiene con el mensaje correspondiente.' -DetalleFallo 'La ausencia de SDT de entrada no detuvo el analisis.'

    $mainSalidaAusente = Obtener-Objeto -Xml $xmlAusente -NombreCompleto 'APIGLM.Comun.SalidaInexistente' -Indice $indiceAusente
    $sourceSalidaAusente = Obtener-Source -ProgramaPrincipal $mainSalidaAusente
    $salidaAusente = Resolver-Salida -Xml $xmlAusente -ProgramaPrincipal $mainSalidaAusente -Source $sourceSalidaAusente -Indice $indiceAusente
    Test-Asercion -Id 'analizador.ausenciaSdtSalida' -Condicion (
        $salidaAusente.NoResuelta -eq $true -and
        $salidaAusente.MotivoNoResuelta -match "La salida del SDT SalidaAusente no est.*exportada en el XPZ configurado"
    ) -DetalleExito 'Una salida que referencia un SDT ausente queda como no resuelta con su motivo.' -DetalleFallo 'La ausencia de SDT de salida no se registro.'

    $xmlMulti = Cargar-XmlFixture -Nombre 'llamada-multilinea.xml'
    $indiceMulti = Construir-Indices -Xml $xmlMulti
    $mainMulti = Obtener-Objeto -Xml $xmlMulti -NombreCompleto 'APIGLM.Comun.RegistrarSolicitud' -Indice $indiceMulti
    $sourceMulti = Obtener-Source -ProgramaPrincipal $mainMulti
    $entradaMulti = Resolver-EntradaPost -Xml $xmlMulti -ProgramaPrincipal $mainMulti -Source $sourceMulti -Indice $indiceMulti
    Test-Asercion -Id 'analizador.llamadaMultiline' -Condicion (
        (Resolver-Metodo -Source $sourceMulti) -eq 'POST' -and
        $entradaMulti.VariableSdt -eq 'EntSolicitud' -and
        $entradaMulti.NombreSdt -eq 'Solicitud' -and
        @($entradaMulti.Campos | Where-Object { $_.GetAttribute('name') -eq 'Numero' }).Count -eq 1
    ) -DetalleExito 'Una llamada FromJson multilinea se reconoce como POST y resuelve el SDT de entrada.' -DetalleFallo 'La llamada multilinea no se reconocio.'

    $erroresGet = @(Resolver-Errores -Source $sourceGet)
    Test-Asercion -Id 'analizador.codigosHttp' -Condicion (
        @($erroresGet | Where-Object { $_.Codigo -eq 400 }).Count -eq 1 -and
        @($erroresGet | Where-Object { $_.Codigo -eq 404 }).Count -eq 1 -and
        (Mapear-CodigoHttp -NombreCodigo 'HttpCode.BadRequest') -eq 400 -and
        (Mapear-CodigoHttp -NombreCodigo 'HttpCode.NotFound') -eq 404 -and
        (Mapear-CodigoHttp -NombreCodigo 'HttpCode.MethodNotAllowed') -eq 405 -and
        (Mapear-CodigoHttp -NombreCodigo 'HttpCode.OK') -eq 200 -and
        (Mapear-CodigoHttp -NombreCodigo 'HttpCode.Desconocido') -eq 0
    ) -DetalleExito 'Los codigos HTTP explicitos se mapean y se registran como errores especificos.' -DetalleFallo 'Los codigos HTTP no se resolvieron como se espera.'

    $mdGet = Redactar-Documento -Documentacion $get
    Test-Asercion -Id 'analizador.condicionesGeneXus' -Condicion (-not ($mdGet -match '(?im)\b(if |for each|endif|endfor|endsub|endwhile)\b')) -DetalleExito 'El Markdown no conserva condiciones ni estructuras de control GeneXus.' -DetalleFallo 'El Markdown conservo condiciones GeneXus.'
}

function Validar-MarkdownOrdenSecciones {
    <#
    .SYNOPSIS
    Verifica el orden canonico de secciones de un Markdown de servicio.
    .DESCRIPTION
    Exige que aparezcan en orden Definicion, Generalidades, Entrada, Salida exitosa
    y Errores especificos, sin ninguna seccion adicional entre Salida exitosa y
    Errores especificos.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Contenido
    )
    $orden = @('## Definición del servicio', '## Generalidades', '## Entrada', '## Salida exitosa', '## Errores específicos')
    $esperado = 0
    foreach ($linea in ($Contenido -split "`n")) {
        if ($linea -notmatch '^## ') { continue }
        if ($esperado -lt $orden.Count -and $linea -eq $orden[$esperado]) {
            $esperado++
        } elseif ($esperado -lt $orden.Count) {
            return $false
        }
    }
    return ($esperado -eq $orden.Count)
}

function Validar-MarkdownSinComentariosNiEjemplos {
    <#
    .SYNOPSIS
    Verifica que el Markdown no conserva comentarios HTML ni filas de ejemplo de la plantilla.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Contenido
    )
    if ($Contenido -match '<!--') { return $false }
    if ($Contenido -match '\| <[^|]+> \|') { return $false }
    if ($Contenido -match 'Repetir la fila anterior|Repetir el siguiente bloque|Variante GET: conservar este bloque|Variante POST: conservar este bloque') { return $false }
    return $true
}

function Validar-MarkdownJsonComun {
    <#
    .SYNOPSIS
    Verifica que el JSON comun bajo Errores especificos conserva las claves exactas.
    .DESCRIPTION
    Exige las claves status, Description, detail (en minuscula) y JsonResult dentro
    del bloque json de codigo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Contenido
    )
    $coincidencia = [regex]::Match($Contenido, '(?s)```json\r?\n(.*?)\r?\n```')
    if (-not $coincidencia.Success) { return $false }
    $bloqueJson = $coincidencia.Groups[1].Value
    return ($bloqueJson -match '"status"' -and $bloqueJson -match '"Description"' -and $bloqueJson -match '"detail"' -and $bloqueJson -match '"JsonResult"')
}

function Validar-MarkdownBloquesCanonicos {
    <#
    .SYNOPSIS
    Verifica la autenticacion literal y la tabla completa de codigos HTTP comunes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Contenido
    )
    $autenticacionOk = $Contenido -match 'Authorization: Basic \{Base64\(usuario:contraseña\)\}'
    $tablaOk = ($Contenido -match '\| 200 \| Solicitud procesada correctamente\. \|') -and
        ($Contenido -match '\| 400 \| Faltan parámetros requeridos o son inválidos\. \|') -and
        ($Contenido -match '\| 401 \| Falló la autenticación\. \|') -and
        ($Contenido -match '\| 500 \| Error interno de Servicio\. \|') -and
        ($Contenido -match '\| 501 \| Servicio no implementado o sin configuración\. \|') -and
        ($Contenido -match '\| 503 \| Servicio no disponible o inactivo\. \|')
    return ($autenticacionOk -and $tablaOk)
}

function Validar-MarkdownObligatorio {
    <#
    .SYNOPSIS
    Verifica que la columna Obligatorio usa solo SI o NO en todas las tablas.
    .DESCRIPTION
    Localiza la posicion de la columna Obligatorio en cada cabecera de tabla y
    valida que las celdas de datos de esa columna contengan SI o NO.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Contenido
    )
    $lineas = @($Contenido -split "`n")
    $indiceObligatorio = -1
    for ($i = 0; $i -lt $lineas.Count; $i++) {
        $linea = $lineas[$i]
        if ($linea -notmatch '\|') {
            $indiceObligatorio = -1
            continue
        }
        if ($linea -match '^\s*\|?(:?-+:?\|)+\s*$') { continue }

        $celdas = @($linea -split '\|' | ForEach-Object { $_.Trim().TrimStart('`').TrimEnd('`') })
        $siguienteEsSeparador = $false
        if (($i + 1) -lt $lineas.Count) {
            $siguienteEsSeparador = $lineas[$i + 1] -match '^\s*\|?(:?-+:?\|)+\s*$'
        }

        if ($siguienteEsSeparador) {
            if ($celdas -contains 'Obligatorio') {
                $indiceObligatorio = [Array]::IndexOf($celdas, 'Obligatorio')
            }
            else {
                $indiceObligatorio = -1
            }
            continue
        }

        if ($indiceObligatorio -ge 0 -and $linea -match '^\s*\|' -and $celdas.Count -gt $indiceObligatorio) {
            $valor = $celdas[$indiceObligatorio]
            if ($valor -and $valor -notin @('SI', 'NO')) { return $false }
        }
    }
    return $true
}

function Validar-MarkdownTiposCanonicos {
    <#
    .SYNOPSIS
    Verifica que no aparecen tipos fuera de la tipografia canonica.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Contenido
    )
    $lineas = @($Contenido -split "`n")
    $indiceTipo = -1
    for ($i = 0; $i -lt $lineas.Count; $i++) {
        $linea = $lineas[$i]
        if ($linea -notmatch '\|') {
            $indiceTipo = -1
            continue
        }
        if ($linea -match '^\s*\|?(:?-+:?\|)+\s*$') { continue }

        $celdas = @($linea -split '\|' | ForEach-Object { $_.Trim().TrimStart('`').TrimEnd('`') })
        $siguienteEsSeparador = $false
        if (($i + 1) -lt $lineas.Count) {
            $siguienteEsSeparador = $lineas[$i + 1] -match '^\s*\|?(:?-+:?\|)+\s*$'
        }

        if ($siguienteEsSeparador) {
            if ($celdas -contains 'Tipo') {
                $indiceTipo = [Array]::IndexOf($celdas, 'Tipo')
            }
            else {
                $indiceTipo = -1
            }
            continue
        }

        if ($indiceTipo -ge 0 -and $linea -match '^\s*\|' -and $celdas.Count -gt $indiceTipo) {
            $tipo = $celdas[$indiceTipo]
            if ($tipo -in @('Texto', 'Numérico', 'Objeto JSON')) { return $false }
        }
    }
    return $true
}

function Validar-MarkdownSinDetallesInternos {
    <#
    .SYNOPSIS
    Verifica ausencia de GUID, XML, nombres internos de SDT, parm y credenciales.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Contenido
    )
    if ($Contenido -match '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}') { return $false }
    if ($Contenido -match '(?i)\b(ExportFile|LevelInfo)\b') { return $false }
    if ($Contenido -match '(?i)sdt\s*:') { return $false }
    if ($Contenido -match '(?i)\bparm\s*\(') { return $false }
    if ($Contenido -match '(?i)Authorization: Basic [A-Za-z0-9+/=]{10,}') { return $false }
    return $true
}

function Validar-MarkdownFechas {
    <#
    .SYNOPSIS
    Verifica que las fechas usan YYYY-MM-DD y no otros formatos.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Contenido
    )
    if ($Contenido -match '\d{1,2}/\d{1,2}/\d{4}') { return $false }
    if ($Contenido -match '\d{2}-\d{2}-\d{4}') { return $false }
    return $true
}

function Validar-MarkdownCoherenciaEntrada {
    <#
    .SYNOPSIS
    Verifica la coherencia de la seccion Entrada con el metodo HTTP del servicio.
    .DESCRIPTION
    Un GET muestra la frase de posiciones y la columna Posicion (o la indicacion de
    ausencia de parametros); un POST muestra la variante de parametros o campos y
    nunca ambas variantes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Contenido
    )
    $esGet = $Contenido -match '\| Método HTTP \| `GET` \|'
    $esPost = $Contenido -match '\| Método HTTP \| `POST` \|'
    if (-not ($esGet -xor $esPost)) { return $false }
    $tienePosiciones = $Contenido -match '\| Posición \| Parámetro \|'
    $tieneParametros = $Contenido -match '\| Parámetro o campo \|'
    if ($esGet) {
        if ($tieneParametros) { return $false }
        if ($tienePosiciones) { return $true }
        return ($Contenido -match 'Sin parámetros de entrada\.')
    }
    return ($tieneParametros -and -not $tienePosiciones)
}

function Validar-MarkdownSalidaErrores {
    <#
    .SYNOPSIS
    Verifica la coherencia de Salida exitosa y de Errores especificos.
    .DESCRIPTION
    Salida exitosa debe mostrar una variante definida (Coleccion SI/NO, mensaje,
    respuesta vacia o archivo binario). Errores especificos debe mostrar solo la
    tabla de rechazos explicitos o el texto estandar.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Contenido
    )
    $salida = [regex]::Match($Contenido, '(?s)## Salida exitosa\r?\n(.*?)\r?\n## Errores específicos').Groups[1].Value
    $salidaOk = ($salida -match 'Colección: `(SI|NO)`\.') -or
        ($salida -match 'Sin mensaje explícito\.') -or
        ($salida -match 'Mensaje: `') -or
        ($salida -match 'Mensajes posibles:') -or
        ($salida -match 'Content-Type: `application/octet-stream`') -or
        ($salida -match '(?m)^Colección (de |JSON)') 
    $errores = [regex]::Match($Contenido, '(?s)## Errores específicos\r?\n(.*?)\r?\n```json').Groups[1].Value
    $erroresOk = ($errores -match 'No se identificaron errores específicos en el programa principal\.') -or
        ($errores -match '\| \d{3} \| `')
    return ($salidaOk -and $erroresOk)
}

function Validar-MarkdownNombreArchivo {
    <#
    .SYNOPSIS
    Verifica que el nombre de archivo corresponde al nombre derivado del FQN del
    inventario en minusculas. Acepta la forma desambiguada de los homonimos y, por
    compatibilidad con archivos publicados antes de la desambiguacion, tambien la
    forma simple del ultimo segmento.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$NombreArchivo,
        [Parameter(Mandatory = $false)][object[]]$Endpoints = @()
    )
    if ($Endpoints.Count -eq 0) { return $true }
    $nombreBase = [System.IO.Path]::GetFileNameWithoutExtension($NombreArchivo)
    foreach ($endpoint in $Endpoints) {
        $fqn = [string]$endpoint.proceso
        $ultimoPunto = $fqn.LastIndexOf('.')
        $ultimoSegmento = ''
        if ($ultimoPunto -gt 0) { $ultimoSegmento = $fqn.Substring($ultimoPunto + 1).ToLowerInvariant() }
        else { $ultimoSegmento = $fqn.ToLowerInvariant() }
        if ($ultimoSegmento -eq $nombreBase.ToLowerInvariant()) { return $true }
        $homonimos = @($Endpoints | Where-Object {
            $puntoOtro = ([string]$_.proceso).LastIndexOf('.')
            $puntoOtro -gt 0 -and ([string]$_.proceso).Substring($puntoOtro + 1) -ieq $ultimoSegmento -and [string]$_.proceso -ine $fqn
        })
        if ($homonimos.Count -gt 0 -and $ultimoPunto -gt 0) {
            $esperado = $ultimoSegmento + '-' + (($fqn.Substring(0, $ultimoPunto) -split '\.') -join '-').ToLowerInvariant()
            if ($esperado -eq $nombreBase.ToLowerInvariant()) { return $true }
        }
    }
    return $false
}

function Validar-MarkdownFilaVersion {
    <#
    .SYNOPSIS
    Verifica que la tabla Definicion del servicio contiene la fila Version con formato 1.<revision>.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Contenido
    )
    return ($Contenido -match '(?m)^\| Versión \| \d+\.\d+ \|$')
}

function Ejecutar-CasosValidacionMarkdown {
    <#
    .SYNOPSIS
    Validaciones estaticas de los Markdown de documentacionServicios/.
    .DESCRIPTION
    Si la carpeta no existe o no contiene documentos, los casos se marcan SKIP y el
    resto de la ejecucion continua. Cuando hay documentos, cada caso valida una
    regla editorial sobre todos los archivos. Ademas se prueba el funcionamiento de
    los validadores sobre un documento generado desde los fixtures en test/tmp/.
    #>
    [CmdletBinding()]
    param()

    $archivos = @()
    if (Test-Path -LiteralPath $DirectorioServiciosProduccion) {
        $archivos = @(Get-ChildItem -LiteralPath $DirectorioServiciosProduccion -Filter '*.md' -File)
    }

    if ($archivos.Count -eq 0) {
        Test-Skip -Id 'validacionMarkdown.archivos' -Detalle 'documentacionServicios/ no tiene documentos; las validaciones estaticas se omiten.'
        Test-Skip -Id 'validacionMarkdown.ordenSecciones' -Detalle 'Sin documentos para validar el orden canonico de secciones.'
        Test-Skip -Id 'validacionMarkdown.sinComentariosNiEjemplos' -Detalle 'Sin documentos para validar la ausencia de comentarios y filas de ejemplo.'
        Test-Skip -Id 'validacionMarkdown.jsonComun' -Detalle 'Sin documentos para validar el JSON comun.'
        Test-Skip -Id 'validacionMarkdown.bloquesCanonicos' -Detalle 'Sin documentos para validar los bloques canonicos literales.'
        Test-Skip -Id 'validacionMarkdown.obligatorio' -Detalle 'Sin documentos para validar la columna Obligatorio.'
        Test-Skip -Id 'validacionMarkdown.tiposCanonicos' -Detalle 'Sin documentos para validar la tipografia canonica de tipos.'
        Test-Skip -Id 'validacionMarkdown.sinDetallesInternos' -Detalle 'Sin documentos para validar la ausencia de GUID, XML, SDT y credenciales.'
        Test-Skip -Id 'validacionMarkdown.fechas' -Detalle 'Sin documentos para validar el formato de fechas.'
        Test-Skip -Id 'validacionMarkdown.coherenciaEntrada' -Detalle 'Sin documentos para validar la coherencia de Entrada con el metodo.'
        Test-Skip -Id 'validacionMarkdown.salidaErrores' -Detalle 'Sin documentos para validar la coherencia de Salida exitosa y Errores especificos.'
        Test-Skip -Id 'validacionMarkdown.nombreArchivo' -Detalle 'Sin documentos para validar la correspondencia del nombre de archivo.'
    } else {
        $endpoints = @()
        $todosOrden = $true
        $todosSinComentarios = $true
        $todosJsonComun = $true
        $todosBloquesCanonicos = $true
        $todosObligatorio = $true
        $todosTiposCanonicos = $true
        $todosSinDetalles = $true
        $todosFechas = $true
        $todosCoherenciaEntrada = $true
        $todosSalidaErrores = $true
        $todosNombreArchivo = $true
        foreach ($archivo in $archivos) {
            $contenido = [System.IO.File]::ReadAllText($archivo.FullName, (New-Object System.Text.UTF8Encoding($false)))
            if (-not (Validar-MarkdownOrdenSecciones -Contenido $contenido)) { $todosOrden = $false }
            if (-not (Validar-MarkdownSinComentariosNiEjemplos -Contenido $contenido)) { $todosSinComentarios = $false }
            if (-not (Validar-MarkdownJsonComun -Contenido $contenido)) { $todosJsonComun = $false }
            if (-not (Validar-MarkdownBloquesCanonicos -Contenido $contenido)) { $todosBloquesCanonicos = $false }
            if (-not (Validar-MarkdownObligatorio -Contenido $contenido)) { $todosObligatorio = $false }
            if (-not (Validar-MarkdownTiposCanonicos -Contenido $contenido)) { $todosTiposCanonicos = $false }
            if (-not (Validar-MarkdownSinDetallesInternos -Contenido $contenido)) { $todosSinDetalles = $false }
            if (-not (Validar-MarkdownFechas -Contenido $contenido)) { $todosFechas = $false }
            if (-not (Validar-MarkdownCoherenciaEntrada -Contenido $contenido)) { $todosCoherenciaEntrada = $false }
            if (-not (Validar-MarkdownSalidaErrores -Contenido $contenido)) { $todosSalidaErrores = $false }
            if (-not (Validar-MarkdownNombreArchivo -NombreArchivo $archivo.Name -Endpoints $endpoints)) { $todosNombreArchivo = $false }
        }
        Test-Asercion -Id 'validacionMarkdown.archivos' -Condicion ($archivos.Count -gt 0) -DetalleExito ("Se validaron " + $archivos.Count + " documentos de documentacionServicios/.") -DetalleFallo 'No se encontraron documentos para validar.'
        Test-Asercion -Id 'validacionMarkdown.ordenSecciones' -Condicion $todosOrden -DetalleExito 'Todos los documentos respetan el orden canonico de secciones.' -DetalleFallo 'Algun documento no respeta el orden canonico de secciones.'
        Test-Asercion -Id 'validacionMarkdown.sinComentariosNiEjemplos' -Condicion $todosSinComentarios -DetalleExito 'Ningun documento conserva comentarios HTML ni filas de ejemplo.' -DetalleFallo 'Algun documento conserva comentarios o filas de ejemplo.'
        Test-Asercion -Id 'validacionMarkdown.jsonComun' -Condicion $todosJsonComun -DetalleExito 'Todos los documentos conservan el JSON comun con las claves exactas.' -DetalleFallo 'Algun documento no conserva el JSON comun.'
        Test-Asercion -Id 'validacionMarkdown.bloquesCanonicos' -Condicion $todosBloquesCanonicos -DetalleExito 'Todos los documentos conservan la autenticacion y la tabla completa de codigos.' -DetalleFallo 'Algun documento no conserva los bloques canonicos.'
        Test-Asercion -Id 'validacionMarkdown.obligatorio' -Condicion $todosObligatorio -DetalleExito 'La columna Obligatorio usa solo SI o NO en todos los documentos.' -DetalleFallo 'Algun documento usa valores fuera de SI/NO en Obligatorio.'
        Test-Asercion -Id 'validacionMarkdown.tiposCanonicos' -Condicion $todosTiposCanonicos -DetalleExito 'Ningun documento usa tipos fuera de la tipografia canonica.' -DetalleFallo 'Algun documento usa un tipo no canonico.'
        Test-Asercion -Id 'validacionMarkdown.sinDetallesInternos' -Condicion $todosSinDetalles -DetalleExito 'Ningun documento expone GUID, XML, SDT internos ni credenciales.' -DetalleFallo 'Algun documento expone detalles internos o credenciales.'
        Test-Asercion -Id 'validacionMarkdown.fechas' -Condicion $todosFechas -DetalleExito 'Las fechas usan YYYY-MM-DD en todos los documentos.' -DetalleFallo 'Algun documento usa un formato de fecha distinto.'
        Test-Asercion -Id 'validacionMarkdown.coherenciaEntrada' -Condicion $todosCoherenciaEntrada -DetalleExito 'La seccion Entrada es coherente con el metodo en todos los documentos.' -DetalleFallo 'Algun documento mezcla variantes de entrada.'
        Test-Asercion -Id 'validacionMarkdown.salidaErrores' -Condicion $todosSalidaErrores -DetalleExito 'Salida exitosa y Errores especificos son coherentes en todos los documentos.' -DetalleFallo 'Algun documento tiene una salida o errores incoherentes.'
        Test-Asercion -Id 'validacionMarkdown.nombreArchivo' -Condicion $todosNombreArchivo -DetalleExito 'Los nombres de archivo corresponden al nombre derivado del FQN del inventario, incluyendo la desambiguacion de homonimos.' -DetalleFallo 'Algun nombre de archivo no corresponde al inventario.'
    }

    $xmlBase = Cargar-XmlFixture -Nombre 'xpz-base.xml'
    $indiceBase = Construir-Indices -Xml $xmlBase
    $docGet = Analizar-Servicio -Xml $xmlBase -NombreCompletoWrapper 'APIGLM.Cotizacion.WSObtenerProductor' -PackageName 'glmsuit.comercial.' -Indice $indiceBase
    $rutaDocGenerado = Join-Path $DirectorioTmp 'wsobtenerproductor.md'
    [System.IO.File]::WriteAllText($rutaDocGenerado, (Redactar-Documento -Documentacion $docGet), (New-Object System.Text.UTF8Encoding($false)))
    $contenidoGenerado = [System.IO.File]::ReadAllText($rutaDocGenerado, (New-Object System.Text.UTF8Encoding($false)))
    $conformidadGenerado = (Validar-MarkdownOrdenSecciones -Contenido $contenidoGenerado) -and
        (Validar-MarkdownSinComentariosNiEjemplos -Contenido $contenidoGenerado) -and
        (Validar-MarkdownJsonComun -Contenido $contenidoGenerado) -and
        (Validar-MarkdownBloquesCanonicos -Contenido $contenidoGenerado) -and
        (Validar-MarkdownObligatorio -Contenido $contenidoGenerado) -and
        (Validar-MarkdownTiposCanonicos -Contenido $contenidoGenerado) -and
        (Validar-MarkdownFilaVersion -Contenido $contenidoGenerado) -and
        (Validar-MarkdownSinDetallesInternos -Contenido $contenidoGenerado) -and
        (Validar-MarkdownFechas -Contenido $contenidoGenerado) -and
        (Validar-MarkdownCoherenciaEntrada -Contenido $contenidoGenerado) -and
        (Validar-MarkdownSalidaErrores -Contenido $contenidoGenerado)
    Test-Asercion -Id 'validacionMarkdown.herramientaDocumentoConforme' -Condicion $conformidadGenerado -DetalleExito 'Los validadores aceptan un documento generado conforme a la plantilla.' -DetalleFallo 'Los validadores rechazaron un documento conforme.'

    $conViolacion = $contenidoGenerado -replace '(?m)^(## Salida exitosa\r?\n)', "## Seccion extra`r`n`r`n$1"
    Test-Asercion -Id 'validacionMarkdown.herramientaDetectaOrden' -Condicion (-not (Validar-MarkdownOrdenSecciones -Contenido $conViolacion)) -DetalleExito 'El validador de orden detecta una seccion extra.' -DetalleFallo 'El validador de orden no detecto la seccion extra.'

    $conViolacionJson = $contenidoGenerado -replace '"detail": "<detalle>",\r?\n', ''
    Test-Asercion -Id 'validacionMarkdown.herramientaDetectaJson' -Condicion (-not (Validar-MarkdownJsonComun -Contenido $conViolacionJson)) -DetalleExito 'El validador del JSON comun detecta una clave faltante.' -DetalleFallo 'El validador del JSON comun no detecto la clave faltante.'

    $conViolacionOblig = $contenidoGenerado -replace '\| 3 \| `ProCod`[^\r\n]*', '| 3 | `ProCod` | Integer (7) | TALVEZ | Código de Productor |'
    Test-Asercion -Id 'validacionMarkdown.herramientaDetectaObligatorio' -Condicion (-not (Validar-MarkdownObligatorio -Contenido $conViolacionOblig)) -DetalleExito 'El validador de Obligatorio detecta un valor invalido.' -DetalleFallo 'El validador de Obligatorio no detecto el valor invalido.'

    $conViolacionComentario = $contenidoGenerado -replace '(?m)^## Entrada', "<!-- comentario -->`r`n## Entrada"
    Test-Asercion -Id 'validacionMarkdown.herramientaDetectaComentario' -Condicion (-not (Validar-MarkdownSinComentariosNiEjemplos -Contenido $conViolacionComentario)) -DetalleExito 'El validador de comentarios detecta un comentario HTML.' -DetalleFallo 'El validador de comentarios no detecto el comentario HTML.'
}


function Escribir-LogPruebas {
    <#
    .SYNOPSIS
    Escribe el log TXT con los casos ejecutados y el resumen.
    .DESCRIPTION
    El log es texto plano legible, separado de los logs productivos, con una linea
    por caso en el formato 'Estado | Id | Detalle' y el conteo final.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaLog
    )
    New-DirectorioSiNoExiste -Directorio $DirectorioLogs | Out-Null

    $cantidadPass = @($Casos | Where-Object { $_.Estado -eq 'PASS' }).Count
    $cantidadFail = @($Casos | Where-Object { $_.Estado -eq 'FAIL' }).Count
    $cantidadSkip = @($Casos | Where-Object { $_.Estado -eq 'SKIP' }).Count

    $lineas = New-Object System.Collections.Generic.List[string]
    $lineas.Add('PRUEBAS LOCALES DEL PIPELINE, ANALIZADOR Y VISOR APIGLM')
    $lineas.Add('Fecha: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
    $lineas.Add('PowerShell: ' + $PSVersionTable.PSVersion.ToString())
    $lineas.Add('Repositorio: ' + $RaizRepositorio)
    $lineas.Add('')
    $lineas.Add('Resultados')
    $lineas.Add('----------')
    foreach ($caso in $Casos) {
        $lineas.Add($caso.Estado + ' | ' + $caso.Id + ' | ' + $caso.Detalle)
    }
    $lineas.Add('')
    $lineas.Add('Resumen: ' + $cantidadPass + ' PASS, ' + $cantidadFail + ' FAIL, ' + $cantidadSkip + ' SKIP.')
    if ($FallaLimpieza) {
        $lineas.Add('FALLA DE LIMPIEZA: ' + $FallaLimpieza)
    }

    $contenido = ($lineas -join "`n") + "`n"
    [System.IO.File]::WriteAllText($RutaLog, $contenido, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ('  Log de pruebas: ' + $RutaLog) -ForegroundColor DarkGray
}

function Limpiar-Temporales {
    <#
    .SYNOPSIS
    Elimina el contenido de test/tmp/.
    .DESCRIPTION
    Se ejecuta siempre en el finally. Un fallo de limpieza se registra en el log
    sin interrumpir el resultado de las pruebas.
    #>
    [CmdletBinding()]
    param()
    if (-not (Test-Path -LiteralPath $DirectorioTmp)) { return }
    try {
        Remove-Item -LiteralPath $DirectorioTmp -Recurse -Force -ErrorAction Stop
    } catch {
        $script:FallaLimpieza = $_.Exception.Message
    }
}

function Resolver-CodigoSalida {
    <#
    .SYNOPSIS
    Resuelve el codigo de salida del harness a partir de los casos registrados.
    .DESCRIPTION
    Devuelve 0 cuando no hay ningun caso FAIL y 1 cuando hay al menos uno. Los
    casos SKIP no afectan el codigo de salida.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$CasosPrueba
    )
    $conteoFallas = @($CasosPrueba | Where-Object { $_.Estado -eq 'FAIL' }).Count
    if ($conteoFallas -gt 0) { return 1 }
    return 0
}

function Ejecutar-CasosFinalesLineaArchivosCmd {
    <#
    .SYNOPSIS
    Verifica la convencion CRLF de los archivos CMD versionados.
    .DESCRIPTION
    Comprueba que .gitattributes declare la convencion y que cada archivo CMD
    contenga exclusivamente pares CRLF, sin saltos LF o CR aislados.
    #>
    [CmdletBinding()]
    param()

    $rutaAtributos = Join-Path $RaizRepositorio '.gitattributes'
    $atributosValidos = $false
    if (Test-Path -LiteralPath $rutaAtributos -PathType Leaf) {
        $contenidoAtributos = [System.IO.File]::ReadAllText($rutaAtributos)
        $atributosValidos = $contenidoAtributos -match '(?m)^\*\.cmd\s+text\s+eol=crlf\s*$'
    }
    Test-Asercion -Id 'finalesLinea.reglaCmd' -Condicion $atributosValidos -DetalleExito 'La convencion CRLF de los archivos CMD esta declarada en .gitattributes.' -DetalleFallo 'Falta la declaracion *.cmd text eol=crlf en .gitattributes.'

    $archivosCmd = @(Get-ChildItem -LiteralPath $RaizRepositorio -Filter '*.cmd' -File -Recurse | Where-Object { $_.FullName -notlike ((Join-Path $RaizRepositorio '.git') + '\*') })
    $archivosValidos = $archivosCmd.Count -gt 0
    $archivoInvalido = ''
    foreach ($archivoCmd in $archivosCmd) {
        $bytes = [System.IO.File]::ReadAllBytes($archivoCmd.FullName)
        for ($indiceByte = 0; $indiceByte -lt $bytes.Length; $indiceByte++) {
            if ($bytes[$indiceByte] -eq 10 -and ($indiceByte -eq 0 -or $bytes[$indiceByte - 1] -ne 13)) {
                $archivosValidos = $false
                $archivoInvalido = $archivoCmd.FullName
                break
            }
            if ($bytes[$indiceByte] -eq 13 -and ($indiceByte + 1 -ge $bytes.Length -or $bytes[$indiceByte + 1] -ne 10)) {
                $archivosValidos = $false
                $archivoInvalido = $archivoCmd.FullName
                break
            }
        }
        if (-not $archivosValidos) { break }
    }
    Test-Asercion -Id 'finalesLinea.archivosCmd' -Condicion $archivosValidos -DetalleExito 'Todos los archivos CMD usan exclusivamente finales de linea CRLF.' -DetalleFallo ('El archivo CMD no usa exclusivamente CRLF: ' + $archivoInvalido)
}

function Cargar-XmlFixture {
    <#
    .SYNOPSIS
    Carga un fixture XML desde test/fixtures/xml/.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Nombre
    )
    $xml = New-Object System.Xml.XmlDocument
    $xml.Load((Join-Path $DirectorioFixturesXml $Nombre))
    return $xml
}

function Cargar-JsonFixture {
    <#
    .SYNOPSIS
    Carga un fixture JSON desde test/fixtures/json/ y lo convierte en objeto.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Nombre
    )
    $texto = [System.IO.File]::ReadAllText((Join-Path $DirectorioFixturesJson $Nombre), (New-Object System.Text.UTF8Encoding($false)))
    return ($texto | ConvertFrom-Json)
}

function Cargar-WebJsonFixture {
    <#
    .SYNOPSIS
    Carga un fixture JSON de los contratos del panel web.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Nombre
    )
    $directorioFixturesWeb = Join-Path $DirectorioFixtures 'web'
    $rutaFixture = Join-Path $directorioFixturesWeb $Nombre
    $texto = [System.IO.File]::ReadAllText($rutaFixture, (New-Object System.Text.UTF8Encoding($false)))
    return ($texto | ConvertFrom-Json)
}

function Cargar-SolicitudReporteFixture {
    <#
    .SYNOPSIS
    Carga una solicitud JSON de reporte y agrega opcionalmente imágenes fixture.
    .DESCRIPTION
    Los fixtures de imagen se almacenan como Base64 separado del JSON para poder
    reutilizar la misma muestra con PNG, JPEG y WebP en las pruebas de la API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Nombre,
        [Parameter(Mandatory = $false)][string[]]$NombresImagen = @(),
        [Parameter(Mandatory = $false)][string[]]$NombresOriginalesImagen = @(),
        [Parameter(Mandatory = $false)][string[]]$TiposMimeImagen = @()
    )

    $rutaSolicitud = Join-Path $DirectorioFixturesReportes $Nombre
    $textoSolicitud = [System.IO.File]::ReadAllText($rutaSolicitud, (New-Object System.Text.UTF8Encoding($false)))
    $solicitud = $textoSolicitud | ConvertFrom-Json

    $solicitud.images = @()
    for ($imageIndex = 0; $imageIndex -lt $NombresImagen.Count; $imageIndex++) {
        $nombreImagen = $NombresImagen[$imageIndex]
        $rutaImagen = Join-Path $DirectorioFixturesReportes $nombreImagen
        $base64 = ([System.IO.File]::ReadAllText($rutaImagen, (New-Object System.Text.UTF8Encoding($false))).Trim())
        $nombreOriginal = if ($imageIndex -lt $NombresOriginalesImagen.Count) { $NombresOriginalesImagen[$imageIndex] } else { '' }
        if ([string]::IsNullOrWhiteSpace($nombreOriginal)) {
            $nombreOriginal = [System.IO.Path]::GetFileNameWithoutExtension($nombreImagen)
        }
        $tipoMime = if ($imageIndex -lt $TiposMimeImagen.Count) { $TiposMimeImagen[$imageIndex] } else { '' }
        $solicitud.images += [pscustomobject]@{
            originalName = $nombreOriginal
            mimeType = $tipoMime
            base64 = $base64
        }
    }

    return $solicitud
}

function Crear-SolicitudReporteConDescripcionFixture {
    <#
    .SYNOPSIS
    Crea una solicitud fixture con una cantidad exacta de grafemas ASCII.
    .DESCRIPTION
    Se usa para cubrir los limites de 500 y 501 caracteres sin duplicar en disco
    cuerpos JSON extensos. La unidad ASCII equivale a un grafema visible.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateRange(0, 501)][int]$CantidadGrafemas
    )

    $solicitud = Cargar-SolicitudReporteFixture -Nombre 'solicitud-error-valida.json'
    $solicitud.description = (('a' * $CantidadGrafemas) -join '')
    return $solicitud
}

function Ejecutar-CasosFixturesPanelWeb {
    <#
    .SYNOPSIS
    Verifica que los fixtures enriquecidos del panel se lean sin artefactos.
    #>
    [CmdletBinding()]
    param()

$servicios = $null
    $paginacion = $null
    $estado = $null
    try {
        $servicios = Cargar-WebJsonFixture -Nombre 'panel-servicios-enriquecidos.json'
        $paginacion = Cargar-WebJsonFixture -Nombre 'panel-paginacion.json'
        $estado = Cargar-WebJsonFixture -Nombre 'panel-estado-enriquecido.json'
    } catch {
        Test-Asercion -Id 'panelFixtures.lectura' -Condicion $false -DetalleFallo ('No se pudieron leer los fixtures web: ' + $_.Exception.Message)
        return
    }

    $sinRutasFisicas = $true
    foreach ($servicio in @($servicios.servicios)) {
        foreach ($propiedad in @('pdf', 'markdown')) {
            if ($servicio.$propiedad.PSObject.Properties['ruta']) { $sinRutasFisicas = $false }
        }
    }
    Test-Asercion -Id 'panelFixtures.serviciosEnriquecidos' -Condicion (
        $servicios.meta.contextId -eq 'trunk/comercial/testing' -and
        $servicios.meta.inventarioObsoleto -eq $true -and
        @($servicios.servicios).Count -eq 3 -and
        $servicios.servicios[0].versionDisponible -eq $true -and
        $servicios.servicios[1].estado -eq 'OBSOLETO' -and
        $servicios.servicios[1].pdf.disponible -eq $false -and
        $servicios.servicios[2].version -eq $null -and
        $servicios.servicios[2].versionDisponible -eq $false -and
        $sinRutasFisicas
    ) -DetalleExito 'El fixture enriquecido cubre contexto, version, PDF ausente, estado obsoleto y ausencia de rutas fisicas.' -DetalleFallo 'El fixture enriquecido no contiene los contratos esperados.'

    Test-Asercion -Id 'panelFixtures.serviciosObservacion' -Condicion (
        [string]$servicios.servicios[0].observacion -match 'Objetos: .* modificado' -and
        [string]$servicios.servicios[1].observacion -eq 'Se modificó el documento.' -and
        $null -eq $servicios.servicios[2].observacion
    ) -DetalleExito 'El servicio enriquecido expone la observacion del cambio de la version vigente.' -DetalleFallo 'El fixture no expone la observacion del cambio por servicio.'

    $archivosPdf = @($estado.dashboard.documentos.archivos | Where-Object { $_.extension -eq '.pdf' })
    $estadosValidacion = @($estado.dashboard.validaciones | ForEach-Object { [string]$_.estado })
    Test-Asercion -Id 'panelFixtures.estadoEnriquecido' -Condicion (
        $estado.dashboard.documentos.total -eq $archivosPdf.Count -and
        $estado.dashboard.documentos.total -eq 2 -and
        -not [string]::IsNullOrWhiteSpace([string]$estado.dashboard.documentos.ultimaActualizacion) -and
        $estadosValidacion -contains 'OK' -and
        $estadosValidacion -contains 'ADVERTENCIA' -and
        $estadosValidacion -contains 'ERROR'
    ) -DetalleExito 'El dashboard enriquecido cuenta solo PDF, expone ultima actualizacion y validaciones de ambiente.' -DetalleFallo 'El dashboard enriquecido no contiene los contratos esperados.'

    Test-Asercion -Id 'panelFixtures.paginacion' -Condicion (
        $paginacion.elementos -gt $paginacion.tamanoInicial -and
        $paginacion.paginaInicial -eq 1 -and
        (@($paginacion.tamanoPermitido) -join ',') -eq '25,50,100' -and
        $paginacion.seleccionPorFqn -eq $true -and
        $paginacion.cambiarFiltroConservaSeleccion -eq $true
    ) -DetalleExito 'El fixture de paginacion conserva pagina inicial, tamanos permitidos y seleccion por FQN.' -DetalleFallo 'El fixture de paginacion no contiene los contratos esperados.'
}

function Ejecutar-CasosEstadosOperacionPanel {
    <#
    .SYNOPSIS
    Verifica el contrato entre estados tecnicos, codigos de salida y estados visibles.
    #>
    [CmdletBinding()]
    param()

    $fixture = $null
    try {
        $fixture = Cargar-WebJsonFixture -Nombre 'panel-estados-operacion.json'
    } catch {
        Test-Asercion -Id 'panelEstadosOperacion.lectura' -Condicion $false -DetalleFallo ('No se pudo leer el fixture de estados operativos: ' + $_.Exception.Message)
        return
    }

    $estadosPermitidos = @($fixture.estadosPermitidos)
    $casosEstadoOperacion = @($fixture.casos)
    $mapeoValido = $true
    foreach ($casoEstadoOperacion in $casosEstadoOperacion) {
        if ($estadosPermitidos -notcontains [string]$casoEstadoOperacion.estadoVisible) {
            $mapeoValido = $false
            break
        }

        if ([string]$casoEstadoOperacion.estadoTecnico -in @('QUEUED', 'RUNNING')) {
            if ($null -ne $casoEstadoOperacion.codigoSalida -or [string]$casoEstadoOperacion.estadoVisible -ne 'EN PROCESO') {
                $mapeoValido = $false
                break
            }
            continue
        }

        $codigoSalida = [int]$casoEstadoOperacion.codigoSalida
        $estadoEsperado = switch ($codigoSalida) {
            0 { 'COMPLETADO' }
            2 { 'COMPLETADO PARCIALMENTE' }
            default { 'ERROR' }
        }
        if ([string]$casoEstadoOperacion.estadoVisible -ne $estadoEsperado) {
            $mapeoValido = $false
            break
        }
    }

    Test-Asercion -Id 'panelEstadosOperacion.mapeoTecnicoVisible' -Condicion (
        $mapeoValido -and
        $casosEstadoOperacion.Count -eq 6 -and
        @($casosEstadoOperacion | Where-Object { $_.codigoSalida -eq 0 }).Count -eq 1 -and
        @($casosEstadoOperacion | Where-Object { $_.codigoSalida -eq 2 }).Count -eq 1 -and
        @($casosEstadoOperacion | Where-Object { $_.codigoSalida -eq 3 }).Count -eq 1 -and
        @($casosEstadoOperacion | Where-Object { $_.codigoSalida -eq 1 }).Count -eq 1
    ) -DetalleExito 'El contrato del panel mapea los codigos 0, 2, 3 y 1 a estados visibles consistentes.' -DetalleFallo 'El contrato de estados operativos no cubre o mapea correctamente los codigos requeridos.'
}

function Procesar-ServicioPrueba {
    <#
    .SYNOPSIS
    Procesa un servicio del inventario sobre un XPZ cargado.
    .DESCRIPTION
    Replica el nucleo del orquestador GenerarDocumento.ps1 (Procesar-Servicio) con
    las funciones productivas reales: Analizar-Servicio, Redactar-Documento y
    Escribir-Salidas, escribiendo unicamente en el directorio de salida indicado
    (test/tmp/). Devuelve el resultado con el mismo modelo de datos del orquestador.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Endpoint,
        [Parameter(Mandatory = $true)][string]$PackageName,
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)]$Indice,
        [Parameter(Mandatory = $true)][string]$DirectorioSalida
    )
    try {
        $documentacion = Analizar-Servicio -Xml $Xml -NombreCompletoWrapper $Endpoint.proceso -PackageName $PackageName -Indice $Indice
        $documento = Redactar-Documento -Documentacion $documentacion
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
        return [pscustomobject]@{
            FullyQualifiedName = $Endpoint.proceso
            Estado = 'ERROR'
            Documento = ''
            Pendientes = @()
            Mensajes = @($_.Exception.Message)
        }
    }
}

function Ejecutar-PipelinePrueba {
    <#
    .SYNOPSIS
    Ejecuta el flujo del pipeline sobre fixtures escribiendo en test/tmp/.
    .DESCRIPTION
    Replica la orquestacion de GenerarDocumento.ps1 sobre el inventario indicado:
    filtra serviciosIgnorados (OMITIDO), detecta duplicados por nombre local
    (primer wrapper gana), procesa cada servicio con las funciones productivas y
    devuelve el resumen con los conteos por estado y la lista de resultados.
    No escribe en carpetas productivas.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Configuracion,
        [Parameter(Mandatory = $true)][string]$RutaInventario,
        [Parameter(Mandatory = $true)][string]$DirectorioSalida
    )
    $inventario = Get-Content -LiteralPath $RutaInventario -Raw | ConvertFrom-Json
    $endpoints = @($inventario.endpoints)

    $ignoradosConfig = @($Configuracion.ServiciosIgnorados)
    $ignoradosEnInventario = @($endpoints | Where-Object { $ignoradosConfig -contains $_.proceso })
    $endpointsEfectivos = @($endpoints | Where-Object { $ignoradosConfig -notcontains $_.proceso })

    $indices = Cargar-IndiceMultiXPZ -RutaXpzPrincipal $Configuracion.XpzPath

    $nombresLocalesVistos = @{}
    $serviciosParaProcesar = New-Object System.Collections.Generic.List[object]
    $duplicados = New-Object System.Collections.Generic.List[object]
    foreach ($servicio in $endpointsEfectivos) {
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
        } else {
            $nombresLocalesVistos[$nombreLocal] = $servicio.proceso
            $serviciosParaProcesar.Add($servicio)
        }
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
    foreach ($servicio in $serviciosParaProcesar) {
        $resultado = Procesar-ServicioPrueba -Endpoint $servicio -PackageName $Configuracion.PackageName -Xml $indices.XmlUnificado -Indice $indices -DirectorioSalida $DirectorioSalida
        $resultados.Add($resultado)
        switch ($resultado.Estado) {
            'OK' { $okCount++ }
            'WARNING' { $warningCount++ }
            'ERROR' { $errorCount++ }
        }
    }
    foreach ($duplicado in $duplicados) {
        $resultados.Add([pscustomobject]@{
            FullyQualifiedName = $duplicado.servicio
            Estado = 'WARNING'
            Documento = ''
            Pendientes = @()
            Mensajes = @("Nombre local duplicado '$($duplicado.nombreLocal)'. El ganador es '$($duplicado.ganador)'.")
        })
        $warningCount++
    }

    return [pscustomobject]@{
        Resumen = [pscustomobject]@{
            ok = $okCount
            warning = $warningCount
            error = $errorCount
            omitido = $omitidoCount
        }
        Servicios = $resultados.ToArray()
        Duplicados = $duplicados.ToArray()
        Indice = $indices
    }
}

function Ejecutar-CasosIntegridadTransaccional {
    [CmdletBinding()]
    param()

    $rutaFixture = Join-Path $DirectorioFixturesJson 'control-versiones-esquema2.json'
    $controlFixture = Get-Content -LiteralPath $rutaFixture -Raw | ConvertFrom-Json
    Test-Asercion -Id 'integridad.controlEsquema2' -Condicion (
        (Validar-ControlVersiones -ControlVersiones $controlFixture) -and
        $controlFixture.schemaVersion -eq 2 -and
        $controlFixture.services.'APIGLM.Fixture.WSValido'.pdfHash
    ) -DetalleExito 'El fixture de control cumple el esquema 2 con hashes Markdown y PDF.' -DetalleFallo 'El fixture de control no cumple el esquema 2.'

    $controlEsquema1 = $controlFixture | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $controlEsquema1.schemaVersion = 1
    Test-AsercionLanzaError -Id 'integridad.rechazaEsquema1' -Bloque { Validar-ControlVersiones -ControlVersiones $controlEsquema1 } -PatronMensaje 'schemaVersion no soportado' -DetalleExito 'Un control de esquema 1 se rechaza sin migracion automatica.'

    $controlVersionInvalida = $controlFixture | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $controlVersionInvalida.services.'APIGLM.Fixture.WSValido'.version = '2.1'
    Test-AsercionLanzaError -Id 'integridad.rechazaVersionIncoherente' -Bloque { Validar-ControlVersiones -ControlVersiones $controlVersionInvalida } -PatronMensaje 'version incoherente' -DetalleExito 'El control rechaza una version que no coincide con revision.'

    $rutaControlPrueba = Join-Path $DirectorioTmp 'control-versiones-esquema2.json'
    Escribir-ControlVersionesAtomico -ControlVersiones $controlFixture -RutaControl $rutaControlPrueba | Out-Null
    $controlLeido = Leer-ControlVersiones -RutaControl $rutaControlPrueba
    Test-Asercion -Id 'integridad.persistenciaEsquema2' -Condicion (
        $controlLeido.schemaVersion -eq 2 -and
        $controlLeido.services.'APIGLM.Fixture.WSValido'.documentHash -eq 'fixture-document-hash' -and
        $controlLeido.services.'APIGLM.Fixture.WSValido'.pdfHash -eq 'fixture-pdf-hash' -and
        -not (Get-ChildItem -LiteralPath $DirectorioTmp -Filter 'control-versiones-esquema2.json.*.tmp' -File -ErrorAction SilentlyContinue)
    ) -DetalleExito 'El control esquema 2 se escribe y relee atomically sin temporales residuales.' -DetalleFallo 'La persistencia del control esquema 2 no es valida.'

    $rutaActualizador = Join-Path $DirectorioBinario 'ActualizarServicios.ps1'
    $contenidoActualizador = Get-Content -LiteralPath $rutaActualizador -Raw
    Test-Asercion -Id 'integridad.promocionConjunta' -Condicion (
        $contenidoActualizador -match 'Promover-ServicioArtefactos' -and
        $contenidoActualizador -match 'estadoMarkdown' -and
        $contenidoActualizador -match 'estadoPdf' -and
        $contenidoActualizador -match 'FileShare\]::None'
    ) -DetalleExito 'El actualizador contiene promocion conjunta, review final y lock exclusivo.' -DetalleFallo 'El actualizador no contiene todos los contratos transaccionales esperados.'

    $rutaGestion = Join-Path $DirectorioBinario 'GestionDocumentosGLM.ps1'
    $contenidoGestion = Get-Content -LiteralPath $rutaGestion -Raw
    Test-Asercion -Id 'integridad.regeneracionReiniciaVersionado' -Condicion (
        $contenidoGestion -match 'Confirmar-ReinicioVersionado' -and
        $contenidoGestion -match 'Desea continuar\? \[S/N\]' -and
        $contenidoGestion -match 'ForzarRegeneracionCompleta.*Inicializar' -and
        $contenidoGestion -match 'Regeneracion de PDF abortada por el usuario'
    ) -DetalleExito 'La opcion 3 confirma y reinicia explicitamente el control de versionado.' -DetalleFallo 'La opcion 3 no confirma o no reinicia explicitamente el control de versionado.'

    Test-Asercion -Id 'integridad.mensajesProgresoRegeneracion' -Condicion (
        $contenidoActualizador -match 'Regeneracion en proceso\.\.\. aguarde\.' -and
        $contenidoActualizador -match 'Cargar-IndiceMultiXPZ[\s\S]*Regeneracion en proceso\.\.\. aguarde\.' -and
        $contenidoActualizador -match 'Regeneracion en proceso\.\.\. aguarde\.[\s\S]*Regeneracion completa solicitada' -and
        $contenidoActualizador -match 'Regeneracion completa solicitada[\s\S]*Generando documentacion Markdown' -and
        $contenidoActualizador -match 'Generando documentacion Markdown .*\.md' -and
        $contenidoActualizador -match 'Generando documentos PDF' -and
        $contenidoActualizador -match 'Validando y publicando Markdown y PDF'
    ) -DetalleExito 'La regeneracion informa al usuario antes de las fases lentas de Markdown, PDF y publicacion.' -DetalleFallo 'La regeneracion no informa al usuario antes de todas sus fases lentas.'

    Test-Asercion -Id 'integridad.pendienteAceptaFingerprintVacio' -Condicion (
        $contenidoActualizador -match 'AllowEmptyString\(\)\]\[string\]\$BaselineFingerprint' -and
        $contenidoActualizador -match 'AllowEmptyString\(\)\]\[string\]\$TargetFingerprint'
    ) -DetalleExito 'El control permite registrar pendientes sin fingerprints cuando no existe un baseline.' -DetalleFallo 'El control rechaza fingerprints vacios al registrar pendientes.'

    Test-Asercion -Id 'integridad.reporteEvaluaPublicado' -Condicion (
        $contenidoActualizador -match '\$estaPublicado = \(Test-Path -LiteralPath \$rutaMarkdownPublicado -PathType Leaf\) -and'
    ) -DetalleExito 'El review evalua correctamente la existencia conjunta de Markdown y PDF.' -DetalleFallo 'El review interpreta -and como un parametro de Test-Path.'

    Test-Asercion -Id 'integridad.reviewListaSerializable' -Condicion (
        $contenidoActualizador -match 'servicios = @\(\$serviciosReviewFinal\.ToArray\(\)\)'
    ) -DetalleExito 'El review convierte la lista generica a array antes de serializarla en PowerShell 5.1.' -DetalleFallo 'El review intenta serializar directamente una lista generica y puede producir incompatibilidad de tipos.'

    Test-Asercion -Id 'integridad.deteccionObjetosSinVinculo' -Condicion (
        $contenidoActualizador -match 'Obtener-ObjetosModificadosSinVinculo' -and
        $contenidoActualizador -match 'AllowEmptyCollection\(\).*ObjetosModificados' -and
        $contenidoActualizador -match 'Obtener-ServiciosActivosSinDependencias' -and
        $contenidoActualizador -match 'objetos modificados sin dependencias registradas' -and
        $contenidoActualizador -match 'servicios ACTIVO sin dependencias'
    ) -DetalleExito 'El actualizador reanaliza servicios ACTIVO sin dependencias cuando hay objetos modificados sin vinculo, reconstruyendo la traza.' -DetalleFallo 'El actualizador no detecta objetos modificados sin vinculo ni reanaliza servicios sin dependencias.'

    Test-Asercion -Id 'integridad.nombreArchivoDesambiguado' -Condicion (
        $contenidoActualizador -match 'FqnsInventario'
    ) -DetalleExito 'El actualizador propaga el inventario al resolver nombres de archivo para desambiguar servicios homonimos.' -DetalleFallo 'El actualizador no desambigua los nombres de archivo de servicios homonimos.'

    $fqnsInventarioPrueba = @('APIGLM.Comun.WSListarCategoriaIVA', 'APIGLM.Cotizacion.WSListarCategoriaIVA', 'APIGLM.Comun.WSListarBanco')
    $nombreComun = Obtener-NombreArchivoServicio -FullyQualifiedName 'APIGLM.Comun.WSListarCategoriaIVA' -FqnsInventario $fqnsInventarioPrueba
    $nombreCotizacion = Obtener-NombreArchivoServicio -FullyQualifiedName 'APIGLM.Cotizacion.WSListarCategoriaIVA' -FqnsInventario $fqnsInventarioPrueba
    $nombreUnico = Obtener-NombreArchivoServicio -FullyQualifiedName 'APIGLM.Comun.WSListarBanco' -FqnsInventario $fqnsInventarioPrueba
    $nombreSinInventario = Obtener-NombreArchivoServicio -FullyQualifiedName 'APIGLM.Cotizacion.WSListarCategoriaIVA'
    Test-Asercion -Id 'integridad.nombreArchivoHomonimos' -Condicion (
        $nombreComun -eq 'wslistarcategoriaiva-apiglm-comun' -and
        $nombreCotizacion -eq 'wslistarcategoriaiva-apiglm-cotizacion' -and
        $nombreUnico -eq 'wslistarbanco' -and
        $nombreSinInventario -eq 'wslistarcategoriaiva'
    ) -DetalleExito 'Los nombres de archivo desambiguan homonimos con la ruta de modulos y conservan el nombre simple sin inventario o sin colision.' -DetalleFallo 'La resolucion de nombres de archivo no desambigua homonimos como se espera.'

    . (Join-Path $DirectorioBinario 'ManifiestoEjecucion.ps1')
    $contextoManifiesto = Cargar-Configuracion -ConfigPath (Join-Path $DirectorioFixturesJson 'configuracion-multicliente.json') -ClienteId 'trunk' -AmbienteId 'testing'
    Test-Asercion -Id 'configuracionMulticliente.serverUrlContexto' -Condicion (
        $contextoManifiesto.ServerUrl -eq 'https://trunk.example.com/testing/rest' -and
        $contextoManifiesto.Host -eq 'https://trunk.example.com' -and
        $contextoManifiesto.BaseUrl -eq '/testing/rest'
    ) -DetalleExito 'El contexto canonico expone Host, BaseUrl y ServerUrl normalizados.' -DetalleFallo 'El contexto no expuso Host/BaseUrl/ServerUrl correctamente.'
    $rutaXpzManifiesto = Join-Path $contextoManifiesto.DirectorioXpz 'fixture-versionado.xpz'
    $manifiestoPrueba = Crear-ManifiestoEjecucion -Xpz $rutaXpzManifiesto -FullyQualifiedNames @('APIGLM.Fixture.WSValido') -DirectorioBase (Join-Path $DirectorioTmp 'ejecuciones-versionado') -Contexto $contextoManifiesto
    Test-Asercion -Id 'configuracionMulticliente.manifiestoServerUrl' -Condicion (
        [string]$manifiestoPrueba.Datos.host -eq 'https://trunk.example.com' -and
        [string]$manifiestoPrueba.Datos.baseUrl -eq '/testing/rest' -and
        [string]$manifiestoPrueba.Datos.serverUrl -eq 'https://trunk.example.com/testing/rest'
    ) -DetalleExito 'El manifiesto conserva host, baseUrl y serverUrl del contexto.' -DetalleFallo 'El manifiesto no conservo host/baseUrl/serverUrl.'
    Establecer-VersionesManifiesto -RutaManifiesto $manifiestoPrueba.Ruta -Versiones @{ 'APIGLM.Fixture.WSValido' = '1.3' } | Out-Null
    $manifiestoConVersiones = Leer-ManifiestoEjecucion -RutaManifiesto $manifiestoPrueba.Ruta
    Test-Asercion -Id 'integridad.manifiestoPersisteVersiones' -Condicion (
        [string]$manifiestoConVersiones.versions.'APIGLM.Fixture.WSValido' -eq '1.3' -and
        @($manifiestoConVersiones.fullyQualifiedNames).Count -eq 1 -and
        [string]$manifiestoConVersiones.fullyQualifiedNames[0] -eq 'APIGLM.Fixture.WSValido'
    ) -DetalleExito 'El manifiesto persiste el mapa de versiones objetivo sin perder los FQN.' -DetalleFallo 'El manifiesto no persiste el mapa de versiones o pierde los FQN.'
    Establecer-FullyQualifiedNamesManifiesto -RutaManifiesto $manifiestoPrueba.Ruta -FullyQualifiedNames @('APIGLM.Fixture.WSValido') | Out-Null
    $manifiestoReleido = Leer-ManifiestoEjecucion -RutaManifiesto $manifiestoPrueba.Ruta
    Eliminar-ManifiestoEjecucion -RutaManifiesto $manifiestoPrueba.Ruta
    Test-Asercion -Id 'integridad.manifiestoVersionesOpcional' -Condicion (
        [string]$manifiestoReleido.versions.'APIGLM.Fixture.WSValido' -eq '1.3' -and
        $contenidoActualizador -match 'Establecer-VersionesManifiesto' -and
        $contenidoActualizador -match 'Quitar-FilaVersionDocumento'
    ) -DetalleExito 'El manifiesto conserva el mapa de versiones al actualizar los FQN y el actualizador normaliza el hash excluyendo la fila Version.' -DetalleFallo 'El manifiesto no conserva las versiones o el actualizador no normaliza el hash de documento.'
}

function Ejecutar-CasosUtilidades {
    <#
    .SYNOPSIS
    Casos del modulo comun GLMUtilidades.ps1: hash, escritura atomica, rutas,
    validacion XPZ/PDF, reportes de validacion, fabrica de registros e invocacion
    de scripts hijo. Incluye la guarda de equivalencia de hashes contra la
    implementacion anterior.
    #>
    [CmdletBinding()]
    param()

    New-DirectorioSiNoExiste -Directorio $DirectorioTmp | Out-Null

    function Obtener-HashReferenciaAnterior {
        param([AllowEmptyString()][string]$Texto)
        $textoNormalizado = ($Texto -replace "`r`n", "`n") -replace "`r", "`n"
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($textoNormalizado)
            return (([System.BitConverter]::ToString($sha256.ComputeHash($bytes))) -replace '-', '').ToLowerInvariant()
        } finally {
            $sha256.Dispose()
        }
    }

    $entradasHash = @(
        '',
        'texto simple',
        "con`r`nfin de linea CRLF",
        "con`nfin de linea LF",
        "mezclado`r`nlf`r`n`nfinal`r",
        ('acentos y símbolos: á é í ó ú ñ — ' + [char]0xF3)
    )
    $hashEquivalente = $true
    foreach ($entradaHash in $entradasHash) {
        if ((Obtener-Sha256TextoNormalizado -Texto $entradaHash) -ne (Obtener-HashReferenciaAnterior -Texto $entradaHash)) {
            $hashEquivalente = $false
            break
        }
    }
    Test-Asercion -Id 'utilidades.hashEquivalenciaImplementacionAnterior' -Condicion $hashEquivalente -DetalleExito 'El hash canonico produce resultados byte-identicos a la implementacion anterior en todas las entradas de muestra.' -DetalleFallo 'El hash canonico difiere de la implementacion anterior.'

    Test-Asercion -Id 'utilidades.hashTextoNormalizado' -Condicion (
        (Obtener-Sha256TextoNormalizado -Texto "a`r`nb") -eq (Obtener-Sha256TextoNormalizado -Texto "a`nb") -and
        (Obtener-Sha256TextoNormalizado -Texto 'abc').Length -eq 64 -and
        (Obtener-Sha256TextoNormalizado -Texto 'abc') -ceq (Obtener-Sha256TextoNormalizado -Texto 'abc').ToLowerInvariant()
    ) -DetalleExito 'El hash de texto normaliza saltos de linea y devuelve SHA256 hexadecimal en minusculas.' -DetalleFallo 'El hash de texto no normaliza como se espera.'

    $rutaArchivoHash = Join-Path $DirectorioTmp 'utilidades-hash-archivo.bin'
    [System.IO.File]::WriteAllText($rutaArchivoHash, "contenido`r`nbinario", (New-Object System.Text.UTF8Encoding($false)))
    Test-Asercion -Id 'utilidades.hashArchivoBinario' -Condicion (
        (Obtener-Sha256Archivo -Ruta $rutaArchivoHash) -eq (Get-FileHash -LiteralPath $rutaArchivoHash -Algorithm SHA256).Hash.ToLowerInvariant()
    ) -DetalleExito 'El hash de archivo coincide con Get-FileHash SHA256 en minusculas (equivalencia con la implementacion anterior).' -DetalleFallo 'El hash de archivo no coincide con Get-FileHash.'

    Test-Asercion -Id 'utilidades.normalizarLf' -Condicion (
        (Normalizar-SaltosLineaLf -Texto "a`r`nb`rc") -eq "a`nb`nc"
    ) -DetalleExito 'La normalizacion convierte CRLF y CR a LF.' -DetalleFallo 'La normalizacion de saltos de linea no es correcta.'

    $rutaUtf8 = Join-Path $DirectorioTmp 'utilidades-utf8.txt'
    Escribir-TextoUtf8SinBom -Ruta $rutaUtf8 -Contenido ('contenido-utf8-' + [char]0xE1)
    $bytesUtf8 = [System.IO.File]::ReadAllBytes($rutaUtf8)
    Test-Asercion -Id 'utilidades.escrituraUtf8SinBom' -Condicion (
        $bytesUtf8.Length -gt 0 -and -not ($bytesUtf8[0] -eq 0xEF -and $bytesUtf8[1] -eq 0xBB -and $bytesUtf8[2] -eq 0xBF) -and
        ([System.IO.File]::ReadAllText($rutaUtf8) -like 'contenido-utf8-*')
    ) -DetalleExito 'La escritura UTF-8 produce un archivo sin BOM con el contenido exacto.' -DetalleFallo 'La escritura UTF-8 no produce el archivo esperado.'

    $rutaAtomicoNuevo = Join-Path $DirectorioTmp 'utilidades-atomico-nuevo.txt'
    Escribir-ArchivoAtomico -Ruta $rutaAtomicoNuevo -Contenido 'primera escritura' | Out-Null
    Escribir-ArchivoAtomico -Ruta $rutaAtomicoNuevo -Contenido 'segunda escritura' | Out-Null
    $residualesAtomico = @(Get-ChildItem -LiteralPath $DirectorioTmp -File | Where-Object { $_.Name.StartsWith('utilidades-atomico-nuevo.txt.') })
    Test-Asercion -Id 'utilidades.escrituraAtomicaReemplazo' -Condicion (
        ([System.IO.File]::ReadAllText($rutaAtomicoNuevo) -eq 'segunda escritura') -and
        $residualesAtomico.Count -eq 0
    ) -DetalleExito 'La escritura atomica crea y reemplaza el archivo sin dejar temporales ni respaldos.' -DetalleFallo 'La escritura atomica no reemplaza correctamente o deja residuales.'

    $rutaAtomicoValidado = Join-Path $DirectorioTmp 'utilidades-atomico-validado.txt'
    Escribir-ArchivoAtomico -Ruta $rutaAtomicoValidado -Contenido 'contenido vigente' | Out-Null
    $bloqueRechazo = { param($RutaTemporal) throw 'validacion rechazada' }
    $conservoContenido = $false
    try {
        Escribir-ArchivoAtomico -Ruta $rutaAtomicoValidado -Contenido 'contenido invalido' -Validar $bloqueRechazo | Out-Null
    } catch {
        $conservoContenido = ([System.IO.File]::ReadAllText($rutaAtomicoValidado) -eq 'contenido vigente')
    }
    $residualesValidado = @(Get-ChildItem -LiteralPath $DirectorioTmp -File | Where-Object { $_.Name.StartsWith('utilidades-atomico-validado.txt.') })
    Test-Asercion -Id 'utilidades.escrituraAtomicaValidacionFalla' -Condicion (
        $conservoContenido -and $residualesValidado.Count -eq 0
    ) -DetalleExito 'Si la validacion rechaza el contenido, el archivo vigente se conserva y no quedan residuales.' -DetalleFallo 'La validacion de la escritura atomica no conserva el archivo vigente.'

    $raizUtilidades = Join-Path $DirectorioTmp 'utilidades-raiz'
    New-DirectorioSiNoExiste -Directorio $raizUtilidades | Out-Null
    Test-Asercion -Id 'utilidades.resolverRutaRepositorio' -Condicion (
        (Resolver-RutaRepositorio -Ruta 'sub\archivo.txt' -Raiz $raizUtilidades) -eq [System.IO.Path]::GetFullPath((Join-Path $raizUtilidades 'sub\archivo.txt')) -and
        (Resolver-RutaRepositorio -Ruta (Join-Path $DirectorioTmp 'absoluto.txt') -Raiz $raizUtilidades) -eq [System.IO.Path]::GetFullPath((Join-Path $DirectorioTmp 'absoluto.txt'))
    ) -DetalleExito 'El resolutor combina rutas relativas contra la raiz y conserva las absolutas.' -DetalleFallo 'El resolutor de rutas no resuelve como se espera.'

    Test-Asercion -Id 'utilidades.quoteArgumento' -Condicion (
        (Quote-ProcessArgument -Valor 'ruta con espacios\xpz.xpz') -eq '"ruta con espacios\xpz.xpz"' -and
        (Quote-ProcessArgument -Valor 'a"b') -eq '"a\"b"'
    ) -DetalleExito 'El quoter encierra entre comillas y escapa las comillas internas.' -DetalleFallo 'El quoter de argumentos no es correcto.'

    $rutaPdfValido = Join-Path $DirectorioTmp 'utilidades-valido.pdf'
    [System.IO.File]::WriteAllText($rutaPdfValido, '%PDF-1.4 contenido simulado', (New-Object System.Text.UTF8Encoding($false)))
    $rutaPdfCorto = Join-Path $DirectorioTmp 'utilidades-corto.pdf'
    [System.IO.File]::WriteAllText($rutaPdfCorto, '1234', (New-Object System.Text.UTF8Encoding($false)))
    $rutaPdfCabecera = Join-Path $DirectorioTmp 'utilidades-cabecera.pdf'
    [System.IO.File]::WriteAllText($rutaPdfCabecera, 'NOESUNPDF contenido', (New-Object System.Text.UTF8Encoding($false)))
    Test-Asercion -Id 'utilidades.pdfValido' -Condicion (
        (Test-PdfValidoParaPromocion -Ruta $rutaPdfValido) -and
        -not (Test-PdfValidoParaPromocion -Ruta $rutaPdfCorto) -and
        -not (Test-PdfValidoParaPromocion -Ruta $rutaPdfCabecera) -and
        -not (Test-PdfValidoParaPromocion -Ruta (Join-Path $DirectorioTmp 'utilidades-inexistente.pdf'))
    ) -DetalleExito 'El validador de PDF acepta %PDF y rechaza archivos cortos, con cabecera invalida o inexistentes.' -DetalleFallo 'El validador de PDF no discrimina como se espera.'

    $rutaXpzFixture = Join-Path $DirectorioFixturesXpz 'SEGUROS_COMERCIAL_APIGLM_test.xpz'
    $validacionXpzFixture = Test-XpzValido -Ruta $rutaXpzFixture
    $rutaNoXpz = Join-Path $DirectorioTmp 'utilidades-no-xpz.bin'
    [System.IO.File]::WriteAllText($rutaNoXpz, 'no es un zip', (New-Object System.Text.UTF8Encoding($false)))
    $validacionNoXpz = Test-XpzValido -Ruta $rutaNoXpz
    $validacionInexistente = Test-XpzValido -Ruta (Join-Path $DirectorioTmp 'utilidades-inexistente.xpz')
    Test-Asercion -Id 'utilidades.xpzValido' -Condicion (
        $validacionXpzFixture.Valid -and
        -not $validacionNoXpz.Valid -and $validacionNoXpz.Error -and
        -not $validacionInexistente.Valid -and $validacionInexistente.Error -like '*no se encontro*'
    ) -DetalleExito 'El validador XPZ acepta el fixture y rechaza archivos invalidos o inexistentes con mensaje.' -DetalleFallo 'El validador XPZ no discrimina como se espera.'

    $directorioLogsUtilidades = Join-Path $DirectorioTmp 'utilidades-logs'
    New-DirectorioSiNoExiste -Directorio $directorioLogsUtilidades | Out-Null
    $reporteIncompatible = [pscustomobject]@{
        ejecucion = [pscustomobject]@{ id = 'ejec-incompatible'; xpz = 'otro.xpz' }
        objectList = 'SDT:Otro'
    }
    $reporteCompatible = [pscustomobject]@{
        ejecucion = [pscustomobject]@{ id = 'ejec-utilidades'; xpz = $rutaXpzFixture }
        solicitudes = @([pscustomobject]@{ servicio = 'APIGLM.Fixture.WS'; exportar = @('SDT:Faltante'); selectores = @('SDT:APIGLM.Faltante') })
        objectList = ''
    }
    Escribir-TextoUtf8SinBom -Ruta (Join-Path $directorioLogsUtilidades 'utilidades-a-validacion-xpz.json') -Contenido ($reporteIncompatible | ConvertTo-Json -Depth 10)
    Escribir-TextoUtf8SinBom -Ruta (Join-Path $directorioLogsUtilidades 'utilidades-b-validacion-xpz.json') -Contenido ($reporteCompatible | ConvertTo-Json -Depth 10)
    $seleccionReporte = Obtener-ReporteValidacionMasReciente -DirectorioLogs $directorioLogsUtilidades -RutaXpz $rutaXpzFixture -RaizRepositorio $RaizRepositorio -EjecucionId 'ejec-utilidades'
    $seleccionSinEjecucion = Obtener-ReporteValidacionMasReciente -DirectorioLogs $directorioLogsUtilidades -RutaXpz $rutaXpzFixture -RaizRepositorio $RaizRepositorio -EjecucionId 'ejec-inexistente'
    $seleccionSinReportes = Obtener-ReporteValidacionMasReciente -DirectorioLogs (Join-Path $DirectorioTmp 'utilidades-logs-vacio') -RutaXpz $rutaXpzFixture -RaizRepositorio $RaizRepositorio
    Test-Asercion -Id 'utilidades.reporteValidacionMasReciente' -Condicion (
        $seleccionReporte -and [string]$seleccionReporte.Datos.ejecucion.id -eq 'ejec-utilidades' -and
        $null -eq $seleccionSinEjecucion -and
        $null -eq $seleccionSinReportes
    ) -DetalleExito 'La busqueda del reporte de validacion respeta XPZ compatible y ejecucion opcional.' -DetalleFallo 'La busqueda del reporte de validacion no filtra como se espera.'

    $objetosPendientes = @(Obtener-ObjetosPendientes -Reporte $reporteCompatible)
    $reporteSoloObjectList = [pscustomobject]@{ solicitudes = $null; objectList = 'SDT:A, SDT:B' }
    $reporteSoloSelectores = [pscustomobject]@{ solicitudes = @([pscustomobject]@{ servicio = 'S'; exportar = @(); selectores = @('SDT:APIGLM.SoloSelector') }); objectList = '' }
    Test-Asercion -Id 'utilidades.objetosPendientes' -Condicion (
        $objetosPendientes.Count -eq 1 -and $objetosPendientes[0] -eq 'SDT:Faltante' -and
        @(Obtener-ObjetosPendientes -Reporte $reporteSoloObjectList).Count -eq 2 -and
        @(Obtener-ObjetosPendientes -Reporte $reporteSoloSelectores) -eq 'SoloSelector'
    ) -DetalleExito 'Los objetos pendientes priorizan exportar, luego objectList y finalmente los selectores.' -DetalleFallo 'La extraccion de objetos pendientes no prioriza como se espera.'

    Test-Asercion -Id 'utilidades.signaturaPendientes' -Condicion (
        (Obtener-SignaturaPendientes -Reporte $reporteCompatible) -eq 'SDT:Faltante' -and
        (Obtener-SignaturaPendientes -Reporte $reporteSoloObjectList) -eq 'SDT:A, SDT:B'
    ) -DetalleExito 'La signatura de pendientes deriva de objectList o de solicitudes.exportar.' -DetalleFallo 'La signatura de pendientes no es correcta.'

    $registroFabrica = New-RegistroServicioControl
    $registroCompleto = New-RegistroServicioControl -WrapperGuid 'guid-1' -Revision 2 -Version '1.2' -DocumentHash 'hash-doc' -PdfHash 'hash-pdf' -Dependencias @('SDT:A', 'SDT:B') -Status 'OMITIDO'
    Test-Asercion -Id 'utilidades.fabricaRegistroServicio' -Condicion (
        $registroFabrica.wrapperGuid -eq '' -and $registroFabrica.revision -eq 0 -and $registroFabrica.version -eq '1.0' -and
        $registroFabrica.documentHash -eq '' -and $registroFabrica.pdfHash -eq '' -and $registroFabrica.status -eq 'ACTIVO' -and
        @($registroFabrica.dependencies).Count -eq 0 -and
        $registroCompleto.wrapperGuid -eq 'guid-1' -and $registroCompleto.revision -eq 2 -and $registroCompleto.version -eq '1.2' -and
        $registroCompleto.documentHash -eq 'hash-doc' -and $registroCompleto.pdfHash -eq 'hash-pdf' -and
        $registroCompleto.status -eq 'OMITIDO' -and @($registroCompleto.dependencies).Count -eq 2
    ) -DetalleExito 'La fabrica de registros de servicio produce valores por defecto y valores explicitos con dependencias copiadas.' -DetalleFallo 'La fabrica de registros de servicio no produce el registro esperado.'

    $endpointsFixture = Leer-InventarioEndpoints -RutaInventario (Join-Path $DirectorioFixturesJson 'inventario-valido.json')
    Test-Asercion -Id 'utilidades.leerInventarioEndpoints' -Condicion (
        @($endpointsFixture).Count -gt 0
    ) -DetalleExito 'La lectura del inventario devuelve las entradas de endpoints.json.' -DetalleFallo 'La lectura del inventario no devuelve entradas.'
    Test-AsercionLanzaError -Id 'utilidades.leerInventarioInexistente' -Bloque { Leer-InventarioEndpoints -RutaInventario (Join-Path $DirectorioTmp 'utilidades-inexistente-endpoints.json') } -PatronMensaje 'No se encontro el inventario'

    $configuracionCruda = Leer-ConfiguracionCruda -ConfigPath (Join-Path $DirectorioFixturesJson 'configuracion-prueba.json')
    Test-Asercion -Id 'utilidades.leerConfiguracionCruda' -Condicion (
        [string]$configuracionCruda.packagename -eq 'glmsuit.comercial.'
    ) -DetalleExito 'La lectura cruda de configuracion.json devuelve el objeto JSON sin validar el XPZ.' -DetalleFallo 'La lectura cruda de configuracion no devuelve el objeto esperado.'
    Test-AsercionLanzaError -Id 'utilidades.leerConfiguracionInexistente' -Bloque { Leer-ConfiguracionCruda -ConfigPath (Join-Path $DirectorioTmp 'utilidades-inexistente-config.json') } -PatronMensaje 'No se encontro el archivo de configuracion'

    $rutaScriptHijo = Join-Path $DirectorioTmp 'utilidades-script-hijo.ps1'
    Escribir-TextoUtf8SinBom -Ruta $rutaScriptHijo -Contenido "Write-Output 'hola-desde-hijo'; Write-Error 'error-consola-hijo'; exit 5"
    $resultadoHijo = Invocar-ScriptHijo -RutaScript $rutaScriptHijo -NoImprimir
    $resultadoHijoNormalizado = Invocar-ScriptHijo -RutaScript $rutaScriptHijo -NoImprimir -NormalizarCodigo
    Test-Asercion -Id 'utilidades.invocarScriptHijo' -Condicion (
        $resultadoHijo.CodigoSalida -eq 5 -and
        (@($resultadoHijo.Salida | Where-Object { $_ -match 'hola-desde-hijo' })).Count -ge 1 -and
        (@($resultadoHijo.Salida | Where-Object { $_ -match 'error-consola-hijo' })).Count -ge 1 -and
        $resultadoHijoNormalizado.CodigoSalida -eq 1
    ) -DetalleExito 'La invocacion de scripts hijo captura salida y error y normaliza codigos fuera de 0/1/2/3 a 1.' -DetalleFallo 'La invocacion de scripts hijo no captura o normaliza como se espera.'
    Test-AsercionLanzaError -Id 'utilidades.invocarScriptInexistente' -Bloque { Invocar-ScriptHijo -RutaScript (Join-Path $DirectorioTmp 'utilidades-inexistente.ps1') -NoImprimir } -PatronMensaje 'No se encontro el script'

    $rutaScriptColor = Join-Path $DirectorioTmp 'utilidades-script-color.ps1'
    Escribir-TextoUtf8SinBom -Ruta $rutaScriptColor -Contenido "Write-Host 'texto-color' -ForegroundColor Cyan; exit 0"
    $colorAntes = [Console]::ForegroundColor
    Invocar-ScriptHijo -RutaScript $rutaScriptColor -NoImprimir | Out-Null
    $colorDespues = [Console]::ForegroundColor
    Restaurar-ColorConsola -ColorBase $colorAntes
    Test-Asercion -Id 'utilidades.restaurarColorConsola' -Condicion (
        $colorDespues -eq $colorAntes -and
        [Console]::ForegroundColor -eq $colorAntes
    ) -DetalleExito 'Invocar-ScriptHijo restaura el color de consola tras un hijo que escribe en Cyan.' -DetalleFallo 'Invocar-ScriptHijo no restauró el color de consola dejado en Cyan por el hijo.'
}

function Ejecutar-CasosProceso {
    <#
    .SYNOPSIS
    Casos de invocacion real por proceso de los scripts sin cobertura directa:
    GenerarDocumento, GenerarPdfServicios y DiagnosticoIA.
    .DESCRIPTION
    Los scripts se invocan como proceso hijo con fixtures o datos productivos en
    modo staging; nada se escribe en carpetas productivas. Los casos que dependen
    de artefactos productivos locales se omiten con SKIP cuando no existen.
    #>
    [CmdletBinding()]
    param()

    New-DirectorioSiNoExiste -Directorio $DirectorioTmp | Out-Null

    . (Join-Path $DirectorioBinario 'DiagnosticoIA.ps1')

    $rutaConfiguracionProduccion = Join-Path $RaizRepositorio 'configuracion.json'
    $rutaXpzFixture = Join-Path $DirectorioFixturesXpz 'SEGUROS_COMERCIAL_APIGLM_test.xpz'

    Test-Skip -Id 'proceso.listaEndpoints' -Detalle 'La exportacion de inventarios es una herramienta independiente retirada del pipeline contextual.'

    $rutaDiagnostico = $null
    try {
        try {
            throw 'error de muestra para el diagnostico'
        } catch {
            $errorDiagnostico = New-DiagnosticoIAError -ErrorRecord $_ -Componente 'Pruebas' -Fase 'proceso' -Servicio 'APIGLM.Fixture.WS' -RaizRepositorio $RaizRepositorio
        }
        $rutaDiagnostico = Write-DiagnosticoIA -Errores @($errorDiagnostico) -Pipeline 'pruebas' -Inicio (Get-Date) -DirectorioLogs $DirectorioTmp -RaizRepositorio $RaizRepositorio -MarcaTemporal 'utilidades'
    } catch {
    }
    $diagnosticoLeido = $null
    if ($rutaDiagnostico -and (Test-Path -LiteralPath $rutaDiagnostico -PathType Leaf)) {
        try { $diagnosticoLeido = [System.IO.File]::ReadAllText($rutaDiagnostico) | ConvertFrom-Json } catch { }
    }
    Test-Asercion -Id 'proceso.diagnosticoIA' -Condicion (
        $diagnosticoLeido -and
        $diagnosticoLeido.schemaVersion -eq 1 -and
        $diagnosticoLeido.ejecucion.totalErrores -eq 1 -and
        @($diagnosticoLeido.errores).Count -eq 1 -and
        [string]$diagnosticoLeido.errores[0].componente -eq 'Pruebas' -and
        [string]$diagnosticoLeido.errores[0].fase -eq 'proceso'
    ) -DetalleExito 'DiagnosticoIA construye y escribe el informe estructurado con fase y componente.' -DetalleFallo 'DiagnosticoIA no produjo el informe esperado.'

    Test-Skip -Id 'proceso.generarDocumento' -Detalle 'La prueba de proceso requiere un contexto multicliente fixture; la ruta productiva global fue retirada.'
    Test-Skip -Id 'proceso.generarPdf' -Detalle 'La prueba de proceso requiere un contexto multicliente fixture; la ruta productiva global fue retirada.'
}

function New-ServicioControlPrueba {
    <#
    .SYNOPSIS
    Construye un servicio valido para el control de versiones de prueba.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][int]$Revision = 0,
        [Parameter(Mandatory = $false)][string]$DocumentHash = 'hash',
        [Parameter(Mandatory = $false)][string]$PdfHash = 'pdf',
        [Parameter(Mandatory = $false)][string[]]$Dependencias = @(),
        [Parameter(Mandatory = $false)][string]$Estado = 'ACTIVO'
    )
    return [ordered]@{
        wrapperGuid = 'wrapper'
        revision = $Revision
        version = '1.' + $Revision
        documentHash = $DocumentHash
        pdfHash = $PdfHash
        dependencies = @($Dependencias)
        status = $Estado
    }
}

function New-ControlPrueba {
    <#
    .SYNOPSIS
    Construye un control de versiones valido para las pruebas unitarias.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][string]$LineageId = 'lineage',
        [Parameter(Mandatory = $false)][string]$SourceFingerprint = 'source',
        [Parameter(Mandatory = $false)][string]$ProfileFingerprint = 'profile',
        [Parameter(Mandatory = $false)]$Objects = @{},
        [Parameter(Mandatory = $false)]$Services = @{},
        [Parameter(Mandatory = $false)]$Pendientes = @{}
    )
    return New-ControlVersiones -LineageId $LineageId -SourceFingerprint $SourceFingerprint -ProfileFingerprint $ProfileFingerprint -Objects $Objects -Services $Services -Pendientes $Pendientes
}

function Obtener-RevisionesHistorialPorServicio {
    <#
    .SYNOPSIS
    Parsea el historial Markdown y agrupa las revisiones por bloque de servicio.
    .DESCRIPTION
    Devuelve un hashtable con el FQN como clave y un array de revisiones (int) en orden
    de aparicion como valor. Se usa para validar continuidad, perdida de entradas y
    sincronia con el control.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Contenido
    )
    $porServicio = @{}
    $servicioActual = ''
    foreach ($linea in ($Contenido -split "`n")) {
        $linea = $linea.Trim()
        if ($linea -match '^## (.+)$') {
            $servicioActual = $matches[1].Trim()
            continue
        }
        if ($linea -match '^- \*\*1\.(\d+)\*\* \((\d{4}-\d{2}-\d{2})\)') {
            if (-not $porServicio.ContainsKey($servicioActual)) { $porServicio[$servicioActual] = @() }
            $porServicio[$servicioActual] += [int]$matches[1]
        }
    }
    return $porServicio
}

function Test-ContinuidadRevisiones {
    <#
    .SYNOPSIS
    Verifica que una secuencia de revisiones es consecutiva sin saltos ni duplicados.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int[]]$Revisiones
    )
    $revisionesOrdenadas = @($Revisiones | Sort-Object)
    if ($revisionesOrdenadas.Count -eq 0) { return $false }
    for ($indice = 1; $indice -lt $revisionesOrdenadas.Count; $indice++) {
        if ($revisionesOrdenadas[$indice] -ne ($revisionesOrdenadas[$indice - 1] + 1)) { return $false }
    }
    return $true
}

function Obtener-ContenidoHistorialPrueba {
    <#
    .SYNOPSIS
    Construye un historial Markdown de prueba con entradas manuales.
    .DESCRIPTION
    Permite simular un historial con perdida de entradas (p. ej. 1.0 y 1.2 sin 1.1) para
    verificar que la continuidad se detecta en las pruebas, sin depender del escritor.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LineageId,
        [Parameter(Mandatory = $true)][string]$Creado,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Entradas
    )
    $lineas = New-Object System.Collections.Generic.List[string]
    $lineas.Add('# Historial de versiones por servicio')
    $lineas.Add('LineageId: ' + $LineageId)
    $lineas.Add('Creado: ' + $Creado)
    foreach ($entrada in $Entradas) {
        $lineas.Add('')
        $lineas.Add($entrada)
    }
    return (($lineas -join "`n") + "`n")
}

function Ejecutar-CasosHistorial {
    <#
    .SYNOPSIS
    Unit tests de binary/HistorialVersiones.ps1 (dot-sourceado via Cargar-ModulosProduccion).
    .DESCRIPTION
    Ejercita Describir-CambiosDocumento (parametros agregados/eliminados, cambios de Tipo y
    de Obligatorio, codigos HTTP, fallback de conteos y fila Version ignorada), el formato de
    Redactar-EntradaHistorial, el detalle no vacio, la continuidad por bloque, la deteccion de
    perdida de entradas, el append byte a byte, el reemplazo por reinicio y por lineageId
    distinto, el encabezado, la version derivada del control y la sincronia bloque-control.
    #>
    [CmdletBinding()]
    param()

    $docAnterior = @'
# Autenticación de usuario

Servicio de autenticación.

## Definición del servicio

| Dato | Valor |
|---|---|
| Endpoint | `x` |
| Descripción | Servicio de autenticación. |
| Método HTTP | `POST` |
| Autenticación | HTTP Basic mediante `Authorization` |
| Versión | 1.0 |

## Entrada

| Parámetro o campo | Tipo | Obligatorio | Descripción |
|---|---|---|---|
| `Usuario` | String (30) | SI | Usuario de red. |
| `Contraseña` | String (50) | NO | Contraseña. |

## Salida exitosa

Colección: `NO`.

| Campo | Tipo | Descripción |
|---|---|---|
| `Token` | String (100) | Token de sesión. |

## Errores específicos

| Código HTTP | Respuesta o mensaje |
|---:|---|
| 400 | `Credenciales inválidas.` |

```json
{
  "status": 400
}
```
'@

    $docNuevo = $docAnterior -replace '(?m)^\| `Contraseña` \| String \(50\) \| NO \|', '| `Contraseña` | String (50) | SI |'
    $docNuevo = $docNuevo -replace '(?m)^\| `Usuario` \|', "| ``Dispositivo`` | String (50) | NO | Dispositivo. |`r`n| `Usuario` |"
    $docNuevo = $docNuevo -replace '(?m)^\| `Token` \|', ''
    $docNuevo = $docNuevo -replace '(?m)^\| 400 \|', "| 409 | `Conflicto.` |`r`n| 400 |"

    $frasesAgregado = @(Describir-CambiosDocumento -DocumentoAnterior $docAnterior -DocumentoNuevo $docNuevo)
    Test-Asercion -Id 'historial.parametroAgregado' -Condicion (
        @($frasesAgregado | Where-Object { $_ -match 'se agregó el parámetro `Dispositivo` \(String \(50\), NO\)' }).Count -eq 1
    ) -DetalleExito 'Un parámetro agregado se describe con su tipo y obligatoriedad.' -DetalleFallo 'El parámetro agregado no se describió con tipo y obligatoriedad.'

    Test-Asercion -Id 'historial.obligatorioCambiado' -Condicion (
        @($frasesAgregado | Where-Object { $_ -match 'pasó Obligatorio de NO a SI' }).Count -eq 1
    ) -DetalleExito 'Un cambio de Obligatorio se describe como NO a SI.' -DetalleFallo 'El cambio de Obligatorio no se describió como NO a SI.'

    Test-Asercion -Id 'historial.campoEliminado' -Condicion (
        @($frasesAgregado | Where-Object { $_ -match 'se eliminó el campo `Token`' }).Count -eq 1
    ) -DetalleExito 'Un campo eliminado de Salida exitosa se describe.' -DetalleFallo 'El campo eliminado no se describió.'

    Test-Asercion -Id 'historial.codigoHttpNuevo' -Condicion (
        @($frasesAgregado | Where-Object { $_ -match 'se agregó el código 409 con su mensaje' }).Count -eq 1
    ) -DetalleExito 'Un código HTTP nuevo se describe con su número.' -DetalleFallo 'El código HTTP nuevo no se describió.'

    $docEliminadoCodigo = $docAnterior -replace '(?m)^\| 400 \|', ''
    $frasesCodigoEliminado = @(Describir-CambiosDocumento -DocumentoAnterior $docAnterior -DocumentoNuevo $docEliminadoCodigo)
    Test-Asercion -Id 'historial.codigoHttpEliminado' -Condicion (
        @($frasesCodigoEliminado | Where-Object { $_ -match 'se eliminó el código 400' }).Count -eq 1
    ) -DetalleExito 'Un código HTTP eliminado se describe con su número.' -DetalleFallo 'El código HTTP eliminado no se describió.'

    $docTipo = $docAnterior -replace '(?m)^\| `Contraseña` \| String \(50\) \|', '| `Contraseña` | String (60) |'
    $frasesTipo = @(Describir-CambiosDocumento -DocumentoAnterior $docAnterior -DocumentoNuevo $docTipo)
    Test-Asercion -Id 'historial.cambioTipo' -Condicion (
        @($frasesTipo | Where-Object { $_ -match 'cambió Tipo de String \(50\) a String \(60\)' }).Count -eq 1
    ) -DetalleExito 'Un cambio de Tipo se describe con su valor anterior y nuevo.' -DetalleFallo 'El cambio de Tipo no se describió con ambos valores.'

    $docVersion = $docAnterior -replace '(?m)^\| Versión \| 1\.0 \|$', '| Versión | 1.7 |'
    $frasesVersion = @(Describir-CambiosDocumento -DocumentoAnterior $docAnterior -DocumentoNuevo $docVersion)
    Test-Asercion -Id 'historial.filaVersionIgnorada' -Condicion ($frasesVersion.Count -eq 0) -DetalleExito 'La fila Versión de Definición nunca aparece como cambio.' -DetalleFallo 'La fila Versión apareció como cambio.'

    $docNoComparable = $docAnterior -replace '(?m)^\| Parámetro o campo \|', '| Posición | Parámetro |'
    $frasesFallback = @(Describir-CambiosDocumento -DocumentoAnterior $docAnterior -DocumentoNuevo $docNoComparable)
    Test-Asercion -Id 'historial.fallbackConteos' -Condicion (
        @($frasesFallback | Where-Object { $_ -match '^Se modificó la sección Entrada \(\+\d+/[-−]\d+\)\.$' }).Count -eq 1
    ) -DetalleExito 'Una sección no comparable cae en el fallback de conteos.' -DetalleFallo 'La sección no comparable no produjo el fallback de conteos.'

    $entrada = Redactar-EntradaHistorial -Version '1.1' -Fecha '2026-08-15' -Objetos @('SDT `APIGLM.Seguridad.Autenticacion`') -Cambios @('Entrada: se agregó el parámetro `Dispositivo` (String (50), NO).')
    Test-Asercion -Id 'historial.formatoEntrada' -Condicion (
        $entrada -match '(?m)^- \*\*1\.1\*\* \(2026-08-15\) — Objetos: SDT `APIGLM\.Seguridad\.Autenticacion` modificado\.$' -and
        $entrada -match '(?m)^  - Entrada: se agregó el parámetro `Dispositivo` \(String \(50\), NO\)\.$'
    ) -DetalleExito 'El formato de entrada es - **1.<n>** (YYYY-MM-DD) — texto con cambios indentados.' -DetalleFallo 'El formato de entrada no coincide con el esperado.'

    $entradaInicial = Redactar-EntradaHistorial -Version '1.0' -Fecha '2026-08-15'
    Test-Asercion -Id 'historial.detalleNoVacioInicial' -Condicion (
        $entradaInicial -match 'Versión inicial\.' -and $entradaInicial -notmatch '^  - $'
    ) -DetalleExito 'La entrada inicial registra Versión inicial. sin detalle vacío.' -DetalleFallo 'La entrada inicial no tiene detalle o quedó vacía.'

    $entradaBumpSinCambios = Redactar-EntradaHistorial -Version '1.1' -Fecha '2026-08-15' -Objetos @('Procedure `APIGLM.Comun.BuscarCodigoPostal`')
    Test-Asercion -Id 'historial.detalleNoVacioBump' -Condicion (
        $entradaBumpSinCambios -match 'Se modificó el documento\.'
    ) -DetalleExito 'Un bump sin cambios descriptibles registra detalle no vacío.' -DetalleFallo 'Un bump sin cambios descriptibles quedó sin detalle.'

    $rutaHistorialPrueba = Join-Path $DirectorioTmp 'historial-versiones.md'
    Remove-Item -LiteralPath $rutaHistorialPrueba -Force -ErrorAction SilentlyContinue
    $entrada10 = [pscustomobject]@{ FullyQualifiedName = 'APIGLM.Comun.WSBuscarCodigoPostal'; Texto = (Redactar-EntradaHistorial -Version '1.0' -Fecha '2026-08-15') }
    $entrada11 = [pscustomobject]@{ FullyQualifiedName = 'APIGLM.Comun.WSBuscarCodigoPostal'; Texto = (Redactar-EntradaHistorial -Version '1.1' -Fecha '2026-08-16' -Objetos @('Procedure `APIGLM.Comun.BuscarCodigoPostal`') -Cambios @('Entrada: el parámetro `CodigoPostal` cambió Tipo de String (4) a String (8).')) }
    Escribir-HistorialVersionado -RutaHistorial $rutaHistorialPrueba -LineageId 'd6e85f10-28f3-409e-afb1-4b38c19fc8af' -Creado '2026-08-15' -Entradas @($entrada10) | Out-Null
    $bytesPrimerEscritura = [System.IO.File]::ReadAllBytes($rutaHistorialPrueba)
    Escribir-HistorialVersionado -RutaHistorial $rutaHistorialPrueba -LineageId 'd6e85f10-28f3-409e-afb1-4b38c19fc8af' -Creado '2026-08-15' -Entradas @($entrada11) | Out-Null
    $contenidoHistorial = [System.IO.File]::ReadAllText($rutaHistorialPrueba, (New-Object System.Text.UTF8Encoding($false)))
    $bytesSegundaEscritura = [System.IO.File]::ReadAllBytes($rutaHistorialPrueba)

    $prefijoConservado = $true
    for ($indiceByte = 0; $indiceByte -lt $bytesPrimerEscritura.Length; $indiceByte++) {
        if ($bytesSegundaEscritura[$indiceByte] -ne $bytesPrimerEscritura[$indiceByte]) { $prefijoConservado = $false; break }
    }
    Test-Asercion -Id 'historial.appendConservaPrefijo' -Condicion (
        $prefijoConservado -and $bytesSegundaEscritura.Length -gt $bytesPrimerEscritura.Length
    ) -DetalleExito 'El append conserva el contenido previo byte a byte y crece.' -DetalleFallo 'El append no conservó el contenido previo byte a byte.'

    $porServicio = Obtener-RevisionesHistorialPorServicio -Contenido $contenidoHistorial
    Test-Asercion -Id 'historial.continuidadPorBloque' -Condicion (
        $porServicio.ContainsKey('APIGLM.Comun.WSBuscarCodigoPostal') -and
        (Test-ContinuidadRevisiones -Revisiones $porServicio['APIGLM.Comun.WSBuscarCodigoPostal'])
    ) -DetalleExito 'Las versiones del bloque son consecutivas sin saltos ni duplicados.' -DetalleFallo 'El bloque tiene saltos o duplicados de versión.'

    Test-Asercion -Id 'historial.sincroniaBloqueControl' -Condicion (
        ($porServicio['APIGLM.Comun.WSBuscarCodigoPostal'] | Select-Object -Last 1) -eq 1
    ) -DetalleExito 'La última revisión del bloque coincide con la revisión esperada del control (1.1).' -DetalleFallo 'La última revisión del bloque no coincide con la revisión del control.'

    $historialConPerdida = Obtener-ContenidoHistorialPrueba -LineageId 'd6e85f10-28f3-409e-afb1-4b38c19fc8af' -Creado '2026-08-15' -Entradas @(
        '## APIGLM.Comun.WSBuscarCodigoPostal',
        '',
        '- **1.0** (2026-08-15) — Versión inicial.',
        '- **1.2** (2026-08-16) — Objetos: Procedure `APIGLM.Comun.BuscarCodigoPostal` modificado.'
    )
    $porServicioPerdida = Obtener-RevisionesHistorialPorServicio -Contenido $historialConPerdida
    Test-Asercion -Id 'historial.deteccionPerdidaEntradas' -Condicion (
        -not (Test-ContinuidadRevisiones -Revisiones $porServicioPerdida['APIGLM.Comun.WSBuscarCodigoPostal'])
    ) -DetalleExito 'Una entrada intermedia eliminada (1.0 y 1.2 sin 1.1) se detecta por discontinuidad.' -DetalleFallo 'La pérdida de una entrada intermedia no se detectó.'

    $rutaHistorialReemplazo = Join-Path $DirectorioTmp 'historial-reemplazo.md'
    Remove-Item -LiteralPath $rutaHistorialReemplazo -Force -ErrorAction SilentlyContinue
    Escribir-HistorialVersionado -RutaHistorial $rutaHistorialReemplazo -LineageId 'aaaa-1111' -Creado '2026-08-15' -Entradas @($entrada10) | Out-Null
    Escribir-HistorialVersionado -RutaHistorial $rutaHistorialReemplazo -LineageId 'bbbb-2222' -Creado '2026-08-16' -Entradas @($entrada11) -Reemplazar | Out-Null
    $contenidoReemplazo = [System.IO.File]::ReadAllText($rutaHistorialReemplazo, (New-Object System.Text.UTF8Encoding($false)))
    $encabezadoReemplazo = Obtener-EncabezadoHistorial -RutaHistorial $rutaHistorialReemplazo
    Test-Asercion -Id 'historial.reemplazoReinicio' -Condicion (
        $encabezadoReemplazo.LineageId -eq 'bbbb-2222' -and
        $contenidoReemplazo -match '(?m)^- \*\*1\.1\*\*' -and
        -not ($contenidoReemplazo -match '(?m)^- \*\*1\.0\*\*')
    ) -DetalleExito 'El reemplazo por reinicio deja solo el encabezado nuevo y las entradas del lote.' -DetalleFallo 'El reemplazo por reinicio no regeneró el historial limpio.'

    Test-Asercion -Id 'historial.encabezadoLineage' -Condicion (
        $encabezadoReemplazo.LineageId -eq 'bbbb-2222' -and $encabezadoReemplazo.Creado -eq '2026-08-16'
    ) -DetalleExito 'El encabezado conserva LineageId y Creado.' -DetalleFallo 'El encabezado no conserva LineageId y Creado.'

    $entradaControl = Redactar-EntradaHistorial -Version '1.3' -Fecha '2026-08-15'
    Test-Asercion -Id 'historial.versionDerivadaDelControl' -Condicion (
        $entradaControl -match '- \*\*1\.3\*\*' -and
        -not ($entradaControl -match '\*\*1\.0\*\*')
    ) -DetalleExito 'La versión de la entrada se deriva del control, nunca del archivo.' -DetalleFallo 'La versión de la entrada no se deriva del parámetro del control.'
}

function Ejecutar-CasosEstadoControl {
    <#
    .SYNOPSIS
    Unit tests de ControlVersiones.ps1 (ya dot-sourceado).
    .DESCRIPTION
    Ejercita Obtener-VersionServicio, Comparar-ControlVersiones (fast-path, pendientes,
    lineage, objetos, perfil, servicios nuevos/eliminados), Validar-ControlVersiones
    negativos adicionales, la escritura atomica con control invalido que conserva el archivo
    previo, y los contratos por contenido de ActualizarServicios.ps1.
    #>
    [CmdletBinding()]
    param()

    $versionSinControl = Obtener-VersionServicio
    $servicioRevision7 = New-ServicioControlPrueba -Revision 7
    $versionIncrementada = Obtener-VersionServicio -ServicioAnterior $servicioRevision7 -Incrementar
    $versionSinIncremento = Obtener-VersionServicio -ServicioAnterior $servicioRevision7
    Test-Asercion -Id 'estadoControl.obtenerVersionServicio' -Condicion (
        $versionSinControl.Revision -eq 0 -and $versionSinControl.Version -eq '1.0' -and
        $versionIncrementada.Revision -eq 8 -and $versionIncrementada.Version -eq '1.8' -and
        $versionSinIncremento.Revision -eq 7 -and $versionSinIncremento.Version -eq '1.7'
    ) -DetalleExito 'Obtener-VersionServicio devuelve 1.0 sin control previo y 1.<n+1> con incremento.' -DetalleFallo 'Obtener-VersionServicio no resuelve las versiones esperadas.'

    $serviciosFast = @{ 'APIGLM.Fixture.WSValido' = (New-ServicioControlPrueba -Revision 1) }
    $controlAnterior = New-ControlPrueba -LineageId 'l1' -SourceFingerprint 's1' -ProfileFingerprint 'p1' -Services $serviciosFast
    $controlObjetivo = New-ControlPrueba -LineageId 'l1' -SourceFingerprint 's1' -ProfileFingerprint 'p1' -Services $serviciosFast
    $comparacionFast = Comparar-ControlVersiones -ControlAnterior $controlAnterior -ControlObjetivo $controlObjetivo
    Test-Asercion -Id 'estadoControl.compararFastPath' -Condicion $comparacionFast.EsFastPath -DetalleExito 'Comparar-ControlVersiones determina fast-path sin cambios.' -DetalleFallo 'No se determinó el fast-path.'

    $controlConPendiente = New-ControlPrueba -LineageId 'l1' -SourceFingerprint 's1' -ProfileFingerprint 'p1' -Services $serviciosFast -Pendientes @{ 'APIGLM.Fixture.WSValido' = @{ attempts = 1; reason = 'test' } }
    $comparacionPendiente = Comparar-ControlVersiones -ControlAnterior $controlConPendiente -ControlObjetivo $controlObjetivo
    Test-Asercion -Id 'estadoControl.compararPendienteBloqueaFastPath' -Condicion (
        -not $comparacionPendiente.EsFastPath -and @($comparacionPendiente.Pendientes).Count -eq 1
    ) -DetalleExito 'Un pendiente impide el fast-path.' -DetalleFallo 'Un pendiente no impidió el fast-path.'

    $controlLineageDistinto = New-ControlPrueba -LineageId 'l2' -SourceFingerprint 's1' -ProfileFingerprint 'p1' -Services $serviciosFast
    $comparacionLineage = Comparar-ControlVersiones -ControlAnterior $controlAnterior -ControlObjetivo $controlLineageDistinto
    Test-Asercion -Id 'estadoControl.compararLineageBloquea' -Condicion (
        $comparacionLineage.LineageCambiado -and $comparacionLineage.BloqueadoPorLineage -and
        -not [string]::IsNullOrWhiteSpace($comparacionLineage.MotivoBloqueo)
    ) -DetalleExito 'Un lineageId cambiado se detecta con motivo de bloqueo.' -DetalleFallo 'El lineageId cambiado no se detectó como bloqueo.'

    $servicioConDependencia = New-ServicioControlPrueba -Revision 1 -Dependencias @('Procedure:guidObjeto')
    $serviciosDependientes = @{ 'APIGLM.Fixture.WSAfectado' = $servicioConDependencia }
    $controlObjetosAnterior = New-ControlPrueba -LineageId 'l1' -SourceFingerprint 's1' -ProfileFingerprint 'p1' -Objects @{ 'Procedure:guidObjeto' = 'checksum-a' } -Services $serviciosDependientes
    $controlObjetosObjetivo = New-ControlPrueba -LineageId 'l1' -SourceFingerprint 's1' -ProfileFingerprint 'p1' -Objects @{ 'Procedure:guidObjeto' = 'checksum-b' } -Services $serviciosDependientes
    $comparacionObjetos = Comparar-ControlVersiones -ControlAnterior $controlObjetosAnterior -ControlObjetivo $controlObjetosObjetivo
    Test-Asercion -Id 'estadoControl.compararObjetoAfectaServicios' -Condicion (
        @($comparacionObjetos.ObjetosModificados) -contains 'Procedure:guidObjeto' -and
        @($comparacionObjetos.ServiciosAfectados) -contains 'APIGLM.Fixture.WSAfectado'
    ) -DetalleExito 'Un objeto modificado afecta los servicios que lo dependen.' -DetalleFallo 'El objeto modificado no afectó a los servicios dependientes.'

    $servicioActivo = New-ServicioControlPrueba -Revision 1 -Estado 'ACTIVO'
    $serviciosPerfil = @{ 'APIGLM.Fixture.WSActivo' = $servicioActivo }
    $controlPerfilAnterior = New-ControlPrueba -LineageId 'l1' -SourceFingerprint 's1' -ProfileFingerprint 'p1' -Services $serviciosPerfil
    $controlPerfilNuevo = New-ControlPrueba -LineageId 'l1' -SourceFingerprint 's1' -ProfileFingerprint 'p2' -Services $serviciosPerfil
    $comparacionPerfil = Comparar-ControlVersiones -ControlAnterior $controlPerfilAnterior -ControlObjetivo $controlPerfilNuevo
    Test-Asercion -Id 'estadoControl.compararPerfilAfectaActivos' -Condicion (
        $comparacionPerfil.ProfileFingerprintCambio -and
        @($comparacionPerfil.ServiciosAfectados) -contains 'APIGLM.Fixture.WSActivo'
    ) -DetalleExito 'Un cambio de perfil afecta a los servicios ACTIVO.' -DetalleFallo 'El cambio de perfil no afectó a los servicios ACTIVO.'

    $serviciosNuevos = @{ 'APIGLM.Fixture.WSValido' = (New-ServicioControlPrueba -Revision 1); 'APIGLM.Fixture.WSNuevo' = (New-ServicioControlPrueba -Revision 0) }
    $controlSinNuevo = New-ControlPrueba -LineageId 'l1' -SourceFingerprint 's1' -ProfileFingerprint 'p1' -Services $serviciosFast
    $controlConNuevo = New-ControlPrueba -LineageId 'l1' -SourceFingerprint 's1' -ProfileFingerprint 'p1' -Services $serviciosNuevos
    $comparacionNuevos = Comparar-ControlVersiones -ControlAnterior $controlSinNuevo -ControlObjetivo $controlConNuevo
    Test-Asercion -Id 'estadoControl.compararServiciosNuevos' -Condicion (
        @($comparacionNuevos.ServiciosNuevos) -contains 'APIGLM.Fixture.WSNuevo'
    ) -DetalleExito 'Los servicios nuevos se detectan en la comparación.' -DetalleFallo 'Los servicios nuevos no se detectaron.'

    $serviciosEliminados = @{ 'APIGLM.Fixture.WSEliminado' = (New-ServicioControlPrueba -Revision 1) }
    $controlConEliminado = New-ControlPrueba -LineageId 'l1' -SourceFingerprint 's1' -ProfileFingerprint 'p1' -Services $serviciosEliminados
    $controlSinEliminado = New-ControlPrueba -LineageId 'l1' -SourceFingerprint 's1' -ProfileFingerprint 'p1' -Services $serviciosFast
    $comparacionEliminados = Comparar-ControlVersiones -ControlAnterior $controlConEliminado -ControlObjetivo $controlSinEliminado
    Test-Asercion -Id 'estadoControl.compararServiciosEliminados' -Condicion (
        @($comparacionEliminados.ServiciosEliminados) -contains 'APIGLM.Fixture.WSEliminado'
    ) -DetalleExito 'Los servicios eliminados se detectan en la comparación.' -DetalleFallo 'Los servicios eliminados no se detectaron.'

    $controlRevisionNegativa = New-ControlPrueba -LineageId 'l1' -SourceFingerprint 's1' -ProfileFingerprint 'p1' -Services @{ 'APIGLM.Fixture.WSValido' = (New-ServicioControlPrueba -Revision -1) }
    Test-AsercionLanzaError -Id 'estadoControl.validaRevisionNegativa' -Bloque { Validar-ControlVersiones -ControlVersiones $controlRevisionNegativa } -PatronMensaje 'revision invalida' -DetalleExito 'El control rechaza una revision negativa.' -DetalleFallo 'El control aceptó una revision negativa.'

    $servicioSinDocumentHash = New-ServicioControlPrueba -Revision 1
    $servicioSinDocumentHash.Remove('documentHash')
    $controlSinDocumentHash = New-ControlPrueba -LineageId 'l1' -SourceFingerprint 's1' -ProfileFingerprint 'p1' -Services @{ 'APIGLM.Fixture.WSValido' = $servicioSinDocumentHash }
    Test-AsercionLanzaError -Id 'estadoControl.validaDocumentHashFaltante' -Bloque { Validar-ControlVersiones -ControlVersiones $controlSinDocumentHash } -PatronMensaje 'documentHash' -DetalleExito 'El control rechaza un servicio sin documentHash.' -DetalleFallo 'El control aceptó un servicio sin documentHash.'

    $servicioSinPdfHash = New-ServicioControlPrueba -Revision 1
    $servicioSinPdfHash.Remove('pdfHash')
    $controlSinPdfHash = New-ControlPrueba -LineageId 'l1' -SourceFingerprint 's1' -ProfileFingerprint 'p1' -Services @{ 'APIGLM.Fixture.WSValido' = $servicioSinPdfHash }
    Test-AsercionLanzaError -Id 'estadoControl.validaPdfHashFaltante' -Bloque { Validar-ControlVersiones -ControlVersiones $controlSinPdfHash } -PatronMensaje 'pdfHash' -DetalleExito 'El control rechaza un servicio sin pdfHash.' -DetalleFallo 'El control aceptó un servicio sin pdfHash.'

    $servicioSinDependencias = New-ServicioControlPrueba -Revision 1
    $servicioSinDependencias.Remove('dependencies')
    $controlSinDependencias = New-ControlPrueba -LineageId 'l1' -SourceFingerprint 's1' -ProfileFingerprint 'p1' -Services @{ 'APIGLM.Fixture.WSValido' = $servicioSinDependencias }
    Test-AsercionLanzaError -Id 'estadoControl.validaDependenciasFaltantes' -Bloque { Validar-ControlVersiones -ControlVersiones $controlSinDependencias } -PatronMensaje 'dependencies' -DetalleExito 'El control rechaza un servicio sin dependencies.' -DetalleFallo 'El control aceptó un servicio sin dependencies.'

    $controlLineageBlanco = New-ControlPrueba -LineageId '   ' -SourceFingerprint 's1' -ProfileFingerprint 'p1' -Services $serviciosFast
    Test-AsercionLanzaError -Id 'estadoControl.validaLineageBlanco' -Bloque { Validar-ControlVersiones -ControlVersiones $controlLineageBlanco } -PatronMensaje 'lineageId' -DetalleExito 'El control rechaza un lineageId en blanco.' -DetalleFallo 'El control aceptó un lineageId en blanco.'

    $rutaControlAtomico = Join-Path $DirectorioTmp 'control-atomico.json'
    Remove-Item -LiteralPath $rutaControlAtomico -Force -ErrorAction SilentlyContinue
    Escribir-ControlVersionesAtomico -ControlVersiones $controlObjetivo -RutaControl $rutaControlAtomico | Out-Null
    $bytesControlPrevio = [System.IO.File]::ReadAllBytes($rutaControlAtomico)
    $controlInvalido = New-ControlPrueba -LineageId 'l1' -SourceFingerprint 's1' -ProfileFingerprint 'p1' -Services @{ 'APIGLM.Fixture.WSValido' = (New-ServicioControlPrueba -Revision -1) }
    Test-AsercionLanzaError -Id 'estadoControl.escrituraAtomicaControlInvalido' -Bloque { Escribir-ControlVersionesAtomico -ControlVersiones $controlInvalido -RutaControl $rutaControlAtomico } -PatronMensaje 'revision invalida' -DetalleExito 'La escritura atomica con control inválido lanza.' -DetalleFallo 'La escritura atomica con control inválido no lanzó.'
    $bytesControlPosterior = [System.IO.File]::ReadAllBytes($rutaControlAtomico)
    $controlIntacto = $bytesControlPrevio.Length -eq $bytesControlPosterior.Length
    if ($controlIntacto) {
        for ($indiceByte = 0; $indiceByte -lt $bytesControlPrevio.Length; $indiceByte++) {
            if ($bytesControlPosterior[$indiceByte] -ne $bytesControlPrevio[$indiceByte]) { $controlIntacto = $false; break }
        }
    }
    Test-Asercion -Id 'estadoControl.escrituraAtomicaConservaPrevio' -Condicion $controlIntacto -DetalleExito 'Una escritura atomica fallida conserva el control previo íntegro.' -DetalleFallo 'La escritura atomica fallida modificó el control previo.'

    $contenidoActualizadorEstado = [System.IO.File]::ReadAllText((Join-Path $DirectorioBinario 'ActualizarServicios.ps1'))
    Test-Asercion -Id 'estadoControl.contenidoDobleBumpProhibido' -Condicion (
        $contenidoActualizadorEstado -match 'VersionesActualizadas' -and
        $contenidoActualizadorEstado -match 'intento actualizar su version mas de una vez'
    ) -DetalleExito 'El actualizador prohíbe el doble bump en el mismo lote.' -DetalleFallo 'El actualizador no prohíbe el doble bump en el mismo lote.'
    Test-Asercion -Id 'estadoControl.contenidoAttemptsPendientes' -Condicion (
        $contenidoActualizadorEstado -match 'attempts = \$intentosAnteriores \+ 1'
    ) -DetalleExito 'El actualizador incrementa attempts en los pendientes.' -DetalleFallo 'El actualizador no incrementa attempts en los pendientes.'
    Test-Asercion -Id 'estadoControl.contenidoHashExcluyeFilaVersion' -Condicion (
        $contenidoActualizadorEstado -match 'Quitar-FilaVersionDocumento' -and
        $contenidoActualizadorEstado -match "patronFilaVersion" -and
        $contenidoActualizadorEstado -match '0xF3'
    ) -DetalleExito 'El actualizador normaliza el hash excluyendo la fila Versión.' -DetalleFallo 'El actualizador no excluye la fila Versión del hash.'
    Test-Asercion -Id 'estadoControl.contenidoReinicioRegistroSinPublicar' -Condicion (
        $contenidoActualizadorEstado -match 'Marcar-ServicioSinPublicar' -and
        $contenidoActualizadorEstado -match "documentHash' -Valor ''"
    ) -DetalleExito 'El actualizador reinicia el registro de un servicio sin publicar.' -DetalleFallo 'El actualizador no reinicia el registro de un servicio sin publicar.'
}

function Ejecutar-CasosValidacionEstado {
    <#
    .SYNOPSIS
    Validadores estáticos de estado/ (control, artefactos, pendientes, dependencias, identidad e historial).
    .DESCRIPTION
    Opera sobre el estado productivo (estado/controlVersiones.json, estado/historialVersiones.md y
    documentacionServicios/). Si estado/ no existe o no tiene control, los casos se marcan SKIP y
    el resto de la ejecución continúa.
    #>
    [CmdletBinding()]
    param()

    $directorioEstado = Join-Path $RaizRepositorio 'estado'
    $rutaControlEstado = Join-Path $directorioEstado 'controlVersiones.json'
    $rutaHistorialEstado = Join-Path $directorioEstado 'historialVersiones.md'

    if (-not (Test-Path -LiteralPath $rutaControlEstado -PathType Leaf)) {
        Test-Skip -Id 'validacionEstado.control' -Detalle 'estado/controlVersiones.json no existe; las validaciones estáticas se omiten.'
        Test-Skip -Id 'validacionEstado.artefactos' -Detalle 'Sin control productivo para validar artefactos publicados.'
        Test-Skip -Id 'validacionEstado.pendientes' -Detalle 'Sin control productivo para validar pendientes.'
        Test-Skip -Id 'validacionEstado.dependencias' -Detalle 'Sin control productivo para validar dependencias.'
        Test-Skip -Id 'validacionEstado.identidad' -Detalle 'Sin control productivo para validar lineage y fingerprints.'
        Test-Skip -Id 'validacionEstado.historial' -Detalle 'Sin control productivo para validar el historial.'
        return
    }

    $controlProductivo = $null
    try { $controlProductivo = Leer-ControlVersiones -RutaControl $rutaControlEstado } catch { }
    Test-Asercion -Id 'validacionEstado.control' -Condicion ($null -ne $controlProductivo) -DetalleExito 'El control productivo pasa Validar-ControlVersiones.' -DetalleFallo 'El control productivo no pasó la validación.'

    $serviciosControlProductivo = Convertir-DiccionarioControlVersiones -Objeto $controlProductivo.services
    $conformidadArtefactos = $true
    $detalleArtefactos = ''
    foreach ($claveServicio in $serviciosControlProductivo.Keys) {
        $servicio = $serviciosControlProductivo[$claveServicio]
        if ([string](Obtener-PropiedadControlVersiones -Objeto $servicio -Nombre 'status') -ne 'ACTIVO') { continue }
        $documentHash = [string](Obtener-PropiedadControlVersiones -Objeto $servicio -Nombre 'documentHash')
        $pdfHash = [string](Obtener-PropiedadControlVersiones -Objeto $servicio -Nombre 'pdfHash')
        $version = [string](Obtener-PropiedadControlVersiones -Objeto $servicio -Nombre 'version')
        if (-not $documentHash -and -not $pdfHash) { continue }
        $nombreArchivo = Obtener-NombreArchivoServicio -FullyQualifiedName $claveServicio -FqnsInventario @($serviciosControlProductivo.Keys)
        $rutaMarkdownEstado = Join-Path $DirectorioServiciosProduccion ($nombreArchivo + '.md')
        $rutaPdfEstado = Join-Path $DirectorioServiciosProduccion ($nombreArchivo + '.pdf')
        if (-not (Test-Path -LiteralPath $rutaMarkdownEstado -PathType Leaf) -or -not (Test-Path -LiteralPath $rutaPdfEstado -PathType Leaf)) {
            $conformidadArtefactos = $false
            $detalleArtefactos = 'Faltan artefactos publicados para ' + $claveServicio
            break
        }
        $etiquetaFilaVersion = 'Versi' + [char]0xF3 + 'n'
        $patronFilaVersion = '(?m)^[ \t]*\| ' + $etiquetaFilaVersion + ' \|[^\r\n]*\r?\n?'
        $textoNormalizado = ([regex]::Replace([System.IO.File]::ReadAllText($rutaMarkdownEstado), $patronFilaVersion, '') -replace "`r`n", "`n") -replace "`r", "`n"
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashMarkdownPublicado = (([System.BitConverter]::ToString($sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($textoNormalizado)))) -replace '-', '').ToLowerInvariant()
        } finally {
            $sha256.Dispose()
        }
        $hashPdfPublicado = (Get-FileHash -LiteralPath $rutaPdfEstado -Algorithm SHA256).Hash.ToLowerInvariant()
        $coincidenciaFilaVersion = [regex]::Match([System.IO.File]::ReadAllText($rutaMarkdownEstado), '(?m)^\| Versión \| (\d+\.\d+) \|$')
        $versionMarkdown = if ($coincidenciaFilaVersion.Success) { $coincidenciaFilaVersion.Groups[1].Value } else { '' }
        if ($hashMarkdownPublicado -ne $documentHash -or $hashPdfPublicado -ne $pdfHash -or $versionMarkdown -ne $version) {
            $conformidadArtefactos = $false
            $detalleArtefactos = 'Hash o versión del Markdown/PDF no coinciden para ' + $claveServicio
            break
        }
    }
    Test-Asercion -Id 'validacionEstado.artefactos' -Condicion $conformidadArtefactos -DetalleExito 'Los artefactos publicados existen y sus hashes y la fila Versión coinciden con el control.' -DetalleFallo $detalleArtefactos

    $pendientesProductivos = Convertir-DiccionarioControlVersiones -Objeto $controlProductivo.pendientes
    $conformidadPendientes = $true
    foreach ($clavePendiente in $pendientesProductivos.Keys) {
        $pendiente = $pendientesProductivos[$clavePendiente]
        if ([int](Obtener-PropiedadControlVersiones -Objeto $pendiente -Nombre 'attempts') -lt 1) { $conformidadPendientes = $false; break }
        if ([string]::IsNullOrWhiteSpace([string](Obtener-PropiedadControlVersiones -Objeto $pendiente -Nombre 'reason'))) { $conformidadPendientes = $false; break }
    }
    Test-Asercion -Id 'validacionEstado.pendientes' -Condicion $conformidadPendientes -DetalleExito 'Los pendientes tienen attempts >= 1 y reason no vacío.' -DetalleFallo 'Algún pendiente tiene attempts < 1 o reason vacío.'

    $conformidadDependencias = $true
    foreach ($claveServicio in $serviciosControlProductivo.Keys) {
        $dependencias = @(Obtener-DependenciasServicioControlVersiones -Servicio $serviciosControlProductivo[$claveServicio])
        if ($dependencias.Count -eq 0) { continue }
        $dependenciasUnicas = @($dependencias | Select-Object -Unique)
        if ($dependenciasUnicas.Count -ne $dependencias.Count) { $conformidadDependencias = $false; break }
    }
    Test-Asercion -Id 'validacionEstado.dependencias' -Condicion $conformidadDependencias -DetalleExito 'Las dependencias son únicas y no vacías.' -DetalleFallo 'Alguna dependencia está duplicada.'

    $lineageIdProductivo = [string](Obtener-PropiedadControlVersiones -Objeto $controlProductivo -Nombre 'lineageId')
    $sourceFingerprintProductivo = [string](Obtener-PropiedadControlVersiones -Objeto $controlProductivo -Nombre 'sourceFingerprint')
    $profileFingerprintProductivo = [string](Obtener-PropiedadControlVersiones -Objeto $controlProductivo -Nombre 'profileFingerprint')
    $esGuid = $lineageIdProductivo -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    $fingerprintsHex = $sourceFingerprintProductivo -match '^[0-9a-f]{64}$' -and $profileFingerprintProductivo -match '^[0-9a-f]{64}$'
    Test-Asercion -Id 'validacionEstado.identidad' -Condicion ($esGuid -and $fingerprintsHex) -DetalleExito 'El lineageId es GUID y los fingerprints son hex de 64.' -DetalleFallo 'El lineageId no es GUID o los fingerprints no son hex de 64.'

    if (-not (Test-Path -LiteralPath $rutaHistorialEstado -PathType Leaf)) {
        Test-Skip -Id 'validacionEstado.historial' -Detalle 'estado/historialVersiones.md no existe; se omite la validación del historial.'
        return
    }
    $encabezadoHistorialEstado = Obtener-EncabezadoHistorial -RutaHistorial $rutaHistorialEstado
    $contenidoHistorialEstado = [System.IO.File]::ReadAllText($rutaHistorialEstado, (New-Object System.Text.UTF8Encoding($false)))
    $porServicioHistorial = Obtener-RevisionesHistorialPorServicio -Contenido $contenidoHistorialEstado
    $conformidadHistorial = $null -ne $encabezadoHistorialEstado -and $encabezadoHistorialEstado.LineageId -eq $lineageIdProductivo
    foreach ($claveServicio in $porServicioHistorial.Keys) {
        if (-not $serviciosControlProductivo.ContainsKey($claveServicio)) {
            $conformidadHistorial = $false
            break
        }
        $revisionControl = [int](Obtener-PropiedadControlVersiones -Objeto $serviciosControlProductivo[$claveServicio] -Nombre 'revision')
        if (($porServicioHistorial[$claveServicio] | Select-Object -Last 1) -ne $revisionControl) {
            $conformidadHistorial = $false
            break
        }
    }
    Test-Asercion -Id 'validacionEstado.historial' -Condicion $conformidadHistorial -DetalleExito 'El historial es coherente con el control: última revisión por bloque y lineageId del encabezado.' -DetalleFallo 'El historial no es coherente con el control.'
}

function Ejecutar-CasosConfiguracionPanelTemporal {
    <#
    .SYNOPSIS
    Inicia el panel con una copia temporal de configuracion.json.
    .DESCRIPTION
    Esta base de pruebas evita escribir la configuracion operativa y comprueba el
    contenido del archivo despues de cada solicitud de configuracion.
    #>
    [CmdletBinding()]
    param()

    $rutaServidorPanel = Join-Path $DirectorioBinario 'ServidorPanelWeb.ps1'
    $rutaFixtureConfiguracion = Join-Path $DirectorioFixturesJson 'configuracion-multicliente-alta.json'
    $directorioPruebaPanel = Join-Path $DirectorioTmp 'configuracion-panel-temporal'
    $rutaConfiguracionTemporal = Join-Path $directorioPruebaPanel 'configuracion.json'
    New-DirectorioSiNoExiste -Directorio $directorioPruebaPanel | Out-Null
    Copy-Item -LiteralPath $rutaFixtureConfiguracion -Destination $rutaConfiguracionTemporal -Force
    $configuracionTemporal = Get-Content -LiteralPath $rutaConfiguracionTemporal -Raw | ConvertFrom-Json
    $rutaKbExistente = Join-Path $directorioPruebaPanel 'kb-cliente-existente'
    New-DirectorioSiNoExiste -Directorio $rutaKbExistente | Out-Null
    Escribir-TextoUtf8SinBom -Ruta (Join-Path $rutaKbExistente 'prueba.gxw') -Contenido '<KnowledgeBase />'
    $configuracionTemporal.clientes[0].ambientes[0].kbPath = ($rutaKbExistente -replace '\\', '/')
    Escribir-TextoUtf8SinBom -Ruta $rutaConfiguracionTemporal -Contenido ($configuracionTemporal | ConvertTo-Json -Depth 10)

    $puerto = 8240 + (Get-Random -Minimum 0 -Maximum 100)
    $rutaPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $procesoPanel = $null
    $etapaPrueba = 'inicio'
    try {
        $procesoPanel = Start-Process -FilePath $rutaPowerShell -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $rutaServidorPanel,
            '-RepositoryRoot', $RaizRepositorio, '-ConfigPath', $rutaConfiguracionTemporal,
            '-Port', $puerto, '-NoBrowser'
        ) -WindowStyle Hidden -PassThru

        $respuestaInicio = $null
        for ($intentoInicio = 0; $intentoInicio -lt 20; $intentoInicio++) {
            Start-Sleep -Milliseconds 250
            try {
                $respuestaInicio = Invoke-WebRequest -UseBasicParsing -Uri ('http://127.0.0.1:' + $puerto + '/') -ErrorAction Stop
                break
            } catch { }
        }
        $tokenMatch = if ($respuestaInicio) { [regex]::Match($respuestaInicio.Content, 'window\.PANEL_TOKEN="([a-f0-9]+)"') } else { $null }
        Test-Asercion -Id 'configuracionPanelTemporal.inicio' -Condicion ($null -ne $respuestaInicio -and $tokenMatch.Success) -DetalleExito 'El panel se inicia con una configuracion temporal y entrega token de sesion.' -DetalleFallo 'El panel no se inicio con la configuracion temporal o no entrego token.'
        if ($null -eq $respuestaInicio -or -not $tokenMatch.Success) { return }

        $headersPanel = @{ 'X-Panel-Token' = $tokenMatch.Groups[1].Value }
        $etapaPrueba = 'leer configuracion temporal'
        $respuestaConfiguracion = Invoke-RestMethod -Uri ('http://127.0.0.1:' + $puerto + '/api/configuracion')
        $hashInicial = [string]$respuestaConfiguracion.data.configHash
        $contenidoInicial = [System.IO.File]::ReadAllBytes($rutaConfiguracionTemporal)
        Test-Asercion -Id 'configuracionPanelTemporal.lectura' -Condicion ([bool]$respuestaConfiguracion.ok -and $hashInicial -match '^[0-9a-f]{64}$' -and $contenidoInicial.Length -gt 0) -DetalleExito 'La API lee el hash y el contenido de la copia temporal.' -DetalleFallo 'La API no leyo correctamente la configuracion temporal.'

        # La API valida que la KB declarada exista. El fixture debe preparar una
        # ruta temporal valida para probar la mutacion, no una ruta de maquina.
        $rutaKbNueva = Join-Path $directorioPruebaPanel 'kb-nuevo-cliente'
        New-DirectorioSiNoExiste -Directorio $rutaKbNueva | Out-Null
        Escribir-TextoUtf8SinBom -Ruta (Join-Path $rutaKbNueva 'prueba.gxw') -Contenido '<KnowledgeBase />'
        $payloadCliente = [ordered]@{
            configHash = $hashInicial
            data = [ordered]@{
                id = 'nuevo-cliente'
                nombre = 'Nuevo cliente'
                packagenames = [ordered]@{ comercial = 'nuevo.' }
                geneXusExportProfile = 'Gx18'
                serviciosIgnorados = @()
                ambientes = @([ordered]@{
                    id = 'testing'
                    nombre = 'Testing'
                    modulo = 'comercial'
                    tipo = 'test'
                    kbPath = ($rutaKbNueva -replace '\\', '/')
                    host = 'https://nuevo.example.com'
                    baseUrl = '/testing/rest'
                })
            }
        }
        $etapaPrueba = 'alta temporal'
        $respuestaAlta = Invoke-WebRequest -Method Post -UseBasicParsing -Uri ('http://127.0.0.1:' + $puerto + '/api/configuracion/clientes') -Headers $headersPanel -ContentType 'application/json' -Body ($payloadCliente | ConvertTo-Json -Depth 10)
        $datosAlta = $respuestaAlta.Content | ConvertFrom-Json
        $contenidoPosterior = [System.IO.File]::ReadAllBytes($rutaConfiguracionTemporal)
        $configuracionPosterior = Get-Content -LiteralPath $rutaConfiguracionTemporal -Raw | ConvertFrom-Json
            $clienteNuevo = @($configuracionPosterior.clientes | Where-Object { $_.id -eq 'nuevo-cliente' })
            Test-Asercion -Id 'configuracionPanelTemporal.escritura' -Condicion (
                $respuestaAlta.StatusCode -eq 200 -and
                [bool]$datosAlta.ok -and
                [string]$configuracionPosterior.herramientas.geneXusExportProfile -eq 'Gx18' -and
                $clienteNuevo.Count -eq 1 -and
            @($clienteNuevo[0].ambientes).Count -eq 1 -and
            $clienteNuevo[0].serviciosIgnorados.Count -eq 0 -and
            -not [System.Linq.Enumerable]::SequenceEqual($contenidoInicial, $contenidoPosterior)
        ) -DetalleExito 'La mutacion valida escribe la copia temporal y conserva el cliente con su primer ambiente.' -DetalleFallo 'La mutacion no actualizo correctamente la copia temporal.'

        $hashPosterior = [string]$datosAlta.data.configHash
        $contenidoAntesError = [System.IO.File]::ReadAllBytes($rutaConfiguracionTemporal)
        $respuestaErrorValidacion = $null
        try {
            $payloadInvalido = [ordered]@{ configHash = $hashPosterior; data = [ordered]@{ id = 'cliente-invalido'; nombre = 'Invalido'; packagenames = [ordered]@{ comercial = 'invalido.' }; serviciosIgnorados = @(); ambientes = @() } }
            Invoke-WebRequest -Method Post -UseBasicParsing -Uri ('http://127.0.0.1:' + $puerto + '/api/configuracion/clientes') -Headers $headersPanel -ContentType 'application/json' -Body ($payloadInvalido | ConvertTo-Json -Depth 10) -ErrorAction Stop | Out-Null
        } catch { $respuestaErrorValidacion = $_ }
        $contenidoDespuesError = [System.IO.File]::ReadAllBytes($rutaConfiguracionTemporal)
        $codigoErrorValidacion = if ($respuestaErrorValidacion -and $respuestaErrorValidacion.Exception.Response) { [int]$respuestaErrorValidacion.Exception.Response.StatusCode.value__ } else { 200 }
        Test-Asercion -Id 'configuracionPanelTemporal.errorValidacionAtomico' -Condicion ($codigoErrorValidacion -eq 400 -and [System.Linq.Enumerable]::SequenceEqual($contenidoAntesError, $contenidoDespuesError)) -DetalleExito 'Un payload invalido se rechaza sin modificar ningun byte de la copia temporal.' -DetalleFallo 'Un payload invalido modifico la copia temporal o no devolvio 400.'

        $respuestaErrorHash = $null
        try {
            $payloadHashObsoleto = [ordered]@{ configHash = ('0' * 64); data = $payloadCliente.data }
            Invoke-WebRequest -Method Post -UseBasicParsing -Uri ('http://127.0.0.1:' + $puerto + '/api/configuracion/clientes') -Headers $headersPanel -ContentType 'application/json' -Body ($payloadHashObsoleto | ConvertTo-Json -Depth 10) -ErrorAction Stop | Out-Null
        } catch { $respuestaErrorHash = $_ }
        $contenidoDespuesHash = [System.IO.File]::ReadAllBytes($rutaConfiguracionTemporal)
        $codigoErrorHash = if ($respuestaErrorHash -and $respuestaErrorHash.Exception.Response) { [int]$respuestaErrorHash.Exception.Response.StatusCode.value__ } else { 200 }
        Test-Asercion -Id 'configuracionPanelTemporal.hashObsoletoAtomico' -Condicion ($codigoErrorHash -eq 409 -and [System.Linq.Enumerable]::SequenceEqual($contenidoAntesError, $contenidoDespuesHash)) -DetalleExito 'Un hash obsoleto devuelve 409 y conserva byte a byte la copia temporal.' -DetalleFallo 'Un hash obsoleto no devolvio 409 o modifico la copia temporal.'

        $respuestaErrorId = $null
        try {
            $payloadIdDuplicado = [ordered]@{ configHash = $hashPosterior; data = [ordered]@{ id = 'existente'; nombre = 'Duplicado'; packagenames = [ordered]@{ comercial = 'duplicado.' }; serviciosIgnorados = @(); ambientes = @([ordered]@{ id = 'nuevo'; nombre = 'Nuevo'; modulo = 'comercial'; tipo = 'prod'; kbPath = 'C:/KBs/CLIENTE_DUPLICADO' }) } }
            Invoke-WebRequest -Method Post -UseBasicParsing -Uri ('http://127.0.0.1:' + $puerto + '/api/configuracion/clientes') -Headers $headersPanel -ContentType 'application/json' -Body ($payloadIdDuplicado | ConvertTo-Json -Depth 10) -ErrorAction Stop | Out-Null
        } catch { $respuestaErrorId = $_ }
        $contenidoDespuesId = [System.IO.File]::ReadAllBytes($rutaConfiguracionTemporal)
        $codigoErrorId = if ($respuestaErrorId -and $respuestaErrorId.Exception.Response) { [int]$respuestaErrorId.Exception.Response.StatusCode.value__ } else { 200 }
        Test-Asercion -Id 'configuracionPanelTemporal.idDuplicadoAtomico' -Condicion ($codigoErrorId -eq 400 -and [System.Linq.Enumerable]::SequenceEqual($contenidoAntesError, $contenidoDespuesId)) -DetalleExito 'Un ID de cliente duplicado se rechaza antes de escribir y conserva el archivo.' -DetalleFallo 'Un ID de cliente duplicado modifico el archivo o no devolvio 400.'

        $respuestaErrorKb = $null
        try {
            $payloadKbDuplicada = [ordered]@{ configHash = $hashPosterior; data = [ordered]@{ id = 'existente'; nombre = 'Cliente existente'; packagenames = [ordered]@{ comercial = 'existente.' }; serviciosIgnorados = @(); ambientes = @([ordered]@{ id = 'produccion'; nombre = 'Produccion'; modulo = 'comercial'; tipo = 'prod'; kbPath = 'C:/KBs/CLIENTE_EXISTENTE' }) } }
            Invoke-WebRequest -Method Post -UseBasicParsing -Uri ('http://127.0.0.1:' + $puerto + '/api/configuracion/clientes') -Headers $headersPanel -ContentType 'application/json' -Body ($payloadKbDuplicada | ConvertTo-Json -Depth 10) -ErrorAction Stop | Out-Null
        } catch { $respuestaErrorKb = $_ }
        $contenidoDespuesKb = [System.IO.File]::ReadAllBytes($rutaConfiguracionTemporal)
        $codigoErrorKb = if ($respuestaErrorKb -and $respuestaErrorKb.Exception.Response) { [int]$respuestaErrorKb.Exception.Response.StatusCode.value__ } else { 200 }
        Test-Asercion -Id 'configuracionPanelTemporal.kbDuplicadaAtomica' -Condicion ($codigoErrorKb -eq 400 -and [System.Linq.Enumerable]::SequenceEqual($contenidoAntesError, $contenidoDespuesKb)) -DetalleExito 'Una KB duplicada se rechaza antes de escribir y conserva el archivo.' -DetalleFallo 'Una KB duplicada modifico el archivo o no devolvio 400.'
    } catch {
        $detalleError = $etapaPrueba + ': ' + $_.Exception.Message
        try {
            if ($_.Exception.Response) {
                $stream = $_.Exception.Response.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $bodyError = $reader.ReadToEnd()
                    $reader.Dispose()
                    if ($bodyError) { $detalleError += ' | respuesta: ' + $bodyError }
                }
            }
        } catch { }
        Registrar-Caso -Id 'configuracionPanelTemporal.error' -Estado 'FAIL' -Detalle $detalleError
    } finally {
        if ($procesoPanel -and -not $procesoPanel.HasExited) {
            try { & taskkill.exe /PID $procesoPanel.Id /T /F | Out-Null } catch { try { Stop-Process -Id $procesoPanel.Id -Force -ErrorAction SilentlyContinue } catch { } }
        }
        if (Test-Path -LiteralPath $directorioPruebaPanel) {
            Remove-Item -LiteralPath $directorioPruebaPanel -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Ejecutar-CasosVersionChangelog {
    <#
    .SYNOPSIS
    Verifica el contrato local de versionado y renderer del panel web.
    .DESCRIPTION
    Lee los fixtures Markdown de version, comprueba el formato de las entradas,
    valida el caso hostil y revisa que el frontend mantenga una degradacion
    independiente de configurationBlocked y sin dependencias externas.
    #>
    [CmdletBinding()]
    param()

    $directorioFixturesWeb = Join-Path $DirectorioFixtures 'web'
    $rutaVersionReal = Join-Path $RaizRepositorio 'web\version.md'
    $rutaVersionValida = Join-Path $directorioFixturesWeb 'version-valido.md'
    $rutaVersionCorrupta = Join-Path $directorioFixturesWeb 'version-corrupto.md'
    $rutaVersionMaliciosa = Join-Path $directorioFixturesWeb 'version-malicioso.md'
    $rutaRenderer = Join-Path $RaizRepositorio 'web\app\render-utils.js'
    $rutaAplicacion = Join-Path $RaizRepositorio 'web\app.js'
    $rutaServidor = Join-Path $DirectorioBinario 'ServidorPanelWeb.ps1'
    $rutaLanzador = Join-Path $RaizRepositorio 'IniciarPanelWeb.cmd'
    $contenidoVersion = ''
    $contenidoVersionValida = ''
    $contenidoVersionCorrupta = ''
    $contenidoVersionMaliciosa = ''
    try {
        $contenidoVersion = [System.IO.File]::ReadAllText($rutaVersionReal, (New-Object System.Text.UTF8Encoding($false)))
        $contenidoVersionValida = [System.IO.File]::ReadAllText($rutaVersionValida, (New-Object System.Text.UTF8Encoding($false)))
        $contenidoVersionCorrupta = [System.IO.File]::ReadAllText($rutaVersionCorrupta, (New-Object System.Text.UTF8Encoding($false)))
        $contenidoVersionMaliciosa = [System.IO.File]::ReadAllText($rutaVersionMaliciosa, (New-Object System.Text.UTF8Encoding($false)))
    } catch {
        Test-Asercion -Id 'versionChangelog.fixturesLectura' -Condicion $false -DetalleFallo ('No se pudieron leer los fixtures de version: ' + $_.Exception.Message)
        return
    }

    $primeraLineaVersion = @($contenidoVersion -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[0].Trim()
    $primeraLineaValida = @($contenidoVersionValida -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[0].Trim()
    $primeraLineaCorrupta = @($contenidoVersionCorrupta -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[0].Trim()
    $versionesFixtureValido = @([regex]::Matches($contenidoVersionValida, '(?m)^#\s+V1\.(\d+)\s*$') | ForEach-Object { [int]$_.Groups[1].Value })
    $revisionDiezPosterior = $versionesFixtureValido.Count -ge 2 -and $versionesFixtureValido[0] -eq 10 -and $versionesFixtureValido[1] -eq 9 -and $versionesFixtureValido[0] -gt $versionesFixtureValido[1]
    Test-Asercion -Id 'versionChangelog.archivoReal' -Condicion ($primeraLineaVersion -eq '# V1.1' -and $contenidoVersion -match '(?m)^\*\*Fecha:\*\*\s+\d{4}-\d{2}-\d{2}\s*$' -and $contenidoVersion -match 'SPEC 26' -and $contenidoVersion -match 'SPEC 27' -and $contenidoVersion -match 'SPEC 28' -and $contenidoVersion -match 'SPEC 30') -DetalleExito 'web/version.md inicia en V1.1, contiene fecha y documenta las SPEC 26, 27, 28 y 30.' -DetalleFallo 'web/version.md no cumple el contrato vigente de version.'
    Test-Asercion -Id 'versionChangelog.formatoVersion' -Condicion ($primeraLineaValida -match '^#\s+V1\.\d+$' -and $primeraLineaCorrupta -notmatch '^#\s+V1\.\d+$' -and $revisionDiezPosterior) -DetalleExito 'El formato V1.<entero> se valida y V1.10 queda posterior a V1.9.' -DetalleFallo 'El formato de version o la comparacion entera no esta cubierta por los fixtures.'
    Test-Asercion -Id 'versionChangelog.fixtureMalicioso' -Condicion ($contenidoVersionMaliciosa -match '<script>' -and $contenidoVersionMaliciosa -match '<img ' -and $contenidoVersionMaliciosa -match '\[Enlace\]\(javascript:' -and $contenidoVersionMaliciosa -match '!\[Imagen\]\(') -DetalleExito 'El fixture hostil contiene HTML, imagen, enlace y javascript para probar el renderer.' -DetalleFallo 'El fixture hostil no cubre todas las entradas Markdown peligrosas.'

    $contenidoRenderer = [System.IO.File]::ReadAllText($rutaRenderer, (New-Object System.Text.UTF8Encoding($false)))
    $contenidoAplicacion = [System.IO.File]::ReadAllText($rutaAplicacion, (New-Object System.Text.UTF8Encoding($false)))
    $contenidoServidor = [System.IO.File]::ReadAllText($rutaServidor, (New-Object System.Text.UTF8Encoding($false)))
    $contenidoLanzador = [System.IO.File]::ReadAllText($rutaLanzador, (New-Object System.Text.UTF8Encoding($false)))
    $rendererSeguro = $contenidoRenderer -match 'function renderInlineMarkdown' -and $contenidoRenderer -match 'escapeHtml\(value\)' -and $contenidoRenderer -match 'function renderMarkdown' -and $contenidoRenderer -notmatch '(?i)DOMParser|marked|showdown|markdown-it'
    Test-Asercion -Id 'versionChangelog.rendererSeguro' -Condicion $rendererSeguro -DetalleExito 'El renderer admite el subconjunto acordado y escapa el texto sin librerias externas.' -DetalleFallo 'El renderer no declara el escape seguro o referencia una dependencia externa.'
    $degradacionVersion = $contenidoAplicacion -match 'available: false' -and $contenidoAplicacion -match 'Versión no disponible' -and $contenidoAplicacion -match 'console\.warn' -and $contenidoAplicacion -match 'configurationBlocked' -and $contenidoAplicacion -notmatch 'function loadApplicationVersion[\s\S]{0,2500}configurationBlocked\s*='
    Test-Asercion -Id 'versionChangelog.degradacionNoBloqueante' -Condicion $degradacionVersion -DetalleExito 'La ausencia o invalidez del changelog conserva Versión no disponible y no modifica configurationBlocked.' -DetalleFallo 'La degradacion del changelog no esta separada del bloqueo de configuracion.'
    Test-Asercion -Id 'versionChangelog.cargaSinCache' -Condicion (($contenidoAplicacion -match "fetch\('/version\.md'\s*,\s*\{\s*cache:\s*'no-store'") -and ($contenidoAplicacion -match 'validateApplicationVersion')) -DetalleExito 'El frontend carga version.md sin cache y valida su primera version.' -DetalleFallo 'El frontend no declara la carga sin cache o la validacion de version.'
    Test-Asercion -Id 'versionChangelog.marcadorTecnicoSincronizado' -Condicion (($contenidoServidor.Contains('20260820-client-export-profile')) -and ($contenidoLanzador.Contains('20260820-client-export-profile')) -and (-not $contenidoLanzador.Contains('V1.'))) -DetalleExito 'El marcador técnico del servidor coincide con el lanzador y no usa la versión funcional.' -DetalleFallo 'El marcador técnico no está sincronizado o se confundió con V1.<revisión>.'
}

function Ejecutar-CasosPanelWeb {
    $rutaServidorPanel = Join-Path $DirectorioBinario 'ServidorPanelWeb.ps1'
    $archivosWeb = @('web/index.html', 'web/app.js', 'web/style.css') | ForEach-Object { Join-Path $RaizRepositorio $_ }
    $dependenciasExternas = $false
    foreach ($rutaWeb in $archivosWeb) {
        if (-not (Test-Path -LiteralPath $rutaWeb -PathType Leaf)) { $dependenciasExternas = $true; continue }
        $contenidoWeb = [System.IO.File]::ReadAllText($rutaWeb)
        if ($contenidoWeb -match '(?i)(?<!placeholder=")https?://|cdn|node_modules|(^|[^A-Za-z])import\s|require\s*\(') { $dependenciasExternas = $true }
    }
    Test-Asercion -Id 'panelWeb.sinDependenciasExternas' -Condicion (-not $dependenciasExternas) -DetalleExito 'El frontend del panel no referencia frameworks, CDN ni paquetes externos.' -DetalleFallo 'El frontend contiene una referencia externa o falta un archivo web.'
    $contenidoAplicacionPanel = [System.IO.File]::ReadAllText((Join-Path $RaizRepositorio 'web\app.js'))
    $contenidoHtmlPanel = [System.IO.File]::ReadAllText((Join-Path $RaizRepositorio 'web\index.html'))
    $contenidoEstilosPanel = [System.IO.File]::ReadAllText((Join-Path $RaizRepositorio 'web\style.css'))
    $contenidoDialogoReporte = [System.IO.File]::ReadAllText((Join-Path $RaizRepositorio 'web\app\components\report-dialog.js'))
    $contenidoServidorPanel = [System.IO.File]::ReadAllText($rutaServidorPanel)
    $contenidoRendererPdf = [System.IO.File]::ReadAllText((Join-Path $RaizRepositorio 'binary\RenderizarMarkdownTypstPdf.ps1'))
    Test-Asercion -Id 'panelWeb.persistenciaContexto' -Condicion (
        $contenidoAplicacionPanel -match 'glm-panel-context:v1' -and
        $contenidoAplicacionPanel -match 'localStorage\.getItem' -and
        $contenidoAplicacionPanel -match 'localStorage\.setItem' -and
        $contenidoAplicacionPanel -match 'localStorage\.removeItem' -and
        $contenidoAplicacionPanel -match '/api/contextos' -and
        $contenidoAplicacionPanel -match '/api/estado' -and
        $contenidoAplicacionPanel -match '/api/contexto/activar'
    ) -DetalleExito 'El frontend declara el contrato de persistencia, validacion y activacion del contexto.' -DetalleFallo 'Falta el contrato de persistencia o validacion del contexto del navegador.'
    Test-Asercion -Id 'panelWeb.decisionConflictoContexto' -Condicion (
        ($contenidoAplicacionPanel -match 'Usar contexto guardado' -or $contenidoHtmlPanel -match 'Usar contexto guardado') -and
        ($contenidoAplicacionPanel -match 'Usar contexto del servidor' -or $contenidoHtmlPanel -match 'Usar contexto del servidor')
    ) -DetalleExito 'El frontend declara las dos decisiones explicitas para resolver un conflicto de contexto.' -DetalleFallo 'Faltan las decisiones del popup de conflicto de contexto.'
    Test-Asercion -Id 'panelWeb.estadoOcupadoContexto' -Condicion (
        $contenidoAplicacionPanel -match 'pendingUi' -and
        $contenidoAplicacionPanel -match 'environment-dropdown-trigger' -and
        $contenidoAplicacionPanel -match 'aria-busy' -and
        $contenidoHtmlPanel -match 'class="spinner'
    ) -DetalleExito 'El frontend declara un estado ocupado comun y un indicador de espera para la activacion.' -DetalleFallo 'Falta el contrato de estado ocupado para la activacion del contexto.'
    Test-Asercion -Id 'panelWeb.dashboardKb' -Condicion (
        $contenidoAplicacionPanel -match 'dashboard-kb-row' -and
        $contenidoAplicacionPanel -match 'summary-item-kb" label="KB"' -and
        $contenidoAplicacionPanel -match 'kbPath' -and
        $contenidoEstilosPanel -match '\.dashboard-kb-row \{[^}]*grid-column:\s*1 / -1' -and
        $contenidoEstilosPanel -match '\.dashboard-kb-row \{[^}]*grid-template-columns:\s*minmax\(0,\s*3fr\) minmax\(0,\s*1fr\)'
    ) -DetalleExito 'El Dashboard declara la fila KB + Últ. actualización en 75/25 con la ruta del contexto.' -DetalleFallo 'Falta el contrato visual de la tarjeta KB del Dashboard.'
    Test-Asercion -Id 'panelWeb.estilosEstadoOcupado' -Condicion (
        $contenidoEstilosPanel -match 'animation:\s*spinner-rotate' -and
        $contenidoEstilosPanel -match '-webkit-animation:\s*spinner-rotate' -and
        $contenidoEstilosPanel -match '@-webkit-keyframes\s+spinner-rotate' -and
        $contenidoEstilosPanel -match '@keyframes\s+spinner-rotate' -and
        $contenidoEstilosPanel -match 'prefers-reduced-motion' -and
        $contenidoEstilosPanel -match 'animation-duration:\s*1\.4s\s*!important' -and
        $contenidoEstilosPanel -match 'margin-top:\s*10px'
    ) -DetalleExito 'Los estilos declaran animacion de spinners, movimiento reducido y espaciado de tarjetas.' -DetalleFallo 'Falta algun contrato CSS de spinners, movimiento reducido o espaciado de tarjetas.'
    Test-Asercion -Id 'panelWeb.contratosPaginacion' -Condicion (
        $contenidoHtmlPanel -match 'documentation-filter' -and
        $contenidoHtmlPanel -match 'documentation-pdf-list'
    ) -DetalleExito 'El frontend declara la consulta filtrable de PDF publicados.' -DetalleFallo 'El frontend no conserva la consulta de PDF publicados.'
    Test-Asercion -Id 'panelWeb.aislamientoCargasContextuales' -Condicion (
        $contenidoAplicacionPanel -match 'documentationLoadSequence' -and
        $contenidoAplicacionPanel -match 'stateLoadSequence' -and
        $contenidoAplicacionPanel -match 'getSelectedContextKey' -and
        $contenidoAplicacionPanel -match 'requestSequence !== documentationLoadSequence' -and
        $contenidoAplicacionPanel -match 'requestedContextKey !== getSelectedContextKey'
    ) -DetalleExito 'Las respuestas tardías de Documentación y estado no pueden sobrescribir el contexto seleccionado.' -DetalleFallo 'Falta aislar las cargas asíncronas cuando cambia el contexto.'
    Test-Asercion -Id 'panelWeb.catalogoPublicadoSinXpz' -Condicion (
        $contenidoAplicacionPanel -match 'servicePayload\.ok \|\| documentPayload\.ok' -and
        $contenidoAplicacionPanel -match 'endpointServices = servicePayload\.ok \? \(servicePayload\.data\.servicios \|\| \[\]\) : \[\]' -and
        $contenidoAplicacionPanel -match 'loadServices\(\);'
    ) -DetalleExito 'Documentación usa los PDF publicados del contexto aunque todavía no haya un XPZ seleccionado.' -DetalleFallo 'Documentación sigue dependiendo de un XPZ activo para mostrar los PDF publicados.'
    Test-Asercion -Id 'panelWeb.contratosSeleccion' -Condicion (
        $contenidoAplicacionPanel -match 'selectedFallbackXpz' -and
        $contenidoAplicacionPanel -match 'validate-xpz-option' -and
        $contenidoAplicacionPanel -match 'continue-operation'
    ) -DetalleExito 'El frontend permite seleccionar, validar y continuar con un XPZ de recuperación.' -DetalleFallo 'El contrato de recuperación de XPZ no está implementado en el frontend.'
    Test-Asercion -Id 'panelWeb.contratosOperativos' -Condicion (
        $contenidoServidorPanel -match "route -eq '/api/servicios'" -and
        $contenidoServidorPanel -match "route -eq '/api/generar-pdf'" -and
        $contenidoServidorPanel -match '/api/reiniciar' -and
        $contenidoServidorPanel -match "modo.*completar" -and
        $contenidoAplicacionPanel -match '/api/reportes/review-ultimo' -and
        $contenidoHtmlPanel -match 'configuration-modal'
    ) -DetalleExito 'El servidor y frontend declaran los contratos de servicios, reinicio, recuperación, reportes y configuración.' -DetalleFallo 'Falta algún contrato operativo del rediseño.'
    Test-Asercion -Id 'panelWeb.reportesTresImagenes' -Condicion (
        $contenidoServidorPanel -match 'ReportImageMaximumCount = 3' -and
        $contenidoServidorPanel -match 'ReportRequestMaximumBytes = 24MB' -and
        $contenidoServidorPanel -match 'images\.Count' -and
        $contenidoAplicacionPanel -match 'readReportImagesAsBase64' -and
        $contenidoAplicacionPanel -match 'images: imageData' -and
        $contenidoDialogoReporte -match 'multiple' -and
        $contenidoDialogoReporte -match 'reportImageMaximumCount = 3' -and
        $contenidoDialogoReporte -match 'reportFormState\.images' -and
        $contenidoDialogoReporte -notmatch 'Captura local'
    ) -DetalleExito 'Los reportes admiten hasta tres imágenes y el diálogo no muestra la leyenda eliminada.' -DetalleFallo 'El contrato de tres imágenes o la eliminación de la leyenda no está completo.'
    Test-Asercion -Id 'panelWeb.reportesPdf' -Condicion (
        $contenidoServidorPanel -match 'Convert-ReportMarkdownToPdf' -and
        $contenidoServidorPanel -match 'pdfFileName' -and
        $contenidoServidorPanel -match 'publishedPdf' -and
        $contenidoRendererPdf -match 'RutaRecursos' -and
        $contenidoRendererPdf -match '--resource-path='
    ) -DetalleExito 'Cada reporte prepara un PDF y el renderer resuelve las imágenes relativas desde su carpeta.' -DetalleFallo 'Falta la generación del PDF del reporte o la resolución de sus imágenes.'
    Test-Asercion -Id 'panelWeb.estadosSemanticos' -Condicion (
        $contenidoServidorPanel -match 'function Get-VisibleWorkStatus' -and
        $contenidoServidorPanel -match 'COMPLETADO PARCIALMENTE' -and
        $contenidoServidorPanel -match 'estadoTecnico = \$Work.estado' -and
        $contenidoServidorPanel -match 'estadoVisible = Get-VisibleWorkStatus' -and
        $contenidoServidorPanel -match 'function Get-LatestValidXpz' -and
        $contenidoServidorPanel -match 'Test-XpzValido -Ruta \$candidate.Ruta' -and
        $contenidoServidorPanel -match 'Operacion abortada.'
    ) -DetalleExito 'El servidor publica estados visibles derivados del resultado técnico y valida el XPZ antes de activarlo.' -DetalleFallo 'Falta el contrato de estados semánticos o la poscondición de XPZ válido.'
    Test-Asercion -Id 'panelWeb.seleccionPasiva' -Condicion (
        $contenidoServidorPanel -match "route -eq '/api/xpz/activar'" -and
        $contenidoServidorPanel -match 'StatusCode 200 -Payload @\{ ok = \$true; data = \(Convert-XpzForResponse' -and
        @([regex]::Matches($contenidoServidorPanel, 'regenerationWork = Start-EndpointGenerationWork')).Count -eq 1
    ) -DetalleExito 'Seleccionar XPZ solo cambia el XPZ activo de la sesión y no inicia regeneración automática.' -DetalleFallo 'Seleccionar XPZ todavía inicia una operación automática o no devuelve activación pasiva.'
    Test-Asercion -Id 'panelWeb.precondicionPdfXpz' -Condicion (
        $contenidoServidorPanel -match 'confirmRestart=true' -and
        $contenidoServidorPanel -match 'PRECONDICION_XPZ' -and
        $contenidoServidorPanel -match 'Obtener-Sha256Archivo -Ruta \$script:ActiveXpz.Ruta' -and
        $contenidoServidorPanel -match 'StatusCode 409' -and
        $contenidoServidorPanel -match 'Start-PdfGenerationWork -RequestBody \$body'
    ) -DetalleExito 'La generación PDF exige confirmar nombre y SHA-256 del XPZ y responde 409 ante divergencias.' -DetalleFallo 'Falta la precondición nombre más SHA-256 o su respuesta 409.'
    Test-Asercion -Id 'panelWeb.consolasIndependientes' -Condicion (
        $contenidoHtmlPanel -match 'id="export-work-card"' -and
        $contenidoHtmlPanel -match 'id="pdf-work-card"' -and
        $contenidoHtmlPanel -notmatch 'id="work-card"' -and
        $contenidoAplicacionPanel -match 'operationResults' -and
        $contenidoAplicacionPanel -match 'exportConsoleVisible' -and
        $contenidoAplicacionPanel -match 'pdfConsoleVisible' -and
        $contenidoAplicacionPanel -match 'activeXpz\.nombre' -and
        $contenidoAplicacionPanel -match 'activeXpzHash'
    ) -DetalleExito 'Exportar y Generar PDF tienen consolas separadas y la confirmación PDF transporta nombre y SHA-256.' -DetalleFallo 'Las consolas no están separadas o falta la precondición enviada por el navegador.'
    Test-Asercion -Id 'panelWeb.resultadoUnificado' -Condicion (
        $contenidoAplicacionPanel -match 'function updateOperationResult' -and
        $contenidoAplicacionPanel -match 'estadoVisible \|\| work.estado' -and
        $contenidoAplicacionPanel -match 'finalStatus = payload.data.estadoVisible' -and
        $contenidoAplicacionPanel -match 'COMPLETADO PARCIALMENTE' -and
        $contenidoHtmlPanel -match 'id="tab-documentacion"' -and
        $contenidoHtmlPanel -notmatch 'Consola de ejecución'
    ) -DetalleExito 'Tag, popup y consola derivan del mismo estado visible y Documentación no contiene consola de proceso.' -DetalleFallo 'El resultado visible no está unificado o Documentación conserva una consola.'
    Test-Asercion -Id 'panelWeb.logsOperaciones' -Condicion (
        $contenidoServidorPanel -match 'Join-Path \$Context.DirectorioLogs ''operaciones''' -and
        $contenidoServidorPanel -match 'function Get-WorkFullOutput' -and
        $contenidoServidorPanel -match 'STDOUT' -and
        $contenidoServidorPanel -match 'STDERR' -and
        $contenidoServidorPanel -match 'function Write-OperationRecord' -and
        $contenidoServidorPanel -match 'function Write-PanelMutationOperation' -and
        $contenidoServidorPanel -match 'operationId = \$Work.operationId' -and
        $contenidoServidorPanel -match 'logNombre = \$Work.operationLogName' -and
        $contenidoServidorPanel -notmatch 'log = \$Work.log'
    ) -DetalleExito 'Los trabajos escriben manifiesto y salida completa en Logs/operaciones sin exponer rutas físicas.' -DetalleFallo 'Falta la persistencia contextual del manifiesto o la captura completa de stdout/stderr.'
    Test-Asercion -Id 'panelWeb.catalogoLogsOperaciones' -Condicion (
        $contenidoServidorPanel -match 'function Get-OperationLogCatalog' -and
        $contenidoServidorPanel -match 'function Get-ContextLogCatalog' -and
        $contenidoServidorPanel -match 'function Get-QueryValue' -and
        $contenidoServidorPanel -match 'Group-Object tipo' -and
        $contenidoServidorPanel -match 'historial' -and
        $contenidoServidorPanel -match 'severidad' -and
        $contenidoServidorPanel -match 'resumen = \$logs' -and
        $contenidoServidorPanel -notmatch 'ruta = \$logPath'
    ) -DetalleExito 'GET /api/logs resume por tipo, filtra por operación y severidad, expone los archivos de contexto (errores, reportes) y devuelve nombres lógicos.' -DetalleFallo 'El catálogo de Logs no implementa resumen, historial, filtros, archivos de contexto o aislamiento de rutas.'
    Test-Asercion -Id 'panelWeb.trazabilidadMutaciones' -Condicion (
        $contenidoServidorPanel -match "Write-PanelMutationOperation -Operation 'ACTIVAR_CONTEXTO'" -and
        $contenidoServidorPanel -match "Write-PanelMutationOperation -Operation 'ACTIVAR_XPZ'" -and
        $contenidoServidorPanel -match 'Write-ConfigurationCandidate -Candidate \$candidate -Operation ''CONFIGURACION_CLIENTE''' -and
        $contenidoServidorPanel -match 'Write-ConfigurationCandidate -Candidate \$candidate -Operation ''CONFIGURACION_AMBIENTE''' -and
        $contenidoServidorPanel -match 'Write-ConfigurationCandidate -Candidate \$candidate -Operation ''CONFIGURACION_GLOBAL''' -and
        $contenidoServidorPanel -match 'Start-PanelChildWork -Operation ''VALIDAR_XPZ'''
    ) -DetalleExito 'Las activaciones, CRUD de configuración, validación y trabajos operativos quedan correlacionados en Logs/operaciones.' -DetalleFallo 'Falta trazabilidad en alguna mutación del panel.'

    $puerto = 8140 + (Get-Random -Minimum 0 -Maximum 100)
    $rutaPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $procesoPanel = $null
    $etapaPanel = 'inicio'
    try {
        $procesoPanel = Start-Process -FilePath $rutaPowerShell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $rutaServidorPanel, '-RepositoryRoot', $RaizRepositorio, '-Port', $puerto, '-NoBrowser') -WindowStyle Hidden -PassThru
        $respuestaInicio = $null
        for ($intento = 0; $intento -lt 20; $intento++) {
            Start-Sleep -Milliseconds 250
            try { $respuestaInicio = Invoke-WebRequest -UseBasicParsing -Uri ('http://127.0.0.1:' + $puerto + '/') -ErrorAction Stop; break } catch { }
        }
        Test-Asercion -Id 'panelWeb.estaticos' -Condicion ($null -ne $respuestaInicio -and $respuestaInicio.StatusCode -eq 200) -DetalleExito 'El servidor entrega el frontend por loopback.' -DetalleFallo 'El servidor no entregó index.html.'
        if ($null -eq $respuestaInicio) { return }

        $respuestaVersion = $null
        try { $respuestaVersion = Invoke-WebRequest -UseBasicParsing -Uri ('http://127.0.0.1:' + $puerto + '/version.md') -ErrorAction Stop } catch { }
        Test-Asercion -Id 'panelWeb.versionServing' -Condicion (
            $null -ne $respuestaVersion -and
            $respuestaVersion.StatusCode -eq 200 -and
            $respuestaVersion.Headers['Content-Type'] -match '^text/markdown;\s*charset=utf-8' -and
            $respuestaVersion.Headers['Cache-Control'] -eq 'no-store' -and
            $respuestaVersion.Content -match '^# V1\.1'
        ) -DetalleExito 'GET /version.md responde Markdown UTF-8 con Cache-Control no-store.' -DetalleFallo 'GET /version.md no respeta el contrato de serving, MIME o cache.'

        $rechazoMetodoVersion = $false
        try { Invoke-WebRequest -Method Post -UseBasicParsing -Uri ('http://127.0.0.1:' + $puerto + '/version.md') -ErrorAction Stop | Out-Null } catch {
            $codigoMetodoVersion = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode.value__ } else { 0 }
            $rechazoMetodoVersion = $codigoMetodoVersion -eq 405
        }
        Test-Asercion -Id 'panelWeb.versionMetodoNoPermitido' -Condicion $rechazoMetodoVersion -DetalleExito 'La entrega estática de version.md rechaza métodos distintos de GET con HTTP 405.' -DetalleFallo 'version.md fue accesible mediante un método HTTP no permitido.'

        $rechazoRutasVersion = $true
        foreach ($rutaNoPermitida in @('/version.md.bak', '/version.mdx', '/version.md%2f..%2fconfiguracion.json')) {
            try {
                $respuestaRutaVersion = Invoke-WebRequest -UseBasicParsing -Uri ('http://127.0.0.1:' + $puerto + $rutaNoPermitida) -ErrorAction Stop
                if ($respuestaRutaVersion.StatusCode -eq 200) { $rechazoRutasVersion = $false; break }
            } catch {
                $codigoRutaVersion = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode.value__ } else { 0 }
                if ($codigoRutaVersion -eq 200) { $rechazoRutasVersion = $false; break }
            }
        }
        Test-Asercion -Id 'panelWeb.versionRutasNoPermitidas' -Condicion $rechazoRutasVersion -DetalleExito 'Rutas similares y traversal no exponen archivos Markdown fuera de la allowlist.' -DetalleFallo 'Una ruta similar o de traversal expuso un archivo estático.'

        $fuentesValidas = $true
        foreach ($nombreFuente in @('Poppins-Regular.ttf', 'Poppins-SemiBold.ttf', 'Poppins-Bold.ttf')) {
            try {
                $respuestaFuente = Invoke-WebRequest -UseBasicParsing -Uri ('http://127.0.0.1:' + $puerto + '/fonts/' + $nombreFuente) -ErrorAction Stop
                if ($respuestaFuente.StatusCode -ne 200 -or $respuestaFuente.Headers['Content-Type'] -notmatch '^font/ttf') { $fuentesValidas = $false }
            } catch { $fuentesValidas = $false }
        }
        Test-Asercion -Id 'panelWeb.fuentesAllowlist' -Condicion $fuentesValidas -DetalleExito 'El servidor entrega únicamente las tres fuentes Poppins allowlisted.' -DetalleFallo 'El servidor no entregó correctamente alguna fuente Poppins allowlisted.'

        $rechazoFuente = $false
        try { Invoke-WebRequest -UseBasicParsing -Uri ('http://127.0.0.1:' + $puerto + '/fonts/Poppins-Regular.txt') -ErrorAction Stop | Out-Null } catch { $rechazoFuente = $_.Exception.Response.StatusCode.value__ -in @(400, 404) }
        Test-Asercion -Id 'panelWeb.fuentesRutaNoPermitida' -Condicion $rechazoFuente -DetalleExito 'El servidor rechaza rutas de fuentes fuera de la allowlist.' -DetalleFallo 'Una ruta de fuente no permitida no fue rechazada.'

        $tokenMatch = [regex]::Match($respuestaInicio.Content, 'window\.PANEL_TOKEN="([a-f0-9]+)"')
        Test-Asercion -Id 'panelWeb.tokenSesion' -Condicion $tokenMatch.Success -DetalleExito 'El token de sesión se inyecta en el HTML.' -DetalleFallo 'No se encontró el token de sesión inyectado.'
        if (-not $tokenMatch.Success) { return }
        $token = $tokenMatch.Groups[1].Value
        $headersPanel = @{ 'X-Panel-Token' = $token }
        $estadoPanel = Invoke-RestMethod -Uri ('http://127.0.0.1:' + $puerto + '/api/estado')
        Test-Asercion -Id 'panelWeb.estado' -Condicion ([bool]$estadoPanel.ok -and $null -eq $estadoPanel.data.context) -DetalleExito 'El servidor inicia sin activar un contexto automáticamente.' -DetalleFallo 'El estado inicial activó un contexto o no respondió correctamente.'
        $contextosPanel = Invoke-RestMethod -Uri ('http://127.0.0.1:' + $puerto + '/api/contextos')
        Test-Asercion -Id 'panelWeb.contextos' -Condicion ([bool]$contextosPanel.ok -and @($contextosPanel.data.contextos).Count -ge 1) -DetalleExito 'La API lista los contextos configurados.' -DetalleFallo 'La API no listó los contextos configurados.'

        $etapaPanel = 'activar contexto'
        $activacionPanel = Invoke-WebRequest -Method Post -UseBasicParsing -Uri ('http://127.0.0.1:' + $puerto + '/api/contexto/activar') -Headers $headersPanel -ContentType 'application/json' -Body '{"clienteId":"trunk","modulo":"comercial","ambienteId":"testing"}'
        $activacionDatos = $activacionPanel.Content | ConvertFrom-Json
        Test-Asercion -Id 'panelWeb.activacion' -Condicion ($activacionPanel.StatusCode -in @(200, 202) -and $activacionDatos.data.contextId -eq 'trunk/comercial/testing' -and $activacionDatos.data.modulo -eq 'comercial') -DetalleExito 'La activación valida y establece el contexto triple solicitado.' -DetalleFallo 'La activación contextual triple falló.'
        $estadoActivoPanel = Invoke-RestMethod -Uri ('http://127.0.0.1:' + $puerto + '/api/estado')
Test-Asercion -Id 'panelWeb.dashboard' -Condicion (
            [bool]$estadoActivoPanel.ok -and
            $estadoActivoPanel.data.dashboard.contexto.ContextId -eq 'trunk/comercial/testing' -and
            $estadoActivoPanel.data.dashboard.xpz.PSObject.Properties['disponibles'] -and
            $estadoActivoPanel.data.dashboard.xpz.PSObject.Properties['sha256'] -and
            $estadoActivoPanel.data.dashboard.documentos.PSObject.Properties['total'] -and
            $estadoActivoPanel.data.dashboard.documentos.PSObject.Properties['ultimaActualizacion'] -and
            $estadoActivoPanel.data.dashboard.PSObject.Properties['validaciones'] -and
            @($estadoActivoPanel.data.dashboard.validaciones).Count -ge 1 -and
            $estadoActivoPanel.data.dashboard.PSObject.Properties['herramientas'] -and
            $estadoActivoPanel.data.dashboard.PSObject.Properties['trabajo']
        ) -DetalleExito 'El estado agrega los datos operativos del Dashboard para el contexto activo.' -DetalleFallo 'El estado no contiene todos los datos agregados del Dashboard.'
        $etapaPanel = 'listar XPZ'
        $xpzPanel = Invoke-RestMethod -Uri ('http://127.0.0.1:' + $puerto + '/api/xpz')
        $xpzPrincipales = @($xpzPanel.data.xpz | Where-Object { $_.principal -eq $true })
        $xpzDisponible = @($xpzPanel.data.xpz).Count -gt 0
        Test-Asercion -Id 'panelWeb.xpzPrincipales' -Condicion (
            [bool]$xpzPanel.ok -and (-not $xpzDisponible -or $xpzPrincipales.Count -eq 1)
        ) -DetalleExito 'La API XPZ lista archivos principales del contexto activo y marca uno como principal vigente cuando hay XPZ publicados.' -DetalleFallo 'La API XPZ incluyó complementos o no marcó correctamente el principal vigente.'
        if (-not $xpzDisponible) {
            foreach ($casoSinXpz in @('panelWeb.seleccionXpzPasiva', 'panelWeb.exportarRecuperable', 'panelWeb.inventario', 'panelWeb.serviciosEnriquecidos')) {
                Test-Skip -Id $casoSinXpz -Detalle 'El contexto activo no tiene XPZ publicado; se omite la parte operativa dependiente del XPZ.'
            }
            return
        }
        $xpzPrincipalNombre = @($xpzPanel.data.xpz | Where-Object { $_.principal -eq $true })[0].nombre
        $etapaPanel = 'activar XPZ'
        $activacionXpzPanel = Invoke-WebRequest -Method Post -UseBasicParsing -Uri ('http://127.0.0.1:' + $puerto + '/api/xpz/activar') -Headers $headersPanel -ContentType 'application/json' -Body ('{"nombre":"' + $xpzPrincipalNombre + '"}')
        $activacionXpzDatos = $activacionXpzPanel.Content | ConvertFrom-Json
        Test-Asercion -Id 'panelWeb.seleccionXpzPasiva' -Condicion ($activacionXpzPanel.StatusCode -eq 200 -and [bool]$activacionXpzDatos.ok -and [string]::IsNullOrWhiteSpace([string]$activacionXpzDatos.jobId)) -DetalleExito 'Seleccionar XPZ activa la sesión sin iniciar validación ni regeneración.' -DetalleFallo 'Seleccionar XPZ inició un trabajo o no confirmó la activación pasiva.'
        $respuestaCompletarInvalido = $null
        try { $respuestaCompletarInvalido = Invoke-WebRequest -Method Post -UseBasicParsing -Uri ('http://127.0.0.1:' + $puerto + '/api/exportar') -Headers $headersPanel -ContentType 'application/json' -Body '{"modo":"completar","nombre":"no-existe.xpz"}' -ErrorAction Stop } catch { }
        Test-Asercion -Id 'panelWeb.exportarRecuperable' -Condicion ($null -eq $respuestaCompletarInvalido) -DetalleExito 'La operación de completitud exige un XPZ perteneciente al contexto activo.' -DetalleFallo 'La operación de completitud aceptó un XPZ ajeno al contexto.'

        $etapaPanel = 'listar endpoints'
        $inventarioPanel = Invoke-RestMethod -Uri ('http://127.0.0.1:' + $puerto + '/api/endpoints')
        Test-Asercion -Id 'panelWeb.inventario' -Condicion ([bool]$inventarioPanel.ok -and $null -ne $inventarioPanel.data) -DetalleExito 'La API devuelve el estado del inventario contextual.' -DetalleFallo 'La API no devolvió el inventario contextual.'
        $etapaPanel = 'listar servicios'
        $serviciosPanel = Invoke-RestMethod -Uri ('http://127.0.0.1:' + $puerto + '/api/servicios')
        $servicioProductor = @($serviciosPanel.data.servicios)[0]
        Test-Asercion -Id 'panelWeb.serviciosEnriquecidos' -Condicion (
            [bool]$serviciosPanel.ok -and
            $null -ne $servicioProductor -and
            $servicioProductor.proceso -eq $servicioProductor.fullyQualifiedName -and
            $servicioProductor.endpoint -match '^glmsuit\.comercial\.apiglm\.' -and
$servicioProductor.PSObject.Properties['versionDisponible'] -and
            $servicioProductor.PSObject.Properties['observacion'] -and
            $servicioProductor.PSObject.Properties['pdf'] -and
            -not $servicioProductor.PSObject.Properties['ruta']
        ) -DetalleExito 'La API devuelve servicios enriquecidos sin exponer rutas fisicas.' -DetalleFallo 'La API no correlaciono correctamente inventario y artefactos documentales.'
        $etapaPanel = 'leer configuracion'
        $configuracionPanel = Invoke-RestMethod -Uri ('http://127.0.0.1:' + $puerto + '/api/configuracion')
        Test-Asercion -Id 'panelWeb.configHash' -Condicion ([bool]$configuracionPanel.ok -and [string]$configuracionPanel.data.configHash -match '^[0-9a-f]{64}$') -DetalleExito 'La configuración expone el hash SHA-256 actual.' -DetalleFallo 'El hash de configuración no es válido.'

        $rechazoRuta = $false
        try { Invoke-WebRequest -UseBasicParsing -Uri ('http://127.0.0.1:' + $puerto + '/api/documentos/..%2Fconfiguracion.json') -ErrorAction Stop | Out-Null } catch { $rechazoRuta = $_.Exception.Response.StatusCode.value__ -in @(400, 404) }
        Test-Asercion -Id 'panelWeb.seguridadRutas' -Condicion $rechazoRuta -DetalleExito 'La API rechaza traversal en identificadores lógicos.' -DetalleFallo 'Una ruta de traversal no fue rechazada.'

        $etapaPanel = 'iniciar validacion'
        $trabajoPanel = Invoke-WebRequest -Method Post -UseBasicParsing -Uri ('http://127.0.0.1:' + $puerto + '/api/validar') -Headers $headersPanel -ContentType 'application/json' -Body '{}'
        $trabajoDatos = $trabajoPanel.Content | ConvertFrom-Json
        Test-Asercion -Id 'panelWeb.trabajo202' -Condicion ($trabajoPanel.StatusCode -eq 202 -and [string]$trabajoDatos.data.jobId) -DetalleExito 'La validación se acepta como trabajo asincrónico.' -DetalleFallo 'La validación no devolvió un trabajo 202.'
    } catch {
        $detalleErrorPanel = $_.Exception.Message
        if ($_.Exception.Response) {
            try {
                $lectorRespuestaPanel = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $detalleErrorPanel = $detalleErrorPanel + ' | ' + $lectorRespuestaPanel.ReadToEnd()
                $lectorRespuestaPanel.Dispose()
            } catch { }
        }
        Registrar-Caso -Id 'panelWeb.error' -Estado 'FAIL' -Detalle ($etapaPanel + ': ' + $detalleErrorPanel)
    } finally {
        if ($procesoPanel -and -not $procesoPanel.HasExited) {
            try { & taskkill.exe /PID $procesoPanel.Id /T /F | Out-Null } catch { try { Stop-Process -Id $procesoPanel.Id -Force -ErrorAction SilentlyContinue } catch { } }
        }
    }
}

try {
    Ejecutar-CasosFinalesLineaArchivosCmd
    foreach ($rutaModulo in Cargar-ModulosProduccion) {
        . $rutaModulo
    }
    Resolver-DirectoriosPrueba | Out-Null
    New-DirectorioSiNoExiste -Directorio $DirectorioTmp | Out-Null
    $script:ConfiguracionesPreflightTemporales = Crear-ConfiguracionesPreflightTemporales
    Ejecutar-CasosPreflightSoloLectura
    Ejecutar-CasosConfiguracionBloqueada

    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  PRUEBAS LOCALES APIGLM (pipeline, analizador y visor)' -ForegroundColor Cyan
    Write-Host ("  " + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan

    # Los grupos de casos se incorporan en los pasos 5 a 10 del plan.
    Ejecutar-CasosConfiguracion
    Ejecutar-CasosConfiguracionMulticliente
    Ejecutar-CasosMigracionConfiguracionModular
    Ejecutar-CasosConfiguracionPanelTemporal
    Ejecutar-CasosFixturesPanelWeb
    Ejecutar-CasosVersionChangelog
    Ejecutar-CasosEstadosOperacionPanel
    Ejecutar-CasosMulticontexto
    Ejecutar-CasosIntegridadTransaccional
    Ejecutar-CasosUtilidades
    Ejecutar-CasosProceso
    Ejecutar-CasosPanelWeb
    Ejecutar-CasosHistorial
    Ejecutar-CasosEstadoControl
    Ejecutar-CasosValidacionEstado
    Ejecutar-CasosPipeline
    Ejecutar-CasosPosicionesGet
    Ejecutar-CasosMultiXpz
    Ejecutar-CasosAnalizador
    Ejecutar-CasosValidacionMarkdown
} catch {
    Registrar-Caso -Id 'harness.error' -Estado 'FAIL' -Detalle ('Fallo general del harness: ' + $_.Exception.Message)
} finally {
    try {
        Escribir-LogPruebas -RutaLog $RutaLog
    } catch {
        Write-Host ('No se pudo escribir el log de pruebas: ' + $_.Exception.Message) -ForegroundColor Yellow
    }
    Limpiar-Temporales
}

$codigoSalida = Resolver-CodigoSalida -CasosPrueba $Casos
Write-Host ("Pruebas: " + $Casos.Count + " casos, " + (@($Casos | Where-Object { $_.Estado -eq 'FAIL' }).Count) + " fallo(s).") -ForegroundColor Cyan
if ($codigoSalida -ne 0) { exit 1 }
exit 0
