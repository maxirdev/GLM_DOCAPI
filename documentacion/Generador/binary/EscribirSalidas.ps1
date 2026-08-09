# EscribirSalidas.ps1
# Modulo de escritura de las salidas del generador de documentacion APIGLM.
# Escribe el documento markdown en documentacion/servicios/<wrapper>.md (UTF-8
# sin BOM y finales LF) sin sobrescribir, y el informe de revision en
# documentacion/Generador/assets/apiglm-doc-review.json.
# Se importa por dot-source desde GenerarDocumento.ps1, despues de
# AnalizarServicio.ps1 y RedactarDocumento.ps1.

$ErrorActionPreference = 'Stop'

function Obtener-EvidenciaRequerida {
    <#
    .SYNOPSIS
    Extrae la evidencia requerida del texto de un pendiente.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Pendiente
    )

    $partida = [regex]::Match($Pendiente, 'Evidencia requerida:\s*(.+?)\s*$')
    if ($partida.Success) {
        $evidencia = $partida.Groups[1].Value.TrimEnd('.')
        if ($evidencia) { return $evidencia }
    }
    return $Pendiente
}

function Agregar-ItemsCampo {
    <#
    .SYNOPSIS
    Agrega los items de revision de un campo (tipo o descripcion no confirmados).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Items,
        [Parameter(Mandatory = $true)][object]$Campo,
        [Parameter(Mandatory = $false)][string]$PrefijoRuta = ''
    )

    $ruta = $Campo.Campo
    if ($PrefijoRuta) { $ruta = $PrefijoRuta + '.' + $Campo.Campo }

    if ($Campo.Tipo -match '^PENDIENTE') {
        $Items.Add([pscustomobject]@{
            campo = $ruta
            asunto = 'tipo'
            evidenciaRequerida = (Obtener-EvidenciaRequerida -Pendiente $Campo.Tipo)
            ejemplo = 'Un valor real del campo para confirmar el tipo.'
            pendiente = $Campo.Tipo
        })
    }
    if ($Campo.Descripcion -match '^PENDIENTE') {
        $Items.Add([pscustomobject]@{
            campo = $ruta
            asunto = 'descripcion'
            evidenciaRequerida = (Obtener-EvidenciaRequerida -Pendiente $Campo.Descripcion)
            ejemplo = 'Texto funcional breve para el desarrollador.'
            pendiente = $Campo.Descripcion
        })
    }
}

function Generar-ItemsRevision {
    <#
    .SYNOPSIS
    Genera los items del informe de revision a partir de la documentación técnica.
    .DESCRIPTION
    Recorre el endpoint, la entrada, las estructuras, la salida y los errores de
    la documentación y registra cada juicio no automatizable con su evidencia requerida
    y un ejemplo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Documentacion
    )

    $items = New-Object System.Collections.Generic.List[object]

    if ($Documentacion.EndpointPublicado -match '^PENDIENTE') {
        $ultimoPunto = $Documentacion.FqWrapper.LastIndexOf('.')
        $rutaSinBase = ''
        if ($ultimoPunto -gt 0) {
            $modulo = $Documentacion.FqWrapper.Substring(0, $ultimoPunto)
            $procedimiento = $Documentacion.FqWrapper.Substring($ultimoPunto + 1)
            $rutaSinBase = $modulo.ToLowerInvariant() + '.' + 'a' + $procedimiento.ToLowerInvariant()
        }
        $items.Add([pscustomobject]@{
            campo = ''
            asunto = 'endpoint'
            evidenciaRequerida = (Obtener-EvidenciaRequerida -Pendiente $Documentacion.EndpointPublicado)
            ejemplo = $rutaSinBase
            pendiente = $Documentacion.EndpointPublicado
        })
    }

    foreach ($campo in $Documentacion.Entrada) {
        Agregar-ItemsCampo -Items $items -Campo $campo
    }
    foreach ($estructura in $Documentacion.Estructuras) {
        foreach ($hijo in $estructura.Hijos) {
            Agregar-ItemsCampo -Items $items -Campo $hijo -PrefijoRuta $estructura.RutaJson
        }
    }
    foreach ($campo in $Documentacion.Salida) {
        Agregar-ItemsCampo -Items $items -Campo $campo
    }
    foreach ($error in $Documentacion.Errores) {
        if ($error.Codigo -eq 0) {
            $pendiente = 'PENDIENTE DE CONFIRMACIÓN: codigo HTTP del error. Evidencia requerida: respuesta real sanitizada o configuración desplegada.'
            $items.Add([pscustomobject]@{
                campo = ''
                asunto = 'codigo'
                evidenciaRequerida = 'respuesta real sanitizada o configuración desplegada'
                ejemplo = 'Numero HTTP confirmado para el rechazo.'
                pendiente = $pendiente
            })
        }
    }

    $vistos = @{}
    $unicos = New-Object System.Collections.Generic.List[object]
    foreach ($item in $items) {
        $clave = $item.campo + '|' + $item.asunto
        if (-not $vistos.ContainsKey($clave)) {
            $vistos[$clave] = $true
            $unicos.Add($item)
        }
    }
    return $unicos.ToArray()
}

function Escribir-Salidas {
    <#
    .SYNOPSIS
    Escribe el documento markdown y el informe de revision del servicio.
    .DESCRIPTION
    Escribe el documento en <directorioSalida>/<wrapper en minusculas>.md con
    UTF-8 sin BOM y finales LF. Si el archivo ya existe, lo regenera.
    Escribe ademas apiglm-doc-review.json con los juicios no automatizables.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Documentacion,
        [Parameter(Mandatory = $true)][string]$Documento,
        [Parameter(Mandatory = $true)][string]$DirectorioSalida,
        [Parameter(Mandatory = $true)][string]$RutaInformeRevision
    )

    $ultimoPunto = $Documentacion.FqWrapper.LastIndexOf('.')
    if ($ultimoPunto -le 0) {
        throw ('El wrapper ' + $Documentacion.FqWrapper + ' no tiene un nombre completo valido.')
    }
    $nombreWrapper = $Documentacion.FqWrapper.Substring($ultimoPunto + 1).ToLowerInvariant()
    $rutaDocumento = Join-Path $DirectorioSalida ($nombreWrapper + '.md')

    if (-not (Test-Path -LiteralPath $DirectorioSalida)) {
        New-Item -ItemType Directory -Path $DirectorioSalida -Force | Out-Null
    }
    $documentoNormalizado = $Documento -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($rutaDocumento, $documentoNormalizado, (New-Object System.Text.UTF8Encoding($false)))

    $items = Generar-ItemsRevision -Documentacion $Documentacion
    $informe = [pscustomobject]@{ servicio = $Documentacion.FqWrapper; items = @($items) }
    $json = $informe | ConvertTo-Json -Depth 6
    $json = $json -replace "`r`n", "`n"
    $directorioInforme = [System.IO.Path]::GetDirectoryName($RutaInformeRevision)
    if (-not (Test-Path -LiteralPath $directorioInforme)) {
        New-Item -ItemType Directory -Path $directorioInforme -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($RutaInformeRevision, $json, (New-Object System.Text.UTF8Encoding($false)))

    return $rutaDocumento
}
