@echo off
chcp 65001 >nul
setlocal DisableDelayedExpansion
set "Repositorio=%~dp0"
if "%Repositorio:~-1%"=="\" set "Repositorio=%Repositorio:~0,-1%"
set "PowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PowerShell%" exit /b 1
"%PowerShell%" -NoProfile -ExecutionPolicy Bypass -File "%Repositorio%\binary\GestionDocumentosGLM.ps1" -Repositorio "%Repositorio%"
set "CodigoSalida=%ERRORLEVEL%"
if not "%CodigoSalida%"=="0" (
    echo.
    echo El proceso termino con errores ^(codigo %CodigoSalida%^). Revise el mensaje anterior.
    pause
)
endlocal & exit /b %CodigoSalida%
