# GenerarOpenApi.ps1
# Punto de entrada independiente para construir el contrato tecnico agregado.
# La conversion OpenAPI y su publicacion se mantienen independientes del pipeline editorial.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)][string]$ConfigPath,
    [Parameter(Mandatory = $false)][string]$ClienteId,
    [Parameter(Mandatory = $false)][ValidateSet('comercial', 'erp')][string]$Modulo,
    [Parameter(Mandatory = $false)][string]$AmbienteId,
    [Parameter(Mandatory = $false)][string]$XpzPath,
    [Parameter(Mandatory = $false)][string]$ManifiestoPath,
    [Parameter(Mandatory = $false)][string]$RutaContratoAnalisis,
    [Parameter(Mandatory = $false)][string]$RutaOpenApi
)

$ErrorActionPreference = 'Stop'
$raizRepositorio = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

. (Join-Path $PSScriptRoot 'GLMUtilidades.ps1')
. (Join-Path $PSScriptRoot 'CargarConfiguracion.ps1')
. (Join-Path $PSScriptRoot 'AnalizarServicio.ps1')
. (Join-Path $PSScriptRoot 'CargarMultiXPZ.ps1')
. (Join-Path $PSScriptRoot 'ContratoAnalisis.ps1')
. (Join-Path $PSScriptRoot 'ControlVersiones.ps1')
. (Join-Path $PSScriptRoot 'ManifiestoEjecucion.ps1')

function Resolver-ContextoOpenApi {
    param(
        [Parameter(Mandatory = $true)][string]$RutaConfiguracion,
        [Parameter(Mandatory = $false)]$Manifiesto
    )

    if ($null -ne $Manifiesto) {
        $contexto = Cargar-Configuracion -ConfigPath $RutaConfiguracion -ClienteId ([string]$Manifiesto.clienteId) -Modulo ([string]$Manifiesto.modulo) -AmbienteId ([string]$Manifiesto.ambienteId)
        if ([string]$Manifiesto.contextId -ne [string]$contexto.ContextId) {
            throw 'El manifiesto de OpenAPI no pertenece al contexto configurado.'
        }
        if ([string]$Manifiesto.host -ne [string]$contexto.Host -or [string]$Manifiesto.baseUrl -ne [string]$contexto.BaseUrl -or [string]$Manifiesto.serverUrl -ne [string]$contexto.ServerUrl) {
            throw 'El manifiesto de OpenAPI combina host/baseUrl/serverUrl de otro ambiente.'
        }
        return $contexto
    }

    if ([string]::IsNullOrWhiteSpace($ClienteId) -or [string]::IsNullOrWhiteSpace($Modulo) -or [string]::IsNullOrWhiteSpace($AmbienteId)) {
        throw 'La generacion OpenAPI independiente requiere -ClienteId, -Modulo y -AmbienteId.'
    }
    return Cargar-Configuracion -ConfigPath $RutaConfiguracion -ClienteId $ClienteId -Modulo $Modulo -AmbienteId $AmbienteId
}

function Obtener-RutaConfiguracionOpenApi {
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        return [System.IO.Path]::GetFullPath($ConfigPath)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $raizRepositorio 'configuracion.json'))
}

