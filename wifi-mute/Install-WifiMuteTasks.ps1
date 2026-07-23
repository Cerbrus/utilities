<#
.SYNOPSIS
    Registers scheduled tasks that mute/unmute audio when connecting to
    specific Wi-Fi networks.
.DESCRIPTION
    Creates one scheduled task per network, triggered by WLAN-AutoConfig
    event 8001 (Wi-Fi connect) filtered on SSID. Tasks run as the current
    user, only while logged on, non-elevated.

    Re-running is idempotent: existing tasks are overwritten.
.NOTES
    Run as your own user; no admin required.
#>

# SSID => mute state (1 = mute, 0 = unmute). Edit to taste, then re-run.
$networks = @(
    @{ Ssid = 'WorkNetwork'; Mute = 1 }
    @{ Ssid = 'HomeNetwork';  Mute = 0 }
)

$scriptPath = Join-Path $PSScriptRoot 'Set-Mute.ps1'

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

foreach ($network in $networks) {
    $verb = if ($network.Mute) { 'Mute' } else { 'Unmute' }
    $taskName = "WiFi $verb - $($network.Ssid)"
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -Mute $($network.Mute) -Notify 1"
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -Trigger (New-WifiEventTrigger $network.Ssid) `
        -Action $action -Settings $settings -Force | Out-Null
    Write-Host "Registered task '$taskName' (SSID '$($network.Ssid)' -> $verb)"
}
