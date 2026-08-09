# AnalizarServicio.ps1
# Modulo de analisis de servicios APIGLM desde el XPZ.
# Se importa por dot-source desde GenerarDocumento.ps1.
# Contiene las funciones de acceso al XPZ y el analisis de la ficha tecnica.
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Abrir-XPZ {
    <#
    .SYNOPSIS
    Abre el XPZ como ZIP de solo lectura y devuelve el XML interno cargado.
    .DESCRIPTION
    Localiza la primera entrada XML del XPZ, lee su contenido,
    lo carga como System.Xml.XmlDocument y valida que la raiz sea ExportFile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaXpz
    )

    if (-not (Test-Path -LiteralPath $RutaXpz)) {
        throw ("No se encontro el archivo XPZ: " + $RutaXpz)
    }
    $RutaXpz = (Resolve-Path -LiteralPath $RutaXpz).Path

    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($RutaXpz)
        $entry = $zip.Entries | Where-Object { $_.Name -like '*.xml' } | Select-Object -First 1
        if (-not $entry) {
            throw ('El XPZ ' + [System.IO.Path]::GetFileName($RutaXpz) + ' no contiene ningún archivo XML.')
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
    return $xml
}

function Obtener-Objeto {
    <#
    .SYNOPSIS
    Localiza un objeto por su atributo fullyQualifiedName exacto.
    .DESCRIPTION
    Devuelve el nodo Object unico o $null si no se encuentra.
    Lanza un error si el nombre aparece mas de una vez en el XPZ.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][string]$NombreCompleto
    )

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
    Recorre el Source del wrapper buscando llamadas a procedimientos y confirma cual
    tiene la firma parm(in:&APIGLMRequestIn, out:&APIGLMResponse). Devuelve el
    fullyQualifiedName del programa principal. Si no hay delegacion unica, lanza un
    error que detiene el analisis sin generar el documento.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Wrapper
    )

    $porNombreCompleto = @{}
    $porNombre = @{}
    foreach ($objeto in $Xml.SelectNodes('//Object')) {
        $nombreCompleto = $objeto.GetAttribute('fullyQualifiedName')
        $nombre = $objeto.GetAttribute('name')
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
    $patronLlamada = [regex]::new('\b([A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*)\s*\(')
    $delegaciones = New-Object System.Collections.Generic.List[string]
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
        }
        if (-not $objeto) { continue }
        $nombreCompletoObjeto = $objeto.GetAttribute('fullyQualifiedName')
        if ($vistos.ContainsKey($nombreCompletoObjeto)) { continue }
        $vistos[$nombreCompletoObjeto] = $true
        $parm = Obtener-ReglaParm -Objeto $objeto
        if ($parm -and ($parm -match '(?i)in\s*:\s*&\s*APIGLMRequestIn') -and ($parm -match '(?i)out\s*:\s*&\s*APIGLMResponse')) {
            $delegaciones.Add($nombreCompletoObjeto)
        }
    }

    if ($delegaciones.Count -eq 0) {
        throw ('No se identifico una delegacion unica (in:&APIGLMRequestIn, out:&APIGLMResponse) en el wrapper ' + $Wrapper.GetAttribute('fullyQualifiedName') + '. No se genera el documento.')
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
    Devuelve el nodo Object unico o $null si no se localiza de forma inequivoca.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][string]$NombreSdt,
        [Parameter(Mandatory = $false)][string]$Modulo = ''
    )

    $candidatos = @($Xml.SelectNodes("//Object[@name='" + $NombreSdt + "']"))
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
    Devuelve los campos directos del item raiz de un SDT.
    .DESCRIPTION
    En el XML cada estructura se representa como un contenedor (atributo Name) que
    contiene el item real (atributo name) y sus campos. Se excluye el item raiz,
    identificado porque su nombre coincide con el nombre del SDT.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Sdt
    )

    $nombreSdt = $Sdt.GetAttribute('name')
    foreach ($part in $Sdt.SelectNodes('Part')) {
        $hijos = @($part.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.Name -ne 'Properties' })
        if ($hijos.Count -eq 0) { continue }
        $contenedor = $hijos[0]
        $campos = @($contenedor.ChildNodes | Where-Object {
            $_.NodeType -eq 'Element' -and $_.GetAttribute('name') -and $_.GetAttribute('name') -ne $nombreSdt
        })
        if ($campos.Count -gt 0) { return @($campos) }
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
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source
    )

    $esPost = $Source -match '(?i)&[A-Za-z_][A-Za-z0-9_]*\s*\.FromJson\s*\(\s*&APIGLMRequestIn\.Body'
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
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$ProgramaPrincipal,
        [Parameter(Mandatory = $true)][string]$Source
    )

    $patron = [regex]::new('&([A-Za-z_][A-Za-z0-9_]*)\s*\.FromJson\s*\(\s*&APIGLMRequestIn\.Body')
    $coincidencia = $patron.Match($Source)
    if (-not $coincidencia.Success) {
        throw 'El programa principal no deserializa APIGLMRequestIn.Body mediante FromJson. No se genera el documento.'
    }
    $variableSdt = $coincidencia.Groups[1].Value
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
    $sdt = Obtener-Sdt -Xml $Xml -NombreSdt $nombreSdt -Modulo $modulo
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

