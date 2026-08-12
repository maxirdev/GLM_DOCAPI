# AnalizarServicio.ps1
# Modulo de analisis de servicios APIGLM desde el XPZ.
# Se importa por dot-source desde GenerarDocumento.ps1.
# Contiene las funciones de acceso al XPZ y el analisis de la documentacion tecnica.
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Abrir-XPZ {
    <#
    .SYNOPSIS
    Abre el XPZ como ZIP de solo lectura y devuelve el XML interno cargado,
    la ruta resuelta y el nombre del archivo.
    .DESCRIPTION
    Localiza la primera entrada XML del XPZ, lee su contenido,
    lo carga como System.Xml.XmlDocument y valida que la raiz sea ExportFile.
    Devuelve un objeto con las propiedades Xml, Ruta y Nombre.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaXpz
    )

    if (-not (Test-Path -LiteralPath $RutaXpz)) {
        throw ("No se encontro el archivo XPZ: " + $RutaXpz)
    }
    $RutaXpz = (Resolve-Path -LiteralPath $RutaXpz).Path
    $NombreXpz = [System.IO.Path]::GetFileName($RutaXpz)

    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($RutaXpz)
        $entry = $zip.Entries | Where-Object { $_.Name -like '*.xml' } | Select-Object -First 1
        if (-not $entry) {
            throw ('El XPZ ' + $NombreXpz + ' no contiene ningún archivo XML.')
        }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        try {
            $xmlText = $reader.ReadToEnd()
        } finally {
            $reader.Close()
        }
    } finally {
        if ($zip) { $zip.Dispose() }
    }

    $xml = New-Object System.Xml.XmlDocument
    $xml.PreserveWhitespace = $false
    try {
        $xml.LoadXml($xmlText)
    } catch {
        throw ('El XML interno del XPZ no es un XML bien formado. Motivo: ' + $_.Exception.Message)
    }
    if ($xml.DocumentElement.LocalName -ne 'ExportFile') {
        throw ('La raiz del XML no es ExportFile; se encontro: ' + $xml.DocumentElement.LocalName)
    }

    return [pscustomobject]@{
        Xml = $xml
        Ruta = $RutaXpz
        Nombre = $NombreXpz
    }
}

function Construir-Indices {
    <#
    .SYNOPSIS
    Construye los indices de objetos del XPZ para reutilizar en el analisis.
    .DESCRIPTION
    Recorre todos los Object del XML una sola vez y construye cinco indices:
    PorFqn (unico por fullyQualifiedName, tipo Procedure preferido),
    PorNombre (todos los objetos por nombre), PorNombreCodigo (solo objetos
    con Source no vacio, para delegaciones), PorNombreDominio (solo objetos de
    tipo Domain, para resolver idBasedOn sin ambiguedad) y PorNombreAtributo
    (Items, Variables y elementos Attribute con evidencia de tipo, para resolver
    referencias de atributo). Devuelve un objeto con las cinco propiedades.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $false)][string]$ProcedureTypeGuid = '84a12160-f59b-4ad7-a683-ea4481ac23e9',
        [Parameter(Mandatory = $false)][string]$GuidTipoDominio = '00972a17-9975-449e-aab1-d26165d51393'
    )

    $porFqn = @{}
    $porNombre = @{}
    $porNombreCodigo = @{}
    $porNombreDominio = @{}
    $porNombreAtributo = @{}

    foreach ($objeto in $Xml.SelectNodes('//Object')) {
        $fqn = $objeto.GetAttribute('fullyQualifiedName')
        $nombre = $objeto.GetAttribute('name')

        if ($fqn) {
            $existente = $porFqn[$fqn]
            if (-not $existente) {
                $porFqn[$fqn] = $objeto
            } elseif ($objeto.GetAttribute('type') -eq $ProcedureTypeGuid) {
                $porFqn[$fqn] = $objeto
            }
        }

        if ($nombre) {
            if (-not $porNombre.ContainsKey($nombre)) {
                $porNombre[$nombre] = New-Object System.Collections.Generic.List[object]
            }
            $porNombre[$nombre].Add($objeto)

            if ($objeto.GetAttribute('type') -eq $GuidTipoDominio) {
                if (-not $porNombreDominio.ContainsKey($nombre)) {
                    $porNombreDominio[$nombre] = New-Object System.Collections.Generic.List[object]
                }
                $porNombreDominio[$nombre].Add($objeto)
            }

            $tieneCodigo = $false
            foreach ($part in $objeto.SelectNodes('Part')) {
                $sourceNode = $part.SelectSingleNode('Source')
                if ($sourceNode -and -not [string]::IsNullOrWhiteSpace($sourceNode.InnerText)) {
                    $tieneCodigo = $true
                    break
                }
            }
            if ($tieneCodigo) {
                if (-not $porNombreCodigo.ContainsKey($nombre)) {
                    $porNombreCodigo[$nombre] = New-Object System.Collections.Generic.List[object]
                }
                $porNombreCodigo[$nombre].Add($objeto)
            }
        }
    }

    foreach ($nodo in $Xml.SelectNodes('//Item | //Variable | //Attribute')) {
        $nombre = $nodo.GetAttribute('name')
        if (-not $nombre) { continue }
        $esAtributo = ($nodo.LocalName -eq 'Attribute')
        $tipoCustom = Obtener-Propiedad -Nodo $nodo -Nombre 'ATTCUSTOMTYPE'
        $idBasedOn = Obtener-Propiedad -Nodo $nodo -Nombre 'idBasedOn'
        $esAutorreferencia = ($idBasedOn -eq ('Attribute:' + $nombre))
        if ($esAtributo) {
            $longitudAtributo = Obtener-Propiedad -Nodo $nodo -Nombre 'Length'
            $decimalesAtributo = Obtener-Propiedad -Nodo $nodo -Nombre 'Decimals'
            if (-not $tipoCustom -and -not $idBasedOn -and -not $longitudAtributo -and -not $decimalesAtributo) { continue }
        } elseif (-not $tipoCustom -and (-not $idBasedOn -or $esAutorreferencia)) {
            continue
        }
        if (-not $porNombreAtributo.ContainsKey($nombre)) {
            $porNombreAtributo[$nombre] = New-Object System.Collections.Generic.List[object]
        }
        $porNombreAtributo[$nombre].Add($nodo)
    }

    return [pscustomobject]@{
        PorFqn = $porFqn
        PorNombre = $porNombre
        PorNombreCodigo = $porNombreCodigo
        PorNombreDominio = $porNombreDominio
        PorNombreAtributo = $porNombreAtributo
        TiposMiembroSdt = $null
        EvidenciasMiembroSdt = $null
        TiposMiembroSdtConstruido = $false
    }
}

function Obtener-Objeto {
    <#
    .SYNOPSIS
    Localiza un objeto por su atributo fullyQualifiedName exacto.
    .DESCRIPTION
    Devuelve el nodo Object unico o $null si no se encuentra.
    Lanza un error si el nombre aparece mas de una vez en el XPZ.
    Si se proporciona el indice, lo consulta en lugar de recorrer el XML.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][string]$NombreCompleto,
        [Parameter(Mandatory = $false)]$Indice
    )

    if ($Indice -and $Indice.PorFqn -and $Indice.PorFqn.ContainsKey($NombreCompleto)) {
        return $Indice.PorFqn[$NombreCompleto]
    }

    $nodos = @($Xml.SelectNodes("//Object[@fullyQualifiedName='" + $NombreCompleto + "']"))
    if ($nodos.Count -eq 0) {
        return $null
    }
    if ($nodos.Count -gt 1) {
        $procedimientos = @($nodos | Where-Object { $_.GetAttribute('type') -eq '84a12160-f59b-4ad7-a683-ea4481ac23e9' })
        if ($procedimientos.Count -eq 1) {
            return $procedimientos[0]
        }
        throw ('El objeto ' + $NombreCompleto + ' aparece ' + $nodos.Count + ' veces en el XPZ sin un unico Procedure.')
    }
    return $nodos[0]
}

function Obtener-ReglaParm {
    <#
    .SYNOPSIS
    Devuelve el texto de la regla parm(...) de un objeto Procedure, o $null si no la tiene.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Objeto
    )

    foreach ($part in $Objeto.SelectNodes('Part')) {
        $source = $part.SelectSingleNode('Source')
        if ($source -and $source.InnerText -match '(?i)\bparm\s*\(') {
            return $source.InnerText
        }
    }
    return $null
}

function Confirmar-Wrapper {
    <#
    .SYNOPSIS
    Confirma que el objeto es un wrapper HTTP activo segun analisisXPZ.md seccion 1.
    .DESCRIPTION
    Valida tipo Procedure, IsMain=True y CALL_PROTOCOL=HTTP. Si alguna condicion
    no se cumple, lanza un error que detiene el analisis sin generar el documento.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Objeto,
        [Parameter(Mandatory = $false)][string]$GuidTipoProcedure = '84a12160-f59b-4ad7-a683-ea4481ac23e9'
    )

    $tipoProcedure = ($Objeto.GetAttribute('type') -eq $GuidTipoProcedure)
    $esMain = ($Objeto.SelectSingleNode("Properties/Property[Name='IsMain' and Value='True']") -ne $null)
    $protocoloHttp = ($Objeto.SelectSingleNode("Properties/Property[Name='CALL_PROTOCOL' and Value='HTTP']") -ne $null)

    if (-not ($tipoProcedure -and $esMain -and $protocoloHttp)) {
        $fallas = New-Object System.Collections.Generic.List[string]
        if (-not $tipoProcedure) { $fallas.Add('tipo Procedure') }
        if (-not $esMain) { $fallas.Add('IsMain=True') }
        if (-not $protocoloHttp) { $fallas.Add('CALL_PROTOCOL=HTTP') }
        throw ('El wrapper ' + $Objeto.GetAttribute('fullyQualifiedName') + ' no cumple las condiciones requeridas: ' + ($fallas -join ', ') + '.')
    }
    return $true
}

function Obtener-DelegacionUnica {
    <#
    .SYNOPSIS
    Localiza la delegacion unica del wrapper al programa principal.
    .DESCRIPTION
    Recorre el Source del wrapper buscando llamadas a procedimientos. Primero busca
    la firma completa parm(in:&APIGLMRequestIn, out:&APIGLMResponse). Si no la
    encuentra, busca procedimientos con out:&APIGLMResponse que no mencionen
    APIGLMRequestIn en ninguna direccion (para servicios sin parametros de entrada).
    Si se proporciona el indice, lo usa en lugar de recorrer el XML.
    Devuelve el fullyQualifiedName del programa principal. Si no hay delegacion
    unica, lanza un error que detiene el analisis sin generar el documento.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Wrapper,
        [Parameter(Mandatory = $false)]$Indice
    )

    $porNombreCompleto = @{}
    $porNombre = @{}
    if ($Indice) {
        $porNombreCompleto = $Indice.PorFqn
        if ($Indice.PorNombreCodigo) {
            $porNombre = $Indice.PorNombreCodigo
        } else {
            $porNombre = @{}
        }
    } else {
        foreach ($objeto in $Xml.SelectNodes('//Object')) {
            $nombreCompleto = $objeto.GetAttribute('fullyQualifiedName')
            $nombre = $objeto.GetAttribute('name')
            $tieneCodigo = $false
            foreach ($part in $objeto.SelectNodes('Part')) {
                $sourceNode = $part.SelectSingleNode('Source')
                if ($sourceNode -and -not [string]::IsNullOrWhiteSpace($sourceNode.InnerText)) {
                    $tieneCodigo = $true
                    break
                }
            }
            if (-not $tieneCodigo) { continue }
            if ($nombreCompleto) {
                if (-not $porNombreCompleto.ContainsKey($nombreCompleto)) {
                    $porNombreCompleto[$nombreCompleto] = $objeto
                } elseif ($objeto.GetAttribute('type') -eq '84a12160-f59b-4ad7-a683-ea4481ac23e9') {
                    $porNombreCompleto[$nombreCompleto] = $objeto
                }
            }
            if ($nombre) {
                if (-not $porNombre.ContainsKey($nombre)) {
                    $porNombre[$nombre] = New-Object System.Collections.Generic.List[object]
                }
                $porNombre[$nombre].Add($objeto)
            }
        }
    }

    $source = $null
    foreach ($part in $Wrapper.SelectNodes('Part')) {
        $sourceNode = $part.SelectSingleNode('Source')
        if ($sourceNode -and -not [string]::IsNullOrWhiteSpace($sourceNode.InnerText)) {
            $source = $sourceNode.InnerText
            break
        }
    }
    if (-not $source) {
        throw ('El wrapper ' + $Wrapper.GetAttribute('fullyQualifiedName') + ' no tiene un Source no vacio.')
    }

    $palabrasReservadas = @('if', 'for', 'while', 'do', 'case', 'switch', 'catch', 'return', 'new', 'format')
    $infraestructura = @('ProcesarRequest', 'GenerarAPIGLMResponse', 'GenerarHttpResponse', 'GenerarHttpError', 'PHacerRollback', 'PHacerCommit', 'InsLogEventos', 'InsLogs')
    $patronLlamada = [regex]::new('\b([A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*)\s*\(')
    $patronDelegacion = [regex]::new('&APIGLMResponse\s*=\s*([A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*)\s*\(')
    $delegacionEscrita = $null
    $coincidenciaDelegacion = $patronDelegacion.Match($source)
    if ($coincidenciaDelegacion.Success) {
        $delegacionEscrita = $coincidenciaDelegacion.Groups[1].Value
        $ultimoSegmentoDelegacion = $delegacionEscrita.Split('.')[-1]
        if ($infraestructura -contains $ultimoSegmentoDelegacion) { $delegacionEscrita = $null }
    }
    $delegacionesTier1 = New-Object System.Collections.Generic.List[string]
    $delegacionesTier2 = New-Object System.Collections.Generic.List[string]
    $vistos = @{}
    foreach ($coincidencia in $patronLlamada.Matches($source)) {
        $llamada = $coincidencia.Groups[1].Value
        $ultimoSegmento = $llamada.Split('.')[-1]
        if ($palabrasReservadas -contains $ultimoSegmento.ToLowerInvariant()) { continue }
        $objeto = $null
        if ($llamada.Contains('.')) {
            if ($porNombreCompleto.ContainsKey($llamada)) { $objeto = $porNombreCompleto[$llamada] }
            if (-not $objeto) {
                $ultimoSegmento = $llamada.Split('.')[-1]
                if ($ultimoSegmento -in @('Udp', 'Call', 'St', 'Upd')) {
                    $nombreBase = $llamada.Substring(0, $llamada.Length - $ultimoSegmento.Length - 1)
                    if ($porNombre.ContainsKey($nombreBase) -and $porNombre[$nombreBase].Count -eq 1) {
                        $objeto = $porNombre[$nombreBase][0]
                    } elseif ($porNombre.ContainsKey($nombreBase)) {
                        $moduloWrapper = $Wrapper.GetAttribute('fullyQualifiedName')
                        $ultimoPunto = $moduloWrapper.LastIndexOf('.')
                        if ($ultimoPunto -gt 0) { $moduloWrapper = $moduloWrapper.Substring(0, $ultimoPunto) }
                        $candidatos = @($porNombre[$nombreBase] | Where-Object { $_.GetAttribute('fullyQualifiedName') -like "$moduloWrapper.*" })
                        if ($candidatos.Count -eq 1) { $objeto = $candidatos[0] }
                    }
                }
            }
        } else {
            if ($porNombre.ContainsKey($llamada) -and $porNombre[$llamada].Count -eq 1) { $objeto = $porNombre[$llamada][0] }
            elseif ($porNombre.ContainsKey($llamada)) {
                $moduloWrapper = $Wrapper.GetAttribute('fullyQualifiedName')
                $ultimoPunto = $moduloWrapper.LastIndexOf('.')
                if ($ultimoPunto -gt 0) { $moduloWrapper = $moduloWrapper.Substring(0, $ultimoPunto) }
                $candidatos = @($porNombre[$llamada] | Where-Object { $_.GetAttribute('fullyQualifiedName') -like "$moduloWrapper.*" })
                if ($candidatos.Count -eq 1) { $objeto = $candidatos[0] }
            }
        }
        if (-not $objeto) { continue }
        $nombreCompletoObjeto = $objeto.GetAttribute('fullyQualifiedName')
        if ($vistos.ContainsKey($nombreCompletoObjeto)) { continue }
        $vistos[$nombreCompletoObjeto] = $true
        $nombreObjeto = $objeto.GetAttribute('name')
        $ultimoSegmentoObjeto = $nombreObjeto.Split('.')[-1]
        if ($infraestructura -contains $ultimoSegmentoObjeto) { continue }
        $parm = Obtener-ReglaParm -Objeto $objeto
        $tieneOut = $parm -and ($parm -match '(?i)out\s*:\s*&\s*APIGLMResponse')
        if (-not $tieneOut) { continue }
        $tieneIn = $parm -match '(?i)in\s*:\s*&\s*APIGLMRequestIn'
        $mencionaRequestIn = $parm -match '(?i)APIGLMRequestIn'
        if ($tieneIn) {
            $delegacionesTier1.Add($nombreCompletoObjeto)
        } elseif (-not $mencionaRequestIn) {
            $delegacionesTier2.Add($nombreCompletoObjeto)
        }
    }

    if ($delegacionesTier1.Count -eq 1) { $delegaciones = $delegacionesTier1 }
    elseif ($delegacionesTier2.Count -eq 1) { $delegaciones = $delegacionesTier2 }
    else { $delegaciones = @() }
    if ($delegaciones.Count -eq 0) {
        if ($delegacionEscrita) {
            $nombreBase = $delegacionEscrita
            $ultimoSegmento = $nombreBase.Split('.')[-1]
            if ($ultimoSegmento -in @('Udp', 'Call', 'St', 'Upd')) {
                $nombreBase = $nombreBase.Substring(0, $nombreBase.Length - $ultimoSegmento.Length - 1)
            }
            $existe = $false
            if ($porNombreCompleto.ContainsKey($delegacionEscrita)) { $existe = $true }
            elseif ($porNombre.ContainsKey($nombreBase)) { $existe = $true }
        if (-not $existe) {
            throw ('El programa principal ' + $nombreBase + ' no está exportado en el XPZ configurado. No puede inferirse.')
        }
        }
        return $null
    }
    if ($delegaciones.Count -gt 1) {
        throw ('Se identificaron varias delegaciones candidatas en el wrapper ' + $Wrapper.GetAttribute('fullyQualifiedName') + ': ' + ($delegaciones -join ', ') + '. No se genera el documento.')
    }
    return $delegaciones[0]
}

function Obtener-Propiedad {
    <#
    .SYNOPSIS
    Devuelve el valor de una propiedad Name/Value de un nodo del XPZ, o $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Nodo,
        [Parameter(Mandatory = $true)][string]$Nombre
    )

    $propiedad = $Nodo.SelectSingleNode("Properties/Property[Name='" + $Nombre + "']")
    if ($propiedad) {
        return $propiedad.SelectSingleNode('Value').InnerText
    }
    return $null
}

function Obtener-Variable {
    <#
    .SYNOPSIS
    Localiza una variable declarada en el programa principal por su atributo Name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$ProgramaPrincipal,
        [Parameter(Mandatory = $true)][string]$Nombre
    )

    foreach ($part in $ProgramaPrincipal.SelectNodes('Part')) {
        if ($part.SelectSingleNode('Source')) { continue }
        foreach ($hijo in $part.ChildNodes) {
            if ($hijo.NodeType -ne 'Element') { continue }
            if ($hijo.Name -eq 'Properties') { continue }
            if ($hijo.GetAttribute('Name') -eq $Nombre) {
                return $hijo
            }
        }
    }
    return $null
}

function Obtener-Sdt {
    <#
    .SYNOPSIS
    Localiza el objeto SDT por nombre, opcionalmente filtrando por modulo.
    Si se proporciona el indice, lo consulta en lugar de recorrer el XML.
    Devuelve el nodo Object unico o $null si no se localiza de forma inequivoca.
    .DESCRIPTION
    Resolucion de SDT homonimos: una referencia sin calificador de modulo con
    varios candidatos se resuelve al SDT de la raiz (aquel cuyo fullyQualifiedName
    coincide exactamente con el nombre). Si la referencia califica el modulo, esa
    forma prevalece y no aplica el respaldo a la raiz.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][string]$NombreSdt,
        [Parameter(Mandatory = $false)][string]$Modulo = '',
        [Parameter(Mandatory = $false)]$Indice
    )

    $candidatos = @()
    if ($Indice -and $Indice.PorNombre -and $Indice.PorNombre.ContainsKey($NombreSdt)) {
        $candidatos = [array]$Indice.PorNombre[$NombreSdt]
    } else {
        $candidatos = @($Xml.SelectNodes("//Object[@name='" + $NombreSdt + "']"))
    }
    if ($candidatos.Count -eq 0 -and $NombreSdt -match '\.') {
        $partesRuta = @($NombreSdt.Split('.'))
        $nodoActual = Obtener-Sdt -Xml $Xml -NombreSdt $partesRuta[0] -Modulo $Modulo -Indice $Indice
        if ($nodoActual) {
            for ($i = 1; $i -lt $partesRuta.Count; $i++) {
                $segmento = $partesRuta[$i]
                $siguiente = $null
                foreach ($hijo in @(Obtener-HijosSdt -Sdt $nodoActual)) {
                    $nombreHijo = $hijo.GetAttribute('name')
                    if (-not $nombreHijo) { $nombreHijo = $hijo.GetAttribute('Name') }
                    if ($nombreHijo -eq $segmento) { $siguiente = $hijo; break }
                }
                if (-not $siguiente) {
                    foreach ($hijo in @(Obtener-HijosSdt -Sdt $nodoActual)) {
                        if ($hijo.LocalName -ne 'Level') { continue }
                        $infoHijo = $hijo.SelectSingleNode('LevelInfo')
                        $itemColeccionHijo = ''
                        if ($infoHijo) { $itemColeccionHijo = Obtener-Propiedad -Nodo $infoHijo -Nombre 'idCollectionItemName' }
                        if ($itemColeccionHijo -eq $segmento) { $siguiente = $hijo; break }
                    }
                }
                if (-not $siguiente -and $nodoActual.LocalName -eq 'Object') {
                    $raiz = $null
                    foreach ($part in $nodoActual.SelectNodes('Part')) {
                        $hijosRaiz = @($part.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -ne 'Properties' })
                        if ($hijosRaiz.Count -gt 0) { $raiz = $hijosRaiz[0]; break }
                    }
                    if ($raiz) {
                        $itemColeccion = ''
                        $info = $raiz.SelectSingleNode('LevelInfo')
                        if ($info) { $itemColeccion = Obtener-Propiedad -Nodo $info -Nombre 'idCollectionItemName' }
                        $nombreRaiz = $raiz.GetAttribute('Name')
                        if (-not $nombreRaiz) { $nombreRaiz = $raiz.GetAttribute('name') }
                        if ($segmento -eq $itemColeccion -or $segmento -eq $nombreRaiz) { $siguiente = $raiz }
                    }
                }
                if (-not $siguiente) { return $null }
                $nodoActual = $siguiente
            }
            return $nodoActual
        }
        return $null
    }
    if ($candidatos.Count -eq 0) { return $null }
    if ($Modulo) {
        $conModulo = @($candidatos | Where-Object { $_.GetAttribute('fullyQualifiedName').StartsWith($Modulo + '.') })
        if ($conModulo.Count -eq 1) { return $conModulo[0] }
    }
    if ($candidatos.Count -eq 1) { return $candidatos[0] }
    if (-not $Modulo) {
        $raiz = @($candidatos | Where-Object { $_.GetAttribute('fullyQualifiedName') -eq $NombreSdt })
        if ($raiz.Count -eq 1) { return $raiz[0] }
    }
    return $null
}

