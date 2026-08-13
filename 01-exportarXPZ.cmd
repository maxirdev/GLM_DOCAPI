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
set "CONFIG_FILE=%~dp0configuracion.json"
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

if not exist "%CONFIG_FILE%" (
    set "ERROR_MESSAGE=No se encontro la configuracion en %CONFIG_FILE%."
    goto :fail
)

for /f "usebackq delims=" %%I in (`powershell.exe -NoProfile -Command "$p = '%CONFIG_FILE%'; try { $j = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json; if ($null -eq $j.exportacion -or $null -eq $j.exportacion.PSObject.Properties['onlyModuleAPIGLM']) { 'true' } elseif ($j.exportacion.onlyModuleAPIGLM -is [bool]) { $j.exportacion.onlyModuleAPIGLM.ToString().ToLowerInvariant() } else { 'INVALID' } } catch { 'INVALID' }"`) do set "ONLY_MODULE_APIGLM=%%I"
if /I "%ONLY_MODULE_APIGLM%"=="INVALID" (
    set "ERROR_MESSAGE=La propiedad exportacion.onlyModuleAPIGLM debe ser un booleano JSON (true o false)."
    goto :fail
)
if /I not "%ONLY_MODULE_APIGLM%"=="true" if /I not "%ONLY_MODULE_APIGLM%"=="false" (
    set "ERROR_MESSAGE=No se pudo resolver exportacion.onlyModuleAPIGLM."
    goto :fail
)

rem GeneXus puede permanecer abierto. El exportador utiliza una sesion
rem independiente de MSBuild y advierte sobre la concurrencia antes de iniciar.

for /f %%I in ('powershell.exe -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmssfff"') do set "TIMESTAMP=%%I"
if not defined TIMESTAMP (
    set "ERROR_MESSAGE=No se pudo generar la marca de tiempo."
    goto :fail
)

if /I "%ONLY_MODULE_APIGLM%"=="true" (
    set "EXPORT_LABEL=APIGLM"
    set "EXPORT_SWITCH=ExportarAPIGLM"
    set "XPZ_FILE=%OUTPUT_DIR%\SEGUROS_COMERCIAL_APIGLM_%TIMESTAMP%.xpz"
) else (
    set "EXPORT_LABEL=KB completa"
    set "EXPORT_SWITCH=ExportarTodaLaKB"
    set "XPZ_FILE=%OUTPUT_DIR%\SEGUROS_COMERCIAL_KB_%TIMESTAMP%.xpz"
)
set "LOG_FILE=%LOG_DIR%\exportarXPZ_%TIMESTAMP%.log"

echo ==============================================================
echo   EXPORTACION AUTOMATICA - %EXPORT_LABEL%
echo ============================================================== 
echo KB:     %KB_PATH%
echo Alcance: %EXPORT_LABEL%
echo Salida: %XPZ_FILE%
echo Log:    %LOG_FILE%
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PROGRESS_SCRIPT%" ^
    -MsbuildPath "%MSBUILD%" ^
    -ProjectFile "%PROJECT_FILE%" ^
    -GxProgramDir "%GX_PROGRAM_DIR%" ^
    -KbPath "%KB_PATH%" ^
    -XpzFile "%XPZ_FILE%" ^
    -LogFile "%LOG_FILE%" ^
    -TargetName %EXPORT_SWITCH%

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
