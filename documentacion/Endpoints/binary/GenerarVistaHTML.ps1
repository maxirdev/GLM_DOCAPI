[CmdletBinding()]
param(
    [string]$InputDirectory,
    [string]$OutputPath,
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
if (-not $InputDirectory) { $InputDirectory = Join-Path $PSScriptRoot '..\assets' }
$JsonPath = Join-Path $InputDirectory 'endpoints.json'
$HtmlPath = Join-Path (Join-Path $PSScriptRoot '..\web') 'APIServicios.html'
if ($OutputPath) { $HtmlPath = $OutputPath }
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '..\..\..\configuracion.json' }
$Cliente = ''
$StartTime = Get-Date
$RaizRepositorio = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$DirectorioLogs = Join-Path $PSScriptRoot '..\..\..\Logs'
$faseActual = 'inicio'
. (Join-Path $PSScriptRoot '..\..\..\binary\DiagnosticoIA.ps1')

if (-not [Console]::IsOutputRedirected) {
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
}

function Write-Step {
    param(
        [Parameter(Mandatory = $true)][int]$Number,
        [string]$Text = ''
    )
    Write-Host ''
    Write-Host ("[ {0}/3 ] {1}" -f $Number, $Text) -ForegroundColor Cyan
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
    Write-Host '  GENERADOR DE VISOR DE ENDPOINTS APIGLM' -ForegroundColor Cyan
    Write-Host ("  " + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan

    $faseActual = 'carga-configuracion'
    . (Join-Path $PSScriptRoot '..\..\..\binary\CargarConfiguracion.ps1')
    try {
        $configuracion = Cargar-Configuracion -ConfigPath $ConfigPath
        $Cliente = $configuracion.Cliente
    } catch { }

    $faseActual = 'lectura-inventario'
    Write-Step 1 'Leyendo endpoints.json...'
    if (-not (Test-Path -LiteralPath $JsonPath)) {
        throw ("No se encontró el inventario en: " + $JsonPath + ". Ejecute primero GenerarListaEndpoints.ps1 o generelo desde el XPZ.")
    }
    $jsonText = [System.IO.File]::ReadAllText($JsonPath, (New-Object System.Text.UTF8Encoding($false)))
    $jsonObj = $jsonText | ConvertFrom-Json
    $jsonObj.meta | Add-Member -MemberType NoteProperty -Name 'cliente' -Value $Cliente -Force
    $jsonModified = $jsonObj | ConvertTo-Json -Depth 5
    $jsonModified = $jsonModified -replace "`r`n", "`n"
    Write-Host ("  Leídos " + $jsonText.Length + " caracteres desde " + [System.IO.Path]::GetFileName($JsonPath)) -ForegroundColor DarkGray

    $faseActual = 'generacion-html'
    Write-Step 2 'Incrustando los datos en APIServicios.html...'
    $embedded = $jsonModified -replace '</script', '<\/script'
    $sb = New-Object System.Text.StringBuilder
    Add-Line $sb '<!DOCTYPE html>'
    Add-Line $sb '<html lang="es">'
    Add-Line $sb '<head>'
    Add-Line $sb '  <meta charset="UTF-8">'
    Add-Line $sb '  <meta name="viewport" content="width=device-width, initial-scale=1.0">'
    $titulo = 'Listado de Servicios API'
    if ($Cliente) { $titulo = $titulo + ' - ' + $Cliente }
    Add-Line $sb ('  <title>' + $titulo + '</title>')
    Add-Line $sb '  <link rel="stylesheet" href="style.css">'
    Add-Line $sb '</head>'
    Add-Line $sb '<body>'
    Add-Line $sb '  <header class="encabezado">'
    Add-Line $sb '    <div class="encabezado-texto">'
    Add-Line $sb ('      <h1>' + $titulo + '</h1>')
    Add-Line $sb '      <p class="metadatos" id="metadatos"></p>'
    Add-Line $sb '    </div>'
    Add-Line $sb '    <button type="button" id="alternar-tema" aria-label="Alternar tema">Modo oscuro</button>'
    Add-Line $sb '  </header>'
    Add-Line $sb '  <main>'
    Add-Line $sb '    <div class="barra-filtro">'
    Add-Line $sb '      <input type="search" id="filtro" placeholder="Filtrar por nombre o descripción..." autocomplete="off">'
    Add-Line $sb '    </div>'
    Add-Line $sb '    <table>'
    Add-Line $sb '      <thead>'
    Add-Line $sb '        <tr>'
    Add-Line $sb '          <th scope="col" class="izquierda">Nombre</th>'
    Add-Line $sb '          <th scope="col" class="izquierda">Descripción</th>'
    Add-Line $sb '        </tr>'
    Add-Line $sb '      </thead>'
    Add-Line $sb '      <tbody id="cuerpo-tabla"></tbody>'
    Add-Line $sb '    </table>'
    Add-Line $sb '    <p id="sin-resultados" hidden>Sin resultados para el filtro aplicado.</p>'
    Add-Line $sb '  </main>'
    Add-Line $sb '  <script type="application/json" id="endpoints-data">'
    Add-Line $sb $embedded
    Add-Line $sb '  </script>'
    Add-Line $sb '  <script src="app.js"></script>'
    Add-Line $sb '</body>'
    Add-Line $sb '</html>'
    $html = $sb.ToString()
    $htmlDirectory = [System.IO.Path]::GetDirectoryName($HtmlPath)
    if (-not (Test-Path -LiteralPath $htmlDirectory)) {
        New-Item -ItemType Directory -Path $htmlDirectory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($HtmlPath, $html, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("  Escritos " + $html.Length + " caracteres en " + $HtmlPath) -ForegroundColor DarkGray

    $faseActual = 'verificacion-html'
    Write-Step 3 'Verificación final'
    if (-not (Test-Path -LiteralPath $HtmlPath)) {
        throw ("No se pudo escribir el archivo: " + $HtmlPath)
    }
    $bytes = [System.IO.File]::ReadAllBytes($HtmlPath)
    $tieneBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    Write-Host ''
    Write-Host ("Archivo generado: " + $HtmlPath) -ForegroundColor Cyan
    Write-Host ("  Tamaño: " + $bytes.Length + " bytes") -ForegroundColor White
    Write-Host ("  UTF-8 sin BOM: " + $(if ($tieneBom) { 'NO (contiene BOM)' } else { 'SI' })) -ForegroundColor White
    Write-Host ''
    Write-Host ('Abra APIServicios.html con doble clic para visualizar el listado.') -ForegroundColor DarkGray
} catch {
    $diagnosticoIA = New-DiagnosticoIAError -ErrorRecord $_ -Componente 'GenerarVistaHTML' -Fase $faseActual -RaizRepositorio $RaizRepositorio
    Write-Host ''
    Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
    try {
        $rutaDiagnosticoIA = Write-DiagnosticoIA -Errores @($diagnosticoIA) -Pipeline 'visor-endpoints' -Inicio $StartTime -DirectorioLogs $DirectorioLogs -RaizRepositorio $RaizRepositorio
        Write-Host ("Diagnostico IA: " + $rutaDiagnosticoIA) -ForegroundColor DarkGray
    } catch {
        Write-Host ("No se pudo escribir el diagnostico IA: " + $_.Exception.Message) -ForegroundColor DarkGray
    }
    exit 1
} finally {
    Write-Host ''
    Write-Host ("Fin: " + ((Get-Date) - $StartTime).ToString('mm\:ss')) -ForegroundColor DarkGray
}
