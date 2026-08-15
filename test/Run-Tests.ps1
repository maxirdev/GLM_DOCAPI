# test/Run-Tests.ps1
# Harness manual de pruebas del pipeline APIGLM, del analizador XPZ y del visor.
# Compatible con PowerShell 5.1 y sin dependencias externas (ni Pester ni Node.js).
# Escribe test/Logs/yyyyMMdd-HHmmss-test.txt y devuelve 0 si todo pasa o 1 si
# algun caso falla. Nunca escribe en carpetas productivas: los temporales de las
# pruebas viven exclusivamente en test/tmp/ y se eliminan siempre en el finally.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$DirectorioScript = $PSScriptRoot
$RaizRepositorio = [System.IO.Path]::GetFullPath((Join-Path $DirectorioScript '..'))
$DirectorioBinario = Join-Path $RaizRepositorio 'binary'
$DirectorioFixtures = Join-Path $DirectorioScript 'fixtures'
$DirectorioFixturesXml = Join-Path $DirectorioFixtures 'xml'
$DirectorioFixturesJson = Join-Path $DirectorioFixtures 'json'
$DirectorioFixturesXpz = Join-Path $DirectorioFixtures 'xpz'
$DirectorioTmp = Join-Path $DirectorioScript 'tmp'
$DirectorioLogs = Join-Path $DirectorioScript 'Logs'
$DirectorioServiciosProduccion = Join-Path $RaizRepositorio 'documentacion\servicios'
$RutaInventarioProduccion = Join-Path $RaizRepositorio 'documentacion\Endpoints\assets\endpoints.json'

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
        (Join-Path $DirectorioBinario 'CargarConfiguracion.ps1')
        (Join-Path $DirectorioBinario 'AnalizarServicio.ps1')
        (Join-Path $DirectorioBinario 'CargarMultiXPZ.ps1')
        (Join-Path $DirectorioBinario 'RedactarDocumento.ps1')
        (Join-Path $DirectorioBinario 'EscribirSalidas.ps1')
    )
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
    try { $configReal = Cargar-Configuracion } catch { }
    Test-Asercion -Id 'configuracion.cargaReal' -Condicion (
        $null -ne $configReal -and
        (Test-Path -LiteralPath $configReal.XpzPath) -and
        $configReal.PackageName -eq 'glmsuit.comercial.' -and
        $configReal.Cliente -eq 'Trunk' -and
        @($configReal.ServiciosIgnorados).Count -eq 4
    ) -DetalleExito 'La configuracion real carga el XPZ configurado, packagename, cliente y serviciosIgnorados.' -DetalleFallo 'La configuracion real no carga los campos esperados.'

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
    Verifica que el nombre de archivo <wrapper>.md corresponde al ultimo segmento
    del FQN del inventario en minusculas.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$NombreArchivo,
        [Parameter(Mandatory = $false)][object[]]$Endpoints = @()
    )
    if ($Endpoints.Count -eq 0) { return $true }
    $nombreBase = [System.IO.Path]::GetFileNameWithoutExtension($NombreArchivo)
    foreach ($endpoint in $Endpoints) {
        $ultimoPunto = $endpoint.proceso.LastIndexOf('.')
        $ultimoSegmento = ''
        if ($ultimoPunto -gt 0) { $ultimoSegmento = $endpoint.proceso.Substring($ultimoPunto + 1) }
        else { $ultimoSegmento = $endpoint.proceso }
        if ($ultimoSegmento.ToLowerInvariant() -eq $nombreBase.ToLowerInvariant()) { return $true }
    }
    return $false
}