function Construir-EnvelopeAnalisisOpenApi {
    param(
        [Parameter(Mandatory = $true)]$Contexto,
        [Parameter(Mandatory = $true)][string]$Xpz,
        [Parameter(Mandatory = $true)]$Indice,
        [Parameter(Mandatory = $true)]$Inventario,
        [Parameter(Mandatory = $true)]$Control
    )

    $serviciosControl = Convertir-DiccionarioControlVersiones -Objeto $Control.services
    $nombresInventario = @($Inventario | ForEach-Object { [string]$_.proceso })
    $activos = @($serviciosControl.Keys | Where-Object {
        $fullyQualifiedName = [string]$_
        $nombreArchivo = Obtener-NombreArchivoServicio -FullyQualifiedName $fullyQualifiedName -FqnsInventario $nombresInventario
        $rutaMarkdown = Join-Path $Contexto.DirectorioServicios ($nombreArchivo + '.md')
        $rutaPdf = Join-Path $Contexto.DirectorioServicios ($nombreArchivo + '.pdf')
        [string](Obtener-PropiedadControlVersiones -Objeto $serviciosControl[$_] -Nombre 'status') -eq 'ACTIVO' -and
            ((Test-Path -LiteralPath $rutaMarkdown -PathType Leaf) -or (Test-Path -LiteralPath $rutaPdf -PathType Leaf))
    } | Sort-Object)
    $registros = New-Object System.Collections.Generic.List[object]

    foreach ($fullyQualifiedName in $activos) {
        $endpoint = @($Inventario | Where-Object { [string]$_.proceso -eq [string]$fullyQualifiedName }) | Select-Object -First 1
        if ($null -eq $endpoint) {
            throw ('El servicio ACTIVO ' + $fullyQualifiedName + ' no aparece en el inventario HTTP del XPZ.')
        }
        try {
            $analisis = Analizar-Servicio -Xml $Indice.XmlUnificado -NombreCompletoWrapper $fullyQualifiedName -PackageName $Contexto.PackageName -Indice $Indice -IncluirTrazaEvidencia
        } catch {
            throw ('No se pudo analizar el servicio ' + $fullyQualifiedName + '. Motivo: ' + $_.Exception.Message)
        }
        $servicioControl = $serviciosControl[$fullyQualifiedName]
        $dependencias = @(Obtener-PropiedadControlVersiones -Objeto $servicioControl -Nombre 'dependencies')
        $registro = New-RegistroContratoAnalisis -FullyQualifiedName $fullyQualifiedName -Documentacion $analisis -WrapperGuid ([string](Obtener-PropiedadControlVersiones -Objeto $servicioControl -Nombre 'wrapperGuid')) -DocumentHash ([string](Obtener-PropiedadControlVersiones -Objeto $servicioControl -Nombre 'documentHash')) -Dependencias $dependencias -EstadoAnalisis 'OK'
        [void]$registros.Add($registro)
    }

    $sourceFingerprint = Obtener-Sha256Archivo -Ruta $Xpz
    $profileFingerprint = Obtener-Sha256TextoNormalizado -Texto 'openapi-technical-analysis-v1'
    $ejecucionId = 'openapi-manual-' + (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
    if ($ManifiestoPath) {
        $ejecucionId = [string]$script:OpenApiManifest.ejecucionId
    }
    $envelope = New-EnvelopeContratoAnalisis -EjecucionId $ejecucionId -ContextId $Contexto.ContextId -Xpz $Xpz -SourceFingerprint $sourceFingerprint -ProfileFingerprint $profileFingerprint -FullyQualifiedNames $activos -Servicios $registros.ToArray()
    Validar-EnvelopeContratoAnalisis -Envelope $envelope -EjecucionId $ejecucionId -ContextId $Contexto.ContextId -Xpz $Xpz -SourceFingerprint $sourceFingerprint -ProfileFingerprint $profileFingerprint -FullyQualifiedNames $activos | Out-Null
    return $envelope
}

function Obtener-EjemploTipoOpenApi {
    param([Parameter(Mandatory = $true)][string]$Tipo)
    if ($Tipo -match '^Integer') { return 0 }
    if ($Tipo -match '^Decimal') { return 0 }
    if ($Tipo -eq 'Boolean') { return $false }
    if ($Tipo -eq 'Date (YYYY-MM-DD)') { return '2000-01-01' }
    if ($Tipo -eq 'DateTime') { return '2000-01-01T00:00:00Z' }
    if ($Tipo -eq 'Base64') { return '' }
    return ''
}

function Convertir-TipoCanonicoAEsquemaOpenApi {
    param([Parameter(Mandatory = $true)][string]$Tipo)
    $esquema = [ordered]@{}
    switch -Regex ($Tipo) {
        '^Integer' { $esquema.type = 'integer'; $esquema.format = 'int64' }
        '^Decimal' { $esquema.type = 'number'; $esquema.format = 'double' }
        '^String' { $esquema.type = 'string' }
        '^LongVarchar$' { $esquema.type = 'string' }
        '^Boolean$' { $esquema.type = 'boolean' }
        '^Date \(YYYY-MM-DD\)$' { $esquema.type = 'string'; $esquema.format = 'date' }
        '^DateTime$' { $esquema.type = 'string'; $esquema.format = 'date-time' }
        '^Base64$' { $esquema.type = 'string'; $esquema.format = 'byte' }
        default { throw ('Tipo canonico no soportado por OpenAPI: ' + $Tipo) }
    }
    if ($Tipo -match '^String \((\d+)\)$') { $esquema.maxLength = [int]$Matches[1] }
    if ($Tipo -match '^Integer \((\d+)\)$') { $esquema.'x-glm-length' = [int]$Matches[1] }
    if ($Tipo -match '^Decimal \((\d+),\s*(\d+)\)$') {
        $esquema.'x-glm-length' = [int]$Matches[1]
        $esquema.'x-glm-decimals' = [int]$Matches[2]
    }
    $esquema.example = Obtener-EjemploTipoOpenApi -Tipo $Tipo
    return [pscustomobject]$esquema
}

function Convertir-CampoAPropiedadOpenApi {
    param(
        [Parameter(Mandatory = $true)]$Campo,
        [Parameter(Mandatory = $false)]$Estructuras = @(),
        [Parameter(Mandatory = $false)][hashtable]$NombresEsquema = @{}
    )
    $tipo = [string]$Campo.Tipo
    $esquema = $null
    if ($tipo -match '^Estructura\s+') {
        $nombre = [string]$Campo.SdtFqn
        if (-not $nombre) { $nombre = [string]$Campo.RutaSdt }
        if ($NombresEsquema.ContainsKey($nombre)) { $esquema = [ordered]@{ '$ref' = '#/components/schemas/' + $NombresEsquema[$nombre] } }
        else { $esquema = [ordered]@{ type = 'object'; example = [ordered]@{} } }
    } elseif ($tipo -match '^Colec.* de Estructura\s+') {
        $nombre = [string]$Campo.SdtFqn
        if (-not $nombre) { $nombre = [string]$Campo.RutaSdt }
        $items = if ($NombresEsquema.ContainsKey($nombre)) { [ordered]@{ '$ref' = '#/components/schemas/' + $NombresEsquema[$nombre] } } else { [ordered]@{ type = 'object' } }
        $esquema = [ordered]@{ type = 'array'; items = $items; example = @() }
    } elseif ($tipo -match '^Colec.* JSON$') {
        $esquema = [ordered]@{ type = 'array'; items = [ordered]@{}; example = @() }
    } else {
        $esquema = Convertir-TipoCanonicoAEsquemaOpenApi -Tipo $tipo
    }
    return [pscustomobject]@{
        Nombre = [string]$Campo.Campo
        RutaJson = [string]$Campo.RutaJson
        Esquema = $esquema
        Requerido = ([string]$Campo.Obligatorio -eq 'SI')
        Descripcion = [string]$Campo.Descripcion
    }
}

function Convertir-EstructuraAEsquemaOpenApi {
    param(
        [Parameter(Mandatory = $true)]$Estructura,
        [Parameter(Mandatory = $false)][hashtable]$NombresEsquema = @{}
    )
    $propiedades = [ordered]@{}
    $requeridos = New-Object System.Collections.Generic.List[string]
    foreach ($hijo in @($Estructura.Hijos)) {
        $propiedad = Convertir-CampoAPropiedadOpenApi -Campo $hijo -Estructuras @() -NombresEsquema $NombresEsquema
        $propiedades[$propiedad.Nombre] = $propiedad.Esquema
        if ($propiedad.Requerido) { [void]$requeridos.Add($propiedad.Nombre) }
    }
    $resultado = [ordered]@{ type = 'object'; properties = $propiedades }
    if ($requeridos.Count -gt 0) { $resultado.required = @($requeridos.ToArray()) }
    return [pscustomobject]$resultado
}

function Convertir-SalidaAEsquemaOpenApi {
    param(
        [Parameter(Mandatory = $true)]$Documentacion,
        [Parameter(Mandatory = $false)][hashtable]$NombresEsquema = @{}
    )
    if ($Documentacion.SalidaVacia) { return $null }
    if ([string]$Documentacion.TipoContenidoSalida -eq 'application/octet-stream') {
        return [pscustomobject]@{ type = 'string'; format = 'binary' }
    }
    if (@($Documentacion.MensajesSalida).Count -gt 0) {
        return [pscustomobject]@{ type = 'string'; example = ([string](@($Documentacion.MensajesSalida) -join ' ')) }
    }
    if ($Documentacion.SalidaColeccion -and $Documentacion.TipoColeccionPrimitiva) {
        return [pscustomobject]@{
            type = 'array'
            items = Convertir-TipoCanonicoAEsquemaOpenApi -Tipo ([string]$Documentacion.TipoColeccionPrimitiva)
            example = @()
        }
    }
    $propiedades = [ordered]@{}
    $requeridos = New-Object System.Collections.Generic.List[string]
    foreach ($campo in @($Documentacion.Salida)) {
        $propiedad = Convertir-CampoAPropiedadOpenApi -Campo $campo -NombresEsquema $NombresEsquema
        $propiedades[$propiedad.Nombre] = $propiedad.Esquema
    }
    foreach ($estructura in @($Documentacion.EstructurasSalida)) {
        $clave = [string]$estructura.RutaJson
        $nombre = if ($NombresEsquema.ContainsKey([string]$estructura.SdtFqn)) { $NombresEsquema[[string]$estructura.SdtFqn] } elseif ($NombresEsquema.ContainsKey($clave)) { $NombresEsquema[$clave] } else { '' }
        $estructuraEsquema = Convertir-EstructuraAEsquemaOpenApi -Estructura $estructura -NombresEsquema $NombresEsquema
        $propiedades[$clave.Split('.')[-1]] = if ($nombre) { [ordered]@{ '$ref' = '#/components/schemas/' + $nombre } } else { $estructuraEsquema }
    }
    $resultado = [ordered]@{ type = 'object'; properties = $propiedades; example = [ordered]@{} }
    if ($requeridos.Count -gt 0) { $resultado.required = @($requeridos.ToArray()) }
    return [pscustomobject]$resultado
}

function Convertir-ErroresARespuestasOpenApi {
    param([Parameter(Mandatory = $true)]$Errores)
    $respuestas = [ordered]@{}
    foreach ($errorConfirmado in @($Errores)) {
        $codigo = [string]$errorConfirmado.Codigo
        if ($codigo -notmatch '^\d+$' -or [int]$codigo -eq 200) { throw 'El análisis contiene un código HTTP de error inválido.' }
        $respuestas[$codigo] = [ordered]@{ description = if ([string]$errorConfirmado.Mensaje) { [string]$errorConfirmado.Mensaje } else { 'Error HTTP confirmado.' } }
    }
    return $respuestas
}

function Convertir-RegistroAOperacionOpenApi {
    param(
        [Parameter(Mandatory = $true)]$Registro,
        [Parameter(Mandatory = $false)][hashtable]$NombresEsquema = @{}
    )
    $documentacion = $Registro.documentacion
    $metodo = ([string]$documentacion.MetodoHttp).ToLowerInvariant()
    $operacion = [ordered]@{
        operationId = [string]$Registro.fullyQualifiedName
        summary = [string]$documentacion.EndpointPublicado
        method = $metodo
        endpoint = [string]$documentacion.EndpointPublicado
        parameters = @()
        requestBody = $null
        responses = [ordered]@{}
        tags = @()
    }
    $partesFqn = ([string]$Registro.fullyQualifiedName).Split('.')
    if ($partesFqn.Count -gt 1) { $operacion.tags += $partesFqn[$partesFqn.Count - 2] }
    if ($metodo) { $operacion.tags += $metodo.ToUpperInvariant() }
    if ($metodo -eq 'get') {
        $parametros = New-Object System.Collections.Generic.List[object]
        foreach ($campo in @($documentacion.Entrada | Sort-Object Orden)) {
            $propiedad = Convertir-CampoAPropiedadOpenApi -Campo $campo -NombresEsquema $NombresEsquema
            $parametro = [ordered]@{ name = $propiedad.Nombre; in = 'query'; required = $propiedad.Requerido; schema = $propiedad.Esquema; 'x-glm-position' = [int]$campo.Orden }
            if ($propiedad.Descripcion) { $parametro.description = $propiedad.Descripcion }
            [void]$parametros.Add([pscustomobject]$parametro)
        }
        $operacion.parameters = @($parametros.ToArray())
    } elseif ($metodo -eq 'post') {
        $propiedades = [ordered]@{}
        $requeridos = New-Object System.Collections.Generic.List[string]
        foreach ($campo in @($documentacion.Entrada)) {
            $propiedad = Convertir-CampoAPropiedadOpenApi -Campo $campo -NombresEsquema $NombresEsquema
            $propiedades[$propiedad.Nombre] = $propiedad.Esquema
            if ($propiedad.Requerido) { [void]$requeridos.Add($propiedad.Nombre) }
        }
        $cuerpo = [ordered]@{ type = 'object'; properties = $propiedades; example = [ordered]@{} }
        if ($requeridos.Count -gt 0) { $cuerpo.required = @($requeridos.ToArray()) }
        $operacion.requestBody = [ordered]@{ required = $true; content = [ordered]@{ 'application/json' = [ordered]@{ schema = $cuerpo; example = [ordered]@{} } } }
    } else {
        throw ('Metodo HTTP no soportado por el mapeo OpenAPI: ' + [string]$documentacion.MetodoHttp)
    }
    $esquemaSalida = Convertir-SalidaAEsquemaOpenApi -Documentacion $documentacion -NombresEsquema $NombresEsquema
    $respuestaExitosa = [ordered]@{ description = 'Respuesta exitosa.' }
    if ($null -ne $esquemaSalida) {
        $tipoContenido = if ($documentacion.TipoContenidoSalida) { [string]$documentacion.TipoContenidoSalida } else { 'application/json' }
        $respuestaExitosa.content = [ordered]@{ $tipoContenido = [ordered]@{ schema = $esquemaSalida } }
    }
    $operacion.responses['200'] = $respuestaExitosa
    foreach ($codigoError in (Convertir-ErroresARespuestasOpenApi -Errores $documentacion.Errores).GetEnumerator()) { $operacion.responses[$codigoError.Key] = $codigoError.Value }
    return [pscustomobject]$operacion
}

function Convertir-EnvelopeAOperacionesOpenApi {
    param([Parameter(Mandatory = $true)]$Envelope)
    $nombresEsquema = @{}
    foreach ($registro in @($Envelope.contratoAnalisis.servicios)) {
        foreach ($estructura in @($registro.documentacion.Estructuras) + @($registro.documentacion.EstructurasSalida)) {
            $clave = [string]$estructura.SdtFqn
            if (-not $clave) { $clave = [string]$estructura.RutaJson }
            if (-not $nombresEsquema.ContainsKey($clave)) { $nombresEsquema[$clave] = ('Sdt' + $nombresEsquema.Count) }
        }
    }
    $operaciones = New-Object System.Collections.Generic.List[object]
    $esquemas = [ordered]@{}
    foreach ($registro in @($Envelope.contratoAnalisis.servicios)) {
        foreach ($estructura in @($registro.documentacion.Estructuras) + @($registro.documentacion.EstructurasSalida)) {
            $clave = [string]$estructura.SdtFqn
            if (-not $clave) { $clave = [string]$estructura.RutaJson }
            $nombreEsquema = $nombresEsquema[$clave]
            if ($nombreEsquema -and -not $esquemas.Contains($nombreEsquema)) {
                $esquemas[$nombreEsquema] = Convertir-EstructuraAEsquemaOpenApi -Estructura $estructura -NombresEsquema $nombresEsquema
            }
        }
        [void]$operaciones.Add((Convertir-RegistroAOperacionOpenApi -Registro $registro -NombresEsquema $nombresEsquema))
    }
    return [pscustomobject]@{ Operaciones = @($operaciones.ToArray()); NombresEsquema = $nombresEsquema; Esquemas = $esquemas }
}

function Obtener-NombreRutaOpenApi {
    param([Parameter(Mandatory = $true)][string]$Endpoint)
    $valor = $Endpoint.Trim()
    if ([string]::IsNullOrWhiteSpace($valor) -or $valor -match '[?#]' -or $valor -match '[\\:]') { throw 'El endpoint publicado no puede convertirse en una ruta OpenAPI segura.' }
    return '/' + $valor.TrimStart('/').ToLowerInvariant()
}

function Convertir-ObjetoSemanticoAJson {
    param([Parameter(Mandatory = $true)]$Objeto)
    return (Normalizar-SaltosLineaLf -Texto ($Objeto | ConvertTo-Json -Depth 100 -Compress))
}

function Obtener-HashSemanticoOpenApi {
    param([Parameter(Mandatory = $true)]$Documento)
    $copia = $Documento | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $copia.info.version = ''
    return (Obtener-Sha256TextoNormalizado -Texto (Convertir-ObjetoSemanticoAJson -Objeto $copia)).Substring(0, 12)
}

function Comparar-DocumentosOpenApiSemanticos {
    param(
        [Parameter(Mandatory = $true)]$DocumentoNuevo,
        [Parameter(Mandatory = $true)][string]$JsonAnterior
    )
    try { $documentoAnterior = $JsonAnterior | ConvertFrom-Json } catch { throw ('El contrato OpenAPI anterior no contiene JSON valido: ' + $_.Exception.Message) }
    if ([string]$documentoAnterior.openapi -cne '3.0.3') { return $false }
    return (Obtener-HashSemanticoOpenApi -Documento $documentoAnterior) -eq (Obtener-HashSemanticoOpenApi -Documento $DocumentoNuevo)
}

function Obtener-ReferenciasOpenApi {
    param([Parameter(Mandatory = $true)]$Objeto)
    $referencias = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Objeto) { return @() }
    if ($Objeto -is [System.Collections.IDictionary]) {
        foreach ($clave in $Objeto.Keys) {
            if ([string]$clave -eq '$ref') { [void]$referencias.Add([string]$Objeto[$clave]) }
            else { foreach ($referenciaHija in @(Obtener-ReferenciasOpenApi -Objeto $Objeto[$clave])) { [void]$referencias.Add([string]$referenciaHija) } }
        }
    } elseif ($Objeto -is [System.Collections.IEnumerable] -and $Objeto -isnot [string]) {
        foreach ($elemento in $Objeto) { foreach ($referenciaHija in @(Obtener-ReferenciasOpenApi -Objeto $elemento)) { [void]$referencias.Add([string]$referenciaHija) } }
    } else {
        foreach ($propiedad in @($Objeto.PSObject.Properties)) {
            if ($propiedad.Name -eq '$ref') { [void]$referencias.Add([string]$propiedad.Value) }
            else { foreach ($referenciaHija in @(Obtener-ReferenciasOpenApi -Objeto $propiedad.Value)) { [void]$referencias.Add([string]$referenciaHija) } }
        }
    }
    return @($referencias.ToArray())
}

