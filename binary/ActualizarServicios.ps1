# ActualizarServicios.ps1
# Orquestador de generacion incremental de Markdown, PDF y control de versiones.

[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$XpzPath,
    [string]$RutaControl,
    [switch]$Inicializar,
    [switch]$ForzarRegeneracionCompleta,
    [string]$ManifiestoPath
)

$ErrorActionPreference = 'Stop'
$inicioEjecucion = Get-Date
$raizRepositorio = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $ConfigPath) { $ConfigPath = Join-Path $raizRepositorio 'configuracion.json' }
if (-not $RutaControl) { $RutaControl = Join-Path $raizRepositorio 'estado\controlVersiones.json' }
$rutaManifiestoEjecucion = $ManifiestoPath
$rutaLockActualizacion = Join-Path $raizRepositorio 'estado\actualizacion.lock'
$lockActualizacion = $null

function Obtener-Sha256TextoNormalizado {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Texto
    )

    $textoNormalizado = ($Texto -replace "`r`n", "`n") -replace "`r", "`n"
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($textoNormalizado)
        return (([System.BitConverter]::ToString($sha256.ComputeHash($bytes))) -replace '-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function Adquirir-LockActualizacion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaLock
    )

    $directorioLock = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($RutaLock))
    if (-not (Test-Path -LiteralPath $directorioLock -PathType Container)) {
        New-Item -ItemType Directory -Path $directorioLock -Force | Out-Null
    }
    try {
        return New-Object -TypeName System.IO.FileStream -ArgumentList @(
            $RutaLock,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
    } catch {
        throw ('Ya existe otra actualizacion en curso. No se modificaron artefactos. Lock: ' + $RutaLock)
    }
}

function Obtener-Sha256ArchivoNormalizado {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Ruta
    )

    return Obtener-Sha256TextoNormalizado -Texto ([System.IO.File]::ReadAllText($Ruta))
}

function Quitar-FilaVersionDocumento {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Texto
    )

    $etiquetaFilaVersion = 'Versi' + [char]0xF3 + 'n'
    $patronFilaVersion = '(?m)^[ \t]*\| ' + $etiquetaFilaVersion + ' \|[^\r\n]*\r?\n?'
    return [regex]::Replace($Texto, $patronFilaVersion, '')
}

function Establecer-PropiedadObjetoControl {
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

function Actualizar-VersionServicioUnaVez {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$VersionesActualizadas,
        [Parameter(Mandatory = $true)][string]$FullyQualifiedName,
        [Parameter(Mandatory = $true)]$ServicioObjetivo,
        [Parameter(Mandatory = $false)]$ServicioAnterior
    )

    if ($VersionesActualizadas.ContainsKey($FullyQualifiedName)) {
        throw ('El servicio ' + $FullyQualifiedName + ' intento actualizar su version mas de una vez en el mismo lote.')
    }
    $hashAnterior = if ($ServicioAnterior) { [string](Obtener-PropiedadControlVersiones -Objeto $ServicioAnterior -Nombre 'documentHash') } else { '' }
    $hashObjetivo = [string](Obtener-PropiedadControlVersiones -Objeto $ServicioObjetivo -Nombre 'documentHash')
    $documentoCambio = -not $ServicioAnterior -or $hashAnterior -ne $hashObjetivo
    $version = Obtener-VersionServicio -ServicioAnterior $ServicioAnterior -Incrementar:$documentoCambio
    Establecer-PropiedadObjetoControl -Objeto $ServicioObjetivo -Nombre 'revision' -Valor $version.Revision
    Establecer-PropiedadObjetoControl -Objeto $ServicioObjetivo -Nombre 'version' -Valor $version.Version
    Establecer-PropiedadObjetoControl -Objeto $ServicioObjetivo -Nombre 'status' -Valor 'ACTIVO'
    $VersionesActualizadas[$FullyQualifiedName] = $true
}

function Obtener-FingerprintPerfilDocumental {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackageName,
        [Parameter(Mandatory = $true)][string]$RaizRepositorio,
        [Parameter(Mandatory = $false)][string[]]$ServiciosIgnorados = @()
    )

    $rutasPerfil = @(
        'documentacion/analisisXPZ.md',
        'documentacion/reglasEditoriales.md',
        'documentacion/templateDoc.md',
        'binary/AnalizarServicio.ps1',
        'binary/RedactarDocumento.ps1',
        'binary/EscribirSalidas.ps1',
        'binary/CargarMultiXPZ.ps1'
    )
    $componentes = New-Object System.Collections.Generic.List[string]
    [void]$componentes.Add('packagename=' + $PackageName)
    [void]$componentes.Add('serviciosIgnorados=' + ((@($ServiciosIgnorados) | Sort-Object) -join ','))
    foreach ($rutaRelativa in $rutasPerfil) {
        $ruta = Join-Path $RaizRepositorio ($rutaRelativa -replace '/', '\')
        if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) {
            throw ('No se encontro un componente del perfil documental: ' + $rutaRelativa)
        }
        [void]$componentes.Add($rutaRelativa + '=' + (Obtener-Sha256ArchivoNormalizado -Ruta $ruta))
    }
    return Obtener-Sha256TextoNormalizado -Texto (($componentes -join "`n") + "`n")
}

function Test-ServiciosPublicadosVigentes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Servicios,
        [Parameter(Mandatory = $true)][string]$DirectorioServicios
    )

    $serviciosControl = Convertir-DiccionarioControlVersiones -Objeto $Servicios
    $fqnsInventario = @($serviciosControl.Keys | ForEach-Object { [string]$_ })
    foreach ($claveServicio in $serviciosControl.Keys) {
        $servicio = $serviciosControl[$claveServicio]
        if ([string](Obtener-PropiedadControlVersiones -Objeto $servicio -Nombre 'status') -ne 'ACTIVO') { continue }
        $nombreArchivo = Obtener-NombreArchivoServicio -FullyQualifiedName $claveServicio -FqnsInventario $fqnsInventario
        $rutaMarkdown = Join-Path $DirectorioServicios ($nombreArchivo + '.md')
        $rutaPdf = Join-Path $DirectorioServicios ($nombreArchivo + '.pdf')
        if (-not (Test-Path -LiteralPath $rutaMarkdown -PathType Leaf) -or -not (Test-PdfValidoParaPromocion -Ruta $rutaPdf)) { return $false }
        $hashDocumentoPublicado = Obtener-Sha256TextoNormalizado -Texto (Quitar-FilaVersionDocumento -Texto ([System.IO.File]::ReadAllText($rutaMarkdown)))
        if ($hashDocumentoPublicado -ne [string](Obtener-PropiedadControlVersiones -Objeto $servicio -Nombre 'documentHash')) { return $false }
        if ((Get-FileHash -LiteralPath $rutaPdf -Algorithm SHA256).Hash.ToLowerInvariant() -ne [string](Obtener-PropiedadControlVersiones -Objeto $servicio -Nombre 'pdfHash')) { return $false }
    }
    return $true
}

function Obtener-FingerprintFuente {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Manifiesto
    )

    $componentes = @($Manifiesto | Sort-Object Orden | ForEach-Object {
        '{0}|{1}|{2}' -f $_.Orden, $_.RutaRelativa, $_.Sha256
    })
    return Obtener-Sha256TextoNormalizado -Texto (($componentes -join "`n") + "`n")
}

function Obtener-LineageId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Indice
    )

    $objetoPrincipal = $null
    if ($Indice.PorFqn.ContainsKey('APIGLM.APIGLMMain')) {
        $objetoPrincipal = $Indice.PorFqn['APIGLM.APIGLMMain']
    }
    if (-not $objetoPrincipal) {
        throw 'El programa principal APIGLM.APIGLMMain no esta exportado en el XPZ configurado. No puede inferirse.'
    }
    $guid = [string]$objetoPrincipal.GetAttribute('guid')
    if ([string]::IsNullOrWhiteSpace($guid)) {
        throw 'APIGLM.APIGLMMain no contiene GUID. No puede determinarse el lineageId.'
    }
    return $guid
}

