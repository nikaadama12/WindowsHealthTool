function Format-HtmlText {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return 'Unavailable' }
    [Net.WebUtility]::HtmlEncode([string]$Value)
}

function Format-Percent {
    param($Value)
    if ($null -eq $Value) { return 'Unavailable' }
    '{0:0.#}%' -f $Value
}

function Format-GiB {
    param($Bytes)
    if ($null -eq $Bytes) { return 'Unavailable' }
    '{0:0.#} GiB' -f ($Bytes / 1GB)
}

function Get-ReportIcon {
    param($Name)
    $paths = @{
        pulse = 'M2 12h5l3-8 4 16 3-8h5'
        memory = 'M3 6h18v11H3z M6 17v3m4-3v3m4-3v3m4-3v3 M7 10v3m5-3v3m5-3v3'
        disk = 'M5 5h14l3 10v4H2v-4z M3 14h18m-5 3h2'
        network = 'M9 3h6v5H9z M2 16h6v5H2z M16 16h6v5h-6z M12 8v4m-7 4v-4h14v4'
        services = 'M3 4h18v6H3z M3 14h18v6H3z M6 7h2m-2 10h2'
        clock = 'M21 12a9 9 0 1 1-18 0 9 9 0 1 1 18 0z M12 7v5l3 2'
        alert = 'M12 3 2 20h20z M12 9v4m0 3v.2'
    }
    "<svg aria-hidden='true' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.7' stroke-linecap='round' stroke-linejoin='round'><path d='$($paths[$Name])'/></svg>"
}

function New-MetricCard {
    param($Label, $Value, $Caption, $Icon, $Tone)
    @"
<article class="metric"><div class="metric-head"><span>$Label</span><i class="icon $Tone">$(Get-ReportIcon $Icon)</i></div>
<strong>$Value</strong><small>$Caption</small></article>
"@
}

function ConvertTo-DriveHealthHtml {
    param($Drives)
    if (!$Drives.Count) { return '<p class="empty">Physical drive inventory unavailable.</p>' }
    $cards = @(foreach ($drive in $Drives) {
        $tone = switch ($drive.HealthStatus) { 'Healthy' { 'good' } { $_ -in 'Warning','Unhealthy' } { 'bad' } default { 'unknown' } }
        $temperature = if ($null -eq $drive.TemperatureC) { 'Unavailable' } else { "$(Format-HtmlText $drive.TemperatureC) &deg;C" }
        $wear = if ($drive.MediaType -eq 'SSD') {
            "<dt>Endurance used</dt><dd>$(Format-Percent $drive.WearUsedPercent)</dd>"
        }
        @"
<article class="drive-card"><h3>$(Format-HtmlText $drive.Label) <span>&middot; $(Format-HtmlText $drive.MediaType)</span></h3>
<dl><dt>Windows health</dt><dd><span class="pill $tone">$(Format-HtmlText $drive.HealthStatus)</span></dd>
<dt>Temperature</dt><dd>$temperature</dd>$wear
<dt>Uncorrected reads</dt><dd>$(Format-HtmlText $drive.ReadErrorsUncorrected)</dd>
<dt>Uncorrected writes</dt><dd>$(Format-HtmlText $drive.WriteErrorsUncorrected)</dd></dl></article>
"@
    })
    "<div class='drive-grid'>$($cards -join '')</div>"
}

