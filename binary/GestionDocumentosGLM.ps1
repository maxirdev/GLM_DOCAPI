# Orquestador interactivo de la gestion de documentos APIGLM.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Repositorio
)

$ErrorActionPreference = 'Stop'
$raizRepositorio = [System.IO.Path]::GetFullPath($Repositorio)
$rutaPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$rutaConfiguracion = Join-Path $raizRepositorio 'configuracion.json'
$rutaDirectorioXpz = Join-Path $raizRepositorio 'xpz'
$rutaDirectorioServicios = Join-Path $raizRepositorio 'documentacion\servicios'
$xpzActivo = ''
$xpzActivoEstablecido = $false
$ultimoCodigo = 0
$codigoCompleto = 0
$codigoErrorFatal = 1
$codigoParcial = 2
$codigoAbortado = 3

. (Join-Path $PSScriptRoot 'ManifiestoEjecucion.ps1')

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

function Resolver-RutaRepositorio {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Ruta
    )

    if ([System.IO.Path]::IsPathRooted($Ruta)) {
        return [System.IO.Path]::GetFullPath($Ruta)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $raizRepositorio $Ruta))
}

function Leer-Configuracion {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $rutaConfiguracion -PathType Leaf)) {
        throw ('No se encontro la configuracion: ' + $rutaConfiguracion)
    }
    return ([System.IO.File]::ReadAllText($rutaConfiguracion) | ConvertFrom-Json)
}

function Invocar-ScriptPowerShell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaScript,
        [Parameter(Mandatory = $false)][string[]]$Argumentos = @()
    )

    if (-not (Test-Path -LiteralPath $RutaScript -PathType Leaf)) {
        throw ('No se encontro el script: ' + $RutaScript)
    }
    & $rutaPowerShell -NoProfile -ExecutionPolicy Bypass -File $RutaScript @Argumentos 2>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            Write-Host $_ -ForegroundColor Red
        } else {
            Write-Host ([string]$_)
        }
    }
    $codigoSalida = [int]$LASTEXITCODE
    return (Normalizar-CodigoSalida -Codigo $codigoSalida)
}

function Obtener-XpzPrincipales {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $rutaDirectorioXpz -PathType Container)) {
        return @()
    }

    $rutaListado = Join-Path $PSScriptRoot 'ListarXPZPrincipales.ps1'
    $salida = @(& $rutaPowerShell -NoProfile -ExecutionPolicy Bypass -File $rutaListado -DirectorioXpz $rutaDirectorioXpz 2>&1)
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
            Ruta = Join-Path $rutaDirectorioXpz $partes[0]
            Fecha = $partes[1]
            EsUltimo = $partes[2]
        })
    }
    return @($entradas.ToArray())
}

function Establecer-XpzActivoConfigurado {
    [CmdletBinding()]
    param()

    if ($xpzActivoEstablecido) { return }
    $configuracion = Leer-Configuracion
    $rutaConfigurada = [string]$configuracion.xpz
    if (-not [string]::IsNullOrWhiteSpace($rutaConfigurada)) {
        $rutaResuelta = Resolver-RutaRepositorio -Ruta $rutaConfigurada
        if (Test-Path -LiteralPath $rutaResuelta -PathType Leaf) {
            $script:xpzActivo = $rutaResuelta
        }
    }

    if ([string]::IsNullOrWhiteSpace($script:xpzActivo)) {
        $principales = @(Obtener-XpzPrincipales)
        if ($principales.Count -gt 0) {
            $script:xpzActivo = [string]$principales[0].Ruta
        }
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
            Write-Host 'ADVERTENCIA: El packagename de configuracion.json no se modifica al cambiar de XPZ.' -ForegroundColor Yellow
            Write-Host 'El endpoint publicado podria no corresponder al XPZ seleccionado.' -ForegroundColor Yellow
            return $codigoCompleto
        }
        Write-Host 'Seleccion invalida.' -ForegroundColor Yellow
    }
}

function Ejecutar-Preflight {
    [CmdletBinding()]
    param()

    Write-Host ''
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  VALIDACION INICIAL' -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host ''
    $rutaValidador = Join-Path $PSScriptRoot 'ValidarConfiguracionGLM.ps1'
    return (Invocar-ScriptPowerShell -RutaScript $rutaValidador -Argumentos @('-Repositorio', $raizRepositorio))
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
    $nombreXpz = 'ninguno'
    if (-not [string]::IsNullOrWhiteSpace($xpzActivo)) {
        $nombreXpz = [System.IO.Path]::GetFileName($xpzActivo)
    }
    Write-Host ('XPZ activo: ' + $nombreXpz) -ForegroundColor Green
}

function Obtener-CantidadPdfVigentes {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $rutaDirectorioServicios -PathType Container)) { return 0 }
    return @((Get-ChildItem -LiteralPath $rutaDirectorioServicios -Filter '*.pdf' -File -ErrorAction SilentlyContinue)).Count
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
    $codigoSalida = Invocar-ScriptPowerShell -RutaScript $rutaExportador -Argumentos @('-Repositorio', $raizRepositorio)
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
    Write-Host 'XPZ existente seleccionado. Use la opcion 3 para generar la documentacion.' -ForegroundColor Green
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
    $rutaActualizador = Join-Path $PSScriptRoot 'ActualizarServicios.ps1'
    return (Invocar-ScriptPowerShell -RutaScript $rutaActualizador -Argumentos @('-ConfigPath', $rutaConfiguracion))
}

