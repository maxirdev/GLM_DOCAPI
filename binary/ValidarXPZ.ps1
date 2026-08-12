# ValidarXPZ.ps1
# Validador de completitud multi-XPZ contra el inventario de endpoints.
# Produce un reporte consolidado de objetos GeneXus faltantes y campos con tipos
# no resolubles, con trazabilidad del XPZ de origen de cada objeto.

[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$XpzPath
)

$ErrorActionPreference = 'Stop'
$StartTime = Get-Date
$RaizRepositorio = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$DirectorioLogs = Join-Path $RaizRepositorio 'Logs'

. (Join-Path $PSScriptRoot 'CargarConfiguracion.ps1')
. (Join-Path $PSScriptRoot 'AnalizarServicio.ps1')

function Descubrir-XPZComplementarios {
    <#
    .SYNOPSIS
    Busca archivos XPZ complementarios en el mismo directorio del XPZ principal.
    .DESCRIPTION
    Dado el nombre del XPZ principal (p.ej. SEGUROS_COMERCIAL_APIGLM_v1_0.xpz),
    busca en el mismo directorio archivos que coincidan con <nombreBase>_<N>.xpz
    y los ordena numericamente por N. El patron es ^<nombreBase>_(\d+)\.xpz$.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaXpzPrincipal
    )

    $directorioXpz = [System.IO.Path]::GetDirectoryName($RutaXpzPrincipal)
    $nombreXpzPrincipal = [System.IO.Path]::GetFileNameWithoutExtension($RutaXpzPrincipal)
    $nombreBaseEscapado = [regex]::Escape($nombreXpzPrincipal)
    $patronComplemento = '^' + $nombreBaseEscapado + '_(\d+)\.xpz$'
    $regexComplemento = [regex]::new($patronComplemento, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $complementos = New-Object System.Collections.Generic.List[object]
    foreach ($archivo in (Get-ChildItem -LiteralPath $directorioXpz -Filter '*.xpz')) {
        $coincidencia = $regexComplemento.Match($archivo.Name)
        if (-not $coincidencia.Success) { continue }
        $numero = [int]$coincidencia.Groups[1].Value
        $complementos.Add([pscustomobject]@{
            Ruta = $archivo.FullName
            Nombre = $archivo.Name
            Numero = $numero
        })
    }

    $ordenados = @($complementos | Sort-Object Numero)
    Write-Host ("  XPZ complementarios descubiertos: " + $ordenados.Count) -ForegroundColor DarkGray
    foreach ($complemento in $ordenados) {
        Write-Host ("    " + $complemento.Nombre) -ForegroundColor DarkGray
    }
    $rutas = @($ordenados | ForEach-Object { $_.Ruta })
    Write-Output -NoEnumerate $rutas
    return
}

function Merge-ListaIndice {
    <#
    .SYNOPSIS
    Fusiona un indice de nombre → lista de nodos en el destino, sin duplicar por GUID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Destino,
        [Parameter(Mandatory = $true)]$Origen,
        [Parameter(Mandatory = $true)][ref]$GuidsVistos
    )

    foreach ($nombre in $Origen.Keys) {
        if (-not $Destino.ContainsKey($nombre)) {
            $Destino[$nombre] = New-Object System.Collections.Generic.List[object]
        }
        foreach ($nodo in $Origen[$nombre]) {
            $guid = $nodo.GetAttribute('guid')
            if ($guid -and $GuidsVistos.Value.ContainsKey($guid)) { continue }
            if ($guid) { $GuidsVistos.Value[$guid] = $true }
            $Destino[$nombre].Add($nodo)
        }
    }
}