function Ejecutar-CasosValidacionMarkdown {
    <#
    .SYNOPSIS
    Validaciones estaticas de los Markdown de documentacion/servicios/.
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
        Test-Skip -Id 'validacionMarkdown.archivos' -Detalle 'documentacion/servicios/ no tiene documentos; las validaciones estaticas se omiten.'
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
        if (Test-Path -LiteralPath $RutaInventarioProduccion) {
            $inventario = Get-Content -LiteralPath $RutaInventarioProduccion -Raw | ConvertFrom-Json
            $endpoints = @($inventario.endpoints)
        }
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
        Test-Asercion -Id 'validacionMarkdown.archivos' -Condicion ($archivos.Count -gt 0) -DetalleExito ("Se validaron " + $archivos.Count + " documentos de documentacion/servicios/.") -DetalleFallo 'No se encontraron documentos para validar.'
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
        Test-Asercion -Id 'validacionMarkdown.nombreArchivo' -Condicion $todosNombreArchivo -DetalleExito 'Los nombres de archivo corresponden al ultimo segmento del FQN del inventario.' -DetalleFallo 'Algun nombre de archivo no corresponde al inventario.'
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

function Validar-VisorEscapeAppJs {
    <#
    .SYNOPSIS
    Verifica que app.js usa textContent y JSON.parse y no inserta datos via innerHTML.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Contenido
    )
    return ($Contenido -match 'textContent') -and
        ($Contenido -match 'JSON\.parse') -and
        (-not ($Contenido -match 'innerHTML\s*=\s*[^;]*endpoint'))
}

function Validar-VisorJsonSinScriptCierre {
    <#
    .SYNOPSIS
    Verifica que el bloque application/json del HTML no contiene </script sin escapar.
    .DESCRIPTION
    El generador escapa la secuencia </script como <\/script dentro del bloque de
    datos JSON; un cierre sin escapar romperia el parseo del HTML.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Contenido
    )
    $coincidencia = [regex]::Match($Contenido, '(?s)<script type="application/json"[^>]*>(.*?)</script>\s*<script src="app\.js">')
    if (-not $coincidencia.Success) {
        return ($Contenido -notmatch '(?<!\\)</script')
    }
    $bloque = $coincidencia.Groups[1].Value
    return ($bloque -notmatch '(?<!\\)</script')
}

function Validar-VisorReferenciasCssJs {
    <#
    .SYNOPSIS
    Verifica que el HTML referencia style.css y app.js.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Contenido
    )
    return ($Contenido -match 'rel="stylesheet" href="style\.css"') -and
        ($Contenido -match '<script src="app\.js"></script>')
}

function Validar-VisorAtributosAccesibles {
    <#
    .SYNOPSIS
    Verifica atributos accesibles: aria-label, scope=col, filtro y hidden.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Contenido
    )
    return ($Contenido -match 'aria-label=') -and
        ($Contenido -match 'scope="col"') -and
        ($Contenido -match 'id="filtro"') -and
        ($Contenido -match 'hidden')
}

function Validar-VisorMobilViewport {
    <#
    .SYNOPSIS
    Verifica el meta viewport de adaptacion movil en el HTML.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Contenido
    )
    return ($Contenido -match 'name="viewport" content="width=device-width, initial-scale=1\.0"')
}

function Validar-VisorMobilCss {
    <#
    .SYNOPSIS
    Verifica la adaptacion movil y el foco del filtro en style.css.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Contenido
    )
    return ($Contenido -match '@media') -and
        ($Contenido -match 'max-width') -and
        ($Contenido -match '#filtro:focus')
}

