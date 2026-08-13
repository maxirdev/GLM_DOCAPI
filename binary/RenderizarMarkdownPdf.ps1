# Conversor local de la redaccion Markdown a PDF mediante Microsoft Edge headless.

$ErrorActionPreference = 'Stop'

function Convertir-TextoHtml {
    param([AllowEmptyString()][string]$Texto)
    return [System.Net.WebUtility]::HtmlEncode([string]$Texto)
}

function Convertir-InlineMarkdown {
    param([AllowEmptyString()][string]$Texto)

    $html = Convertir-TextoHtml -Texto $Texto
    $html = [regex]::Replace($html, '`([^`]+)`', '<code>$1</code>')
    $html = [regex]::Replace($html, '\*\*([^*]+)\*\*', '<strong>$1</strong>')
    $html = [regex]::Replace($html, '(?<!\*)\*([^*]+)\*(?!\*)', '<em>$1</em>')
    $html = [regex]::Replace($html, '\[([^\]]+)\]\(([^)]+)\)', '<a href="$2">$1</a>')
    return $html
}

function Obtener-CeldasTabla {
    param([Parameter(Mandatory = $true)][string]$Linea)

    $texto = $Linea.Trim()
    if ($texto.StartsWith('|')) { $texto = $texto.Substring(1) }
    if ($texto.EndsWith('|')) { $texto = $texto.Substring(0, $texto.Length - 1) }
    return @($texto -split '\|' | ForEach-Object { $_.Trim() })
}

function EsSeparadorTabla {
    param([Parameter(Mandatory = $true)][string]$Linea)
    return ($Linea -match '^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$')
}

function Agregar-Parrafo {
    param(
        [Parameter(Mandatory = $true)][System.Text.StringBuilder]$Builder,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Lineas
    )

    if ($Lineas.Count -eq 0) { return }
    $texto = ($Lineas -join ' ').Trim()
    if ($texto) { [void]$Builder.AppendLine('<p>' + (Convertir-InlineMarkdown $texto) + '</p>') }
    $Lineas.Clear()
}