function Construir-IndiceMultiXPZ {
    <#
    .SYNOPSIS
    Abre el XPZ principal y los complementarios, construye sus indices y los
    fusiona en un indice unificado con trazabilidad de origen.
    .DESCRIPTION
    Cada entrada del indice unificado registra el XPZ de origen. La fusion
    respeta cascada: si un FQN ya existe en un XPZ anterior, se conserva el
    del primer XPZ donde aparecio.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaXpzPrincipal,
        [Parameter(Mandatory = $false)][string[]]$XpzComplementarios = @()
    )

    $todasRutas = @($RutaXpzPrincipal) + @($XpzComplementarios)
    $nombresXpz = @()
    $indicesParciales = @()

    foreach ($rutaXpz in $todasRutas) {
        $nombreXpz = [System.IO.Path]::GetFileName($rutaXpz)
        $abierto = Abrir-XPZ -RutaXpz $rutaXpz
        $indice = Construir-Indices -Xml $abierto.Xml
        $indice | Add-Member -MemberType NoteProperty -Name 'NombreXpz' -Value $nombreXpz -Force
        $indicesParciales += $indice
        $nombresXpz += $nombreXpz
    }

    $porFqnUnificado = @{}
    $origen = @{}
    $origenPorGuid = @{}
    $todosNombresXpz = @($nombresXpz)

    for ($indiceXpz = 0; $indiceXpz -lt $indicesParciales.Count; $indiceXpz++) {
        $indiceParcial = $indicesParciales[$indiceXpz]
        $nombreXpz = $indiceParcial.NombreXpz

        foreach ($fqn in $indiceParcial.PorFqn.Keys) {
            $objeto = $indiceParcial.PorFqn[$fqn]
            if (-not $porFqnUnificado.ContainsKey($fqn)) {
                $porFqnUnificado[$fqn] = $objeto
                $origen[$fqn] = $nombreXpz
                $guid = $objeto.GetAttribute('guid')
                if ($guid -and -not $origenPorGuid.ContainsKey($guid)) {
                    $origenPorGuid[$guid] = $nombreXpz
                }
            }
        }
    }

    $porNombreUnificado = @{}
    $porNombreCodigoUnificado = @{}
    $porNombreDominioUnificado = @{}
    $porNombreAtributoUnificado = @{}
    $guidsVistosNodos = @{}

    foreach ($indiceParcial in $indicesParciales) {
        Merge-ListaIndice -Destino $porNombreUnificado -Origen $indiceParcial.PorNombre -GuidsVistos ([ref]$guidsVistosNodos)
        Merge-ListaIndice -Destino $porNombreCodigoUnificado -Origen $indiceParcial.PorNombreCodigo -GuidsVistos ([ref]$guidsVistosNodos)
        Merge-ListaIndice -Destino $porNombreDominioUnificado -Origen $indiceParcial.PorNombreDominio -GuidsVistos ([ref]$guidsVistosNodos)
        Merge-ListaIndice -Destino $porNombreAtributoUnificado -Origen $indiceParcial.PorNombreAtributo -GuidsVistos ([ref]$guidsVistosNodos)
    }

    $indiceUnificado = [pscustomobject]@{
        PorFqn = $porFqnUnificado
        PorNombre = $porNombreUnificado
        PorNombreCodigo = $porNombreCodigoUnificado
        PorNombreDominio = $porNombreDominioUnificado
        PorNombreAtributo = $porNombreAtributoUnificado
        Origen = $origen
        OrigenPorGuid = $origenPorGuid
        NombresXpz = $todosNombresXpz
        TiposMiembroSdt = $null
        EvidenciasMiembroSdt = $null
        TiposMiembroSdtConstruido = $false
    }

    Write-Host ("  Indice unificado: " + $porFqnUnificado.Count + " objetos FQN de " + $todosNombresXpz.Count + " XPZ") -ForegroundColor DarkGray

    return $indiceUnificado
}