function Obtener-HijosSdt {
    <#
    .SYNOPSIS
    Devuelve los campos directos del item raiz de un SDT o de un Level inline.
    .DESCRIPTION
    Para Object (SDT externo): navega Part -> contenedor -> hijos (Item y Level),
    excluyendo el item raiz y los nodos LevelInfo/Properties.
    Para Level (nivel inline): devuelve directamente los hijos Item y Level,
    excluyendo LevelInfo y Properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Sdt
    )

    $nombreSdt = $Sdt.GetAttribute('name')
    if (-not $nombreSdt) { $nombreSdt = $Sdt.GetAttribute('Name') }

    $nodos = @()

    if ($Sdt.LocalName -eq 'Object') {
        foreach ($part in $Sdt.SelectNodes('Part')) {
            $hijos = @($part.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -ne 'Properties' })
            if ($hijos.Count -eq 0) { continue }
            $contenedor = $hijos[0]
            $campos = @($contenedor.ChildNodes | Where-Object {
                $_.NodeType -eq 'Element' -and $_.LocalName -ne 'Properties' -and $_.LocalName -ne 'LevelInfo' -and (
                    ($_.LocalName -eq 'Item' -and $_.GetAttribute('name') -and $_.GetAttribute('name') -ne $nombreSdt) -or
                    ($_.LocalName -eq 'Level' -and $_.GetAttribute('Name') -and $_.GetAttribute('Name') -ne $nombreSdt)
                )
            })
            if ($campos.Count -gt 0) { $nodos = @($campos) }
        }
        return $nodos
    }

    if ($Sdt.LocalName -eq 'Level') {
        return @($Sdt.ChildNodes | Where-Object {
            $_.NodeType -eq 'Element' -and $_.LocalName -ne 'Properties' -and $_.LocalName -ne 'LevelInfo' -and (
                ($_.LocalName -eq 'Item' -and $_.GetAttribute('name')) -or
                ($_.LocalName -eq 'Level' -and $_.GetAttribute('Name'))
            )
        })
    }

    return @()
}

function Obtener-NombreCampoSdt {
    param([Parameter(Mandatory = $true)][System.Xml.XmlNode]$Nodo)
    $nombre = $Nodo.GetAttribute('name')
    if (-not $nombre) { $nombre = $Nodo.GetAttribute('Name') }
    if (-not $nombre -and $Nodo.LocalName -eq 'Level') {
        $info = $Nodo.SelectSingleNode('LevelInfo')
        if ($info) { $nombre = Obtener-Propiedad -Nodo $info -Nombre 'idCollectionItemName' }
    }
    return $nombre
}

function Resolver-SdtItemRuta {
    <#
    Resuelve un miembro por ruta JSON dentro de un SDT, siguiendo SDT anidados
    e Inline Levels. No copia tipos de campos homónimos: cada salto se hace
    sobre el nodo que corresponde a la ruta solicitada.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Sdt,
        [Parameter(Mandatory = $true)][string]$Ruta,
        [Parameter(Mandatory = $false)]$Indice
    )

    $actual = $Sdt
    $segmentos = @($Ruta -split '\.' | Where-Object { $_ })
    for ($i = 0; $i -lt $segmentos.Count; $i++) {
        $segmento = $segmentos[$i]
        $hijo = @((Obtener-HijosSdt -Sdt $actual) | Where-Object { (Obtener-NombreCampoSdt -Nodo $_) -eq $segmento }) | Select-Object -First 1
        if (-not $hijo) { return $null }
        if ($i -eq $segmentos.Count - 1) { return $hijo }

        $datos = Obtener-DatosTipo -Xml $Xml -Nodo $hijo -Indice $Indice
        if (-not $datos.EsEstructura) { return $null }
        if ($hijo.LocalName -eq 'Level') {
            $actual = $hijo
        } else {
            $actual = Obtener-Sdt -Xml $Xml -NombreSdt $datos.NombreSdt -Modulo $datos.ModuloSdt -Indice $Indice
        }
        if (-not $actual) { return $null }
    }
    return $null
}

function Resolver-TipoMiembro {
    <# Resuelve &Variable.RutaJson con la declaración real de la variable y del SDT. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][string]$Variable,
        [Parameter(Mandatory = $true)][string]$Ruta,
        [Parameter(Mandatory = $false)][object[]]$Nodos = @(),
        [Parameter(Mandatory = $false)]$Indice
    )

    foreach ($nodo in $Nodos) {
        $variableNodo = $null
        try { $variableNodo = Obtener-Variable -ProgramaPrincipal $nodo -Nombre $Variable } catch { $variableNodo = $null }
        if (-not $variableNodo) { continue }
        $datosVariable = Obtener-DatosTipo -Xml $Xml -Nodo $variableNodo -Indice $Indice
        if (-not $datosVariable.EsEstructura) { continue }
        $sdt = Obtener-Sdt -Xml $Xml -NombreSdt $datosVariable.NombreSdt -Modulo $datosVariable.ModuloSdt -Indice $Indice
        if (-not $sdt) { continue }
        $item = Resolver-SdtItemRuta -Xml $Xml -Sdt $sdt -Ruta $Ruta -Indice $Indice
        if (-not $item) { continue }
        $datos = Obtener-DatosTipo -Xml $Xml -Nodo $item -Indice $Indice
        $tipo = Convertir-TipoCanonico -DatosTipo $datos -NombreCampo (Split-Path $Ruta -Leaf)
        if ($tipo) { return $tipo }
    }
    return ''
}

function Obtener-IdentidadSdtVariable {
    <# Convierte la declaración sdt: de una variable en SDT raíz y ruta interna exacta. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Variable,
        [Parameter(Mandatory = $false)]$Indice
    )

    $tipoCustom = Obtener-Propiedad -Nodo $Variable -Nombre 'ATTCUSTOMTYPE'
    $coincidencia = [regex]::Match($tipoCustom, '^sdt:(.+)$')
    if (-not $coincidencia.Success) { return $null }
    $referencia = $coincidencia.Groups[1].Value.Trim()
    $partesReferencia = @($referencia -split ',', 2)
    $nombreSdt = $partesReferencia[0].Trim()
    $modulo = $(if ($partesReferencia.Count -gt 1) { $partesReferencia[1].Trim() } else { '' })
    $segmentos = @($nombreSdt -split '\.' | Where-Object { $_ })
    if ($segmentos.Count -eq 0) { return $null }

    $sdtRaiz = Obtener-Sdt -Xml $Xml -NombreSdt $segmentos[0] -Modulo $modulo -Indice $Indice
    if (-not $sdtRaiz -or $sdtRaiz.LocalName -ne 'Object') { return $null }
    $ruta = New-Object System.Collections.Generic.List[string]
    $actual = $sdtRaiz
    for ($indiceSegmento = 1; $indiceSegmento -lt $segmentos.Count; $indiceSegmento++) {
        $segmento = $segmentos[$indiceSegmento]
        $siguiente = $null
        foreach ($hijo in @(Obtener-HijosSdt -Sdt $actual)) {
            $nombreHijo = Obtener-NombreCampoSdt -Nodo $hijo
            $nombreItemColeccion = ''
            if ($hijo.LocalName -eq 'Level') {
                $infoHijo = $hijo.SelectSingleNode('LevelInfo')
                if ($infoHijo) { $nombreItemColeccion = Obtener-Propiedad -Nodo $infoHijo -Nombre 'idCollectionItemName' }
            }
            if ($nombreHijo -eq $segmento -or $nombreItemColeccion -eq $segmento) {
                $siguiente = $hijo
                [void]$ruta.Add($nombreHijo)
                break
            }
        }
        if (-not $siguiente) { return $null }
        if ($siguiente.LocalName -eq 'Level') {
            $actual = $siguiente
        } else {
            $datosSiguiente = Obtener-DatosTipo -Xml $Xml -Nodo $siguiente -Indice $Indice
            if (-not $datosSiguiente.EsEstructura) { return $null }
            $actual = Obtener-Sdt -Xml $Xml -NombreSdt $datosSiguiente.NombreSdt -Modulo $datosSiguiente.ModuloSdt -Indice $Indice
            if (-not $actual) { return $null }
        }
    }

    return [pscustomobject]@{
        SdtFqn = $sdtRaiz.GetAttribute('fullyQualifiedName')
        PrefijoRuta = ($ruta -join '.')
    }
}

function Obtener-ClaveMiembroSdt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][object]$Identidad,
        [Parameter(Mandatory = $true)][string]$Ruta,
        [Parameter(Mandatory = $false)]$Indice
    )

    $rutaCompleta = $(if ($Identidad.PrefijoRuta) { $Identidad.PrefijoRuta + '.' + $Ruta } else { $Ruta })
    return ($Identidad.SdtFqn.ToLowerInvariant() + '|' + $rutaCompleta.ToLowerInvariant())
}

function Agregar-EvidenciaTipoMiembroSdt {
    param(
        [Parameter(Mandatory = $true)]$Tipos,
        [Parameter(Mandatory = $true)]$Evidencias,
        [Parameter(Mandatory = $true)][string]$Clave,
        [Parameter(Mandatory = $true)][string]$Tipo,
        [Parameter(Mandatory = $true)][string]$Origen,
        [Parameter(Mandatory = $true)][string]$Sentencia
    )
    if (-not $Clave -or -not $Tipo -or $Tipo -match '^PENDIENTE') { return }
    if (-not $Tipos.ContainsKey($Clave)) { $Tipos[$Clave] = New-Object System.Collections.Generic.List[string] }
    if (-not $Evidencias.ContainsKey($Clave)) { $Evidencias[$Clave] = New-Object System.Collections.Generic.List[object] }
    if (-not $Tipos[$Clave].Contains($Tipo)) { $Tipos[$Clave].Add($Tipo) }
    $Evidencias[$Clave].Add([pscustomobject]@{ Tipo = $Tipo; Origen = $Origen; Sentencia = $Sentencia.Trim() })
}

function Construir-IndiceTiposMiembroSdt {
    <# Indexa usos del mismo SDT y ruta exacta; los tipos se resuelven bajo demanda. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)]$Indice
    )

    if ($Indice.TiposMiembroSdtConstruido) { return }
    $usos = @{}
    $objetosVistos = @{}
    $identidadesPorDeclaracion = @{}
    foreach ($objeto in @($Indice.PorFqn.Values)) {
        $fqn = $objeto.GetAttribute('fullyQualifiedName')
        if (-not $fqn -or $objetosVistos.ContainsKey($fqn)) { continue }
        $objetosVistos[$fqn] = $true
        $source = $null
        try { $source = Obtener-Source -ProgramaPrincipal $objeto } catch { $source = $null }
        if (-not $source) { continue }

        $identidades = @{}
        foreach ($variable in $objeto.SelectNodes('.//Variable')) {
            $nombreVariable = $variable.GetAttribute('Name')
            if (-not $nombreVariable) { continue }
            $tipoDeclarado = Obtener-Propiedad -Nodo $variable -Nombre 'ATTCUSTOMTYPE'
            if (-not $tipoDeclarado -or $tipoDeclarado -notmatch '^sdt:') { continue }
            $identidad = $null
            if ($identidadesPorDeclaracion.ContainsKey($tipoDeclarado)) {
                $identidad = $identidadesPorDeclaracion[$tipoDeclarado]
            } else {
                $identidad = Obtener-IdentidadSdtVariable -Xml $Xml -Variable $variable -Indice $Indice
                $identidadesPorDeclaracion[$tipoDeclarado] = $identidad
            }
            if ($identidad) { $identidades[$nombreVariable] = $identidad }
        }
        if ($identidades.Count -eq 0) { continue }

        $sourceLimpio = Obtener-SourceLimpio -Source $source
        $patronAsignacion = [regex]::new('(?m)^\s*&([A-Za-z_][A-Za-z0-9_]*)(?:\.([A-Za-z_][A-Za-z0-9_.]*))?\s*=\s*(.+?)\s*$')
        foreach ($asignacion in $patronAsignacion.Matches($sourceLimpio)) {
            $variableIzquierda = $asignacion.Groups[1].Value
            $rutaIzquierda = $asignacion.Groups[2].Value
            $rhsRaw = $asignacion.Groups[3].Value.Trim()
            $sentencia = $asignacion.Value.Trim()

            if ($rutaIzquierda -and $identidades.ContainsKey($variableIzquierda)) {
                $claveIzquierda = Obtener-ClaveMiembroSdt -Xml $Xml -Identidad $identidades[$variableIzquierda] -Ruta $rutaIzquierda -Indice $Indice
                if ($claveIzquierda) {
                    if (-not $usos.ContainsKey($claveIzquierda)) { $usos[$claveIzquierda] = New-Object System.Collections.Generic.List[object] }
                    $usos[$claveIzquierda].Add([pscustomobject]@{
                        Direccion = 'DesdeRhs'
                        Objeto = $objeto
                        Origen = $fqn
                        Sentencia = $sentencia
                        Rhs = $rhsRaw
                    })
                }
            }

            $rhsNormalizado = Normalizar-Rhs -Texto $rhsRaw
            $miembroDerecho = [regex]::Match($rhsNormalizado, '^&([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_.]*)$')
            if (-not $miembroDerecho.Success) { continue }
            $variableDerecha = $miembroDerecho.Groups[1].Value
            $rutaDerecha = $miembroDerecho.Groups[2].Value
            if (-not $identidades.ContainsKey($variableDerecha)) { continue }
            $claveDerecha = Obtener-ClaveMiembroSdt -Xml $Xml -Identidad $identidades[$variableDerecha] -Ruta $rutaDerecha -Indice $Indice
            if (-not $claveDerecha) { continue }
            if (-not $usos.ContainsKey($claveDerecha)) { $usos[$claveDerecha] = New-Object System.Collections.Generic.List[object] }
            $usos[$claveDerecha].Add([pscustomobject]@{
                Direccion = 'HaciaDestino'
                Objeto = $objeto
                Origen = $fqn
                Sentencia = $sentencia
                VariableDestino = $variableIzquierda
                RutaDestino = $rutaIzquierda
            })
        }
    }
    $Indice | Add-Member -MemberType NoteProperty -Name 'UsosMiembroSdt' -Value $usos -Force
    $Indice.TiposMiembroSdt = @{}
    $Indice.EvidenciasMiembroSdt = @{}
    $Indice.TiposMiembroSdtConstruido = $true
}

function Resolver-TipoMiembroSdtGlobal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][string]$SdtFqn,
        [Parameter(Mandatory = $true)][string]$RutaSdt,
        [Parameter(Mandatory = $false)]$Indice
    )
    if (-not $Indice -or -not $SdtFqn -or -not $RutaSdt) { return '' }
    Construir-IndiceTiposMiembroSdt -Xml $Xml -Indice $Indice
    $clave = $SdtFqn.ToLowerInvariant() + '|' + $RutaSdt.ToLowerInvariant()
    if (-not $Indice.TiposMiembroSdt.ContainsKey($clave)) {
        if (-not $Indice.UsosMiembroSdt.ContainsKey($clave)) {
            $Indice.TiposMiembroSdt[$clave] = New-Object System.Collections.Generic.List[string]
            $Indice.EvidenciasMiembroSdt[$clave] = New-Object System.Collections.Generic.List[object]
            return ''
        }
        $tipos = @{}
        $evidencias = @{}
        foreach ($uso in $Indice.UsosMiembroSdt[$clave].ToArray()) {
            $tipo = ''
            if ($uso.Direccion -eq 'DesdeRhs') {
                $tipo = Resolver-TipoRhs -Xml $Xml -Rhs $uso.Rhs -Nodos @($uso.Objeto) -Indice $Indice
            } elseif ($uso.Direccion -eq 'HaciaDestino') {
                if ($uso.RutaDestino) {
                    $tipo = Resolver-TipoMiembro -Xml $Xml -Variable $uso.VariableDestino -Ruta $uso.RutaDestino -Nodos @($uso.Objeto) -Indice $Indice
                } else {
                    $tipo = Resolver-TipoVariable -Xml $Xml -Variable $uso.VariableDestino -Nodos @($uso.Objeto) -Indice $Indice
                }
            }
            if ($tipo) {
                Agregar-EvidenciaTipoMiembroSdt -Tipos $tipos -Evidencias $evidencias -Clave $clave -Tipo $tipo -Origen $uso.Origen -Sentencia $uso.Sentencia
            }
        }
        $Indice.TiposMiembroSdt[$clave] = New-Object System.Collections.Generic.List[string]
        if ($tipos.ContainsKey($clave)) {
            foreach ($tipoResuelto in $tipos[$clave].ToArray()) { $Indice.TiposMiembroSdt[$clave].Add($tipoResuelto) }
        }
        $Indice.EvidenciasMiembroSdt[$clave] = New-Object System.Collections.Generic.List[object]
        if ($evidencias.ContainsKey($clave)) {
            foreach ($evidencia in $evidencias[$clave].ToArray()) { $Indice.EvidenciasMiembroSdt[$clave].Add($evidencia) }
        }
    }
    $tipos = @($Indice.TiposMiembroSdt[$clave] | Select-Object -Unique)
    if ($tipos.Count -eq 1) { return $tipos[0] }
    return ''
}

function Obtener-EvidenciaMiembroSdtGlobal {
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][string]$SdtFqn,
        [Parameter(Mandatory = $true)][string]$RutaSdt,
        [Parameter(Mandatory = $false)]$Indice
    )
    if (-not $Indice -or -not $SdtFqn -or -not $RutaSdt) { return @() }
    Construir-IndiceTiposMiembroSdt -Xml $Xml -Indice $Indice
    $clave = $SdtFqn.ToLowerInvariant() + '|' + $RutaSdt.ToLowerInvariant()
    if ($Indice.EvidenciasMiembroSdt.ContainsKey($clave)) { return $Indice.EvidenciasMiembroSdt[$clave].ToArray() }
    return @()
}

function Resolver-Metodo {
    <#
    .SYNOPSIS
    Resuelve el metodo HTTP segun analisisXPZ.md seccion 2.
    .DESCRIPTION
    POST cuando el programa principal deserializa APIGLMRequestIn.Body con FromJson;
    GET cuando usa QueryParams o no recibe parametros funcionales.
    Si combina ambas fuentes, lanza un error que detiene el analisis.
    Reconoce llamadas FromJson multilinea.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source
    )

    $esPost = $false
    $spansFromJson = Obtener-SpansLlamada -Source $Source -PatronNombre '&[A-Za-z_][A-Za-z0-9_]*\s*\.FromJson'
    foreach ($span in $spansFromJson) {
        if ($span.Texto -match '(?i)&APIGLMRequestIn\.Body') {
            $esPost = $true
            break
        }
    }
    $esGet = $Source -match '(?i)&APIGLMRequestIn\.QueryParams'
    if ($esPost -and $esGet) {
        throw 'El programa principal combina QueryParams y FromJson sobre Body; el metodo no puede resolverse. No se genera el documento.'
    }
    if ($esPost) { return 'POST' }

    $esFromJsonQuery = $Source -match '&[A-Za-z_][A-Za-z0-9_]*\s*\.FromJson\s*\(\s*&[A-Za-z_][A-Za-z0-9_]*\.Item\s*\('
    if ($esFromJsonQuery) {
        throw 'Metodo ambiguo: el programa combina QueryParams con FromJson de una estructura en una posicion de la URL; no es compatible con GET. No se genera el documento.'
    }
    return 'GET'
}

function Resolver-EntradaGet {
    <#
    .SYNOPSIS
    Resuelve la entrada GET por posiciones de QueryParams (analisisXPZ.md seccion 2).
    .DESCRIPTION
    Localiza el parser posicional ObtenerParametrosQueryParams(&APIGLMRequestIn.QueryParams)
    y documenta las variables asignadas desde cada posicion, conservando orden y posiciones.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source
    )

    $entrada = New-Object System.Collections.Generic.List[object]
    $patronParser = [regex]::new('&([A-Za-z_][A-Za-z0-9_]*)\s*=\s*[A-Za-z_][A-Za-z0-9_.]*\(\s*&APIGLMRequestIn\.QueryParams')
    $coincidenciaParser = $patronParser.Match($Source)
    if (-not $coincidenciaParser.Success) {
        return $entrada.ToArray()
    }
    $variableColeccion = $coincidenciaParser.Groups[1].Value
    $patronPosicion = [regex]::new('&([A-Za-z_][A-Za-z0-9_]*)\s*=\s*&' + [regex]::Escape($variableColeccion) + '\.Item\(\s*(\d+)\s*\)')
    foreach ($coincidencia in $patronPosicion.Matches($Source)) {
        $posicion = [int]$coincidencia.Groups[2].Value
        $variable = $coincidencia.Groups[1].Value
        $existe = $false
        foreach ($item in $entrada) {
            if ($item.Posicion -eq $posicion) { $existe = $true; break }
        }
        if (-not $existe) {
            $entrada.Add([pscustomobject]@{ Posicion = $posicion; Campo = $variable })
        }
    }
    return @($entrada | Sort-Object Posicion)
}