function ConvertTo-HealthHtml {
    param([Parameter(Mandatory)]$Report)
    $s = $Report.Snapshot
    $h = $Report.Health
    $css = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'report.css'))
    $when = [DateTimeOffset]::Parse($s.CapturedAt, [Globalization.CultureInfo]::InvariantCulture)
    $date = $when.ToString('dd MMM yyyy', [Globalization.CultureInfo]::InvariantCulture)
    $time = $when.ToString('HH:mm zzz')
    $source = if ($s.IsSample) { 'Fictional sample' } else { 'Local snapshot' }
    $state = switch ($h.Status) {
        'Review' { 'Needs review' } 'Incomplete' { 'Incomplete' } default { 'Healthy' }
    }
    $serviceCount = if ($s.Services.Available) { $s.Services.StoppedAutomatic.Count } else { 'Unavailable' }
    $cards = @(
        New-MetricCard 'Memory in use' (Format-Percent $h.MemoryUsedPercent) 'Of visible physical RAM' 'memory' 'teal'
        New-MetricCard 'Lowest disk free' (Format-Percent $h.LowestDiskFreePercent) 'Across measured fixed drives' 'disk' 'blue'
        New-MetricCard 'Network checks' "$($h.NetworkPassed)<em> / $($s.Network.Count)</em>" 'IPv4 probes passed' 'network' 'purple'
        New-MetricCard 'Stopped services' $serviceCount 'Automatic startup only' 'services' 'slate'
    ) -join ''

    $findingRows = @(foreach ($item in $h.Warnings) {
        "<li><i class='finding-icon'>$(Get-ReportIcon 'alert')</i><div><b>$(Format-HtmlText $item.Title)</b><p>$(Format-HtmlText $item.Detail)</p></div></li>"
    }) -join ''
    if (!$findingRows) { $findingRows = "<li>Available measurements triggered no health warnings.</li>" }
    $gaps = if ($h.Unavailable.Count) {
        "<p class='notice'><b>Unavailable data</b> &middot; $(Format-HtmlText ($h.Unavailable -join ', '))</p>"
    }
    $ram = if ($s.System.TotalMemoryKiB -gt 0) { Format-GiB ($s.System.TotalMemoryKiB * 1024.0) } else { 'Unavailable' }
    $uptime = if ($null -ne $s.System.UptimeSeconds) {
        $span = [timespan]::FromSeconds($s.System.UptimeSeconds)
        '{0}d {1}h {2}m' -f $span.Days, $span.Hours, $span.Minutes
    } else { 'Unavailable' }
    $diskRows = @(foreach ($d in $s.Disks) {
        $free = Get-FreePercent $d.FreeBytes $d.TotalBytes
        $bar = ''
        $tone = ''
        if ($null -ne $free) {
            $width = (100 - $free).ToString('0.##', [Globalization.CultureInfo]::InvariantCulture)
            if ($free -lt $h.Thresholds.MinDiskFreePercent) { $tone = 'low' }
            $bar = "<div class='track $tone' aria-hidden='true'><span style='width:$width%'></span></div>"
        }
        "<li><div class='disk-head'><b>$(Format-HtmlText $d.Drive)</b><span>$(Format-Percent $free) free</span></div>$bar<p>$(Format-GiB $d.FreeBytes) free of $(Format-GiB $d.TotalBytes)</p></li>"
    }) -join ''
    if (!$diskRows) { $diskRows = '<li>Fixed disk data unavailable.</li>' }
    $networkRows = @(foreach ($n in $s.Network) {
        $tone = switch ($n.Status) { 'Passed' { 'good' } 'Failed' { 'bad' } default { 'unknown' } }
        "<tr><th scope='row'>$(Format-HtmlText $n.Name)</th><td class='target'>$(Format-HtmlText $n.Target)</td><td><span class='pill $tone'>$(Format-HtmlText $n.Status)</span></td><td>$(Format-HtmlText $n.Detail)</td></tr>"
    }) -join ''
    $serviceBody = if (!$s.Services.Available) {
        '<p class="empty">Service inventory unavailable.</p>'
    } elseif (!$s.Services.StoppedAutomatic.Count) {
        '<p class="empty">No stopped automatic services found.</p>'
    } else {
        $rows = @(foreach ($svc in $s.Services.StoppedAutomatic) {
            "<tr><th scope='row'>$(Format-HtmlText $svc.DisplayName)</th><td class='target'>$(Format-HtmlText $svc.Name)</td><td><span class='pill bad'>Stopped</span></td></tr>"
        }) -join ''
        "<div class='table-wrap' tabindex='0' aria-label='Stopped services table'><table><thead><tr><th>Display name</th><th>Service name</th><th>State</th></tr></thead><tbody>$rows</tbody></table></div>"
    }
    @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>Windows Health | Diagnostic report</title><style>$css</style></head>
<body><header><div class="top inner"><a class="brand" href="#overview"><i>$(Get-ReportIcon 'pulse')</i>Windows Health</a>
<nav aria-label="Report sections"><a href="#system">System</a><a href="#storage">Drives</a><a href="#network">Network</a><a href="#services">Services</a></nav></div></header>
<main class="inner" id="overview"><div class="intro"><div><div class="eyebrow"><span></span> Diagnostics report</div>
<h1>Health overview</h1><div class="meta"><span class="timestamp">$(Get-ReportIcon 'clock') $date &middot; $time</span><span class="source">$source</span></div></div>
<div class="status-group"><small>Overall status</small><span class="pill $($h.Status.ToLowerInvariant())">$state</span></div></div>
<div class="metrics">$cards</div>
<section class="panel findings"><div class="section-head"><h2>Health warnings</h2><span class="count">$($h.Warnings.Count)</span></div><ul>$findingRows</ul>$gaps</section>
<div class="split" id="system"><section class="panel"><div class="section-head"><h2>System information</h2></div><dl>
<dt>Operating system</dt><dd>$(Format-HtmlText $s.System.Windows)</dd><dt>Version / build</dt><dd>$(Format-HtmlText $s.System.Version) / $(Format-HtmlText $s.System.Build)</dd>
<dt>Processor</dt><dd>$(Format-HtmlText $s.System.Cpu)</dd><dt>Visible RAM</dt><dd>$ram</dd><dt>Uptime</dt><dd>$uptime</dd></dl></section>
<section class="panel"><div class="section-head"><h2>Disk capacity</h2></div><ul class="drives">$diskRows</ul></section></div>
<section class="panel" id="storage"><div class="section-head"><h2>Physical drive health</h2></div>$(ConvertTo-DriveHealthHtml $s.PhysicalDrives)</section>
<section class="panel" id="network"><div class="section-head"><h2>Network diagnostics</h2></div>
<div class="table-wrap" tabindex="0" aria-label="Network diagnostics table"><table><thead><tr><th>Check</th><th>Target</th><th>Result</th><th>Observation</th></tr></thead><tbody>$networkRows</tbody></table></div></section>
<section class="panel" id="services"><div class="section-head"><h2>Stopped automatic services</h2></div>$serviceBody</section>
<footer><span>Windows Health &amp; Diagnostics Tool</span><a href="#overview">Back to top &uarr;</a></footer></main></body></html>
"@
}
