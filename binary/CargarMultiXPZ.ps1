# CargarMultiXPZ.ps1
# Carga el XPZ principal y sus complementos numerados como una fuente unificada.

function Obtener-RutaRelativaRepositorio {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Ruta
    )

    $directorioRepositorio = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $rutaCompleta = [System.IO.Path]::GetFullPath($Ruta)
    $uriRepositorio = New-Object System.Uri(($directorioRepositorio.TrimEnd('\') + '\'))
    $uriRuta = New-Object System.Uri($rutaCompleta)
    return [System.Uri]::UnescapeDataString($uriRepositorio.MakeRelativeUri($uriRuta).ToString()).Replace('\', '/')
}

function Obtener-HashSha256Archivo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Ruta
    )

    return (Get-FileHash -LiteralPath $Ruta -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Obtener-NombreArchivoServicio {
    <#
    .SYNOPSIS
    Resuelve el nombre base (sin extension) del archivo Markdown/PDF de un servicio.
    .DESCRIPTION
    Usa el ultimo segmento del FQN en minusculas. Si el inventario contiene otro
    servicio con el mismo ultimo segmento (homonimo), desambigua anexando la ruta
    de modulos en minusculas separada por guiones, para que dos servicios distintos
    nunca compartan archivo publicado ni ruta de staging.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FullyQualifiedName,
        [Parameter(Mandatory = $false)][string[]]$FqnsInventario = @()
    )

    $ultimoPunto = $FullyQualifiedName.LastIndexOf('.')
    if ($ultimoPunto -le 0) {
        throw ('El FQN no tiene un nombre local valido: ' + $FullyQualifiedName)
    }
    $nombreLocal = $FullyQualifiedName.Substring($ultimoPunto + 1).ToLowerInvariant()
    if ($FqnsInventario.Count -gt 0) {
        $homonimos = @($FqnsInventario | Where-Object {
            $punto = $_.LastIndexOf('.')
            $punto -gt 0 -and $_.Substring($punto + 1) -ieq $nombreLocal -and $_ -ine $FullyQualifiedName
        })
        if ($homonimos.Count -gt 0) {
            $rutaModulos = ($FullyQualifiedName.Substring(0, $ultimoPunto) -split '\.') -join '-'
            $nombreLocal = $nombreLocal + '-' + $rutaModulos.ToLowerInvariant()
        }
    }
    return $nombreLocal
}

function Construir-ManifiestoMultiXPZ {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$RutasXpz
    )

    $manifiesto = New-Object System.Collections.Generic.List[object]
    for ($indiceRuta = 0; $indiceRuta -lt $RutasXpz.Count; $indiceRuta++) {
        $rutaCompleta = (Resolve-Path -LiteralPath $RutasXpz[$indiceRuta]).Path
        $manifiesto.Add([pscustomobject]@{
            Orden = $indiceRuta
            Ruta = $rutaCompleta
            RutaRelativa = Obtener-RutaRelativaRepositorio -Ruta $rutaCompleta
            Nombre = [System.IO.Path]::GetFileName($rutaCompleta)
            Sha256 = Obtener-HashSha256Archivo -Ruta $rutaCompleta
        })
    }

    return $manifiesto.ToArray()
}

function Obtener-TipoObjetoEfectivo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Objeto
    )

    if ($Objeto.LocalName -eq 'Attribute') { return 'Attribute' }

    switch ($Objeto.GetAttribute('type')) {
        '84a12160-f59b-4ad7-a683-ea4481ac23e9' { return 'Procedure' }
        '447527b5-9210-4523-898b-5dccb17be60a' { return 'SDT' }
        '00972a17-9975-449e-aab1-d26165d51393' { return 'Domain' }
        default { return 'Object' }
    }
}

function Obtener-ChecksumNativoObjeto {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Objeto
    )

    foreach ($nombreAtributo in @('checksum', 'Checksum', 'sha256', 'SHA256')) {
        $valor = [string]$Objeto.GetAttribute($nombreAtributo)
        if ($valor) { return $valor }
    }

    $propiedad = $Objeto.SelectSingleNode("Properties/Property[Name='Checksum' or Name='checksum' or Name='SHA256' or Name='sha256']/Value")
    if ($propiedad -and $propiedad.InnerText) { return $propiedad.InnerText.Trim() }
    return $null
}

