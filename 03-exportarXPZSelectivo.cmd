@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
set "SCRIPT_DIR=%~dp0"

set "NO_PAUSE=0"
set "REPORTE_PATH="

:parse_arguments
if "%~1"=="" goto arguments_parsed
if /I "%~1"=="--no-pause" (
    set "NO_PAUSE=1"
    shift
    goto parse_arguments
)
if /I "%~1"=="--reporte" (
    if "%~2"=="" (
        set "ERROR_MESSAGE=--reporte requiere la ruta de un archivo JSON."
        goto fail
    )
    set "REPORTE_PATH=%~2"
    shift
    shift
    goto parse_arguments
)
set "ERROR_MESSAGE=Argumento no reconocido: %~1"
goto fail

:arguments_parsed
set "GX_PROGRAM_DIR=C:\Program Files (x86)\GeneXus\GeneXus18"
set "KB_PATH=C:\KBs\SEGUROS_COMERCIAL_TRUNK"
set "MSBUILD=%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe"
set "PROJECT_FILE=%SCRIPT_DIR%binary\ExportarXPZSelectivo.msbuild"
set "SELECTIVE_SCRIPT=%SCRIPT_DIR%binary\ExportarXPZSelectivo.ps1"
set "LOG_DIR=%SCRIPT_DIR%Logs"

if not exist "%LOG_DIR%\" (
    mkdir "%LOG_DIR%"
    if errorlevel 1 (
        set "ERROR_MESSAGE=No se pudo crear la carpeta de logs %LOG_DIR%."
        goto fail
    )
)

if not exist "%GX_PROGRAM_DIR%\Genexus.Tasks.targets" (
    set "ERROR_MESSAGE=No se encontro Genexus.Tasks.targets en %GX_PROGRAM_DIR%."
    goto fail
)

if not exist "%KB_PATH%\" (
    set "ERROR_MESSAGE=No se encontro la Knowledge Base en %KB_PATH%."
    goto fail
)

if not exist "%MSBUILD%" (
    set "ERROR_MESSAGE=No se encontro MSBuild de 32 bits en %MSBUILD%."
    goto fail
)

if not exist "%PROJECT_FILE%" (
    set "ERROR_MESSAGE=No se encontro %PROJECT_FILE%."
    goto fail
)

if not exist "%SELECTIVE_SCRIPT%" (
    set "ERROR_MESSAGE=No se encontro %SELECTIVE_SCRIPT%."
    goto fail
)

if defined REPORTE_PATH if not exist "%REPORTE_PATH%" (
    set "ERROR_MESSAGE=No se encontro el reporte indicado: %REPORTE_PATH%."
    goto fail
)

tasklist /FI "IMAGENAME eq GeneXus.exe" /NH 2>nul | find /I "GeneXus.exe" >nul
if not errorlevel 1 (
    set "ERROR_MESSAGE=GeneXus esta abierto. Cierre GeneXus antes de exportar la KB."
    set "EXIT_CODE=2"
    goto fail
)

echo ==============================================================
echo   EXPORTACION SELECTIVA DE OBJETOS APIGLM
echo ==============================================================
echo KB:       %KB_PATH%
if defined REPORTE_PATH echo Reporte:  %REPORTE_PATH%
echo.

if defined REPORTE_PATH (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SELECTIVE_SCRIPT%" ^
        -MsbuildPath "%MSBUILD%" ^
        -ProjectFile "%PROJECT_FILE%" ^
        -GxProgramDir "%GX_PROGRAM_DIR%" ^
        -KbPath "%KB_PATH%" ^
        -ReportePath "%REPORTE_PATH%"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SELECTIVE_SCRIPT%" ^
        -MsbuildPath "%MSBUILD%" ^
        -ProjectFile "%PROJECT_FILE%" ^
        -GxProgramDir "%GX_PROGRAM_DIR%" ^
        -KbPath "%KB_PATH%"
)

if errorlevel 1 (
    set "ERROR_MESSAGE=GeneXus no pudo generar el XPZ complementario. Revise el log indicado por el script."
    goto fail
)

set "EXIT_CODE=0"
goto finish

:fail
if not defined EXIT_CODE set "EXIT_CODE=1"
echo.
echo ERROR: %ERROR_MESSAGE%

:finish
if "%NO_PAUSE%"=="0" (
    echo.
    pause
)
exit /b %EXIT_CODE%
