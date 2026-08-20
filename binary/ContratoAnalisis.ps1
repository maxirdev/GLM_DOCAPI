# Contrato temporal para transportar el resultado tecnico del analisis.
# Se carga despues de GLMUtilidades.ps1 y no consulta el XPZ ni la KB.

$ErrorActionPreference = 'Stop'

function Obtener-PropiedadContratoAnalisis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Objeto,
        [Parameter(Mandatory = $true)][string]$Nombre
    )

    if ($null -eq $Objeto -or -not $Objeto.PSObject.Properties[$Nombre]) {
        return $null
    }
    return $Objeto.PSObject.Properties[$Nombre].Value
}

function Test-PropiedadContratoAnalisis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Objeto,
        [Parameter(Mandatory = $true)][string]$Nombre
    )

    return ($null -ne $Objeto -and $null -ne $Objeto.PSObject.Properties[$Nombre])
}

function Test-ValorColeccionContratoAnalisis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$Valor
    )

    if ($null -eq $Valor -or $Valor -is [string] -or $Valor -is [System.Collections.IDictionary]) {
        return $false
    }
    return ($Valor -is [System.Collections.IEnumerable])
}

function Convertir-ValorContratoAnalisisInterno {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$Valor,
        [Parameter(Mandatory = $true)]$ContextoNormalizacion
    )

    $ObjetosVisitados = $ContextoNormalizacion.ObjetosVisitados

    if ($null -eq $Valor) { return $null }
    if ($Valor -is [string] -or $Valor -is [char] -or $Valor -is [bool]) { return $Valor }
    if ($Valor -is [byte] -or $Valor -is [int16] -or $Valor -is [int32] -or $Valor -is [int64] -or
        $Valor -is [uint16] -or $Valor -is [uint32] -or $Valor -is [uint64] -or
        $Valor -is [single] -or $Valor -is [double] -or $Valor -is [decimal]) { return $Valor }
    if ($Valor -is [datetime]) { return $Valor.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($Valor -is [timespan]) { return $Valor.ToString('c', [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($Valor -is [guid]) { return $Valor.ToString() }
    if ($Valor -is [uri]) { return $Valor.AbsoluteUri }
    if ($Valor -is [System.Enum]) { return $Valor.ToString() }

    if ($Valor -is [System.Xml.XmlNode] -or $Valor -is [System.Xml.XmlDocument] -or
        $Valor -is [System.IO.Stream] -or $Valor -is [System.Management.Automation.ErrorRecord] -or
        $Valor -is [System.Management.Automation.InvocationInfo]) {
        throw ('El contrato de analisis no admite el tipo no serializable: ' + $Valor.GetType().FullName)
    }

    $identidadObjeto = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Valor)
    if (-not $ObjetosVisitados.Add($identidadObjeto)) {
        throw 'El contrato de analisis contiene una referencia circular.'
    }

    try {
        if ($Valor -is [System.Collections.IDictionary]) {
            $resultadoDiccionario = [ordered]@{}
            foreach ($clave in @($Valor.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
                if (-not $Valor.Contains($clave)) {
                    throw ('El diccionario del contrato no contiene la clave esperada: ' + $clave)
                }
                $resultadoDiccionario[$clave] = Convertir-ValorContratoAnalisisInterno -Valor $Valor[$clave] -ContextoNormalizacion $ContextoNormalizacion
            }
            return ,[pscustomobject]$resultadoDiccionario
        }

        if (Test-ValorColeccionContratoAnalisis -Valor $Valor) {
            $resultadoColeccion = New-Object System.Collections.Generic.List[object]
            foreach ($elemento in $Valor) {
                [void]$resultadoColeccion.Add((Convertir-ValorContratoAnalisisInterno -Valor $elemento -ContextoNormalizacion $ContextoNormalizacion))
            }
            return ,@($resultadoColeccion.ToArray())
        }

        $propiedades = @($Valor.PSObject.Properties | Where-Object { $_.MemberType -in @('NoteProperty', 'Property', 'AliasProperty', 'ScriptProperty') })
        if ($propiedades.Count -eq 0) {
            if ($Valor -is [pscustomobject]) { return ,[pscustomobject]@{} }
            throw ('El contrato de analisis no admite el tipo de objeto: ' + $Valor.GetType().FullName)
        }

        $resultadoObjeto = [ordered]@{}
        foreach ($propiedad in @($propiedades | Sort-Object Name)) {
            $resultadoObjeto[$propiedad.Name] = Convertir-ValorContratoAnalisisInterno -Valor $propiedad.Value -ContextoNormalizacion $ContextoNormalizacion
        }
        return ,[pscustomobject]$resultadoObjeto
    } finally {
        [void]$ObjetosVisitados.Remove($identidadObjeto)
    }
}

function Convertir-ValorContratoAnalisis {
    <# Convierte valores PowerShell a una forma JSON estable y sin objetos vivos. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$Valor
    )

    $objetosVisitados = [System.Collections.Generic.HashSet[int]]::new()
    $contextoNormalizacion = [pscustomobject]@{ ObjetosVisitados = $objetosVisitados }
    return Convertir-ValorContratoAnalisisInterno -Valor $Valor -ContextoNormalizacion $contextoNormalizacion
}

function Convertir-ColeccionContratoAnalisis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$Valor
    )

    if ($null -eq $Valor) { return ,@() }
    $elementosNormalizados = New-Object System.Collections.Generic.List[object]
    foreach ($elemento in @($Valor)) {
        [void]$elementosNormalizados.Add((Convertir-ValorContratoAnalisis -Valor $elemento))
    }
    return ,@($elementosNormalizados.ToArray())
}

