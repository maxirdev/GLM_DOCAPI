# HistorialVersiones.ps1
# Genera y persiste el historial legible de versiones por servicio (estado/historialVersiones.md).
# El historial es un artefacto derivado best-effort: el control de versiones sigue siendo la
# fuente de verdad y este modulo nunca altera los contratos de SPEC 16.

$ErrorActionPreference = 'Stop'

function Normalizar-Celda {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$Valor = ''
    )

    $celda = [string]$Valor
    $celda = $celda.Trim()
    if ($celda.Length -ge 2 -and $celda.StartsWith('`') -and $celda.EndsWith('`')) {
        $celda = $celda.Substring(1, $celda.Length - 2)
    }
    return $celda.Trim()
}

function Convertir-DocumentoEnSecciones {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$Texto = ''
    )

    $secciones = @{}
    $estado = @{
        Seccion = ''
        Contexto = ''
        TablaCabecera = $null
        TablaFilas = $null
        TablasSeccion = New-Object System.Collections.Generic.List[object]
    }

    function Cerrar-TablaEnCurso {
        [CmdletBinding()]
        param()

        if ($null -ne $estado.TablaCabecera -and $estado.TablaFilas.Count -gt 0) {
            $estado.TablasSeccion.Add([pscustomobject]@{
                Contexto = $estado.Contexto
                Cabecera = $estado.TablaCabecera
                Filas = $estado.TablaFilas.ToArray()
            })
        }
        $estado.TablaCabecera = $null
        $estado.TablaFilas = $null
    }

    foreach ($linea in ($Texto -split "`n")) {
        $linea = $linea.TrimEnd("`r").Trim()
        if ($linea -match '^## (.+)$') {
            Cerrar-TablaEnCurso
            if ($estado.Seccion -and $estado.TablasSeccion.Count -gt 0) {
                $secciones[$estado.Seccion] = $estado.TablasSeccion.ToArray()
            }
            $estado.TablasSeccion = New-Object System.Collections.Generic.List[object]
            $estado.Seccion = $matches[1].Trim()
            $estado.Contexto = ''
            continue
        }
        if ($linea -match '^### (.+)$') {
            Cerrar-TablaEnCurso
            $estado.Contexto = $matches[1].Trim()
            continue
        }
        if ($linea -match '^\*\*(.+)\*\*$') {
            Cerrar-TablaEnCurso
            $estado.Contexto = $matches[1].Trim()
            continue
        }
        if ($linea -notmatch '\|') {
            Cerrar-TablaEnCurso
            continue
        }
        if ($linea -match '^\s*\|?(:?-+:?\|)+\s*$') {
            continue
        }

        $celdas = @($linea -split '\|')
        while ($celdas.Count -gt 0 -and [string]::IsNullOrWhiteSpace([string]$celdas[0])) {
            $celdas = $celdas[1..($celdas.Count - 1)]
        }
        while ($celdas.Count -gt 0 -and [string]::IsNullOrWhiteSpace([string]$celdas[$celdas.Count - 1])) {
            $celdas = $celdas[0..($celdas.Count - 2)]
        }
        if ($celdas.Count -eq 0) { continue }
        $celdas = @($celdas | ForEach-Object { $_.Trim() })

        if ($null -eq $estado.TablaCabecera) {
            $estado.TablaCabecera = $celdas
            $estado.TablaFilas = New-Object System.Collections.Generic.List[object]
            continue
        }

        $celdasObjeto = @{}
        for ($indiceColumna = 0; $indiceColumna -lt $estado.TablaCabecera.Count; $indiceColumna++) {
            $valorColumna = if ($indiceColumna -lt $celdas.Count) { $celdas[$indiceColumna] } else { '' }
            $celdasObjeto[[string]$estado.TablaCabecera[$indiceColumna]] = $valorColumna
        }
        $claveFila = Obtener-ClaveFilaTabla -Cabecera $estado.TablaCabecera -Celdas $celdasObjeto
        if ($null -eq $claveFila) { continue }
        $estado.TablaFilas.Add([pscustomobject]@{
            Clave = $claveFila
            Celdas = $celdasObjeto
        })
    }
    Cerrar-TablaEnCurso
    if ($estado.Seccion -and $estado.TablasSeccion.Count -gt 0) {
        $secciones[$estado.Seccion] = $estado.TablasSeccion.ToArray()
    }
    return $secciones
}

