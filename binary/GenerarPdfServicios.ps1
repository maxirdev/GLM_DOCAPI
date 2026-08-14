# GenerarPdfServicios.ps1
# Convierte bajo demanda los documentos Markdown existentes en PDF.
# No analiza el XPZ ni modifica los archivos Markdown.

[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$Todos
)

$ErrorActionPreference = 'Stop'
$StartTime = Get-Date
$RaizRepositorio = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $ConfigPath) { $ConfigPath = Join-Path $RaizRepositorio 'configuracion.json' }

$script:spinnerActivo = $false
$script:spinnerEstado = $null
$script:spinnerRunspace = $null
$script:spinnerToken = $null

function Seleccionar-Documentos {
    param([Parameter(Mandatory = $true)][object[]]$Documentos)

    Write-Host ''
    Write-Host '  Modos de conversion PDF:' -ForegroundColor Cyan
    Write-Host '    1. Documento particular'
    Write-Host '    2. Multiples documentos'
    Write-Host '    3. TODOS los documentos Markdown'
    Write-Host ''
    $modo = 0
    while ($modo -lt 1 -or $modo -gt 3) {
        $texto = Read-Host 'Seleccione un modo [1-3]'
        $parseado = 0
        if ([int]::TryParse($texto, [ref]$parseado)) { $modo = $parseado } else { $modo = 0 }
        if ($modo -lt 1 -or $modo -gt 3) {
            Write-Host '  Seleccion invalida. Ingrese 1, 2 o 3.' -ForegroundColor Yellow
        }
    }

    if ($modo -eq 1) {
        for ($i = 0; $i -lt $Documentos.Count; $i++) {
            Write-Host ('  {0,3}. {1}' -f ($i + 1), $Documentos[$i].Name)
        }
        $seleccion = 0
        while ($seleccion -lt 1 -or $seleccion -gt $Documentos.Count) {
            $texto = Read-Host ('Seleccione un documento [1-' + $Documentos.Count + ']')
            $parseado = 0
            if ([int]::TryParse($texto, [ref]$parseado)) { $seleccion = $parseado } else { $seleccion = 0 }
            if ($seleccion -lt 1 -or $seleccion -gt $Documentos.Count) {
                Write-Host ('  Seleccion invalida. Ingrese un numero entre 1 y ' + $Documentos.Count + '.') -ForegroundColor Yellow
            }
        }
        return @($Documentos[$seleccion - 1])
    }

    if ($modo -eq 2) {
        $seleccionadosGrid = $Documentos | Select-Object Name, FullName | Out-GridView -OutputMode Multiple -Title 'Seleccione los Markdown para convertir a PDF'
        if ($null -eq $seleccionadosGrid) { return @() }
        return @($Documentos | Where-Object { $_.FullName -in $seleccionadosGrid.FullName })
    }

    return @($Documentos)
}

function Iniciar-Spinner {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Estado,
        [Parameter(Mandatory = $true)][string[]]$Secuencias
    )

    $runspace = [powershell]::Create()
    [void]$runspace.AddScript({
        param($EstadoSpinner, $Marcos)
        $indice = 0
        while ($EstadoSpinner.Activo) {
            if (-not $EstadoSpinner.Pausa) {
                $marco = $Marcos[$indice % $Marcos.Count]
                [Console]::Write("`rGenerando PDF... $marco")
                $indice++
            }
            Start-Sleep -Milliseconds 120
        }
        [Console]::Write("`r" + (' ' * 30) + "`r")
    }).AddArgument($Estado).AddArgument($Secuencias)
    return $runspace
}

function Detener-Spinner {
    if (-not $script:spinnerActivo) { return }
    if ($null -ne $script:spinnerRunspace) {
        $script:spinnerEstado.Activo = $false
        try { $script:spinnerRunspace.EndInvoke($script:spinnerToken) } catch { }
        $script:spinnerRunspace.Dispose()
    }
    $script:spinnerRunspace = $null
    $script:spinnerEstado = $null
    $script:spinnerToken = $null
    $script:spinnerActivo = $false
}

function Write-ResultadoPdf {
    param(
        [Parameter(Mandatory = $true)][string]$Texto,
        [Parameter(Mandatory = $true)][string]$Color
    )

    if ($script:spinnerActivo -and $null -ne $script:spinnerEstado) {
        $script:spinnerEstado.Pausa = $true
        [Console]::Write("`r" + (' ' * 30) + "`r")
    }
    Write-Host $Texto -ForegroundColor $Color
    if ($script:spinnerActivo -and $null -ne $script:spinnerEstado) {
        $script:spinnerEstado.Pausa = $false
    }
}

