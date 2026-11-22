function Read-DiagnosticData {
    param([scriptblock]$Query)
    # A failed provider must not prevent the other checks from running.
    try { & $Query } catch { return }
}

function New-NetworkResult {
    param($Name, $Target, $Status, $Detail)
    [ordered]@{ Name = $Name; Target = $Target; Status = $Status; Detail = $Detail }
}

function Test-InternetPath {
    $target = '1.1.1.1:443'
    $client = $null
    $pending = $null
    try {
        $client = New-Object Net.Sockets.TcpClient
        $pending = $client.BeginConnect('1.1.1.1', 443, $null, $null)
        if ($pending.AsyncWaitHandle.WaitOne(3000)) {
            $client.EndConnect($pending)
            return New-NetworkResult 'Internet connectivity' $target 'Passed' 'TCP connection established.'
        }
        return New-NetworkResult 'Internet connectivity' $target 'Failed' 'TCP connection timed out.'
    } catch [Net.Sockets.SocketException] {
        return New-NetworkResult 'Internet connectivity' $target 'Failed' 'TCP connection could not be established.'
    } catch {
        return New-NetworkResult 'Internet connectivity' $target 'Unavailable' 'The TCP probe could not run.'
    } finally {
        if ($client) { $client.Close() }
        if ($pending) { $pending.AsyncWaitHandle.Close() }
    }
}

function Test-DnsLookup {
    $target = 'example.com'
    try {
        $answer = Resolve-DnsName -Name $target -Type A -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop
        if (@($answer | Where-Object { $_.Type -eq 'A' -and $_.IPAddress }).Count -gt 0) {
            return New-NetworkResult 'DNS resolution' $target 'Passed' 'IPv4 address record resolved.'
        }
        return New-NetworkResult 'DNS resolution' $target 'Failed' 'No IPv4 address record returned.'
    } catch [System.ComponentModel.Win32Exception] {
        return New-NetworkResult 'DNS resolution' $target 'Failed' 'DNS returned an error or timed out.'
    } catch {
        return New-NetworkResult 'DNS resolution' $target 'Unavailable' 'The DNS probe could not run.'
    }
}

function Test-DefaultGateway {
    try {
        $routes = Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop
        $route = $routes | Where-Object DestinationPrefix -eq '0.0.0.0/0' |
            Sort-Object @{Expression = { [long]$_.RouteMetric + $_.InterfaceMetric }}, InterfaceIndex |
            Select-Object -First 1
    } catch {
        return New-NetworkResult 'Default gateway' 'IPv4 default route' 'Unavailable' 'The routing table could not be read.'
    }
    if ($null -eq $route) {
        return New-NetworkResult 'Default gateway' 'IPv4 default route' 'Failed' 'No IPv4 default route was found.'
    }
    if (!$route.NextHop -or $route.NextHop -eq '0.0.0.0') {
        return New-NetworkResult 'Default gateway' 'On-link route' 'Unavailable' 'This route has no gateway address to ping.'
    }
    $ping = $null
    try {
        $ping = New-Object Net.NetworkInformation.Ping
        $reply = $ping.Send([ipaddress]$route.NextHop, 2000)
        if ($reply.Status -eq 'Success') {
            return New-NetworkResult 'Default gateway' $route.NextHop 'Passed' "ICMP echo reply in $($reply.RoundtripTime) ms."
        }
        return New-NetworkResult 'Default gateway' $route.NextHop 'Failed' "ICMP result: $($reply.Status)."
    } catch [Net.NetworkInformation.PingException] {
        return New-NetworkResult 'Default gateway' $route.NextHop 'Failed' 'ICMP echo attempt failed.'
    } catch {
        return New-NetworkResult 'Default gateway' $route.NextHop 'Unavailable' 'The ICMP probe could not run.'
    } finally {
        if ($ping) { $ping.Dispose() }
    }
}

function Get-PhysicalDriveSnapshot {
    $devices = @(Read-DiagnosticData { Get-PhysicalDisk -ErrorAction Stop | Sort-Object DeviceId })
    $index = 0
    foreach ($device in $devices) {
        $index++
        $label = if ([string]$device.DeviceId -match '^\d{1,5}$') { "Disk $($device.DeviceId)" } else { "Drive entry $index" }
        $counters = Read-DiagnosticData { Get-StorageReliabilityCounter -PhysicalDisk $device -ErrorAction Stop }
        $media = [string]$device.MediaType
        if ($media -notin 'SSD','HDD','SCM') { $media = 'Unspecified' }
        $status = [string]$device.HealthStatus
        if ($status -notin 'Healthy','Warning','Unhealthy') { $status = 'Unknown' }
        $wear = if ($media -eq 'SSD') { $counters.Wear }
        [ordered]@{
            Label = $label
            MediaType = $media
            HealthStatus = $status
            TemperatureC = $counters.Temperature
            WearUsedPercent = $wear
            ReadErrorsUncorrected = $counters.ReadErrorsUncorrected
            WriteErrorsUncorrected = $counters.WriteErrorsUncorrected
        }
    }
}

function Get-DiagnosticSnapshot {
    $ErrorActionPreference = 'Stop'
    $os = Read-DiagnosticData {
        Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 10 -Property Caption,Version,BuildNumber,LastBootUpTime,TotalVisibleMemorySize,FreePhysicalMemory
    }
    $cpu = @(Read-DiagnosticData {
        Get-CimInstance Win32_Processor -OperationTimeoutSec 10 -Property Name | Select-Object -ExpandProperty Name
    })
    $uptime = $null
    if ($os.LastBootUpTime) {
        $seconds = ((Get-Date) - $os.LastBootUpTime).TotalSeconds
        if ($seconds -ge 0) { $uptime = [long][math]::Floor($seconds) }
    }
    $disks = @(Read-DiagnosticData {
        Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3' -OperationTimeoutSec 10 -Property DeviceID,Size,FreeSpace |
            Sort-Object DeviceID | ForEach-Object {
                [ordered]@{ Drive = $_.DeviceID; TotalBytes = $_.Size; FreeBytes = $_.FreeSpace }
            }
    })
    $servicesAvailable = $true
    try {
        $stopped = @(Get-CimInstance Win32_Service -Filter "StartMode = 'Auto' AND State = 'Stopped'" -OperationTimeoutSec 10 -Property Name,DisplayName |
            Sort-Object DisplayName | ForEach-Object {
                [ordered]@{ Name = $_.Name; DisplayName = $_.DisplayName }
            })
    } catch {
        $servicesAvailable = $false
        $stopped = @()
    }
    [ordered]@{
        CapturedAt = [DateTimeOffset]::Now.ToString('o')
        IsSample = $false
        System = [ordered]@{
            Windows = $os.Caption; Version = $os.Version; Build = $os.BuildNumber
            Cpu = $cpu -join ' / '; UptimeSeconds = $uptime
            TotalMemoryKiB = $os.TotalVisibleMemorySize; FreeMemoryKiB = $os.FreePhysicalMemory
        }
        Disks = $disks
        PhysicalDrives = @(Get-PhysicalDriveSnapshot)
        Network = @((Test-InternetPath); (Test-DnsLookup); (Test-DefaultGateway))
        Services = [ordered]@{ Available = $servicesAvailable; StoppedAutomatic = $stopped }
    }
}