function Obtener-ChecksumSemanticoObjeto {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Objeto
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $contenido = [System.Text.Encoding]::UTF8.GetBytes($Objeto.OuterXml)
        $resultado = $sha256.ComputeHash($contenido)
        return ([System.BitConverter]::ToString($resultado) -replace '-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function Construir-IndiceObjetosEfectivos {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Xml,
        [Parameter(Mandatory = $false)][hashtable]$OrigenPorFqn = @{},
        [Parameter(Mandatory = $false)][hashtable]$OrigenPorGuid = @{}
    )

    $objetosEfectivos = @{}
    $serviciosPorObjeto = @{}
    foreach ($objeto in @($Xml.SelectNodes('//Object | //Attribute'))) {
        $tipo = Obtener-TipoObjetoEfectivo -Objeto $objeto
        $guid = [string]$objeto.GetAttribute('guid')
        $fqn = [string]$objeto.GetAttribute('fullyQualifiedName')
        $identificador = if ($guid) { $guid } else { $fqn }
        if (-not $identificador) { continue }

        $claveObjeto = $tipo + ':' + $identificador
        if ($objetosEfectivos.ContainsKey($claveObjeto)) { continue }

        $checksumNativo = Obtener-ChecksumNativoObjeto -Objeto $objeto
        $origen = $null
        if ($guid -and $OrigenPorGuid.ContainsKey($guid)) {
            $origen = $OrigenPorGuid[$guid]
        } elseif ($fqn -and $OrigenPorFqn.ContainsKey($fqn)) {
            $origen = $OrigenPorFqn[$fqn]
        }

        $objetosEfectivos[$claveObjeto] = [pscustomobject]@{
            Clave = $claveObjeto
            Tipo = $tipo
            Guid = $guid
            FullyQualifiedName = $fqn
            Nombre = [string]$objeto.GetAttribute('name')
            Origen = $origen
            Checksum = if ($checksumNativo) { $checksumNativo } else { Obtener-ChecksumSemanticoObjeto -Objeto $objeto }
            ChecksumNativo = $checksumNativo
            Objeto = $objeto
        }
        $serviciosPorObjeto[$claveObjeto] = New-Object System.Collections.Generic.List[string]
    }

    return [pscustomobject]@{
        ObjetosEfectivos = $objetosEfectivos
        ServiciosPorObjeto = $serviciosPorObjeto
    }
}

function Descubrir-XPZComplementariosCompartido {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaXpzPrincipal
    )

    $directorioXpz = [System.IO.Path]::GetDirectoryName($RutaXpzPrincipal)
    $nombreBase = [System.IO.Path]::GetFileNameWithoutExtension($RutaXpzPrincipal)
    $patron = '^' + [regex]::Escape($nombreBase) + '_(\d+)\.xpz$'
    $regex = [regex]::new($patron, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $complementos = New-Object System.Collections.Generic.List[object]

    foreach ($archivo in (Get-ChildItem -LiteralPath $directorioXpz -Filter '*.xpz' -File)) {
        $coincidencia = $regex.Match($archivo.Name)
        if (-not $coincidencia.Success) { continue }
        $complementos.Add([pscustomobject]@{
            Ruta = $archivo.FullName
            Nombre = $archivo.Name
            Numero = [int]$coincidencia.Groups[1].Value
        })
    }

    return @($complementos | Sort-Object Numero | ForEach-Object { $_.Ruta })
}

function Agregar-ContenedorXpzUnificado {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Destino,
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Origen,
        [Parameter(Mandatory = $true)][string]$NombreContenedor,
        [Parameter(Mandatory = $true)][hashtable]$FqnsVistos,
        [Parameter(Mandatory = $true)][hashtable]$GuidsVistos,
        [Parameter(Mandatory = $true)][string]$NombreXpz,
        [Parameter(Mandatory = $true)][hashtable]$OrigenPorFqn,
        [Parameter(Mandatory = $true)][hashtable]$OrigenPorGuid
    )

    $contenedorDestino = $Destino.DocumentElement.SelectSingleNode($NombreContenedor)
    $contenedorOrigen = $Origen.DocumentElement.SelectSingleNode($NombreContenedor)
    if (-not $contenedorOrigen) { return }

    if (-not $contenedorDestino) {
        $contenedorDestino = $Destino.ImportNode($contenedorOrigen, $false)
        [void]$Destino.DocumentElement.AppendChild($contenedorDestino)
    }

    foreach ($nodoOrigen in @($contenedorOrigen.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })) {
        $fqn = [string]$nodoOrigen.GetAttribute('fullyQualifiedName')
        $guid = [string]$nodoOrigen.GetAttribute('guid')
        if (($fqn -and $FqnsVistos.ContainsKey($fqn)) -or ($guid -and $GuidsVistos.ContainsKey($guid))) { continue }
        if ($fqn) { $FqnsVistos[$fqn] = $true }
        if ($guid) { $GuidsVistos[$guid] = $true }
        if ($fqn) { $OrigenPorFqn[$fqn] = $NombreXpz }
        if ($guid) { $OrigenPorGuid[$guid] = $NombreXpz }
        [void]$contenedorDestino.AppendChild($Destino.ImportNode($nodoOrigen, $true))
    }
}