function Validar-CompletitudServicio {
    <#
    .SYNOPSIS
    Valida la completitud de un servicio contra el indice unificado multi-XPZ.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Endpoint,
        [Parameter(Mandatory = $true)]$IndiceUnificado,
        [Parameter(Mandatory = $true)][object]$Configuracion
    )

    $fullyQualifiedName = $Endpoint.proceso
    $xml = $IndiceUnificado.XmlPrincipal

    $faltantesExportar = New-Object System.Collections.Generic.List[string]
    $programaPrincipalNode = $null
    $metodo = ''
    $variableSdt = ''

    try {
        if ($IndiceUnificado.PorFqn.ContainsKey($fullyQualifiedName)) {
            $wrapperNode = $IndiceUnificado.PorFqn[$fullyQualifiedName]
        } else {
            Agregar-Faltante -Nombre (Obtener-NombreObjeto -FQN $fullyQualifiedName) -FaltantesExportar $faltantesExportar -IndiceUnificado $IndiceUnificado
            return Construir-ResultadoValidacion -WS $fullyQualifiedName -Faltantes $faltantesExportar.ToArray()
        }

        try {
            $sourceWrapper = Obtener-Source -ProgramaPrincipal $wrapperNode
            $metodo = Resolver-Metodo -Source $sourceWrapper
            $delegacion = Obtener-DelegacionUnica -Xml $xml -Wrapper $wrapperNode -Indice $IndiceUnificado
        } catch {
            if ($_.Exception.Message -match 'no está exportado en el XPZ configurado') {
                $nombreFaltante = [regex]::Match($_.Exception.Message, 'programa principal ([^\s]+)').Groups[1].Value
                if (-not $nombreFaltante) { $nombreFaltante = 'desconocido' }
                Agregar-Faltante -Nombre (Obtener-NombreObjeto -FQN $nombreFaltante) -FaltantesExportar $faltantesExportar -IndiceUnificado $IndiceUnificado
            }
            $delegacion = $null
        }

        if ($delegacion) {
            if ($IndiceUnificado.PorFqn.ContainsKey($delegacion)) {
                $programaPrincipalNode = $IndiceUnificado.PorFqn[$delegacion]
            } else {
                Agregar-Faltante -Nombre (Obtener-NombreObjeto -FQN $delegacion) -FaltantesExportar $faltantesExportar -IndiceUnificado $IndiceUnificado
            }
        }

        if ($programaPrincipalNode) {
            $sourcePrograma = Obtener-Source -ProgramaPrincipal $programaPrincipalNode
            try { $metodo = Resolver-Metodo -Source $sourcePrograma } catch {}
            $nodosEvidencia = @(Obtener-NodosEvidencia -Xml $xml -ProgramaPrincipal $programaPrincipalNode -Indice $IndiceUnificado -IncluirSufijos -ProfundidadMaxima 3)

            if ($metodo -eq 'POST') {
                try {
                    $entrada = Resolver-EntradaPost -Xml $xml -ProgramaPrincipal $programaPrincipalNode -Source $sourcePrograma -Indice $IndiceUnificado
                    $variableSdt = $entrada.VariableSdt
                    $expandidoEntrada = Expandir-EstructuraSdt -Xml $xml -Sdt $entrada.Sdt -Indice $IndiceUnificado
                    foreach ($faltante in $expandidoEntrada.Faltantes) {
                        Agregar-Faltante -Nombre (Obtener-NombreObjeto -FQN $faltante.NombreSdt) -FaltantesExportar $faltantesExportar -IndiceUnificado $IndiceUnificado
                    }
                    Procesar-FilasPendientes -Filas $expandidoEntrada.Filas -Tablas $expandidoEntrada.Tablas -FaltantesExportar $faltantesExportar -Xml $xml -IndiceUnificado $IndiceUnificado -NodosEvidencia $nodosEvidencia -SourcePrograma $sourcePrograma -ProgramaPrincipalNode $programaPrincipalNode -VariableSdt $variableSdt -FQN $fullyQualifiedName
                } catch {
                    if ($_.Exception.Message -match 'no está exportada en el XPZ') {
                        $nombreFaltante = [regex]::Match($_.Exception.Message, 'SDT\s+([^\s]+)').Groups[1].Value
                        if ($nombreFaltante) {
                            Agregar-Faltante -Nombre (Obtener-NombreObjeto -FQN $nombreFaltante) -FaltantesExportar $faltantesExportar -IndiceUnificado $IndiceUnificado
                        }
                    }
                }
            } else {
                try {
                    $posiciones = Resolver-EntradaGet -Source $sourcePrograma
                    $entradaResuelta = Resolver-EntradaGetTipos -Xml $xml -ProgramaPrincipal $programaPrincipalNode -Source $sourcePrograma -Posiciones $posiciones -Indice $IndiceUnificado
                    foreach ($fila in $entradaResuelta) {
                        if ($fila.Tipo -match '^PENDIENTE') {
                            Aplicar-EstrategiasTipo -Fila $fila -Xml $xml -IndiceUnificado $IndiceUnificado -NodosEvidencia $nodosEvidencia -ProgramaPrincipalNode $programaPrincipalNode -SourcePrograma $sourcePrograma -VariableSdt '' -FaltantesExportar $faltantesExportar -FQN $fullyQualifiedName
                        }
                    }
                } catch {}
            }

            try {
                $salida = Resolver-Salida -Xml $xml -ProgramaPrincipal $programaPrincipalNode -Source $sourcePrograma -Indice $IndiceUnificado
                if ($salida.NoResuelta) {
                    if ($salida.MotivoNoResuelta -match 'SDT\s+([^\s]+)\s+no está exportada') {
                        Agregar-Faltante -Nombre (Obtener-NombreObjeto -FQN $Matches[1]) -FaltantesExportar $faltantesExportar -IndiceUnificado $IndiceUnificado
                    }
                } else {
                    Procesar-FilasPendientes -Filas $salida.Salida -Tablas $salida.EstructurasSalida -FaltantesExportar $faltantesExportar -Xml $xml -IndiceUnificado $IndiceUnificado -NodosEvidencia $nodosEvidencia -SourcePrograma $sourcePrograma -ProgramaPrincipalNode $programaPrincipalNode -VariableSdt '' -FQN $fullyQualifiedName
                    foreach ($faltante in $salida.Faltantes) {
                        Agregar-Faltante -Nombre (Obtener-NombreObjeto -FQN $faltante.NombreSdt) -FaltantesExportar $faltantesExportar -IndiceUnificado $IndiceUnificado
                    }
                }
            } catch {
                if ($_.Exception.Message -match 'no está exportada en el XPZ') {
                    $nombreFaltante = [regex]::Match($_.Exception.Message, 'SDT\s+([^\s]+)').Groups[1].Value
                    if ($nombreFaltante) {
                        Agregar-Faltante -Nombre (Obtener-NombreObjeto -FQN $nombreFaltante) -FaltantesExportar $faltantesExportar -IndiceUnificado $IndiceUnificado
                    }
                }
            }
        }
    } catch {
        Agregar-Faltante -Nombre (Obtener-NombreObjeto -FQN $fullyQualifiedName) -FaltantesExportar $faltantesExportar -IndiceUnificado $IndiceUnificado
    }

    return Construir-ResultadoValidacion -WS $fullyQualifiedName -Faltantes $faltantesExportar.ToArray()
}