function Obtener-DocumentacionContratoAnalisis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Documentacion
    )

    if ($null -eq $Documentacion) {
        throw 'El analisis OK requiere documentacion tecnica.'
    }

    $documentacionNormalizada = [ordered]@{
        FqWrapper = [string](Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'FqWrapper')
        ProgramaPrincipal = [string](Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'ProgramaPrincipal')
        MetodoHttp = [string](Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'MetodoHttp')
        EndpointPublicado = [string](Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'EndpointPublicado')
        NombreFuncional = [string](Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'NombreFuncional')
        Descripcion = [string](Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'Descripcion')
        Entrada = Convertir-ColeccionContratoAnalisis -Valor (Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'Entrada')
        Estructuras = Convertir-ColeccionContratoAnalisis -Valor (Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'Estructuras')
        EstructurasSalida = Convertir-ColeccionContratoAnalisis -Valor (Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'EstructurasSalida')
        ReferenciasRecursivasSalida = Convertir-ColeccionContratoAnalisis -Valor (Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'ReferenciasRecursivasSalida')
        SalidaColeccion = [bool](Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'SalidaColeccion')
        Salida = Convertir-ColeccionContratoAnalisis -Valor (Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'Salida')
        SalidaVacia = [bool](Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'SalidaVacia')
        TipoColeccionPrimitiva = Convertir-ValorContratoAnalisis -Valor (Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'TipoColeccionPrimitiva')
        TipoContenidoSalida = Convertir-ValorContratoAnalisis -Valor (Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'TipoContenidoSalida')
        MensajesSalida = Convertir-ColeccionContratoAnalisis -Valor (Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'MensajesSalida')
        NotasSalida = Convertir-ColeccionContratoAnalisis -Valor (Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'NotasSalida')
        Errores = Convertir-ColeccionContratoAnalisis -Valor (Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'Errores')
        Pendientes = Convertir-ColeccionContratoAnalisis -Valor (Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'Pendientes')
        FaltantesEntrada = Convertir-ColeccionContratoAnalisis -Valor (Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'FaltantesEntrada')
        CiclosEntrada = Convertir-ColeccionContratoAnalisis -Valor (Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'CiclosEntrada')
        TrazaEvidencia = $(if ($null -eq (Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'TrazaEvidencia')) { [ordered]@{} } else { Convertir-ValorContratoAnalisis -Valor (Obtener-PropiedadContratoAnalisis -Objeto $Documentacion -Nombre 'TrazaEvidencia') })
    }
    return ,[pscustomobject]$documentacionNormalizada
}