function Construir-XmlMultiXPZ {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaXpzPrincipal,
        [Parameter(Mandatory = $false)][string[]]$XpzComplementarios = @()
    )

    $aperturaPrincipal = Abrir-XPZ -RutaXpz $RutaXpzPrincipal
    $rutas = @($aperturaPrincipal.Ruta)
    $xmlUnificado = New-Object System.Xml.XmlDocument
    $xmlUnificado.LoadXml($aperturaPrincipal.Xml.OuterXml)

    $fqnsVistos = @{}
    $guidsVistos = @{}
    $origenPorFqn = @{}
    $origenPorGuid = @{}
    foreach ($nodo in @($xmlUnificado.SelectNodes('//Object | //Attribute'))) {
        $fqn = [string]$nodo.GetAttribute('fullyQualifiedName')
        $guid = [string]$nodo.GetAttribute('guid')
        if ($fqn) { $fqnsVistos[$fqn] = $true }
        if ($guid) { $guidsVistos[$guid] = $true }
        if ($fqn) { $origenPorFqn[$fqn] = $aperturaPrincipal.Nombre }
        if ($guid) { $origenPorGuid[$guid] = $aperturaPrincipal.Nombre }
    }

    foreach ($rutaComplementaria in @($XpzComplementarios)) {
        $aperturaComplementaria = Abrir-XPZ -RutaXpz $rutaComplementaria
        $rutas += $aperturaComplementaria.Ruta
        foreach ($contenedor in @('Objects', 'Attributes', 'Dependencies', 'ObjectsIdentityMapping')) {
            Agregar-ContenedorXpzUnificado -Destino $xmlUnificado -Origen $aperturaComplementaria.Xml -NombreContenedor $contenedor -FqnsVistos $fqnsVistos -GuidsVistos $guidsVistos -NombreXpz $aperturaComplementaria.Nombre -OrigenPorFqn $origenPorFqn -OrigenPorGuid $origenPorGuid
        }
    }

    return [pscustomobject]@{
        XmlPrincipal = $aperturaPrincipal.Xml
        XmlUnificado = $xmlUnificado
        Rutas = $rutas
        OrigenPorFqn = $origenPorFqn
        OrigenPorGuid = $origenPorGuid
    }
}

function Cargar-IndiceMultiXPZ {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaXpzPrincipal
    )

    $complementos = @(Descubrir-XPZComplementariosCompartido -RutaXpzPrincipal $RutaXpzPrincipal)
    $xmls = Construir-XmlMultiXPZ -RutaXpzPrincipal $RutaXpzPrincipal -XpzComplementarios $complementos
    $indice = Construir-Indices -Xml $xmls.XmlUnificado
    $manifiesto = @(Construir-ManifiestoMultiXPZ -RutasXpz $xmls.Rutas)
    $indiceObjetos = Construir-IndiceObjetosEfectivos -Xml $xmls.XmlUnificado -OrigenPorFqn $xmls.OrigenPorFqn -OrigenPorGuid $xmls.OrigenPorGuid

    $indice | Add-Member -MemberType NoteProperty -Name 'XmlPrincipal' -Value $xmls.XmlPrincipal -Force
    $indice | Add-Member -MemberType NoteProperty -Name 'XmlUnificado' -Value $xmls.XmlUnificado -Force
    $indice | Add-Member -MemberType NoteProperty -Name 'NombresXpz' -Value @($xmls.Rutas | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -Force
    $indice | Add-Member -MemberType NoteProperty -Name 'RutasXpz' -Value @($xmls.Rutas) -Force
    $indice | Add-Member -MemberType NoteProperty -Name 'Manifiesto' -Value $manifiesto -Force
    $indice | Add-Member -MemberType NoteProperty -Name 'ObjetosEfectivos' -Value $indiceObjetos.ObjetosEfectivos -Force
    $indice | Add-Member -MemberType NoteProperty -Name 'ServiciosPorObjeto' -Value $indiceObjetos.ServiciosPorObjeto -Force
    $indice | Add-Member -MemberType NoteProperty -Name 'IndiceInverso' -Value $indiceObjetos.ServiciosPorObjeto -Force
    $indice | Add-Member -MemberType NoteProperty -Name 'OrigenPorFqn' -Value $xmls.OrigenPorFqn -Force
    $indice | Add-Member -MemberType NoteProperty -Name 'OrigenPorGuid' -Value $xmls.OrigenPorGuid -Force

    Write-Host ('  XPZ multiarchivo: ' + $indice.NombresXpz.Count + ' archivo(s), ' + $indice.PorFqn.Count + ' objetos FQN') -ForegroundColor DarkGray
    return $indice
}
