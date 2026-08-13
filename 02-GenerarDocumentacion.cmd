@echo off
chcp 65001 >nul
title Generacion de documentacion APIGLM
set "ERRORLEVEL=0"

echo ==============================================================
echo   GENERACION DE DOCUMENTACION APIGLM
echo   %DATE% %TIME%
echo ==============================================================
echo.

echo [ 1/2 ] Analizando XPZ...
echo.
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0documentacion\Endpoints\binary\GenerarListaEndpoints.ps1"
if errorlevel 1 goto error
echo.
echo Analisis de XPZ completado.
echo.

echo [ 2/2 ] Validando completitud del XPZ...
echo.
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0binary\ValidarXPZ.ps1"
if errorlevel 1 (
    echo.
    %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Write-Host 'ADVERTENCIA: Hay servicios que requieren exportacion adicional. Revise el reporte en Logs\*-validacion-xpz.json.' -ForegroundColor Yellow"
    echo.
) else (
    echo.
    echo Validacion completada sin incidencias.
    echo.
)

echo ==============================================================
echo   PROCESO COMPLETADO CON EXITO
echo ==============================================================
goto fin

:error
echo.
echo ##############################################################
echo   ERROR: El proceso fallo. Revise los mensajes anteriores.
echo ##############################################################
pause
exit /b 1

:fin
pause
exit /b 0