function Ejecutar-RegeneracionPdf {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($xpzActivo)) {
        Write-Host 'ERROR: No hay un XPZ activo para la generacion de PDF.' -ForegroundColor Red
        return $codigoErrorFatal
    }

    $manifiestoOperacion = Crear-ManifiestoEjecucion -Xpz $xpzActivo -FullyQualifiedNames @()
    $rutaManifiestoOperacion = $manifiestoOperacion.Ruta
    try {

    Write-Host ''
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  GENERAR PDF DESDE EL XPZ ACTIVO' -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host ('XPZ activo: ' + $xpzActivo)

    $rutaInventario = Join-Path $raizRepositorio 'documentacion\Endpoints\binary\GenerarListaEndpoints.ps1'
    $codigoInventario = Invocar-ScriptPowerShell -RutaScript $rutaInventario -Argumentos @('-ConfigPath', $rutaConfiguracion, '-XpzPath', $xpzActivo, '-ManifiestoPath', $rutaManifiestoOperacion)
    if ($codigoInventario -eq $codigoAbortado) {
        return $codigoAbortado
    }
    if ($codigoInventario -eq $codigoParcial) {
        return $codigoParcial
    }
    if ($codigoInventario -ne $codigoCompleto) {
        return $codigoErrorFatal
    }

    Write-Host ''
    Write-Host 'Validando la completitud del XPZ y completando los elementos necesarios...' -ForegroundColor Cyan
    $rutaCompletador = Join-Path $PSScriptRoot 'CompletarXPZActivoGLM.ps1'
    $codigoCompletado = Invocar-ScriptPowerShell -RutaScript $rutaCompletador -Argumentos @('-Repositorio', $raizRepositorio, '-XpzActivo', $xpzActivo, '-ManifiestoPath', $rutaManifiestoOperacion)
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
    $codigoActualizacion = Invocar-ScriptPowerShell -RutaScript $rutaActualizador -Argumentos @('-ConfigPath', $rutaConfiguracion, '-XpzPath', $xpzActivo, '-ForzarRegeneracionCompleta', '-ManifiestoPath', $rutaManifiestoOperacion)
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
    $codigoResumen = Invocar-ScriptPowerShell -RutaScript $rutaResumen -Argumentos @('-Repositorio', $raizRepositorio)
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
    return (Invocar-ScriptPowerShell -RutaScript $rutaPruebas)
}

function Leer-OpcionMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][bool]$HayXpz,
        [Parameter(Mandatory = $true)][bool]$ConfiguracionValida
    )

    if (-not $ConfiguracionValida) {
        Write-Host '  1. Salir' -ForegroundColor White
        Write-Host ''
        return (Read-Host 'Presione 1 para salir')
    }

    if (-not $HayXpz) {
        Write-Host '[AVISO] No hay archivos XPZ disponibles en:' -ForegroundColor Yellow
        Write-Host ('  ' + $rutaDirectorioXpz)
        Write-Host 'Puede exportar APIGLMMain para generar el XPZ o salir.'
        Write-Host ''
        Write-Host '  1. Exportar APIGLMMain' -ForegroundColor White
        Write-Host '  2. Salir' -ForegroundColor White
        Write-Host ''
        return (Read-Host 'Seleccione una opcion [1-2]')
    }

    $textoOpcionUno = 'Exportar segun configuracion (APIGLM/KB) y completar el XPZ'
    $textoOpcionTres = 'Generar PDF con el XPZ seleccionado'
    if ((Obtener-CantidadPdfVigentes) -gt 0) {
        $textoOpcionUno = 'Buscar actualizacion de servicios'
        $textoOpcionTres = 'Regenerar PDF'
    }
    Write-Host ('  1. ' + $textoOpcionUno) -ForegroundColor White
    Write-Host '  2. Seleccionar XPZ principal' -ForegroundColor White
    Write-Host ('  3. ' + $textoOpcionTres) -ForegroundColor White
    Write-Host '  4. Ejecutar pruebas locales (test\Run-Tests.ps1)' -ForegroundColor White
    Write-Host '  5. Salir' -ForegroundColor White
    Write-Host ''
    return (Read-Host 'Seleccione una opcion [1-5]')
}

try {
    if (-not (Test-Path -LiteralPath $raizRepositorio -PathType Container)) {
        throw ('No existe el repositorio: ' + $raizRepositorio)
    }
    if (-not (Test-Path -LiteralPath $rutaPowerShell -PathType Leaf)) {
        throw ('No se encontro Windows PowerShell en: ' + $rutaPowerShell)
    }

    while ($true) {
        try {
            $codigoPreflight = Ejecutar-Preflight
        } catch {
            Write-Host ('ERROR DE ARRANQUE: ' + $_.Exception.Message) -ForegroundColor Red
            $codigoPreflight = 1
        }
        $configuracionValida = $codigoPreflight -ne $codigoErrorFatal

        $principalesDisponibles = @()
        if ($configuracionValida) {
            try { $principalesDisponibles = @(Obtener-XpzPrincipales) } catch { $principalesDisponibles = @() }
            if (-not $xpzActivoEstablecido) {
                try { Establecer-XpzActivoConfigurado } catch { }
            }
        }

        Write-Host ''
        Mostrar-Encabezado
        Write-Host ''
        $opcion = Leer-OpcionMenu -HayXpz ($principalesDisponibles.Count -gt 0) -ConfiguracionValida $configuracionValida

        if (-not $configuracionValida) {
            break
        }
        if ($principalesDisponibles.Count -eq 0) {
            if ($opcion -eq '2') { break }
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
                $ultimoCodigo = Ejecutar-PruebasLocales
                Esperar-Retorno
            }
            '5' { break }
            default { Write-Host 'Opcion invalida.' -ForegroundColor Yellow }
        }
        if ($opcion -eq '5') { break }
    }

    Write-Host ''
    Write-Host 'Saliendo de la gestion de documentos APIGLM.'
    exit $ultimoCodigo
} catch {
    Write-Host ''
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
