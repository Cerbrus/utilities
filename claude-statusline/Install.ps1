<#
.SYNOPSIS
    Points Claude Code's status line at this repo's pr-statusline.ps1.
.DESCRIPTION
    Updates the statusLine entry in Claude Code's settings.json (respecting
    $env:CLAUDE_CONFIG_DIR, defaulting to ~\.claude). Other settings are
    preserved. Idempotent - re-running with an already-correct entry changes
    nothing. No admin required.
#>
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'pr-statusline.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
    Write-Error "Status line script not found: $scriptPath"
    return
}

$claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$settingsPath = Join-Path $claudeDir 'settings.json'

# Forward slashes survive the JSON escaping in settings.json more readably.
$command = "powershell -ExecutionPolicy Bypass -File `"$($scriptPath -replace '\\', '/')`""

if (Test-Path -LiteralPath $settingsPath) {
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
} else {
    if (-not (Test-Path -LiteralPath $claudeDir)) {
        New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
    }
    $settings = [pscustomobject]@{}
}

$current = $null
if ($settings.PSObject.Properties['statusLine']) {
    $current = $settings.statusLine.command
}
if ($current -eq $command) {
    Write-Host "Status line already configured -> $scriptPath"
    return
}

$statusLine = [pscustomobject]@{ type = 'command'; command = $command }
$settings | Add-Member -NotePropertyName statusLine -NotePropertyValue $statusLine -Force
ConvertTo-Json $settings -Depth 50 | Set-Content -LiteralPath $settingsPath -Encoding utf8
Write-Host "Status line configured in $settingsPath"
Write-Host "  -> $scriptPath"
