# ValidarXPZ.ps1
# Validador de completitud multi-XPZ contra el inventario de endpoints.
# Produce un reporte consolidado de objetos GeneXus faltantes y campos con tipos
# no resolubles, con trazabilidad del XPZ de origen de cada objeto.

[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$XpzPath,
    [string]$ManifiestoPath
)

$ErrorActionPreference = 'Stop'
$StartTime = Get-Date
$RaizRepositorio = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$DirectorioLogs = Join-Path $RaizRepositorio 'Logs'

. (Join-Path $PSScriptRoot 'GLMUtilidades.ps1')
. (Join-Path $PSScriptRoot 'CargarConfiguracion.ps1')
. (Join-Path $PSScriptRoot 'AnalizarServicio.ps1')
. (Join-Path $PSScriptRoot 'CargarMultiXPZ.ps1')
. (Join-Path $PSScriptRoot 'ManifiestoEjecucion.ps1')

$ejecucionId = ''

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
    $xml = if ($IndiceUnificado.PSObject.Properties['XmlUnificado']) { $IndiceUnificado.XmlUnificado } else { $IndiceUnificado.XmlPrincipal }

    $faltantesExportar = New-Object System.Collections.Generic.List[string]
    $selectoresExportar = New-Object System.Collections.Generic.List[string]
    $programaPrincipalNode = $null
    $metodo = ''
    $variableSdt = ''

    try {
        if ($IndiceUnificado.PorFqn.ContainsKey($fullyQualifiedName)) {
            $wrapperNode = $IndiceUnificado.PorFqn[$fullyQualifiedName]
        } else {
            Agregar-Faltante -Nombre (Obtener-NombreObjeto -FQN $fullyQualifiedName) -FaltantesExportar $faltantesExportar -IndiceUnificado $IndiceUnificado
            Agregar-SelectorExportacion -Tipo 'Procedure' -FQN $fullyQualifiedName -SelectoresExportar $selectoresExportar
            return Construir-ResultadoValidacion -WS $fullyQualifiedName -Faltantes $faltantesExportar.ToArray() -Selectores $selectoresExportar.ToArray()
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
                $fqnFaltante = Resolver-FqnObjetoFaltante -Nombre $nombreFaltante -WrapperFQN $fullyQualifiedName
                Agregar-SelectorExportacion -Tipo 'Procedure' -FQN $fqnFaltante -SelectoresExportar $selectoresExportar
            }
            $delegacion = $null
        }

        if ($delegacion) {
            if ($IndiceUnificado.PorFqn.ContainsKey($delegacion)) {
                $programaPrincipalNode = $IndiceUnificado.PorFqn[$delegacion]
            } else {
                Agregar-Faltante -Nombre (Obtener-NombreObjeto -FQN $delegacion) -FaltantesExportar $faltantesExportar -IndiceUnificado $IndiceUnificado
                $fqnFaltante = Resolver-FqnObjetoFaltante -Nombre $delegacion -WrapperFQN $fullyQualifiedName
                Agregar-SelectorExportacion -Tipo 'Procedure' -FQN $fqnFaltante -SelectoresExportar $selectoresExportar
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
                        Agregar-SelectorExportacion -Tipo 'SDT' -FQN $faltante.NombreSdt -SelectoresExportar $selectoresExportar
                    }
                    Procesar-FilasPendientes -Filas $expandidoEntrada.Filas -Tablas $expandidoEntrada.Tablas -FaltantesExportar $faltantesExportar -SelectoresExportar $selectoresExportar -Xml $xml -IndiceUnificado $IndiceUnificado -NodosEvidencia $nodosEvidencia -SourcePrograma $sourcePrograma -ProgramaPrincipalNode $programaPrincipalNode -VariableSdt $variableSdt -FQN $fullyQualifiedName
                } catch {
                    if ($_.Exception.Message -match 'no está exportada en el XPZ') {
                        $nombreFaltante = [regex]::Match($_.Exception.Message, 'SDT\s+([^\s]+)').Groups[1].Value
                        if ($nombreFaltante) {
                            Agregar-Faltante -Nombre (Obtener-NombreObjeto -FQN $nombreFaltante) -FaltantesExportar $faltantesExportar -IndiceUnificado $IndiceUnificado
                            Agregar-SelectorExportacion -Tipo 'SDT' -FQN $nombreFaltante -SelectoresExportar $selectoresExportar
                        }
                    }
                }
            } else {
                try {
                    $posiciones = Resolver-EntradaGet -Source $sourcePrograma
                    $entradaResuelta = Resolver-EntradaGetTipos -Xml $xml -ProgramaPrincipal $programaPrincipalNode -Source $sourcePrograma -Posiciones $posiciones -Indice $IndiceUnificado
                    foreach ($fila in $entradaResuelta) {
                        if ($fila.Tipo -match '^PENDIENTE') {
                            Aplicar-EstrategiasTipo -Fila $fila -Xml $xml -IndiceUnificado $IndiceUnificado -NodosEvidencia $nodosEvidencia -ProgramaPrincipalNode $programaPrincipalNode -SourcePrograma $sourcePrograma -VariableSdt '' -FaltantesExportar $faltantesExportar -SelectoresExportar $selectoresExportar -FQN $fullyQualifiedName
                        }
                    }
                } catch {}
            }

            try {
                $salida = Resolver-Salida -Xml $xml -ProgramaPrincipal $programaPrincipalNode -Source $sourcePrograma -Indice $IndiceUnificado
                if ($salida.NoResuelta) {
                    if ($salida.MotivoNoResuelta -match 'SDT\s+([^\s]+)\s+no está exportada') {
                        Agregar-Faltante -Nombre (Obtener-NombreObjeto -FQN $Matches[1]) -FaltantesExportar $faltantesExportar -IndiceUnificado $IndiceUnificado
                        Agregar-SelectorExportacion -Tipo 'SDT' -FQN $Matches[1] -SelectoresExportar $selectoresExportar
                    }
                } else {
                    Procesar-FilasPendientes -Filas $salida.Salida -Tablas $salida.EstructurasSalida -FaltantesExportar $faltantesExportar -SelectoresExportar $selectoresExportar -Xml $xml -IndiceUnificado $IndiceUnificado -NodosEvidencia $nodosEvidencia -SourcePrograma $sourcePrograma -ProgramaPrincipalNode $programaPrincipalNode -VariableSdt '' -FQN $fullyQualifiedName
                    foreach ($faltante in $salida.Faltantes) {
                        Agregar-Faltante -Nombre (Obtener-NombreObjeto -FQN $faltante.NombreSdt) -FaltantesExportar $faltantesExportar -IndiceUnificado $IndiceUnificado
                        Agregar-SelectorExportacion -Tipo 'SDT' -FQN $faltante.NombreSdt -SelectoresExportar $selectoresExportar
                    }
                }
            } catch {
                if ($_.Exception.Message -match 'no está exportada en el XPZ') {
                    $nombreFaltante = [regex]::Match($_.Exception.Message, 'SDT\s+([^\s]+)').Groups[1].Value
                    if ($nombreFaltante) {
                        Agregar-Faltante -Nombre (Obtener-NombreObjeto -FQN $nombreFaltante) -FaltantesExportar $faltantesExportar -IndiceUnificado $IndiceUnificado
                        Agregar-SelectorExportacion -Tipo 'SDT' -FQN $nombreFaltante -SelectoresExportar $selectoresExportar
                    }
                }
            }
        }
    } catch {
        Agregar-Faltante -Nombre (Obtener-NombreObjeto -FQN $fullyQualifiedName) -FaltantesExportar $faltantesExportar -IndiceUnificado $IndiceUnificado
        Agregar-SelectorExportacion -Tipo 'Procedure' -FQN $fullyQualifiedName -SelectoresExportar $selectoresExportar
    }

    return Construir-ResultadoValidacion -WS $fullyQualifiedName -Faltantes $faltantesExportar.ToArray() -Selectores $selectoresExportar.ToArray()
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