function Obtener-NombreObjeto {
    <#
    .SYNOPSIS
    Devuelve el nombre real (ultimo segmento) de un fullyQualifiedName.
    .DESCRIPTION
    Recibe un FQN como 'APIGLM.Cobranzas.BPCrearNovedadPago' o
    'Cobranzas.BotonDePago.BPInsIntencionPago' y devuelve solo el nombre del
    objeto, que es lo que se solicita exportar en el objectList.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FQN
    )

    if (-not $FQN) { return '' }
    $partes = $FQN -split '\.'
    return $partes[-1]
}

function Es-ObjetoEnIndice {
    <#
    .SYNOPSIS
    Indica si un objeto existe en el indice unificado por FQN exacto o por nombre.
    .DESCRIPTION
    Se usa para distinguir los objetos genuinamente ausentes del XPZ de aquellos
    que ya estan exportados. El objectList solo debe solicitar los ausentes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Nombre,
        [Parameter(Mandatory = $true)]$IndiceUnificado
    )

    if (-not $Nombre) { return $false }
    if ($IndiceUnificado.PorFqn -and $IndiceUnificado.PorFqn.ContainsKey($Nombre)) { return $true }
    if ($IndiceUnificado.PorNombre -and $IndiceUnificado.PorNombre.ContainsKey($Nombre)) { return $true }
    return $false
}

function Agregar-Faltante {
    <#
    .SYNOPSIS
    Agrega un objeto a la lista de exportacion solo si no existe en el indice.
    .DESCRIPTION
    El validador solo debe solicitar objetos ausentes del XPZ. Los objetos ya
    exportados (aunque su tipo de miembro no se haya confirmado) no se piden,
    porque volver a exportarlos no resolveria la confirmacion pendiente.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Nombre,
        [System.Collections.Generic.List[string]]$FaltantesExportar,
        [Parameter(Mandatory = $true)]$IndiceUnificado
    )

    if (-not $Nombre) { return }
    if (Es-ObjetoEnIndice -Nombre $Nombre -IndiceUnificado $IndiceUnificado) { return }
    if ($FaltantesExportar -contains $Nombre) { return }
    [void]$FaltantesExportar.Add($Nombre)
}

