<#
.SYNOPSIS
    Registers scheduled tasks that mute/unmute audio when connecting to
    specific Wi-Fi networks.
.DESCRIPTION
    Reads the network list from networks.json next to this script (machine-
    specific, not committed). If the file is missing - or -Reconfigure is
    passed - it prompts interactively for SSIDs and writes the file.

    Creates one scheduled task per network, triggered by WLAN-AutoConfig
    event 8001 (Wi-Fi connect) filtered on SSID. Tasks run as the current
    user, only while logged on, non-elevated.

    Re-running is idempotent: all existing 'WiFi Mute - *' / 'WiFi Unmute - *'
    tasks are removed first, so networks deleted from the config are cleaned up.
.PARAMETER Reconfigure
    Ignore any existing networks.json and prompt for a fresh network list.
.NOTES
    Run as your own user; no admin required.
#>
param(
    [switch]$Reconfigure
)

$ErrorActionPreference = 'Stop'

# The event trigger needs the WLAN-AutoConfig log, which only exists with a Wi-Fi adapter.
$wlanLog = Get-WinEvent -ListLog 'Microsoft-Windows-WLAN-AutoConfig/Operational' -ErrorAction SilentlyContinue
if (-not $wlanLog) {
    Write-Warning "WLAN-AutoConfig event log not found (no Wi-Fi on this machine?) - skipping wifi-mute install."
    return
}

$configPath = Join-Path $PSScriptRoot 'networks.json'
$scriptPath = Join-Path $PSScriptRoot 'Set-Mute.ps1'

function Read-NetworkConfig([string]$Path) {
    try {
        $raw = Get-Content -Raw -Path $Path
        $parsed = ConvertFrom-Json -InputObject $raw
    } catch {
        throw "Failed to parse '$Path' as JSON: $($_.Exception.Message)"
    }

    $entries = @($parsed)
    if ($entries.Count -eq 0) {
        throw "Config '$Path' contains no networks. Re-run with -Reconfigure to set it up."
    }
    foreach ($entry in $entries) {
        $hasSsid = ($null -ne $entry.PSObject.Properties['ssid'])
        $hasMute = ($null -ne $entry.PSObject.Properties['mute'])
        if (-not $hasSsid -or -not $hasMute) {
            throw "Config '$Path' is malformed: every entry needs an 'ssid' and a 'mute' property. Expected format: [{`"ssid`": `"MyNetwork`", `"mute`": true}]"
        }
        if ($entry.ssid -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.ssid)) {
            throw "Config '$Path' is malformed: 'ssid' must be a non-empty string."
        }
        if ($entry.mute -isnot [bool]) {
            throw "Config '$Path' is malformed: 'mute' must be a JSON boolean (true/false) for SSID '$($entry.ssid)'."
        }
    }
    return $entries
}

function New-NetworkConfig([string]$Path) {
    Write-Host 'No network configuration found (or reconfigure requested).'
    Write-Host 'Enter your Wi-Fi networks. Press Enter on an empty SSID to finish.'
    Write-Host ''

    $entries = @()
    while ($true) {
        $ssid = Read-Host 'SSID (empty to finish)'
        if ([string]::IsNullOrWhiteSpace($ssid)) {
            if ($entries.Count -ge 1) { break }
            Write-Host 'At least one network is required.'
            continue
        }
        $ssid = $ssid.Trim()

        $mute = $null
        while ($null -eq $mute) {
            $answer = Read-Host "Mute or unmute when connecting to '$ssid'? [m/u]"
            switch -Regex ($answer.Trim()) {
                '^(m|mute)$'   { $mute = $true }
                '^(u|unmute)$' { $mute = $false }
                default        { Write-Host "Please answer 'm' (mute) or 'u' (unmute)." }
            }
        }

        $entries += [pscustomobject]@{ ssid = $ssid; mute = $mute }
    }

    ConvertTo-Json -InputObject @($entries) | Out-File -FilePath $Path -Encoding utf8
    Write-Host "Saved configuration to $Path"
    Write-Host ''
    return $entries
}

# --- Load or create the config ----------------------------------------------

if ($Reconfigure -or -not (Test-Path $configPath)) {
    $networks = New-NetworkConfig $configPath
} else {
    $networks = Read-NetworkConfig $configPath
}

Write-Host "Installing $($networks.Count) task(s) from ${configPath}:"
foreach ($network in $networks) {
    $verb = if ($network.mute) { 'mute' } else { 'unmute' }
    Write-Host "  - '$($network.ssid)' -> $verb"
}
Write-Host ''

# --- Register the tasks ------------------------------------------------------

function New-WifiEventTrigger([string]$Ssid) {
    # New-ScheduledTaskTrigger cannot build custom event triggers; use the CIM class directly.
    $class = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
    $trigger = New-CimInstance -CimClass $class -ClientOnly
    $trigger.Enabled = $true
    $trigger.Subscription = @"
<QueryList><Query Id="0" Path="Microsoft-Windows-WLAN-AutoConfig/Operational">
  <Select Path="Microsoft-Windows-WLAN-AutoConfig/Operational">
    *[System[EventID=8001]] and *[EventData[Data[@Name='SSID']='$Ssid']]
  </Select>
</Query></QueryList>
"@
    return $trigger
}

# Remove all existing wifi-mute tasks first, so networks dropped from the
# config don't leave stale tasks behind.
$existing = @(Get-ScheduledTask -TaskName 'WiFi Mute - *', 'WiFi Unmute - *' -ErrorAction SilentlyContinue)
foreach ($task in $existing) {
    Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false
    Write-Host "Removed existing task '$($task.TaskName)'"
}

foreach ($network in $networks) {
    if ($network.mute) { $verb = 'Mute'; $muteArg = 1 } else { $verb = 'Unmute'; $muteArg = 0 }
    $taskName = "WiFi $verb - $($network.ssid)"
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -Mute $muteArg -Notify 1"
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -Trigger (New-WifiEventTrigger $network.ssid) `
        -Action $action -Settings $settings -Force | Out-Null
    Write-Host "Registered task '$taskName' (SSID '$($network.ssid)' -> $verb)"
}