function Resolver-EntradaPost {
    <#
    .SYNOPSIS
    Resuelve la entrada POST desde el SDT deserializado con FromJson (analisisXPZ.md seccion 2).
    .DESCRIPTION
    Identifica la variable destino de FromJson sobre APIGLMRequestIn.Body, localiza su SDT
    completo en el XPZ y lo devuelve junto con sus campos directos y nombres JSON.
    Reconoce llamadas FromJson multilinea.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$ProgramaPrincipal,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $false)]$Indice
    )

    $spanBody = $null
    $spansFromJson = Obtener-SpansLlamada -Source $Source -PatronNombre '&[A-Za-z_][A-Za-z0-9_]*\s*\.FromJson'
    foreach ($span in $spansFromJson) {
        if ($span.Texto -match '(?i)&APIGLMRequestIn\.Body') {
            $spanBody = $span
            break
        }
    }
    if (-not $spanBody) {
        throw 'El programa principal no deserializa APIGLMRequestIn.Body mediante FromJson. No se genera el documento.'
    }
    $coincidenciaVariable = [regex]::Match($spanBody.Texto, '&([A-Za-z_][A-Za-z0-9_]*)\s*\.FromJson')
    if (-not $coincidenciaVariable.Success) {
        throw 'No se identifico la variable destino de FromJson en el programa principal.'
    }
    $variableSdt = $coincidenciaVariable.Groups[1].Value
    $variable = Obtener-Variable -ProgramaPrincipal $ProgramaPrincipal -Nombre $variableSdt
    if (-not $variable) {
        throw ('No se encontro la variable ' + $variableSdt + ' en el programa principal.')
    }
    $tipo = Obtener-Propiedad -Nodo $variable -Nombre 'ATTCUSTOMTYPE'
    $partidaSdt = [regex]::Match($tipo, '^sdt:(.+)$')
    if (-not $partidaSdt.Success) {
        throw ('La variable ' + $variableSdt + ' no apunta a un SDT. No se genera el documento.')
    }
    $referencia = $partidaSdt.Groups[1].Value
    $nombreSdt = $referencia
    $modulo = ''
    if ($referencia -match ',') {
        $partes = $referencia.Split(',')
        $nombreSdt = $partes[0].Trim()
        $modulo = $partes[1].Trim()
    }
    $sdt = Obtener-Sdt -Xml $Xml -NombreSdt $nombreSdt -Modulo $modulo -Indice $Indice
    if (-not $sdt) {
        throw ('La entrada del SDT ' + $nombreSdt + ' no está exportada en el XPZ configurado. No puede inferirse.')
    }
    return [pscustomobject]@{
        VariableSdt = $variableSdt
        NombreSdt = $nombreSdt
        Sdt = $sdt
        Campos = Obtener-HijosSdt -Sdt $sdt
    }
}

function Obtener-Referencia {
    <#
    .SYNOPSIS
    Resuelve una referencia idBasedOn de dominio o atributo por nombre y modulo.
    .DESCRIPTION
    Separa el sufijo de modulo de la referencia ('Nombre, Modulo') y consulta el
    indice de dominios o de atributos segun el tipo. Para atributos, prioriza el
    elemento Attribute de nivel superior (la definicion canonica del atributo)
    cuando existe unico; si hay varios candidatos, filtra por modulo y, en el caso
    de atributos, por los que declaran ATTCUSTOMTYPE. Para dominios con homonimos
    y referencia sin modulo, prioriza el dominio de la raiz (fullyQualifiedName
    igual al nombre de la referencia); cuando se necesita un dominio de otro modulo,
    la referencia lo califica.
    Devuelve el nodo unico o $null cuando la referencia no puede resolverse
    sin ambiguedad.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Tipo,
        [Parameter(Mandatory = $true)][string]$Nombre,
        [Parameter(Mandatory = $false)][string]$Modulo = '',
        [Parameter(Mandatory = $false)]$Indice,
        [Parameter(Mandatory = $false)][System.Xml.XmlDocument]$Xml
    )

    $indiceNombres = $null
    if ($Tipo -eq 'Domain' -and $Indice -and $Indice.PorNombreDominio) {
        $indiceNombres = $Indice.PorNombreDominio
    } elseif ($Tipo -eq 'Attribute' -and $Indice -and $Indice.PorNombreAtributo) {
        $indiceNombres = $Indice.PorNombreAtributo
    }
    if (-not $indiceNombres -and $Xml) {
        $indiceNombres = @{}
        if ($Tipo -eq 'Domain') {
            foreach ($objeto in $Xml.SelectNodes("//Object[@name='" + $Nombre + "']")) {
                if ($objeto.GetAttribute('type') -ne '00972a17-9975-449e-aab1-d26165d51393') { continue }
                if (-not $indiceNombres.ContainsKey($Nombre)) {
                    $indiceNombres[$Nombre] = New-Object System.Collections.Generic.List[object]
                }
                $indiceNombres[$Nombre].Add($objeto)
            }
        }
    }
    if (-not $indiceNombres -or -not $indiceNombres.ContainsKey($Nombre)) { return $null }

    $candidatos = [array]$indiceNombres[$Nombre]
    if ($candidatos.Count -eq 0) { return $null }
    if ($candidatos.Count -eq 1) { return $candidatos[0] }

    if ($Tipo -eq 'Attribute') {
        $atributos = @($candidatos | Where-Object { $_.LocalName -eq 'Attribute' })
        if ($atributos.Count -eq 1) { return $atributos[0] }
    }

    if ($Tipo -eq 'Domain' -and -not $Modulo) {
        $deRaiz = @($candidatos | Where-Object { $_.GetAttribute('fullyQualifiedName') -eq $Nombre })
        if ($deRaiz.Count -eq 1) { return $deRaiz[0] }
    }

    if ($Modulo) {
        $porModulo = @($candidatos | Where-Object {
            $nombreCompleto = $_.GetAttribute('fullyQualifiedName')
            $nombreCompleto -and ($nombreCompleto -eq $Modulo -or $nombreCompleto.StartsWith($Modulo + '.'))
        })
        if ($porModulo.Count -eq 1) { return $porModulo[0] }
    }

    if ($Tipo -eq 'Attribute') {
        $conTipo = @($candidatos | Where-Object { Obtener-Propiedad -Nodo $_ -Nombre 'ATTCUSTOMTYPE' })
        if ($conTipo.Count -eq 1) { return $conTipo[0] }
    }

    return $null
}

function Obtener-DatosTipo {
    <#
    .SYNOPSIS
    Resuelve la informacion de tipo de un campo o variable (analisisXPZ.md seccion 3).
    .DESCRIPTION
    Sigue la cadena ATTCUSTOMTYPE / idBasedOn (Domain o Attribute) hasta obtener
    el tipo base (bas:X), la estructura (sdt:Nombre) o marcar el tipo como no resuelto.
    Cuando la cadena llega a un nodo hoja sin ATTCUSTOMTYPE ni idBasedOn, mapea el tipo
    con los datos presentes en el XPZ: Decimals o Length/AttMaxLen confirman bas:Numeric
    (default de GeneXus). Solo cuando el nodo no expone ningun dato de tipo (sin bas:,
    sin idBasedOn, sin Length ni Decimals) queda marcado como no resuelto.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Nodo,
        [Parameter(Mandatory = $false)]$Indice
    )

    $nodoActual = $Nodo
    $visitados = @{}
    $baseTipo = ''
    $nombreSdt = ''
    $moduloSdt = ''
    $esEstructura = $false
    $esColeccion = $false
    $longitud = ''
    $longitudMaxima = ''
    $decimales = ''
    $noResuelto = $false

    while ($nodoActual) {
        $identificador = $nodoActual.GetAttribute('guid')
        if (-not $identificador) { $identificador = $nodoActual.GetAttribute('fullyQualifiedName') }
        if ($identificador -and $visitados.ContainsKey($identificador)) {
            $noResuelto = $true
            break
        }
        if ($identificador) { $visitados[$identificador] = $true }

        if (-not $longitud) { $longitud = Obtener-Propiedad -Nodo $nodoActual -Nombre 'Length' }
        if (-not $longitudMaxima) { $longitudMaxima = Obtener-Propiedad -Nodo $nodoActual -Nombre 'AttMaxLen' }
        if (-not $decimales) { $decimales = Obtener-Propiedad -Nodo $nodoActual -Nombre 'Decimals' }
        if (-not $esColeccion) { $esColeccion = (Obtener-Propiedad -Nodo $nodoActual -Nombre 'AttCollection') -eq 'True' }

        $tipoCustom = Obtener-Propiedad -Nodo $nodoActual -Nombre 'ATTCUSTOMTYPE'
        $idBasedOn = Obtener-Propiedad -Nodo $nodoActual -Nombre 'idBasedOn'

        $partida = [regex]::Match($tipoCustom, '^sdt:(.+)$')
        if ($partida.Success) {
            $referencia = $partida.Groups[1].Value.Trim()
            if ($referencia -match ',') {
                $partes = $referencia.Split(',')
                $nombreSdt = $partes[0].Trim()
                $moduloSdt = $partes[1].Trim()
            } else {
                $nombreSdt = $referencia
            }
            $esEstructura = $true
            break
        }

        $partida = [regex]::Match($tipoCustom, '^bas:(.+)$')
        if ($partida.Success) {
            $baseTipo = $partida.Groups[1].Value.Trim()
            break
        }

        $partida = [regex]::Match($idBasedOn, '^Domain:(.+)$')
        if ($partida.Success) {
            $referencia = $partida.Groups[1].Value.Trim()
            $nombreReferencia = $referencia
            $moduloReferencia = ''
            if ($referencia -match ',') {
                $partes = $referencia.Split(',')
                $nombreReferencia = $partes[0].Trim()
                $moduloReferencia = $partes[1].Trim()
            }
            $dominio = Obtener-Referencia -Tipo 'Domain' -Nombre $nombreReferencia -Modulo $moduloReferencia -Indice $Indice -Xml $Xml
            if ($dominio) { $nodoActual = $dominio; continue }
            $noResuelto = $true
            break
        }

        $partida = [regex]::Match($idBasedOn, '^Attribute:(.+)$')
        if ($partida.Success) {
            $referencia = $partida.Groups[1].Value.Trim()
            $nombreReferencia = $referencia
            $moduloReferencia = ''
            if ($referencia -match ',') {
                $partes = $referencia.Split(',')
                $nombreReferencia = $partes[0].Trim()
                $moduloReferencia = $partes[1].Trim()
            }
            $atributo = Obtener-Referencia -Tipo 'Attribute' -Nombre $nombreReferencia -Modulo $moduloReferencia -Indice $Indice -Xml $Xml
            if ($atributo) { $nodoActual = $atributo; continue }
            $noResuelto = $true
            break
        }

        $tieneDecimales = ([string]$decimales -ne '')
        $tieneLongitud = (([string]$longitud -ne '') -or ([string]$longitudMaxima -ne ''))
        if ($tieneDecimales -or $tieneLongitud) {
            $baseTipo = 'Numeric'
            break
        }
        $noResuelto = $true
        break
    }

    return [pscustomobject]@{
        BaseTipo = $baseTipo
        EsEstructura = $esEstructura
        EsColeccion = $esColeccion
        NombreSdt = $nombreSdt
        ModuloSdt = $moduloSdt
        Longitud = $longitud
        LongitudMaxima = $longitudMaxima
        Decimales = $decimales
        NoResuelto = $noResuelto
    }
}

function Convertir-TipoCanonico {
    <#
    .SYNOPSIS
    Convierte la informacion de tipo resuelta a la tipografia canonica (analisisXPZ.md seccion 3).
    .DESCRIPTION
    Tipos permitidos: Integer, Decimal, String, LongVarchar, Boolean, Date (YYYY-MM-DD), DateTime,
    Base64, Estructura <campo>, Coleccion de Estructura <campo> y Coleccion JSON.
    Devuelve una cadena vacia cuando el tipo no puede representarse de forma canonica.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$DatosTipo,
        [Parameter(Mandatory = $true)][string]$NombreCampo
    )

    if ($DatosTipo.EsEstructura) {
        if ($DatosTipo.EsColeccion) { return 'Colección de Estructura ' + $NombreCampo }
        return 'Estructura ' + $NombreCampo
    }
    if ($DatosTipo.EsColeccion) { return 'Colección JSON' }
    if ($DatosTipo.NoResuelto) { return '' }

    $base = $DatosTipo.BaseTipo
    $longitud = $DatosTipo.Longitud
    $longitudMaxima = $DatosTipo.LongitudMaxima
    $decimales = $DatosTipo.Decimales

    if ($base -eq 'Numeric') {
        $hayDecimales = ($decimales -and [int]$decimales -gt 0)
        if ($hayDecimales) {
            if ($longitud) { return 'Decimal (' + $longitud + ', ' + $decimales + ')' }
            return 'Decimal'
        }
        if ($longitud) { return 'Integer (' + $longitud + ')' }
        return 'Integer'
    }
    if ($base -in @('Character', 'VarChar')) {
        $dimensionConfirmada = ($longitud -and (-not $longitudMaxima -or $longitud -eq $longitudMaxima))
        if ($dimensionConfirmada) { return 'String (' + $longitud + ')' }
        return 'String'
    }
    if ($base -eq 'LongVarChar') { return 'LongVarchar' }
    if ($base -eq 'Boolean') { return 'Boolean' }
    if ($base -eq 'Date') { return 'Date (YYYY-MM-DD)' }
    if ($base -eq 'DateTime') { return 'DateTime' }
    if ($base -in @('Blob', 'Image')) { return 'Base64' }
    return ''
}

function Obtener-DescripcionCampo {
    <#
    .SYNOPSIS
    Obtiene la descripcion de un campo desde su evidencia en el XPZ.
    .DESCRIPTION
    Usa el atributo description del item o la propiedad Description, y en su defecto
    la descripcion del objeto Domain o Attribute referenciado por idBasedOn. Para
    referencias Attribute se consulta la definicion canonica (elemento Attribute),
    ademas de la busqueda entre objetos.
    Devuelve una cadena vacia cuando no hay descripcion derivable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Item,
        [Parameter(Mandatory = $false)]$Indice
    )

    $descripcion = $Item.GetAttribute('description')
    if ($descripcion) { return ($descripcion -replace '^\*\s*', '') }
    $descripcion = Obtener-Propiedad -Nodo $Item -Nombre 'Description'
    if ($descripcion) { return $descripcion }

    $idBasedOn = Obtener-Propiedad -Nodo $Item -Nombre 'idBasedOn'
    if ($idBasedOn -match '^(Domain|Attribute):(.+)$') {
        $nombreRef = $Matches[2].Trim()
        if ($Matches[1] -eq 'Attribute') {
            $atributo = Obtener-Referencia -Tipo 'Attribute' -Nombre $nombreRef -Indice $Indice -Xml $Xml
            if (-not $atributo) {
                $atributosXml = @($Xml.SelectNodes("//Attribute[@name='" + $nombreRef + "']"))
                if ($atributosXml.Count -eq 1) { $atributo = $atributosXml[0] }
            }
            if ($atributo) {
                $descripcion = $atributo.GetAttribute('description')
                if ($descripcion) { return ($descripcion -replace '^\*\s*', '') }
                $descripcion = Obtener-Propiedad -Nodo $atributo -Nombre 'Description'
                if ($descripcion) { return $descripcion }
            }
        }
        $objetos = @()
        if ($Indice -and $Indice.PorNombre -and $Indice.PorNombre.ContainsKey($nombreRef)) {
            $objetos = [array]$Indice.PorNombre[$nombreRef]
        } else {
            $objetos = @($Xml.SelectNodes("//Object[@name='" + $nombreRef + "']"))
        }
        if ($objetos.Count -eq 1) {
            $descripcion = $objetos[0].GetAttribute('description')
            if ($descripcion) { return $descripcion }
            $descripcion = Obtener-Propiedad -Nodo $objetos[0] -Nombre 'Description'
            if ($descripcion) { return $descripcion }
        }
        foreach ($obj in $Xml.SelectNodes('//Object//Item')) {
            $ref = Obtener-Propiedad -Nodo $obj -Nombre 'idBasedOn'
            if ($ref -eq $idBasedOn) {
                $desc = $obj.GetAttribute('description')
                if ($desc) { return ($desc -replace '^\*\s*', '') }
                $desc = Obtener-Propiedad -Nodo $obj -Nombre 'Description'
                if ($desc) { return $desc }
            }
        }
    }
    return ''
}

function Resolver-DescripcionPorSource {
    <#
    Obtiene únicamente descripciones ligadas explícitamente en el Source: una
    etiqueta literal junto a la variable, una variable destino con metadatos, o
    un dominio utilizado como condición. No transforma nombres por heurística.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$ProgramaPrincipal,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Variable,
        [Parameter(Mandatory = $false)]$Indice
    )

    $variableEscapada = [regex]::Escape($Variable)
    $etiqueta = [regex]::Match($Source, "'([^']+?)\s*:?'\s*\+\s*&\s*" + $variableEscapada + '\b')
    if ($etiqueta.Success) { return $etiqueta.Groups[1].Value.Trim() }

    $destino = [regex]::Match($Source, '(?mi)^\s*&([A-Za-z_][A-Za-z0-9_]*)\s*=\s*[^\r\n]*&' + $variableEscapada + '\b')
    if ($destino.Success) {
        $destinoNodo = Obtener-Variable -ProgramaPrincipal $ProgramaPrincipal -Nombre $destino.Groups[1].Value
        if ($destinoNodo) {
            $descripcionDestino = Obtener-DescripcionCampo -Xml $Xml -Item $destinoNodo -Indice $Indice
            if ($descripcionDestino) { return $descripcionDestino }
        }
    }

    $dominio = Obtener-Referencia -Tipo 'Domain' -Nombre $Variable -Indice $Indice -Xml $Xml
    if ($dominio -and $Source -match ('(?i)\b' + $variableEscapada + '\s*\.')) {
        $descripcionDominio = $dominio.GetAttribute('description')
        if (-not $descripcionDominio) { $descripcionDominio = Obtener-Propiedad -Nodo $dominio -Nombre 'Description' }
        if ($descripcionDominio) { return ($descripcionDominio -replace '^\*\s*', '') }
    }
    return ''
}

function Resolver-Campo {
    <#
    .SYNOPSIS
    Resuelve un campo de entrada (item de SDT o Level inline) con su tipo canonico y descripcion.
    .DESCRIPTION
    Devuelve un objeto con Campo, Tipo, Descripcion y los datos de estructura para
    la expansion posterior. Cuando el tipo o la descripción no pueden confirmarse,
    conserva un pendiente breve; el detalle de evidencia se agrega al resultado.
    Los nodos Level representan estructuras inline anidadas directamente en el SDT padre.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Item,
        [Parameter(Mandatory = $false)]$Indice
    )

    $nombre = $Item.GetAttribute('name')
    if (-not $nombre) { $nombre = $Item.GetAttribute('Name') }

    if ($Item.LocalName -eq 'Level') {
        $levelInfo = $Item.SelectSingleNode('LevelInfo')
        $esColeccion = $false
        if ($levelInfo) {
            $esColeccion = (Obtener-Propiedad -Nodo $levelInfo -Nombre 'AttCollection') -eq 'True'
        }
        $tipo = if ($esColeccion) { 'Colección de Estructura ' + $nombre } else { 'Estructura ' + $nombre }
        $descripcion = $Item.GetAttribute('description')
        if (-not $descripcion -and $levelInfo) { $descripcion = $levelInfo.GetAttribute('description') }
        if (-not $descripcion) { $descripcion = 'PENDIENTE DE CONFIRMACIÓN: descripcion del campo ' + $nombre + '.' }
        return [pscustomobject]@{
            Campo = $nombre
            Tipo = $tipo
            Descripcion = $descripcion
            EsEstructura = $true
            EsColeccion = $esColeccion
            NombreSdt = $nombre
            ModuloSdt = ''
            EsInline = $true
            NodoInline = $Item
        }
    }

    $datosTipo = Obtener-DatosTipo -Xml $Xml -Nodo $Item -Indice $Indice
    $tipo = Convertir-TipoCanonico -DatosTipo $datosTipo -NombreCampo $nombre
    if (-not $tipo) {
        $tipo = 'PENDIENTE DE CONFIRMACIÓN: tipo del campo ' + $nombre + '.'
    }

    $descripcion = Obtener-DescripcionCampo -Xml $Xml -Item $Item -Indice $Indice
    if (-not $descripcion) {
        $descripcion = 'PENDIENTE DE CONFIRMACIÓN: descripcion del campo ' + $nombre + '.'
    }

    return [pscustomobject]@{
        Campo = $nombre
        Tipo = $tipo
        Descripcion = $descripcion
        EsEstructura = $datosTipo.EsEstructura
        EsColeccion = $datosTipo.EsColeccion
        NombreSdt = $datosTipo.NombreSdt
        ModuloSdt = $datosTipo.ModuloSdt
    }
}