function New-RegistroContratoAnalisis {
    <# Construye un registro tecnico normalizado a partir de un analisis. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FullyQualifiedName,
        [Parameter(Mandatory = $false)][AllowNull()]$Documentacion,
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$WrapperGuid = '',
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$DocumentHash = '',
        [Parameter(Mandatory = $false)][string[]]$Dependencias = @(),
        [Parameter(Mandatory = $false)][ValidateSet('OK', 'ERROR', 'OMITIDO')][string]$EstadoAnalisis = 'OK',
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$MensajeError = ''
    )

    if ([string]::IsNullOrWhiteSpace($FullyQualifiedName)) { throw 'El registro de analisis requiere fullyQualifiedName.' }
    if ($EstadoAnalisis -eq 'OK' -and $null -eq $Documentacion) { throw ('El registro OK no tiene documentacion: ' + $FullyQualifiedName) }

    $registro = [ordered]@{
        fullyQualifiedName = $FullyQualifiedName
        wrapperGuid = $WrapperGuid
        estadoAnalisis = $EstadoAnalisis
        documentHash = $DocumentHash
        dependencias = Convertir-ColeccionContratoAnalisis -Valor $Dependencias
        documentacion = $(if ($null -eq $Documentacion) { $null } else { Obtener-DocumentacionContratoAnalisis -Documentacion $Documentacion })
    }
    if ($MensajeError) { $registro['mensajeError'] = $MensajeError }
    return ,[pscustomobject]$registro
}

function New-EnvelopeContratoAnalisis {
    <# Construye el envelope ANALISIS_PREVIO asociado a una ejecucion. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$EjecucionId,
        [Parameter(Mandatory = $true)][string]$ContextId,
        [Parameter(Mandatory = $true)][string]$Xpz,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$SourceFingerprint,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ProfileFingerprint,
        [Parameter(Mandatory = $true)][string[]]$FullyQualifiedNames,
        [Parameter(Mandatory = $true)]$Servicios
    )

    $nombres = @($FullyQualifiedNames | ForEach-Object { [string]$_ })
    $registros = @($Servicios | ForEach-Object { Convertir-ValorContratoAnalisis -Valor $_ })
    return ,[pscustomobject]([ordered]@{
        fase = 'ANALISIS_PREVIO'
        ejecucionId = $EjecucionId
        contextId = $ContextId
        xpz = [System.IO.Path]::GetFullPath($Xpz)
        sourceFingerprint = $SourceFingerprint
        profileFingerprint = $ProfileFingerprint
        fullyQualifiedNames = @($nombres)
        contratoAnalisis = [pscustomobject]([ordered]@{
            schemaVersion = 1
            servicios = @($registros)
        })
    })
}

function Convertir-EnvelopeContratoAnalisisAJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Envelope
    )

    $normalizado = Convertir-ValorContratoAnalisis -Valor $Envelope
    return (Normalizar-SaltosLineaLf -Texto ($normalizado | ConvertTo-Json -Depth 100))
}

function Convertir-JsonAEnvelopeContratoAnalisis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Json
    )

    if ([string]::IsNullOrWhiteSpace($Json)) { throw 'El envelope de analisis esta vacio.' }
    try {
        return ($Json | ConvertFrom-Json)
    } catch {
        throw ('El envelope de analisis no contiene JSON valido: ' + $_.Exception.Message)
    }
}

