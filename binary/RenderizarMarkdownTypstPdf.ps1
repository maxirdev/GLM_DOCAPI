# Convierte Markdown a PDF mediante Pandoc y Typst.
# Ambos ejecutables se distribuyen como herramientas portables del proyecto.

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'GLMUtilidades.ps1')

function Reemplazar-PdfValidado {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaTemporal,
        [Parameter(Mandatory = $true)][string]$RutaVigente
    )

    if (Test-Path -LiteralPath $RutaVigente -PathType Leaf) {
        $rutaRespaldo = $RutaVigente + '.' + [Guid]::NewGuid().ToString('N') + '.bak'
        try {
            [System.IO.File]::Replace($RutaTemporal, $RutaVigente, $rutaRespaldo)
        } finally {
            if (Test-Path -LiteralPath $rutaRespaldo -PathType Leaf) {
                Remove-Item -LiteralPath $rutaRespaldo -Force -ErrorAction SilentlyContinue
            }
        }
    } else {
        Move-Item -LiteralPath $RutaTemporal -Destination $RutaVigente
    }
}

function Resaltar-MetodoHttpTypst {
    param([Parameter(Mandatory = $true)][string]$Contenido)

    $patron = '(?m)^(\s*)\[(M[^\]]*todo HTTP)\],\s*\[`?(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|TRACE)`?\],\s*$'
    return [regex]::Replace($Contenido, $patron, {
        param($coincidencia)
        $indentacion = $coincidencia.Groups[1].Value
        $etiqueta = $coincidencia.Groups[2].Value
        $metodo = $coincidencia.Groups[3].Value.ToUpperInvariant()
        return $indentacion + '[' + $etiqueta + '], [#box(fill: accent-soft, stroke: 0.6pt + accent, radius: 3pt, inset: (x: 7pt, y: 3pt))[#text(weight: "bold", fill: accent)[' + $metodo + ']]],'
    })
}

function Agregar-CortesEnCodigoInlineTypst {
    param([Parameter(Mandatory = $true)][string]$Contenido)

    $corte = [char]0x200B
    return [regex]::Replace($Contenido, '(?<!`)`([^`\r\n]+)`(?!`)', {
        param($coincidencia)
        $valor = $coincidencia.Groups[1].Value
        $valor = [regex]::Replace($valor, '([\p{Ll}\d])([\p{Lu}])', ('$1' + $corte + '$2'))
        foreach ($separador in @('.', '/', '_', '-')) {
            $valor = $valor.Replace($separador, ($separador + $corte))
        }
        return '`' + $valor + '`'
    })
}

