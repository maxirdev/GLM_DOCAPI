# Orquestador interactivo de la gestion de documentos APIGLM (multicliente).

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Repositorio
)

$ErrorActionPreference = 'Stop'
$raizRepositorio = [System.IO.Path]::GetFullPath($Repositorio)
$rutaPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

$script:Contexto = $null
$script:rutaConfiguracion = Join-Path $raizRepositorio 'configuracion.json'
$script:rutaDirectorioXpz = ''
$script:rutaDirectorioServicios = ''
$script:rutaControl = ''
$script:xpzActivo = ''
$script:xpzActivoEstablecido = $false
$ultimoCodigo = 0
$codigoCompleto = 0
$codigoErrorFatal = 1
$codigoParcial = 2
$codigoAbortado = 3

. (Join-Path $PSScriptRoot 'GLMUtilidades.ps1')
. (Join-Path $PSScriptRoot 'ManifiestoEjecucion.ps1')
. (Join-Path $PSScriptRoot 'CargarConfiguracion.ps1')

function Normalizar-CodigoSalida {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$Codigo
    )

    if ($Codigo -in @($codigoCompleto, $codigoErrorFatal, $codigoParcial, $codigoAbortado)) {
        return $Codigo
    }
    return $codigoErrorFatal
}

function Leer-ConfiguracionGlobal {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $script:rutaConfiguracion -PathType Leaf)) {
        throw ('No se encontro la configuracion: ' + $script:rutaConfiguracion)
    }
    return ([System.IO.File]::ReadAllText($script:rutaConfiguracion) | ConvertFrom-Json)
}

function Invocar-ScriptPowerShell {
    <#
    .SYNOPSIS
    Ejecuta un script PowerShell como proceso hijo normalizando su codigo de salida.
    .DESCRIPTION
    Wrapper de Invocar-ScriptHijo (GLMUtilidades.ps1) para preservar la firma
    historica y la normalizacion a 0/1/2/3 de este orquestador.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaScript,
        [Parameter(Mandatory = $false)][string[]]$Argumentos = @()
    )

    $resultado = Invocar-ScriptHijo -RutaScript $RutaScript -Argumentos $Argumentos -NormalizarCodigo
    return (Normalizar-CodigoSalida -Codigo $resultado.CodigoSalida)
}

function Obtener-XpzPrincipales {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $script:rutaDirectorioXpz -PathType Container)) {
        return @()
    }

    $rutaListado = Join-Path $PSScriptRoot 'ListarXPZPrincipales.ps1'
    $salida = @(& $rutaPowerShell -NoProfile -ExecutionPolicy Bypass -File $rutaListado -DirectorioXpz $script:rutaDirectorioXpz 2>&1)
    $codigoSalida = Normalizar-CodigoSalida -Codigo ([int]$LASTEXITCODE)
    if ($codigoSalida -ne $codigoCompleto) {
        throw 'No se pudo listar los XPZ principales.'
    }

    $entradas = New-Object System.Collections.Generic.List[object]
    foreach ($lineaSalida in $salida) {
        $texto = [string]$lineaSalida
        $partes = $texto -split '\|', 3
        if ($partes.Count -ne 3) { continue }
        [void]$entradas.Add([pscustomobject]@{
            Nombre = $partes[0]
            Ruta = Join-Path $script:rutaDirectorioXpz $partes[0]
            Fecha = $partes[1]
            EsUltimo = $partes[2]
        })
    }
    return @($entradas.ToArray())
}

function Establecer-XpzActivoConfigurado {
    [CmdletBinding()]
    param()

    if ($script:xpzActivoEstablecido) { return }
    $principales = @(Obtener-XpzPrincipales)
    if ($principales.Count -gt 0) {
        $masReciente = @($principales | Where-Object { $_.EsUltimo -eq '1' }) | Select-Object -First 1
        if ($null -eq $masReciente) { $masReciente = $principales[$principales.Count - 1] }
        $script:xpzActivo = [string]$masReciente.Ruta
    }
    $script:xpzActivoEstablecido = $true
}