function Validar-RegistroContratoAnalisis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Registro
    )

    foreach ($propiedad in @('fullyQualifiedName', 'wrapperGuid', 'estadoAnalisis', 'documentHash', 'dependencias', 'documentacion')) {
        if (-not (Test-PropiedadContratoAnalisis -Objeto $Registro -Nombre $propiedad)) {
            throw ('El registro de analisis no contiene la propiedad obligatoria: ' + $propiedad)
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$Registro.fullyQualifiedName)) { throw 'El registro de analisis contiene fullyQualifiedName vacio.' }
    if ($Registro.wrapperGuid -isnot [string]) { throw ('wrapperGuid debe ser string en ' + $Registro.fullyQualifiedName) }
    if ($Registro.estadoAnalisis -isnot [string] -or [string]$Registro.estadoAnalisis -notin @('OK', 'ERROR', 'OMITIDO')) {
        throw ('estadoAnalisis invalido en ' + $Registro.fullyQualifiedName)
    }
    if ($Registro.documentHash -isnot [string] -or ([string]$Registro.documentHash -and [string]$Registro.documentHash -notmatch '^[0-9a-fA-F]{64}$')) {
        throw ('documentHash invalido en ' + $Registro.fullyQualifiedName)
    }
    if (-not (Test-ValorColeccionContratoAnalisis -Valor $Registro.dependencias)) {
        throw ('dependencias debe ser un array en ' + $Registro.fullyQualifiedName)
    }
    if ($Registro.estadoAnalisis -eq 'OK' -and $null -eq $Registro.documentacion) {
        throw ('El registro OK no contiene documentacion: ' + $Registro.fullyQualifiedName)
    }
    if ($null -eq $Registro.documentacion) { return $true }

    $documentacion = $Registro.documentacion
    $propiedadesDocumentacion = @('FqWrapper', 'ProgramaPrincipal', 'MetodoHttp', 'EndpointPublicado', 'NombreFuncional', 'Descripcion', 'Entrada', 'Estructuras', 'EstructurasSalida', 'ReferenciasRecursivasSalida', 'SalidaColeccion', 'Salida', 'SalidaVacia', 'TipoColeccionPrimitiva', 'TipoContenidoSalida', 'MensajesSalida', 'NotasSalida', 'Errores', 'Pendientes', 'FaltantesEntrada', 'CiclosEntrada', 'TrazaEvidencia')
    foreach ($propiedadDocumentacion in $propiedadesDocumentacion) {
        if (-not (Test-PropiedadContratoAnalisis -Objeto $documentacion -Nombre $propiedadDocumentacion)) {
            throw ('La documentacion del registro no contiene la propiedad obligatoria: ' + $propiedadDocumentacion)
        }
    }
    foreach ($propiedadTexto in @('FqWrapper', 'ProgramaPrincipal', 'MetodoHttp', 'EndpointPublicado', 'NombreFuncional', 'Descripcion')) {
        if ($documentacion.$propiedadTexto -isnot [string]) { throw ($propiedadTexto + ' debe ser string en ' + $Registro.fullyQualifiedName) }
    }
    foreach ($propiedadLista in @('Entrada', 'Estructuras', 'EstructurasSalida', 'ReferenciasRecursivasSalida', 'Salida', 'MensajesSalida', 'NotasSalida', 'Errores', 'Pendientes', 'FaltantesEntrada', 'CiclosEntrada')) {
        if (-not (Test-ValorColeccionContratoAnalisis -Valor $documentacion.$propiedadLista)) {
            throw ($propiedadLista + ' debe ser un array en ' + $Registro.fullyQualifiedName)
        }
    }
    if ($documentacion.SalidaColeccion -isnot [bool] -or $documentacion.SalidaVacia -isnot [bool]) {
        throw ('Los indicadores de salida deben ser booleanos en ' + $Registro.fullyQualifiedName)
    }
    if ($documentacion.TrazaEvidencia -is [string] -or (Test-ValorColeccionContratoAnalisis -Valor $documentacion.TrazaEvidencia)) {
        throw ('TrazaEvidencia debe ser un objeto en ' + $Registro.fullyQualifiedName)
    }
    return $true
}

function Comparar-ConjuntoContratoAnalisis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$Esperados,
        [Parameter(Mandatory = $true)][string[]]$Recibidos
    )

    $esperadosUnicos = @($Esperados | Sort-Object -Unique)
    $recibidosUnicos = @($Recibidos | Sort-Object -Unique)
    if ($esperadosUnicos.Count -ne $Esperados.Count -or $recibidosUnicos.Count -ne $Recibidos.Count) { return $false }
    if ($esperadosUnicos.Count -ne $recibidosUnicos.Count) { return $false }
    for ($indice = 0; $indice -lt $esperadosUnicos.Count; $indice++) {
        if ($esperadosUnicos[$indice] -cne $recibidosUnicos[$indice]) { return $false }
    }
    return $true
}