function Obtener-ClaveFilaTabla {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Cabecera,
        [Parameter(Mandatory = $true)]$Celdas
    )

    foreach ($columna in @('Código HTTP', 'Parámetro o campo', 'Parámetro', 'Campo', 'Dato')) {
        if (@($Cabecera) -contains $columna) {
            return Normalizar-Celda -Valor ([string]$Celdas[$columna])
        }
    }
    if (@($Cabecera).Count -gt 0) {
        return Normalizar-Celda -Valor ([string]$Celdas[@($Cabecera)[0]])
    }
    return $null
}

function Obtener-TerminoFila {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Seccion,
        [Parameter(Mandatory = $true)]$Cabecera
    )

    if (@($Cabecera) -contains 'Código HTTP') { return 'código' }
    if ($Seccion -eq 'Definición del servicio') { return 'dato' }
    if ($Seccion -eq 'Entrada' -and (@($Cabecera) -contains 'Parámetro' -or @($Cabecera) -contains 'Parámetro o campo')) {
        return 'parámetro'
    }
    return 'campo'
}

function Obtener-ValorColumnaFila {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Tabla,
        [Parameter(Mandatory = $true)]$Fila
    )

    foreach ($columna in @('Valor', 'Respuesta o mensaje')) {
        if (@($Tabla.Cabecera) -contains $columna) { return [string]$Fila.Celdas[$columna] }
    }
    return ''
}

function Comparar-EstructuraSeccion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$TablasAnteriores,
        [Parameter(Mandatory = $true)]$TablasNuevas
    )

    $contextosAnteriores = @($TablasAnteriores | ForEach-Object { $_.Contexto } | Sort-Object -Unique)
    $contextosNuevos = @($TablasNuevas | ForEach-Object { $_.Contexto } | Sort-Object -Unique)
    if ($contextosAnteriores.Count -ne $contextosNuevos.Count) { return $false }
    foreach ($contexto in $contextosAnteriores) {
        if ($contextosNuevos -notcontains $contexto) { return $false }
        $tablaAnterior = @($TablasAnteriores | Where-Object { $_.Contexto -eq $contexto })[0]
        $tablaNueva = @($TablasNuevas | Where-Object { $_.Contexto -eq $contexto })[0]
        if (($tablaAnterior.Cabecera -join '|') -ne ($tablaNueva.Cabecera -join '|')) { return $false }
    }
    return $true
}

function Construir-FraseFilaAgregada {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Seccion,
        [Parameter(Mandatory = $true)]$Tabla,
        [Parameter(Mandatory = $true)]$Fila
    )

    $termino = Obtener-TerminoFila -Seccion $Seccion -Cabecera $Tabla.Cabecera
    $clave = $Fila.Clave
    if ($termino -eq 'código') {
        return ('se agregó el código ' + $clave + ' con su mensaje.')
    }
    if ($termino -eq 'dato') {
        return ('se agregó el dato `' + $clave + '` con valor ' + (Obtener-ValorColumnaFila -Tabla $Tabla -Fila $Fila) + '.')
    }
    $texto = 'se agregó el ' + $termino + ' `' + $clave + '`'
    $detalles = @()
    if ($Tabla.Cabecera -contains 'Tipo' -and [string]$Fila.Celdas['Tipo']) { $detalles += [string]$Fila.Celdas['Tipo'] }
    if ($Tabla.Cabecera -contains 'Obligatorio' -and [string]$Fila.Celdas['Obligatorio']) { $detalles += [string]$Fila.Celdas['Obligatorio'] }
    if ($detalles.Count -gt 0) { $texto += ' (' + ($detalles -join ', ') + ')' }
    return ($texto + '.')
}