function Procesar-FilasPendientes {
    <#
    .SYNOPSIS
    Recorre filas y tablas de estructuras y aplica las estrategias de tipo a
    las filas pendientes, registrando el objeto a exportar cuando el tipo no
    se puede resolver.
    #>
    [CmdletBinding()]
    param(
        $Filas,
        $Tablas,
        [System.Collections.Generic.List[string]]$FaltantesExportar,
        $Xml,
        $IndiceUnificado,
        $NodosEvidencia,
        $SourcePrograma,
        $ProgramaPrincipalNode,
        $VariableSdt,
        $FQN
    )

    $procesar = [scriptblock]{
        param($fila)
        if ($fila.Tipo -match '^PENDIENTE') {
            Aplicar-EstrategiasTipo -Fila $fila -Xml $Xml -IndiceUnificado $IndiceUnificado -NodosEvidencia $NodosEvidencia -ProgramaPrincipalNode $ProgramaPrincipalNode -SourcePrograma $SourcePrograma -VariableSdt $VariableSdt -FaltantesExportar $FaltantesExportar -FQN $FQN
        }
    }

    foreach ($fila in $Filas) { & $procesar $fila }
    foreach ($tabla in $Tablas) {
        $hijos = $null
        if ($tabla.PSObject.Properties['Hijos'] -and $tabla.Hijos) { $hijos = $tabla.Hijos }
        elseif ($tabla.PSObject.Properties['Filas'] -and $tabla.Filas) { $hijos = $tabla.Filas }
        foreach ($fila in $hijos) { & $procesar $fila }
    }
}

function Aplicar-EstrategiasTipo {
    [CmdletBinding()]
    param(
        $Fila,
        $Xml,
        $IndiceUnificado,
        $NodosEvidencia,
        $ProgramaPrincipalNode,
        $SourcePrograma,
        $VariableSdt,
        [System.Collections.Generic.List[string]]$FaltantesExportar,
        $FQN
    )

    $campo = $Fila.Campo
    $rutaJson = if ($Fila.PSObject.Properties['RutaJson'] -and $Fila.RutaJson) { $Fila.RutaJson } else { $campo }
    $sdtFqn = if ($Fila.PSObject.Properties['SdtFqn'] -and $Fila.SdtFqn) { $Fila.SdtFqn } else { '' }
    $rutaSdt = if ($Fila.PSObject.Properties['RutaSdt'] -and $Fila.RutaSdt) { $Fila.RutaSdt } else { $rutaJson }

    if ($VariableSdt) {
        $tipo = Resolver-TipoPorLectura -Xml $Xml -Campo $campo -VariableSdt $VariableSdt -Nodos $NodosEvidencia -Indice $IndiceUnificado
        if ($tipo) { $Fila.Tipo = $tipo; return }
    }

    if ($VariableSdt -and $SourcePrograma -and $ProgramaPrincipalNode) {
        $tipo = Resolver-TipoPorFlujoParametros -Xml $Xml -Programa $ProgramaPrincipalNode -Source $SourcePrograma -VariableSdt $VariableSdt -Fila $Fila -Indice $IndiceUnificado
        if ($tipo) { $Fila.Tipo = $tipo; return }
    }

    if ($sdtFqn -and $rutaSdt) {
        $tipo = Resolver-TipoMiembroSdtGlobal -Xml $Xml -SdtFqn $sdtFqn -RutaSdt $rutaSdt -Indice $IndiceUnificado
        if ($tipo) { $Fila.Tipo = $tipo; return }
    }

    if (-not $VariableSdt) {
        $tipo = Resolver-TipoPorAsignacion -Xml $Xml -Campo $campo -RutaJson $rutaJson -Nodos $NodosEvidencia -Indice $IndiceUnificado
        if ($tipo) { $Fila.Tipo = $tipo; return }
    }

    $tipo = Resolver-TipoVariable -Xml $Xml -Variable $campo -Nodos $NodosEvidencia -Indice $IndiceUnificado
    if ($tipo) { $Fila.Tipo = $tipo; return }

    $tipo = Resolver-TipoAtributo -Xml $Xml -Nombre $campo -Indice $IndiceUnificado
    if ($tipo) { $Fila.Tipo = $tipo; return }

    if ($rutaJson -match '\.') {
        $partesRuta = $rutaJson -split '\.'
        $tipo = Resolver-TipoMiembro -Xml $Xml -Variable $partesRuta[0] -Ruta ($partesRuta[1..($partesRuta.Count - 1)] -join '.') -Nodos $NodosEvidencia -Indice $IndiceUnificado
        if ($tipo) { $Fila.Tipo = $tipo; return }
    }

    $nombreObjeto = if ($sdtFqn) {
        (Obtener-NombreObjeto -FQN $sdtFqn)
    } else {
        (Obtener-NombreObjeto -FQN $ProgramaPrincipalNode.GetAttribute('fullyQualifiedName'))
    }
    if ($nombreObjeto) {
        Agregar-Faltante -Nombre $nombreObjeto -FaltantesExportar $FaltantesExportar -IndiceUnificado $IndiceUnificado
    }
}

