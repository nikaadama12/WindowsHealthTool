@echo off
setlocal DisableDelayedExpansion
rem Let Windows PowerShell build its own module path when launched from PowerShell 7.
set "PSModulePath="
set "healthToolRoot=%~dp0"
echo Running Windows health checks...
rem Keep the preflight here so it can explain a blocked download before loading any scripts.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "$entry = Join-Path $env:healthToolRoot 'Start-HealthCheck.ps1';" ^
  "if ((Get-ExecutionPolicy) -eq 'RemoteSigned') {" ^
  "    $scripts = 'Start-HealthCheck.ps1', 'src\Collect.ps1', 'src\Health.ps1', 'src\Report.ps1';" ^
  "    $marked = @(foreach ($script in $scripts) {" ^
  "        $path = Join-Path $env:healthToolRoot $script;" ^
  "        if ((Get-Content -LiteralPath $path -Stream Zone.Identifier -ErrorAction SilentlyContinue) -match '^ZoneId=[34]$') { $path }" ^
  "    });" ^
  "    if ($marked.Count) {" ^
  "        Write-Host 'Windows marked these unsigned scripts as downloaded:'; $marked | ForEach-Object { Write-Host $_ };" ^
  "        $answer = Read-Host 'If you reviewed and trust these files, type YES to unblock them and run the check (Enter cancels)';" ^
  "        if ($answer -ne 'YES') { Write-Host 'Cancelled.'; exit 2 };" ^
  "        Unblock-File -LiteralPath $marked;" ^
  "    }" ^
  "};" ^
  "& $entry -ExportJson -OpenReport"
set "result=%errorlevel%"
if "%result%"=="0" exit /b 0
if "%result%"=="2" exit /b 2
echo.
echo See the error above. For a script policy error, see "Windows execution policy" in README.md.
pause
exit /b %result%