function Ejecutar-CasosVisor {
    <#
    .SYNOPSIS
    Validaciones estaticas del visor en documentacion/Endpoints/web/.
    .DESCRIPTION
    Valida app.js y style.css (escape, filtro, foco y movil) e inventario en
    documentacion/Endpoints/assets/. APIServicios.html es generado e ignorado: si no
    existe, los casos que dependen del HTML se marcan SKIP y, en su lugar, se genera
    una muestra en test/tmp/ con el generador real para verificar los validadores.
    #>
    [CmdletBinding()]
    param()

    $directorioWeb = Join-Path $RaizRepositorio 'documentacion\Endpoints\web'
    $rutaAppJs = Join-Path $directorioWeb 'app.js'
    $rutaStyleCss = Join-Path $directorioWeb 'style.css'
    $rutaHtmlProductivo = Join-Path $directorioWeb 'APIServicios.html'

    $appJs = ''
    $styleCss = ''
    if (Test-Path -LiteralPath $rutaAppJs) { $appJs = [System.IO.File]::ReadAllText($rutaAppJs, (New-Object System.Text.UTF8Encoding($false))) }
    if (Test-Path -LiteralPath $rutaStyleCss) { $styleCss = [System.IO.File]::ReadAllText($rutaStyleCss, (New-Object System.Text.UTF8Encoding($false))) }

    Test-Asercion -Id 'visor.archivosBase' -Condicion ($appJs.Length -gt 0 -and $styleCss.Length -gt 0) -DetalleExito 'app.js y style.css existen y no estan vacios.' -DetalleFallo 'app.js o style.css faltan o estan vacios.'

    Test-Asercion -Id 'visor.escapeHtmlAppJs' -Condicion (Validar-VisorEscapeAppJs -Contenido $appJs) -DetalleExito 'app.js escapa los datos con textContent y JSON.parse sin innerHTML.' -DetalleFallo 'app.js no escapa correctamente los datos del visor.'

    Test-Asercion -Id 'visor.mobilCss' -Condicion (Validar-VisorMobilCss -Contenido $styleCss) -DetalleExito 'style.css define media queries, max-width y el foco del filtro.' -DetalleFallo 'style.css no define la adaptacion movil ni el foco del filtro.'

    if (Test-Path -LiteralPath $RutaInventarioProduccion) {
        $inventarioVisor = $null
        try { $inventarioVisor = Get-Content -LiteralPath $RutaInventarioProduccion -Raw | ConvertFrom-Json } catch { }
        Test-Asercion -Id 'visor.inventarioJson' -Condicion (
            $null -ne $inventarioVisor -and $null -ne $inventarioVisor.meta -and @($inventarioVisor.endpoints).Count -gt 0
        ) -DetalleExito 'El inventario del visor se parsea con meta y endpoints.' -DetalleFallo 'El inventario del visor no se parsea correctamente.'
    } else {
        Test-Skip -Id 'visor.inventarioJson' -Detalle 'No existe documentacion/Endpoints/assets/endpoints.json para validar.'
    }

    $htmlProductivo = ''
    if (Test-Path -LiteralPath $rutaHtmlProductivo) { $htmlProductivo = [System.IO.File]::ReadAllText($rutaHtmlProductivo, (New-Object System.Text.UTF8Encoding($false))) }
    if ($htmlProductivo.Length -gt 0) {
        Test-Asercion -Id 'visor.referenciasCssJs' -Condicion (Validar-VisorReferenciasCssJs -Contenido $htmlProductivo) -DetalleExito 'APIServicios.html referencia style.css y app.js.' -DetalleFallo 'APIServicios.html no referencia style.css o app.js.'
        Test-Asercion -Id 'visor.atributosAccesibles' -Condicion (Validar-VisorAtributosAccesibles -Contenido $htmlProductivo) -DetalleExito 'APIServicios.html conserva aria-label, scope=col, filtro y hidden.' -DetalleFallo 'APIServicios.html pierde atributos accesibles.'
        Test-Asercion -Id 'visor.mobilViewport' -Condicion (Validar-VisorMobilViewport -Contenido $htmlProductivo) -DetalleExito 'APIServicios.html conserva el meta viewport movil.' -DetalleFallo 'APIServicios.html pierde el meta viewport.'
        Test-Asercion -Id 'visor.escapeHtmlJson' -Condicion (Validar-VisorJsonSinScriptCierre -Contenido $htmlProductivo) -DetalleExito 'El bloque de datos JSON no contiene </script sin escapar.' -DetalleFallo 'El bloque de datos JSON contiene </script sin escapar.'
    } else {
        Test-Skip -Id 'visor.referenciasCssJs' -Detalle 'APIServicios.html no existe (es generado e ignorado); las validaciones de HTML se omiten.'
        Test-Skip -Id 'visor.atributosAccesibles' -Detalle 'APIServicios.html no existe; no se pueden validar atributos accesibles.'
        Test-Skip -Id 'visor.mobilViewport' -Detalle 'APIServicios.html no existe; no se puede validar el viewport.'
        Test-Skip -Id 'visor.escapeHtmlJson' -Detalle 'APIServicios.html no existe; no se puede validar el escape del JSON.'
    }

    $rutaGeneradorVista = Join-Path $RaizRepositorio 'documentacion\Endpoints\binary\GenerarVistaHTML.ps1'
    if (Test-Path -LiteralPath $rutaGeneradorVista) {
        $directorioMuestra = Join-Path $DirectorioTmp 'visor'
        New-DirectorioSiNoExiste -Directorio $directorioMuestra | Out-Null
        Copy-Item -LiteralPath (Join-Path $DirectorioFixturesJson 'control-versiones-minimo.json') -Destination (Join-Path $directorioMuestra 'endpoints.json') -Force
        $rutaHtmlMuestra = Join-Path $directorioMuestra 'APIServicios.html'
        try {
            & $rutaGeneradorVista -InputDirectory $directorioMuestra -OutputPath $rutaHtmlMuestra -ConfigPath (Join-Path $DirectorioFixturesJson 'configuracion-prueba.json') | Out-Null
        } catch { }
        if (Test-Path -LiteralPath $rutaHtmlMuestra) {
            $htmlMuestra = [System.IO.File]::ReadAllText($rutaHtmlMuestra, (New-Object System.Text.UTF8Encoding($false)))
            $conformidadMuestra = (Validar-VisorReferenciasCssJs -Contenido $htmlMuestra) -and
                (Validar-VisorAtributosAccesibles -Contenido $htmlMuestra) -and
                (Validar-VisorMobilViewport -Contenido $htmlMuestra) -and
                (Validar-VisorJsonSinScriptCierre -Contenido $htmlMuestra)
            Test-Asercion -Id 'visor.herramientaHtmlConforme' -Condicion $conformidadMuestra -DetalleExito 'El HTML generado por el generador real pasa los validadores del visor.' -DetalleFallo 'El HTML generado no pasa los validadores del visor.'

            $htmlConCierreSinEscape = $htmlMuestra -replace '(?s)(<script type="application/json"[^>]*>)', '$1</script>'
            Test-Asercion -Id 'visor.herramientaDetectaScriptSinEscape' -Condicion (-not (Validar-VisorJsonSinScriptCierre -Contenido $htmlConCierreSinEscape)) -DetalleExito 'El validador detecta un cierre de script sin escapar en el JSON.' -DetalleFallo 'El validador no detecto el cierre de script sin escapar.'
        } else {
            Test-Skip -Id 'visor.herramientaHtmlConforme' -Detalle 'No se pudo generar la muestra del visor en test/tmp/.'
            Test-Skip -Id 'visor.herramientaDetectaScriptSinEscape' -Detalle 'No se pudo generar la muestra del visor en test/tmp/.'
        }
    } else {
        Test-Skip -Id 'visor.herramientaHtmlConforme' -Detalle 'No existe el generador GenerarVistaHTML.ps1.'
        Test-Skip -Id 'visor.herramientaDetectaScriptSinEscape' -Detalle 'No existe el generador GenerarVistaHTML.ps1.'
    }
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

try {
    New-DirectorioSiNoExiste -Directorio $DirectorioTmp | Out-Null
    foreach ($rutaModulo in Cargar-ModulosProduccion) {
        . $rutaModulo
    }

    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  PRUEBAS LOCALES APIGLM (pipeline, analizador y visor)' -ForegroundColor Cyan
    Write-Host ("  " + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan

    # Los grupos de casos se incorporan en los pasos 5 a 10 del plan.
    Ejecutar-CasosConfiguracion
    Ejecutar-CasosPipeline
    Ejecutar-CasosPosicionesGet
    Ejecutar-CasosMultiXpz
    Ejecutar-CasosAnalizador
    Ejecutar-CasosValidacionMarkdown
    Ejecutar-CasosVisor
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