function Construir-ResultadoValidacion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WS,
        [string[]]$Faltantes = @()
    )

    $esPendiente = $Faltantes.Count -gt 0

    return [pscustomobject]@{
        ws = $WS
        esPendiente = $esPendiente
        faltantes = @($Faltantes)
    }
}

function Construir-ObjectList {
    <#
    .SYNOPSIS
    Construye el objectList con los nombres reales de los objetos a exportar,
    sin prefijo de tipo ni nombre completo, separados por coma.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Resultados
    )

    $items = New-Object System.Collections.Generic.List[string]

    foreach ($resultado in $resultados) {
        if (-not $resultado.PSObject.Properties['faltantes'] -or $resultado.faltantes.Count -eq 0) { continue }
        foreach ($faltante in $resultado.faltantes) {
            $nombre = Obtener-NombreObjeto -FQN $faltante
            if ($nombre -and $items -notcontains $nombre) {
                [void]$items.Add($nombre)
            }
        }
    }

    return ($items -join ',')
}

function Write-ReporteValidacion {
    <#
    .SYNOPSIS
    Serializa los resultados de la validacion en el JSON de salida.
    .DESCRIPTION
    El reporte es la receta de exportacion: solo listas los servicios que
    requieren objetos adicionales y el objectList con los nombres reales a
    exportar.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Resultados,
        [Parameter(Mandatory = $true)][string]$RutaReporte,
        [Parameter(Mandatory = $true)][datetime]$StartTime,
        [Parameter(Mandatory = $true)][datetime]$FinEjecucion,
        [Parameter(Mandatory = $true)]$IndiceUnificado
    )

    $pendientes = @($Resultados | Where-Object { $_.esPendiente })
    $ok = $Resultados.Count - $pendientes.Count

    $nombresXpz = $IndiceUnificado.NombresXpz
    $xpzPrincipal = if ($IndiceUnificado.XpzPrincipalRelativo) { $IndiceUnificado.XpzPrincipalRelativo } elseif ($nombresXpz.Count -gt 0) { $nombresXpz[0] } else { '' }

    $objectList = Construir-ObjectList -Resultados $Resultados

    $reporte = [pscustomobject]@{
        schemaVersion = 2
        ejecucion = [pscustomobject]@{
            xpz = $xpzPrincipal
            inicio = $StartTime.ToString('s')
            fin = $FinEjecucion.ToString('s')
            total = $Resultados.Count
            ok = $ok
            pendientes = $pendientes.Count
        }
        solicitudes = @($pendientes | ForEach-Object {
            [pscustomobject]@{
                servicio = $_.ws
                exportar = @($_.faltantes)
            }
        })
        objectList = $objectList
    }

    $directorioReporte = [System.IO.Path]::GetDirectoryName($RutaReporte)
    if (-not (Test-Path -LiteralPath $directorioReporte)) {
        New-Item -ItemType Directory -Path $directorioReporte -Force | Out-Null
    }

    $json = $reporte | ConvertTo-Json -Depth 10
    $json = $json -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($RutaReporte, $json, (New-Object System.Text.UTF8Encoding($false)))
}