function Seleccionar-XpzActivo {
    [CmdletBinding()]
    param()

    $principales = @(Obtener-XpzPrincipales)
    if ($principales.Count -eq 0) {
        Write-Host 'ERROR: No se encontraron XPZ principales.' -ForegroundColor Red
        return $codigoErrorFatal
    }

    Write-Host ''
    Write-Host 'XPZ principales disponibles:' -ForegroundColor Cyan
    for ($indice = 0; $indice -lt $principales.Count; $indice++) {
        $marcaUltimo = ''
        if ($principales[$indice].EsUltimo -eq '1') { $marcaUltimo = ' [ULTIMO]' }
        Write-Host ('  {0}. {1} | {2}{3}' -f ($indice + 1), $principales[$indice].Nombre, $principales[$indice].Fecha, $marcaUltimo)
    }

    while ($true) {
        $textoSeleccion = Read-Host ('Seleccione el XPZ principal [1-' + $principales.Count + ']')
        $seleccion = 0
        if ([int]::TryParse($textoSeleccion, [ref]$seleccion) -and $seleccion -ge 1 -and $seleccion -le $principales.Count) {
            $script:xpzActivo = [System.IO.Path]::GetFullPath($principales[$seleccion - 1].Ruta)
            $script:xpzActivoEstablecido = $true
            Write-Host ''
            Write-Host ('XPZ activo de la sesion: ' + [System.IO.Path]::GetFileName($script:xpzActivo)) -ForegroundColor Green
            Write-Host 'ADVERTENCIA: El packagename del cliente no se modifica al cambiar de XPZ.' -ForegroundColor Yellow
            Write-Host 'El endpoint publicado podria no corresponder al XPZ seleccionado.' -ForegroundColor Yellow
            return $codigoCompleto
        }
        Write-Host 'Seleccion invalida.' -ForegroundColor Yellow
    }
}

function Ejecutar-Preflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$ClienteId = '',
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$AmbienteId = ''
    )

    Write-Host ''
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  VALIDACION INICIAL' -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host ''
    $rutaValidador = Join-Path $PSScriptRoot 'ValidarConfiguracionGLM.ps1'
    $argumentos = @('-Repositorio', $raizRepositorio)
    if (-not [string]::IsNullOrWhiteSpace($ClienteId) -and -not [string]::IsNullOrWhiteSpace($AmbienteId)) {
        $argumentos += @('-ClienteId', $ClienteId, '-AmbienteId', $AmbienteId)
    }
    return (Invocar-ScriptPowerShell -RutaScript $rutaValidador -Argumentos $argumentos)
}

