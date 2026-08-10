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
    if ($candidatos.Count -eq 0) { return $null }
    if ($Modulo) {
        $conModulo = @($candidatos | Where-Object { $_.GetAttribute('fullyQualifiedName').StartsWith($Modulo + '.') })
        if ($conModulo.Count -eq 1) { return $conModulo[0] }
    }
    if ($candidatos.Count -eq 1) { return $candidatos[0] }
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
        throw ('No se pudo localizar el SDT ' + $nombreSdt + ' en el XPZ.')
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
    la descripcion del objeto Domain o Attribute referenciado por idBasedOn.
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

function Resolver-Campo {
    <#
    .SYNOPSIS
    Resuelve un campo de entrada (item de SDT o Level inline) con su tipo canonico y descripcion.
    .DESCRIPTION
    Devuelve un objeto con Campo, Tipo, Descripcion y los datos de estructura para
    la expansion posterior. Cuando el tipo no puede confirmarse, lanza un error que
    detiene la generacion del documento con el servicio y el campo afectados.
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
        if (-not $descripcion) { $descripcion = $nombre }
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
        [Parameter(Mandatory = $false)]$Indice,
        [Parameter(Mandatory = $false)][System.Collections.Generic.HashSet[string]]$Ancestros = $null
    )

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
        $resuelto | Add-Member -MemberType NoteProperty -Name 'RutaJson' -Value $rutaCampo -Force
        $filas.Add($resuelto)
        if (-not $resuelto.EsEstructura) { continue }

        if ($resuelto.EsInline) {
            $nodoHijo = $resuelto.NodoInline
            $guidHijo = $nodoHijo.GetAttribute('guid')
            if ($guidHijo -and $Ancestros.Contains($guidHijo)) {
                $ciclos.Add([pscustomobject]@{ NombreSdt = $resuelto.NombreSdt; RutaJson = $rutaCampo })
                continue
            }
            $nuevosAncestros = New-Object 'System.Collections.Generic.HashSet[string]'
            foreach ($ancestro in $Ancestros) { [void]$nuevosAncestros.Add($ancestro) }
            if ($guidHijo) { [void]$nuevosAncestros.Add($guidHijo) }

            $recursivo = Expandir-EstructuraSdt -Xml $Xml -Sdt $nodoHijo -RutaJson $rutaCampo -Indice $Indice -Ancestros $nuevosAncestros
        } else {
            $sdtHijo = Obtener-Sdt -Xml $Xml -NombreSdt $resuelto.NombreSdt -Modulo $resuelto.ModuloSdt -Indice $Indice
            if (-not $sdtHijo) {
                $faltantes.Add([pscustomobject]@{ NombreSdt = $resuelto.NombreSdt; RutaJson = $rutaCampo })
                continue
            }
            $guidHijo = $sdtHijo.GetAttribute('guid')
            if ($guidHijo -and $Ancestros.Contains($guidHijo)) {
                $ciclos.Add([pscustomobject]@{ NombreSdt = $resuelto.NombreSdt; RutaJson = $rutaCampo })
                continue
            }
            $nuevosAncestros = New-Object 'System.Collections.Generic.HashSet[string]'
            foreach ($ancestro in $Ancestros) { [void]$nuevosAncestros.Add($ancestro) }
            if ($guidHijo) { [void]$nuevosAncestros.Add($guidHijo) }

            $recursivo = Expandir-EstructuraSdt -Xml $Xml -Sdt $sdtHijo -RutaJson $rutaCampo -Indice $Indice -Ancestros $nuevosAncestros
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
    Usa las conversiones explicitas del parser (.ToNumeric, .ToString) y, en su defecto,
    la definicion de la variable. Si el tipo no puede confirmarse, lanza un error que
    detiene la generacion del documento. Conserva el orden y las posiciones exactas.
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
        $patronConversion = [regex]::new('&' + [regex]::Escape($variable) + '\s*=\s*&' + [regex]::Escape($variableColeccion) + '\.Item\(\s*' + $posicion.Posicion + '\s*\)\s*\.([A-Za-z]+)\s*\(')
        $coincidenciaConversion = $patronConversion.Match($Source)
        if ($coincidenciaConversion.Success) {
            $conversion = $coincidenciaConversion.Groups[1].Value
            if ($conversion -eq 'ToNumeric') { $tipo = 'Integer' }
            elseif ($conversion -eq 'ToString') { $tipo = 'String' }
        }

        $variableNodo = Obtener-Variable -ProgramaPrincipal $ProgramaPrincipal -Nombre $variable
        if (-not $tipo -and $variableNodo) {
            $datos = Obtener-DatosTipo -Xml $Xml -Nodo $variableNodo -Indice $Indice
            $tipo = Convertir-TipoCanonico -DatosTipo $datos -NombreCampo $variable
        }
        if (-not $tipo) {
            $tipo = 'PENDIENTE DE CONFIRMACIÓN: tipo del campo ' + $variable + '.'
        }

        $descripcion = ''
        if ($variableNodo) { $descripcion = Obtener-DescripcionCampo -Xml $Xml -Item $variableNodo -Indice $Indice }
        if (-not $descripcion) {
            $descripcion = 'PENDIENTE DE CONFIRMACIÓN: descripcion del campo ' + $variable + '.'
        }

        $entrada.Add([pscustomobject]@{
            Posicion = $posicion.Posicion
            Campo = $variable
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

function Resolver-Obligatorio {
    <#
    .SYNOPSIS
    Calcula la columna Obligatorio segun analisisXPZ.md seccion 4.
    .DESCRIPTION
    El campo se marca SI cuando aparece referenciado en el Source del programa
    principal (where, asignacion, parametro o condicion) o en una comprobacion
    explicita de campo vacio o invalido; NO cuando no aparece. En POST la referencia
    se limita al campo como miembro de la variable SDT deserializada
    (VariableSdt.RutaJson), de modo que los campos homonimos no comparten
    obligatoriedad accidentalmente. En GET se limita a la variable con prefijo &.
    Se limita al programa principal, sin recorrer procedimientos en cascada,
    y se ignoran las lineas de comentario.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][object]$Fila,
        [Parameter(Mandatory = $false)][string]$VariableSdt = ''
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

    if ($codigo -match $patron) {
        return 'SI'
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
        [Parameter(Mandatory = $false)][string]$VariableSdt = ''
    )

    $Fila | Add-Member -MemberType NoteProperty -Name 'Obligatorio' -Value (Resolver-Obligatorio -Source $Source -Fila $Fila -VariableSdt $VariableSdt) -Force
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
        [Parameter(Mandatory = $false)][string]$VariableSdt = ''
    )

    foreach ($fila in $Filas) { Agregar-Obligatorio -Source $Source -Fila $fila -VariableSdt $VariableSdt }
    foreach ($tabla in $Tablas) {
        foreach ($fila in $tabla.Filas) { Agregar-Obligatorio -Source $Source -Fila $fila -VariableSdt $VariableSdt }
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
    $partida = [regex]::Match($texto, "^'([^']*)'(\s*\+\s*[^']+)$")
    if ($partida.Success) {
        $plantilla = $partida.Groups[1].Value
        $variables = @([regex]::Matches($partida.Groups[2].Value, '&\s*([A-Za-z_][A-Za-z0-9_]*)') | ForEach-Object { $_.Groups[1].Value })
        foreach ($variable in $variables) { $plantilla += '<' + $variable + '>' }
        return $plantilla
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
    $spans = Obtener-SpansLlamada -Source $Source -PatronNombre 'GenerarAPIGLMResponse'
    foreach ($span in $spans) {
        $interior = Obtener-InteriorLlamada -Span $span
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
        [Parameter(Mandatory = $false)]$Indice
    )

    $variable = $null
    $spans = Obtener-SpansLlamada -Source $Source -PatronNombre 'GenerarAPIGLMResponse'
    foreach ($span in $spans) {
        $interior = Obtener-InteriorLlamada -Span $span
        $argumentos = Obtener-ArgumentosLlamada -Interior $interior
        if ($argumentos.Count -lt 3) { continue }
        if ($argumentos[0].Trim() -notmatch '^HttpCode\.OK$') { continue }
        $coincidenciaVariable = [regex]::Match($argumentos[2], '&([A-Za-z_][A-Za-z0-9_]*)\s*\.ToJson\s*\(\s*\)')
        if (-not $coincidenciaVariable.Success) { continue }
        $variable = $coincidenciaVariable.Groups[1].Value
    }
    if (-not $variable) {
        if ($Source -match 'HttpResponse\.AddFile') {
            return [pscustomobject]@{
                SalidaColeccion = $false
                Salida = @()
                EstructurasSalida = @()
                Faltantes = @()
                Ciclos = @()
                NoResuelta = $false
                TipoContenidoSalida = 'application/octet-stream'
            }
        }
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
            TipoContenidoSalida = 'application/json'
        }
    }

    $expandido = Expandir-EstructuraSdt -Xml $Xml -Sdt $sdt -Indice $Indice
    $salida = New-Object System.Collections.Generic.List[object]
    foreach ($fila in $expandido.Filas) {
        $salida.Add([pscustomobject]@{
            Campo = $fila.Campo
            Tipo = $fila.Tipo
            Descripcion = $fila.Descripcion
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
            })
        }
        $estructurasSalida.Add([pscustomobject]@{
            RutaJson = $tabla.Ruta
            EsColeccion = $tabla.EsColeccion
            Hijos = $hijos.ToArray()
        })
    }

    return [pscustomobject]@{
        SalidaColeccion = $datosTipo.EsColeccion
        Salida = $salida.ToArray()
        EstructurasSalida = $estructurasSalida.ToArray()
        Faltantes = $expandido.Faltantes
        Ciclos = $expandido.Ciclos
        NoResuelta = $false
        TipoContenidoSalida = 'application/json'
    }
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
        $detalles.Add('SDT faltante ' + $faltante.NombreSdt + ' en la ruta ' + $faltante.RutaJson)
    }
    foreach ($ciclo in $Ciclos) {
        $detalles.Add('ciclo SDT en la ruta ' + $ciclo.RutaJson)
    }
    if ($detalles.Count -eq 0) { return '' }
    return 'No se puede confirmar la estructura ' + $Contexto + ': ' + ($detalles -join '; ') + '. No se genera el documento.'
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
        if ($faltantesEntrada.Count -gt 0 -or $ciclosEntrada.Count -gt 0) {
            throw (Construir-MensajeEstructura -Faltantes $faltantesEntrada -Ciclos $ciclosEntrada -Contexto 'de la entrada')
        }
        Aplicar-Obligatorio -Source $source -Filas @($expandido.Filas) -Tablas @($expandido.Tablas) -VariableSdt $entradaPost.VariableSdt
        $entrada = @($expandido.Filas | ForEach-Object {
            [pscustomobject]@{ Orden = 0; Campo = $_.Campo; Tipo = $_.Tipo; Obligatorio = $_.Obligatorio; Descripcion = $_.Descripcion }
        })
        $estructuras = @($expandido.Tablas | ForEach-Object {
            [pscustomobject]@{
                RutaJson = $_.Ruta
                EsColeccion = $_.EsColeccion
                Hijos = @($_.Filas | ForEach-Object {
                    [pscustomobject]@{ Campo = $_.Campo; Tipo = $_.Tipo; Obligatorio = $_.Obligatorio; Descripcion = $_.Descripcion }
                })
            }
        })
    } else {
        $posiciones = Resolver-EntradaGet -Source $source
        $posicionesTipos = Resolver-EntradaGetTipos -Xml $Xml -ProgramaPrincipal $programaPrincipal -Source $source -Posiciones @($posiciones) -Indice $Indice
        Aplicar-Obligatorio -Source $source -Filas @($posicionesTipos)
        $entrada = @($posicionesTipos | ForEach-Object {
            [pscustomobject]@{ Orden = $_.Posicion; Campo = $_.Campo; Tipo = $_.Tipo; Obligatorio = $_.Obligatorio; Descripcion = $_.Descripcion }
        })
    }

    $salida = Resolver-Salida -Xml $Xml -ProgramaPrincipal $programaPrincipal -Source $source -Indice $Indice
    if (@($salida.Faltantes).Count -gt 0 -or @($salida.Ciclos).Count -gt 0) {
        throw (Construir-MensajeEstructura -Faltantes @($salida.Faltantes) -Ciclos @($salida.Ciclos) -Contexto 'de la salida')
    }
    if ($salida.NoResuelta) {
        $pendientes.Add('PENDIENTE DE CONFIRMACIÓN: estructura de salida.')
    }
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
    }
    foreach ($estructura in $estructuras) {
        foreach ($hijo in $estructura.Hijos) {
            if ($hijo.Tipo -match '^PENDIENTE') { $pendientes.Add($hijo.Tipo) }
            if ($hijo.Descripcion -match '^PENDIENTE') { $pendientes.Add($hijo.Descripcion) }
        }
    }
    foreach ($estructura in $salida.EstructurasSalida) {
        foreach ($hijo in $estructura.Hijos) {
            if ($hijo.Tipo -match '^PENDIENTE') { $pendientes.Add($hijo.Tipo) }
            if ($hijo.Descripcion -match '^PENDIENTE') { $pendientes.Add($hijo.Descripcion) }
        }
    }
    foreach ($campo in $salida.Salida) {
        if ($campo.Tipo -match '^PENDIENTE') { $pendientes.Add($campo.Tipo) }
        if ($campo.Descripcion -match '^PENDIENTE') { $pendientes.Add($campo.Descripcion) }
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
        SalidaColeccion = $salida.SalidaColeccion
        Salida = $salida.Salida
        TipoContenidoSalida = $salida.TipoContenidoSalida
        Errores = $errores
        Pendientes = $pendientes.ToArray()
        FaltantesEntrada = $faltantesEntrada
        CiclosEntrada = $ciclosEntrada
    }
}