function Expandir-EstructuraSdt {
    <#
    .SYNOPSIS
    Expande un SDT en filas y tablas independientes por ruta JSON.
    .DESCRIPTION
    Mantiene cada estructura en la tabla que la contiene y crea una tabla aparte por
    cada ruta JSON, indicando si la estructura es coleccion. Recorre los SDT anidados
    de forma recursiva registrando los GUID visitados para detectar ciclos, y reporta
    los SDT referenciados que no existen. Devuelve las filas de la tabla actual, las
    tablas de estructuras, las referencias faltantes y los ciclos detectados.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Sdt,
        [Parameter(Mandatory = $false)][string]$RutaJson = '',
        [Parameter(Mandatory = $false)][string]$SdtRaizFqn = '',
        [Parameter(Mandatory = $false)][string]$RutaSdt = '',
        [Parameter(Mandatory = $false)]$Indice,
        [Parameter(Mandatory = $false)][System.Collections.Generic.HashSet[string]]$Ancestros = $null
    )

    if (-not $SdtRaizFqn -and $Sdt.LocalName -eq 'Object') {
        $SdtRaizFqn = $Sdt.GetAttribute('fullyQualifiedName')
    }
    if (-not $Ancestros) {
        $Ancestros = New-Object 'System.Collections.Generic.HashSet[string]'
        $guidRaiz = $Sdt.GetAttribute('guid')
        if ($guidRaiz) { [void]$Ancestros.Add($guidRaiz) }
    }

    $campos = Obtener-HijosSdt -Sdt $Sdt
    $filas = New-Object System.Collections.Generic.List[object]
    $tablas = New-Object System.Collections.Generic.List[object]
    $faltantes = New-Object System.Collections.Generic.List[object]
    $ciclos = New-Object System.Collections.Generic.List[object]

    foreach ($campo in $campos) {
        $resuelto = Resolver-Campo -Xml $Xml -Item $campo -Indice $Indice
        $rutaCampo = $(if ($RutaJson) { $RutaJson + '.' + $resuelto.Campo } else { $resuelto.Campo })
        $rutaSdtCampo = $(if ($RutaSdt) { $RutaSdt + '.' + $resuelto.Campo } else { $resuelto.Campo })
        $resuelto | Add-Member -MemberType NoteProperty -Name 'RutaJson' -Value $rutaCampo -Force
        $resuelto | Add-Member -MemberType NoteProperty -Name 'SdtFqn' -Value $SdtRaizFqn -Force
        $resuelto | Add-Member -MemberType NoteProperty -Name 'RutaSdt' -Value $rutaSdtCampo -Force
        $filas.Add($resuelto)
        if (-not $resuelto.EsEstructura) { continue }

        if ($resuelto.EsInline) {
            $nodoHijo = $resuelto.NodoInline
            $guidHijo = $nodoHijo.GetAttribute('guid')
            if ($guidHijo -and $Ancestros.Contains($guidHijo)) {
                $resuelto | Add-Member -MemberType NoteProperty -Name 'ReferenciaRecursiva' -Value $true -Force
                $resuelto.Descripcion = ($resuelto.Descripcion.TrimEnd('.') + '. Repite recursivamente la misma estructura.')
                $ciclos.Add([pscustomobject]@{ NombreSdt = $resuelto.NombreSdt; RutaJson = $rutaCampo })
                continue
            }
            $nuevosAncestros = New-Object 'System.Collections.Generic.HashSet[string]'
            foreach ($ancestro in $Ancestros) { [void]$nuevosAncestros.Add($ancestro) }
            if ($guidHijo) { [void]$nuevosAncestros.Add($guidHijo) }

            $recursivo = Expandir-EstructuraSdt -Xml $Xml -Sdt $nodoHijo -RutaJson $rutaCampo -SdtRaizFqn $SdtRaizFqn -RutaSdt $rutaSdtCampo -Indice $Indice -Ancestros $nuevosAncestros
        } else {
            $sdtHijo = Obtener-Sdt -Xml $Xml -NombreSdt $resuelto.NombreSdt -Modulo $resuelto.ModuloSdt -Indice $Indice
            if (-not $sdtHijo) {
                $faltantes.Add([pscustomobject]@{ NombreSdt = $resuelto.NombreSdt; RutaJson = $rutaCampo })
                continue
            }
            if ((Obtener-SdtEsColeccion -Sdt $sdtHijo) -and -not $resuelto.EsColeccion) {
                $resuelto.EsColeccion = $true
                $resuelto.Tipo = 'Colección de Estructura ' + $resuelto.Campo
            }
            $guidHijo = $sdtHijo.GetAttribute('guid')
            if ($guidHijo -and $Ancestros.Contains($guidHijo)) {
                $resuelto | Add-Member -MemberType NoteProperty -Name 'ReferenciaRecursiva' -Value $true -Force
                $resuelto.Descripcion = ($resuelto.Descripcion.TrimEnd('.') + '. Repite recursivamente la misma estructura.')
                $ciclos.Add([pscustomobject]@{ NombreSdt = $resuelto.NombreSdt; RutaJson = $rutaCampo })
                continue
            }
            $nuevosAncestros = New-Object 'System.Collections.Generic.HashSet[string]'
            foreach ($ancestro in $Ancestros) { [void]$nuevosAncestros.Add($ancestro) }
            if ($guidHijo) { [void]$nuevosAncestros.Add($guidHijo) }

            $fqnHijo = $sdtHijo.GetAttribute('fullyQualifiedName')
            $recursivo = Expandir-EstructuraSdt -Xml $Xml -Sdt $sdtHijo -RutaJson $rutaCampo -SdtRaizFqn $fqnHijo -RutaSdt '' -Indice $Indice -Ancestros $nuevosAncestros
        }
        $tablas.Add([pscustomobject]@{
            Ruta = $rutaCampo
            EsColeccion = $resuelto.EsColeccion
            Filas = $recursivo.Filas
        })
        foreach ($tabla in $recursivo.Tablas) { $tablas.Add($tabla) }
        foreach ($faltante in $recursivo.Faltantes) { $faltantes.Add($faltante) }
        foreach ($ciclo in $recursivo.Ciclos) { $ciclos.Add($ciclo) }
    }

    return [pscustomobject]@{
        Filas = $filas.ToArray()
        Tablas = $tablas.ToArray()
        Faltantes = $faltantes.ToArray()
        Ciclos = $ciclos.ToArray()
    }
}

function Resolver-EntradaGetTipos {
    <#
    .SYNOPSIS
    Resuelve tipos y descripciones de las posiciones GET desde el Source y las variables.
    .DESCRIPTION
    Consulta primero la declaración de la variable y la enriquece con la conversión
    del parser (.ToNumeric, .ToString). Si la declaración solo confirma la familia,
    se conserva el tipo canónico sin inventar dimensión; si no hay declaración, la
    conversión aporta Integer o String genérico. Conserva el orden y las posiciones.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$ProgramaPrincipal,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $false)][object[]]$Posiciones = @(),
        [Parameter(Mandatory = $false)]$Indice
    )

    $patronParser = [regex]::new('&([A-Za-z_][A-Za-z0-9_]*)\s*=\s*[A-Za-z_][A-Za-z0-9_.]*\(\s*&APIGLMRequestIn\.QueryParams')
    $coincidenciaParser = $patronParser.Match($Source)
    $variableColeccion = ''
    if ($coincidenciaParser.Success) { $variableColeccion = $coincidenciaParser.Groups[1].Value }

    $entrada = New-Object System.Collections.Generic.List[object]
    foreach ($posicion in $Posiciones) {
        $variable = $posicion.Campo
        $tipo = ''
        $variableNodo = Obtener-Variable -ProgramaPrincipal $ProgramaPrincipal -Nombre $variable
        if ($variableNodo) {
            $datos = Obtener-DatosTipo -Xml $Xml -Nodo $variableNodo -Indice $Indice
            $tipo = Convertir-TipoCanonico -DatosTipo $datos -NombreCampo $variable
        }

        $patronConversion = [regex]::new('&' + [regex]::Escape($variable) + '\s*=\s*&' + [regex]::Escape($variableColeccion) + '\.Item\(\s*' + $posicion.Posicion + '\s*\)\s*\.([A-Za-z]+)\s*\(', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $coincidenciaConversion = $patronConversion.Match($Source)
        if ($coincidenciaConversion.Success) {
            $conversion = $coincidenciaConversion.Groups[1].Value
            if (-not $tipo -and $conversion -match '(?i)ToNumeric') { $tipo = 'Integer' }
            elseif (-not $tipo -and $conversion -match '(?i)ToString') { $tipo = 'String' }
        }
        if (-not $tipo) {
            $tipo = 'PENDIENTE DE CONFIRMACIÓN: tipo del campo ' + $variable + '.'
        }

        $descripcion = ''
        if ($variableNodo) { $descripcion = Obtener-DescripcionCampo -Xml $Xml -Item $variableNodo -Indice $Indice }
        if (-not $descripcion) { $descripcion = Resolver-DescripcionPorSource -Xml $Xml -ProgramaPrincipal $ProgramaPrincipal -Source $Source -Variable $variable -Indice $Indice }
        if (-not $descripcion) {
            $descripcion = 'PENDIENTE DE CONFIRMACIÓN: descripcion del campo ' + $variable + '.'
        }

        $entrada.Add([pscustomobject]@{
            Posicion = $posicion.Posicion
            Campo = $variable
            RutaJson = $variable
            Tipo = $tipo
            Descripcion = $descripcion
        })
    }
    return $entrada.ToArray()
}

function Obtener-Iteradores {
    <#
    .SYNOPSIS
    Detecta las variables iteradoras For...in del Source.
    .DESCRIPTION
    Busca patrones 'For &varIter in &ruta.Coleccion' y devuelve un diccionario
    que mapea cada variable iteradora a la ruta de la coleccion sin el prefijo &.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source
    )

    $iteradores = @{}
    $patron = [regex]::new('For\s+&([A-Za-z_][A-Za-z0-9_]*)\s+[Ii][Nn]\s+&([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)')
    foreach ($coincidencia in $patron.Matches($Source)) {
        $varIter = $coincidencia.Groups[1].Value
        $rutaColeccion = $coincidencia.Groups[2].Value
        $iteradores[$varIter] = $rutaColeccion
    }
    return $iteradores
}

function Obtener-ParametrosFormales {
    <# Extrae dirección y nombre de cada parámetro de una regla parm(...). #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][string]$Parm = '')

    if (-not $Parm) { return @() }
    $apertura = $Parm.IndexOf('(')
    $cierre = $Parm.LastIndexOf(')')
    if ($apertura -lt 0 -or $cierre -le $apertura) { return @() }
    $interiorParm = $Parm.Substring($apertura + 1, $cierre - $apertura - 1)
    if ([string]::IsNullOrWhiteSpace($interiorParm)) { return @() }
    $argumentos = Obtener-ArgumentosLlamada -Interior $interiorParm
    $resultado = New-Object System.Collections.Generic.List[object]
    foreach ($argumento in $argumentos) {
        $texto = $argumento.Trim()
        $direccion = 'in'
        if ($texto -match '(?i)^(inout|in|out)\s*:\s*(.+)$') {
            $direccion = $Matches[1].ToLowerInvariant()
            $texto = $Matches[2].Trim()
        }
        $coincidencia = [regex]::Match($texto, '^&([A-Za-z_][A-Za-z0-9_]*)(?:\.([A-Za-z_][A-Za-z0-9_.]*))?$')
        if (-not $coincidencia.Success) { continue }
        $resultado.Add([pscustomobject]@{
            Direccion = $direccion
            Variable = $coincidencia.Groups[1].Value
            Ruta = $coincidencia.Groups[2].Value
        })
    }
    return $resultado.ToArray()
}

function Resolver-ObligatorioEnFlujo {
    <#
    Sigue una fila cuando el SDT/variable se pasa como argumento real a un
    Procedure con parámetro formal confirmado. El recorrido es transitivo,
    memoizado y acotado para proteger ciclos; una rama no exportada no inventa
    obligatoriedad en sus hijos.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Programa,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][object]$Fila,
        [Parameter(Mandatory = $false)][string]$VariableSdt = '',
        [Parameter(Mandatory = $false)]$Indice,
        [Parameter(Mandatory = $false)]$Visitados = $null
    )

    if (-not $Visitados) { $Visitados = New-Object 'System.Collections.Generic.HashSet[string]' }
    $ruta = $Fila.Campo
    if ($Fila.PSObject.Properties['RutaJson'] -and $Fila.RutaJson) { $ruta = $Fila.RutaJson }
    $claveCache = ''
    $cacheFlujo = $null
    if ($Indice) {
        if (-not $Indice.PSObject.Properties['ObligatoriedadFlujo']) {
            $Indice | Add-Member -MemberType NoteProperty -Name 'ObligatoriedadFlujo' -Value @{}
        }
        $cacheFlujo = $Indice.ObligatoriedadFlujo
        $fqnPrograma = $Programa.GetAttribute('fullyQualifiedName')
        $claveCache = $fqnPrograma + '|' + $VariableSdt + '|' + $ruta
        if ($cacheFlujo.ContainsKey($claveCache)) {
            if ($cacheFlujo[$claveCache] -eq 'EN_CURSO') { return $false }
            return [bool]$cacheFlujo[$claveCache]
        }
        $cacheFlujo[$claveCache] = 'EN_CURSO'
    }
    $spansFlujo = $null
    if ($Indice) {
        if (-not $Indice.PSObject.Properties['SpansLlamadaPorFuente']) {
            $Indice | Add-Member -MemberType NoteProperty -Name 'SpansLlamadaPorFuente' -Value @{}
        }
        $fqnFuente = $Programa.GetAttribute('fullyQualifiedName')
        $claveFuente = $fqnFuente + '|' + $Source.Length + '|' + $Source.GetHashCode()
        if (-not $Indice.SpansLlamadaPorFuente.ContainsKey($claveFuente)) {
            $Indice.SpansLlamadaPorFuente[$claveFuente] = @(Obtener-SpansLlamada -Source $Source -PatronNombre '[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*')
        }
        $spansFlujo = $Indice.SpansLlamadaPorFuente[$claveFuente]
    } else {
        $spansFlujo = @(Obtener-SpansLlamada -Source $Source -PatronNombre '[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*')
    }
    foreach ($span in $spansFlujo) {
        $nombre = ([regex]::Match($span.Texto, '^([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)')).Groups[1].Value
        if (-not $nombre -or $nombre -match '(?i)^(if|for|while|format|GenerarAPIGLMResponse|FromJson|ToJson|ToString|ToNumeric|Item)$') { continue }
        $interior = Obtener-InteriorLlamada -Span $span
        if (-not $interior) { continue }
        $reales = @(Obtener-ArgumentosLlamada -Interior $interior)
        $variableBuscada = if ($VariableSdt) { $VariableSdt } else { $Fila.Campo }
        $patronRealBuscado = '^\s*&' + [regex]::Escape($variableBuscada) + '(?:\.|\s*$)'
        if (-not @($reales | Where-Object { $_ -match $patronRealBuscado }).Count) { continue }
        $objeto = Resolver-ObjetoLlamado -Xml $Xml -Nombre $nombre -Indice $Indice -Origen $Programa -IncluirSufijos
        if (-not $objeto) { continue }
        $fqn = $objeto.GetAttribute('fullyQualifiedName')
        $clave = $fqn + '|' + $VariableSdt + '|' + $ruta
        if ($Visitados.Contains($clave)) { continue }
        [void]$Visitados.Add($clave)
        $formales = @(Obtener-ParametrosFormales -Parm (Obtener-ReglaParm -Objeto $objeto))
        if ($formales.Count -eq 0) { continue }
        $fuenteHija = $null
        try { $fuenteHija = Obtener-Source -ProgramaPrincipal $objeto } catch { $fuenteHija = $null }
        if (-not $fuenteHija) { continue }
        for ($i = 0; $i -lt [Math]::Min($formales.Count, $reales.Count); $i++) {
            $real = $reales[$i].Trim()
            $formal = $formales[$i]
            if (-not $real -or -not $formal) { continue }
            if ($formal.Direccion -eq 'out') { continue }
            $coincidenciaReal = [regex]::Match($real, '^&([A-Za-z_][A-Za-z0-9_]*)(?:\.([A-Za-z_][A-Za-z0-9_.]*))?$')
            if (-not $coincidenciaReal.Success) { continue }
            $realVariable = $coincidenciaReal.Groups[1].Value
            $realRuta = $coincidenciaReal.Groups[2].Value
            $filaFlujo = $Fila
            $rutaFlujo = $ruta
            if ($VariableSdt) {
                if ($realVariable -ne $VariableSdt) { continue }
                if ($realRuta) {
                    if ($realRuta -eq $ruta) {
                        if ($cacheFlujo) { $cacheFlujo[$claveCache] = $true }
                        return $true
                    }
                    if (-not $ruta.StartsWith($realRuta + '.', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                    $rutaFlujo = $ruta.Substring($realRuta.Length + 1)
                    $filaFlujo = [pscustomobject]@{ Campo = $Fila.Campo; RutaJson = $rutaFlujo }
                }
                $segmentosFormal = @($rutaFlujo -split '\.' | ForEach-Object { [regex]::Escape($_) })
                $rutaFormal = $segmentosFormal -join '\s*\.\s*'
                $patronFormal = '&\s*' + [regex]::Escape($formal.Variable) + '\s*\.\s*' + $rutaFormal + '\b'
            } else {
                if ($realVariable -ne $Fila.Campo) { continue }
                if ($realRuta) {
                    if ($cacheFlujo) { $cacheFlujo[$claveCache] = $true }
                    return $true
                }
                $patronFormal = '&\s*' + [regex]::Escape($formal.Variable) + '\b'
            }
            $lineasHija = [regex]::Split($fuenteHija, "`r?`n") | Where-Object { $_ -notmatch '^\s*//' }
            if (($lineasHija -join "`n") -match $patronFormal) {
                if ($cacheFlujo) { $cacheFlujo[$claveCache] = $true }
                return $true
            }
            if (Resolver-ObligatorioEnFlujo -Xml $Xml -Programa $objeto -Source $fuenteHija -Fila $filaFlujo -VariableSdt $formal.Variable -Indice $Indice -Visitados $Visitados) {
                if ($cacheFlujo) { $cacheFlujo[$claveCache] = $true }
                return $true
            }
        }
    }
    if ($cacheFlujo) { $cacheFlujo[$claveCache] = $false }
    return $false
}

function Es-ReferenciaParametroOut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Programa,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][int]$IndiceReferencia,
        [Parameter(Mandatory = $false)]$Indice
    )
    $spans = $null
    $cacheResultados = $null
    $claveResultado = ''
    if ($Indice) {
        if (-not $Indice.PSObject.Properties['SpansLlamadaPorFuente']) {
            $Indice | Add-Member -MemberType NoteProperty -Name 'SpansLlamadaPorFuente' -Value @{}
        }
        if (-not $Indice.PSObject.Properties['ReferenciasParametroOut']) {
            $Indice | Add-Member -MemberType NoteProperty -Name 'ReferenciasParametroOut' -Value @{}
        }
        $fqnPrograma = $Programa.GetAttribute('fullyQualifiedName')
        $claveFuente = $fqnPrograma + '|' + $Source.Length + '|' + $Source.GetHashCode()
        if (-not $Indice.SpansLlamadaPorFuente.ContainsKey($claveFuente)) {
            $Indice.SpansLlamadaPorFuente[$claveFuente] = @(Obtener-SpansLlamada -Source $Source -PatronNombre '[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*')
        }
        $spans = $Indice.SpansLlamadaPorFuente[$claveFuente]
        $cacheResultados = $Indice.ReferenciasParametroOut
        $claveResultado = $claveFuente + '|' + $IndiceReferencia
        if ($cacheResultados.ContainsKey($claveResultado)) { return [bool]$cacheResultados[$claveResultado] }
    } else {
        $spans = @(Obtener-SpansLlamada -Source $Source -PatronNombre '[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*')
    }
    foreach ($span in $spans) {
        if ($IndiceReferencia -lt $span.Inicio -or $IndiceReferencia -gt $span.Fin) { continue }
        $nombre = ([regex]::Match($span.Texto, '^([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)')).Groups[1].Value
        if (-not $nombre) { continue }
        $objeto = Resolver-ObjetoLlamado -Xml $Xml -Nombre $nombre -Indice $Indice -Origen $Programa -IncluirSufijos
        if (-not $objeto) { continue }
        $formales = @(Obtener-ParametrosFormales -Parm (Obtener-ReglaParm -Objeto $objeto))
        if ($formales.Count -eq 0) { continue }
        $interior = Obtener-InteriorLlamada -Span $span
        if (-not $interior) { continue }
        $reales = @(Obtener-ArgumentosLlamada -Interior $interior)
        for ($i = 0; $i -lt [Math]::Min($formales.Count, $reales.Count); $i++) {
            if ($formales[$i].Direccion -ne 'out') { continue }
            $real = $reales[$i].Trim()
            $indiceEnSpan = $span.Inicio + $span.Texto.IndexOf($real)
            if ($indiceEnSpan -le $IndiceReferencia -and $IndiceReferencia -le ($indiceEnSpan + $real.Length)) {
                if ($cacheResultados) { $cacheResultados[$claveResultado] = $true }
                return $true
            }
        }
    }
    if ($cacheResultados) { $cacheResultados[$claveResultado] = $false }
    return $false
}

function Resolver-Obligatorio {
    <#
    .SYNOPSIS
    Calcula la columna Obligatorio segun analisisXPZ.md seccion 4.
    .DESCRIPTION
    El campo se marca SI cuando aparece validado, consumido o pasado como parámetro
    en el flujo del servicio; NO cuando la única evidencia es la asignación inicial
    del parser GET (o la deserialización). En POST la referencia
    se limita al campo como miembro de la variable SDT deserializada
    (VariableSdt.RutaJson), de modo que los campos homonimos no comparten
    obligatoriedad accidentalmente. En GET se limita a la variable con prefijo &.
    Las fuentes adicionales sólo aportan evidencia cuando el mismo campo sigue el
    flujo a un Procedure alcanzable; no se hereda obligatoriedad a hijos de un SDT
    completo si el receptor no está exportado.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][object]$Fila,
        [Parameter(Mandatory = $false)][string]$VariableSdt = '',
        [Parameter(Mandatory = $false)][object[]]$SourcesAdicionales = @(),
        [Parameter(Mandatory = $false)][System.Xml.XmlDocument]$Xml = $null,
        [Parameter(Mandatory = $false)][System.Xml.XmlNode]$ProgramaPrincipal = $null,
        [Parameter(Mandatory = $false)]$Indice
    )

    $lineas = [regex]::Split($Source, "`r?`n")
    $codigo = @($lineas | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"

    $patron = ''
    if ($VariableSdt) {
        $campo = $Fila.Campo
        $ruta = $campo
        if ($Fila.PSObject.Properties['RutaJson'] -and $Fila.RutaJson) { $ruta = $Fila.RutaJson }
        $segmentos = @(($ruta -split '\.') | ForEach-Object { [regex]::Escape($_) })
        $patron = '&\s*' + [regex]::Escape($VariableSdt) + '\s*\.\s*' + ($segmentos -join '\s*\.\s*') + '\b'
    } else {
        $patron = '&\s*' + [regex]::Escape($Fila.Campo) + '\b'
    }

    # Una asignación desde QueryParams sólo materializa la posición documentada;
    # no prueba por sí misma que el valor sea obligatorio.
    $lineasCodigo = [regex]::Split($codigo, "`r?`n")
    $lineasUtiles = New-Object System.Collections.Generic.List[string]
    foreach ($linea in $lineasCodigo) {
        $esParser = $false
        if (-not $VariableSdt) {
            $esParser = $linea -match ('^\s*&\s*' + [regex]::Escape($Fila.Campo) + '\s*=\s*&[A-Za-z_][A-Za-z0-9_]*\.Item\s*\(')
        }
        if (-not $esParser) { $lineasUtiles.Add($linea) }
    }
    $codigo = $lineasUtiles -join "`n"

    $referencias = [regex]::Matches($codigo, $patron)
    if ($referencias.Count -gt 0) {
        foreach ($referencia in $referencias) {
            if (-not ($Xml -and $ProgramaPrincipal -and (Es-ReferenciaParametroOut -Xml $Xml -Programa $ProgramaPrincipal -Source $codigo -IndiceReferencia $referencia.Index -Indice $Indice))) {
                return 'SI'
            }
        }
    }

    if ($Xml -and $ProgramaPrincipal) {
        if (Resolver-ObligatorioEnFlujo -Xml $Xml -Programa $ProgramaPrincipal -Source $Source -Fila $Fila -VariableSdt $VariableSdt -Indice $Indice) {
            return 'SI'
        }
    }

    if ($VariableSdt -and $Fila.PSObject.Properties['RutaJson'] -and $Fila.RutaJson) {
        $iteradores = Obtener-Iteradores -Source $Source
        $segmentosRuta = @($Fila.RutaJson -split '\.')
        if ($segmentosRuta.Count -ge 2) {
            $coleccionBuscar = $VariableSdt + '.' + $segmentosRuta[0]
            $varIter = ''
            foreach ($clave in $iteradores.Keys) {
                if ($iteradores[$clave] -eq $coleccionBuscar) {
                    $varIter = $clave
                    break
                }
            }
            if ($varIter) {
                $restoSegmentos = $segmentosRuta[1..($segmentosRuta.Count - 1)] | ForEach-Object { [regex]::Escape($_) }
                $patronIter = '&\s*' + [regex]::Escape($varIter) + '\s*\.\s*' + ($restoSegmentos -join '\s*\.\s*') + '\b'
                if ($codigo -match $patronIter) {
                    return 'SI'
                }
            }
        }
    }

    return 'NO'
}