function Seleccionar-Contexto {
    <#
    .SYNOPSIS
    Selecciona cliente y ambiente y valida el contexto con el preflight completo.
    .DESCRIPTION
    Muestra los clientes configurados y luego los ambientes del cliente elegido.
    Ejecuta el preflight del contexto (esquema, herramientas, cliente, ambiente y
    KB) y solo si supera devuelve el objeto de contexto. Con -PermitirCancelar la
    opcion 0 cancela sin cambiar nada. Devuelve $null si cancela o si el preflight falla.
    #>
    [CmdletBinding()]
    param(
        [switch]$PermitirCancelar
    )

    $configuracionGlobal = $null
    try {
        $configuracionGlobal = Leer-ConfiguracionGlobal
    } catch {
        Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
        return $null
    }

    $clientes = @(Obtener-ClientesConfigurados -ConfiguracionRaw $configuracionGlobal)
    if ($clientes.Count -eq 0) {
        Write-Host 'ERROR: La configuracion no define clientes.' -ForegroundColor Red
        return $null
    }

    Write-Host ''
    Write-Host 'Clientes configurados:' -ForegroundColor Cyan
    for ($indice = 0; $indice -lt $clientes.Count; $indice++) {
        Write-Host ('  {0}. {1} ({2})' -f ($indice + 1), $clientes[$indice].Nombre, $clientes[$indice].Id)
    }
    if ($PermitirCancelar) {
        Write-Host '  0. Cancelar' -ForegroundColor Gray
    }
    $clienteSeleccionado = $null
    while ($null -eq $clienteSeleccionado) {
        $rango = '1-' + $clientes.Count
        if ($PermitirCancelar) { $rango = '0-' + $clientes.Count }
        $textoSeleccion = Read-Host ('Seleccione el cliente [' + $rango + ']')
        $seleccion = 0
        if ([int]::TryParse($textoSeleccion, [ref]$seleccion)) {
            if ($PermitirCancelar -and $seleccion -eq 0) { return $null }
            if ($seleccion -ge 1 -and $seleccion -le $clientes.Count) {
                $clienteSeleccionado = $clientes[$seleccion - 1]
                continue
            }
        }
        Write-Host 'Seleccion invalida.' -ForegroundColor Yellow
    }

    $ambientes = @(Obtener-AmbientesConfigurados -ConfiguracionRaw $configuracionGlobal -ClienteId $clienteSeleccionado.Id)
    if ($ambientes.Count -eq 0) {
        Write-Host ('ERROR: El cliente ' + $clienteSeleccionado.Id + ' no define ambientes.') -ForegroundColor Red
        return $null
    }

    Write-Host ''
    Write-Host ('Ambientes de ' + $clienteSeleccionado.Nombre + ' (' + $clienteSeleccionado.Id + '):') -ForegroundColor Cyan
    for ($indice = 0; $indice -lt $ambientes.Count; $indice++) {
        Write-Host ('  {0}. {1} ({2})' -f ($indice + 1), $ambientes[$indice].Nombre, $ambientes[$indice].Id)
    }
    if ($PermitirCancelar) {
        Write-Host '  0. Cancelar' -ForegroundColor Gray
    }
    $ambienteSeleccionado = $null
    while ($null -eq $ambienteSeleccionado) {
        $rango = '1-' + $ambientes.Count
        if ($PermitirCancelar) { $rango = '0-' + $ambientes.Count }
        $textoSeleccion = Read-Host ('Seleccione el ambiente [' + $rango + ']')
        $seleccion = 0
        if ([int]::TryParse($textoSeleccion, [ref]$seleccion)) {
            if ($PermitirCancelar -and $seleccion -eq 0) { return $null }
            if ($seleccion -ge 1 -and $seleccion -le $ambientes.Count) {
                $ambienteSeleccionado = $ambientes[$seleccion - 1]
                continue
            }
        }
        Write-Host 'Seleccion invalida.' -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Host ('Preflight del contexto ' + $clienteSeleccionado.Id + '/' + $ambienteSeleccionado.Id + '...') -ForegroundColor Cyan
    $codigoPreflight = Ejecutar-Preflight -ClienteId $clienteSeleccionado.Id -AmbienteId $ambienteSeleccionado.Id
    if ($codigoPreflight -ne $codigoCompleto) {
        Write-Host 'El contexto no supero el preflight. Revise el mensaje anterior.' -ForegroundColor Yellow
        return $null
    }

    try {
        return (Cargar-Configuracion -ConfigPath $script:rutaConfiguracion -ClienteId $clienteSeleccionado.Id -AmbienteId $ambienteSeleccionado.Id)
    } catch {
        Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
        return $null
    }
}

function Activar-Contexto {
    <#
    .SYNOPSIS
    Activa un contexto y deriva todas las rutas operativas desde el.
    .DESCRIPTION
    Reasigna las rutas de documentos, XPZ, estado y control desde el objeto de
    contexto y restablece el XPZ activo por defecto. Ninguna operacion posterior
    conserva rutas del contexto anterior.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Contexto
    )

    $script:Contexto = $Contexto
    $script:rutaConfiguracion = $Contexto.ConfigPath
    $script:rutaDirectorioXpz = $Contexto.DirectorioXpz
    $script:rutaDirectorioServicios = $Contexto.DirectorioServicios
    $script:rutaControl = $Contexto.RutaControl
    $script:xpzActivo = ''
    $script:xpzActivoEstablecido = $false
    Write-Host ''
    Write-Host ('Contexto activo: ' + $Contexto.ContextId + ' (' + $Contexto.ClienteNombre + ' / ' + $Contexto.AmbienteNombre + ')') -ForegroundColor Green
}

