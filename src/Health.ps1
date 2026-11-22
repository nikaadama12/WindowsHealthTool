function Get-FreePercent {
    param($Free, $Total)
    if ($null -eq $Free -or $null -eq $Total -or $Total -le 0 -or $Free -lt 0 -or $Free -gt $Total) {
        return $null
    }
    return (100.0 * $Free / $Total)
}

function Get-HealthAssessment {
    param([Parameter(Mandatory)]$Snapshot)
    $diskLimit = 15
    $memoryLimit = 85
    $findings = New-Object 'System.Collections.Generic.List[object]'
    $gaps = New-Object 'System.Collections.Generic.List[string]'
    $sys = $Snapshot.System
    if (!$sys.Windows -or !$sys.Build -or !$sys.Version) { $gaps.Add('Windows version') }
    if (!$sys.Cpu) { $gaps.Add('Processor') }
    if ($null -eq $sys.UptimeSeconds) { $gaps.Add('Uptime') }

    $used = $null
    $free = Get-FreePercent $sys.FreeMemoryKiB $sys.TotalMemoryKiB
    if ($null -eq $free) {
        $gaps.Add('Physical memory')
    } else {
        $used = 100 - $free
        if ($used -ge $memoryLimit) {
            $findings.Add([ordered]@{ Code = 'HighMemory'; Title = 'High memory usage'; Detail = "Physical memory use reached the $memoryLimit% warning threshold." })
        }
    }

    $lowest = $null
    if (!$Snapshot.Disks.Count) { $gaps.Add('Fixed disk capacity') }
    foreach ($disk in $Snapshot.Disks) {
        $free = Get-FreePercent $disk.FreeBytes $disk.TotalBytes
        if ($null -eq $free) { $gaps.Add("Capacity on $($disk.Drive)"); continue }
        if ($null -eq $lowest -or $free -lt $lowest) { $lowest = $free }
        if ($free -lt $diskLimit) {
            $findings.Add([ordered]@{ Code = 'LowDisk'; Title = "Low disk space on $($disk.Drive)"; Detail = "Free space is below $diskLimit% of this drive's capacity." })
        }
    }

    if (!$Snapshot.PhysicalDrives.Count) { $gaps.Add('Physical drive inventory') }
    foreach ($drive in $Snapshot.PhysicalDrives) {
        $reasons = @(
            switch ($drive.HealthStatus) {
                'Healthy' { }
                'Warning' { 'Windows reports a drive health warning.' }
                'Unhealthy' { 'Windows reports that the drive is unhealthy.' }
                default { $gaps.Add("Windows drive health for $($drive.Label)") }
            }
            if ($drive.MediaType -eq 'SSD' -and $drive.WearUsedPercent -ge 100) {
                'SSD wear has reached the estimated endurance limit.'
            }
            if ($drive.ReadErrorsUncorrected -gt 0 -or $drive.WriteErrorsUncorrected -gt 0) {
                'The drive has recorded uncorrected I/O errors.'
            }
        )
        if ($reasons.Count) {
            $findings.Add([ordered]@{ Code = 'DriveHealth'; Title = "Drive health warning on $($drive.Label)"; Detail = $reasons -join ' ' })
        }
    }

    $passed = 0
    foreach ($test in $Snapshot.Network) {
        switch ($test.Status) {
            'Passed' { $passed++ }
            'Failed' { $findings.Add([ordered]@{ Code = 'NetworkFailure'; Title = "$($test.Name) failed"; Detail = $test.Detail }) }
            default  { $gaps.Add($test.Name) }
        }
    }
    if (!$Snapshot.Services.Available) { $gaps.Add('Service inventory') }
    $status = 'Healthy'
    if ($gaps.Count) { $status = 'Incomplete' }
    if ($findings.Count -or ($Snapshot.Services.Available -and $Snapshot.Services.StoppedAutomatic.Count)) {
        $status = 'Review'
    }

    [ordered]@{
        Status = $status
        Warnings = $findings.ToArray()
        Unavailable = $gaps.ToArray()
        MemoryUsedPercent = $used
        LowestDiskFreePercent = $lowest
        NetworkPassed = $passed
        Thresholds = [ordered]@{ MinDiskFreePercent = $diskLimit; HighMemoryUsedPercent = $memoryLimit }
    }
}