try {
    $cargarConfiguracionParametros = @{ ConfigPath = $ConfigPath }
    if ($XpzPath) { $cargarConfiguracionParametros.XpzPath = $XpzPath }
    $configuracion = Cargar-Configuracion @cargarConfiguracionParametros

    $RutaInventario = Join-Path $RaizRepositorio 'documentacion\Endpoints\assets\endpoints.json'
    if (-not (Test-Path -LiteralPath $RutaInventario)) {
        throw ("No se encontro el inventario en: " + $RutaInventario)
    }
    $inventarioRaw = Get-Content -LiteralPath $RutaInventario -Raw | ConvertFrom-Json
    $endpointsInventario = @($inventarioRaw.endpoints)

    $ignoradosConfig = @($configuracion.ServiciosIgnorados)
    $endpointsEfectivos = @($endpointsInventario | Where-Object { $ignoradosConfig -notcontains $_.proceso })
    $endpointsIgnorados = @($endpointsInventario | Where-Object { $ignoradosConfig -contains $_.proceso })

    if ($endpointsIgnorados.Count -gt 0) {
        Write-Host ("  Servicios ignorados (serviciosIgnorados en configuracion.json): " + $endpointsIgnorados.Count) -ForegroundColor DarkGray
    }

    $xpzComplementarios = Descubrir-XPZComplementarios -RutaXpzPrincipal $configuracion.XpzPath

    $indiceUnificado = Construir-IndiceMultiXPZ -RutaXpzPrincipal $configuracion.XpzPath -XpzComplementarios $xpzComplementarios

    $aperturaPrincipal = Abrir-XPZ -RutaXpz $configuracion.XpzPath
    $indiceUnificado | Add-Member -MemberType NoteProperty -Name 'XmlPrincipal' -Value $aperturaPrincipal.Xml -Force

    $rutaRelativaXpzPrincipal = $configuracion.XpzPath
    if ($rutaRelativaXpzPrincipal.StartsWith($RaizRepositorio, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rutaRelativaXpzPrincipal = $rutaRelativaXpzPrincipal.Substring($RaizRepositorio.Length).TrimStart('\', '/')
    }
    $indiceUnificado | Add-Member -MemberType NoteProperty -Name 'XpzPrincipalRelativo' -Value ($rutaRelativaXpzPrincipal -replace '\\', '/') -Force

    $rutaRelativaComplementarios = @($xpzComplementarios | ForEach-Object {
        $relativo = $_
        if ($relativo.StartsWith($RaizRepositorio, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relativo = $relativo.Substring($RaizRepositorio.Length).TrimStart('\', '/')
        }
        $relativo -replace '\\', '/'
    })
    $indiceUnificado | Add-Member -MemberType NoteProperty -Name 'XpzComplementariosRelativos' -Value $rutaRelativaComplementarios -Force

    $resultados = New-Object System.Collections.Generic.List[object]

    foreach ($endpoint in $endpointsEfectivos) {
        $resultado = Validar-CompletitudServicio -Endpoint $endpoint -IndiceUnificado $indiceUnificado -Configuracion $configuracion
        $resultados.Add($resultado)
    }

    $finEjecucion = Get-Date
    $marcaTemporal = $finEjecucion.ToString('yyyyMMdd-HHmmss')
    $rutaReporte = Join-Path $DirectorioLogs ($marcaTemporal + '-validacion-xpz.json')

    Write-ReporteValidacion -Resultados $resultados -RutaReporte $rutaReporte -StartTime $StartTime -FinEjecucion $finEjecucion -IndiceUnificado $indiceUnificado

    $ok = @($resultados | Where-Object { -not $_.esPendiente }).Count
    $pendientes = @($resultados | Where-Object { $_.esPendiente }).Count

    Write-Host ''
    Write-Host -NoNewline ("Validacion completada: ") -ForegroundColor Gray
    Write-Host -NoNewline ("$ok OK") -ForegroundColor Green
    if ($pendientes -gt 0) {
        Write-Host -NoNewline (", ") -ForegroundColor Gray
        Write-Host ("$pendientes requieren exportacion adicional.") -ForegroundColor Yellow
    } else {
        Write-Host '.'
    }
    Write-Host ("Reporte: $rutaReporte") -ForegroundColor DarkGray

    if ($pendientes -gt 0) { exit 1 }
    exit 0
} catch {
    Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