function Cambiar-Contexto {
    [CmdletBinding()]
    param()

    Write-Host ''
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  CAMBIAR DE CLIENTE O AMBIENTE' -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan
    $nuevoContexto = Seleccionar-Contexto -PermitirCancelar
    if ($null -eq $nuevoContexto) {
        Write-Host 'Se mantiene el contexto activo.' -ForegroundColor Yellow
        return
    }
    Activar-Contexto -Contexto $nuevoContexto
}

function Esperar-Retorno {
    [CmdletBinding()]
    param()

    Write-Host ''
    [void](Read-Host 'Presione ENTER para volver al menu')
}

function Mostrar-Encabezado {
    [CmdletBinding()]
    param()

    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  GESTION DE DOCUMENTOS APIGLM' -ForegroundColor Cyan
    Write-Host ('  ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan
    $clienteTexto = 'ninguno'
    $ambienteTexto = 'ninguno'
    if ($script:Contexto) {
        $clienteTexto = $script:Contexto.ClienteNombre + ' (' + $script:Contexto.ClienteId + ')'
        $ambienteTexto = $script:Contexto.AmbienteNombre + ' (' + $script:Contexto.AmbienteId + ')'
    }
    $nombreXpz = 'ninguno'
    if (-not [string]::IsNullOrWhiteSpace($script:xpzActivo)) {
        $nombreXpz = [System.IO.Path]::GetFileName($script:xpzActivo)
    }
    Write-Host ('Cliente: ' + $clienteTexto) -ForegroundColor Green
    Write-Host ('Ambiente: ' + $ambienteTexto) -ForegroundColor Green
    Write-Host ('XPZ activo: ' + $nombreXpz) -ForegroundColor Green
}

function Obtener-CantidadPdfVigentes {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $script:rutaDirectorioServicios -PathType Container)) { return 0 }
    return @((Get-ChildItem -LiteralPath $script:rutaDirectorioServicios -Filter '*.pdf' -File -ErrorAction SilentlyContinue)).Count
}

function Confirmar-ReinicioVersionado {
    [CmdletBinding()]
    param()

    Write-Host ''
    Write-Host 'ADVERTENCIA: La regeneracion de los PDF implica reiniciar el control de versionado.' -ForegroundColor Yellow
    Write-Host 'Se perdera el historial de revisiones y los servicios publicados comenzaran en la version 1.0.' -ForegroundColor Yellow
    Write-Host 'El control se reconstruira de forma atomica al finalizar la ejecucion.' -ForegroundColor Yellow
    while ($true) {
        $respuesta = (Read-Host 'Desea continuar? [S/N]').Trim().ToUpperInvariant()
        if ($respuesta -eq 'S') { return $true }
        if ($respuesta -eq 'N') { return $false }
        Write-Host 'Respuesta invalida. Indique S o N.' -ForegroundColor Yellow
    }
}