function Construir-FraseFilaEliminada {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Seccion,
        [Parameter(Mandatory = $true)]$Tabla,
        [Parameter(Mandatory = $true)]$Fila
    )

    $termino = Obtener-TerminoFila -Seccion $Seccion -Cabecera $Tabla.Cabecera
    $clave = $Fila.Clave
    if ($termino -eq 'código') {
        return ('se eliminó el código ' + $clave + '.')
    }
    if ($termino -eq 'dato') {
        return ('se eliminó el dato `' + $clave + '`.')
    }
    return ('se eliminó el ' + $termino + ' `' + $clave + '`.')
}

function Comparar-CeldasFila {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Seccion,
        [Parameter(Mandatory = $true)]$Tabla,
        [Parameter(Mandatory = $true)]$FilaAnterior,
        [Parameter(Mandatory = $true)]$FilaNueva
    )

    $frases = New-Object System.Collections.Generic.List[string]
    $termino = Obtener-TerminoFila -Seccion $Seccion -Cabecera $Tabla.Cabecera
    $clave = $FilaNueva.Clave

    foreach ($columna in @('Tipo', 'Obligatorio', 'Descripción')) {
        if ($Tabla.Cabecera -notcontains $columna) { continue }
        $valorAnterior = Normalizar-Celda -Valor ([string]$FilaAnterior.Celdas[$columna])
        $valorNuevo = Normalizar-Celda -Valor ([string]$FilaNueva.Celdas[$columna])
        if ($valorAnterior -eq $valorNuevo) { continue }
        switch ($columna) {
            'Tipo' {
                $frases.Add('el ' + $termino + ' `' + $clave + '` cambió Tipo de ' + $valorAnterior + ' a ' + $valorNuevo + '.')
            }
            'Obligatorio' {
                $frases.Add('el ' + $termino + ' `' + $clave + '` pasó Obligatorio de ' + $valorAnterior + ' a ' + $valorNuevo + '.')
            }
            'Descripción' {
                $frases.Add('el ' + $termino + ' `' + $clave + '` cambió su descripción.')
            }
        }
    }

    if ($Tabla.Cabecera -contains 'Respuesta o mensaje') {
        $valorAnterior = Normalizar-Celda -Valor ([string]$FilaAnterior.Celdas['Respuesta o mensaje'])
        $valorNuevo = Normalizar-Celda -Valor ([string]$FilaNueva.Celdas['Respuesta o mensaje'])
        if ($valorAnterior -ne $valorNuevo) {
            $frases.Add('el código ' + $clave + ' cambió su mensaje.')
        }
    }

    if ($Tabla.Cabecera -contains 'Valor') {
        $valorAnterior = Normalizar-Celda -Valor ([string]$FilaAnterior.Celdas['Valor'])
        $valorNuevo = Normalizar-Celda -Valor ([string]$FilaNueva.Celdas['Valor'])
        if ($valorAnterior -ne $valorNuevo) {
            $frases.Add('el dato `' + $clave + '` cambió de ' + $valorAnterior + ' a ' + $valorNuevo + '.')
        }
    }

    return $frases.ToArray()
}