function Agregar-Obligatorio {
    <#
    .SYNOPSIS
    Agrega la propiedad Obligatorio a una fila de la documentación técnica.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][object]$Fila,
        [Parameter(Mandatory = $false)][string]$VariableSdt = '',
        [Parameter(Mandatory = $false)][object[]]$SourcesAdicionales = @(),
        [Parameter(Mandatory = $false)][System.Xml.XmlDocument]$Xml = $null,
        [Parameter(Mandatory = $false)][System.Xml.XmlNode]$ProgramaPrincipal = $null,
        [Parameter(Mandatory = $false)]$Indice
    )

    $Fila | Add-Member -MemberType NoteProperty -Name 'Obligatorio' -Value (Resolver-Obligatorio -Source $Source -Fila $Fila -VariableSdt $VariableSdt -SourcesAdicionales $SourcesAdicionales -Xml $Xml -ProgramaPrincipal $ProgramaPrincipal -Indice $Indice) -Force
}

function Aplicar-Obligatorio {
    <#
    .SYNOPSIS
    Aplica la columna Obligatorio a las filas de entrada (y a las de estructuras).
    .DESCRIPTION
    Recibe las filas de la tabla principal y las tablas de estructuras expandidas,
    o una lista de filas (caso GET), y agrega la propiedad Obligatorio a cada una.
    En POST, VariableSdt restringe la referencia al miembro del SDT deserializado.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $false)][object[]]$Filas = @(),
        [Parameter(Mandatory = $false)][object[]]$Tablas = @(),
        [Parameter(Mandatory = $false)][string]$VariableSdt = '',
        [Parameter(Mandatory = $false)][object[]]$SourcesAdicionales = @(),
        [Parameter(Mandatory = $false)][System.Xml.XmlDocument]$Xml = $null,
        [Parameter(Mandatory = $false)][System.Xml.XmlNode]$ProgramaPrincipal = $null,
        [Parameter(Mandatory = $false)]$Indice
    )

    foreach ($fila in $Filas) { Agregar-Obligatorio -Source $Source -Fila $fila -VariableSdt $VariableSdt -SourcesAdicionales $SourcesAdicionales -Xml $Xml -ProgramaPrincipal $ProgramaPrincipal -Indice $Indice }
    foreach ($tabla in $Tablas) {
        foreach ($fila in $tabla.Filas) { Agregar-Obligatorio -Source $Source -Fila $fila -VariableSdt $VariableSdt -SourcesAdicionales $SourcesAdicionales -Xml $Xml -ProgramaPrincipal $ProgramaPrincipal -Indice $Indice }
    }
}

function Construir-MarcasEspeciales {
    <#
    .SYNOPSIS
    Clasifica cada caracter del Source como codigo, literal o comentario.
    .DESCRIPTION
    Devuelve un arreglo de enteros con la misma longitud del Source: 0 para codigo,
    1 para literal de cadena, 2 para comentario de linea, 3 para comentario de bloque
    y 4 para seccion java. Permite balancear parentesis ignorando los que aparecen
    dentro de literales o comentarios.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source
    )

    $longitud = $Source.Length
    $marcas = New-Object 'int[]' $longitud
    $posicion = 0
    while ($posicion -lt $longitud) {
        $caracter = $Source[$posicion]

        if ($caracter -eq "'") {
            $inicio = $posicion
            $posicion++
            while ($posicion -lt $longitud -and $Source[$posicion] -ne "'") { $posicion++ }
            for ($indice = $inicio; $indice -le $posicion -and $indice -lt $longitud; $indice++) { $marcas[$indice] = 1 }
            $posicion++
            continue
        }

        if ($caracter -eq '/' -and $posicion + 1 -lt $longitud -and $Source[$posicion + 1] -eq '/') {
            $inicio = $posicion
            while ($posicion -lt $longitud -and $Source[$posicion] -ne "`n") { $posicion++ }
            for ($indice = $inicio; $indice -lt $posicion; $indice++) { $marcas[$indice] = 2 }
            continue
        }

        if ($caracter -eq '/' -and $posicion + 1 -lt $longitud -and $Source[$posicion + 1] -eq '*') {
            $inicio = $posicion
            $posicion += 2
            while ($posicion + 1 -lt $longitud -and -not ($Source[$posicion] -eq '*' -and $Source[$posicion + 1] -eq '/')) { $posicion++ }
            $posicion = [Math]::Min($posicion + 2, $longitud)
            for ($indice = $inicio; $indice -lt $posicion; $indice++) { $marcas[$indice] = 3 }
            continue
        }

        if ($caracter -eq '[' -and $posicion + 1 -lt $longitud -and $Source[$posicion + 1] -eq '!') {
            $inicio = $posicion
            $posicion += 2
            while ($posicion + 1 -lt $longitud -and -not ($Source[$posicion] -eq '!' -and $Source[$posicion + 1] -eq ']')) { $posicion++ }
            $posicion = [Math]::Min($posicion + 2, $longitud)
            for ($indice = $inicio; $indice -lt $posicion; $indice++) { $marcas[$indice] = 4 }
            continue
        }

        $posicion++
    }

    return $marcas
}

function Obtener-SpansLlamada {
    <#
    .SYNOPSIS
    Extrae los spans completos de llamadas que abren parentesis en el Source.
    .DESCRIPTION
    Localiza cada aparicion del patron de nombre seguida de un parentesis de apertura
    y devuelve el span completo desde el inicio del nombre hasta el parentesis de
    cierre balanceado. Cruza lineas continuadas y omite los parentesis que aparecen
    dentro de literales, comentarios o secciones java.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$PatronNombre
    )

    $marcas = Construir-MarcasEspeciales -Source $Source
    $resultados = New-Object System.Collections.Generic.List[object]
    $patron = [regex]::new($PatronNombre + '\s*\(')

    foreach ($coincidencia in $patron.Matches($Source)) {
        if ($marcas[$coincidencia.Index] -ne 0) { continue }
        $inicio = $coincidencia.Index
        $posicion = $coincidencia.Index + $coincidencia.Length
        $nivel = 1
        $cierre = -1
        while ($posicion -lt $Source.Length) {
            if ($marcas[$posicion] -eq 0) {
                $caracter = $Source[$posicion]
                if ($caracter -eq '(') { $nivel++ }
                elseif ($caracter -eq ')') {
                    $nivel--
                    if ($nivel -eq 0) { $cierre = $posicion; break }
                }
            }
            $posicion++
        }
        if ($cierre -lt 0) { continue }
        $resultados.Add([pscustomobject]@{
            Inicio = $inicio
            Fin = $cierre
            Texto = $Source.Substring($inicio, $cierre - $inicio + 1)
            LineaInicio = ([regex]::Matches($Source.Substring(0, $inicio), "`n")).Count + 1
            LineaFin = ([regex]::Matches($Source.Substring(0, $cierre), "`n")).Count + 1
        })
    }

    return $resultados.ToArray()
}

function Obtener-InteriorLlamada {
    <#
    .SYNOPSIS
    Devuelve el texto entre los parentesis exteriores de un span de llamada.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Span
    )

    $texto = $Span.Texto
    $apertura = $texto.IndexOf('(')
    $cierre = $texto.LastIndexOf(')')
    if ($apertura -lt 0 -or $cierre -le $apertura) { return '' }
    return $texto.Substring($apertura + 1, $cierre - $apertura - 1)
}

function Obtener-ArgumentosLlamada {
    <#
    .SYNOPSIS
    Divide el interior de una llamada en argumentos de nivel superior.
    .DESCRIPTION
    Recibe el texto entre los parentesis exteriores de una llamada y lo separa por
    comas que estan fuera de literales y de parentesis anidados. Devuelve un arreglo
    de cadenas con los argumentos en orden.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Interior
    )

    $argumentos = New-Object System.Collections.Generic.List[string]
    $marcas = Construir-MarcasEspeciales -Source $Interior
    $nivel = 0
    $inicio = 0
    $posicion = 0
    while ($posicion -lt $Interior.Length) {
        if ($marcas[$posicion] -eq 0) {
            $caracter = $Interior[$posicion]
            if ($caracter -eq '(') { $nivel++ }
            elseif ($caracter -eq ')') { $nivel-- }
            elseif ($caracter -eq ',' -and $nivel -eq 0) {
                $argumentos.Add($Interior.Substring($inicio, $posicion - $inicio).Trim())
                $inicio = $posicion + 1
            }
        }
        $posicion++
    }
    $argumentos.Add($Interior.Substring($inicio).Trim())
    return $argumentos.ToArray()
}

function Mapear-CodigoHttp {
    <#
    .SYNOPSIS
    Convierte el nombre del codigo HttpCode a su numero HTTP (analisisXPZ.md seccion 6).
    .DESCRIPTION
    HttpCode.BadRequest a 400, NotFound a 404 y MethodNotAllowed a 405, segun la
    convencion del analisis. Devuelve 0 cuando el codigo no puede resolverse.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$NombreCodigo
    )

    switch ($NombreCodigo) {
        'HttpCode.OK' { return 200 }
        'HttpCode.BadRequest' { return 400 }
        'HttpCode.Unauthorized' { return 401 }
        'HttpCode.Forbidden' { return 403 }
        'HttpCode.NotFound' { return 404 }
        'HttpCode.MethodNotAllowed' { return 405 }
        'HttpCode.InternalServerError' { return 500 }
        'HttpCode.NotImplemented' { return 501 }
        'HttpCode.ServiceUnavailable' { return 503 }
        default { return 0 }
    }
}

function Normalizar-Mensaje {
    <#
    .SYNOPSIS
    Normaliza el mensaje de una llamada a GenerarAPIGLMResponse.
    .DESCRIPTION
    Conserva el texto fijo de los literales y representa las partes dinamicas
    (format) con marcadores descriptivos como <variable>.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$MensajeRaw
    )

    $texto = $MensajeRaw.Trim()
    $partida = [regex]::Match($texto, "^'([^']*)'$")
    if ($partida.Success) { return $partida.Groups[1].Value }
    if ($texto -eq "!''") { return '' }
    $partida = [regex]::Match($texto, '^format\s*\(\s*''([^'']*)''(.*)\)$')
    if ($partida.Success) {
        $plantilla = $partida.Groups[1].Value
        $argumentos = @([regex]::Matches($partida.Groups[2].Value, '&\s*([A-Za-z_][A-Za-z0-9_]*)') | ForEach-Object { $_.Groups[1].Value })
        for ($i = 0; $i -lt $argumentos.Count; $i++) {
            $plantilla = $plantilla.Replace('%' + ($i + 1), '<' + $argumentos[$i] + '>')
        }
        return $plantilla
    }
    $patronParte = '(?:!?''([^'']*)''|!?"([^"]*)"|&\s*([A-Za-z_][A-Za-z0-9_]*)(?:\.(?:ToString|Trim)\s*\(\s*\))?)'
    $partes = @([regex]::Matches($texto, $patronParte, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
    if ($partes.Count -gt 0) {
        $resto = [regex]::Replace($texto, $patronParte, '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $resto = $resto -replace '[\s+]', ''
        if (-not $resto) {
            $plantilla = ''
            foreach ($parte in $partes) {
                if ($parte.Groups[1].Success) { $plantilla += $parte.Groups[1].Value }
                elseif ($parte.Groups[2].Success) { $plantilla += $parte.Groups[2].Value }
                else { $plantilla += '<' + $parte.Groups[3].Value + '>' }
            }
            return $plantilla
        }
    }
    return 'PENDIENTE DE CONFIRMACIÓN: mensaje del error.'
}

function Resolver-Errores {
    <#
    .SYNOPSIS
    Extrae los errores HTTP explicitos del programa principal (analisisXPZ.md seccion 6).
    .DESCRIPTION
    La unica evidencia admitida es una llamada a GenerarAPIGLMResponse dentro del
    programa principal con codigo distinto de 200. Registra codigo y mensaje literal
    o patron. Ignora comentarios y llamadas multilinea balanceadas por parentesis.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source
    )

    $errores = New-Object System.Collections.Generic.List[object]
    $spans = Obtener-SpansLlamada -Source $Source -PatronNombre 'GenerarAPIGLMResponse(?:\.[A-Za-z]+)?'
    foreach ($span in $spans) {
        $interior = Obtener-InteriorLlamada -Span $span
        if (-not $interior) { continue }
        $argumentos = Obtener-ArgumentosLlamada -Interior $interior
        if ($argumentos.Count -lt 3) { continue }
        $nombreCodigo = $argumentos[0].Trim()
        if ($nombreCodigo -notmatch '^HttpCode\.\w+$') { continue }
        $codigo = Mapear-CodigoHttp -NombreCodigo $nombreCodigo
        if ($codigo -eq 200) { continue }
        $mensaje = Normalizar-Mensaje -MensajeRaw $argumentos[1].Trim()
        $errores.Add([pscustomobject]@{ Codigo = $codigo; Mensaje = $mensaje })
    }

    return $errores.ToArray()
}

function Resolver-Salida {
    <#
    .SYNOPSIS
    Resuelve la salida satisfactoria HTTP 200 (analisisXPZ.md seccion 5).
    .DESCRIPTION
    Sigue la construccion de la respuesta exitosa en el programa principal,
    confirma el payload, si es una coleccion y los campos expuestos con sus
    tipos y descripciones canonicos. Expande los SDT anidados de salida por
    ruta JSON. Reconoce respuestas HttpCode.OK multilinea.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$ProgramaPrincipal,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $false)]$Indice,
        [Parameter(Mandatory = $false)][string[]]$Visitados = @()
    )

    $variable = $null
    $variableEscalar = $null
    $payloadVacio = $false
    $mensajesSalida = New-Object System.Collections.Generic.List[string]
    $spans = Obtener-SpansLlamada -Source $Source -PatronNombre 'GenerarAPIGLMResponse(?:\.[A-Za-z]+)?'
    foreach ($span in $spans) {
        $interior = Obtener-InteriorLlamada -Span $span
        if (-not $interior) { continue }
        $argumentos = Obtener-ArgumentosLlamada -Interior $interior
        if ($argumentos.Count -lt 3) { continue }
        if ($argumentos[0].Trim() -notmatch '(?i)^HttpCode\.OK$') { continue }
        $coincidenciaVariable = [regex]::Match($argumentos[2].Trim(), '^&([A-Za-z_][A-Za-z0-9_]*)\s*\.ToJson\s*\(\s*\)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($coincidenciaVariable.Success) { $variable = $coincidenciaVariable.Groups[1].Value; continue }
        $arg2Normalizado = $argumentos[2].Trim() -replace '^!', ''
        if ($arg2Normalizado -eq "''" -or $arg2Normalizado -eq '""' -or $arg2Normalizado -eq '') { $payloadVacio = $true; continue }
        if ($variableEscalar) { continue }
        $coincidenciaEscalar = [regex]::Match($argumentos[2].Trim(), '^&([A-Za-z_][A-Za-z0-9_]*)\s*\.ToString\s*\(\s*\)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $coincidenciaEscalar.Success) {
            $coincidenciaEscalar = [regex]::Match($argumentos[2].Trim(), '^&([A-Za-z_][A-Za-z0-9_]*)$')
        }
        if ($coincidenciaEscalar.Success) {
            $variableEscalar = $coincidenciaEscalar.Groups[1].Value
            continue
        }
        $mensaje = Normalizar-Mensaje -MensajeRaw $argumentos[2]
        if ($mensaje -and $mensaje -notmatch '^PENDIENTE DE CONFIRMACIÓN:') { [void]$mensajesSalida.Add($mensaje) }
    }
    if (-not $variable -and $mensajesSalida.Count -eq 0) {
        if ($payloadVacio) {
            return [pscustomobject]@{
                SalidaColeccion = $false
                Salida = @()
                EstructurasSalida = @()
                Faltantes = @()
                Ciclos = @()
                NoResuelta = $false
                SalidaVacia = $true
                MensajesSalida = @()
                TipoContenidoSalida = 'application/json'
            }
        }
        if ($variableEscalar) {
            $salidaEscalar = Resolver-SalidaEscalar -Xml $Xml -ProgramaPrincipal $ProgramaPrincipal -Nombre $variableEscalar -Indice $Indice
            if ($salidaEscalar) {
                return [pscustomobject]@{
                    SalidaColeccion = $false
                    Salida = @($salidaEscalar)
                    EstructurasSalida = @()
                    Faltantes = @()
                    Ciclos = @()
                    NoResuelta = $false
                    MensajesSalida = @()
                    TipoContenidoSalida = 'application/json'
                }
            }
        }
        if ($Source -match 'HttpResponse\.AddFile') {
            return [pscustomobject]@{
                SalidaColeccion = $false
                Salida = @()
                EstructurasSalida = @()
                Faltantes = @()
                Ciclos = @()
                NoResuelta = $false
                MensajesSalida = @($mensajesSalida)
                TipoContenidoSalida = 'application/octet-stream'
            }
        }
        # La respuesta puede construirse en un Procedure delegado que recibe
        # APIGLMResponse como parámetro out:. Se sigue únicamente esa arista
        # confirmada por la regla parm y por el argumento real, sin importar
        # errores HTTP auxiliares.
        $patronLlamadaDelegada = '[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*'
        foreach ($spanDelegada in (Obtener-SpansLlamada -Source $Source -PatronNombre $patronLlamadaDelegada)) {
            $nombreLlamada = ([regex]::Match($spanDelegada.Texto, '^(' + $patronLlamadaDelegada + ')')).Groups[1].Value
            if (-not $nombreLlamada -or $nombreLlamada -match '(?i)^(if|for|while|format|GenerarAPIGLMResponse|FromJson|ToJson|ToString|ToNumeric)$') { continue }
            $objetoDelegado = Resolver-ObjetoLlamado -Xml $Xml -Nombre $nombreLlamada -Indice $Indice -Origen $ProgramaPrincipal -IncluirSufijos
            if (-not $objetoDelegado) { continue }
            $fqnDelegado = $objetoDelegado.GetAttribute('fullyQualifiedName')
            if ($Visitados -contains $fqnDelegado) { continue }
            $parmDelegado = Obtener-ReglaParm -Objeto $objetoDelegado
            if (-not $parmDelegado) { continue }
            $formalesDelegados = @(Obtener-ParametrosFormales -Parm $parmDelegado)
            $interiorDelegado = Obtener-InteriorLlamada -Span $spanDelegada
            $realesDelegados = @(Obtener-ArgumentosLlamada -Interior $interiorDelegado)
            $enlaceResponse = $false
            for ($iDelegado = 0; $iDelegado -lt [Math]::Min($formalesDelegados.Count, $realesDelegados.Count); $iDelegado++) {
                if ($formalesDelegados[$iDelegado].Direccion -eq 'out' -and $realesDelegados[$iDelegado].Trim() -match '(?i)^&\s*APIGLMResponse$') {
                    $enlaceResponse = $true
                    break
                }
            }
            $inicioSpan = [Math]::Max(0, $spanDelegada.Inicio - 80)
            $prefijo = $Source.Substring($inicioSpan, $spanDelegada.Inicio - $inicioSpan)
            $esAsignacionResponse = $prefijo -match '(?i)&\s*APIGLMResponse\s*=\s*$'
            if ($esAsignacionResponse -and @($formalesDelegados | Where-Object { $_.Direccion -eq 'out' }).Count -eq 1) {
                $enlaceResponse = $true
            }
            if (-not $enlaceResponse) { continue }
            try {
                $sourceDelegado = Obtener-Source -ProgramaPrincipal $objetoDelegado
                $visitadosDelegado = @($Visitados + $fqnDelegado)
                $resueltoDelegado = Resolver-Salida -Xml $Xml -ProgramaPrincipal $objetoDelegado -Source $sourceDelegado -Indice $Indice -Visitados $visitadosDelegado
                if (-not $resueltoDelegado.NoResuelta) { return $resueltoDelegado }
            } catch { }
        }
        return [pscustomobject]@{
            SalidaColeccion = $false
            Salida = @()
            EstructurasSalida = @()
            Faltantes = @()
            Ciclos = @()
            NoResuelta = $true
            MensajesSalida = @()
            TipoContenidoSalida = 'application/json'
        }
    }
    if (-not $variable -and $mensajesSalida.Count -gt 0) {
        return [pscustomobject]@{
            SalidaColeccion = $false
            Salida = @()
            EstructurasSalida = @()
            Faltantes = @()
            Ciclos = @()
            NoResuelta = $false
            SalidaVacia = $false
            MensajesSalida = @($mensajesSalida | Select-Object -Unique)
            TipoContenidoSalida = 'text/plain'
        }
    }
    $variableNodo = Obtener-Variable -ProgramaPrincipal $ProgramaPrincipal -Nombre $variable
    if (-not $variableNodo) {
        return [pscustomobject]@{
            SalidaColeccion = $false
            Salida = @()
            EstructurasSalida = @()
            Faltantes = @()
            Ciclos = @()
            NoResuelta = $true
            TipoContenidoSalida = 'application/json'
        }
    }
    $datosTipo = Obtener-DatosTipo -Xml $Xml -Nodo $variableNodo -Indice $Indice
    if (-not $datosTipo.EsEstructura) {
        if ($datosTipo.EsColeccion) {
            $datosElemento = [pscustomobject]@{
                BaseTipo = $datosTipo.BaseTipo
                EsEstructura = $false
                EsColeccion = $false
                NombreSdt = ''
                ModuloSdt = ''
                Longitud = $datosTipo.Longitud
                LongitudMaxima = $datosTipo.LongitudMaxima
                Decimales = $datosTipo.Decimales
                NoResuelto = $datosTipo.NoResuelto
            }
            $tipoElemento = Convertir-TipoCanonico -DatosTipo $datosElemento -NombreCampo $variable
            return [pscustomobject]@{
                SalidaColeccion = $true
                Salida = @()
                EstructurasSalida = @()
                Faltantes = @()
                Ciclos = @()
                NoResuelta = $false
                TipoColeccionPrimitiva = $tipoElemento
                TipoContenidoSalida = 'application/json'
            }
        }
        return [pscustomobject]@{
            SalidaColeccion = $datosTipo.EsColeccion
            Salida = @()
            EstructurasSalida = @()
            Faltantes = @()
            Ciclos = @()
            NoResuelta = $true
            TipoContenidoSalida = 'application/json'
        }
    }
    $sdt = Obtener-Sdt -Xml $Xml -NombreSdt $datosTipo.NombreSdt -Modulo $datosTipo.ModuloSdt -Indice $Indice
    if (-not $sdt) {
        return [pscustomobject]@{
            SalidaColeccion = $datosTipo.EsColeccion
            Salida = @()
            EstructurasSalida = @()
            Faltantes = @()
            Ciclos = @()
            NoResuelta = $true
            MotivoNoResuelta = ('La salida del SDT ' + $datosTipo.NombreSdt + ' no está exportada en el XPZ configurado. No puede inferirse.')
            TipoContenidoSalida = 'application/json'
        }
    }

    $esColeccionSalida = $datosTipo.EsColeccion -or (Obtener-SdtEsColeccion -Sdt $sdt)
    $expandido = Expandir-EstructuraSdt -Xml $Xml -Sdt $sdt -Indice $Indice
    $salida = New-Object System.Collections.Generic.List[object]
    foreach ($fila in $expandido.Filas) {
        $salida.Add([pscustomobject]@{
            Campo = $fila.Campo
            Tipo = $fila.Tipo
            Descripcion = $fila.Descripcion
            RutaJson = $fila.RutaJson
            SdtFqn = $fila.SdtFqn
            RutaSdt = $fila.RutaSdt
            ReferenciaRecursiva = $fila.ReferenciaRecursiva
            VariableSalida = $variable
        })
    }
    $estructurasSalida = New-Object System.Collections.Generic.List[object]
    foreach ($tabla in $expandido.Tablas) {
        $hijos = New-Object System.Collections.Generic.List[object]
        foreach ($fila in $tabla.Filas) {
            $hijos.Add([pscustomobject]@{
                Campo = $fila.Campo
                Tipo = $fila.Tipo
                Descripcion = $fila.Descripcion
                RutaJson = $fila.RutaJson
                SdtFqn = $fila.SdtFqn
                RutaSdt = $fila.RutaSdt
                ReferenciaRecursiva = $fila.ReferenciaRecursiva
                VariableSalida = $variable
            })
        }
        $estructurasSalida.Add([pscustomobject]@{
            RutaJson = $tabla.Ruta
            EsColeccion = $tabla.EsColeccion
            Hijos = $hijos.ToArray()
        })
    }

    return [pscustomobject]@{
        SalidaColeccion = $esColeccionSalida
        Salida = $salida.ToArray()
        EstructurasSalida = $estructurasSalida.ToArray()
        Faltantes = $expandido.Faltantes
        Ciclos = $expandido.Ciclos
        NoResuelta = $false
        TipoContenidoSalida = 'application/json'
    }
}

