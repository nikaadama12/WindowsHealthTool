#requires -Version 5.1
<#
.SYNOPSIS
    Create a local Windows health report.
.PARAMETER ExportJson
    Write the same snapshot and findings to JSON alongside the HTML.
.PARAMETER Sample
    Use the bundled fictional snapshot. All live probes are skipped.
.PARAMETER OpenReport
    Open the saved HTML report in the default application.
.EXAMPLE
    .\Start-HealthCheck.ps1 -ExportJson
#>
[CmdletBinding()]
param([switch]$ExportJson, [switch]$Sample, [switch]$OpenReport)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src/Health.ps1')
. (Join-Path $PSScriptRoot 'src/Report.ps1')

if ($Sample) {
    $snapshot = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'samples/fictional.psd1')
} else {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') {
        throw 'Live diagnostics require Windows. Use -Sample for a fictional report.'
    }
    . (Join-Path $PSScriptRoot 'src/Collect.ps1')
    $snapshot = Get-DiagnosticSnapshot
}

$health = Get-HealthAssessment $snapshot
$report = [ordered]@{ SchemaVersion = 2; Snapshot = $snapshot; Health = $health }
$html = ConvertTo-HealthHtml $report
if ($ExportJson) { $json = ConvertTo-Json $report -Depth 8 }

$directory = [IO.Directory]::CreateDirectory((Join-Path $PSScriptRoot 'reports')).FullName
$name = 'health-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N').Substring(0,12)
$htmlPath = Join-Path $directory "$name.html"
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($htmlPath, $html, $utf8)
$jsonPath = $null
if ($ExportJson) {
    $jsonPath = Join-Path $directory "$name.json"
    [IO.File]::WriteAllText($jsonPath, $json, $utf8)
}
if ($OpenReport) {
    Write-Host "Saved HTML report to $htmlPath"
    try {
        Invoke-Item -LiteralPath $htmlPath
    } catch {
        throw "Could not open the saved report. Open '$htmlPath' in a browser. $($_.Exception.Message)"
    }
}
[pscustomobject]@{ Status = $health.Status; HtmlPath = $htmlPath; JsonPath = $jsonPath }
