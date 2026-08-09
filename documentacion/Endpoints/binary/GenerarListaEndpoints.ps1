[CmdletBinding()]
param(
    [string]$XpzPath,
    [string]$XpzDirectory,
    [string]$CatalogPath,
    [string]$OutputDirectory,
    [string]$ConfigPath,
    [int]$ExpectedCount = 135
)

$ErrorActionPreference = 'Stop'
if (-not $XpzDirectory) { $XpzDirectory = Join-Path $PSScriptRoot '..\..\..\xpz' }
if (-not $CatalogPath) { $CatalogPath = Join-Path $PSScriptRoot '..\..\..\GeneXus-XPZ-Skills-main\scripts\gx-object-type-catalog.json' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot '..\assets' }
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '..\..\..\configuracion.json' }
$XpzName = ''
$StartTime = Get-Date
$ProcedureTypeGuid = '84a12160-f59b-4ad7-a683-ea4481ac23e9'
$PackageName = ''
$zip = $null

if (-not [Console]::IsOutputRedirected) {
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
}

function Write-Step {
    param(
        [Parameter(Mandatory = $true)][int]$Number,
        [string]$Text = ''
    )
    Write-Host ''
    Write-Host ("[ {0}/8 ] {1}" -f $Number, $Text) -ForegroundColor Cyan
}

function Add-Line {
    param(
        [Parameter(Mandatory = $true)][System.Text.StringBuilder]$Builder,
        [string]$Text = ''
    )
    [void]$Builder.Append($Text)
    [void]$Builder.Append("`n")
}

try {
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  EXTRACCION DE ENDPOINTS APIGLM' -ForegroundColor Cyan
    Write-Host ("  " + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan

    if (Test-Path -LiteralPath $CatalogPath) {
        try {
            $catalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json
            if ($catalog.types.Procedure.objectTypeGuid) {
                $ProcedureTypeGuid = $catalog.types.Procedure.objectTypeGuid
            }
        } catch {
            Write-Host 'No se pudo leer el catálogo de tipos; se usa el GUID constante de Procedure.' -ForegroundColor DarkGray
        }
    }
    Write-Host ("GUID de tipo Procedure: " + $ProcedureTypeGuid) -ForegroundColor DarkGray

    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $configuracion = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
            $PackageName = [string]$configuracion.packagename
        } catch {
            Write-Host 'No se pudo leer configuracion.json; el endpoint no incluira el packagename.' -ForegroundColor DarkGray
        }
    } else {
        Write-Host 'No se encontro configuracion.json en la raiz; el endpoint no incluira el packagename.' -ForegroundColor DarkGray
    }
    if ($PackageName) {
        Write-Host ("PackageName: " + $PackageName) -ForegroundColor DarkGray
    }

    Write-Step 1 'Buscando archivos .xpz...'
    if ($XpzPath) {
        if (-not (Test-Path -LiteralPath $XpzPath)) {
            throw ("No se encontró el XPZ indicado en: " + $XpzPath)
        }
        $XpzPath = (Resolve-Path -LiteralPath $XpzPath).Path
    } else {
        if (-not (Test-Path -LiteralPath $XpzDirectory)) {
            throw ("No existe el directorio de XPZ: " + $XpzDirectory)
        }
        $xpzFiles = @(Get-ChildItem -LiteralPath $XpzDirectory -Filter '*.xpz' -File)
        if ($xpzFiles.Count -eq 0) {
            throw ("No se encontró ningún archivo .xpz en: " + $XpzDirectory)
        }
        if ($xpzFiles.Count -gt 1) {
            Write-Host ("  Se encontraron " + $xpzFiles.Count + " archivos .xpz:") -ForegroundColor Yellow
            for ($i = 0; $i -lt $xpzFiles.Count; $i++) {
                Write-Host ("    {0}. {1}" -f ($i + 1), $xpzFiles[$i].Name) -ForegroundColor White
            }
            $selection = 0
            while ($selection -lt 1 -or $selection -gt $xpzFiles.Count) {
                $selText = Read-Host ("  Seleccione un archivo [1-" + $xpzFiles.Count + "]")
                $selection = 0
                [int]$parsed = 0
                if ([int]::TryParse($selText, [ref]$parsed)) { $selection = $parsed }
                if ($selection -lt 1 -or $selection -gt $xpzFiles.Count) {
                    Write-Host ("    Selección inválida. Ingrese un número entre 1 y " + $xpzFiles.Count + ".") -ForegroundColor Yellow
                }
            }
            $XpzPath = $xpzFiles[$selection - 1].FullName
            Write-Host ("  Seleccionado: " + $xpzFiles[$selection - 1].Name) -ForegroundColor DarkGray
        } else {
            $XpzPath = $xpzFiles[0].FullName
        }
    }
    $XpzName = [System.IO.Path]::GetFileName($XpzPath)
    Write-Host ("  Archivo: " + $XpzName) -ForegroundColor DarkGray
    Write-Host ("  Abriendo " + $XpzName + " en modo solo lectura...") -ForegroundColor DarkGray
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($XpzPath)
    } catch {
        throw ("No se pudo abrir el XPZ como contenedor ZIP. Motivo: " + $_.Exception.Message)
    }