function Construir-SelectorExportacion {
    <#
    Construye un selector estable para la tarea Export de GeneXus.
    El FQN se conserva completo para evitar colisiones entre modulos.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Tipo,
        [Parameter(Mandatory = $true)][string]$FQN
    )

    if (-not $FQN) { return '' }
    return ($Tipo + ':' + $FQN)
}

function Resolver-FqnObjetoFaltante {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Nombre,
        [Parameter(Mandatory = $true)][string]$WrapperFQN
    )

    if (-not $Nombre) { return '' }
    if ($Nombre.Contains('.')) { return $Nombre }

    $ultimoPunto = $WrapperFQN.LastIndexOf('.')
    if ($ultimoPunto -gt 0) {
        return ($WrapperFQN.Substring(0, $ultimoPunto) + '.' + $Nombre)
    }

    return $Nombre
}

function Agregar-SelectorExportacion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Tipo,
        [Parameter(Mandatory = $true)][string]$FQN,
        [System.Collections.Generic.List[string]]$SelectoresExportar
    )

    if ($null -eq $SelectoresExportar -or -not $FQN) { return }
    $selector = Construir-SelectorExportacion -Tipo $Tipo -FQN $FQN
    if ($selector -and $SelectoresExportar -notcontains $selector) {
        [void]$SelectoresExportar.Add($selector)
    }
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
        [System.Collections.Generic.List[string]]$SelectoresExportar,
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
            Aplicar-EstrategiasTipo -Fila $fila -Xml $Xml -IndiceUnificado $IndiceUnificado -NodosEvidencia $NodosEvidencia -ProgramaPrincipalNode $ProgramaPrincipalNode -SourcePrograma $SourcePrograma -VariableSdt $VariableSdt -FaltantesExportar $FaltantesExportar -SelectoresExportar $SelectoresExportar -FQN $FQN
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
        [System.Collections.Generic.List[string]]$SelectoresExportar,
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
        if ($sdtFqn) {
            Agregar-SelectorExportacion -Tipo 'SDT' -FQN $sdtFqn -SelectoresExportar $SelectoresExportar
        } else {
            Agregar-SelectorExportacion -Tipo 'Procedure' -FQN $ProgramaPrincipalNode.GetAttribute('fullyQualifiedName') -SelectoresExportar $SelectoresExportar
        }
    }
}

