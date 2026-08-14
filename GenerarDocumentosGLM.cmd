@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
title Gestion de Documentos APIGLM

set "SCRIPT_DIR=%~dp0"
set "REPOSITORY_PATH=%SCRIPT_DIR:~0,-1%"
set "ULTIMO_ESTADO=INICIALIZADO"
set "ULTIMO_CODIGO=0"
set "PREFLIGHT_CODIGO=1"
set "SIN_XPZ=0"
set "CONFIGURACION_INVALIDA=0"
set "XPZ_ACTIVO="
set "XPZ_ACTIVO_NOMBRE=ninguno"

call :preflight

:menu
cls
call :mostrar_encabezado
echo.
if "%CONFIGURACION_INVALIDA%"=="1" goto menu_solo_salida
call :obtener_xpz_principales
if "%XPZ_CANTIDAD%"=="0" goto menu_sin_xpz

echo  1. Exportar segun configuracion (APIGLM/KB) y completar el XPZ
echo  2. Seleccionar XPZ principal
echo  3. Generar PDF con el XPZ seleccionado
echo  4. Salir
echo.

choice /C 1234 /N /M "Seleccione una opcion [1-4]: "
if errorlevel 4 goto salir
if errorlevel 3 goto pdf
if errorlevel 2 goto seleccion_xpz
goto exportacion

:menu_sin_xpz
echo  1. Exportar APIGLMMain
echo  2. Salir
echo.
choice /C 12 /N /M "Seleccione una opcion [1-2]: "
if errorlevel 2 goto salir
goto exportacion

:menu_solo_salida
echo  1. Salir
echo.
choice /C 1 /N /M "Presione 1 para salir: "
goto salir

:exportacion
call :ejecutar_exportacion
call :esperar_retorno
goto menu

:pdf
call :ejecutar_pdf
call :esperar_retorno
goto menu

:seleccion_xpz
set "ULTIMO_ESTADO=OPERANDO"
set "ULTIMO_CODIGO=1"
call :seleccionar_xpz_activo
if errorlevel 1 (
    set "ULTIMO_ESTADO=ERROR"
    set "ULTIMO_CODIGO=1"
) else (
    set "ULTIMO_ESTADO=COMPLETADO"
    set "ULTIMO_CODIGO=0"
)
call :esperar_retorno
goto menu

:operacion_pendiente
set "ULTIMO_ESTADO=PENDIENTE"
set "ULTIMO_CODIGO=0"
echo.
echo ==============================================================
echo   %~1
echo ==============================================================
echo.
echo Esta operacion sera integrada en los siguientes pasos.
exit /b 0

:ejecutar_exportacion
set "ULTIMO_ESTADO=OPERANDO"
set "ULTIMO_CODIGO=1"
echo.
echo ==============================================================
echo   EXPORTAR SEGUN CONFIGURACION Y COMPLETAR EL XPZ
echo ==============================================================
echo.
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%binary\EjecutarExportacionGLM.ps1" -Repositorio "%REPOSITORY_PATH%"
if errorlevel 3 (
    set "ULTIMO_ESTADO=ABORTADO"
    set "ULTIMO_CODIGO=0"
    exit /b 0
)
if errorlevel 1 (
    set "ULTIMO_ESTADO=ERROR"
    set "ULTIMO_CODIGO=1"
    exit /b 1
)
set "ULTIMO_ESTADO=COMPLETADO"
set "ULTIMO_CODIGO=0"
set "XPZ_ACTIVO_ESTABLECIDO="
call :inicializar_xpz_activo
exit /b 0

:ejecutar_pdf
set "ULTIMO_ESTADO=OPERANDO"
set "ULTIMO_CODIGO=1"
if "%XPZ_ACTIVO%"=="" (
    echo ERROR: No hay un XPZ activo para la generacion de PDF.
    set "ULTIMO_ESTADO=ERROR"
    set "ULTIMO_CODIGO=1"
    exit /b 1
)
echo.
echo ==============================================================
echo   GENERAR PDF DESDE EL XPZ ACTIVO
echo ==============================================================
echo.
echo XPZ activo: %XPZ_ACTIVO%
echo Regenerando el inventario para el XPZ activo...
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%documentacion\Endpoints\binary\GenerarListaEndpoints.ps1" -ConfigPath "%SCRIPT_DIR%configuracion.json" -XpzPath "%XPZ_ACTIVO%"
if errorlevel 1 (
    set "ULTIMO_ESTADO=ERROR"
    set "ULTIMO_CODIGO=1"
    exit /b 1
)

