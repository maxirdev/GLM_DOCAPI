[CmdletBinding()]
param(
    [string]$XpzPath,
    [string]$CatalogPath,
    [string]$OutputDirectory,
    [string]$ConfigPath,
    [string]$ManifiestoPath,
    [string]$ClienteId,
    [ValidateSet('comercial', 'erp')][string]$Modulo,
    [string]$AmbienteId
)

$ErrorActionPreference = 'Stop'
if (-not $CatalogPath) { $CatalogPath = Join-Path $PSScriptRoot '..\GeneXus-XPZ-Skills-main\scripts\gx-object-type-catalog.json' }
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '..\configuracion.json' }
$StartTime = Get-Date
$RaizRepositorio = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$DirectorioLogs = Join-Path $RaizRepositorio 'Logs'
$faseActual = 'inicio'
. (Join-Path $PSScriptRoot 'GLMUtilidades.ps1')
. (Join-Path $PSScriptRoot 'DiagnosticoIA.ps1')
. (Join-Path $PSScriptRoot 'ManifiestoEjecucion.ps1')
$ProcedureTypeGuid = '84a12160-f59b-4ad7-a683-ea4481ac23e9'
$PackageName = ''
$ejecucionId = ''

Inicializar-ConsolaUtf8

function Write-Step {
    param(
        [Parameter(Mandatory = $true)][int]$Number,
        [string]$Text = ''
    )
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
}

function Write-ContextualEndpointGeneration {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)]$Configuration,
        [Parameter(Mandatory = $true)]$Index,
        [Parameter(Mandatory = $true)][string]$GenerationId
    )

    $endpointsRoot = Join-Path $Manifest.servicesDirectory 'Endpoints'
    $generationsRoot = Join-Path $endpointsRoot 'generations'
    $generationDirectory = Join-Path $generationsRoot $GenerationId
    Asegurar-Directorio -Ruta $generationDirectory

    $allEndpoints = @(Obtener-ServiciosHttpDesdeIndice -Indice $Index -ProcedureTypeGuid $ProcedureTypeGuid)
    $ignoredNames = @($Configuration.ServiciosIgnorados | ForEach-Object { [string]$_ })
    $ignoredEndpoints = @($allEndpoints | Where-Object { $ignoredNames -contains [string]$_.proceso })
    $publishedEndpoints = @($allEndpoints | Where-Object { $ignoredNames -notcontains [string]$_.proceso } | ForEach-Object {
        $publishedEndpoint = [string]$_.endpoint
        if ($Configuration.PackageName) { $publishedEndpoint = $Configuration.PackageName.TrimEnd('.') + '.' + $publishedEndpoint }
        [pscustomobject]@{
            nombre = [string]$_.nombre
            descripcion = [string]$_.descripcion
            proceso = [string]$_.proceso
            endpoint = $publishedEndpoint
        }
    })
    $xpzHash = Obtener-Sha256Archivo -Ruta ([string]$Manifest.xpz)
    $meta = [pscustomobject]@{
        generationId = $GenerationId
        contextId = [string]$Manifest.contextId
        clienteId = [string]$Manifest.clienteId
        modulo = [string]$Manifest.modulo
        ambienteId = [string]$Manifest.ambienteId
        xpz = [System.IO.Path]::GetFullPath([string]$Manifest.xpz)
        xpzSha256 = $xpzHash
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        totalConfirmed = $publishedEndpoints.Count
        totalProcessable = $publishedEndpoints.Count
        totalIgnored = $ignoredEndpoints.Count
    }
    $payload = [pscustomobject]@{
        schemaVersion = 1
        meta = $meta
        endpoints = @($publishedEndpoints)
    }
    $jsonContent = Normalizar-SaltosLineaLf -Texto ($payload | ConvertTo-Json -Depth 8)
    $markdownBuilder = New-Object System.Text.StringBuilder
    Add-Line $markdownBuilder '# Inventario de endpoints APIGLM'
    Add-Line $markdownBuilder
    Add-Line $markdownBuilder ('Contexto: **' + $meta.contextId + '** | XPZ: `' + [System.IO.Path]::GetFileName($meta.xpz) + '`')
    Add-Line $markdownBuilder ('Total confirmado: **' + $meta.totalConfirmed + '** | Ignorados: **' + $meta.totalIgnored + '**')
    Add-Line $markdownBuilder
    Add-Line $markdownBuilder '| Nombre | Descripción | Proceso | Endpoint |'
    Add-Line $markdownBuilder '|---|---|---|---|'
    foreach ($endpoint in $publishedEndpoints) {
        Add-Line $markdownBuilder ('| ' + $endpoint.nombre + ' | ' + $endpoint.descripcion + ' | `' + $endpoint.proceso + '` | `' + $endpoint.endpoint + '` |')
    }
    $markdownContent = $markdownBuilder.ToString()
    $jsonPath = Join-Path $generationDirectory 'endpoints.json'
    $markdownPath = Join-Path $generationDirectory 'endpoints.md'
    Escribir-TextoUtf8SinBom -Ruta $jsonPath -Contenido $jsonContent
    Escribir-TextoUtf8SinBom -Ruta $markdownPath -Contenido $markdownContent
    if (-not (Test-Path -LiteralPath $jsonPath -PathType Leaf) -or -not (Test-Path -LiteralPath $markdownPath -PathType Leaf)) {
        throw 'No se pudo publicar el par completo del inventario contextual.'
    }

    $pointer = [pscustomobject]@{ schemaVersion = 1; generationId = $GenerationId; updatedAt = $meta.generatedAt }
    Escribir-ArchivoAtomico -Ruta (Join-Path $endpointsRoot 'current.json') -Contenido (Normalizar-SaltosLineaLf -Texto ($pointer | ConvertTo-Json -Depth 4)) | Out-Null

    try {
        $generationDirectories = @(Get-ChildItem -LiteralPath $generationsRoot -Directory | Sort-Object LastWriteTime -Descending)
        foreach ($oldGeneration in @($generationDirectories | Select-Object -Skip 2)) {
            Remove-Item -LiteralPath $oldGeneration.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Warning ('No se pudieron limpiar generaciones antiguas: ' + $_.Exception.Message)
    }
}

