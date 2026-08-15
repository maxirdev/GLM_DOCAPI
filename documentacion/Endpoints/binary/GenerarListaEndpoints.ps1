[CmdletBinding()]
param(
    [string]$XpzPath,
    [string]$CatalogPath,
    [string]$OutputDirectory,
    [string]$ConfigPath,
    [string]$ManifiestoPath
)

$ErrorActionPreference = 'Stop'
if (-not $CatalogPath) { $CatalogPath = Join-Path $PSScriptRoot '..\..\..\GeneXus-XPZ-Skills-main\scripts\gx-object-type-catalog.json' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot '..\assets' }
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '..\..\..\configuracion.json' }
$StartTime = Get-Date
$RaizRepositorio = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$DirectorioLogs = Join-Path $PSScriptRoot '..\..\..\Logs'
$faseActual = 'inicio'
. (Join-Path $PSScriptRoot '..\..\..\binary\DiagnosticoIA.ps1')
. (Join-Path $PSScriptRoot '..\..\..\binary\ManifiestoEjecucion.ps1')
$ProcedureTypeGuid = '84a12160-f59b-4ad7-a683-ea4481ac23e9'
$PackageName = ''
$ejecucionId = ''

if (-not [Console]::IsOutputRedirected) {
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
}

function Write-Step {
    param(
        [Parameter(Mandatory = $true)][int]$Number,
        [string]$Text = ''
    )
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
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
    Write-Host '  ANALISIS DE XPZ APIGLM' -ForegroundColor Cyan
    Write-Host ("  " + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan

    $faseActual = 'carga-modulos'
    . (Join-Path $PSScriptRoot '..\..\..\binary\CargarConfiguracion.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\binary\AnalizarServicio.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\binary\CargarMultiXPZ.ps1')

    $faseActual = 'catalogo-tipos'
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

    $faseActual = 'configuracion'
    Write-Step 1 'Cargando configuracion y abriendo el XPZ...'
    if ($ManifiestoPath) {
        $manifiestoEjecucion = Leer-ManifiestoEjecucion -RutaManifiesto $ManifiestoPath
        $XpzPath = [string]$manifiestoEjecucion.xpz
        $ejecucionId = [string]$manifiestoEjecucion.ejecucionId
    } else {
        $ejecucionId = Obtener-NuevoIdentificadorEjecucion
    }
    $cargarConfiguracionParametros = @{ ConfigPath = $ConfigPath }
    if ($XpzPath) { $cargarConfiguracionParametros.XpzPath = $XpzPath }
    $configuracion = Cargar-Configuracion @cargarConfiguracionParametros
    $XpzPath = $configuracion.XpzPath
    $PackageName = $configuracion.PackageName
    Write-Host ("  XPZ: " + $configuracion.XpzPath) -ForegroundColor DarkGray
    Write-Host ("  PackageName: " + $PackageName) -ForegroundColor DarkGray
    if ($configuracion.Cliente) {
        Write-Host ("  Cliente: " + $configuracion.Cliente) -ForegroundColor DarkGray
    }

    $faseActual = 'apertura-xpz'
    $indiceMultiXpz = Cargar-IndiceMultiXPZ -RutaXpzPrincipal $XpzPath
    $xml = $indiceMultiXpz.XmlUnificado
    $XpzName = ($indiceMultiXpz.NombresXpz -join ', ')
    Write-Host ("  Archivos: " + $XpzName) -ForegroundColor DarkGray

    $faseActual = 'localizacion-main'
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
    Write-Host ("  APIGLMMain localizado, Source de " + $source.Length + " caracteres") -ForegroundColor DarkGray

    $faseActual = 'extraccion-llamadas'
    Write-Step 2 'Extrayendo y confirmando endpoints WS activos...'
    $lines = [regex]::Split($source, "`r?`n")
    $candidates = New-Object System.Collections.Generic.List[object]
    $ignored = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].Trim()
        if ($trimmed -eq '') { continue }
        if ($trimmed.StartsWith('//')) {
            $ignored++
            continue
        }
        $m = [regex]::Match($trimmed, '(\b(?:\w+\.)*WS[A-Za-z0-9_]+)\s*\(')
        if ($m.Success) {
            [void]$candidates.Add([pscustomobject]@{ Line = $i + 1; Call = $m.Groups[1].Value; Active = $true })
        }
    }

    $faseActual = 'resolucion-candidatos'
    $byFqn = $indiceMultiXpz.PorFqn
    $byName = $indiceMultiXpz.PorNombre

    $resolved = New-Object System.Collections.Generic.List[object]
    $unresolved = New-Object System.Collections.Generic.List[object]
    $noEncontrados = 0
    $ambiguos = 0
    foreach ($c in $candidates) {
        $call = $c.Call
        $matches = $null
        if ($call.Contains('.')) {
            if ($byFqn.ContainsKey($call)) { $matches = @($byFqn[$call]) }
        } else {
            if ($byName.ContainsKey($call)) { $matches = @($byName[$call] | ForEach-Object { $_ }) }
        }
        if ($matches -and $matches.Count -gt 1) {
            $procedures = $matches | Where-Object { $_.GetAttribute('type') -eq $ProcedureTypeGuid }
            if ($procedures.Count -eq 1) { $matches = @($procedures) }
        }
        if (-not $matches) {
            $noEncontrados++
            [void]$unresolved.Add([pscustomobject]@{ Candidate = $call; Reason = 'No encontrado'; Line = $c.Line; Active = $c.Active })
            continue
        }
        if ($matches.Count -ne 1) {
            $ambiguos++
            [void]$unresolved.Add([pscustomobject]@{ Candidate = $call; Reason = ("Coincidencias: " + $matches.Count); Line = $c.Line; Active = $c.Active })
            continue
        }
        [void]$resolved.Add([pscustomobject]@{ Fqn = $matches[0].GetAttribute('fullyQualifiedName'); Name = $matches[0].GetAttribute('name'); Object = $matches[0]; Line = $c.Line; Active = $c.Active })
    }

    $final = New-Object System.Collections.Generic.List[object]
    $rejected = New-Object System.Collections.Generic.List[object]
    $seenFqn = @{}
    $duplicados = 0
    foreach ($item in $resolved) {
        $obj = $item.Object
        $typeOk = ($obj.GetAttribute('type') -eq $ProcedureTypeGuid)
        $isMainOk = ($obj.SelectSingleNode("Properties/Property[Name='IsMain' and Value='True']") -ne $null)
        $httpOk = ($obj.SelectSingleNode("Properties/Property[Name='CALL_PROTOCOL' and Value='HTTP']") -ne $null)
        if (-not ($typeOk -and $isMainOk -and $httpOk)) {
            [void]$rejected.Add([pscustomobject]@{ Fqn = $item.Fqn; Type = $typeOk; IsMain = $isMainOk; CallProtocol = $httpOk; Line = $item.Line; Active = $item.Active })
            continue
        }
        if ($seenFqn.ContainsKey($item.Fqn)) { $duplicados++; continue }
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
        [void]$final.Add([pscustomobject]@{ Fqn = $item.Fqn; Name = $item.Name; Module = $module; Nombre = $nombre; Descripcion = $descripcion; Endpoint = $endpoint })
    }

    $okCount = $final.Count
    $warningCount = $ambiguos + $rejected.Count
    $errorCount = $noEncontrados
    Write-Host ("  Candidatos WS: " + $candidates.Count + " (ignorados por comentario: " + $ignored + ")") -ForegroundColor DarkGray
    Write-Host ("  OK: " + $okCount) -ForegroundColor Green
    if ($duplicados -gt 0) { Write-Host ("  Duplicados: " + $duplicados) -ForegroundColor DarkGray }
    if ($warningCount -gt 0) { Write-Host ("  Warning: " + $warningCount) -ForegroundColor Yellow }
    if ($errorCount -gt 0) { Write-Host ("  Error: " + $errorCount) -ForegroundColor Red }

    $faseActual = 'escritura-inventario'
    Write-Step 3 'Escribiendo endpoints.json y endpoints.md...'
    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }
    $endpointsArr = @($final | ForEach-Object { [pscustomobject]@{ nombre = $_.Nombre; descripcion = $_.Descripcion; proceso = $_.Fqn; endpoint = $_.Endpoint } })
    $unresolvedArr = @($unresolved | ForEach-Object { [pscustomobject]@{ candidate = $_.Candidate; reason = $_.Reason; line = $_.Line; active = [bool]$_.Active } })
    $payload = [pscustomobject]@{
        meta = [pscustomobject]@{
            generatedAt = $StartTime.ToString('s')
            ejecucionId = $ejecucionId
            manifiesto = $ManifiestoPath
            source = $XpzName
            xpzFiles = @($indiceMultiXpz.NombresXpz)
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
    Add-Line $sb ("Conteo confirmado: **" + $final.Count + "**.")
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

    $faseActual = 'verificacion-inventario'
    Write-Step 4 'Verificación final'
    Write-Host ''
    Write-Host ("Conteo confirmado: " + $final.Count) -ForegroundColor Cyan
    if ($unresolved.Count -gt 0) {
        Write-Host ("Candidatos no incorporados: " + $unresolved.Count) -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host 'Archivos generados:' -ForegroundColor Cyan
    Write-Host ("  " + $jsonPath) -ForegroundColor White
    Write-Host ("  " + $mdPath) -ForegroundColor White
} catch {
    $diagnosticoIA = New-DiagnosticoIAError -ErrorRecord $_ -Componente 'GenerarListaEndpoints' -Fase $faseActual -RaizRepositorio $RaizRepositorio
    Write-Host ''
    Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
    try {
        $rutaDiagnosticoIA = Write-DiagnosticoIA -Errores @($diagnosticoIA) -Pipeline 'inventario-endpoints' -Inicio $StartTime -DirectorioLogs $DirectorioLogs -RaizRepositorio $RaizRepositorio
        Write-Host ("Diagnostico IA: " + $rutaDiagnosticoIA) -ForegroundColor DarkGray
    } catch {
        Write-Host ("No se pudo escribir el diagnostico IA: " + $_.Exception.Message) -ForegroundColor DarkGray
    }
    exit 1
} finally {
}
