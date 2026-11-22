#requires -Version 5.1
# Dependency-free tests. Every input and every provider response is synthetic.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/Health.ps1')
. (Join-Path $root 'src/Report.ps1')
. (Join-Path $root 'src/Collect.ps1')
$fixture = Join-Path $root 'samples/fictional.psd1'
$results = New-Object 'System.Collections.Generic.List[bool]'

function Assert-Equal {
    param($Actual, $Expected)
    if ($Actual -cne $Expected) {
        throw "Expected [$Expected], received [$Actual]."
    }
}

function Invoke-Case {
    param([string]$Name, [scriptblock]$Body)
    try {
        $s = Import-PowerShellDataFile $fixture
        & $Body
        $results.Add($true)
        Write-Output "PASS  $Name"
    } catch {
        $results.Add($false)
        Write-Output "FAIL  $Name - $($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))"
    }
}

function Set-HealthyFixture {
    param($Snapshot)
    $Snapshot.Network[1].Status = 'Passed'
    $Snapshot.Disks[0].FreeBytes = $Snapshot.Disks[0].TotalBytes / 2
    $Snapshot.Services.StoppedAutomatic = @()
    $Snapshot.PhysicalDrives[1].HealthStatus = 'Healthy'
    $Snapshot.PhysicalDrives[1].ReadErrorsUncorrected = 0
}

