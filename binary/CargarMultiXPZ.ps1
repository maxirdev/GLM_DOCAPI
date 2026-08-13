# CargarMultiXPZ.ps1
# Carga el XPZ principal y sus complementos numerados como una fuente unificada.

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
        [Parameter(Mandatory = $true)][hashtable]$GuidsVistos
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
        [void]$contenedorDestino.AppendChild($Destino.ImportNode($nodoOrigen, $true))
    }
}

function Construir-XmlMultiXPZ {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaXpzPrincipal,
        [Parameter(Mandatory = $false)][string[]]$XpzComplementarios = @()
    )

    $rutas = @($RutaXpzPrincipal) + @($XpzComplementarios)
    $aperturaPrincipal = Abrir-XPZ -RutaXpz $RutaXpzPrincipal
    $xmlUnificado = New-Object System.Xml.XmlDocument
    $xmlUnificado.LoadXml($aperturaPrincipal.Xml.OuterXml)

    $fqnsVistos = @{}
    $guidsVistos = @{}
    foreach ($nodo in @($xmlUnificado.SelectNodes('//Object | //Attribute'))) {
        $fqn = [string]$nodo.GetAttribute('fullyQualifiedName')
        $guid = [string]$nodo.GetAttribute('guid')
        if ($fqn) { $fqnsVistos[$fqn] = $true }
        if ($guid) { $guidsVistos[$guid] = $true }
    }

    foreach ($rutaComplementaria in @($XpzComplementarios)) {
        $aperturaComplementaria = Abrir-XPZ -RutaXpz $rutaComplementaria
        foreach ($contenedor in @('Objects', 'Attributes', 'Dependencies', 'ObjectsIdentityMapping')) {
            Agregar-ContenedorXpzUnificado -Destino $xmlUnificado -Origen $aperturaComplementaria.Xml -NombreContenedor $contenedor -FqnsVistos $fqnsVistos -GuidsVistos $guidsVistos
        }
    }

    return [pscustomobject]@{
        XmlPrincipal = $aperturaPrincipal.Xml
        XmlUnificado = $xmlUnificado
        Rutas = $rutas
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

    $indice | Add-Member -MemberType NoteProperty -Name 'XmlPrincipal' -Value $xmls.XmlPrincipal -Force
    $indice | Add-Member -MemberType NoteProperty -Name 'XmlUnificado' -Value $xmls.XmlUnificado -Force
    $indice | Add-Member -MemberType NoteProperty -Name 'NombresXpz' -Value @($xmls.Rutas | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -Force
    $indice | Add-Member -MemberType NoteProperty -Name 'RutasXpz' -Value @($xmls.Rutas) -Force

    Write-Host ('  XPZ multiarchivo: ' + $indice.NombresXpz.Count + ' archivo(s), ' + $indice.PorFqn.Count + ' objetos FQN') -ForegroundColor DarkGray
    return $indice
}
