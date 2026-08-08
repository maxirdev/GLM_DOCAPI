@echo off
chcp 65001 >nul
title Generacion de documentacion APIGLM
set "ERRORLEVEL=0"

echo ==============================================================
echo   GENERACION DE DOCUMENTACION APIGLM
echo   %DATE% %TIME%
echo ==============================================================
echo.

echo [ 1/2 ] Extrayendo inventario de endpoints...
echo.
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0documentacion\Endpoints\binary\GenerarListaEndpoints.ps1"
if errorlevel 1 goto error
echo.
echo Inventario generado correctamente.
echo.

echo [ 2/2 ] Generando visor de endpoints...
echo.
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0documentacion\Endpoints\binary\GenerarVistaHTML.ps1"
if errorlevel 1 goto error
echo.
echo Visor generado correctamente.
echo.

echo ==============================================================
echo   PROCESO COMPLETADO CON EXITO
echo ==============================================================
goto fin

:error
echo.
echo ##############################################################
echo   ERROR: El proceso fallo. Revise los mensajes anteriores.
echo ##############################################################
exit /b 1

:fin
pause
exit /b 0