function Validar-DocumentoOpenApi {
    param([Parameter(Mandatory = $true)]$Documento)
    if ([string]$Documento.openapi -cne '3.0.3') { throw 'El documento OpenAPI debe declarar openapi 3.0.3.' }
    if (@($Documento.servers).Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$Documento.servers[0].url)) { throw 'El documento OpenAPI debe contener un unico servidor valido.' }
    $operacionIds = @{}
    foreach ($ruta in @($Documento.paths.PSObject.Properties)) {
        foreach ($operacion in @($ruta.Value.PSObject.Properties | Where-Object { $_.Name -in @('get', 'post', 'put', 'delete', 'patch', 'head', 'options', 'trace') })) {
            $operationId = [string]$operacion.Value.operationId
            if ([string]::IsNullOrWhiteSpace($operationId)) { throw ('La ruta OpenAPI ' + $ruta.Name + ' no contiene operationId.') }
            if ($operacionIds.ContainsKey($operationId)) { throw ('operationId duplicado: ' + $operationId) }
            $operacionIds[$operationId] = $true
        }
    }
    $schemas = @{}
    if ($Documento.components -and $Documento.components.schemas) {
        foreach ($schema in @($Documento.components.schemas.PSObject.Properties)) { $schemas[$schema.Name] = $true }
    }
    foreach ($referencia in @(Obtener-ReferenciasOpenApi -Objeto $Documento)) {
        if ($referencia -match '^#/components/schemas/(.+)$' -and -not $schemas.ContainsKey($Matches[1])) { throw ('Referencia OpenAPI rota: ' + $referencia) }
    }
    return $true
}

