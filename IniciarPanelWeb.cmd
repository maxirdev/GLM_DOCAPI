@echo off
chcp 65001 >nul
setlocal DisableDelayedExpansion
set "Repositorio=%~dp0"
if "%Repositorio:~-1%"=="\" set "Repositorio=%Repositorio:~0,-1%"
set "PowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PowerShell%" (
    echo No se encontro Windows PowerShell 5.1.
    endlocal & exit /b 1	
)
set "Puerto=8123"
set "UrlPanel=http://127.0.0.1:%Puerto%/"
"%PowerShell%" -NoProfile -Command "$ErrorActionPreference='Stop'; $apiOk=$false; try { $r=Invoke-WebRequest -UseBasicParsing -Uri '%UrlPanel%api/estado' -TimeoutSec 2; $apiOk=$r.StatusCode -eq 200 -and $r.Content -match '\"ok\":true' } catch {}; if(-not $apiOk){ exit 1 }; if($r.Content -match '20260820-client-export-profile'){ exit 0 }; exit 2"
set "EstadoPanel=%ERRORLEVEL%"
if "%EstadoPanel%"=="2" (
    "%PowerShell%" -NoProfile -Command "$ErrorActionPreference='Stop'; $repo=[System.IO.Path]::GetFullPath('%Repositorio%'); $procesos=Get-CimInstance Win32_Process -Filter \"Name = 'powershell.exe'\" | Where-Object { $_.CommandLine -and $_.CommandLine -match 'ServidorPanelWeb\.ps1' -and $_.CommandLine -like ('*' + $repo + '*') }; foreach($proceso in $procesos){ Stop-Process -Id $proceso.ProcessId -Force }"
    timeout /t 1 /nobreak >nul
)
if "%EstadoPanel%"=="0" (
    echo.
    echo El panel web ya se encuentra ejecutando en:
    echo %UrlPanel%
    start "" "%UrlPanel%"
    endlocal & exit /b 0
)
"%PowerShell%" -NoProfile -ExecutionPolicy Bypass -File "%Repositorio%\binary\ServidorPanelWeb.ps1" -RepositoryRoot "%Repositorio%"
set "CodigoSalida=%ERRORLEVEL%"
if not "%CodigoSalida%"=="0" (
    echo.
    echo El panel web no pudo iniciar. Codigo de salida: %CodigoSalida%
    echo Revise el mensaje anterior para conocer la causa.
    pause
)
endlocal & exit /b %CodigoSalida%