function Ejecutar-Exportacion {
    [CmdletBinding()]
    param()

    Write-Host ''
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  EXPORTAR SEGUN CONFIGURACION Y COMPLETAR EL XPZ' -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host ''
    $rutaExportador = Join-Path $PSScriptRoot 'EjecutarExportacionGLM.ps1'
    $codigoSalida = Invocar-ScriptPowerShell -RutaScript $rutaExportador -Argumentos @('-Repositorio', $raizRepositorio, '-ClienteId', $script:Contexto.ClienteId, '-Modulo', $script:Contexto.Modulo, '-AmbienteId', $script:Contexto.AmbienteId)
    if ($codigoSalida -eq $codigoAbortado) {
        Write-Host 'Exportacion abortada por el usuario.' -ForegroundColor Yellow
        return $codigoAbortado
    }
    if ($codigoSalida -eq $codigoParcial) {
        Write-Host 'La exportacion termino parcialmente; no se continuara como si fuera un exito.' -ForegroundColor Yellow
        return $codigoParcial
    }
    if ($codigoSalida -eq $codigoCompleto) {
        $script:xpzActivoEstablecido = $false
        Establecer-XpzActivoConfigurado
        return $codigoCompleto
    }

    Write-Host ''
    Write-Host 'WARNING: No se pudo exportar un XPZ nuevo desde la Knowledge Base.' -ForegroundColor Yellow
    Write-Host 'Puede seleccionar un XPZ principal existente o abortar la operacion.' -ForegroundColor Yellow
    $respuesta = Read-Host 'Seleccione: 1. Usar XPZ existente  2. Abortar'
    if ($respuesta -ne '1') {
        Write-Host 'Operacion abortada.' -ForegroundColor Yellow
        return $codigoAbortado
    }
    $codigoSeleccion = Seleccionar-XpzActivo
    if ($codigoSeleccion -ne $codigoCompleto) { return $codigoErrorFatal }
    Write-Host ''
    Write-Host 'XPZ existente seleccionado. Se continuara con la busqueda de actualizaciones.' -ForegroundColor Green
    return $codigoCompleto
}

function Ejecutar-ActualizacionServicios {
    [CmdletBinding()]
    param()

    Write-Host ''
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  BUSCAR ACTUALIZACION DE SERVICIOS' -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Actualizacion: exportando y completando el XPZ segun configuracion...' -ForegroundColor Cyan
    $codigoExportacion = Ejecutar-Exportacion
    if ($codigoExportacion -eq $codigoAbortado) {
        return $codigoAbortado
    }
    if ($codigoExportacion -eq $codigoParcial) {
        return $codigoParcial
    }
    if ($codigoExportacion -ne $codigoCompleto) {
        return $codigoErrorFatal
    }
    if ([string]::IsNullOrWhiteSpace($script:xpzActivo)) {
        Write-Host 'ERROR: La exportacion no establecio un XPZ activo.' -ForegroundColor Red
        return $codigoErrorFatal
    }
    $manifiestoActualizacion = Crear-ManifiestoEjecucion -Xpz $script:xpzActivo -FullyQualifiedNames @() -Contexto $script:Contexto
    $rutaManifiestoActualizacion = $manifiestoActualizacion.Ruta
    try {
        $rutaActualizador = Join-Path $PSScriptRoot 'ActualizarServicios.ps1'
        return (Invocar-ScriptPowerShell -RutaScript $rutaActualizador -Argumentos @('-ConfigPath', $script:rutaConfiguracion, '-ManifiestoPath', $rutaManifiestoActualizacion))
    } finally {
        Eliminar-ManifiestoEjecucion -RutaManifiesto $rutaManifiestoActualizacion
    }
}