function Construir-DocumentoOpenApi {
    param(
        [Parameter(Mandatory = $true)]$Contexto,
        [Parameter(Mandatory = $true)][string]$Xpz,
        [Parameter(Mandatory = $true)]$Envelope,
        [Parameter(Mandatory = $true)]$Mapeo
    )
    $paths = [ordered]@{}
    $tags = New-Object System.Collections.Generic.List[object]
    $tagsVistos = @{}
    foreach ($operacion in @($Mapeo.Operaciones)) {
        $ruta = Obtener-NombreRutaOpenApi -Endpoint ([string]$operacion.endpoint)
        if ($paths.Contains($ruta)) { throw ('Ruta OpenAPI duplicada: ' + $ruta) }
        $operationObject = [ordered]@{}
        foreach ($propiedad in @('operationId', 'summary', 'parameters', 'requestBody', 'responses', 'tags')) {
            if ($null -ne $operacion.$propiedad -and ($propiedad -ne 'parameters' -or @($operacion.parameters).Count -gt 0) -and ($propiedad -ne 'requestBody' -or $null -ne $operacion.requestBody)) { $operationObject[$propiedad] = $operacion.$propiedad }
        }
        $operationObject.security = @([ordered]@{ basicAuth = @() })
        $paths[$ruta] = [ordered]@{ ([string]$operacion.method) = [pscustomobject]$operationObject }
        foreach ($tag in @($operacion.tags)) {
            if (-not $tagsVistos.ContainsKey([string]$tag)) { $tagsVistos[[string]$tag] = $true; [void]$tags.Add([ordered]@{ name = [string]$tag }) }
        }
    }
    $documento = [ordered]@{
        openapi = '3.0.3'
        info = [ordered]@{ title = 'APIGLM'; version = '' }
        servers = @([ordered]@{ url = [string]$Contexto.ServerUrl })
        tags = @($tags.ToArray())
        paths = [pscustomobject]$paths
        components = [ordered]@{ securitySchemes = [ordered]@{ basicAuth = [ordered]@{ type = 'http'; scheme = 'basic' } }; schemas = [pscustomobject]$Mapeo.Esquemas }
        'x-glm-context' = [ordered]@{ contextId = [string]$Contexto.ContextId; clienteId = [string]$Contexto.ClienteId; modulo = [string]$Contexto.Modulo; ambienteId = [string]$Contexto.AmbienteId }
        'x-glm-source' = [ordered]@{ contextId = [string]$Contexto.ContextId; xpz = [System.IO.Path]::GetFileName($Xpz) }
    }
    $documento.info.version = Obtener-HashSemanticoOpenApi -Documento ([pscustomobject]$documento)
    Validar-DocumentoOpenApi -Documento ([pscustomobject]$documento) | Out-Null
    return [pscustomobject]$documento
}