try {
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  ANALISIS DE XPZ APIGLM' -ForegroundColor Cyan
    Write-Host ("  " + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan

    $faseActual = 'carga-modulos'
    . (Join-Path $PSScriptRoot 'CargarConfiguracion.ps1')
    . (Join-Path $PSScriptRoot 'AnalizarServicio.ps1')
    . (Join-Path $PSScriptRoot 'CargarMultiXPZ.ps1')

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
    $clienteId = $ClienteId
    $modulo = $Modulo
    $ambienteId = $AmbienteId
    if ($ManifiestoPath) {
        $manifiestoEjecucion = Leer-ManifiestoEjecucion -RutaManifiesto $ManifiestoPath
        $XpzPath = [string]$manifiestoEjecucion.xpz
        $ConfigPath = [string]$manifiestoEjecucion.configPath
        $clienteId = [string]$manifiestoEjecucion.clienteId
        $modulo = [string]$manifiestoEjecucion.modulo
        $ambienteId = [string]$manifiestoEjecucion.ambienteId
        $ejecucionId = [string]$manifiestoEjecucion.ejecucionId
        $OutputDirectory = Join-Path ([string]$manifiestoEjecucion.servicesDirectory) ('Endpoints\generations\' + $ejecucionId)
    } else {
        $ejecucionId = Obtener-NuevoIdentificadorEjecucion
        if (-not $OutputDirectory) {
            throw 'La invocacion directa requiere -OutputDirectory o -ManifiestoPath; el inventario ya no se publica como artefacto global (SPEC 19).'
        }
    }
    $cargarConfiguracionParametros = @{ ConfigPath = $ConfigPath }
    if ($XpzPath) { $cargarConfiguracionParametros.XpzPath = $XpzPath }
    if ($clienteId) {
        $cargarConfiguracionParametros.ClienteId = $clienteId
        $cargarConfiguracionParametros.Modulo = $modulo
        $cargarConfiguracionParametros.AmbienteId = $ambienteId
    }
    $configuracion = Cargar-Configuracion @cargarConfiguracionParametros
    if (-not $XpzPath) { $XpzPath = $configuracion.XpzPath }
    $PackageName = $configuracion.PackageName
    Write-Host ("  XPZ: " + $XpzPath) -ForegroundColor DarkGray
    Write-Host ("  PackageName: " + $PackageName) -ForegroundColor DarkGray
    if ($configuracion.Cliente) {
        Write-Host ("  Cliente: " + $configuracion.Cliente) -ForegroundColor DarkGray
    }
    if ($clienteId) {
        Write-Host ("  Contexto: " + $configuracion.ContextId) -ForegroundColor DarkGray
    }

    $faseActual = 'apertura-xpz'
    $indiceMultiXpz = Cargar-IndiceMultiXPZ -RutaXpzPrincipal $XpzPath
    $xml = $indiceMultiXpz.XmlUnificado
    $XpzName = ($indiceMultiXpz.NombresXpz -join ', ')
    Write-Host ("  Archivos: " + $XpzName) -ForegroundColor DarkGray

    if ($ManifiestoPath) {
        $faseActual = 'publicacion-generacion-contextual'
        Write-Step 2 'Publicando generación contextual de endpoints...'
        Write-ContextualEndpointGeneration -Manifest $manifiestoEjecucion -Configuration $configuracion -Index $indiceMultiXpz -GenerationId $ejecucionId
        Write-Host ('  Generación: ' + $ejecucionId) -ForegroundColor Green
        exit 0
    }

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
            contextId = if ($ManifiestoPath) { [string]$manifiestoEjecucion.contextId } else { '' }
            modulo = if ($clienteId) { [string]$configuracion.Modulo } else { '' }
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