function Ejecutar-RegeneracionPdf {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($script:xpzActivo)) {
        Write-Host 'ERROR: No hay un XPZ activo para la generacion de PDF.' -ForegroundColor Red
        return $codigoErrorFatal
    }
    if (-not (Confirmar-ReinicioVersionado)) {
        Write-Host 'Regeneracion de PDF abortada por el usuario.' -ForegroundColor Yellow
        return $codigoAbortado
    }

    $manifiestoOperacion = Crear-ManifiestoEjecucion -Xpz $script:xpzActivo -FullyQualifiedNames @() -Contexto $script:Contexto
    $rutaManifiestoOperacion = $manifiestoOperacion.Ruta
    try {

    Write-Host ''
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  GENERAR PDF DESDE EL XPZ ACTIVO' -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host ('XPZ activo: ' + $script:xpzActivo)

    Write-Host ''
    Write-Host 'Validando la completitud del XPZ y completando los elementos necesarios...' -ForegroundColor Cyan
    $rutaCompletador = Join-Path $PSScriptRoot 'CompletarXPZActivoGLM.ps1'
    $codigoCompletado = Invocar-ScriptPowerShell -RutaScript $rutaCompletador -Argumentos @('-Repositorio', $raizRepositorio, '-XpzActivo', $script:xpzActivo, '-ManifiestoPath', $rutaManifiestoOperacion)
    if ($codigoCompletado -eq $codigoAbortado) {
        return $codigoAbortado
    }
    if ($codigoCompletado -eq $codigoParcial) {
        return $codigoParcial
    }
    if ($codigoCompletado -ne $codigoCompleto) {
        return $codigoErrorFatal
    }

    Write-Host ''
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  REGENERAR DOCUMENTACION Y PDF CON CONTROL DE VERSIONES' -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host ''
    $rutaActualizador = Join-Path $PSScriptRoot 'ActualizarServicios.ps1'
    $codigoActualizacion = Invocar-ScriptPowerShell -RutaScript $rutaActualizador -Argumentos @('-ConfigPath', $script:rutaConfiguracion, '-XpzPath', $script:xpzActivo, '-ForzarRegeneracionCompleta', '-Inicializar', '-ManifiestoPath', $rutaManifiestoOperacion)
    if ($codigoActualizacion -eq $codigoAbortado) {
        return $codigoAbortado
    }
    if ($codigoActualizacion -eq $codigoParcial) {
        return $codigoParcial
    }
    if ($codigoActualizacion -ne $codigoCompleto) {
        return $codigoErrorFatal
    }

    $rutaResumen = Join-Path $PSScriptRoot 'ResumirOperacionPdf.ps1'
    $codigoResumen = Invocar-ScriptPowerShell -RutaScript $rutaResumen -Argumentos @('-Repositorio', $raizRepositorio, '-ManifiestoPath', $rutaManifiestoOperacion)
    return $codigoResumen
    } finally {
        Eliminar-ManifiestoEjecucion -RutaManifiesto $rutaManifiestoOperacion
    }
}

function Ejecutar-PruebasLocales {
    [CmdletBinding()]
    param()

    Write-Host ''
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  EJECUTAR PRUEBAS LOCALES (test\Run-Tests.ps1)' -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host ''
    $rutaPruebas = Join-Path $raizRepositorio 'test\Run-Tests.ps1'
    $argumentosPruebas = @()
    if ($script:Contexto) {
        $argumentosPruebas += @('-ClienteId', $script:Contexto.ClienteId, '-AmbienteId', $script:Contexto.AmbienteId, '-ConfigPath', $script:rutaConfiguracion)
    }
    return (Invocar-ScriptPowerShell -RutaScript $rutaPruebas -Argumentos $argumentosPruebas)
}