$entry = $zip.Entries | Where-Object { $_.Name -like '*.xml' } | Select-Object -First 1
if (-not $entry) {
    throw ('El XPZ ' + $XpzName + ' no contiene ningún archivo XML.')
    }
    Write-Host ("  Entrada localizada: " + $entry.FullName + " (" + $entry.Length + " bytes)") -ForegroundColor DarkGray

    Write-Step 2 ("Leyendo " + $entry.Name + " desde " + $XpzName + "...")
    $reader = New-Object System.IO.StreamReader($entry.Open())
    try {
        $xmlText = $reader.ReadToEnd()
    } finally {
        $reader.Close()
    }
    Write-Host ("  Tamaño leído: " + $xmlText.Length + " caracteres") -ForegroundColor DarkGray

    Write-Step 3 'Cargando el XML y validando la raíz ExportFile...'
    $xml = New-Object System.Xml.XmlDocument
    $xml.PreserveWhitespace = $false
    try {
        $xml.LoadXml($xmlText)
    } catch {
        throw ("El XML interno no es un XML bien formado. Motivo: " + $_.Exception.Message)
    }
    if ($xml.DocumentElement.LocalName -ne 'ExportFile') {
        throw ("La raíz del XML no es ExportFile; se encontró: " + $xml.DocumentElement.LocalName)
    }
    Write-Host ("  Raíz: " + $xml.DocumentElement.Name) -ForegroundColor DarkGray

    Write-Step 4 ("Localizando APIGLM.APIGLMMain en " + $XpzName + " y su único Source no vacío...")
    $mainNodes = $xml.SelectNodes("//Object[@fullyQualifiedName='APIGLM.APIGLMMain']")
    if ($mainNodes.Count -ne 1) {
        throw ("APIGLM.APIGLMMain no se encontró o aparece " + $mainNodes.Count + " veces.")
    }
    $main = $mainNodes[0]
    $sourceNode = $null
    foreach ($part in $main.SelectNodes('Part')) {
        $src = $part.SelectSingleNode('Source')
        if ($src -and -not [string]::IsNullOrWhiteSpace($src.InnerText)) {
            if ($sourceNode) {
                throw 'APIGLMMain contiene más de un Part/Source no vacío.'
            }
            $sourceNode = $src
        }
    }
    if (-not $sourceNode) {
        throw 'No se encontró un Part/Source no vacío en APIGLM.APIGLMMain.'
    }
    $source = $sourceNode.InnerText
    Write-Host ("  Source localizado (" + $source.Length + " caracteres)") -ForegroundColor DarkGray

    Write-Step 5 'Extrayendo llamadas WS... activas del Source...'
    $lines = [regex]::Split($source, "`r?`n")
    $candidates = New-Object System.Collections.Generic.List[object]
    $ignored = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].Trim()
        if ($trimmed -eq '') { continue }
        if ($trimmed.StartsWith('//')) {
            $ignored++
            $preview = $trimmed
            if ($preview.Length -gt 60) { $preview = $preview.Substring(0, 60) + '...' }
            Write-Host ("  [ignorada] " + $preview) -ForegroundColor DarkGray
            continue
        }
        $m = [regex]::Match($trimmed, '(\b(?:\w+\.)*WS[A-Za-z0-9_]+)\s*\(')
        if ($m.Success) {
            $candidates.Add([pscustomobject]@{ Line = $i + 1; Call = $m.Groups[1].Value })
        }
    }
    Write-Host ("  Candidatos activos: " + $candidates.Count + " / líneas ignoradas por comentario: " + $ignored) -ForegroundColor DarkGray

    Write-Step 6 'Resolviendo candidatos y confirmando Procedure / IsMain=True / CALL_PROTOCOL=HTTP...'
    $allObjects = $xml.SelectNodes('//Object')
    $byFqn = @{}
    $byName = @{}
    foreach ($o in $allObjects) {
        $f = $o.GetAttribute('fullyQualifiedName')
        $n = $o.GetAttribute('name')
        if ($f) {
            if (-not $byFqn.ContainsKey($f)) { $byFqn[$f] = New-Object System.Collections.Generic.List[object] }
            $byFqn[$f].Add($o)
        }
        if ($n) {
            if (-not $byName.ContainsKey($n)) { $byName[$n] = New-Object System.Collections.Generic.List[object] }
            $byName[$n].Add($o)
        }
    }
    Write-Host ("  Objetos indexados: " + $allObjects.Count) -ForegroundColor DarkGray

    $resolved = New-Object System.Collections.Generic.List[object]
    $unresolved = New-Object System.Collections.Generic.List[object]
    foreach ($c in $candidates) {
        $call = $c.Call
        $matches = $null
        if ($call.Contains('.')) {
            if ($byFqn.ContainsKey($call)) { $matches = $byFqn[$call] }
        } else {
            if ($byName.ContainsKey($call)) { $matches = $byName[$call] }
        }
        if ($matches -and $matches.Count -gt 1) {
            $procedures = $matches | Where-Object { $_.GetAttribute('type') -eq $ProcedureTypeGuid }
            if ($procedures.Count -eq 1) { $matches = @($procedures) }
        }
        if (-not $matches -or $matches.Count -ne 1) {
            $count = 0
            if ($matches) { $count = $matches.Count }
            $unresolved.Add([pscustomobject]@{ Candidate = $call; Reason = ("Coincidencias: " + $count) })
            Write-Host ("  [ambiguo] " + $call + " (coincidencias: " + $count + ")") -ForegroundColor Yellow
            continue
        }
        $resolved.Add([pscustomobject]@{ Fqn = $matches[0].GetAttribute('fullyQualifiedName'); Name = $matches[0].GetAttribute('name'); Object = $matches[0] })
    }

    $final = New-Object System.Collections.Generic.List[object]
    $rejected = New-Object System.Collections.Generic.List[object]
    $seenFqn = @{}
    foreach ($item in $resolved) {
        $obj = $item.Object
        $typeOk = ($obj.GetAttribute('type') -eq $ProcedureTypeGuid)
        $isMainOk = ($obj.SelectSingleNode("Properties/Property[Name='IsMain' and Value='True']") -ne $null)
        $httpOk = ($obj.SelectSingleNode("Properties/Property[Name='CALL_PROTOCOL' and Value='HTTP']") -ne $null)
        if (-not ($typeOk -and $isMainOk -and $httpOk)) {
            $rejected.Add([pscustomobject]@{ Fqn = $item.Fqn; Type = $typeOk; IsMain = $isMainOk; CallProtocol = $httpOk })
            Write-Host ("  [no confirmado] " + $item.Fqn) -ForegroundColor Yellow
            continue
        }
        if ($seenFqn.ContainsKey($item.Fqn)) { continue }
        $seenFqn[$item.Fqn] = $true
        $lastDot = $item.Fqn.LastIndexOf('.')
        $module = ''
        if ($lastDot -gt 0) { $module = $item.Fqn.Substring(0, $lastDot) }
        $nombre = $item.Name
        if ($nombre.StartsWith('WS')) { $nombre = 'WS - ' + $nombre.Substring(2) }
        $descripcion = $item.Object.GetAttribute('description')
        if (-not $descripcion) { $descripcion = '' }
        $endpoint = 'a' + $item.Name.ToLowerInvariant()
        if ($module) { $endpoint = $module.ToLowerInvariant() + '.' + $endpoint }
        if ($PackageName) { $endpoint = $PackageName.TrimEnd('.') + '.' + $endpoint }
        $final.Add([pscustomobject]@{ Fqn = $item.Fqn; Name = $item.Name; Module = $module; Nombre = $nombre; Descripcion = $descripcion; Endpoint = $endpoint })
        Write-Host ("  [OK] " + $item.Fqn) -ForegroundColor Green
    }

    Write-Step 7 'Escribiendo endpoints.json y endpoints.md...'
    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }
    $endpointsArr = @($final | ForEach-Object { [pscustomobject]@{ nombre = $_.Nombre; descripcion = $_.Descripcion; proceso = $_.Fqn; endpoint = $_.Endpoint } })
    $unresolvedArr = @($unresolved | ForEach-Object { [pscustomobject]@{ candidate = $_.Candidate; reason = $_.Reason } })
    $payload = [pscustomobject]@{
        meta = [pscustomobject]@{
            generatedAt = $StartTime.ToString('s')
            source = $XpzName
            expectedCount = $ExpectedCount
            procedureTypeGuid = $ProcedureTypeGuid
            totalConfirmed = $final.Count
        }
        endpoints = $endpointsArr
        unresolved = $unresolvedArr
    }
    $json = $payload | ConvertTo-Json -Depth 5
    $json = $json -replace "`r`n", "`n"
    $jsonPath = Join-Path $OutputDirectory 'endpoints.json'
    [System.IO.File]::WriteAllText($jsonPath, $json, (New-Object System.Text.UTF8Encoding($false)))

    $bt = [char]96
    $sb = New-Object System.Text.StringBuilder
    Add-Line $sb '# Inventario de endpoints APIGLM'
    Add-Line $sb
    Add-Line $sb 'Inventario de endpoints activos y únicos confirmados desde `APIGLM.APIGLMMain` en el XPZ, generado por `GenerarListaEndpoints.ps1`.'
    Add-Line $sb
    Add-Line $sb ("Conteo confirmado: **" + $final.Count + "** (esperado: " + $ExpectedCount + ").")
    Add-Line $sb
    Add-Line $sb '## Endpoints'
    Add-Line $sb
    Add-Line $sb '| Nombre | Descripción | Proceso | Endpoint |'
    Add-Line $sb '|---|---|---|---|'
    foreach ($e in $final) {
        Add-Line $sb ("| " + $e.Nombre + " | " + $e.Descripcion + " | " + $bt + $e.Fqn + $bt + " | " + $bt + $e.Endpoint + $bt + " |")
    }
    if ($unresolved.Count -gt 0) {
        Add-Line $sb
        Add-Line $sb '## Candidatos no incorporados'
        Add-Line $sb
        foreach ($u in $unresolved) {
            Add-Line $sb ("- " + $bt + $u.Candidate + $bt + " — " + $u.Reason)
        }
    }
    Add-Line $sb
    $md = $sb.ToString()
    $mdPath = Join-Path $OutputDirectory 'endpoints.md'
    [System.IO.File]::WriteAllText($mdPath, $md, (New-Object System.Text.UTF8Encoding($false)))

    Write-Step 8 'Verificación final'
    Write-Host ''
    Write-Host ("Conteo confirmado: " + $final.Count) -ForegroundColor Cyan
    if ($final.Count -ne $ExpectedCount) {
        Write-Host ("  AVISO: difiere del esperado (" + $ExpectedCount + "). Determinar primero si cambió el XPZ o APIGLMMain; no forzar el número.") -ForegroundColor Yellow
    } else {
        Write-Host ("  Coincide con el esperado (" + $ExpectedCount + ").") -ForegroundColor Green
    }
    $dups = @($final | Group-Object Fqn | Where-Object { $_.Count -gt 1 })
    $zona = @($final | Where-Object { $_.Name -eq 'WSObtenerZonaTarifa' })
    $grabar = @($final | Where-Object { $_.Fqn -eq 'APIGLM.Tramite.WSGrabarTramites' })
    Write-Host ("Duplicados: " + $(if ($dups.Count -eq 0) { 'ninguno' } else { $dups.Count })) -ForegroundColor Green
    Write-Host ("WSObtenerZonaTarifa excluido: " + $(if ($zona.Count -eq 0) { 'SI' } else { 'NO' })) -ForegroundColor Green
    Write-Host ("WSGrabarTramites resuelto como APIGLM.Tramite.WSGrabarTramites: " + $(if ($grabar.Count -eq 1) { 'SI' } else { 'NO' })) -ForegroundColor Green
    if ($unresolved.Count -gt 0) {
        Write-Host ("Candidatos no incorporados: " + $unresolved.Count) -ForegroundColor Yellow
        foreach ($u in $unresolved) {
            Write-Host ("  - " + $u.Candidate + " (" + $u.Reason + ")") -ForegroundColor Yellow
        }
    }
    Write-Host ''
    Write-Host 'Archivos generados:' -ForegroundColor Cyan
    Write-Host ("  " + $jsonPath) -ForegroundColor White
    Write-Host ("  " + $mdPath) -ForegroundColor White
} catch {
    Write-Host ''
    Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if ($zip) { $zip.Dispose() }
    Write-Host ''
    Write-Host ("Fin: " + ((Get-Date) - $StartTime).ToString('mm\:ss')) -ForegroundColor DarkGray
}