function Obtener-SdtEsColeccion {
    <#
    .SYNOPSIS
    Indica si un SDT esta definido como coleccion en su nodo principal (factor B).
    .DESCRIPTION
    Para Object (SDT externo) lee el AttCollection del LevelInfo del nodo raiz;
    para Level (resultado de ruta punteada) lee su LevelInfo. Devuelve $true si el
    SDT declara coleccion aunque la variable no lo marque.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Sdt
    )

    try {
        $raiz = $Sdt
        if ($Sdt.LocalName -eq 'Object') {
            foreach ($part in $Sdt.SelectNodes('Part')) {
                $hijos = @($part.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -ne 'Properties' })
                if ($hijos.Count -eq 0) { continue }
                $raiz = $hijos[0]
                break
            }
        }
        $info = $raiz.SelectSingleNode('LevelInfo')
        if ($info) {
            return (Obtener-Propiedad -Nodo $info -Nombre 'AttCollection') -eq 'True'
        }
        return (Obtener-Propiedad -Nodo $raiz -Nombre 'AttCollection') -eq 'True'
    } catch { return $false }
}

function Resolver-SalidaEscalar {
    <#
    .SYNOPSIS
    Resuelve la salida cuando el payload de OK es un valor escalar, no un SDT.
    .DESCRIPTION
    Control adicional que actua solo cuando la salida estructurada no pudo
    confirmarse: reconoce la variable del payload escalar ('&X.ToString()' o
    '&X') y documenta un unico campo con su tipo y descripcion canonicos.
    Devuelve $null cuando el tipo no puede confirmarse desde el XPZ.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$ProgramaPrincipal,
        [Parameter(Mandatory = $true)][string]$Nombre,
        [Parameter(Mandatory = $false)]$Indice
    )

    try {
        $tipo = ''
        $descripcion = ''
        $variableNodo = Obtener-Variable -ProgramaPrincipal $ProgramaPrincipal -Nombre $Nombre
        if ($variableNodo) {
            $datos = Obtener-DatosTipo -Xml $Xml -Nodo $variableNodo -Indice $Indice
            $tipo = Convertir-TipoCanonico -DatosTipo $datos -NombreCampo $Nombre
            $descripcion = Obtener-DescripcionCampo -Xml $Xml -Item $variableNodo -Indice $Indice
        }
        if (-not $tipo) {
            $atributo = Obtener-Referencia -Tipo 'Attribute' -Nombre $Nombre -Indice $Indice -Xml $Xml
            if ($atributo) {
                $datosAtributo = Obtener-DatosTipo -Xml $Xml -Nodo $atributo -Indice $Indice
                $tipo = Convertir-TipoCanonico -DatosTipo $datosAtributo -NombreCampo $Nombre
                if (-not $descripcion) { $descripcion = Obtener-DescripcionCampo -Xml $Xml -Item $atributo -Indice $Indice }
            }
        }
        if (-not $tipo) { return $null }
        if (-not $descripcion) { $descripcion = 'PENDIENTE DE CONFIRMACIÓN: descripcion del campo ' + $Nombre + '.' }
        return [pscustomobject]@{ Campo = $Nombre; RutaJson = $Nombre; VariableSalida = $Nombre; Tipo = $tipo; Descripcion = $descripcion }
    } catch { return $null }
}

function Resolver-Endpoint {
    <#
    .SYNOPSIS
    Resuelve el nombre completo del endpoint publicado (analisisXPZ.md seccion 7).
    .DESCRIPTION
    El nombre se documenta en minusculas: packagename + ruta del modulo en
    minusculas + 'a' + procedimiento. El packagename es una constante de
    configuracion (configuracion.json) que no se confirma desde el XPZ.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$NombreCompletoWrapper,
        [Parameter(Mandatory = $true)][string]$PackageName
    )

    $ultimoPunto = $NombreCompletoWrapper.LastIndexOf('.')
    if ($ultimoPunto -le 0) {
        throw ('El wrapper ' + $NombreCompletoWrapper + ' no tiene un nombre completo con modulo.')
    }
    $modulo = $NombreCompletoWrapper.Substring(0, $ultimoPunto)
    $procedimiento = $NombreCompletoWrapper.Substring($ultimoPunto + 1)

    $base = $PackageName.TrimEnd('.')
    $rutaModulo = (($modulo -split '\.') | ForEach-Object { $_.ToLowerInvariant() }) -join '.'
    return $base + '.' + $rutaModulo + '.' + 'a' + $procedimiento.ToLowerInvariant()
}

function Obtener-Source {
    <#
    .SYNOPSIS
    Devuelve el Source del programa principal (codigo), omitiendo la regla parm.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$ProgramaPrincipal
    )

    foreach ($part in $ProgramaPrincipal.SelectNodes('Part')) {
        $source = $part.SelectSingleNode('Source')
        if ($source -and -not [string]::IsNullOrWhiteSpace($source.InnerText)) {
            if ($source.InnerText -match '(?i)\bparm\s*\(') { continue }
            return $source.InnerText
        }
    }
    throw ('El programa principal ' + $ProgramaPrincipal.GetAttribute('fullyQualifiedName') + ' no tiene un Source no vacio.')
}

function Obtener-SourcesEvidencia {
    <#
    .SYNOPSIS
    Reune los Sources de los procedimientos que construyen la salida de un servicio.
    .DESCRIPTION
    Devuelve el Source del programa principal y los de los procedimientos alcanzables
    por llamadas (incluyendo sufijos de invocacion como Udp/Call cuando se indique).
    No lanza: omite los procedimientos sin Source no vacio.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$ProgramaPrincipal,
        [Parameter(Mandatory = $false)]$Indice,
        [Parameter(Mandatory = $false)][switch]$IncluirSufijos
    )

    $fuentes = New-Object System.Collections.Generic.List[string]
    foreach ($nodo in @(Obtener-NodosEvidencia -Xml $Xml -ProgramaPrincipal $ProgramaPrincipal -Indice $Indice -IncluirSufijos:$IncluirSufijos -ProfundidadMaxima 5)) {
        try {
            $fuente = Obtener-Source -ProgramaPrincipal $nodo
            $fuentes.Add($fuente)
        } catch { }
    }
    return $fuentes.ToArray()
}

function Obtener-SourceLimpio {
    <#
    .SYNOPSIS
    Devuelve el Source con comentarios y secciones java neutralizadas.
    .DESCRIPTION
    Reemplaza por espacios los caracteres de comentario de linea, bloque y las
    secciones java (marcas 2, 3 y 4 de Construir-MarcasEspeciales), conservando los
    saltos de linea para que las anclas de linea sigan siendo validas. Los literales
    se mantienen para poder descartarlos en la resolucion de tipos.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source
    )

    $marcas = Construir-MarcasEspeciales -Source $Source
    $chars = $Source.ToCharArray()
    for ($i = 0; $i -lt $chars.Length; $i++) {
        if ($marcas[$i] -ge 2 -and $chars[$i] -ne "`n") { $chars[$i] = ' ' }
    }
    return (-join $chars)
}

function Obtener-NombresLlamados {
    <#
    .SYNOPSIS
    Extrae los nombres de procedimientos llamados desde un Source.
    .DESCRIPTION
    Devuelve los nombres unicos de llamadas que abren parentesis, omitiendo
    palabras reservadas, infraestructura y las apariciones dentro de literales o
    comentarios. Se usa para reunir los procedimientos que construyen la salida.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source
    )

    $palabrasReservadas = @('if', 'for', 'while', 'do', 'case', 'switch', 'catch', 'return', 'new', 'format', 'elseif', 'else', 'endif', 'endfor', 'endwhile', 'endsub', 'sub', 'end', 'exit', 'continue')
    $infraestructura = @('ProcesarRequest', 'GenerarAPIGLMResponse', 'GenerarHttpResponse', 'GenerarHttpError', 'PHacerRollback', 'PHacerCommit', 'InsLogEventos', 'InsLogs', 'FromJson', 'ToJson', 'ToNumeric', 'ToString', 'Item', 'IsEmpty', 'Add', 'Clear')
    $marcas = Construir-MarcasEspeciales -Source $Source
    $patron = [regex]::new('\b([A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*)\s*\(')
    $resultados = New-Object System.Collections.Generic.List[string]
    $vistos = @{}
    foreach ($coincidencia in $patron.Matches($Source)) {
        if ($marcas[$coincidencia.Index] -ne 0) { continue }
        $llamada = $coincidencia.Groups[1].Value
        $ultimoSegmento = $llamada.Split('.')[-1]
        if ($palabrasReservadas -contains $ultimoSegmento.ToLowerInvariant()) { continue }
        if ($infraestructura -contains $ultimoSegmento) { continue }
        if ($vistos.ContainsKey($llamada)) { continue }
        $vistos[$llamada] = $true
        $resultados.Add($llamada)
    }
    return $resultados.ToArray()
}

function Resolver-ObjetoLlamado {
    <#
    .SYNOPSIS
    Resuelve el objeto Procedure de una llamada por nombre o fullyQualifiedName.
    .DESCRIPTION
    Devuelve el nodo unico o $null cuando la llamada no puede resolverse sin
    ambiguedad. No lanza: ante cualquier duda se omite la fuente de evidencia.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][string]$Nombre,
        [Parameter(Mandatory = $false)]$Indice,
        [Parameter(Mandatory = $false)][System.Xml.XmlNode]$Origen,
        [Parameter(Mandatory = $false)][switch]$IncluirSufijos
    )

    if (-not $Indice) { return $null }
    if ($Nombre.Contains('.')) {
        if ($Indice.PorFqn -and $Indice.PorFqn.ContainsKey($Nombre)) {
            return $Indice.PorFqn[$Nombre]
        }
        if ($IncluirSufijos) {
            foreach ($sufijo in @('Call', 'Udp', 'St', 'Upd')) {
                if ($Nombre -match ('\.' + $sufijo + '$')) {
                    $nombreBase = $Nombre.Substring(0, $Nombre.Length - $sufijo.Length - 1)
                    $objetoSufijo = Resolver-ObjetoLlamado -Xml $Xml -Nombre $nombreBase -Indice $Indice -Origen $Origen -IncluirSufijos
                    if ($objetoSufijo) { return $objetoSufijo }
                }
            }
        }
        return $null
    }
    if ($Indice.PorNombreCodigo -and $Indice.PorNombreCodigo.ContainsKey($Nombre)) {
        $candidatos = [array]$Indice.PorNombreCodigo[$Nombre]
        if ($candidatos.Count -eq 1) { return $candidatos[0] }
        if ($candidatos.Count -gt 1 -and $Origen) {
            $moduloOrigen = $Origen.GetAttribute('fullyQualifiedName')
            $ultimoPunto = $moduloOrigen.LastIndexOf('.')
            if ($ultimoPunto -gt 0) { $moduloOrigen = $moduloOrigen.Substring(0, $ultimoPunto) }
            $porModulo = @($candidatos | Where-Object { $_.GetAttribute('fullyQualifiedName') -like "$moduloOrigen.*" })
            if ($porModulo.Count -eq 1) { return $porModulo[0] }
        }
    }
    return $null
}

function Obtener-NodosEvidencia {
    <#
    .SYNOPSIS
    Reune los procedimientos que construyen la salida de un servicio.
    .DESCRIPTION
    Devuelve el programa principal y los procedimientos que este alcanza por
    llamadas (transitivo con profundidad acotada y deduplicado). No lanza: ante
    cualquier fallo devuelve el programa principal como unica evidencia.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$ProgramaPrincipal,
        [Parameter(Mandatory = $false)]$Indice,
        [Parameter(Mandatory = $false)][int]$ProfundidadMaxima = 3,
        [Parameter(Mandatory = $false)][switch]$IncluirSufijos
    )

    $nodos = New-Object System.Collections.Generic.List[object]
    $vistos = New-Object System.Collections.Generic.List[string]
    try {
        $cola = New-Object System.Collections.Generic.Queue[object]
        $fqnRaiz = $ProgramaPrincipal.GetAttribute('fullyQualifiedName')
        $vistos.Add($fqnRaiz)
        $cola.Enqueue([pscustomobject]@{ Nodo = $ProgramaPrincipal; Profundidad = 0 })
        while ($cola.Count -gt 0) {
            $actual = $cola.Dequeue()
            $nodos.Add($actual.Nodo)
            if ($actual.Profundidad -ge $ProfundidadMaxima) { continue }
            $source = $null
            try { $source = Obtener-Source -ProgramaPrincipal $actual.Nodo } catch { $source = $null }
            if (-not $source) { continue }
            foreach ($nombre in Obtener-NombresLlamados -Source $source) {
                $objeto = Resolver-ObjetoLlamado -Xml $Xml -Nombre $nombre -Indice $Indice -Origen $actual.Nodo -IncluirSufijos:$IncluirSufijos
                if (-not $objeto) { continue }
                $fqn = $objeto.GetAttribute('fullyQualifiedName')
                if ($vistos -contains $fqn) { continue }
                $vistos.Add($fqn)
                $cola.Enqueue([pscustomobject]@{ Nodo = $objeto; Profundidad = $actual.Profundidad + 1 })
            }
        }
    } catch { }
    return $nodos.ToArray()
}

function Normalizar-Rhs {
    <#
    .SYNOPSIS
    Normaliza el lado derecho de una asignacion para resolver su tipo.
    .DESCRIPTION
    Quita los sufijos Trim() encadenados. No elimina otras conversiones
    (ToString, ToNumeric) para no perder evidencia; si aparecen, la resolucion
    queda sin confirmar.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Texto
    )

    $t = $Texto.Trim()
    $cambio = $true
    while ($cambio) {
        $cambio = $false
        if ($t -match '\.Trim\(\s*\)\s*$') {
            $t = ($t -replace '\.Trim\(\s*\)\s*$', '').Trim()
            $cambio = $true
        }
    }
    return $t
}

function Resolver-TipoAtributo {
    <#
    .SYNOPSIS
    Resuelve el tipo canonico de un atributo referenciado como identificador.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][string]$Nombre,
        [Parameter(Mandatory = $false)]$Indice
    )

    try {
        $atributo = Obtener-Referencia -Tipo 'Attribute' -Nombre $Nombre -Indice $Indice -Xml $Xml
        if (-not $atributo) { return '' }
        $datos = Obtener-DatosTipo -Xml $Xml -Nodo $atributo -Indice $Indice
        $tipo = Convertir-TipoCanonico -DatosTipo $datos -NombreCampo $Nombre
        if ($tipo) { return $tipo }

        # Algunos dominios GeneXus se exportan únicamente con sus valores de
        # enumeración. Esa evidencia confirma la familia Integer, pero no una
        # dimensión: nunca se deriva una longitud a partir del valor máximo.
        $idBasedOn = Obtener-Propiedad -Nodo $atributo -Nombre 'idBasedOn'
        if ($idBasedOn -match '^Domain:(.+)$') {
            $referencia = $Matches[1].Trim()
            $nombreDominio = $referencia
            $moduloDominio = ''
            if ($referencia -match ',') {
                $partes = $referencia.Split(',')
                $nombreDominio = $partes[0].Trim()
                $moduloDominio = $partes[1].Trim()
            }
            $dominio = Obtener-Referencia -Tipo 'Domain' -Nombre $nombreDominio -Modulo $moduloDominio -Indice $Indice -Xml $Xml
            if ($dominio) {
                $valores = Obtener-Propiedad -Nodo $dominio -Nombre 'IDEnumDefinedValues'
                if ($valores -and @([regex]::Matches($valores, '(?m)(?:^|;)\s*([0-9]+)\s*,')).Count -gt 0) {
                    $noNumericos = @([regex]::Matches($valores, '(?m)(?:^|;)\s*([^,;]+)\s*,') | Where-Object { $_.Groups[1].Value.Trim() -notmatch '^\d+$' })
                    if ($noNumericos.Count -eq 0) { return 'Integer' }
                    # El formato de enumeración habitual es "número, nombre".
                    $primeros = @([regex]::Matches($valores, '(?m)(?:^|;)\s*([0-9]+)\s*,'))
                    if ($primeros.Count -gt 0) { return 'Integer' }
                }
            }
        }
        return ''
    } catch { return '' }
}

function Resolver-TipoVariable {
    <#
    .SYNOPSIS
    Resuelve el tipo canonico de una variable a partir de su declaracion o sus asignaciones.
    .DESCRIPTION
    Busca la declaracion de la variable en los procedimientos de evidencia y, en su
    defecto, las asignaciones '&variable = <rhs>' en sus fuentes, resolviendo el RHS
    de forma recursiva con profundidad acotada. Devuelve el tipo solo si todos los
    caminos confirman un unico tipo canonico.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][string]$Variable,
        [Parameter(Mandatory = $false)][object[]]$Nodos = @(),
        [Parameter(Mandatory = $false)]$Indice,
        [Parameter(Mandatory = $false)][int]$Profundidad = 0,
        [Parameter(Mandatory = $false)]$Visitados = $null
    )

    if (-not $Visitados) { $Visitados = New-Object 'System.Collections.Generic.HashSet[string]' }
    if ($Visitados.Contains($Variable)) { return '' }
    if ($Profundidad -gt 3) { return '' }
    [void]$Visitados.Add($Variable)

    $tipos = New-Object System.Collections.Generic.List[string]
    foreach ($nodo in $Nodos) {
        $variableNodo = $null
        try { $variableNodo = Obtener-Variable -ProgramaPrincipal $nodo -Nombre $Variable } catch { $variableNodo = $null }
        if ($variableNodo) {
            try {
                $datos = Obtener-DatosTipo -Xml $Xml -Nodo $variableNodo -Indice $Indice
                $canon = Convertir-TipoCanonico -DatosTipo $datos -NombreCampo $Variable
                if ($canon) { $tipos.Add($canon) }
            } catch { }
        }

        $source = $null
        try { $source = Obtener-Source -ProgramaPrincipal $nodo } catch { $source = $null }
        if (-not $source) { continue }
        $limpio = Obtener-SourceLimpio -Source $source
        $patron = [regex]::new('(?m)^\s*&' + [regex]::Escape($Variable) + '\s*=\s*(.+?)\s*$')
        foreach ($coincidencia in $patron.Matches($limpio)) {
            $rhsRaw = $coincidencia.Groups[1].Value
            $rhs = Normalizar-Rhs -Texto $rhsRaw
            if (-not $rhs) { continue }
            $nuevoVisitados = New-Object 'System.Collections.Generic.HashSet[string]'
            foreach ($v in $Visitados) { [void]$nuevoVisitados.Add($v) }
            $tipoRhs = Resolver-TipoRhs -Xml $Xml -Rhs $rhsRaw -Nodos $Nodos -Indice $Indice -Profundidad ($Profundidad + 1) -Visitados $nuevoVisitados
            if ($tipoRhs) { $tipos.Add($tipoRhs) }
        }
    }

    $distintos = @($tipos | Select-Object -Unique)
    if ($distintos.Count -eq 1) { return $distintos[0] }
    return ''
}