function Convertir-MarkdownAHtml {
    param([Parameter(Mandatory = $true)][string]$Markdown)

    $builder = New-Object System.Text.StringBuilder
    $rutaCss = Join-Path $PSScriptRoot 'templates\documentacion.css'
    if (Test-Path -LiteralPath $rutaCss -PathType Leaf) {
        $css = [System.IO.File]::ReadAllText($rutaCss)
    } else {
        throw ('No se encontro la plantilla CSS de documentacion: ' + $rutaCss)
    }
    [void]$builder.AppendLine('<!doctype html>')
    [void]$builder.AppendLine('<html lang="es"><head><meta charset="utf-8">')
    [void]$builder.AppendLine('<style>')
    [void]$builder.AppendLine($css)
    [void]$builder.AppendLine('</style></head><body>')

    $lineas = @($Markdown -replace "`r`n", "`n" -replace "`r", "`n" -split "`n")
    $parrafo = New-Object 'System.Collections.Generic.List[string]'
    $indice = 0

    while ($indice -lt $lineas.Count) {
        $linea = [string]$lineas[$indice]
        $lineaSinFinal = $linea.TrimEnd()

        if ([string]::IsNullOrWhiteSpace($lineaSinFinal)) {
            Agregar-Parrafo -Builder $builder -Lineas $parrafo
            $indice++
            continue
        }

        if ($lineaSinFinal -match '^\s*```') {
            Agregar-Parrafo -Builder $builder -Lineas $parrafo
            $indice++
            $codigo = New-Object System.Collections.Generic.List[string]
            while ($indice -lt $lineas.Count -and $lineas[$indice] -notmatch '^\s*```') {
                [void]$codigo.Add([string]$lineas[$indice])
                $indice++
            }
            if ($indice -lt $lineas.Count) { $indice++ }
            $contenidoCodigo = Convertir-TextoHtml -Texto ($codigo -join "`n")
            [void]$builder.AppendLine('<pre><code>' + $contenidoCodigo + '</code></pre>')
            continue
        }

        if ($lineaSinFinal -match '^\s*\|.*\|\s*$' -and ($indice + 1) -lt $lineas.Count -and (EsSeparadorTabla -Linea ([string]$lineas[$indice + 1]))) {
            Agregar-Parrafo -Builder $builder -Lineas $parrafo
            $encabezados = @(Obtener-CeldasTabla -Linea $lineaSinFinal)
            [void]$builder.AppendLine('<table><thead><tr>')
            foreach ($encabezado in $encabezados) { [void]$builder.AppendLine('<th>' + (Convertir-InlineMarkdown $encabezado) + '</th>') }
            [void]$builder.AppendLine('</tr></thead><tbody>')
            $indice += 2
            while ($indice -lt $lineas.Count -and ([string]$lineas[$indice]).Trim() -match '^\s*\|.*\|\s*$') {
                $celdas = @(Obtener-CeldasTabla -Linea ([string]$lineas[$indice]))
                $esMetodoHttp = $celdas.Count -ge 2 -and ([string]$celdas[0] -match '(?i)^M.{0,2}todo HTTP$')
                $claseFila = if ($esMetodoHttp) { ' class="http-method-row"' } else { '' }
                [void]$builder.AppendLine('<tr' + $claseFila + '>')
                for ($indiceCelda = 0; $indiceCelda -lt $celdas.Count; $indiceCelda++) {
                    $celdaHtml = Convertir-InlineMarkdown ([string]$celdas[$indiceCelda])
                    if ($esMetodoHttp -and $indiceCelda -eq 1) {
                        $celdaHtml = '<span class="http-method-badge">' + $celdaHtml + '</span>'
                    }
                    [void]$builder.AppendLine('<td>' + $celdaHtml + '</td>')
                }
                [void]$builder.AppendLine('</tr>')
                $indice++
            }
            [void]$builder.AppendLine('</tbody></table>')
            continue
        }

        if ($lineaSinFinal -match '^\s*(#{1,6})\s+(.+)$') {
            Agregar-Parrafo -Builder $builder -Lineas $parrafo
            $nivel = $Matches[1].Length
            [void]$builder.AppendLine(('<h{0}>{1}</h{0}>' -f $nivel, (Convertir-InlineMarkdown $Matches[2])))
            $indice++
            continue
        }

        if ($lineaSinFinal -match '^\s*>\s?(.*)$') {
            Agregar-Parrafo -Builder $builder -Lineas $parrafo
            $citas = New-Object System.Collections.Generic.List[string]
            while ($indice -lt $lineas.Count -and ([string]$lineas[$indice]).TrimEnd() -match '^\s*>\s?(.*)$') {
                [void]$citas.Add($Matches[1])
                $indice++
            }
            [void]$builder.AppendLine('<blockquote>' + (Convertir-InlineMarkdown ($citas -join ' ')) + '</blockquote>')
            continue
        }

        if ($lineaSinFinal -match '^\s*[-*+]\s+(.+)$' -or $lineaSinFinal -match '^\s*\d+\.\s+(.+)$') {
            Agregar-Parrafo -Builder $builder -Lineas $parrafo
            $esNumerada = $lineaSinFinal -match '^\s*\d+\.\s+(.+)$'
            $etiqueta = if ($esNumerada) { 'ol' } else { 'ul' }
            [void]$builder.AppendLine('<' + $etiqueta + '>')
            while ($indice -lt $lineas.Count) {
                $elemento = ([string]$lineas[$indice]).TrimEnd()
                $coincide = if ($esNumerada) { $elemento -match '^\s*\d+\.\s+(.+)$' } else { $elemento -match '^\s*[-*+]\s+(.+)$' }
                if (-not $coincide) { break }
                [void]$builder.AppendLine('<li>' + (Convertir-InlineMarkdown $Matches[1]) + '</li>')
                $indice++
            }
            [void]$builder.AppendLine('</' + $etiqueta + '>')
            continue
        }

        [void]$parrafo.Add($lineaSinFinal.Trim())
        $indice++
    }

    Agregar-Parrafo -Builder $builder -Lineas $parrafo
    [void]$builder.AppendLine('</body></html>')
    return $builder.ToString()
}