echo.
echo Validando la completitud del XPZ y completando los elementos necesarios...
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%binary\CompletarXPZActivoGLM.ps1" -Repositorio "%REPOSITORY_PATH%" -XpzActivo "%XPZ_ACTIVO%"
if errorlevel 3 (
    set "ULTIMO_ESTADO=ABORTADO"
    set "ULTIMO_CODIGO=0"
    exit /b 0
)
if errorlevel 1 (
    set "ULTIMO_ESTADO=ERROR"
    set "ULTIMO_CODIGO=1"
    exit /b 1
)

%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%binary\GenerarDocumento.ps1" -ConfigPath "%SCRIPT_DIR%configuracion.json" -XpzPath "%XPZ_ACTIVO%" -Todos
set "GENERACION_MD_CODIGO=%ERRORLEVEL%"

echo.
echo ==============================================================
echo   CONVERTIR MARKDOWN GENERADOS A PDF
echo ==============================================================
echo.
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%binary\GenerarPdfServicios.ps1" -ConfigPath "%SCRIPT_DIR%configuracion.json" -Todos
if errorlevel 1 (
    set "ULTIMO_ESTADO=ERROR"
    set "ULTIMO_CODIGO=1"
    exit /b 1
)

echo.
echo Eliminando los archivos Markdown generados...
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%SCRIPT_DIR%documentacion\servicios' -Filter '*.md' -File -ErrorAction SilentlyContinue | Remove-Item -Force"
call :mostrar_resumen_pdf
if "%GENERACION_MD_CODIGO%"=="1" (
    set "ULTIMO_ESTADO=ERROR"
    set "ULTIMO_CODIGO=1"
    exit /b 1
)
set "ULTIMO_ESTADO=COMPLETADO"
set "ULTIMO_CODIGO=0"
exit /b 0

:mostrar_resumen_pdf
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%binary\ResumirOperacionPdf.ps1" -Repositorio "%REPOSITORY_PATH%"
exit /b 0

:esperar_retorno
echo.
pause
call :preflight
exit /b 0

:seleccionar_xpz_activo
call :obtener_xpz_principales
if "%XPZ_CANTIDAD%"=="0" (
    echo ERROR: No se encontraron XPZ principales en "%SCRIPT_DIR%xpz".
    exit /b 1
)

setlocal EnableDelayedExpansion
set "XPZ_OPCIONES="
set "XPZ_POSICION=0"
echo.
echo XPZ principales disponibles:
for /L %%N in (1,1,%XPZ_CANTIDAD%) do (
    call :marca_opcion_xpz %%N
    for %%F in ("!XPZ_ARCHIVO_%%N!") do set "XPZ_NOMBRE_OPCION=%%~nxF"
    set "XPZ_TAG="
    if "!XPZ_ULTIMO_%%N!"=="1" set "XPZ_TAG=[ÚLTIMO]"
    echo   !XPZ_MARCA!. !XPZ_NOMBRE_OPCION!  ^|  !XPZ_FECHA_%%N!  !XPZ_TAG!
    set /a XPZ_POSICION+=1
    set "XPZ_MAPA_!XPZ_POSICION!=%%N"
    set "XPZ_OPCIONES=!XPZ_OPCIONES!!XPZ_MARCA!"
)
echo.
choice /C !XPZ_OPCIONES! /N /M "Seleccione el XPZ principal: "
for %%I in (!ERRORLEVEL!) do set "XPZ_INDICE=!XPZ_MAPA_%%I!"
for %%I in (!XPZ_INDICE!) do set "XPZ_ELEGIDO=!XPZ_ARCHIVO_%%I!"
for %%F in ("!XPZ_ELEGIDO!") do (
    endlocal
    set "XPZ_ACTIVO=%%~fF"
    set "XPZ_ACTIVO_NOMBRE=%%~nxF"
    set "XPZ_ACTIVO_ESTABLECIDO=1"
    echo.
    echo XPZ activo de la sesion: %%~nxF
    echo ADVERTENCIA: El packagename de configuracion.json no se modifica al cambiar de XPZ.
    echo El endpoint publicado podria no corresponder al XPZ seleccionado.
    exit /b 0
)

:obtener_xpz_principales
set "XPZ_CANTIDAD=0"
for /f "usebackq delims=" %%L in (`%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%binary\ListarXPZPrincipales.ps1" -DirectorioXpz "%SCRIPT_DIR%xpz"`) do (
    call :registrar_linea_xpz "%%L"
)
exit /b 0