function Resolver-TipoRhs {
    <#
    .SYNOPSIS
    Resuelve el tipo canonico del lado derecho de una asignacion.
    .DESCRIPTION
    Si el RHS es una variable (&var) delega en Resolver-TipoVariable; si es un
    miembro (&var.Ruta) resuelve la ruta exacta del SDT; si es un identificador
    pelado lo resuelve como atributo. Las conversiones ToNumeric/ToString
    confirman la familia cuando no hay declaración más precisa.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][string]$Rhs,
        [Parameter(Mandatory = $false)][object[]]$Nodos = @(),
        [Parameter(Mandatory = $false)]$Indice,
        [Parameter(Mandatory = $false)][int]$Profundidad = 0,
        [Parameter(Mandatory = $false)]$Visitados = $null
    )

    $rhsOriginal = $Rhs.Trim()
    $teniaTrim = $rhsOriginal -match '(?i)\.Trim\s*\(\s*\)\s*$'
    $rhs = Normalizar-Rhs -Texto $Rhs
    if (-not $rhs) { return '' }

    $conversion = ''
    if ($rhs -match '(?i)\.((?:ToNumeric)|(?:ToString))\s*\(\s*\)\s*$') {
        $conversion = $Matches[1]
        $rhs = ($rhs.Substring(0, $rhs.Length - $Matches[0].Length)).Trim()
    }
    if ($rhs -match '^&([A-Za-z_][A-Za-z0-9_]*)(?:\.([A-Za-z_][A-Za-z0-9_.]*))?$') {
        $variable = $Matches[1]
        $ruta = $Matches[2]
        if ($ruta) {
            $tipoMiembro = Resolver-TipoMiembro -Xml $Xml -Variable $variable -Ruta $ruta -Nodos $Nodos -Indice $Indice
            if ($tipoMiembro) { return $tipoMiembro }
            # Si el miembro del SDT no expone metadatos, seguir la asignación
            # intermedia hacia la variable receptora declarada (por ejemplo
            # SolDisIns <- EntRechazarSolicitud.Instalacion).
            foreach ($nodo in $Nodos) {
                $fuente = $null
                try { $fuente = Obtener-Source -ProgramaPrincipal $nodo } catch { $fuente = $null }
                if (-not $fuente) { continue }
                $limpio = Obtener-SourceLimpio -Source $fuente
                $segmentosIntermedios = @($ruta -split '\.' | ForEach-Object { [regex]::Escape($_) })
                $rutaIntermedia = $segmentosIntermedios -join '\.'
                $patronIntermedio = [regex]::new('(?mi)^\s*&([A-Za-z_][A-Za-z0-9_]*)\s*=\s*&' + [regex]::Escape($variable) + '\.' + $rutaIntermedia + '\s*$')
                foreach ($m in $patronIntermedio.Matches($limpio)) {
                    $tipoIntermedio = Resolver-TipoVariable -Xml $Xml -Variable $m.Groups[1].Value -Nodos $Nodos -Indice $Indice -Profundidad ($Profundidad + 1) -Visitados $Visitados
                    if ($tipoIntermedio) { return $tipoIntermedio }
                }
            }
        } else {
            $tipoVariable = Resolver-TipoVariable -Xml $Xml -Variable $variable -Nodos $Nodos -Indice $Indice -Profundidad $Profundidad -Visitados $Visitados
            if ($tipoVariable) { return $tipoVariable }
        }
        if ($teniaTrim) { return 'String' }
        if ($conversion -match '(?i)ToNumeric') { return 'Integer' }
        if ($conversion -match '(?i)ToString') { return 'String' }
        return ''
    }
    if ($rhs -match '^[A-Za-z_][A-Za-z0-9_]*$') {
        $tipoAtributo = Resolver-TipoAtributo -Xml $Xml -Nombre $rhs -Indice $Indice
        if ($tipoAtributo) { return $tipoAtributo }
        if ($teniaTrim) { return 'String' }
        if ($conversion -match '(?i)ToNumeric') { return 'Integer' }
        if ($conversion -match '(?i)ToString') { return 'String' }
    }
    if ($conversion -match '(?i)ToNumeric') { return 'Integer' }
    if ($conversion -match '(?i)ToString') { return 'String' }
    return ''
}

function Resolver-TipoPorAsignacion {
    <#
    .SYNOPSIS
    Resuelve el tipo canonico de un campo de SDT de salida por su asignacion en el programa.
    .DESCRIPTION
    Busca en las fuentes de evidencia asignaciones de la ruta JSON exacta y
    resuelve el tipo del RHS. Solo devuelve un tipo cuando todas las asignaciones
    encontradas confirman un unico tipo canonico; ante ausencia o ambiguedad devuelve
    vacio. La ruta evita mezclar miembros homónimos (por ejemplo dos Secuencia).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][string]$Campo,
        [Parameter(Mandatory = $false)][string]$RutaJson = '',
        [Parameter(Mandatory = $false)][object[]]$Nodos = @(),
        [Parameter(Mandatory = $false)]$Indice
    )

    try {
        $tipos = New-Object System.Collections.Generic.List[string]
        if ($RutaJson) {
            $segmentosPatron = @($RutaJson -split '\.' | ForEach-Object { [regex]::Escape($_) })
            $patronRuta = $segmentosPatron -join '\.'
            $patron = [regex]::new('(?m)^\s*&[A-Za-z_][A-Za-z0-9_]*\.' + $patronRuta + '\s*=\s*(.+?)\s*$')
        } else {
            $patron = [regex]::new('(?m)^\s*&[A-Za-z_][A-Za-z0-9_]*\.' + [regex]::Escape($Campo) + '\s*=\s*(.+?)\s*$')
        }
        foreach ($nodo in $Nodos) {
            $source = $null
            try { $source = Obtener-Source -ProgramaPrincipal $nodo } catch { $source = $null }
            if (-not $source) { continue }
            $limpio = Obtener-SourceLimpio -Source $source
            foreach ($coincidencia in $patron.Matches($limpio)) {
                $rhsRaw = $coincidencia.Groups[1].Value
                $rhs = Normalizar-Rhs -Texto $rhsRaw
                if (-not $rhs) { continue }
                $tipo = Resolver-TipoRhs -Xml $Xml -Rhs $rhsRaw -Nodos $Nodos -Indice $Indice
                if ($tipo) { $tipos.Add($tipo) }
            }

            # Para colecciones GeneXus se asigna primero a un SDT temporal y
            # luego se agrega a la ruta (&Salida.Polizas.Add(&Poliza)). En ese
            # caso, seguir únicamente el temporal asociado a la colección.
            if ($RutaJson -match '\.' ) {
                $partesRuta = @($RutaJson -split '\.')
                $coleccionRuta = ($partesRuta[0..($partesRuta.Count - 2)] -join '\.')
                $campoRelativo = $partesRuta[-1]
                $segmentosColeccion = @($coleccionRuta -split '\.' | ForEach-Object { [regex]::Escape($_) })
                $rutaColeccionPatron = $segmentosColeccion -join '\s*\.\s*'
                $patronAdd = [regex]::new('&[A-Za-z_][A-Za-z0-9_]*\s*\.\s*' + $rutaColeccionPatron + '\s*\.\s*Add\s*\(\s*&([A-Za-z_][A-Za-z0-9_]*)\s*\)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                foreach ($add in $patronAdd.Matches($limpio)) {
                    $patronTemporal = [regex]::new('(?m)^\s*&' + [regex]::Escape($add.Groups[1].Value) + '\s*\.\s*' + [regex]::Escape($campoRelativo) + '\s*=\s*(.+?)\s*$')
                    foreach ($asignacionTemporal in $patronTemporal.Matches($limpio)) {
                        $rhsTemporalRaw = $asignacionTemporal.Groups[1].Value
                        $rhsTemporal = Normalizar-Rhs -Texto $rhsTemporalRaw
                        if (-not $rhsTemporal) { continue }
                        $tipoTemporal = Resolver-TipoRhs -Xml $Xml -Rhs $rhsTemporalRaw -Nodos $Nodos -Indice $Indice
                        if ($tipoTemporal) { $tipos.Add($tipoTemporal) }
                    }
                }
            }
        }
        $distintos = @($tipos | Select-Object -Unique)
        if ($distintos.Count -eq 1) { return $distintos[0] }
    } catch { }
    return ''
}

function Resolver-TipoPorLectura {
    <#
    .SYNOPSIS
    Resuelve el tipo canonico de un campo de SDT de entrada por su lectura en el programa.
    .DESCRIPTION
    Busca en las fuentes de evidencia asignaciones donde se lee el campo del SDT
    de entrada deserializado ('&destino = &VariableSdt.<ruta>.<Campo>') y resuelve el
    tipo de la variable receptora. Solo devuelve un tipo cuando todas las lecturas
    encontradas confirman un unico tipo canonico; ante ausencia o ambiguedad
    devuelve vacio.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][string]$Campo,
        [Parameter(Mandatory = $true)][string]$VariableSdt,
        [Parameter(Mandatory = $false)][object[]]$Nodos = @(),
        [Parameter(Mandatory = $false)]$Indice
    )

    try {
        $tipos = New-Object System.Collections.Generic.List[string]
        $patronLectura = [regex]::new('&' + [regex]::Escape($VariableSdt) + '(?:\.\w+)*\.' + [regex]::Escape($Campo) + '\b')
        $patron = [regex]::new('(?m)^\s*&([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$')
        foreach ($nodo in $Nodos) {
            $source = $null
            try { $source = Obtener-Source -ProgramaPrincipal $nodo } catch { $source = $null }
            if (-not $source) { continue }
            $limpio = Obtener-SourceLimpio -Source $source
            foreach ($coincidencia in $patron.Matches($limpio)) {
                $lhs = $coincidencia.Groups[1].Value
                $rhs = $coincidencia.Groups[2].Value
                if ($lhs -eq $VariableSdt) { continue }
                if (-not $patronLectura.IsMatch($rhs)) { continue }
                $tipo = Resolver-TipoVariable -Xml $Xml -Variable $lhs -Nodos $Nodos -Indice $Indice
                if ($tipo) { $tipos.Add($tipo) }
            }
        }
        $distintos = @($tipos | Select-Object -Unique)
        if ($distintos.Count -eq 1) { return $distintos[0] }
    } catch { }
    return ''
}

function Resolver-TipoPorFlujoParametros {
    <#
    Resuelve un miembro de entrada cuando el SDT se pasa completo a un Procedure:
    mapea argumento real/parámetro formal y sigue la asignación consumidora. Sólo
    acepta un destino exportado de forma unívoca y evita ciclos.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Programa,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$VariableSdt,
        [Parameter(Mandatory = $true)][object]$Fila,
        [Parameter(Mandatory = $false)]$Indice,
        [Parameter(Mandatory = $false)]$Visitados = $null
    )

    if (-not $Visitados) { $Visitados = New-Object 'System.Collections.Generic.HashSet[string]' }
    $ruta = $Fila.Campo
    if ($Fila.PSObject.Properties['RutaJson'] -and $Fila.RutaJson) { $ruta = $Fila.RutaJson }
    $cacheTiposFlujo = $null
    $claveCache = ''
    if ($Indice) {
        if (-not $Indice.PSObject.Properties['TiposFlujoParametros']) {
            $Indice | Add-Member -MemberType NoteProperty -Name 'TiposFlujoParametros' -Value @{}
        }
        $cacheTiposFlujo = $Indice.TiposFlujoParametros
        $claveCache = $Programa.GetAttribute('fullyQualifiedName') + '|' + $VariableSdt + '|' + $ruta
        if ($cacheTiposFlujo.ContainsKey($claveCache)) {
            if ($cacheTiposFlujo[$claveCache] -eq 'EN_CURSO') { return '' }
            return [string]$cacheTiposFlujo[$claveCache]
        }
        $cacheTiposFlujo[$claveCache] = 'EN_CURSO'
    }
    $spansFlujo = $null
    if ($Indice) {
        if (-not $Indice.PSObject.Properties['SpansLlamadaPorFuente']) {
            $Indice | Add-Member -MemberType NoteProperty -Name 'SpansLlamadaPorFuente' -Value @{}
        }
        $claveFuente = $Programa.GetAttribute('fullyQualifiedName') + '|' + $Source.Length + '|' + $Source.GetHashCode()
        if (-not $Indice.SpansLlamadaPorFuente.ContainsKey($claveFuente)) {
            $Indice.SpansLlamadaPorFuente[$claveFuente] = @(Obtener-SpansLlamada -Source $Source -PatronNombre '[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*')
        }
        $spansFlujo = $Indice.SpansLlamadaPorFuente[$claveFuente]
    } else {
        $spansFlujo = @(Obtener-SpansLlamada -Source $Source -PatronNombre '[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*')
    }
    foreach ($span in $spansFlujo) {
        $nombre = ([regex]::Match($span.Texto, '^([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)')).Groups[1].Value
        if (-not $nombre -or $nombre -match '(?i)^(if|for|while|format|GenerarAPIGLMResponse|FromJson|ToJson|ToString|ToNumeric|Item)$') { continue }
        $interior = Obtener-InteriorLlamada -Span $span
        if (-not $interior) { continue }
        $reales = @(Obtener-ArgumentosLlamada -Interior $interior)
        $patronRealBuscado = '^\s*&' + [regex]::Escape($VariableSdt) + '(?:\.|\s*$)'
        if (-not @($reales | Where-Object { $_ -match $patronRealBuscado }).Count) { continue }
        $objeto = Resolver-ObjetoLlamado -Xml $Xml -Nombre $nombre -Indice $Indice -Origen $Programa -IncluirSufijos
        if (-not $objeto) { continue }
        $fqn = $objeto.GetAttribute('fullyQualifiedName')
        $clave = $fqn + '|' + $VariableSdt + '|' + $ruta
        if ($Visitados.Contains($clave)) { continue }
        [void]$Visitados.Add($clave)
        $formales = @(Obtener-ParametrosFormales -Parm (Obtener-ReglaParm -Objeto $objeto))
        if ($formales.Count -eq 0) { continue }
        $sourceHijo = $null
        try { $sourceHijo = Obtener-Source -ProgramaPrincipal $objeto } catch { $sourceHijo = $null }
        if (-not $sourceHijo) { continue }
        for ($i = 0; $i -lt [Math]::Min($formales.Count, $reales.Count); $i++) {
            $formal = $formales[$i]
            if ($formal.Direccion -eq 'out') { continue }
            $realMatch = [regex]::Match($reales[$i].Trim(), '^&([A-Za-z_][A-Za-z0-9_]*)(?:\.([A-Za-z_][A-Za-z0-9_.]*))?$')
            if (-not $realMatch.Success -or $realMatch.Groups[1].Value -ne $VariableSdt) { continue }
            if ($realMatch.Groups[2].Value -and $realMatch.Groups[2].Value -ne $ruta) { continue }
            $segmentosRuta = @($ruta -split '\.' | ForEach-Object { [regex]::Escape($_) })
            $rutaFormal = $segmentosRuta -join '\s*\.\s*'
            $patronLecturaHija = [regex]::new('&' + [regex]::Escape($formal.Variable) + '\s*\.\s*' + $rutaFormal + '\b')
            if (-not $patronLecturaHija.IsMatch((Obtener-SourceLimpio -Source $sourceHijo))) { continue }
            $patronAsignacion = [regex]::new('(?mi)^\s*&([A-Za-z_][A-Za-z0-9_]*)\s*=\s*&' + [regex]::Escape($formal.Variable) + '\s*\.\s*' + $rutaFormal + '\b')
            $tipos = New-Object System.Collections.Generic.List[string]
            foreach ($m in $patronAsignacion.Matches((Obtener-SourceLimpio -Source $sourceHijo))) {
                $nodosHijo = @($objeto)
                $tipoDestino = Resolver-TipoVariable -Xml $Xml -Variable $m.Groups[1].Value -Nodos $nodosHijo -Indice $Indice
                if ($tipoDestino) { $tipos.Add($tipoDestino) }
            }
            $distintos = @($tipos | Select-Object -Unique)
            if ($distintos.Count -eq 1) {
                if ($cacheTiposFlujo) { $cacheTiposFlujo[$claveCache] = $distintos[0] }
                return $distintos[0]
            }
            $tipoTransitivo = Resolver-TipoPorFlujoParametros -Xml $Xml -Programa $objeto -Source $sourceHijo -VariableSdt $formal.Variable -Fila $Fila -Indice $Indice -Visitados $Visitados
            if ($tipoTransitivo) {
                if ($cacheTiposFlujo) { $cacheTiposFlujo[$claveCache] = $tipoTransitivo }
                return $tipoTransitivo
            }
        }
    }
    if ($cacheTiposFlujo) { $cacheTiposFlujo[$claveCache] = '' }
    return ''
}

function Construir-MensajeEstructura {
    <#
    .SYNOPSIS
    Construye el mensaje de error cuando falta un SDT o existe un ciclo.
    .DESCRIPTION
    Registra el nombre del SDT faltante y la ruta JSON de cada estructura con
    problema, segun el contexto indicado (entrada o salida).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][object[]]$Faltantes = @(),
        [Parameter(Mandatory = $false)][object[]]$Ciclos = @(),
        [Parameter(Mandatory = $false)][string]$Contexto = ''
    )

    $detalles = New-Object System.Collections.Generic.List[string]
    foreach ($faltante in $Faltantes) {
        $detalles.Add('SDT faltante ' + $faltante.NombreSdt + ' en la ruta ' + $faltante.RutaJson + ' (no está exportado en el XPZ configurado; no puede inferirse)')
    }
    foreach ($ciclo in $Ciclos) {
        $detalles.Add('ciclo SDT en la ruta ' + $ciclo.RutaJson)
    }
    if ($detalles.Count -eq 0) { return '' }
    return 'No se puede confirmar la estructura ' + $Contexto + ': ' + ($detalles -join '; ') + '. No se genera el documento.'
}

function Resolver-NotasSalidaRecursiva {
    <# Describe una salida recursiva únicamente con evidencia del DataProvider exportado. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$ProgramaPrincipal,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $false)][object[]]$ReferenciasRecursivas = @(),
        [Parameter(Mandatory = $false)]$Indice
    )

    if (@($ReferenciasRecursivas).Count -eq 0) { return @() }
    $notas = New-Object System.Collections.Generic.List[string]
    $llamadaUdp = [regex]::Match($Source, '(?mi)^\s*&[A-Za-z_][A-Za-z0-9_]*\s*=\s*([A-Za-z_][A-Za-z0-9_.]*)\.Udp\s*\(\s*\)')
    if ($llamadaUdp.Success) {
        $dataProvider = Resolver-ObjetoLlamado -Xml $Xml -Nombre ($llamadaUdp.Groups[1].Value + '.Udp') -Indice $Indice -Origen $ProgramaPrincipal -IncluirSufijos
        if ($dataProvider) {
            $sourceDataProvider = Obtener-Source -ProgramaPrincipal $dataProvider
            $posicionChildren = $sourceDataProvider.IndexOf('Children', [System.StringComparison]::OrdinalIgnoreCase)
            if ($posicionChildren -ge 0) {
                $sourceRaiz = $sourceDataProvider.Substring(0, $posicionChildren)
                $sourceHijos = $sourceDataProvider.Substring($posicionChildren)
                $idRaiz = [regex]::Match($sourceRaiz, '(?mi)^\s*ID\s*=\s*([A-Za-z_][A-Za-z0-9_]*)')
                $idHijo = [regex]::Match($sourceHijos, '(?mi)^\s*ID\s*=\s*([A-Za-z_][A-Za-z0-9_]*)')
                $descripcionRaiz = ''
                $descripcionHijo = ''
                if ($idRaiz.Success) {
                    $atributoRaiz = Obtener-Referencia -Tipo 'Attribute' -Nombre $idRaiz.Groups[1].Value -Indice $Indice -Xml $Xml
                    if ($atributoRaiz) { $descripcionRaiz = Obtener-DescripcionCampo -Xml $Xml -Item $atributoRaiz -Indice $Indice }
                }
                if ($idHijo.Success) {
                    $atributoHijo = Obtener-Referencia -Tipo 'Attribute' -Nombre $idHijo.Groups[1].Value -Indice $Indice -Xml $Xml
                    if ($atributoHijo) { $descripcionHijo = Obtener-DescripcionCampo -Xml $Xml -Item $atributoHijo -Indice $Indice }
                }
                if ($descripcionRaiz -and $descripcionHijo) {
                    $notas.Add('El DataProvider organiza los elementos raíz por ' + $descripcionRaiz + ' y carga en Children elementos identificados por ' + $descripcionHijo + '. Children repite la misma estructura.')
                } else {
                    $notas.Add('El DataProvider organiza la salida en elementos raíz y elementos Children. Children repite la misma estructura.')
                }
            }
        }
    }
    if ($notas.Count -eq 0) {
        foreach ($referencia in @($ReferenciasRecursivas)) {
            $notas.Add('La ruta ' + $referencia.RutaJson + ' repite recursivamente la misma estructura.')
        }
    }
    return @($notas | Select-Object -Unique)
}

function Confirmar-LogicaREST {
    <#
    .SYNOPSIS
    Confirma que el Source del wrapper contiene logica REST reconocible.
    .DESCRIPTION
    Busca patrones de API REST en el Source: APIGLMRequestIn.QueryParams (GET),
    APIGLMRequestIn.Body (POST), GenerarAPIGLMResponse o HttpResponse.AddFile.
    Si el Source no contiene ninguno de estos patrones, el wrapper no responde
    a una estructura API REST y debe marcarse como error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source
    )

    $patronesREST = @(
        'APIGLMRequestIn\.QueryParams',
        'APIGLMRequestIn\.Body',
        'GenerarAPIGLMResponse',
        'HttpResponse\.AddFile',
        'HttpResponse\.AddString',
        'GenerarHttpResponse'
    )
    foreach ($patron in $patronesREST) {
        if ($Source -match $patron) { return $true }
    }
    return $false
}