Invoke-Case 'Healthy snapshot has no findings or gaps' {
    Set-HealthyFixture $s
    $h = Get-HealthAssessment $s
    Assert-Equal $h.Status 'Healthy'
    Assert-Equal $h.Warnings.Count 0
    Assert-Equal $h.Unavailable.Count 0
    Assert-Equal $h.NetworkPassed 3
}
Invoke-Case 'Sample flags the correct drive and failed network probe' {
    $h = Get-HealthAssessment $s
    Assert-Equal $h.Status 'Review'
    Assert-Equal ($h.Warnings.Code -join ',') 'LowDisk,DriveHealth,NetworkFailure'
    Assert-Equal $h.Warnings[0].Title 'Low disk space on C:'
    Assert-Equal $h.Warnings[1].Title 'Drive health warning on Disk 1'
    Assert-Equal $h.Warnings[2].Title 'DNS resolution failed'
    Assert-Equal $h.LowestDiskFreePercent 12
    Assert-Equal $h.NetworkPassed 2
}
Invoke-Case 'Disk warning uses the unrounded value below 15 percent' {
    Set-HealthyFixture $s
    $s.Disks[0].TotalBytes = 100000
    $s.Disks[0].FreeBytes = 15000
    Assert-Equal (Get-HealthAssessment $s).Warnings.Count 0
    $s.Disks[0].FreeBytes = 14999
    Assert-Equal (Get-HealthAssessment $s).Warnings[0].Code 'LowDisk'
    $s.Disks[0].FreeBytes = 0
    Assert-Equal (Get-HealthAssessment $s).LowestDiskFreePercent 0
}
Invoke-Case 'Memory warning starts at exactly 85 percent' {
    Set-HealthyFixture $s
    $s.System.TotalMemoryKiB = 100000
    $s.System.FreeMemoryKiB = 15001
    Assert-Equal (Get-HealthAssessment $s).Warnings.Count 0
    $s.System.FreeMemoryKiB = 15000
    Assert-Equal (Get-HealthAssessment $s).Warnings[0].Code 'HighMemory'
    $s.System.FreeMemoryKiB = 0
    Assert-Equal (Get-HealthAssessment $s).MemoryUsedPercent 100
}
Invoke-Case 'Invalid counters are unavailable, including a zero denominator' {
    Set-HealthyFixture $s
    $s.System.TotalMemoryKiB = 0
    $s.Disks[0].FreeBytes = $null
    $s.Disks[1].FreeBytes = $s.Disks[1].TotalBytes + 1
    $h = Get-HealthAssessment $s
    Assert-Equal $h.Status 'Incomplete'
    Assert-Equal $h.MemoryUsedPercent $null
    Assert-Equal $h.LowestDiskFreePercent $null
    Assert-Equal $h.Unavailable.Count 3
    Assert-Equal $h.Warnings.Count 0
}
Invoke-Case 'Unavailable probe stays distinct from a failed probe' {
    Set-HealthyFixture $s
    $s.Network[2].Status = 'Unavailable'
    $h = Get-HealthAssessment $s
    Assert-Equal $h.Status 'Incomplete'
    Assert-Equal $h.NetworkPassed 2
    Assert-Equal $h.Unavailable[0] 'Default gateway'
    Assert-Equal $h.Warnings.Count 0
}
Invoke-Case 'Every failed probe has its own warning' {
    Set-HealthyFixture $s
    foreach ($probe in $s.Network) { $probe.Status = 'Failed' }
    $h = Get-HealthAssessment $s
    Assert-Equal $h.Warnings.Count 3
    Assert-Equal $h.NetworkPassed 0
}
Invoke-Case 'A stopped automatic service alone warrants review' {
    $service = $s.Services.StoppedAutomatic[0]
    Set-HealthyFixture $s
    $s.Services.StoppedAutomatic = @($service)
    Assert-Equal (Get-HealthAssessment $s).Status 'Review'
}
Invoke-Case 'Unreadable service inventory is incomplete' {
    Set-HealthyFixture $s
    $s.Services.Available = $false
    Assert-Equal (Get-HealthAssessment $s).Status 'Incomplete'
}
Invoke-Case 'Known warnings take priority and retain missing fields' {
    $s.System.Cpu = $null
    $s.Disks = @()
    $h = Get-HealthAssessment $s
    Assert-Equal $h.Status 'Review'
    Assert-Equal ($h.Unavailable -join ',') 'Processor,Fixed disk capacity'
}
Invoke-Case 'Report encodes dynamic text and preserves missing counters' {
    $s.Services.StoppedAutomatic[0].DisplayName = '<img src=x> & test'
    $s.System.FreeMemoryKiB = $null
    $html = ConvertTo-HealthHtml @{ Snapshot = $s; Health = (Get-HealthAssessment $s) }
    Assert-Equal ($html.Contains('&lt;img src=x&gt; &amp; test')) $true
    Assert-Equal ($html.Contains('<img src=x>')) $false
    Assert-Equal ($html.Contains('Unavailable data')) $true
    Assert-Equal ($html.Contains('Fictional sample')) $true
}
Invoke-Case 'Unavailable providers still produce a complete snapshot structure' {
    function Get-PhysicalDisk { throw 'Synthetic provider failure' }
    function Get-CimInstance { throw 'Synthetic provider failure' }
    function Get-NetRoute { throw 'Synthetic provider failure' }
    function Resolve-DnsName { throw 'Synthetic provider failure' }
    function Test-InternetPath { New-NetworkResult 'Internet connectivity' 'example' 'Unavailable' 'Synthetic failure.' }
    $snapshot = Get-DiagnosticSnapshot
    $h = Get-HealthAssessment $snapshot
    Assert-Equal $h.Status 'Incomplete'
    Assert-Equal $h.NetworkPassed 0
    Assert-Equal $snapshot.Network.Count 3
    Assert-Equal $snapshot.Services.Available $false
    Assert-Equal $snapshot.Disks.Count 0
    Assert-Equal $snapshot.PhysicalDrives.Count 0
    Assert-Equal $h.Warnings.Count 0
}
Invoke-Case 'No IPv4 default route is a failed reachability check' {
    function Get-NetRoute { return }
    Assert-Equal (Test-DefaultGateway).Status 'Failed'
}
Invoke-Case 'An on-link default route has no ping target' {
    function Get-NetRoute {
        [pscustomobject]@{ DestinationPrefix = '0.0.0.0/0'; NextHop = '0.0.0.0'; RouteMetric = 1; InterfaceMetric = 1; InterfaceIndex = 1 }
    }
    Assert-Equal (Test-DefaultGateway).Status 'Unavailable'
}
Invoke-Case 'DNS errors and empty answers both fail the lookup' {
    function Resolve-DnsName { throw [System.ComponentModel.Win32Exception]::new(1460) }
    Assert-Equal (Test-DnsLookup).Status 'Failed'
    function Resolve-DnsName { return }
    Assert-Equal (Test-DnsLookup).Status 'Failed'
}

