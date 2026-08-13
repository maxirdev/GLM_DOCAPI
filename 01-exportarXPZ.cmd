@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

set "NO_PAUSE=0"
if /I "%~1"=="--no-pause" set "NO_PAUSE=1"

set "GX_PROGRAM_DIR=C:\Program Files (x86)\GeneXus\GeneXus18"
set "KB_PATH=C:\KBs\SEGUROS_COMERCIAL_TRUNK"
set "MSBUILD=%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe"
set "PROJECT_FILE=%~dp0binary\ExportarXPZ.msbuild"
set "PROGRESS_SCRIPT=%~dp0binary\ExportarXPZProgreso.ps1"
set "OUTPUT_DIR=%~dp0xpz"
set "LOG_DIR=%~dp0Logs"

if not exist "%OUTPUT_DIR%\" (
    mkdir "%OUTPUT_DIR%"
    if errorlevel 1 (
        set "ERROR_MESSAGE=No se pudo crear la carpeta de salida %OUTPUT_DIR%."
        goto :fail
    )
)

if not exist "%LOG_DIR%\" (
    mkdir "%LOG_DIR%"
    if errorlevel 1 (
        set "ERROR_MESSAGE=No se pudo crear la carpeta de logs %LOG_DIR%."
        goto :fail
    )
)

if not exist "%GX_PROGRAM_DIR%\Genexus.Tasks.targets" (
    set "ERROR_MESSAGE=No se encontro Genexus.Tasks.targets en %GX_PROGRAM_DIR%."
    goto :fail
)

if not exist "%KB_PATH%\SEGUROS_COMERCIAL_TRUNK.gxw" (
    set "ERROR_MESSAGE=No se encontro la Knowledge Base en %KB_PATH%."
    goto :fail
)

if not exist "%MSBUILD%" (
    set "ERROR_MESSAGE=No se encontro MSBuild de 32 bits en %MSBUILD%."
    goto :fail
)

if not exist "%PROJECT_FILE%" (
    set "ERROR_MESSAGE=No se encontro %PROJECT_FILE%."
    goto :fail
)

if not exist "%PROGRESS_SCRIPT%" (
    set "ERROR_MESSAGE=No se encontro %PROGRESS_SCRIPT%."
    goto :fail
)

tasklist /FI "IMAGENAME eq GeneXus.exe" /NH 2>nul | find /I "GeneXus.exe" >nul
if not errorlevel 1 (
    set "ERROR_MESSAGE=GeneXus esta abierto. Cierre GeneXus antes de exportar la KB."
    set "EXIT_CODE=2"
    goto :fail
)

for /f %%I in ('powershell.exe -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmssfff"') do set "TIMESTAMP=%%I"
if not defined TIMESTAMP (
    set "ERROR_MESSAGE=No se pudo generar la marca de tiempo."
    goto :fail
)

set "XPZ_FILE=%OUTPUT_DIR%\SEGUROS_COMERCIAL_APIGLM_%TIMESTAMP%.xpz"
set "LOG_FILE=%LOG_DIR%\exportarXPZ_%TIMESTAMP%.log"

echo ==============================================================
echo   EXPORTACION AUTOMATICA DEL MODULO APIGLM
echo ============================================================== 
echo KB:     %KB_PATH%
echo Salida: %XPZ_FILE%
echo Log:    %LOG_FILE%
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PROGRESS_SCRIPT%" ^
    -MsbuildPath "%MSBUILD%" ^
    -ProjectFile "%PROJECT_FILE%" ^
    -GxProgramDir "%GX_PROGRAM_DIR%" ^
    -KbPath "%KB_PATH%" ^
    -XpzFile "%XPZ_FILE%" ^
    -LogFile "%LOG_FILE%"

if errorlevel 1 (
    set "ERROR_MESSAGE=GeneXus no pudo generar el XPZ. Revise el log."
    goto :fail
)

if not exist "%XPZ_FILE%" (
    set "ERROR_MESSAGE=MSBuild termino sin error, pero no se encontro el XPZ esperado."
    goto :fail
)

echo.
echo XPZ generado correctamente:
echo %XPZ_FILE%
echo Log de ejecucion:
echo %LOG_FILE%
set "EXIT_CODE=0"
goto :finish

:fail
if not defined EXIT_CODE set "EXIT_CODE=1"
echo.
echo ERROR: %ERROR_MESSAGE%
if exist "%LOG_FILE%" echo Revise el log: %LOG_FILE%

:finish
if "%NO_PAUSE%"=="0" (
    echo.
    pause
)
exit /b %EXIT_CODE%