function Obtener-DatosTipo {
    <#
    .SYNOPSIS
    Resuelve la informacion de tipo de un campo o variable (analisisXPZ.md seccion 3).
    .DESCRIPTION
    Sigue la cadena ATTCUSTOMTYPE / idBasedOn (Domain o Attribute) hasta obtener
    el tipo base (bas:X), la estructura (sdt:Nombre) o marcar el tipo como no resuelto.
    No inferir el tipo por el nombre del campo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Nodo
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
        $nombreCompleto = $nodoActual.GetAttribute('fullyQualifiedName')
        if ($nombreCompleto -and $visitados.ContainsKey($nombreCompleto)) {
            $noResuelto = $true
            break
        }
        if ($nombreCompleto) { $visitados[$nombreCompleto] = $true }

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

        $imagen = Obtener-Propiedad -Nodo $nodoActual -Nombre 'ATT_PICTURE'
        if ($imagen) {
            if ($imagen.Contains('@')) { $baseTipo = 'VarChar' } else { $baseTipo = 'Numeric' }
            break
        }

        $partida = [regex]::Match($idBasedOn, '^Domain:(.+)$')
        if ($partida.Success) {
            $objetos = @($Xml.SelectNodes("//Object[@name='" + $partida.Groups[1].Value.Trim() + "']"))
            if ($objetos.Count -eq 1) { $nodoActual = $objetos[0]; continue }
            $noResuelto = $true
            break
        }

        $partida = [regex]::Match($idBasedOn, '^Attribute:(.+)$')
        if ($partida.Success) {
            $objetos = @($Xml.SelectNodes("//Object[@name='" + $partida.Groups[1].Value.Trim() + "']"))
            if ($objetos.Count -eq 1) { $nodoActual = $objetos[0]; continue }
            $noResuelto = $true
            break
        }

        if ($longitud -or $longitudMaxima) {
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
    Tipos permitidos: Integer, Decimal, String, Boolean, Date (YYYY-MM-DD), DateTime,
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
    if ($base -in @('Character', 'VarChar', 'LongVarChar')) {
        $dimensionConfirmada = ($longitud -and (-not $longitudMaxima -or $longitud -eq $longitudMaxima))
        if ($dimensionConfirmada) { return 'String (' + $longitud + ')' }
        return 'String'
    }
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
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Item
    )

    $descripcion = $Item.GetAttribute('description')
    if ($descripcion) { return ($descripcion -replace '^\*\s*', '') }
    $descripcion = Obtener-Propiedad -Nodo $Item -Nombre 'Description'
    if ($descripcion) { return $descripcion }

    $idBasedOn = Obtener-Propiedad -Nodo $Item -Nombre 'idBasedOn'
    if ($idBasedOn -match '^(Domain|Attribute):(.+)$') {
        $objetos = @($Xml.SelectNodes("//Object[@name='" + $Matches[2].Trim() + "']"))
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
    Resuelve un campo de entrada (item de SDT) con su tipo canonico y descripcion.
    .DESCRIPTION
    Devuelve un objeto con Campo, Tipo, Descripcion y los datos de estructura para
    la expansion posterior. Cuando el tipo no puede confirmarse, se registra el
    pendiente con la evidencia necesaria.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Item
    )

    $nombre = $Item.GetAttribute('name')
    if (-not $nombre) { $nombre = $Item.GetAttribute('Name') }

    $datosTipo = Obtener-DatosTipo -Xml $Xml -Nodo $Item
    $tipo = Convertir-TipoCanonico -DatosTipo $datosTipo -NombreCampo $nombre
    if (-not $tipo) {
        $tipo = 'PENDIENTE DE CONFIRMACIÓN: tipo del campo ' + $nombre + '. Evidencia requerida: respuesta real sanitizada o configuración desplegada.'
    }

    $descripcion = Obtener-DescripcionCampo -Xml $Xml -Item $Item
    if (-not $descripcion) {
        $descripcion = 'PENDIENTE DE CONFIRMACIÓN: descripcion del campo ' + $nombre + '. Evidencia requerida: respuesta real sanitizada o configuración desplegada.'
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
    Expande un SDT de entrada en filas y tablas independientes por ruta JSON.
    .DESCRIPTION
    Mantiene cada estructura en la tabla que la contiene y crea una tabla aparte por
    cada ruta JSON. Devuelve las filas de la tabla actual y las tablas de estructuras.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Sdt,
        [Parameter(Mandatory = $false)][string]$RutaJson = ''
    )

    $campos = Obtener-HijosSdt -Sdt $Sdt
    $filas = New-Object System.Collections.Generic.List[object]
    $tablas = New-Object System.Collections.Generic.List[object]

    foreach ($campo in $campos) {
        $resuelto = Resolver-Campo -Xml $Xml -Item $campo
        $resuelto | Add-Member -MemberType NoteProperty -Name 'RutaJson' -Value $(if ($RutaJson) { $RutaJson + '.' + $resuelto.Campo } else { $resuelto.Campo })
        $filas.Add($resuelto)
        if ($resuelto.EsEstructura) {
            $sdtHijo = Obtener-Sdt -Xml $Xml -NombreSdt $resuelto.NombreSdt -Modulo $resuelto.ModuloSdt
            if (-not $sdtHijo) { continue }
            $recursivo = Expandir-EstructuraSdt -Xml $Xml -Sdt $sdtHijo -RutaJson $resuelto.RutaJson
            $tablas.Add([pscustomobject]@{ Ruta = $resuelto.RutaJson; Filas = $recursivo.Filas })
            foreach ($tabla in $recursivo.Tablas) { $tablas.Add($tabla) }
        }
    }

    return [pscustomobject]@{ Filas = $filas.ToArray(); Tablas = $tablas.ToArray() }
}

