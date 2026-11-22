@echo off
setlocal DisableDelayedExpansion
echo Running Windows health checks...
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File "%~dp0Start-HealthCheck.ps1" -ExportJson -OpenReport
set "result=%errorlevel%"
if "%result%"=="0" exit /b 0
echo.
echo See the error above. For a script policy error, see "Windows execution policy" in README.md.
pause
exit /b %result%