function Validar-EnvelopeContratoAnalisis {
    <# Valida identidad, conjunto y registros. Lanza ante cualquier incompatibilidad. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Envelope,
        [Parameter(Mandatory = $true)][string]$EjecucionId,
        [Parameter(Mandatory = $true)][string]$ContextId,
        [Parameter(Mandatory = $true)][string]$Xpz,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$SourceFingerprint,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ProfileFingerprint,
        [Parameter(Mandatory = $true)][string[]]$FullyQualifiedNames,
        [Parameter(Mandatory = $false)][switch]$PermitirRegistrosInvalidos
    )

    foreach ($propiedadEnvelope in @('fase', 'ejecucionId', 'contextId', 'xpz', 'sourceFingerprint', 'profileFingerprint', 'fullyQualifiedNames', 'contratoAnalisis')) {
        if (-not (Test-PropiedadContratoAnalisis -Objeto $Envelope -Nombre $propiedadEnvelope)) {
            throw ('El envelope de analisis no contiene la propiedad obligatoria: ' + $propiedadEnvelope)
        }
    }
    if ([string]$Envelope.fase -cne 'ANALISIS_PREVIO') { throw 'El review no esta en fase ANALISIS_PREVIO.' }
    if ([string]$Envelope.ejecucionId -cne $EjecucionId) { throw 'El envelope de analisis pertenece a otra ejecucion.' }
    if ([string]$Envelope.contextId -cne $ContextId) { throw 'El envelope de analisis pertenece a otro contexto.' }
    try {
        $xpzEnvelope = [System.IO.Path]::GetFullPath([string]$Envelope.xpz)
        $xpzEsperado = [System.IO.Path]::GetFullPath($Xpz)
    } catch {
        throw ('La ruta XPZ del envelope no es valida: ' + $_.Exception.Message)
    }
    if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($xpzEnvelope, $xpzEsperado)) { throw 'El envelope de analisis pertenece a otro XPZ.' }
    if ([string]$Envelope.sourceFingerprint -cne $SourceFingerprint) { throw 'El sourceFingerprint del envelope no coincide.' }
    if ([string]$Envelope.profileFingerprint -cne $ProfileFingerprint) { throw 'El profileFingerprint del envelope no coincide.' }
    if (-not (Comparar-ConjuntoContratoAnalisis -Esperados @($FullyQualifiedNames) -Recibidos @($Envelope.fullyQualifiedNames))) {
        throw 'El conjunto de fullyQualifiedNames del envelope no coincide.'
    }

    $contrato = $Envelope.contratoAnalisis
    if (-not (Test-PropiedadContratoAnalisis -Objeto $contrato -Nombre 'schemaVersion') -or [int]$contrato.schemaVersion -ne 1) {
        throw 'La version del contrato de analisis no es compatible.'
    }
    if (-not (Test-PropiedadContratoAnalisis -Objeto $contrato -Nombre 'servicios') -or -not (Test-ValorColeccionContratoAnalisis -Valor $contrato.servicios)) {
        throw 'El contrato de analisis no contiene un array de servicios.'
    }
    $nombresRegistros = New-Object System.Collections.Generic.List[string]
    foreach ($registro in @($contrato.servicios)) {
        if (-not $PermitirRegistrosInvalidos) {
            Validar-RegistroContratoAnalisis -Registro $registro | Out-Null
        } elseif (-not (Test-PropiedadContratoAnalisis -Objeto $registro -Nombre 'fullyQualifiedName') -or [string]::IsNullOrWhiteSpace([string]$registro.fullyQualifiedName)) {
            throw 'Un registro invalido no contiene fullyQualifiedName; no puede asociarse de forma segura al conjunto esperado.'
        }
        [void]$nombresRegistros.Add([string]$registro.fullyQualifiedName)
    }
    if (-not (Comparar-ConjuntoContratoAnalisis -Esperados @($FullyQualifiedNames) -Recibidos @($nombresRegistros.ToArray()))) {
        throw 'El contrato de analisis no contiene exactamente un registro por servicio esperado.'
    }
    return $true
}


