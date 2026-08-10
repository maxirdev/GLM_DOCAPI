@echo off
chcp 65001 >nul
title Generador de Documentacion de Servicio APIGLM
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0GenerarDocumento.ps1"
if errorlevel 1 goto error
echo.
echo.
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