function Obtener-ObjetosModificadosSinVinculo {
    <#
    .SYNOPSIS
    Determina que objetos modificados no estan vinculados a ningun servicio del control.
    .DESCRIPTION
    Un objeto modificado esta vinculado si aparece en el indice inverso poblado con las
    dependencias registradas o si alguna dependencia registrada de un servicio lo referencia.
    Un objeto sin vinculo indica servicios cuyas dependencias nunca se registraron (por
    ejemplo, controles creados antes de la captura de traza o analisis fallidos) y exige
    una re-evaluacion dirigida para reconstruir la traza.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$ObjetosModificados,
        [Parameter(Mandatory = $true)]$IndiceInverso,
        [Parameter(Mandatory = $true)]$Servicios
    )

    $sinVinculo = New-Object System.Collections.Generic.List[string]
    foreach ($claveObjetoModificado in $ObjetosModificados) {
        $vinculado = $false
        if ($IndiceInverso.ContainsKey($claveObjetoModificado) -and @($IndiceInverso[$claveObjetoModificado]).Count -gt 0) {
            $vinculado = $true
        }
        if (-not $vinculado) {
            foreach ($fullyQualifiedName in $Servicios.Keys) {
                if ((Obtener-DependenciasServicioControlVersiones -Servicio $Servicios[$fullyQualifiedName]) -contains $claveObjetoModificado) {
                    $vinculado = $true
                    break
                }
            }
        }
        if (-not $vinculado -and -not $sinVinculo.Contains($claveObjetoModificado)) {
            [void]$sinVinculo.Add($claveObjetoModificado)
        }
    }
    return $sinVinculo.ToArray()
}

function Obtener-ServiciosActivosSinDependencias {
    <#
    .SYNOPSIS
    Devuelve los FQN de los servicios ACTIVO cuyas dependencias registradas estan vacias.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Servicios
    )

    $serviciosSinDependencias = New-Object System.Collections.Generic.List[string]
    foreach ($fullyQualifiedName in $Servicios.Keys) {
        $servicio = $Servicios[$fullyQualifiedName]
        if ([string](Obtener-PropiedadControlVersiones -Objeto $servicio -Nombre 'status') -ne 'ACTIVO') { continue }
        if ((Obtener-DependenciasServicioControlVersiones -Servicio $servicio).Count -eq 0) {
            [void]$serviciosSinDependencias.Add([string]$fullyQualifiedName)
        }
    }
    return $serviciosSinDependencias.ToArray()
}

function Invocar-PowerShellScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaScript,
        [Parameter(Mandatory = $true)][string[]]$Argumentos
    )

    $rutaPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $rutaPowerShell -PathType Leaf)) {
        throw ('No se encontro Windows PowerShell en: ' + $rutaPowerShell)
    }
    $salida = & $rutaPowerShell -NoProfile -ExecutionPolicy Bypass -File $RutaScript @Argumentos 2>&1
    return [pscustomobject]@{
        CodigoSalida = [int]$LASTEXITCODE
        Salida = @($salida | ForEach-Object { [string]$_ })
    }
}

function Seleccionar-XpzAlternativo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DirectorioXpz
    )

    $archivosPrincipales = @(Get-ChildItem -LiteralPath $DirectorioXpz -Filter '*.xpz' -File -ErrorAction SilentlyContinue | Where-Object {
        $nombreSinExtension = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        $coincidenciaComplemento = [regex]::Match($nombreSinExtension, '^(.*)_\d+$')
        if (-not $coincidenciaComplemento.Success) { return $true }
        $rutaPrincipalAsociada = Join-Path $DirectorioXpz ($coincidenciaComplemento.Groups[1].Value + '.xpz')
        return -not (Test-Path -LiteralPath $rutaPrincipalAsociada -PathType Leaf)
    } | Sort-Object LastWriteTime -Descending)
    if ($archivosPrincipales.Count -eq 0) {
        throw ('No hay XPZ principales disponibles en: ' + $DirectorioXpz)
    }

    Write-Host ''
    Write-Host 'No se pudo obtener un XPZ nuevo desde la Knowledge Base.' -ForegroundColor Yellow
    Write-Host 'Seleccione un XPZ principal existente para continuar o 0 para abortar:' -ForegroundColor Yellow
    for ($indiceArchivo = 0; $indiceArchivo -lt $archivosPrincipales.Count; $indiceArchivo++) {
        $archivo = $archivosPrincipales[$indiceArchivo]
        Write-Host ('  {0}. {1} | {2}' -f ($indiceArchivo + 1), $archivo.Name, $archivo.LastWriteTime.ToString('dd-MM-yyyy HH:mm'))
    }
    Write-Host '  0. Abortar'

    while ($true) {
        $textoSeleccion = Read-Host ('Seleccione una opcion [0-' + $archivosPrincipales.Count + ']')
        $seleccion = 0
        if (-not [int]::TryParse($textoSeleccion, [ref]$seleccion)) {
            Write-Host '  Seleccion invalida.' -ForegroundColor Yellow
            continue
        }
        if ($seleccion -eq 0) { return $null }
        if ($seleccion -ge 1 -and $seleccion -le $archivosPrincipales.Count) {
            return $archivosPrincipales[$seleccion - 1].FullName
        }
        Write-Host '  Seleccion invalida.' -ForegroundColor Yellow
    }
}

function Obtener-RegistroServicioActual {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FullyQualifiedName,
        [Parameter(Mandatory = $true)]$Indice,
        [Parameter(Mandatory = $true)]$Documentacion,
        [Parameter(Mandatory = $true)]$ServicioAnterior
    )

    $wrapper = $Indice.PorFqn[$FullyQualifiedName]
    $dependencias = New-Object System.Collections.ArrayList
    foreach ($claveDependencia in @($Documentacion.TrazaEvidencia.NodosConsultados | ForEach-Object { [string]$_.Clave } | Select-Object -Unique)) {
        [void]$dependencias.Add($claveDependencia)
    }
    $hashDocumento = Obtener-Sha256TextoNormalizado -Texto (Quitar-FilaVersionDocumento -Texto (Redactar-Documento -Documentacion $Documentacion))
    $versionAnterior = Obtener-VersionServicio -ServicioAnterior $ServicioAnterior
    return [ordered]@{
        wrapperGuid = [string]$wrapper.GetAttribute('guid')
        revision = $versionAnterior.Revision
        version = $versionAnterior.Version
        documentHash = $hashDocumento
        pdfHash = if ($ServicioAnterior) { [string](Obtener-PropiedadControlVersiones -Objeto $ServicioAnterior -Nombre 'pdfHash') } else { '' }
        dependencies = $dependencias
        status = 'ACTIVO'
    }
}

function Obtener-ResultadoReviewPorFqn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Review,
        [Parameter(Mandatory = $true)][string]$FullyQualifiedName
    )

    return @($Review.servicios | Where-Object { $_.fullyQualifiedName -eq $FullyQualifiedName }) | Select-Object -First 1
}

function Crear-PendienteControlVersiones {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$BaselineFingerprint,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$TargetFingerprint,
        [Parameter(Mandatory = $true)][string]$Reason,
        [Parameter(Mandatory = $false)]$PendienteAnterior,
        [Parameter(Mandatory = $false)][string]$LastError = ''
    )

    $intentosAnteriores = 0
    if ($PendienteAnterior) { $intentosAnteriores = [int](Obtener-PropiedadControlVersiones -Objeto $PendienteAnterior -Nombre 'attempts') }
    return [ordered]@{
        baselineFingerprint = $BaselineFingerprint
        targetFingerprint = $TargetFingerprint
        reason = $Reason
        attempts = $intentosAnteriores + 1
        lastError = $LastError
    }
}