function Leer-OpcionMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][bool]$HayXpz
    )

    if (-not $HayXpz) {
        Write-Host '[AVISO] No hay archivos XPZ disponibles en:' -ForegroundColor Yellow
        Write-Host ('  ' + $script:rutaDirectorioXpz)
        Write-Host 'Puede exportar APIGLMMain para generar el XPZ o salir.'
        Write-Host ''
        Write-Host '  1. Exportar APIGLMMain' -ForegroundColor White
        Write-Host '  2. Cambiar de cliente o ambiente' -ForegroundColor White
        Write-Host '  3. Salir' -ForegroundColor White
        Write-Host ''
        return (Read-Host 'Seleccione una opcion [1-3]')
    }

    $textoOpcionUno = 'Exportar segun configuracion (APIGLM/KB) y completar el XPZ'
    $textoOpcionTres = 'Generar PDF con el XPZ seleccionado (reinicia el versionado)'
    if ((Obtener-CantidadPdfVigentes) -gt 0) {
        $textoOpcionUno = 'Buscar actualizacion de servicios'
        $textoOpcionTres = 'Regenerar PDF (reinicia el versionado)'
    }
    Write-Host ('  1. ' + $textoOpcionUno) -ForegroundColor White
    Write-Host '  2. Seleccionar XPZ principal' -ForegroundColor White
    Write-Host ('  3. ' + $textoOpcionTres) -ForegroundColor White
    Write-Host '  4. Cambiar de cliente o ambiente' -ForegroundColor White
    Write-Host '  5. Ejecutar pruebas locales (test\Run-Tests.ps1)' -ForegroundColor White
    Write-Host '  6. Salir' -ForegroundColor White
    Write-Host ''
    return (Read-Host 'Seleccione una opcion [1-6]')
}

try {
    if (-not (Test-Path -LiteralPath $raizRepositorio -PathType Container)) {
        throw ('No existe el repositorio: ' + $raizRepositorio)
    }
    if (-not (Test-Path -LiteralPath $rutaPowerShell -PathType Leaf)) {
        throw ('No se encontro Windows PowerShell en: ' + $rutaPowerShell)
    }

    $codigoPreflight = $null
    try {
        $codigoPreflight = Ejecutar-Preflight
    } catch {
        Write-Host ('ERROR DE ARRANQUE: ' + $_.Exception.Message) -ForegroundColor Red
        $codigoPreflight = 1
    }
    if ($codigoPreflight -ne $codigoCompleto) {
        Write-Host 'No se pudo validar la configuracion global. Revise configuracion.json.' -ForegroundColor Yellow
        exit $codigoPreflight
    }

    $contextoSeleccionado = Seleccionar-Contexto
    if ($null -eq $contextoSeleccionado) {
        Write-Host 'No se pudo activar un contexto valido.' -ForegroundColor Yellow
        exit $codigoErrorFatal
    }
    Activar-Contexto -Contexto $contextoSeleccionado

    while ($true) {
        $principalesDisponibles = @()
        try { $principalesDisponibles = @(Obtener-XpzPrincipales) } catch { $principalesDisponibles = @() }

        Write-Host ''
        Mostrar-Encabezado
        Write-Host ''
        $opcion = Leer-OpcionMenu -HayXpz ($principalesDisponibles.Count -gt 0)

        if ($principalesDisponibles.Count -eq 0) {
            if ($opcion -eq '3') { break }
            if ($opcion -eq '2') {
                Cambiar-Contexto
                Esperar-Retorno
            }
            if ($opcion -eq '1') {
                $ultimoCodigo = Ejecutar-Exportacion
                Esperar-Retorno
            }
            continue
        }

        switch ($opcion) {
            '1' {
                if ((Obtener-CantidadPdfVigentes) -gt 0) {
                    $ultimoCodigo = Ejecutar-ActualizacionServicios
                } else {
                    $ultimoCodigo = Ejecutar-Exportacion
                }
                Esperar-Retorno
            }
            '2' {
                $ultimoCodigo = Seleccionar-XpzActivo
                Esperar-Retorno
            }
            '3' {
                $ultimoCodigo = Ejecutar-RegeneracionPdf
                Esperar-Retorno
            }
            '4' {
                Cambiar-Contexto
                Esperar-Retorno
            }
            '5' {
                $ultimoCodigo = Ejecutar-PruebasLocales
                Esperar-Retorno
            }
            '6' { break }
            default { Write-Host 'Opcion invalida.' -ForegroundColor Yellow }
        }
        if ($opcion -eq '6') { break }
    }

    Write-Host ''
    Write-Host 'Saliendo de la gestion de documentos APIGLM.'
    exit $ultimoCodigo
} catch {
    Write-Host ''
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