function Resolver-EntradaGetTipos {
    <#
    .SYNOPSIS
    Resuelve tipos y descripciones de las posiciones GET desde el Source y las variables.
    .DESCRIPTION
    Usa las conversiones explicitas del parser (.ToNumeric, .ToString) y, en su defecto,
    la definicion de la variable. Conserva el orden y las posiciones exactas.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$ProgramaPrincipal,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $false)][object[]]$Posiciones = @()
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
            $datos = Obtener-DatosTipo -Xml $Xml -Nodo $variableNodo
            $tipo = Convertir-TipoCanonico -DatosTipo $datos -NombreCampo $variable
        }
        if (-not $tipo) {
            $tipo = 'PENDIENTE DE CONFIRMACIÓN: tipo del campo ' + $variable + '. Evidencia requerida: respuesta real sanitizada o configuración desplegada.'
        }

        $descripcion = ''
        if ($variableNodo) { $descripcion = Obtener-DescripcionCampo -Xml $Xml -Item $variableNodo }
        if (-not $descripcion) {
            $descripcion = 'PENDIENTE DE CONFIRMACIÓN: descripcion del campo ' + $variable + '. Evidencia requerida: respuesta real sanitizada o configuración desplegada.'
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

function Resolver-Obligatorio {
    <#
    .SYNOPSIS
    Calcula la columna Obligatorio segun analisisXPZ.md seccion 4.
    .DESCRIPTION
    El campo se marca SI cuando su nombre aparece referenciado en el Source del
    programa principal (where, asignacion, parametro o condicion) o en una
    comprobacion explicita de campo vacio o invalido; NO cuando no aparece.
    Se limita al programa principal, sin recorrer procedimientos en cascada,
    y se ignoran las lineas de comentario.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Campo
    )

    $lineas = [regex]::Split($Source, "`r?`n")
    $codigo = @($lineas | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
    if ($codigo -match ('\b' + [regex]::Escape($Campo) + '\b')) {
        return 'SI'
    }
    return 'NO'
}

function Agregar-Obligatorio {
    <#
    .SYNOPSIS
    Agrega la propiedad Obligatorio a una fila de la ficha.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][object]$Fila
    )

    $Fila | Add-Member -MemberType NoteProperty -Name 'Obligatorio' -Value (Resolver-Obligatorio -Source $Source -Campo $Fila.Campo) -Force
}