:registrar_linea_xpz
set "XPZ_LINEA=%~1"
set "XPZ_CAMPO1="
set "XPZ_CAMPO2="
set "XPZ_CAMPO3="
for /f "tokens=1-3 delims=|" %%A in ("%XPZ_LINEA%") do (
    set "XPZ_CAMPO1=%%A"
    set "XPZ_CAMPO2=%%B"
    set "XPZ_CAMPO3=%%C"
)
set /a XPZ_CANTIDAD+=1
set "XPZ_ARCHIVO_%XPZ_CANTIDAD%=%SCRIPT_DIR%xpz\%XPZ_CAMPO1%"
set "XPZ_FECHA_%XPZ_CANTIDAD%=%XPZ_CAMPO2%"
set "XPZ_ULTIMO_%XPZ_CANTIDAD%=%XPZ_CAMPO3%"
exit /b 0

:obtener_xpz_configurado
set "XPZ_CONFIGURADO="
for /f "usebackq delims=" %%C in (`%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command "$c = Get-Content -LiteralPath '%SCRIPT_DIR%configuracion.json' -Raw | ConvertFrom-Json; $ruta = [string]$c.xpz; if (-not [System.String]::IsNullOrWhiteSpace($ruta)) { if (-not [System.IO.Path]::IsPathRooted($ruta)) { $ruta = Join-Path '%SCRIPT_DIR%' $ruta }; Write-Output ([System.IO.Path]::GetFullPath($ruta)) }"`) do set "XPZ_CONFIGURADO=%%C"
exit /b 0

:inicializar_xpz_activo
if defined XPZ_ACTIVO_ESTABLECIDO exit /b 0
call :obtener_xpz_configurado
call :obtener_xpz_principales
if exist "%XPZ_CONFIGURADO%" (
    set "XPZ_ACTIVO=%XPZ_CONFIGURADO%"
    for %%F in ("%XPZ_CONFIGURADO%") do set "XPZ_ACTIVO_NOMBRE=%%~nxF"
) else (
    if "%XPZ_CANTIDAD%"=="0" (
        set "XPZ_ACTIVO="
        set "XPZ_ACTIVO_NOMBRE=ninguno"
    ) else (
        set "XPZ_ACTIVO=%XPZ_ARCHIVO_1%"
        for %%F in ("%XPZ_ARCHIVO_1%") do set "XPZ_ACTIVO_NOMBRE=%%~nxF"
    )
)
set "XPZ_ACTIVO_ESTABLECIDO=1"
exit /b 0

:marca_opcion_xpz
set "XPZ_MARCA=%~1"
if "%~1"=="10" set "XPZ_MARCA=A"
if "%~1"=="11" set "XPZ_MARCA=B"
if "%~1"=="12" set "XPZ_MARCA=C"
if "%~1"=="13" set "XPZ_MARCA=D"
if "%~1"=="14" set "XPZ_MARCA=E"
if "%~1"=="15" set "XPZ_MARCA=F"
if "%~1"=="16" set "XPZ_MARCA=G"
if "%~1"=="17" set "XPZ_MARCA=H"
if "%~1"=="18" set "XPZ_MARCA=I"
if "%~1"=="19" set "XPZ_MARCA=J"
if "%~1"=="20" set "XPZ_MARCA=K"
if "%~1"=="21" set "XPZ_MARCA=L"
if "%~1"=="22" set "XPZ_MARCA=M"
if "%~1"=="23" set "XPZ_MARCA=N"
if "%~1"=="24" set "XPZ_MARCA=O"
if "%~1"=="25" set "XPZ_MARCA=P"
if "%~1"=="26" set "XPZ_MARCA=Q"
exit /b 0

:preflight
set "SIN_XPZ=0"
set "CONFIGURACION_INVALIDA=0"
echo.
echo ==============================================================
echo   VALIDACION INICIAL
echo ==============================================================
echo.
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%binary\ValidarConfiguracionGLM.ps1" -Repositorio "%REPOSITORY_PATH%"
set "PREFLIGHT_CODIGO=%ERRORLEVEL%"
if "%PREFLIGHT_CODIGO%"=="1" set "CONFIGURACION_INVALIDA=1"
if "%PREFLIGHT_CODIGO%"=="2" set "SIN_XPZ=1"
if not "%CONFIGURACION_INVALIDA%"=="1" if not defined XPZ_ACTIVO_ESTABLECIDO call :inicializar_xpz_activo
exit /b 0

:mostrar_encabezado
echo ==============================================================
echo   GESTION DE DOCUMENTOS APIGLM
echo   %DATE% %TIME%
echo ==============================================================
echo Estado de sesion: %ULTIMO_ESTADO%
echo XPZ activo: %XPZ_ACTIVO_NOMBRE%
exit /b 0

:salir
echo.
echo Saliendo de la gestion de documentos APIGLM.
exit /b %ULTIMO_CODIGO%