function Convertir-DocumentoOpenApiAJson {
    param([Parameter(Mandatory = $true)]$Documento)
    return (Normalizar-SaltosLineaLf -Texto ($Documento | ConvertTo-Json -Depth 100))
}

function Publicar-DocumentoOpenApi {
    param(
        [Parameter(Mandatory = $true)][string]$Ruta,
        [Parameter(Mandatory = $true)]$Documento
    )
    $json = Convertir-DocumentoOpenApiAJson -Documento $Documento
    if (Test-Path -LiteralPath $Ruta -PathType Leaf) {
        $anterior = [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath($Ruta))
        $objetoAnterior = $null
        try { $objetoAnterior = $anterior | ConvertFrom-Json } catch { $objetoAnterior = $null }
        if ($null -ne $objetoAnterior) {
            try { Validar-DocumentoOpenApi -Documento $objetoAnterior | Out-Null } catch { $objetoAnterior = $null }
        }
        if ($null -ne $objetoAnterior -and (Comparar-DocumentosOpenApiSemanticos -DocumentoNuevo $Documento -JsonAnterior $anterior)) {
            return [pscustomobject]@{ Ruta = [System.IO.Path]::GetFullPath($Ruta); Publicado = $false; FastPath = $true; Hash = [string]$Documento.info.version }
        }
    }
    $validar = {
        param([string]$RutaTemporal)
        $contenidoTemporal = [System.IO.File]::ReadAllText($RutaTemporal)
        try { $objetoTemporal = $contenidoTemporal | ConvertFrom-Json } catch { throw ('El contrato OpenAPI temporal no contiene JSON valido: ' + $_.Exception.Message) }
        Validar-DocumentoOpenApi -Documento $objetoTemporal | Out-Null
    }
    Escribir-ArchivoAtomico -Ruta $Ruta -Contenido $json -Validar $validar | Out-Null
    return [pscustomobject]@{ Ruta = [System.IO.Path]::GetFullPath($Ruta); Publicado = $true; FastPath = $false; Hash = [string]$Documento.info.version }
}