function Aplicar-Obligatorio {
    <#
    .SYNOPSIS
    Aplica la columna Obligatorio a las filas de entrada (y a las de estructuras).
    .DESCRIPTION
    Recibe las filas de la tabla principal y las tablas de estructuras expandidas,
    o una lista de filas (caso GET), y agrega la propiedad Obligatorio a cada una.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $false)][object[]]$Filas = @(),
        [Parameter(Mandatory = $false)][object[]]$Tablas = @()
    )

    foreach ($fila in $Filas) { Agregar-Obligatorio -Source $Source -Fila $fila }
    foreach ($tabla in $Tablas) {
        foreach ($fila in $tabla.Filas) { Agregar-Obligatorio -Source $Source -Fila $fila }
    }
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
    return 'PENDIENTE DE CONFIRMACIÓN: mensaje del error. Evidencia requerida: respuesta real sanitizada.'
}

function Resolver-Errores {
    <#
    .SYNOPSIS
    Extrae los errores HTTP explicitos del programa principal (analisisXPZ.md seccion 6).
    .DESCRIPTION
    La unica evidencia admitida es una llamada a GenerarAPIGLMResponse dentro del
    programa principal con codigo distinto de 200. Registra codigo, condicion que
    conduce a la llamada y mensaje literal o patron. Ignora comentarios y lineas
    de otras partes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source
    )

    $errores = New-Object System.Collections.Generic.List[object]
    $pila = New-Object System.Collections.Generic.List[object]
    $patronLlamada = [regex]::new('GenerarAPIGLMResponse\s*\(\s*(HttpCode\.\w+)\s*,\s*(.*?)\s*,\s*((?:!?''''|&[A-Za-z_][A-Za-z0-9_]*(?:\.ToJson\(\))?|format\s*\([^)]*\)))\s*\)')

    foreach ($linea in [regex]::Split($Source, "`r?`n")) {
        $linea = $linea.Trim()
        if ($linea -eq '' -or $linea.StartsWith('//')) { continue }

        if ($linea -match '^else\s+if\s+(.+)$') {
            if ($pila.Count -gt 0) {
                $pila[$pila.Count - 1].Condicion = ($Matches[1].Trim() -replace '\s*//.*$', '')
                $pila[$pila.Count - 1].Rama = 'then'
            }
            continue
        }
        if ($linea -match '^else') {
            if ($pila.Count -gt 0) { $pila[$pila.Count - 1].Rama = 'else' }
            continue
        }
        if ($linea -match '^endif') {
            if ($pila.Count -gt 0) { $pila.RemoveAt($pila.Count - 1) }
            continue
        }
        if ($linea -match '^do\s+case') {
            $pila.Add([pscustomobject]@{ Condicion = ''; Rama = 'then'; Tipo = 'case' })
            continue
        }
        if ($linea -match '^case\s+(.+)$') {
            if ($pila.Count -gt 0 -and $pila[$pila.Count - 1].Tipo -eq 'case') {
                $pila[$pila.Count - 1].Condicion = ($Matches[1].Trim() -replace '\s*//.*$', '')
                $pila[$pila.Count - 1].Rama = 'then'
            }
            continue
        }
        if ($linea -match '^otherwise') {
            if ($pila.Count -gt 0 -and $pila[$pila.Count - 1].Tipo -eq 'case') { $pila[$pila.Count - 1].Rama = 'else' }
            continue
        }
        if ($linea -match '^endcase') {
            if ($pila.Count -gt 0 -and $pila[$pila.Count - 1].Tipo -eq 'case') { $pila.RemoveAt($pila.Count - 1) }
            continue
        }
        if ($linea -match '^if\s+(.+)$') {
            $pila.Add([pscustomobject]@{ Condicion = ($Matches[1].Trim() -replace '\s*//.*$', ''); Rama = 'then'; Tipo = 'if' })
            continue
        }

        $coincidencia = $patronLlamada.Match($linea)
        if ($coincidencia.Success) {
            $codigo = Mapear-CodigoHttp -NombreCodigo $coincidencia.Groups[1].Value
            $condicion = ''
            if ($pila.Count -gt 0) {
                $superior = $pila[$pila.Count - 1]
                if ($superior.Rama -eq 'else') {
                    if ($superior.Condicion -match '^not\s+(.+)$') { $condicion = 'se cumple: ' + $Matches[1].Trim() }
                    else { $condicion = 'no se cumple: ' + $superior.Condicion }
                }
                else { $condicion = $superior.Condicion }
            }
            $mensaje = Normalizar-Mensaje -MensajeRaw $coincidencia.Groups[2].Value.Trim()
            if ($codigo -eq 200) { continue }
            $errores.Add([pscustomobject]@{ Codigo = $codigo; Condicion = $condicion; Mensaje = $mensaje })
        }
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
    tipos y descripciones canonicos.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$ProgramaPrincipal,
        [Parameter(Mandatory = $true)][string]$Source
    )

    $patron = [regex]::new('GenerarAPIGLMResponse\s*\(\s*HttpCode\.OK\s*,\s*(.*?)\s*,\s*&([A-Za-z_][A-Za-z0-9_]*)\.ToJson\(\)')
    $coincidencias = $patron.Matches($Source)
    if ($coincidencias.Count -eq 0) {
        return [pscustomobject]@{
            SalidaColeccion = $false
            Salida = @()
            NoResuelta = $true
        }
    }
    $variable = $coincidencias[$coincidencias.Count - 1].Groups[2].Value
    $variableNodo = Obtener-Variable -ProgramaPrincipal $ProgramaPrincipal -Nombre $variable
    if (-not $variableNodo) {
        return [pscustomobject]@{
            SalidaColeccion = $false
            Salida = @()
            NoResuelta = $true
        }
    }
    $datosTipo = Obtener-DatosTipo -Xml $Xml -Nodo $variableNodo
    if (-not $datosTipo.EsEstructura) {
        return [pscustomobject]@{
            SalidaColeccion = $datosTipo.EsColeccion
            Salida = @()
            NoResuelta = $true
        }
    }
    $sdt = Obtener-Sdt -Xml $Xml -NombreSdt $datosTipo.NombreSdt -Modulo $datosTipo.ModuloSdt
    if (-not $sdt) {
        return [pscustomobject]@{
            SalidaColeccion = $datosTipo.EsColeccion
            Salida = @()
            NoResuelta = $true
        }
    }

    $campos = Obtener-HijosSdt -Sdt $sdt
    $salida = New-Object System.Collections.Generic.List[object]
    foreach ($campo in $campos) {
        $resuelto = Resolver-Campo -Xml $Xml -Item $campo
        $salida.Add([pscustomobject]@{
            Campo = $resuelto.Campo
            Tipo = $resuelto.Tipo
            Descripcion = $resuelto.Descripcion
        })
    }

    return [pscustomobject]@{
        SalidaColeccion = $datosTipo.EsColeccion
        Salida = $salida.ToArray()
        NoResuelta = $false
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

function Analizar-Servicio {
    <#
    .SYNOPSIS
    Analiza un servicio desde el XPZ y arma la ficha tecnica unica.
    .DESCRIPTION
    Encadena la confirmacion del wrapper, la delegacion al programa principal,
    el metodo, la entrada (GET o POST), la expansion de estructuras, la
    obligatoriedad, la salida, los errores y el endpoint publicado. Devuelve la
    ficha que consumen la redaccion y la escritura de salidas.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $true)][string]$NombreCompletoWrapper,
        [Parameter(Mandatory = $true)][string]$PackageName
    )

    $wrapper = Obtener-Objeto -Xml $Xml -NombreCompleto $NombreCompletoWrapper
    if (-not $wrapper) {
        throw ('No se encontro el wrapper ' + $NombreCompletoWrapper + ' en el XPZ.')
    }
    Confirmar-Wrapper -Objeto $wrapper | Out-Null

    $nombreMain = Obtener-DelegacionUnica -Xml $Xml -Wrapper $wrapper
    $programaPrincipal = Obtener-Objeto -Xml $Xml -NombreCompleto $nombreMain
    if (-not $programaPrincipal) {
        throw ('No se encontro el programa principal ' + $nombreMain + ' en el XPZ.')
    }
    $source = Obtener-Source -ProgramaPrincipal $programaPrincipal
    $metodo = Resolver-Metodo -Source $source

    $entrada = @()
    $estructuras = @()
    if ($metodo -eq 'POST') {
        $entradaPost = Resolver-EntradaPost -Xml $Xml -ProgramaPrincipal $programaPrincipal -Source $source
        $expandido = Expandir-EstructuraSdt -Xml $Xml -Sdt $entradaPost.Sdt
        Aplicar-Obligatorio -Source $source -Filas @($expandido.Filas) -Tablas @($expandido.Tablas)
        $entrada = @($expandido.Filas | ForEach-Object {
            [pscustomobject]@{ Orden = 0; Campo = $_.Campo; Tipo = $_.Tipo; Obligatorio = $_.Obligatorio; Descripcion = $_.Descripcion }
        })
        $estructuras = @($expandido.Tablas | ForEach-Object {
            [pscustomobject]@{
                RutaJson = $_.Ruta
                Hijos = @($_.Filas | ForEach-Object {
                    [pscustomobject]@{ Campo = $_.Campo; Tipo = $_.Tipo; Obligatorio = $_.Obligatorio; Descripcion = $_.Descripcion }
                })
            }
        })
    } else {
        $posiciones = Resolver-EntradaGet -Source $source
        $posicionesTipos = Resolver-EntradaGetTipos -Xml $Xml -ProgramaPrincipal $programaPrincipal -Source $source -Posiciones @($posiciones)
        Aplicar-Obligatorio -Source $source -Filas @($posicionesTipos)
        $entrada = @($posicionesTipos | ForEach-Object {
            [pscustomobject]@{ Orden = $_.Posicion; Campo = $_.Campo; Tipo = $_.Tipo; Obligatorio = $_.Obligatorio; Descripcion = $_.Descripcion }
        })
    }

    $salida = Resolver-Salida -Xml $Xml -ProgramaPrincipal $programaPrincipal -Source $source
    if ($salida.NoResuelta) {
        $salida.Salida = @([pscustomobject]@{
            Campo = ''
            Tipo = 'PENDIENTE DE CONFIRMACIÓN: salida del servicio. Evidencia requerida: respuesta real sanitizada o configuración desplegada.'
            Descripcion = ''
        })
    }
    $errores = Resolver-Errores -Source $source
    $endpoint = Resolver-Endpoint -NombreCompletoWrapper $NombreCompletoWrapper -PackageName $PackageName

    $nombreFuncional = $wrapper.GetAttribute('description')
    $descripcion = $nombreFuncional
    if (-not $nombreFuncional) {
        $pendienteDescripcion = 'PENDIENTE DE CONFIRMACIÓN: descripción funcional del servicio. Evidencia requerida: configuración desplegada o respuesta real sanitizada.'
        $nombreFuncional = $pendienteDescripcion
        $descripcion = $pendienteDescripcion
    }

    $pendientes = New-Object System.Collections.Generic.List[string]
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
    foreach ($campo in $salida.Salida) {
        if ($campo.Tipo -match '^PENDIENTE') { $pendientes.Add($campo.Tipo) }
        if ($campo.Descripcion -match '^PENDIENTE') { $pendientes.Add($campo.Descripcion) }
    }

    return [pscustomobject]@{
        FqWrapper = $NombreCompletoWrapper
        ProgramaPrincipal = $nombreMain
        MetodoHttp = $metodo
        EndpointPublicado = $endpoint
        NombreFuncional = $nombreFuncional
        Descripcion = $descripcion
        Entrada = $entrada
        Estructuras = $estructuras
        SalidaColeccion = $salida.SalidaColeccion
        Salida = $salida.Salida
        Errores = $errores
        Pendientes = $pendientes.ToArray()
    }
}