function Test-PdfValidoParaPromocion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Ruta
    )

    if (-not (Test-Path -LiteralPath $Ruta -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $Ruta).Length -lt 5) { return $false }
    $flujo = [System.IO.File]::OpenRead($Ruta)
    try {
        $cabecera = New-Object byte[] 4
        [void]$flujo.Read($cabecera, 0, 4)
        return ([System.Text.Encoding]::ASCII.GetString($cabecera) -eq '%PDF')
    } finally {
        $flujo.Dispose()
    }
}

function Promover-ServicioArtefactos {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FullyQualifiedName,
        [Parameter(Mandatory = $true)][string]$RutaMarkdownStaging,
        [Parameter(Mandatory = $true)][string]$RutaPdfStaging,
        [Parameter(Mandatory = $true)][string]$DirectorioServicios,
        [Parameter(Mandatory = $false)][string[]]$FqnsInventario = @()
    )

    if (-not (Test-Path -LiteralPath $RutaMarkdownStaging -PathType Leaf)) {
        throw ('No existe el Markdown candidato del servicio: ' + $FullyQualifiedName)
    }
    if (-not (Test-PdfValidoParaPromocion -Ruta $RutaPdfStaging)) {
        throw ('No existe un PDF candidato valido del servicio: ' + $FullyQualifiedName)
    }
    if (-not (Test-Path -LiteralPath $DirectorioServicios -PathType Container)) {
        New-Item -ItemType Directory -Path $DirectorioServicios -Force | Out-Null
    }

    $nombreArchivo = Obtener-NombreArchivoServicio -FullyQualifiedName $FullyQualifiedName -FqnsInventario $FqnsInventario
    $operaciones = New-Object System.Collections.Generic.List[object]
    foreach ($artefacto in @(
        [pscustomobject]@{ Fuente = $RutaMarkdownStaging; Destino = (Join-Path $DirectorioServicios ($nombreArchivo + '.md')) },
        [pscustomobject]@{ Fuente = $RutaPdfStaging; Destino = (Join-Path $DirectorioServicios ($nombreArchivo + '.pdf')) }
    )) {
        $operacion = [pscustomobject]@{
            Fuente = $artefacto.Fuente
            Destino = $artefacto.Destino
            Temporal = $artefacto.Destino + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
            Respaldo = ''
            Existia = Test-Path -LiteralPath $artefacto.Destino -PathType Leaf
            Promocionado = $false
        }
        [void]$operaciones.Add($operacion)
    }

    try {
        foreach ($operacion in $operaciones) {
            [System.IO.File]::Copy($operacion.Fuente, $operacion.Temporal, $true)
            if ($operacion.Existia) {
                $operacion.Respaldo = $operacion.Destino + '.' + [guid]::NewGuid().ToString('N') + '.bak'
                [System.IO.File]::Replace($operacion.Temporal, $operacion.Destino, $operacion.Respaldo)
            } else {
                [System.IO.File]::Move($operacion.Temporal, $operacion.Destino)
            }
            $operacion.Promocionado = $true
        }

        $rutaMarkdownPublicado = Join-Path $DirectorioServicios ($nombreArchivo + '.md')
        $rutaPdfPublicado = Join-Path $DirectorioServicios ($nombreArchivo + '.pdf')
        return [pscustomobject]@{
            FullyQualifiedName = $FullyQualifiedName
            Markdown = $rutaMarkdownPublicado
            Pdf = $rutaPdfPublicado
            DocumentHash = Obtener-Sha256TextoNormalizado -Texto (Quitar-FilaVersionDocumento -Texto ([System.IO.File]::ReadAllText($rutaMarkdownPublicado)))
            PdfHash = (Get-FileHash -LiteralPath $rutaPdfPublicado -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    } catch {
        foreach ($operacion in @($operaciones | Where-Object { $_.Promocionado } | Sort-Object -Property Destino -Descending)) {
            try {
                if ($operacion.Existia) {
                    if (Test-Path -LiteralPath $operacion.Destino -PathType Leaf) {
                        Remove-Item -LiteralPath $operacion.Destino -Force
                    }
                    if ($operacion.Respaldo -and (Test-Path -LiteralPath $operacion.Respaldo -PathType Leaf)) {
                        Move-Item -LiteralPath $operacion.Respaldo -Destination $operacion.Destino -Force | Out-Null
                    }
                } elseif (Test-Path -LiteralPath $operacion.Destino -PathType Leaf) {
                    Remove-Item -LiteralPath $operacion.Destino -Force
                }
            } catch {
            }
        }
        throw
    } finally {
        foreach ($operacion in $operaciones) {
            if (Test-Path -LiteralPath $operacion.Temporal -PathType Leaf) {
                Remove-Item -LiteralPath $operacion.Temporal -Force -ErrorAction SilentlyContinue
            }
            if ($operacion.Respaldo -and (Test-Path -LiteralPath $operacion.Respaldo -PathType Leaf)) {
                Remove-Item -LiteralPath $operacion.Respaldo -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Marcar-ServicioSinPublicar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Servicio
    )

    Establecer-PropiedadObjetoControl -Objeto $Servicio -Nombre 'revision' -Valor 0
    Establecer-PropiedadObjetoControl -Objeto $Servicio -Nombre 'version' -Valor '1.0'
    Establecer-PropiedadObjetoControl -Objeto $Servicio -Nombre 'documentHash' -Valor ''
    Establecer-PropiedadObjetoControl -Objeto $Servicio -Nombre 'pdfHash' -Valor ''
    Establecer-PropiedadObjetoControl -Objeto $Servicio -Nombre 'status' -Valor 'ACTIVO'
    return $Servicio
}

try {
    $lockActualizacion = Adquirir-LockActualizacion -RutaLock $rutaLockActualizacion
    . (Join-Path $PSScriptRoot 'CargarConfiguracion.ps1')
    . (Join-Path $PSScriptRoot 'AnalizarServicio.ps1')
    . (Join-Path $PSScriptRoot 'CargarMultiXPZ.ps1')
    . (Join-Path $PSScriptRoot 'RedactarDocumento.ps1')
    . (Join-Path $PSScriptRoot 'ControlVersiones.ps1')
    . (Join-Path $PSScriptRoot 'ManifiestoEjecucion.ps1')

    if ($ManifiestoPath) {
        $manifiestoEjecucion = Leer-ManifiestoEjecucion -RutaManifiesto $ManifiestoPath
        $XpzPath = [string]$manifiestoEjecucion.xpz
    }

    $parametrosConfiguracion = @{ ConfigPath = $ConfigPath }
    if ($XpzPath) { $parametrosConfiguracion.XpzPath = $XpzPath }
    $configuracion = Cargar-Configuracion @parametrosConfiguracion
    try {
        $controlAnterior = Leer-ControlVersiones -RutaControl $RutaControl
    } catch {
        if (-not $Inicializar) {
            throw ('El control de versiones es incompatible o invalido. Se requiere inicializacion explicita con -Inicializar. Motivo: ' + $_.Exception.Message)
        }
        Write-Host ('Control de versiones incompatible; se inicializara explicitamente. Motivo: ' + $_.Exception.Message) -ForegroundColor Yellow
        $controlAnterior = $null
    }
    if ($Inicializar) { $controlAnterior = $null }

    $rutaConfiguracionRaiz = [System.IO.Path]::GetFullPath((Join-Path $raizRepositorio 'configuracion.json'))
    $rutaConfiguracionSolicitada = [System.IO.Path]::GetFullPath($ConfigPath)
    $exportacionAutomatica = -not $XpzPath -and [System.StringComparer]::OrdinalIgnoreCase.Equals($rutaConfiguracionRaiz, $rutaConfiguracionSolicitada)
    if ($exportacionAutomatica) {
        Write-Host 'Actualizacion: exportando un XPZ nuevo desde la Knowledge Base...' -ForegroundColor Cyan
        $rutaExportador = Join-Path $PSScriptRoot 'EjecutarExportacionGLM.ps1'
        $rutaXpzAlternativa = $null
        try {
            $resultadoExportacion = Invocar-PowerShellScript -RutaScript $rutaExportador -Argumentos @('-Repositorio', $raizRepositorio)
            foreach ($lineaExportacion in $resultadoExportacion.Salida) {
                if ($lineaExportacion) { Write-Host $lineaExportacion }
            }
            if ($resultadoExportacion.CodigoSalida -eq 3) {
                exit 3
            }
            if ($resultadoExportacion.CodigoSalida -eq 2) {
                exit 2
            }
            if ($resultadoExportacion.CodigoSalida -ne 0) {
                throw 'La exportacion automatica del XPZ fallo.'
            }
        } catch {
            Write-Host ('  Motivo: ' + $_.Exception.Message) -ForegroundColor Yellow
            $rutaXpzAlternativa = Seleccionar-XpzAlternativo -DirectorioXpz (Join-Path $raizRepositorio 'xpz')
            if (-not $rutaXpzAlternativa) {
                exit 3
            }
            $XpzPath = $rutaXpzAlternativa
            $parametrosConfiguracion.XpzPath = $XpzPath
            $configuracion = Cargar-Configuracion @parametrosConfiguracion
            $rutaInventarioAlternativo = Join-Path $raizRepositorio 'documentacion\Endpoints\binary\GenerarListaEndpoints.ps1'
            $resultadoInventarioAlternativo = Invocar-PowerShellScript -RutaScript $rutaInventarioAlternativo -Argumentos @('-ConfigPath', $ConfigPath, '-XpzPath', $XpzPath)
            if ($resultadoInventarioAlternativo.CodigoSalida -eq 3) { exit 3 }
            if ($resultadoInventarioAlternativo.CodigoSalida -eq 2) { exit 2 }
            if ($resultadoInventarioAlternativo.CodigoSalida -ne 0) {
                throw 'No se pudo regenerar el inventario para el XPZ seleccionado.'
            }
        }
        if (-not $rutaXpzAlternativa) {
            $configuracion = Cargar-Configuracion -ConfigPath $ConfigPath
        }
    }

    $rutaInventario = Join-Path $raizRepositorio 'documentacion\Endpoints\assets\endpoints.json'
    if (-not (Test-Path -LiteralPath $rutaInventario -PathType Leaf)) {
        throw ('No se encontro el inventario en: ' + $rutaInventario)
    }
    $inventario = [System.IO.File]::ReadAllText($rutaInventario) | ConvertFrom-Json
    $serviciosInventarioTotal = @($inventario.endpoints)
    $serviciosInventario = @($serviciosInventarioTotal | Where-Object { $_.proceso -notin @($configuracion.ServiciosIgnorados) })
    if ($serviciosInventarioTotal.Count -eq 0) { throw 'El inventario no contiene servicios.' }
    $nombresInventario = @($serviciosInventarioTotal | ForEach-Object { [string]$_.proceso })

    $rutasXpz = @($configuracion.XpzPath) + @(Descubrir-XPZComplementariosCompartido -RutaXpzPrincipal $configuracion.XpzPath)
    $manifiestoActual = @(Construir-ManifiestoMultiXPZ -RutasXpz $rutasXpz)
    $sourceFingerprint = Obtener-FingerprintFuente -Manifiesto $manifiestoActual
    $profileFingerprint = Obtener-FingerprintPerfilDocumental -PackageName $configuracion.PackageName -RaizRepositorio $raizRepositorio -ServiciosIgnorados $configuracion.ServiciosIgnorados
    $pendientesAnteriores = @{}
    if ($controlAnterior) {
        $pendientesAnteriores = Convertir-DiccionarioControlVersiones -Objeto $controlAnterior.pendientes
        $sourceFingerprintAnterior = [string](Obtener-PropiedadControlVersiones -Objeto $controlAnterior -Nombre 'sourceFingerprint')
        $profileFingerprintAnterior = [string](Obtener-PropiedadControlVersiones -Objeto $controlAnterior -Nombre 'profileFingerprint')
        $serviciosAnterioresFastPath = Obtener-PropiedadControlVersiones -Objeto $controlAnterior -Nombre 'services'
        $artefactosVigentes = Test-ServiciosPublicadosVigentes -Servicios $serviciosAnterioresFastPath -DirectorioServicios (Join-Path $raizRepositorio 'documentacion\servicios')
        if (-not $ForzarRegeneracionCompleta -and $sourceFingerprintAnterior -eq $sourceFingerprint -and $profileFingerprintAnterior -eq $profileFingerprint -and $pendientesAnteriores.Count -eq 0 -and $artefactosVigentes) {
            Write-Host 'Fast-path: no cambiaron el conjunto XPZ ni el perfil documental y no hay pendientes.' -ForegroundColor DarkGray
            exit 0
        }
    }

    $indice = Cargar-IndiceMultiXPZ -RutaXpzPrincipal $configuracion.XpzPath
    Write-Host 'Regeneracion en proceso... aguarde.' -ForegroundColor Cyan
    $lineageId = Obtener-LineageId -Indice $indice

    $serviciosAnteriores = @{}
    if ($controlAnterior) {
        $serviciosAnteriores = Convertir-DiccionarioControlVersiones -Objeto $controlAnterior.services
        $pendientesAnteriores = Convertir-DiccionarioControlVersiones -Objeto $controlAnterior.pendientes
    }

    $objetosActuales = @{}
    foreach ($objetoEfectivo in $indice.ObjetosEfectivos.GetEnumerator()) {
        $objetosActuales[$objetoEfectivo.Key] = $objetoEfectivo.Value.Checksum
    }
    $serviciosPreliminares = @{}
    foreach ($servicioInventario in $serviciosInventario) {
        $fullyQualifiedName = [string]$servicioInventario.proceso
        if ($serviciosAnteriores.ContainsKey($fullyQualifiedName)) {
            $serviciosPreliminares[$fullyQualifiedName] = $serviciosAnteriores[$fullyQualifiedName]
        } else {
            $serviciosPreliminares[$fullyQualifiedName] = [ordered]@{
                wrapperGuid = ''
                revision = 0
                version = '1.0'
                documentHash = ''
                pdfHash = ''
                dependencies = (New-Object System.Collections.ArrayList)
                status = 'ACTIVO'
            }
        }
    }
    foreach ($servicioIgnorado in @($serviciosInventarioTotal | Where-Object { $_.proceso -in @($configuracion.ServiciosIgnorados) })) {
        $fullyQualifiedName = [string]$servicioIgnorado.proceso
        if ($serviciosAnteriores.ContainsKey($fullyQualifiedName)) {
            $servicioIgnoradoAnterior = $serviciosAnteriores[$fullyQualifiedName]
            Establecer-PropiedadObjetoControl -Objeto $servicioIgnoradoAnterior -Nombre 'status' -Valor 'OMITIDO'
            $serviciosPreliminares[$fullyQualifiedName] = $servicioIgnoradoAnterior
        } else {
            $serviciosPreliminares[$fullyQualifiedName] = [ordered]@{
                wrapperGuid = if ($indice.PorFqn.ContainsKey($fullyQualifiedName)) { [string]$indice.PorFqn[$fullyQualifiedName].GetAttribute('guid') } else { '' }
                revision = 0
                version = '1.0'
                documentHash = ''
                pdfHash = ''
                dependencies = (New-Object System.Collections.ArrayList)
                status = 'OMITIDO'
            }
        }
    }
    $controlObjetivoPreliminar = New-ControlVersiones -LineageId $lineageId -SourceFingerprint $sourceFingerprint -ProfileFingerprint $profileFingerprint -Objects $objetosActuales -Services $serviciosPreliminares -Pendientes @{}
    $comparacionPreliminar = Comparar-ControlVersiones -ControlAnterior $controlAnterior -ControlObjetivo $controlObjetivoPreliminar
    if ($comparacionPreliminar.BloqueadoPorLineage) { throw $comparacionPreliminar.MotivoBloqueo }

    foreach ($fullyQualifiedName in $serviciosAnteriores.Keys) {
        foreach ($claveDependencia in (Obtener-DependenciasServicioControlVersiones -Servicio $serviciosAnteriores[$fullyQualifiedName])) {
            if ($indice.IndiceInverso.ContainsKey($claveDependencia) -and -not $indice.IndiceInverso[$claveDependencia].Contains($fullyQualifiedName)) {
                [void]$indice.IndiceInverso[$claveDependencia].Add($fullyQualifiedName)
            }
        }
    }
    $nombresCandidatos = New-Object System.Collections.Generic.List[string]
    foreach ($claveObjetoModificado in $comparacionPreliminar.ObjetosModificados) {
        if ($indice.IndiceInverso.ContainsKey($claveObjetoModificado)) {
            foreach ($fullyQualifiedName in @($indice.IndiceInverso[$claveObjetoModificado])) {
                if (-not $nombresCandidatos.Contains($fullyQualifiedName)) { [void]$nombresCandidatos.Add($fullyQualifiedName) }
            }
        }
        foreach ($fullyQualifiedName in $serviciosAnteriores.Keys) {
            if ((Obtener-DependenciasServicioControlVersiones -Servicio $serviciosAnteriores[$fullyQualifiedName]) -contains $claveObjetoModificado -and -not $nombresCandidatos.Contains($fullyQualifiedName)) {
                [void]$nombresCandidatos.Add($fullyQualifiedName)
            }
        }
    }
    foreach ($fullyQualifiedName in $comparacionPreliminar.ServiciosNuevos) { if (-not $nombresCandidatos.Contains($fullyQualifiedName)) { [void]$nombresCandidatos.Add($fullyQualifiedName) } }
    foreach ($fullyQualifiedName in $comparacionPreliminar.Pendientes) { if (-not $nombresCandidatos.Contains($fullyQualifiedName)) { [void]$nombresCandidatos.Add($fullyQualifiedName) } }
    foreach ($fullyQualifiedName in $comparacionPreliminar.ServiciosAfectados) { if (-not $nombresCandidatos.Contains($fullyQualifiedName)) { [void]$nombresCandidatos.Add($fullyQualifiedName) } }
    $objetosModificadosSinVinculo = @(Obtener-ObjetosModificadosSinVinculo -ObjetosModificados $comparacionPreliminar.ObjetosModificados -IndiceInverso $indice.IndiceInverso -Servicios $serviciosAnteriores)
    if ($objetosModificadosSinVinculo.Count -gt 0) {
        $serviciosSinDependencias = @(Obtener-ServiciosActivosSinDependencias -Servicios $serviciosAnteriores)
        foreach ($fullyQualifiedName in $serviciosSinDependencias) {
            if (-not $nombresCandidatos.Contains($fullyQualifiedName)) { [void]$nombresCandidatos.Add($fullyQualifiedName) }
        }
        Write-Host ('Objetos modificados sin vinculo de dependencias (' + $objetosModificadosSinVinculo.Count + '): se reanalizan ' + $serviciosSinDependencias.Count + ' servicio(s) ACTIVO sin dependencias registradas para reconstruir la traza.') -ForegroundColor Yellow
    }
    foreach ($servicioInventario in $serviciosInventario) {
        $fullyQualifiedName = [string]$servicioInventario.proceso
        if ($serviciosAnteriores.ContainsKey($fullyQualifiedName) -and [string](Obtener-PropiedadControlVersiones -Objeto $serviciosAnteriores[$fullyQualifiedName] -Nombre 'status') -ne 'ACTIVO' -and -not $nombresCandidatos.Contains($fullyQualifiedName)) {
            [void]$nombresCandidatos.Add($fullyQualifiedName)
        }
    }
    if ($ForzarRegeneracionCompleta) {
        foreach ($servicioInventario in $serviciosInventario) {
            $nombreServicio = [string]$servicioInventario.proceso
            if (-not $nombresCandidatos.Contains($nombreServicio)) { [void]$nombresCandidatos.Add($nombreServicio) }
        }
        Write-Host 'Regeneracion completa solicitada: se procesaran todos los servicios del inventario.' -ForegroundColor Yellow
        Write-Host ('Generando documentacion Markdown (.md): ' + $nombresCandidatos.Count + ' servicio(s). Aguarde...') -ForegroundColor Cyan
    }

    if ($ManifiestoPath) {
        $nombresManifiesto = @($manifiestoEjecucion.fullyQualifiedNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
        if ($nombresManifiesto.Count -gt 0) {
            $nombresCandidatos = New-Object System.Collections.Generic.List[string]
            foreach ($fullyQualifiedName in $nombresManifiesto) {
                if (-not $nombresCandidatos.Contains([string]$fullyQualifiedName)) {
                    [void]$nombresCandidatos.Add([string]$fullyQualifiedName)
                }
            }
        }
        $rutaManifiestoEjecucion = [System.IO.Path]::GetFullPath($ManifiestoPath)
        $datosManifiestoEjecucion = $manifiestoEjecucion
    }

    $serviciosActuales = @{}
    $analisisActuales = @{}
    foreach ($servicioInventario in $serviciosInventario) {
        $fullyQualifiedName = [string]$servicioInventario.proceso
        $servicioAnterior = if ($serviciosAnteriores.ContainsKey($fullyQualifiedName)) { $serviciosAnteriores[$fullyQualifiedName] } else { $null }
        if (-not $nombresCandidatos.Contains($fullyQualifiedName)) {
            $serviciosActuales[$fullyQualifiedName] = $servicioAnterior
            $analisisActuales[$fullyQualifiedName] = [pscustomobject]@{ Documentacion = $null; Documento = ''; Error = '' }
            continue
        }
        try {
            $documentacion = Analizar-Servicio -Xml $indice.XmlUnificado -NombreCompletoWrapper $fullyQualifiedName -PackageName $configuracion.PackageName -Indice $indice -IncluirTrazaEvidencia
            $documento = Redactar-Documento -Documentacion $documentacion
            $registroServicio = Obtener-RegistroServicioActual -FullyQualifiedName $fullyQualifiedName -Indice $indice -Documentacion $documentacion -ServicioAnterior $servicioAnterior
            $serviciosActuales[$fullyQualifiedName] = $registroServicio
            $analisisActuales[$fullyQualifiedName] = [pscustomobject]@{ Documentacion = $documentacion; Documento = $documento; Error = '' }
        } catch {
            $dependenciasAnteriores = New-Object System.Collections.ArrayList
            if ($servicioAnterior) {
                foreach ($claveDependencia in (Obtener-DependenciasServicioControlVersiones -Servicio $servicioAnterior)) {
                    [void]$dependenciasAnteriores.Add($claveDependencia)
                }
            }
            $serviciosActuales[$fullyQualifiedName] = [ordered]@{
                wrapperGuid = if ($servicioAnterior) { [string](Obtener-PropiedadControlVersiones -Objeto $servicioAnterior -Nombre 'wrapperGuid') } else { [string]$indice.PorFqn[$fullyQualifiedName].GetAttribute('guid') }
                revision = if ($servicioAnterior) { [int](Obtener-PropiedadControlVersiones -Objeto $servicioAnterior -Nombre 'revision') } else { 0 }
                version = if ($servicioAnterior) { [string](Obtener-PropiedadControlVersiones -Objeto $servicioAnterior -Nombre 'version') } else { '1.0' }
                documentHash = if ($servicioAnterior) { [string](Obtener-PropiedadControlVersiones -Objeto $servicioAnterior -Nombre 'documentHash') } else { '' }
                pdfHash = if ($servicioAnterior) { [string](Obtener-PropiedadControlVersiones -Objeto $servicioAnterior -Nombre 'pdfHash') } else { '' }
                dependencies = $dependenciasAnteriores
                status = 'ACTIVO'
            }
            $analisisActuales[$fullyQualifiedName] = [pscustomobject]@{ Documentacion = $null; Documento = ''; Error = $_.Exception.Message }
        }
    }
    foreach ($servicioIgnorado in @($serviciosInventarioTotal | Where-Object { $_.proceso -in @($configuracion.ServiciosIgnorados) })) {
        $fullyQualifiedName = [string]$servicioIgnorado.proceso
        $serviciosActuales[$fullyQualifiedName] = $serviciosPreliminares[$fullyQualifiedName]
        $analisisActuales[$fullyQualifiedName] = [pscustomobject]@{ Documentacion = $null; Documento = ''; Error = '' }
    }

    $controlObjetivo = New-ControlVersiones -LineageId $lineageId -SourceFingerprint $sourceFingerprint -ProfileFingerprint $profileFingerprint -Objects @{} -Services $serviciosActuales -Pendientes @{}
    foreach ($objetoEfectivo in $indice.ObjetosEfectivos.GetEnumerator()) {
        $controlObjetivo['objects'][$objetoEfectivo.Key] = $objetoEfectivo.Value.Checksum
    }
    $comparacion = Comparar-ControlVersiones -ControlAnterior $controlAnterior -ControlObjetivo $controlObjetivo
    if ($comparacion.BloqueadoPorLineage) {
        throw $comparacion.MotivoBloqueo
    }

    $nombresParaRegenerar = New-Object System.Collections.Generic.List[string]
    foreach ($fullyQualifiedName in $nombresCandidatos) {
        $servicioAnterior = if ($serviciosAnteriores.ContainsKey($fullyQualifiedName)) { $serviciosAnteriores[$fullyQualifiedName] } else { $null }
        $analisis = $analisisActuales[$fullyQualifiedName]
        $hashAnterior = if ($servicioAnterior) { [string](Obtener-PropiedadControlVersiones -Objeto $servicioAnterior -Nombre 'documentHash') } else { '' }
        $hashActual = [string](Obtener-PropiedadControlVersiones -Objeto $serviciosActuales[$fullyQualifiedName] -Nombre 'documentHash')
        $hayPendiente = $pendientesAnteriores.ContainsKey($fullyQualifiedName)
        if ($ForzarRegeneracionCompleta -or $comparacion.ProfileFingerprintCambio -or $analisis.Error -or -not $servicioAnterior -or $hayPendiente -or $hashAnterior -ne $hashActual) {
            [void]$nombresParaRegenerar.Add($fullyQualifiedName)
        }
    }

    if ($ManifiestoPath) {
        if ($nombresManifiesto.Count -eq 0) {
            Establecer-FullyQualifiedNamesManifiesto -RutaManifiesto $rutaManifiestoEjecucion -FullyQualifiedNames @($nombresParaRegenerar.ToArray()) | Out-Null
            $manifiestoEjecucion = Leer-ManifiestoEjecucion -RutaManifiesto $rutaManifiestoEjecucion
            $datosManifiestoEjecucion = $manifiestoEjecucion
        }
    } else {
        $xpzParaManifiesto = if ($XpzPath) { $XpzPath } else { [string]$configuracion.XpzPath }
        $manifiestoEjecucion = Crear-ManifiestoEjecucion -Xpz $xpzParaManifiesto -FullyQualifiedNames @($nombresParaRegenerar.ToArray())
        $rutaManifiestoEjecucion = $manifiestoEjecucion.Ruta
        $datosManifiestoEjecucion = $manifiestoEjecucion.Datos
    }

    $versionesObjetivo = @{}
    foreach ($fullyQualifiedName in $nombresParaRegenerar) {
        $servicioAnterior = if ($serviciosAnteriores.ContainsKey($fullyQualifiedName)) { $serviciosAnteriores[$fullyQualifiedName] } else { $null }
        $hashAnterior = if ($servicioAnterior) { [string](Obtener-PropiedadControlVersiones -Objeto $servicioAnterior -Nombre 'documentHash') } else { '' }
        $hashActual = [string](Obtener-PropiedadControlVersiones -Objeto $serviciosActuales[$fullyQualifiedName] -Nombre 'documentHash')
        $documentoCambio = -not $servicioAnterior -or $hashAnterior -ne $hashActual
        $versionObjetivo = Obtener-VersionServicio -ServicioAnterior $servicioAnterior -Incrementar:$documentoCambio
        $versionesObjetivo[$fullyQualifiedName] = $versionObjetivo.Version
    }
    Establecer-VersionesManifiesto -RutaManifiesto $rutaManifiestoEjecucion -Versiones $versionesObjetivo | Out-Null

    $directorioLogs = Join-Path $raizRepositorio 'Logs'
    if (-not (Test-Path -LiteralPath $directorioLogs -PathType Container)) { New-Item -ItemType Directory -Path $directorioLogs -Force | Out-Null }
    $marcaTemporal = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $rutaReviewGeneracion = Join-Path $directorioLogs ($datosManifiestoEjecucion.ejecucionId + '-actualizacion-review.json')
    $rutaGenerador = Join-Path $PSScriptRoot 'GenerarDocumento.ps1'
    $resultadoGeneracion = $null
    $erroresGeneracion = @{}
    $codigoSalidaOperacion = 0
    if ($nombresParaRegenerar.Count -gt 0) {
        if (-not $ForzarRegeneracionCompleta) {
            Write-Host ('Generando documentacion Markdown (.md): ' + $nombresParaRegenerar.Count + ' servicio(s). Aguarde...') -ForegroundColor Cyan
        }
        $argumentosGenerador = @('-ConfigPath', $ConfigPath, '-ManifiestoPath', $rutaManifiestoEjecucion, '-NoInteractivo', '-RutaReview', $rutaReviewGeneracion)
        if ($XpzPath) { $argumentosGenerador += @('-XpzPath', $XpzPath) }
        try {
            $resultadoGeneracion = Invocar-PowerShellScript -RutaScript $rutaGenerador -Argumentos $argumentosGenerador
            if ($resultadoGeneracion.CodigoSalida -eq 3) { exit 3 }
        } catch {
            foreach ($fullyQualifiedName in $nombresParaRegenerar) { $erroresGeneracion[$fullyQualifiedName] = $_.Exception.Message }
        }
        if (-not (Test-Path -LiteralPath $rutaReviewGeneracion -PathType Leaf)) {
            $mensajeGeneracion = if ($erroresGeneracion.Count -gt 0) { ($erroresGeneracion.Values -join '; ') } else { 'El generador no produjo el review esperado de la actualizacion.' }
            foreach ($fullyQualifiedName in $nombresParaRegenerar) { $erroresGeneracion[$fullyQualifiedName] = $mensajeGeneracion }
            if ($resultadoGeneracion -and $resultadoGeneracion.CodigoSalida -eq 2) {
                $codigoSalidaOperacion = 2
            } else {
                $codigoSalidaOperacion = 1
            }
        } elseif ($resultadoGeneracion -and $resultadoGeneracion.CodigoSalida -eq 2) {
            $codigoSalidaOperacion = 2
        }
    }

    $reviewGeneracion = if ($resultadoGeneracion) { [System.IO.File]::ReadAllText($rutaReviewGeneracion) | ConvertFrom-Json } else { $null }
    $rutasMarkdown = New-Object System.Collections.Generic.List[string]
    $nombresParaPdf = New-Object System.Collections.Generic.List[string]
    $pendientesObjetivo = @{}
    $versionesActualizadas = @{}
    $promocionesExitosas = @{}
    $erroresPublicacion = @{}
    $serviciosObjetivo = Convertir-DiccionarioControlVersiones -Objeto $controlObjetivo['services']
    foreach ($fullyQualifiedName in $serviciosActuales.Keys) {
        $servicioAnterior = if ($serviciosAnteriores.ContainsKey($fullyQualifiedName)) { $serviciosAnteriores[$fullyQualifiedName] } else { $null }
        $analisis = $analisisActuales[$fullyQualifiedName]
        if (-not $nombresParaRegenerar.Contains($fullyQualifiedName) -and -not $analisis.Error) { continue }
        $resultadoReview = if ($reviewGeneracion) { Obtener-ResultadoReviewPorFqn -Review $reviewGeneracion -FullyQualifiedName $fullyQualifiedName } else { $null }
        $documentoEscrito = $resultadoReview -and $resultadoReview.documento -and $resultadoReview.estado -in @('OK', 'WARNING')
        if ($documentoEscrito) {
            [void]$rutasMarkdown.Add([string]$resultadoReview.documento)
            [void]$nombresParaPdf.Add($fullyQualifiedName)
            if ($resultadoReview.estado -eq 'WARNING' -and $codigoSalidaOperacion -eq 0) {
                $codigoSalidaOperacion = 2
            }
        } else {
            $mensajeError = if ($analisis.Error) { $analisis.Error } elseif ($erroresGeneracion.ContainsKey($fullyQualifiedName)) { $erroresGeneracion[$fullyQualifiedName] } elseif ($resultadoReview) { (@($resultadoReview.mensajes) -join '; ') } else { 'No se genero el documento.' }
            $pendienteAnterior = if ($pendientesAnteriores.ContainsKey($fullyQualifiedName)) { $pendientesAnteriores[$fullyQualifiedName] } else { $null }
            $baselineFingerprint = $(if ($servicioAnterior) { [string](Obtener-PropiedadControlVersiones -Objeto $servicioAnterior -Nombre 'documentHash') } else { '' })
            $pendientesObjetivo[$fullyQualifiedName] = Crear-PendienteControlVersiones -BaselineFingerprint $baselineFingerprint -TargetFingerprint ([string](Obtener-PropiedadControlVersiones -Objeto $serviciosActuales[$fullyQualifiedName] -Nombre 'documentHash')) -Reason 'GENERATION_ERROR' -PendienteAnterior $pendienteAnterior -LastError $mensajeError
            if ($servicioAnterior) {
                $serviciosObjetivo[$fullyQualifiedName] = $servicioAnterior
            } else {
                $serviciosObjetivo[$fullyQualifiedName] = Marcar-ServicioSinPublicar -Servicio $serviciosObjetivo[$fullyQualifiedName]
            }
            if ($codigoSalidaOperacion -eq 0) { $codigoSalidaOperacion = 2 }
        }
    }

    foreach ($fullyQualifiedName in $comparacion.ServiciosEliminados) {
        if ($serviciosAnteriores.ContainsKey($fullyQualifiedName)) {
            $servicioEliminado = $serviciosAnteriores[$fullyQualifiedName]
            $estadoEliminado = if ($configuracion.ServiciosIgnorados -contains $fullyQualifiedName) { 'OMITIDO' } else { 'ELIMINADO' }
            Establecer-PropiedadObjetoControl -Objeto $servicioEliminado -Nombre 'status' -Valor $estadoEliminado
            $serviciosObjetivo[$fullyQualifiedName] = $servicioEliminado
        }
    }
    $controlObjetivo['services'] = $serviciosObjetivo
    $controlObjetivo['pendientes'] = $pendientesObjetivo

    if ($rutasMarkdown.Count -gt 0) {
        Write-Host ('Generando documentos PDF: ' + $nombresParaPdf.Count + ' archivo(s). Aguarde...') -ForegroundColor Cyan
        $rutaGeneradorPdf = Join-Path $PSScriptRoot 'GenerarPdfServicios.ps1'
        try {
            Establecer-FullyQualifiedNamesManifiesto -RutaManifiesto $rutaManifiestoEjecucion -FullyQualifiedNames @($nombresParaPdf.ToArray()) | Out-Null
            $resultadoPdf = Invocar-PowerShellScript -RutaScript $rutaGeneradorPdf -Argumentos @('-ConfigPath', $ConfigPath, '-ManifiestoPath', $rutaManifiestoEjecucion, '-NoInteractivo')
            if ($resultadoPdf.CodigoSalida -eq 3) { exit 3 }
            if ($resultadoPdf.CodigoSalida -ne 0) {
                Write-Host '  [WARNING] Fallo la regeneracion de uno o mas PDF; se conservaron los PDF vigentes.' -ForegroundColor Yellow
                if ($codigoSalidaOperacion -eq 0) { $codigoSalidaOperacion = 2 }
            }
        } catch {
            Write-Host ('  [WARNING] No se pudo iniciar la regeneracion PDF: ' + $_.Exception.Message) -ForegroundColor Yellow
            if ($codigoSalidaOperacion -eq 0) { $codigoSalidaOperacion = 1 }
        }
    }

    $directorioServiciosProductivo = Join-Path $raizRepositorio 'documentacion\servicios'
    if ($nombresParaPdf.Count -gt 0) {
        Write-Host 'Validando y publicando Markdown y PDF... aguarde.' -ForegroundColor Cyan
    }
    foreach ($fullyQualifiedName in @($nombresParaPdf.ToArray())) {
        $nombreArchivo = Obtener-NombreArchivoServicio -FullyQualifiedName $fullyQualifiedName -FqnsInventario $nombresInventario
        $rutaMarkdownStaging = Join-Path ([string]$datosManifiestoEjecucion.staging) ('markdown\' + $nombreArchivo + '.md')
        $rutaPdfStaging = Join-Path ([string]$datosManifiestoEjecucion.staging) ('pdf\' + $nombreArchivo + '.pdf')
        $servicioAnterior = if ($serviciosAnteriores.ContainsKey($fullyQualifiedName)) { $serviciosAnteriores[$fullyQualifiedName] } else { $null }
        try {
            $promocion = Promover-ServicioArtefactos -FullyQualifiedName $fullyQualifiedName -RutaMarkdownStaging $rutaMarkdownStaging -RutaPdfStaging $rutaPdfStaging -DirectorioServicios $directorioServiciosProductivo -FqnsInventario $nombresInventario
            $servicioObjetivo = $serviciosObjetivo[$fullyQualifiedName]
            Establecer-PropiedadObjetoControl -Objeto $servicioObjetivo -Nombre 'documentHash' -Valor $promocion.DocumentHash
            Establecer-PropiedadObjetoControl -Objeto $servicioObjetivo -Nombre 'pdfHash' -Valor $promocion.PdfHash
            Actualizar-VersionServicioUnaVez -VersionesActualizadas $versionesActualizadas -FullyQualifiedName $fullyQualifiedName -ServicioObjetivo $servicioObjetivo -ServicioAnterior $servicioAnterior
            $serviciosObjetivo[$fullyQualifiedName] = $servicioObjetivo
            $promocionesExitosas[$fullyQualifiedName] = $promocion
            Write-Host ('  [PUBLICADO] ' + $fullyQualifiedName + ' | Markdown y PDF validados.') -ForegroundColor Green
        } catch {
            $mensajeError = $_.Exception.Message
            $erroresPublicacion[$fullyQualifiedName] = $mensajeError
            $pendienteAnterior = if ($pendientesAnteriores.ContainsKey($fullyQualifiedName)) { $pendientesAnteriores[$fullyQualifiedName] } else { $null }
            $baselineFingerprint = $(if ($servicioAnterior) { [string](Obtener-PropiedadControlVersiones -Objeto $servicioAnterior -Nombre 'documentHash') } else { '' })
            $pendientesObjetivo[$fullyQualifiedName] = Crear-PendienteControlVersiones -BaselineFingerprint $baselineFingerprint -TargetFingerprint ([string](Obtener-PropiedadControlVersiones -Objeto $serviciosActuales[$fullyQualifiedName] -Nombre 'documentHash')) -Reason 'PUBLICATION_ERROR' -PendienteAnterior $pendienteAnterior -LastError $mensajeError
            if ($servicioAnterior) {
                $serviciosObjetivo[$fullyQualifiedName] = $servicioAnterior
            } else {
                $serviciosObjetivo[$fullyQualifiedName] = Marcar-ServicioSinPublicar -Servicio $serviciosObjetivo[$fullyQualifiedName]
            }
            if ($codigoSalidaOperacion -eq 0) { $codigoSalidaOperacion = 2 }
            Write-Host ('  [CONSERVADO] ' + $fullyQualifiedName + ' | ' + $mensajeError) -ForegroundColor Yellow
        }
    }

    $controlObjetivo['services'] = $serviciosObjetivo
    $controlObjetivo['pendientes'] = $pendientesObjetivo

    $serviciosReviewFinal = New-Object System.Collections.Generic.List[object]
    foreach ($fullyQualifiedName in ($serviciosObjetivo.Keys | Sort-Object)) {
        $servicioObjetivo = $serviciosObjetivo[$fullyQualifiedName]
        $servicioAnterior = if ($serviciosAnteriores.ContainsKey($fullyQualifiedName)) { $serviciosAnteriores[$fullyQualifiedName] } else { $null }
        $estadoControl = [string](Obtener-PropiedadControlVersiones -Objeto $servicioObjetivo -Nombre 'status')
        $nombreArchivo = Obtener-NombreArchivoServicio -FullyQualifiedName $fullyQualifiedName -FqnsInventario $nombresInventario
        $rutaMarkdownPublicado = Join-Path $directorioServiciosProductivo ($nombreArchivo + '.md')
        $rutaPdfPublicado = Join-Path $directorioServiciosProductivo ($nombreArchivo + '.pdf')
        $estaPublicado = (Test-Path -LiteralPath $rutaMarkdownPublicado -PathType Leaf) -and (Test-PdfValidoParaPromocion -Ruta $rutaPdfPublicado)
        $estadoMarkdown = 'NO_APLICA'
        $estadoPdf = 'NO_APLICA'
        $promocionado = $false
        $mensajesReview = New-Object System.Collections.Generic.List[string]

        if ($estadoControl -eq 'ACTIVO') {
            if ($promocionesExitosas.ContainsKey($fullyQualifiedName)) {
                $estadoMarkdown = 'OK'
                $estadoPdf = 'OK'
                $promocionado = $true
            } elseif ($nombresParaRegenerar.Contains($fullyQualifiedName)) {
                $analisis = $analisisActuales[$fullyQualifiedName]
                $resultadoReview = if ($reviewGeneracion) { Obtener-ResultadoReviewPorFqn -Review $reviewGeneracion -FullyQualifiedName $fullyQualifiedName } else { $null }
                $estadoMarkdown = if (-not $analisis.Error -and $resultadoReview -and $resultadoReview.documento -and $resultadoReview.estado -in @('OK', 'WARNING')) { 'OK' } else { 'ERROR' }
                $estadoPdf = if ($estaPublicado -and $servicioAnterior -and [string](Obtener-PropiedadControlVersiones -Objeto $servicioAnterior -Nombre 'pdfHash') -eq (Get-FileHash -LiteralPath $rutaPdfPublicado -Algorithm SHA256).Hash.ToLowerInvariant()) { 'CONSERVADO' } else { 'ERROR' }
            } elseif ($estaPublicado) {
                $estadoMarkdown = 'OK'
                $estadoPdf = 'OK'
            }
        }
        if ($erroresPublicacion.ContainsKey($fullyQualifiedName)) { [void]$mensajesReview.Add($erroresPublicacion[$fullyQualifiedName]) }
        if ($analisisActuales.ContainsKey($fullyQualifiedName) -and $analisisActuales[$fullyQualifiedName].Error) { [void]$mensajesReview.Add([string]$analisisActuales[$fullyQualifiedName].Error) }
        $resultadoReview = if ($reviewGeneracion) { Obtener-ResultadoReviewPorFqn -Review $reviewGeneracion -FullyQualifiedName $fullyQualifiedName } else { $null }
        if ($resultadoReview) { foreach ($mensaje in @($resultadoReview.mensajes)) { if ($mensaje) { [void]$mensajesReview.Add([string]$mensaje) } } }
        [void]$serviciosReviewFinal.Add([pscustomobject]@{
            fullyQualifiedName = $fullyQualifiedName
            estado = $estadoControl
            estadoMarkdown = $estadoMarkdown
            estadoPdf = $estadoPdf
            documento = if (Test-Path -LiteralPath $rutaMarkdownPublicado -PathType Leaf) { $rutaMarkdownPublicado } else { '' }
            pdf = if (Test-Path -LiteralPath $rutaPdfPublicado -PathType Leaf) { $rutaPdfPublicado } else { '' }
            markdownHash = [string](Obtener-PropiedadControlVersiones -Objeto $servicioObjetivo -Nombre 'documentHash')
            pdfHash = [string](Obtener-PropiedadControlVersiones -Objeto $servicioObjetivo -Nombre 'pdfHash')
            versionAnterior = if ($servicioAnterior) { [string](Obtener-PropiedadControlVersiones -Objeto $servicioAnterior -Nombre 'version') } else { '' }
            versionObjetivo = [string](Obtener-PropiedadControlVersiones -Objeto $servicioObjetivo -Nombre 'version')
            promocionado = $promocionado
            pendientes = if ($pendientesObjetivo.ContainsKey($fullyQualifiedName)) { @($pendientesObjetivo[$fullyQualifiedName]) } else { @() }
            mensajes = @($mensajesReview.ToArray() | Select-Object -Unique)
        })
    }
    $estadoReview = switch ($codigoSalidaOperacion) { 0 { 'COMPLETO' } 2 { 'PARCIAL' } default { 'ERROR' } }
    try {
        $reviewFinal = [ordered]@{
            ejecucion = [ordered]@{
                ejecucionId = [string]$datosManifiestoEjecucion.ejecucionId
                xpz = [string]$configuracion.XpzPath
                fin = (Get-Date).ToString('s')
                estado = $estadoReview
                codigoSalida = $codigoSalidaOperacion
            }
            servicios = @($serviciosReviewFinal.ToArray())
        }
    } catch {
        throw ('No se pudo construir el review final: ' + $_.Exception.Message)
    }
    try {
        $jsonReviewFinal = ($reviewFinal | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText($rutaReviewGeneracion, $jsonReviewFinal, (New-Object System.Text.UTF8Encoding($false)))
    } catch {
        throw ('No se pudo escribir el review final: ' + $_.Exception.Message)
    }

    Escribir-ControlVersionesAtomico -ControlVersiones $controlObjetivo -RutaControl $RutaControl | Out-Null
    Write-Host ('Actualizacion completada. Servicios candidatos: ' + $nombresCandidatos.Count) -ForegroundColor Cyan
    Write-Host ('Control: ' + [System.IO.Path]::GetFullPath($RutaControl)) -ForegroundColor DarkGray
    if ($comparacion.EsFastPath) { Write-Host 'Fast-path: sin cambios de fuente, perfil ni pendientes.' -ForegroundColor DarkGray }
    exit $codigoSalidaOperacion
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    if ($_.InvocationInfo) {
        Write-Host ('  Origen: ' + $_.InvocationInfo.ScriptName + ' | linea ' + $_.InvocationInfo.ScriptLineNumber) -ForegroundColor DarkGray
    }
    if ($_.ScriptStackTrace) {
        Write-Host ('  Traza: ' + $_.ScriptStackTrace) -ForegroundColor DarkGray
    }
    exit 1
} finally {
    if ($lockActualizacion) {
        try { $lockActualizacion.Dispose() } catch { }
        try { Remove-Item -LiteralPath $rutaLockActualizacion -Force -ErrorAction SilentlyContinue } catch { }
    }
    if ($rutaManifiestoEjecucion) {
        try { Eliminar-ManifiestoEjecucion -RutaManifiesto $rutaManifiestoEjecucion } catch { }
    }
    Write-Host ('Fin: ' + ((Get-Date) - $inicioEjecucion).ToString('mm\:ss')) -ForegroundColor DarkGray
}