Invoke-Case 'A Windows drive warning or unhealthy state triggers review on its own' {
    Set-HealthyFixture $s
    foreach ($state in 'Warning','Unhealthy') {
        $s.PhysicalDrives[1].HealthStatus = $state
        $h = Get-HealthAssessment $s
        Assert-Equal $h.Status 'Review'
        Assert-Equal $h.Warnings[0].Code 'DriveHealth'
    }
}
Invoke-Case 'SSD wear is consumed endurance and triggers at 100 percent' {
    Set-HealthyFixture $s
    $s.PhysicalDrives[0].WearUsedPercent = 99
    Assert-Equal (Get-HealthAssessment $s).Status 'Healthy'
    $s.PhysicalDrives[0].WearUsedPercent = 100
    Assert-Equal (Get-HealthAssessment $s).Warnings[0].Code 'DriveHealth'
}
Invoke-Case 'Uncorrected read or write errors trigger review even with healthy Windows status' {
    Set-HealthyFixture $s
    foreach ($field in 'ReadErrorsUncorrected','WriteErrorsUncorrected') {
        $s.PhysicalDrives[1][$field] = 1
        Assert-Equal (Get-HealthAssessment $s).Warnings[0].Title 'Drive health warning on Disk 1'
        $s.PhysicalDrives[1][$field] = 0
    }
}
Invoke-Case 'Missing inventory and unknown health remain visible as gaps' {
    Set-HealthyFixture $s
    $s.PhysicalDrives[1].HealthStatus = 'Unknown'
    Assert-Equal (Get-HealthAssessment $s).Status 'Incomplete'
    $s.Remove('PhysicalDrives')
    Assert-Equal (Get-HealthAssessment $s).Unavailable[0] 'Physical drive inventory'
    Assert-Equal ((ConvertTo-DriveHealthHtml $s.PhysicalDrives).Contains('inventory unavailable')) $true
}
Invoke-Case 'Per-drive counter failure preserves inventory and real zeroes from another device' {
    function Get-PhysicalDisk {
        [pscustomobject]@{ DeviceId = '0'; MediaType = 'SSD'; HealthStatus = 'Healthy'; SerialNumber = 'PrivateValue' }
        [pscustomobject]@{ DeviceId = '1'; MediaType = 'HDD'; HealthStatus = 'Healthy' }
    }
    function Get-StorageReliabilityCounter {
        param($PhysicalDisk)
        if ($PhysicalDisk.DeviceId -eq '1') { throw 'Synthetic access denied' }
        [pscustomobject]@{ Temperature = 37; Wear = 0; ReadErrorsUncorrected = 0; WriteErrorsUncorrected = 2 }
    }
    $drives = @(Get-PhysicalDriveSnapshot)
    Assert-Equal $drives.Count 2
    Assert-Equal $drives[0].WearUsedPercent 0
    Assert-Equal $drives[0].WriteErrorsUncorrected 2
    Assert-Equal $drives[1].TemperatureC $null
    Assert-Equal $drives[1].HealthStatus 'Healthy'
    Assert-Equal (($drives | ConvertTo-Json).Contains('PrivateValue')) $false
    $html = ConvertTo-DriveHealthHtml $drives
    Assert-Equal ($html.Contains('Unavailable')) $true
    Assert-Equal ($html.Contains('0%')) $true
}

$failed = @($results | Where-Object { !$_ }).Count
Write-Output ("{0} passed, {1} failed" -f ($results.Count - $failed), $failed)
if ($failed) { exit 1 }