function Ajustar-TablasTypst {
    param([Parameter(Mandatory = $true)][string]$Contenido)

    $ajustado = [regex]::Replace($Contenido, '(?m)(#table\(\r?\n)\s*columns:\s*(\d+),', {
        param($coincidencia)
        $cantidad = [int]$coincidencia.Groups[2].Value
        if ($cantidad -eq 2) {
            $columnas = '0.28fr, 0.72fr'
        } elseif ($cantidad -eq 3) {
            $columnas = '0.28fr, 0.32fr, 0.40fr'
        } elseif ($cantidad -eq 4) {
            $columnas = '1.2fr, 1fr, 0.8fr, 2fr'
        } else {
            $columnas = (1..$cantidad | ForEach-Object { '1fr' }) -join ', '
        }
        return $coincidencia.Groups[1].Value + '  columns: (' + $columnas + '),'
    })
    $ajustado = [regex]::Replace($ajustado, '(?m)^(\s*)align:\s*\(([^)]*)\),', {
        param($coincidencia)
        $cantidad = @($coincidencia.Groups[2].Value -split ',' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
        if ($cantidad -eq 0) { return $coincidencia.Value }
        $alineaciones = (1..$cantidad | ForEach-Object { 'left' }) -join ', '
        return $coincidencia.Groups[1].Value + 'align: (' + $alineaciones + '),'
    })
    $ajustado = $ajustado.Replace('align(center)[#table(', 'align(left)[#table(')
    return $ajustado
}

function Quitar-ContenedoresFiguraTablaTypst {
    param([Parameter(Mandatory = $true)][string]$Contenido)

    $patron = '(?ms)^#figure\(\r?\n\s*align\((?:center|left)\)\[#table\((.*?)\)\]\r?\n\s*, kind: table\r?\n\s*\)'
    return [regex]::Replace($Contenido, $patron, {
        param($coincidencia)
        return '#table(' + $coincidencia.Groups[1].Value + ')'
    })
}

function Copiar-RecursosMarkdownTypst {
    param(
        [Parameter(Mandatory = $true)][string]$Contenido,
        [Parameter(Mandatory = $true)][string]$RutaRecursos,
        [Parameter(Mandatory = $true)][string]$DirectorioDestino
    )

    if ([string]::IsNullOrWhiteSpace($RutaRecursos)) { return }
    $directorioRecursos = [System.IO.Path]::GetFullPath($RutaRecursos).TrimEnd('\') + '\'
    foreach ($coincidencia in [regex]::Matches($Contenido, '!?\[[^\]]*\]\(([^)\s]+)')) {
        $referencia = [System.Uri]::UnescapeDataString([string]$coincidencia.Groups[1].Value)
        if ([string]::IsNullOrWhiteSpace($referencia) -or $referencia -match '^(?i)(?:[a-z][a-z0-9+.-]*:|//)') { continue }
        $referenciaRelativa = $referencia.Replace('/', '\')
        $rutaRecurso = [System.IO.Path]::GetFullPath((Join-Path $RutaRecursos $referenciaRelativa))
        if (-not $rutaRecurso.StartsWith($directorioRecursos, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ('La imagen del reporte queda fuera de su carpeta de recursos: ' + $referencia)
        }
        if (-not (Test-Path -LiteralPath $rutaRecurso -PathType Leaf)) {
            throw ('No se encontro la imagen referenciada por el Markdown: ' + $referencia)
        }
        $rutaDestino = Join-Path $DirectorioDestino $referenciaRelativa
        $directorioDestino = Split-Path -Parent $rutaDestino
        if (-not (Test-Path -LiteralPath $directorioDestino -PathType Container)) {
            New-Item -ItemType Directory -Path $directorioDestino -Force | Out-Null
        }
        Copy-Item -LiteralPath $rutaRecurso -Destination $rutaDestino -Force
    }
}

function Obtener-NombreWsPieDePagina {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Titulo,
        [Parameter(Mandatory = $true)][string]$NombreArchivo
    )

    $nombre = $Titulo -replace '\s+', ''
    if (-not $nombre) { return $NombreArchivo }
    if ($nombre.StartsWith('WS', [System.StringComparison]::OrdinalIgnoreCase)) {
        $nombre = $nombre.Substring(2)
    }
    return ('WS ' + $nombre)
}

function Agregar-PieDePaginaTypst {
    param(
        [Parameter(Mandatory = $true)][string]$Contenido,
        [Parameter(Mandatory = $true)][string]$NombreServicio
    )

    $paginaConAcento = 'P' + [char]0xE1 + 'gina'
    $pieDePagina = @'
#let ws-nombre = "{NOMBRE}"
#set page(footer: context {
  let total-pages = counter(page).final().first()
  let current-page = counter(page).get().first()
  grid(
    columns: (1fr, auto),
    [
      #text(size: 8pt, fill: rgb("#6b7280"))[#ws-nombre]
    ],
    [
      #text(size: 8pt, fill: rgb("#6b7280"))[- {PAGINA} #current-page/#total-pages]
    ],
  )
})

'@
    $pieDePagina = $pieDePagina.Replace('{NOMBRE}', $NombreServicio)
    $pieDePagina = $pieDePagina.Replace('{PAGINA}', $paginaConAcento)
    return ($pieDePagina + $Contenido)
}

function Invoke-HerramientaPdf {
    param(
        [Parameter(Mandatory = $true)][string]$RutaEjecutable,
        [Parameter(Mandatory = $true)][string[]]$Argumentos,
        [Parameter(Mandatory = $true)][string]$Nombre,
        [Parameter(Mandatory = $true)][int]$TiempoMaximoMs
    )

    $informacionInicio = New-Object System.Diagnostics.ProcessStartInfo
    $informacionInicio.FileName = $RutaEjecutable
    $informacionInicio.Arguments = ($Argumentos | ForEach-Object { Quote-ProcessArgument $_ }) -join ' '
    $informacionInicio.WorkingDirectory = Split-Path -Parent $RutaEjecutable
    $informacionInicio.UseShellExecute = $false
    $informacionInicio.CreateNoWindow = $true
    $informacionInicio.RedirectStandardOutput = $true
    $informacionInicio.RedirectStandardError = $true

    $proceso = New-Object System.Diagnostics.Process
    $proceso.StartInfo = $informacionInicio
    try {
        if (-not $proceso.Start()) { throw ("No se pudo iniciar " + $Nombre + '.') }
        $salida = $proceso.StandardOutput.ReadToEndAsync()
        $error = $proceso.StandardError.ReadToEndAsync()
        if (-not $proceso.WaitForExit($TiempoMaximoMs)) {
            try { $proceso.Kill() } catch { }
            throw ($Nombre + ' no termino dentro del tiempo esperado.')
        }
        $textoSalida = $salida.GetAwaiter().GetResult()
        $textoError = $error.GetAwaiter().GetResult()
        if ($proceso.ExitCode -ne 0) {
            $detalle = (($textoError, $textoSalida) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
            if ([string]::IsNullOrWhiteSpace($detalle)) { $detalle = 'sin mensaje adicional' }
            throw ($Nombre + ' termino con codigo ' + $proceso.ExitCode + ': ' + $detalle.Trim())
        }
        return [pscustomobject]@{ Salida = $textoSalida; Error = $textoError }
    } finally {
        $proceso.Dispose()
    }
}

function Convertir-MarkdownAPdf {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Markdown,
        [Parameter(Mandatory = $true)][string]$RutaSalida,
        [Parameter(Mandatory = $true)][string]$RutaPandoc,
        [Parameter(Mandatory = $true)][string]$RutaTypst,
        [Parameter(Mandatory = $false)][string]$RutaRecursos = ''
    )

    foreach ($herramienta in @(
        [pscustomobject]@{ Nombre = 'Pandoc'; Ruta = $RutaPandoc },
        [pscustomobject]@{ Nombre = 'Typst'; Ruta = $RutaTypst }
    )) {
        if (-not (Test-Path -LiteralPath $herramienta.Ruta -PathType Leaf)) {
            throw ('No se encontro ' + $herramienta.Nombre + ' en: ' + $herramienta.Ruta)
        }
    }

    $directorioSalida = Split-Path -Parent $RutaSalida
    if (-not (Test-Path -LiteralPath $directorioSalida -PathType Container)) {
        New-Item -ItemType Directory -Path $directorioSalida -Force | Out-Null
    }
    $nombrePdfTemporal = '.' + [System.IO.Path]::GetFileNameWithoutExtension($RutaSalida) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp.pdf'
    $rutaPdfTemporal = Join-Path $directorioSalida $nombrePdfTemporal

    $directorioTemporal = Join-Path ([System.IO.Path]::GetTempPath()) ('APIGLM-PDF-' + [Guid]::NewGuid().ToString('N'))
    $rutaMarkdown = Join-Path $directorioTemporal 'documento.md'
    $rutaFuenteTypst = Join-Path $directorioTemporal 'documento.typ'
    $rutaPlantillaTypst = Join-Path $PSScriptRoot 'templates\documentacion.typ'
    $rutaFuentes = Join-Path $PSScriptRoot 'fonts'
    try {
        New-Item -ItemType Directory -Path $directorioTemporal -Force | Out-Null
        if (-not (Test-Path -LiteralPath $rutaPlantillaTypst -PathType Leaf)) {
            throw ('No se encontro la plantilla Typst de documentacion: ' + $rutaPlantillaTypst)
        }
        if (-not (Test-Path -LiteralPath (Join-Path $rutaFuentes 'Poppins-Regular.ttf') -PathType Leaf)) {
            throw ('No se encontro la fuente Poppins en: ' + $rutaFuentes)
        }
        $codificacion = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($rutaMarkdown, $Markdown, $codificacion)
        Copiar-RecursosMarkdownTypst -Contenido $Markdown -RutaRecursos $RutaRecursos -DirectorioDestino $directorioTemporal

        $argumentosPandoc = @(
            '--from=gfm',
            '--to=typst',
            '--standalone',
            '--metadata=lang:es',
            ('--template=' + $rutaPlantillaTypst),
            ('--output=' + $rutaFuenteTypst),
            $rutaMarkdown
        )
        if (-not [string]::IsNullOrWhiteSpace($RutaRecursos)) {
            $argumentosPandoc = @('--resource-path=' + [System.IO.Path]::GetFullPath($RutaRecursos)) + $argumentosPandoc
        }
        [void](Invoke-HerramientaPdf -RutaEjecutable $RutaPandoc -Nombre 'Pandoc' -TiempoMaximoMs 120000 -Argumentos $argumentosPandoc)

        $contenidoTypst = [System.IO.File]::ReadAllText($rutaFuenteTypst)
        $contenidoTypst = Ajustar-TablasTypst -Contenido $contenidoTypst
        $contenidoTypst = Agregar-CortesEnCodigoInlineTypst -Contenido $contenidoTypst
        $contenidoTypst = Quitar-ContenedoresFiguraTablaTypst -Contenido $contenidoTypst
        $contenidoTypst = Resaltar-MetodoHttpTypst -Contenido $contenidoTypst
        $tituloServicio = ''
        foreach ($linea in ($Markdown -split "`n")) {
            if ($linea -match '^\s*#\s+(.+?)\s*$') {
                $tituloServicio = $Matches[1].Trim()
                break
            }
        }
        $nombreServicio = Obtener-NombreWsPieDePagina -Titulo $tituloServicio -NombreArchivo ([System.IO.Path]::GetFileNameWithoutExtension($RutaSalida))
        $contenidoTypst = Agregar-PieDePaginaTypst -Contenido $contenidoTypst -NombreServicio $nombreServicio
        [System.IO.File]::WriteAllText($rutaFuenteTypst, $contenidoTypst, $codificacion)

        [void](Invoke-HerramientaPdf -RutaEjecutable $RutaTypst -Nombre 'Typst' -TiempoMaximoMs 120000 -Argumentos @(
            'compile',
            '--font-path',
            $rutaFuentes,
            $rutaFuenteTypst,
            $rutaPdfTemporal
        ))

        if (-not (Test-PdfValidoParaPromocion -Ruta $rutaPdfTemporal)) {
            throw 'Typst termino correctamente, pero no genero un PDF valido.'
        }
        Reemplazar-PdfValidado -RutaTemporal $rutaPdfTemporal -RutaVigente $RutaSalida
        return $RutaSalida
    } finally {
        if (Test-Path -LiteralPath $rutaPdfTemporal -PathType Leaf) {
            Remove-Item -LiteralPath $rutaPdfTemporal -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $directorioTemporal -PathType Container) {
            Remove-Item -LiteralPath $directorioTemporal -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
