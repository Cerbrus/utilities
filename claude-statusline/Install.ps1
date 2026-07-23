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

# PS 5.1's ConvertTo-Json mangles formatting (BOM, 4-space alignment indent,
# double-space after colons, \uXXXX escapes), so serialize by hand: 2-space
# indent, property order preserved, non-ASCII kept literal.
function ConvertTo-OrderedJson {
    param($Value, [int]$Depth = 0)
    $pad = '  ' * $Depth
    $childPad = '  ' * ($Depth + 1)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } return 'false' }
    if ($Value -is [string]) {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('"')
        foreach ($ch in $Value.ToCharArray()) {
            switch ($ch) {
                '"'  { [void]$sb.Append('\"') }
                '\'  { [void]$sb.Append('\\') }
                "`b" { [void]$sb.Append('\b') }
                "`f" { [void]$sb.Append('\f') }
                "`n" { [void]$sb.Append('\n') }
                "`r" { [void]$sb.Append('\r') }
                "`t" { [void]$sb.Append('\t') }
                default {
                    if ([char]::IsControl($ch)) { [void]$sb.AppendFormat('\u{0:x4}', [int]$ch) }
                    else { [void]$sb.Append($ch) }
                }
            }
        }
        [void]$sb.Append('"')
        return $sb.ToString()
    }
    if ($Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject]) {
        if ($Value -is [System.Collections.IDictionary]) {
            $props = @($Value.GetEnumerator() | ForEach-Object { @{ Name = $_.Key; Value = $_.Value } })
        } else {
            $props = @($Value.PSObject.Properties | ForEach-Object { @{ Name = $_.Name; Value = $_.Value } })
        }
        if ($props.Count -eq 0) { return '{}' }
        $lines = foreach ($p in $props) {
            $childPad + (ConvertTo-OrderedJson $p.Name) + ': ' + (ConvertTo-OrderedJson $p.Value ($Depth + 1))
        }
        return "{`n" + ($lines -join ",`n") + "`n$pad}"
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @($Value)
        if ($items.Count -eq 0) { return '[]' }
        $lines = foreach ($item in $items) { $childPad + (ConvertTo-OrderedJson $item ($Depth + 1)) }
        return "[`n" + ($lines -join ",`n") + "`n$pad]"
    }
    # Numbers (int/long/double/decimal from ConvertFrom-Json).
    return $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
}

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
# WriteAllText writes UTF-8 without BOM (unlike Set-Content -Encoding utf8).
[System.IO.File]::WriteAllText($settingsPath, (ConvertTo-OrderedJson $settings) + "`n")
Write-Host "Status line configured in $settingsPath"
Write-Host "  -> $scriptPath"