function Describir-CambiosDocumento {
    <#
    .SYNOPSIS
    Compara las tablas de dos versiones del Markdown de un servicio y produce frases legibles.
    .DESCRIPTION
    Compara por seccion (Definicion, Entrada, Salida exitosa y Errores especificos) los
    parametros/campos agregados o eliminados, los cambios de Tipo, de Obligatorio y de
    descripcion, y los codigos HTTP agregados o eliminados. La fila Version de la tabla
    Definicion se ignora siempre. Si una seccion no es comparable, queda el fallback de
    conteos (Se modifico la seccion N (+a/-b)).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$DocumentoAnterior,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$DocumentoNuevo
    )

    $seccionesAnteriores = Convertir-DocumentoEnSecciones -Texto $DocumentoAnterior
    $seccionesNuevas = Convertir-DocumentoEnSecciones -Texto $DocumentoNuevo
    $frases = New-Object System.Collections.Generic.List[string]
    $seccionesComparadas = @('Definición del servicio', 'Entrada', 'Salida exitosa', 'Errores específicos')

    foreach ($seccion in $seccionesComparadas) {
        $tablasAnteriores = if ($seccionesAnteriores.ContainsKey($seccion)) { @($seccionesAnteriores[$seccion]) } else { @() }
        $tablasNuevas = if ($seccionesNuevas.ContainsKey($seccion)) { @($seccionesNuevas[$seccion]) } else { @() }
        if ($tablasAnteriores.Count -eq 0 -and $tablasNuevas.Count -eq 0) { continue }

        if (-not (Comparar-EstructuraSeccion -TablasAnteriores $tablasAnteriores -TablasNuevas $tablasNuevas)) {
            $conteoNuevo = 0
            foreach ($tabla in $tablasNuevas) { $conteoNuevo += @($tabla.Filas).Count }
            $conteoAnterior = 0
            foreach ($tabla in $tablasAnteriores) { $conteoAnterior += @($tabla.Filas).Count }
            $frases.Add('Se modificó la sección ' + $seccion + ' (+' + $conteoNuevo + '/−' + $conteoAnterior + ').')
            continue
        }

        $filasAnterioresPorContexto = @{}
        foreach ($tabla in $tablasAnteriores) {
            $porClave = @{}
            foreach ($fila in @($tabla.Filas)) { $porClave[$fila.Clave] = $fila }
            $filasAnterioresPorContexto[$tabla.Contexto] = [pscustomobject]@{ Cabecera = $tabla.Cabecera; PorClave = $porClave }
        }
        $filasNuevasPorContexto = @{}
        foreach ($tabla in $tablasNuevas) {
            $porClave = @{}
            foreach ($fila in @($tabla.Filas)) { $porClave[$fila.Clave] = $fila }
            $filasNuevasPorContexto[$tabla.Contexto] = [pscustomobject]@{ Cabecera = $tabla.Cabecera; PorClave = $porClave }
        }

        foreach ($contexto in $filasNuevasPorContexto.Keys) {
            $tablaNueva = $filasNuevasPorContexto[$contexto]
            $tablaAnterior = if ($filasAnterioresPorContexto.ContainsKey($contexto)) { $filasAnterioresPorContexto[$contexto] } else { $null }

            foreach ($clave in @($tablaNueva.PorClave.Keys | Where-Object { $_ -ne 'Versión' })) {
                if (-not $tablaAnterior -or -not $tablaAnterior.PorClave.ContainsKey($clave)) {
                    $frase = Construir-FraseFilaAgregada -Seccion $seccion -Tabla ([pscustomobject]@{ Cabecera = $tablaNueva.Cabecera }) -Fila $tablaNueva.PorClave[$clave]
                    $frases.Add($seccion + ': ' + $frase)
                }
            }
            if ($tablaAnterior) {
                foreach ($clave in @($tablaAnterior.PorClave.Keys | Where-Object { $_ -ne 'Versión' })) {
                    if (-not $tablaNueva.PorClave.ContainsKey($clave)) {
                        $frase = Construir-FraseFilaEliminada -Seccion $seccion -Tabla ([pscustomobject]@{ Cabecera = $tablaAnterior.Cabecera }) -Fila $tablaAnterior.PorClave[$clave]
                        $frases.Add($seccion + ': ' + $frase)
                    }
                }
            }
            if ($tablaAnterior) {
                foreach ($clave in @($tablaAnterior.PorClave.Keys | Where-Object { $_ -ne 'Versión' })) {
                    if (-not $tablaNueva.PorClave.ContainsKey($clave)) { continue }
                    foreach ($frase in @(Comparar-CeldasFila -Seccion $seccion -Tabla ([pscustomobject]@{ Cabecera = $tablaNueva.Cabecera }) -FilaAnterior $tablaAnterior.PorClave[$clave] -FilaNueva $tablaNueva.PorClave[$clave])) {
                        $frases.Add($seccion + ': ' + $frase)
                    }
                }
            }
        }
    }
    return $frases.ToArray()
}