try {
    $rutaConfiguracion = Obtener-RutaConfiguracionOpenApi
    $script:OpenApiManifest = $null
    if (-not [string]::IsNullOrWhiteSpace($ManifiestoPath)) {
        $script:OpenApiManifest = Leer-ManifiestoEjecucion -RutaManifiesto $ManifiestoPath
    }
    $contexto = Resolver-ContextoOpenApi -RutaConfiguracion $rutaConfiguracion -Manifiesto $script:OpenApiManifest
    $rutaXpz = if ($script:OpenApiManifest) { [string]$script:OpenApiManifest.xpz } elseif ($XpzPath) { [System.IO.Path]::GetFullPath($XpzPath) } else { throw 'La generacion OpenAPI requiere -XpzPath o -ManifiestoPath.' }
    if (-not (Test-Path -LiteralPath $rutaXpz -PathType Leaf)) { throw ('No se encontro el XPZ para OpenAPI: ' + $rutaXpz) }

    $indice = Cargar-IndiceMultiXPZ -RutaXpzPrincipal $rutaXpz
    $inventario = @(Obtener-ServiciosHttpDesdeIndice -Indice $indice | Where-Object { @($contexto.ServiciosIgnorados) -notcontains $_.proceso })
    if ($inventario.Count -eq 0) { throw 'El XPZ no contiene servicios HTTP confirmados para OpenAPI.' }
    $rutaControl = $contexto.RutaControl
    if (-not (Test-Path -LiteralPath $rutaControl -PathType Leaf)) { throw ('No existe control de versiones para el contexto: ' + $contexto.ContextId) }
    $control = Leer-ControlVersiones -RutaControl $rutaControl
    $envelope = Construir-EnvelopeAnalisisOpenApi -Contexto $contexto -Xpz $rutaXpz -Indice $indice -Inventario $inventario -Control $control
    $mapeo = Convertir-EnvelopeAOperacionesOpenApi -Envelope $envelope
    $json = Convertir-EnvelopeContratoAnalisisAJson -Envelope $envelope
    if (-not [string]::IsNullOrWhiteSpace($RutaContratoAnalisis)) {
        Escribir-ArchivoAtomico -Ruta $RutaContratoAnalisis -Contenido $json | Out-Null
    }
    $documentoOpenApi = Construir-DocumentoOpenApi -Contexto $contexto -Xpz $rutaXpz -Envelope $envelope -Mapeo $mapeo
    $rutaPublicacion = if ($RutaOpenApi) { [System.IO.Path]::GetFullPath($RutaOpenApi) } else { [System.IO.Path]::GetFullPath((Join-Path $contexto.DirectorioServicios 'OpenAPI\openapi.json')) }
    $publicacion = Publicar-DocumentoOpenApi -Ruta $rutaPublicacion -Documento $documentoOpenApi
    Write-Output ('OPENAPI_GENERADO: ' + $publicacion.Ruta)
    [pscustomobject]@{ Envelope = $envelope; DocumentoOpenApi = $documentoOpenApi; Operaciones = $mapeo.Operaciones; NombresEsquema = $mapeo.NombresEsquema; Publicacion = $publicacion }
    exit 0
} catch {
    Write-Error ('GenerarOpenApi: ' + $_.Exception.Message)
    exit 1
}