function Agregar-DetallePendiente {
    <# Mantiene la celda breve y transporta el diagnóstico completo al resultado. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Fila,
        [Parameter(Mandatory = $true)][string]$Objeto,
        [Parameter(Mandatory = $true)][string]$Contexto,
        [Parameter(Mandatory = $false)][object[]]$Nodos = @(),
        [Parameter(Mandatory = $false)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $false)]$Indice
    )

    if (($Fila.Tipo -match '^PENDIENTE') -or ($Fila.Descripcion -match '^PENDIENTE')) {
        $ruta = $Fila.Campo
        if ($Fila.PSObject.Properties['RutaJson'] -and $Fila.RutaJson) { $ruta = $Fila.RutaJson }
        $nombres = @($Nodos | ForEach-Object { $_.GetAttribute('fullyQualifiedName') } | Where-Object { $_ } | Select-Object -Unique)
        $trazas = New-Object System.Collections.Generic.List[string]
        if ($Fila.Tipo -match '^PENDIENTE' -and $Xml) {
            $campoEscapado = [regex]::Escape($Fila.Campo)
            foreach ($nodo in $Nodos) {
                $fuente = $null
                try { $fuente = Obtener-Source -ProgramaPrincipal $nodo } catch { $fuente = $null }
                if (-not $fuente) { continue }
                $fuenteLimpia = Obtener-SourceLimpio -Source $fuente

                $patronEscritura = [regex]::new('(?mi)^\s*&[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*\.' + $campoEscapado + '\s*=\s*(.+?)\s*$')
                foreach ($asignacion in $patronEscritura.Matches($fuenteLimpia)) {
                    $sentencia = $asignacion.Value.Trim()
                    if (-not $trazas.Contains($sentencia)) { $trazas.Add($sentencia) }
                    $rhs = Normalizar-Rhs -Texto $asignacion.Groups[1].Value
                    if ($rhs -match '^([A-Za-z_][A-Za-z0-9_]*)$') {
                        $simbolo = $Matches[1]
                        if (-not (Resolver-TipoAtributo -Xml $Xml -Nombre $simbolo -Indice $Indice)) {
                            $detalleSimbolo = $simbolo + ' no declara tipo, longitud ni decimales'
                            if ($fuenteLimpia -match ('(?i)\b' + [regex]::Escape($simbolo) + '\b\s*(?:[+\-*/]|<=|>=|<|>|=\s*\d)')) {
                                $detalleSimbolo += '; el uso confirma familia numérica, pero no Integer/Decimal ni dimensión'
                            }
                            if (-not $trazas.Contains($detalleSimbolo)) { $trazas.Add($detalleSimbolo) }
                        }
                    }
                }

                $patronLectura = [regex]::new('(?mi)^\s*&([A-Za-z_][A-Za-z0-9_]*)\s*=\s*&[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*\.' + $campoEscapado + '\s*$')
                foreach ($lectura in $patronLectura.Matches($fuenteLimpia)) {
                    $receptor = $lectura.Groups[1].Value
                    $sentencia = $lectura.Value.Trim()
                    if (-not $trazas.Contains($sentencia)) { $trazas.Add($sentencia) }
                    if (-not (Resolver-TipoVariable -Xml $Xml -Variable $receptor -Nodos @($nodo) -Indice $Indice)) {
                        $detalleReceptor = '&' + $receptor + ' no tiene tipo declarado'
                        if (-not $trazas.Contains($detalleReceptor)) { $trazas.Add($detalleReceptor) }
                    }
                    $procedimientosAusentes = New-Object System.Collections.Generic.List[string]
                    foreach ($span in (Obtener-SpansLlamada -Source $fuenteLimpia -PatronNombre '[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*')) {
                        $interiorLlamada = Obtener-InteriorLlamada -Span $span
                        if (-not $interiorLlamada) { continue }
                        $argumentos = Obtener-ArgumentosLlamada -Interior $interiorLlamada
                        if (-not (@($argumentos | Where-Object { $_.Trim() -eq ('&' + $receptor) }).Count -gt 0)) { continue }
                        $nombreLlamada = ([regex]::Match($span.Texto, '^([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)')).Groups[1].Value
                        if (-not $nombreLlamada) { continue }
                        if (-not (Resolver-ObjetoLlamado -Xml $Xml -Nombre $nombreLlamada -Indice $Indice -Origen $nodo -IncluirSufijos)) {
                            if (-not $procedimientosAusentes.Contains($nombreLlamada)) { $procedimientosAusentes.Add($nombreLlamada) }
                        }
                    }
                    if ($procedimientosAusentes.Count -gt 0) {
                        $detalleAusentes = 'Procedures receptores no exportados: ' + ($procedimientosAusentes -join ', ')
                        if (-not $trazas.Contains($detalleAusentes)) { $trazas.Add($detalleAusentes) }
                    }
                }
            }
        }
        $detalleTraza = ''
        if ($trazas.Count -gt 0) { $detalleTraza = ' Traza observada: ' + (($trazas | Select-Object -Unique) -join ' -> ') + '.' }
        $cadena = 'Objeto ' + $Objeto + ', ruta ' + $ruta + '. Nodos recorridos: ' + $(if ($nombres.Count -gt 0) { $nombres -join ' -> ' } else { '(ninguno)' }) + '.' + $detalleTraza + ' Evidencia requerida: declaración o asignación inequívoca del ' + $Contexto + '.'
        $Fila | Add-Member -MemberType NoteProperty -Name 'DetallePendiente' -Value $cadena -Force
    }
}

function Analizar-Servicio {
    <#
    .SYNOPSIS
    Analiza un servicio desde el XPZ y arma la documentación técnica unica.
    .DESCRIPTION
    Encadena la confirmacion del wrapper, la delegacion al programa principal,
    el metodo, la entrada (GET o POST), la expansion de estructuras, la
    obligatoriedad, la salida, los errores y el endpoint publicado. Devuelve la
    documentación que consumen la redaccion y la escritura de salidas.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][string]$NombreCompletoWrapper,
        [Parameter(Mandatory = $true)][string]$PackageName,
        [Parameter(Mandatory = $false)]$Indice
    )

    $wrapper = Obtener-Objeto -Xml $Xml -NombreCompleto $NombreCompletoWrapper -Indice $Indice
    if (-not $wrapper) {
        throw ('No se encontro el wrapper ' + $NombreCompletoWrapper + ' en el XPZ.')
    }
    Confirmar-Wrapper -Objeto $wrapper | Out-Null

    $nombreMain = Obtener-DelegacionUnica -Xml $Xml -Wrapper $wrapper -Indice $Indice
    if ($nombreMain) {
        $programaPrincipal = Obtener-Objeto -Xml $Xml -NombreCompleto $nombreMain -Indice $Indice
        if (-not $programaPrincipal) {
            throw ('No se encontro el programa principal ' + $nombreMain + ' en el XPZ.')
        }
    } else {
        $wrapperSource = Obtener-Source -ProgramaPrincipal $wrapper
        if (-not (Confirmar-LogicaREST -Source $wrapperSource)) {
            throw ('El wrapper ' + $NombreCompletoWrapper + ' no tiene estructura API REST y no delega en un programa principal. No se genera el documento.')
        }
        $programaPrincipal = $wrapper
    }
    $source = Obtener-Source -ProgramaPrincipal $programaPrincipal
    $metodo = Resolver-Metodo -Source $source

    $fuentesObligatorio = @()
    try { $fuentesObligatorio = Obtener-SourcesEvidencia -Xml $Xml -ProgramaPrincipal $programaPrincipal -Indice $Indice -IncluirSufijos } catch { $fuentesObligatorio = @() }

    $pendientes = New-Object System.Collections.Generic.List[string]

    $entrada = @()
    $estructuras = @()
    $faltantesEntrada = @()
    $ciclosEntrada = @()
    if ($metodo -eq 'POST') {
        $entradaPost = Resolver-EntradaPost -Xml $Xml -ProgramaPrincipal $programaPrincipal -Source $source -Indice $Indice
        $expandido = Expandir-EstructuraSdt -Xml $Xml -Sdt $entradaPost.Sdt -Indice $Indice
        $faltantesEntrada = @($expandido.Faltantes)
        $ciclosEntrada = @($expandido.Ciclos)
        if ($faltantesEntrada.Count -gt 0) {
            throw (Construir-MensajeEstructura -Faltantes $faltantesEntrada -Contexto 'de la entrada')
        }
        Aplicar-Obligatorio -Source $source -Filas @($expandido.Filas) -Tablas @($expandido.Tablas) -VariableSdt $entradaPost.VariableSdt -SourcesAdicionales $fuentesObligatorio -Xml $Xml -ProgramaPrincipal $programaPrincipal -Indice $Indice
        $nodosEvidenciaEntrada = Obtener-NodosEvidencia -Xml $Xml -ProgramaPrincipal $programaPrincipal -Indice $Indice
        $nodosEvidenciaEntradaSufijos = $null
        foreach ($filaEntrada in $expandido.Filas) {
            if ($filaEntrada.Tipo -notmatch '^PENDIENTE DE CONFIRMACIÓN: tipo del campo') { continue }
            $tipoLectura = Resolver-TipoPorLectura -Xml $Xml -Campo $filaEntrada.Campo -VariableSdt $entradaPost.VariableSdt -Nodos $nodosEvidenciaEntrada -Indice $Indice
            if (-not $tipoLectura -and $null -eq $nodosEvidenciaEntradaSufijos) {
                $nodosEvidenciaEntradaSufijos = Obtener-NodosEvidencia -Xml $Xml -ProgramaPrincipal $programaPrincipal -Indice $Indice -IncluirSufijos -ProfundidadMaxima 5
            }
            if (-not $tipoLectura) {
                $tipoLectura = Resolver-TipoPorLectura -Xml $Xml -Campo $filaEntrada.Campo -VariableSdt $entradaPost.VariableSdt -Nodos $nodosEvidenciaEntradaSufijos -Indice $Indice
            }
            if (-not $tipoLectura) {
                $tipoLectura = Resolver-TipoPorFlujoParametros -Xml $Xml -Programa $programaPrincipal -Source $source -VariableSdt $entradaPost.VariableSdt -Fila $filaEntrada -Indice $Indice
            }
            if (-not $tipoLectura -and $filaEntrada.SdtFqn -and $filaEntrada.RutaSdt) {
                $tipoLectura = Resolver-TipoMiembroSdtGlobal -Xml $Xml -SdtFqn $filaEntrada.SdtFqn -RutaSdt $filaEntrada.RutaSdt -Indice $Indice
            }
            if ($tipoLectura) { $filaEntrada.Tipo = $tipoLectura }
        }
        foreach ($tablaEntrada in $expandido.Tablas) {
            foreach ($filaEntrada in $tablaEntrada.Filas) {
                if ($filaEntrada.Tipo -notmatch '^PENDIENTE DE CONFIRMACIÓN: tipo del campo') { continue }
                $tipoLectura = Resolver-TipoPorLectura -Xml $Xml -Campo $filaEntrada.Campo -VariableSdt $entradaPost.VariableSdt -Nodos $nodosEvidenciaEntrada -Indice $Indice
                if (-not $tipoLectura -and $null -eq $nodosEvidenciaEntradaSufijos) {
                    $nodosEvidenciaEntradaSufijos = Obtener-NodosEvidencia -Xml $Xml -ProgramaPrincipal $programaPrincipal -Indice $Indice -IncluirSufijos -ProfundidadMaxima 5
                }
                if (-not $tipoLectura) {
                    $tipoLectura = Resolver-TipoPorLectura -Xml $Xml -Campo $filaEntrada.Campo -VariableSdt $entradaPost.VariableSdt -Nodos $nodosEvidenciaEntradaSufijos -Indice $Indice
                }
                if (-not $tipoLectura) {
                    $tipoLectura = Resolver-TipoPorFlujoParametros -Xml $Xml -Programa $programaPrincipal -Source $source -VariableSdt $entradaPost.VariableSdt -Fila $filaEntrada -Indice $Indice
                }
                if (-not $tipoLectura -and $filaEntrada.SdtFqn -and $filaEntrada.RutaSdt) {
                    $tipoLectura = Resolver-TipoMiembroSdtGlobal -Xml $Xml -SdtFqn $filaEntrada.SdtFqn -RutaSdt $filaEntrada.RutaSdt -Indice $Indice
                }
                if ($tipoLectura) { $filaEntrada.Tipo = $tipoLectura }
            }
        }
        $entrada = @($expandido.Filas | ForEach-Object {
            [pscustomobject]@{ Orden = 0; Campo = $_.Campo; RutaJson = $_.RutaJson; SdtFqn = $_.SdtFqn; RutaSdt = $_.RutaSdt; Tipo = $_.Tipo; Obligatorio = $_.Obligatorio; Descripcion = $_.Descripcion; DetallePendiente = $_.DetallePendiente; ReferenciaRecursiva = $_.ReferenciaRecursiva }
        })
        $estructuras = @($expandido.Tablas | ForEach-Object {
            [pscustomobject]@{
                RutaJson = $_.Ruta
                EsColeccion = $_.EsColeccion
                Hijos = @($_.Filas | ForEach-Object {
                    [pscustomobject]@{ Campo = $_.Campo; RutaJson = $_.RutaJson; SdtFqn = $_.SdtFqn; RutaSdt = $_.RutaSdt; Tipo = $_.Tipo; Obligatorio = $_.Obligatorio; Descripcion = $_.Descripcion; DetallePendiente = $_.DetallePendiente; ReferenciaRecursiva = $_.ReferenciaRecursiva }
                })
            }
        })
    } else {
        $posiciones = Resolver-EntradaGet -Source $source
        $posicionesTipos = Resolver-EntradaGetTipos -Xml $Xml -ProgramaPrincipal $programaPrincipal -Source $source -Posiciones @($posiciones) -Indice $Indice
        Aplicar-Obligatorio -Source $source -Filas @($posicionesTipos) -SourcesAdicionales $fuentesObligatorio -Xml $Xml -ProgramaPrincipal $programaPrincipal -Indice $Indice
        $entrada = @($posicionesTipos | ForEach-Object {
            [pscustomobject]@{ Orden = $_.Posicion; Campo = $_.Campo; RutaJson = $_.Campo; Tipo = $_.Tipo; Obligatorio = $_.Obligatorio; Descripcion = $_.Descripcion; DetallePendiente = $_.DetallePendiente }
        })
    }

    $salida = Resolver-Salida -Xml $Xml -ProgramaPrincipal $programaPrincipal -Source $source -Indice $Indice
    if (@($salida.Faltantes).Count -gt 0) {
        throw (Construir-MensajeEstructura -Faltantes @($salida.Faltantes) -Contexto 'de la salida')
    }
    if ($salida.NoResuelta) {
        if ($salida.MotivoNoResuelta) {
            throw $salida.MotivoNoResuelta
        }
        throw 'No se puede determinar la estructura de la salida del servicio. No se genera el documento.'
    } else {
        $nodosEvidencia = Obtener-NodosEvidencia -Xml $Xml -ProgramaPrincipal $programaPrincipal -Indice $Indice
        $nodosEvidenciaSufijos = $null
        foreach ($campoSalida in $salida.Salida) {
            if ($campoSalida.Tipo -notmatch '^PENDIENTE DE CONFIRMACIÓN: tipo del campo') { continue }
            $tipoSalida = Resolver-TipoPorAsignacion -Xml $Xml -Campo $campoSalida.Campo -RutaJson $campoSalida.RutaJson -Nodos $nodosEvidencia -Indice $Indice
            if (-not $tipoSalida -and $null -eq $nodosEvidenciaSufijos) {
                $nodosEvidenciaSufijos = Obtener-NodosEvidencia -Xml $Xml -ProgramaPrincipal $programaPrincipal -Indice $Indice -IncluirSufijos -ProfundidadMaxima 5
            }
            if (-not $tipoSalida) {
                $tipoSalida = Resolver-TipoPorAsignacion -Xml $Xml -Campo $campoSalida.Campo -RutaJson $campoSalida.RutaJson -Nodos $nodosEvidenciaSufijos -Indice $Indice
            }
            if (-not $tipoSalida -and $campoSalida.SdtFqn -and $campoSalida.RutaSdt) {
                $tipoSalida = Resolver-TipoMiembroSdtGlobal -Xml $Xml -SdtFqn $campoSalida.SdtFqn -RutaSdt $campoSalida.RutaSdt -Indice $Indice
            }
            if ($tipoSalida) { $campoSalida.Tipo = $tipoSalida }
        }
        foreach ($estructuraSalida in $salida.EstructurasSalida) {
            foreach ($hijoSalida in $estructuraSalida.Hijos) {
                if ($hijoSalida.Tipo -notmatch '^PENDIENTE DE CONFIRMACIÓN: tipo del campo') { continue }
                $tipoHijo = Resolver-TipoPorAsignacion -Xml $Xml -Campo $hijoSalida.Campo -RutaJson $hijoSalida.RutaJson -Nodos $nodosEvidencia -Indice $Indice
                if (-not $tipoHijo -and $null -eq $nodosEvidenciaSufijos) {
                    $nodosEvidenciaSufijos = Obtener-NodosEvidencia -Xml $Xml -ProgramaPrincipal $programaPrincipal -Indice $Indice -IncluirSufijos -ProfundidadMaxima 5
                }
                if (-not $tipoHijo) {
                    $tipoHijo = Resolver-TipoPorAsignacion -Xml $Xml -Campo $hijoSalida.Campo -RutaJson $hijoSalida.RutaJson -Nodos $nodosEvidenciaSufijos -Indice $Indice
                }
                if (-not $tipoHijo -and $hijoSalida.SdtFqn -and $hijoSalida.RutaSdt) {
                    $tipoHijo = Resolver-TipoMiembroSdtGlobal -Xml $Xml -SdtFqn $hijoSalida.SdtFqn -RutaSdt $hijoSalida.RutaSdt -Indice $Indice
                }
                if ($tipoHijo) { $hijoSalida.Tipo = $tipoHijo }
            }
        }
    }
    $nodosDiagnostico = @()
    try { $nodosDiagnostico = Obtener-NodosEvidencia -Xml $Xml -ProgramaPrincipal $programaPrincipal -Indice $Indice -IncluirSufijos -ProfundidadMaxima 5 } catch { $nodosDiagnostico = @() }
    foreach ($campoEntrada in $entrada) { Agregar-DetallePendiente -Fila $campoEntrada -Objeto $programaPrincipal.GetAttribute('fullyQualifiedName') -Contexto 'tipo o descripción' -Nodos $nodosDiagnostico -Xml $Xml -Indice $Indice }
    foreach ($estructuraEntrada in $estructuras) {
        foreach ($hijoEntrada in $estructuraEntrada.Hijos) { Agregar-DetallePendiente -Fila $hijoEntrada -Objeto $programaPrincipal.GetAttribute('fullyQualifiedName') -Contexto 'tipo o descripción' -Nodos $nodosDiagnostico -Xml $Xml -Indice $Indice }
    }
    foreach ($campoSalidaDetalle in $salida.Salida) { Agregar-DetallePendiente -Fila $campoSalidaDetalle -Objeto $programaPrincipal.GetAttribute('fullyQualifiedName') -Contexto 'tipo o descripción de salida' -Nodos $nodosDiagnostico -Xml $Xml -Indice $Indice }
    foreach ($estructuraSalidaDetalle in $salida.EstructurasSalida) {
        foreach ($hijoSalidaDetalle in $estructuraSalidaDetalle.Hijos) { Agregar-DetallePendiente -Fila $hijoSalidaDetalle -Objeto $programaPrincipal.GetAttribute('fullyQualifiedName') -Contexto 'tipo o descripción de salida' -Nodos $nodosDiagnostico -Xml $Xml -Indice $Indice }
    }
    $notasSalida = Resolver-NotasSalidaRecursiva -Xml $Xml -ProgramaPrincipal $programaPrincipal -Source $source -ReferenciasRecursivas @($salida.Ciclos) -Indice $Indice

    $errores = Resolver-Errores -Source $source
    $endpoint = Resolver-Endpoint -NombreCompletoWrapper $NombreCompletoWrapper -PackageName $PackageName

    $nombreFuncional = $wrapper.GetAttribute('description')
    $descripcion = $nombreFuncional
    if (-not $nombreFuncional) {
        $pendienteDescripcion = 'PENDIENTE DE CONFIRMACIÓN: descripción funcional del servicio.'
        $nombreFuncional = $pendienteDescripcion
        $descripcion = $pendienteDescripcion
    }

    if ($endpoint -match '^PENDIENTE') { $pendientes.Add($endpoint) }
    foreach ($campo in $entrada) {
        if ($campo.Tipo -match '^PENDIENTE') { $pendientes.Add($campo.Tipo) }
        if ($campo.Descripcion -match '^PENDIENTE') { $pendientes.Add($campo.Descripcion) }
        if ($campo.DetallePendiente) { $pendientes.Add($campo.DetallePendiente) }
    }
    foreach ($estructura in $estructuras) {
        foreach ($hijo in $estructura.Hijos) {
            if ($hijo.Tipo -match '^PENDIENTE') { $pendientes.Add($hijo.Tipo) }
            if ($hijo.Descripcion -match '^PENDIENTE') { $pendientes.Add($hijo.Descripcion) }
            if ($hijo.DetallePendiente) { $pendientes.Add($hijo.DetallePendiente) }
        }
    }
    foreach ($estructura in $salida.EstructurasSalida) {
        foreach ($hijo in $estructura.Hijos) {
            if ($hijo.Tipo -match '^PENDIENTE') { $pendientes.Add($hijo.Tipo) }
            if ($hijo.Descripcion -match '^PENDIENTE') { $pendientes.Add($hijo.Descripcion) }
            if ($hijo.DetallePendiente) { $pendientes.Add($hijo.DetallePendiente) }
        }
    }
    foreach ($campo in $salida.Salida) {
        if ($campo.Tipo -match '^PENDIENTE') { $pendientes.Add($campo.Tipo) }
        if ($campo.Descripcion -match '^PENDIENTE') { $pendientes.Add($campo.Descripcion) }
        if ($campo.DetallePendiente) { $pendientes.Add($campo.DetallePendiente) }
    }

    return [pscustomobject]@{
        FqWrapper = $NombreCompletoWrapper
        ProgramaPrincipal = $(if ($nombreMain) { $nombreMain } else { $NombreCompletoWrapper })
        MetodoHttp = $metodo
        EndpointPublicado = $endpoint
        NombreFuncional = $nombreFuncional
        Descripcion = $descripcion
        Entrada = $entrada
        Estructuras = $estructuras
        EstructurasSalida = $salida.EstructurasSalida
        ReferenciasRecursivasSalida = @($salida.Ciclos)
        SalidaColeccion = $salida.SalidaColeccion
        Salida = $salida.Salida
        SalidaVacia = $salida.SalidaVacia
        TipoColeccionPrimitiva = $salida.TipoColeccionPrimitiva
        TipoContenidoSalida = $salida.TipoContenidoSalida
        MensajesSalida = $(if ($salida.MensajesSalida) { @($salida.MensajesSalida) } else { @() })
        NotasSalida = @($notasSalida)
        Errores = $errores
        Pendientes = $pendientes.ToArray()
        FaltantesEntrada = $faltantesEntrada
        CiclosEntrada = $ciclosEntrada
    }
}