function Resolver-ObjetosHistorial {
    <#
    .SYNOPSIS
    Convierte las claves de ObjetosModificados (Tipo:identificador) en nombres legibles.
    .DESCRIPTION
    Resuelve cada clave contra ObjetosEfectivos para obtener el fullyQualifiedName y
    formatear <Tipo> `<FQN>`. Un objeto eliminado del XPZ (no presente en
    ObjetosEfectivos) queda como la clave literal `Tipo:guid`.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$Claves,
        [Parameter(Mandatory = $false)]$ObjetosEfectivos = @{}
    )

    $resultados = New-Object System.Collections.Generic.List[string]
    foreach ($clave in $Claves) {
        $objeto = $null
        if ($ObjetosEfectivos -is [System.Collections.IDictionary] -and $ObjetosEfectivos.ContainsKey($clave)) {
            $objeto = $ObjetosEfectivos[$clave]
        }
        $tipo = ''
        $indiceSeparador = $clave.IndexOf(':')
        if ($indiceSeparador -gt 0) {
            $tipo = $clave.Substring(0, $indiceSeparador)
        }
        $fqn = ''
        if ($objeto) {
            $propiedad = $objeto.PSObject.Properties['FullyQualifiedName']
            if ($propiedad) { $fqn = [string]$propiedad.Value }
        }
        if ($tipo -and $fqn) {
            $resultados.Add($tipo + ' `' + $fqn + '`')
        } else {
            $resultados.Add($clave)
        }
    }
    return $resultados.ToArray()
}

function Redactar-EntradaHistorial {
    <#
    .SYNOPSIS
    Redacta el bloque Markdown de una entrada de version del historial.
    .DESCRIPTION
    Produce la linea `- **1.<n>** (YYYY-MM-DD) — <texto>` con los objetos modificados y las
    frases de cambio indentadas. Sin cambios, una version 1.0 se describe como
    `Versión inicial.` y un bump sin cambios descriptibles como `Se modificó el documento.`.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$Fecha,
        [Parameter(Mandatory = $false)][string[]]$Objetos = @(),
        [Parameter(Mandatory = $false)][string[]]$Cambios = @()
    )

    $lineas = New-Object System.Collections.Generic.List[string]
    $cabeceraEntrada = '- **' + $Version + '** (' + $Fecha + ')'
    if (@($Cambios).Count -eq 0) {
        if ($Version -eq '1.0') {
            $lineas.Add($cabeceraEntrada + ' — Versión inicial.')
        } else {
            $lineas.Add($cabeceraEntrada + ' — Se modificó el documento.')
        }
        return ($lineas -join "`n")
    }
    if (@($Objetos).Count -gt 0) {
        $lineas.Add($cabeceraEntrada + ' — Objetos: ' + (@($Objetos) -join ', ') + ' modificado.')
    } else {
        $lineas.Add($cabeceraEntrada + ' — Se modificó el documento.')
    }
    foreach ($cambio in @($Cambios)) {
        if ($cambio) { $lineas.Add('  - ' + $cambio) }
    }
    return ($lineas -join "`n")
}

function Obtener-EncabezadoHistorial {
    <#
    .SYNOPSIS
    Lee el encabezado (LineageId y Creado) de un historial existente.
    .DESCRIPTION
    Devuelve $null si el archivo no existe o no tiene encabezado. El lineageId del
    encabezado es la identidad del historial y dispara el reemplazo ante un cambio de KB.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaHistorial
    )

    if (-not (Test-Path -LiteralPath $RutaHistorial -PathType Leaf)) { return $null }
    $contenido = [System.IO.File]::ReadAllText($RutaHistorial, (New-Object System.Text.UTF8Encoding($false)))
    $lineageId = ''
    $creado = ''
    foreach ($linea in ($contenido -split "`n")) {
        $linea = $linea.Trim()
        if ($linea -match '^LineageId:\s*(.+)$') { $lineageId = $matches[1].Trim(); continue }
        if ($linea -match '^Creado:\s*(.+)$') { $creado = $matches[1].Trim() }
        if ($lineageId -and $creado) { break }
    }
    if (-not $lineageId -and -not $creado) { return $null }
    return [pscustomobject]@{ LineageId = $lineageId; Creado = $creado }
}