function Construir-ResultadoValidacion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WS,
        [string[]]$Faltantes = @(),
        [string[]]$Selectores = @()
    )

    $esPendiente = $Faltantes.Count -gt 0

    return [pscustomobject]@{
        ws = $WS
        esPendiente = $esPendiente
        faltantes = @($Faltantes)
        selectores = @($Selectores)
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
        [Parameter(Mandatory = $true)]$IndiceUnificado,
        [Parameter(Mandatory = $true)][string]$EjecucionId,
        [Parameter(Mandatory = $false)][string]$RutaManifiesto = '',
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$ContextId = ''
    )

    $pendientes = @($Resultados | Where-Object { $_.esPendiente })
    $ok = $Resultados.Count - $pendientes.Count

    $nombresXpz = $IndiceUnificado.NombresXpz
    $xpzPrincipal = if ($IndiceUnificado.XpzPrincipalRelativo) { $IndiceUnificado.XpzPrincipalRelativo } elseif ($nombresXpz.Count -gt 0) { $nombresXpz[0] } else { '' }

    $objectList = Construir-ObjectList -Resultados $Resultados

    $reporte = [pscustomobject]@{
        schemaVersion = 2
        ejecucion = [pscustomobject]@{
            id = $EjecucionId
            contextId = $ContextId
            xpz = $xpzPrincipal
            manifiesto = $RutaManifiesto
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
                selectores = if ($_.PSObject.Properties['selectores']) { @($_.selectores) } else { @() }
            }
        })
        objectList = $objectList
    }

    Asegurar-Directorio -Ruta ([System.IO.Path]::GetDirectoryName($RutaReporte))

    $json = Normalizar-SaltosLineaLf -Texto ($reporte | ConvertTo-Json -Depth 10)
    Escribir-TextoUtf8SinBom -Ruta $RutaReporte -Contenido $json
}

try {
    $clienteId = ''
    $ambienteId = ''
    $contextId = ''
    if ($ManifiestoPath) {
        $manifiestoEjecucion = Leer-ManifiestoEjecucion -RutaManifiesto $ManifiestoPath
        $XpzPath = [string]$manifiestoEjecucion.xpz
        $ejecucionId = [string]$manifiestoEjecucion.ejecucionId
        $clienteId = [string]$manifiestoEjecucion.clienteId
        $ambienteId = [string]$manifiestoEjecucion.ambienteId
        $contextId = [string]$manifiestoEjecucion.contextId
        $DirectorioLogs = [System.IO.Path]::GetFullPath([string]$manifiestoEjecucion.logsDirectory)
        Asegurar-Directorio -Ruta $DirectorioLogs
    } else {
        $ejecucionId = Obtener-NuevoIdentificadorEjecucion
    }
    $cargarConfiguracionParametros = @{ ConfigPath = $ConfigPath }
    if ($XpzPath) { $cargarConfiguracionParametros.XpzPath = $XpzPath }
    if ($clienteId) {
        $cargarConfiguracionParametros.ClienteId = $clienteId
        $cargarConfiguracionParametros.AmbienteId = $ambienteId
    }
    $configuracion = Cargar-Configuracion @cargarConfiguracionParametros
    if (-not $XpzPath) { $XpzPath = $configuracion.XpzPath }

    $ignoradosConfig = @($configuracion.ServiciosIgnorados)
    $indiceUnificado = Cargar-IndiceMultiXPZ -RutaXpzPrincipal $XpzPath
    $endpointsInventario = @(Obtener-ServiciosHttpDesdeIndice -Indice $indiceUnificado)
    $endpointsEfectivos = @($endpointsInventario | Where-Object { $ignoradosConfig -notcontains $_.proceso })
    $endpointsIgnorados = @($endpointsInventario | Where-Object { $ignoradosConfig -contains $_.proceso })

    if ($endpointsIgnorados.Count -gt 0) {
        Write-Host ("  Servicios ignorados (serviciosIgnorados en configuracion.json): " + $endpointsIgnorados.Count) -ForegroundColor DarkGray
    }

    $xpzComplementarios = @($indiceUnificado.RutasXpz | Select-Object -Skip 1)

    $rutaRelativaXpzPrincipal = $XpzPath
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
    $rutaReporte = Join-Path $DirectorioLogs ($ejecucionId + '-validacion-xpz.json')

    Write-ReporteValidacion -Resultados $resultados -RutaReporte $rutaReporte -StartTime $StartTime -FinEjecucion $finEjecucion -IndiceUnificado $indiceUnificado -EjecucionId $ejecucionId -RutaManifiesto $ManifiestoPath -ContextId $contextId

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
