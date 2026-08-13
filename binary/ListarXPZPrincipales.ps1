# Lista los XPZ principales de un directorio, ordenados del mas viejo al mas nuevo.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DirectorioXpz,
    [Parameter(Mandatory = $false)][string]$XpzConfigurado = ''
)

$ErrorActionPreference = 'Stop'

function Obtener-FechaXpz {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$Archivo)

    $nombreSinExtension = [System.IO.Path]::GetFileNameWithoutExtension($Archivo.Name)
    $coincidenciaMarca = [regex]::Match($nombreSinExtension, '_(\d{8})_(\d{9})$')
    if ($coincidenciaMarca.Success) {
        $marca = $coincidenciaMarca.Groups[1].Value + '_' + $coincidenciaMarca.Groups[2].Value
        try {
            return [datetime]::ParseExact($marca, 'yyyyMMdd_HHmmssfff', [System.Globalization.CultureInfo]::InvariantCulture)
        } catch {
        }
    }
    return $Archivo.LastWriteTime
}

if (-not (Test-Path -LiteralPath $DirectorioXpz -PathType Container)) {
    Write-Error ("No existe el directorio de XPZ: " + $DirectorioXpz)
    exit 1
}

$archivosXpz = @(Get-ChildItem -LiteralPath $DirectorioXpz -Filter '*.xpz' -File -ErrorAction SilentlyContinue | Sort-Object Name)
$entradas = New-Object System.Collections.Generic.List[object]
$indice = 0

foreach ($archivo in $archivosXpz) {
    $nombreSinExtension = [System.IO.Path]::GetFileNameWithoutExtension($archivo.Name)
    $coincidenciaComplemento = [regex]::Match($nombreSinExtension, '^(.*)_\d+$')
    if ($coincidenciaComplemento.Success) {
        $rutaPrincipalAsociada = Join-Path $DirectorioXpz ($coincidenciaComplemento.Groups[1].Value + '.xpz')
        if (Test-Path -LiteralPath $rutaPrincipalAsociada -PathType Leaf) { continue }
    }

    $indice++
    $entradas.Add([pscustomobject]@{
        Nombre = $archivo.Name
        Ruta = $archivo.FullName
        Fecha = Obtener-FechaXpz -Archivo $archivo
        Orden = $indice
    })
}

if (-not [string]::IsNullOrWhiteSpace($XpzConfigurado) -and -not (Test-Path -LiteralPath $XpzConfigurado -PathType Leaf)) {
    Write-Warning ('El XPZ configurado no existe: ' + $XpzConfigurado)
}

$ordenadas = @($entradas | Sort-Object Fecha, Orden)
$total = $ordenadas.Count
for ($posicion = 0; $posicion -lt $total; $posicion++) {
    $entrada = $ordenadas[$posicion]
    $esUltimo = 0
    if ($posicion -eq ($total - 1)) { $esUltimo = 1 }
    Write-Output (($entrada.Nombre) + '|' + $entrada.Fecha.ToString('dd-MM-yyyy HH:mm') + '|' + $esUltimo)
}

exit 0