function Quote-EdgeArgument {
    param([Parameter(Mandatory = $true)][string]$Valor)
    return '"' + $Valor.Replace('"', '\"') + '"'
}

function Test-PdfHeader {
    param([Parameter(Mandatory = $true)][string]$Ruta)

    if (-not (Test-Path -LiteralPath $Ruta -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $Ruta).Length -lt 5) { return $false }
    $stream = [System.IO.File]::OpenRead($Ruta)
    try {
        $buffer = New-Object byte[] 4
        [void]$stream.Read($buffer, 0, 4)
        return ([System.Text.Encoding]::ASCII.GetString($buffer) -eq '%PDF')
    } finally {
        $stream.Dispose()
    }
}

function Convertir-MarkdownAPdf {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Markdown,
        [Parameter(Mandatory = $true)][string]$RutaSalida,
        [Parameter(Mandatory = $true)][string]$RutaEdge
    )

    if (-not (Test-Path -LiteralPath $RutaEdge -PathType Leaf)) {
        throw ('No se encontro Microsoft Edge en: ' + $RutaEdge)
    }

    $directorioSalida = Split-Path -Parent $RutaSalida
    if (-not (Test-Path -LiteralPath $directorioSalida -PathType Container)) {
        New-Item -ItemType Directory -Path $directorioSalida -Force | Out-Null
    }
    if (Test-Path -LiteralPath $RutaSalida -PathType Leaf) {
        Remove-Item -LiteralPath $RutaSalida -Force
    }

    $directorioTemporal = Join-Path ([System.IO.Path]::GetTempPath()) ('APIGLM-PDF-' + [Guid]::NewGuid().ToString('N'))
    $rutaHtml = Join-Path $directorioTemporal 'documento.html'
    $rutaPerfil = Join-Path $directorioTemporal 'perfil-edge'
    $proceso = $null
    try {
        New-Item -ItemType Directory -Path $directorioTemporal -Force | Out-Null
        $html = Convertir-MarkdownAHtml -Markdown $Markdown
        $codificacion = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($rutaHtml, $html, $codificacion)

        $url = (New-Object System.Uri($rutaHtml)).AbsoluteUri
        $argumentos = @(
            '--headless',
            '--disable-gpu',
            '--no-first-run',
            '--no-default-browser-check',
            '--no-pdf-header-footer',
            ('--user-data-dir=' + (Quote-EdgeArgument $rutaPerfil)),
            ('--print-to-pdf=' + (Quote-EdgeArgument $RutaSalida)),
            (Quote-EdgeArgument $url)
        )
        $informacionInicio = New-Object System.Diagnostics.ProcessStartInfo
        $informacionInicio.FileName = $RutaEdge
        $informacionInicio.Arguments = $argumentos -join ' '
        $informacionInicio.UseShellExecute = $false
        $informacionInicio.CreateNoWindow = $true
        $informacionInicio.RedirectStandardOutput = $true
        $informacionInicio.RedirectStandardError = $true
        $proceso = New-Object System.Diagnostics.Process
        $proceso.StartInfo = $informacionInicio
        if (-not $proceso.Start()) { throw 'No se pudo iniciar Microsoft Edge headless.' }
        $tareaSalida = $proceso.StandardOutput.ReadToEndAsync()
        $tareaError = $proceso.StandardError.ReadToEndAsync()
        if (-not $proceso.WaitForExit(120000)) {
            $proceso.Kill()
            throw 'Microsoft Edge no termino la conversion PDF dentro del tiempo esperado.'
        }
        [void]$tareaSalida.GetAwaiter().GetResult()
        [void]$tareaError.GetAwaiter().GetResult()
        if (-not (Test-PdfHeader -Ruta $RutaSalida)) {
            throw ('Microsoft Edge no genero un PDF valido. Codigo: ' + $proceso.ExitCode)
        }
        return $RutaSalida
    } finally {
        if ($null -ne $proceso) { $proceso.Dispose() }
        if (Test-Path -LiteralPath $directorioTemporal -PathType Container) {
            Remove-Item -LiteralPath $directorioTemporal -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
