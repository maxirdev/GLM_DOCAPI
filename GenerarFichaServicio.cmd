@echo off
chcp 65001 >nul
title Generacion de ficha de servicio APIGLM
set "ERRORLEVEL=0"

echo ==============================================================
echo   GENERACION DE FICHA DE SERVICIO APIGLM
echo   %DATE% %TIME%
echo ==============================================================
echo.

echo [ 1/1 ] Generando ficha del servicio seleccionado...
echo.
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0documentacion\Generador\binary\GenerarDocumento.ps1"
if errorlevel 1 goto error
echo.
echo Ficha generada correctamente.
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
pause
exit /b 1

:fin
pause
exit /b 0