function Escribir-HistorialVersionado {
    <#
    .SYNOPSIS
    Escribe el historial de versiones en modo append o reemplazo.
    .DESCRIPTION
    El archivo se escribe UTF-8 sin BOM con finales LF. En modo append conserva el contenido
    previo byte a byte y agrega una entrada por servicio: si el bloque `## <FQN>` ya existe, la
    nueva entrada se inserta al final del bloque (las versiones de un servicio se acumulan bajo
    un unico encabezado); si no existe, el bloque se crea al final del archivo. Crea el
    encabezado si no existe. En modo reemplazo reescribe el archivo con un encabezado nuevo y
    las entradas del lote. Sin entradas en modo append, el archivo no se toca.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RutaHistorial,
        [Parameter(Mandatory = $true)][string]$LineageId,
        [Parameter(Mandatory = $true)][string]$Creado,
        [Parameter(Mandatory = $true)][object[]]$Entradas,
        [Parameter(Mandatory = $false)][switch]$Reemplazar
    )

    $directorio = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($RutaHistorial))
    if (-not (Test-Path -LiteralPath $directorio -PathType Container)) {
        New-Item -ItemType Directory -Path $directorio -Force | Out-Null
    }

    $entradas = @($Entradas)
    $encabezado = ('# Historial de versiones por servicio' + "`n" +
        'LineageId: ' + $LineageId + "`n" +
        'Creado: ' + $Creado + "`n")
    $existeArchivo = Test-Path -LiteralPath $RutaHistorial -PathType Leaf

    if (-not $Reemplazar -and $entradas.Count -eq 0 -and $existeArchivo) { return $RutaHistorial }

    if ($Reemplazar -or -not $existeArchivo) {
        $contenidoBloques = New-Object System.Text.StringBuilder
        foreach ($entrada in $entradas) {
            [void]$contenidoBloques.Append("`n## " + $entrada.FullyQualifiedName + "`n`n" + $entrada.Texto + "`n")
        }
        $contenidoFinal = $encabezado + $contenidoBloques.ToString()
    } else {
        $contenido = [System.IO.File]::ReadAllText($RutaHistorial, (New-Object System.Text.UTF8Encoding($false)))
        $tieneEncabezado = $contenido -match '(?m)^LineageId:\s*\S'
        $lineas = New-Object System.Collections.Generic.List[string]
        foreach ($lineaExistente in ($contenido -split "`n")) { $lineas.Add($lineaExistente) }

        foreach ($entrada in $entradas) {
            $indiceEncabezado = -1
            for ($indiceLinea = 0; $indiceLinea -lt $lineas.Count; $indiceLinea++) {
                if ($lineas[$indiceLinea].Trim() -eq ('## ' + $entrada.FullyQualifiedName)) {
                    $indiceEncabezado = $indiceLinea
                    break
                }
            }
            $lineasEntrada = New-Object System.Collections.Generic.List[string]
            foreach ($lineaEntrada in @($entrada.Texto -split "`n")) { $lineasEntrada.Add($lineaEntrada) }
            if ($indiceEncabezado -ge 0) {
                $indiceFinBloque = $indiceEncabezado + 1
                while ($indiceFinBloque -lt $lineas.Count -and $lineas[$indiceFinBloque].Trim() -notmatch '^## ') {
                    $indiceFinBloque++
                }
                $indiceUltimaLinea = $indiceFinBloque - 1
                while ($indiceUltimaLinea -gt $indiceEncabezado -and [string]::IsNullOrWhiteSpace([string]$lineas[$indiceUltimaLinea])) {
                    $indiceUltimaLinea--
                }
                $indiceInsercion = $indiceUltimaLinea + 1
                $lineas.InsertRange($indiceInsercion, $lineasEntrada)
            } else {
                if ($lineas.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$lineas[$lineas.Count - 1])) {
                    $lineas.Add('')
                }
                $lineas.Add('## ' + $entrada.FullyQualifiedName)
                $lineas.Add('')
                $lineas.AddRange($lineasEntrada)
            }
        }

        $contenidoFinal = $lineas -join "`n"
        if (-not $tieneEncabezado) {
            $contenidoFinal = $encabezado + "`n" + $contenidoFinal
        }
    }

    [System.IO.File]::WriteAllText($RutaHistorial, $contenidoFinal, (New-Object System.Text.UTF8Encoding($false)))
    return $RutaHistorial
}
