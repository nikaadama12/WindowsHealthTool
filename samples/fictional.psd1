@{
    IsSample = $true
    CapturedAt = '2026-04-16T09:42:00+00:00'
    System = @{
        Windows = 'Windows 11 Pro'
        Version = '10.0.26100'
        Build = '26100'
        Cpu = 'Example Eight-Core Processor'
        UptimeSeconds = 367380
        TotalMemoryKiB = 16777216
        FreeMemoryKiB = 6291456
    }
    Disks = @(
        @{ Drive = 'C:'; TotalBytes = 536870912000; FreeBytes = 64424509440 }
        @{ Drive = 'D:'; TotalBytes = 268435456000; FreeBytes = 171798691840 }
    )
    PhysicalDrives = @(
        @{ Label = 'Disk 0'; MediaType = 'SSD'; HealthStatus = 'Healthy'; TemperatureC = 38; WearUsedPercent = 6; ReadErrorsUncorrected = 0; WriteErrorsUncorrected = 0 }
        @{ Label = 'Disk 1'; MediaType = 'HDD'; HealthStatus = 'Warning'; TemperatureC = 33; WearUsedPercent = $null; ReadErrorsUncorrected = 2; WriteErrorsUncorrected = 0 }
    )
    Network = @(
        @{ Name = 'Internet connectivity'; Target = '1.1.1.1:443'; Status = 'Passed'; Detail = 'TCP connection established.' }
        @{ Name = 'DNS resolution'; Target = 'example.com'; Status = 'Failed'; Detail = 'DNS query timed out.' }
        @{ Name = 'Default gateway'; Target = '192.0.2.1'; Status = 'Passed'; Detail = 'ICMP echo reply in 2 ms.' }
    )
    Services = @{
        Available = $true
        StoppedAutomatic = @(@{ Name = 'ExampleInventory'; DisplayName = 'Example Inventory Service' })
    }
}