try {
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  CONVERSION BAJO DEMANDA DE DOCUMENTACION A PDF' -ForegroundColor Cyan
    Write-Host ('  ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw ('No se encontro el archivo de configuracion: ' + $ConfigPath)
    }
    $configuracion = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $rutaPandoc = [string]$configuracion.herramientas.pandocPath
    $rutaTypst = [string]$configuracion.herramientas.typstPath
    if ([string]::IsNullOrWhiteSpace($rutaPandoc)) {
        throw 'La configuracion no define herramientas.pandocPath.'
    }
    if ([string]::IsNullOrWhiteSpace($rutaTypst)) {
        throw 'La configuracion no define herramientas.typstPath.'
    }
    if (-not [System.IO.Path]::IsPathRooted($rutaPandoc)) { $rutaPandoc = Join-Path $RaizRepositorio $rutaPandoc }
    if (-not [System.IO.Path]::IsPathRooted($rutaTypst)) { $rutaTypst = Join-Path $RaizRepositorio $rutaTypst }
    if (-not (Test-Path -LiteralPath $rutaPandoc -PathType Leaf)) { throw ('No se encontro Pandoc en: ' + $rutaPandoc) }
    if (-not (Test-Path -LiteralPath $rutaTypst -PathType Leaf)) { throw ('No se encontro Typst en: ' + $rutaTypst) }

    . (Join-Path $PSScriptRoot 'RenderizarMarkdownTypstPdf.ps1')
    $directorioServicios = Join-Path $RaizRepositorio 'documentacion\servicios'
    $documentos = @(Get-ChildItem -LiteralPath $directorioServicios -Filter '*.md' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($documentos.Count -eq 0) {
        throw ('No se encontraron documentos Markdown en: ' + $directorioServicios)
    }
    Write-Host ('  Markdown disponibles: ' + $documentos.Count) -ForegroundColor DarkGray

    if ($Todos) {
        Write-Host '  Modo automatico: convertir TODOS los Markdown disponibles.' -ForegroundColor DarkGray
        $seleccionados = @($documentos)
    } else {
        $seleccionados = @(Seleccionar-Documentos -Documentos $documentos)
    }
    if ($seleccionados.Count -eq 0) {
        Write-Host '  Conversion cancelada. No se genero ningun PDF.' -ForegroundColor Yellow
        exit 0
    }

    $ok = 0
    $errores = 0
    $duraciones = New-Object System.Collections.Generic.List[double]

    if (-not [Console]::IsOutputRedirected) {
        $script:spinnerActivo = $true
        $script:spinnerEstado = @{ Activo = $true; Pausa = $false }
        $script:spinnerRunspace = Iniciar-Spinner -Estado $script:spinnerEstado -Secuencias @('|', '/', '-', '\')
        $script:spinnerToken = $script:spinnerRunspace.BeginInvoke()
    }

    foreach ($documento in $seleccionados) {
        $nombre = [System.IO.Path]::GetFileNameWithoutExtension($documento.Name)
        $rutaPdf = Join-Path $directorioServicios ($nombre + '.pdf')
        try {
            $markdown = [System.IO.File]::ReadAllText($documento.FullName)
            $cronometro = [Diagnostics.Stopwatch]::StartNew()
            Convertir-MarkdownAPdf -Markdown $markdown -RutaSalida $rutaPdf -RutaPandoc $rutaPandoc -RutaTypst $rutaTypst | Out-Null
            $cronometro.Stop()
            $segundos = [math]::Round($cronometro.Elapsed.TotalSeconds, 2)
            $duraciones.Add($segundos)
            Write-ResultadoPdf -Texto ('  [OK] ' + $nombre + '.pdf (' + $segundos + ' s)') -Color 'Green'
            $ok++
        } catch {
            Write-ResultadoPdf -Texto ('  [ERROR] ' + $documento.Name + ': ' + $_.Exception.Message) -Color 'Red'
            $errores++
        }
    }

    Detener-Spinner

    Write-Host ''
    $promedio = 0
    if ($duraciones.Count -gt 0) {
        $promedio = [math]::Round((($duraciones | Measure-Object -Average).Average), 2)
    }
    Write-Host ('Completado: ' + $ok + ' PDF(s) generados, ' + $errores + ' error(es).') -ForegroundColor Cyan
    if ($duraciones.Count -gt 0) {
        Write-Host ('Tiempo promedio por PDF: ' + $promedio + ' s.') -ForegroundColor DarkGray
    }
    if ($errores -gt 0) { exit 1 }
    exit 0
} catch {
    Write-Host ''
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    Detener-Spinner
    Write-Host ''
    Write-Host ('Fin: ' + ((Get-Date) - $StartTime).ToString('mm\:ss')) -ForegroundColor DarkGray
}
