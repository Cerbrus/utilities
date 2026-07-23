# Installs the repo PowerShell profile for every installed PowerShell edition
# by writing (or appending to) a stub profile that dot-sources the repo file.
# No admin rights required. Idempotent: safe to run multiple times.

$ErrorActionPreference = 'Stop'

$repoProfile = Join-Path $PSScriptRoot 'Microsoft.PowerShell_profile.ps1'
if (-not (Test-Path -LiteralPath $repoProfile)) {
    Write-Error "Repo profile not found: $repoProfile"
    return
}

# Soft dependencies: the profile installs fine without them, but 'dev' needs both.
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Warning "'claude' CLI not found on PATH - 'dev' will fail to launch Claude Code until it is installed."
}
if (-not (Test-Path -LiteralPath 'C:\DEV')) {
    Write-Warning "'C:\DEV' does not exist - the dev picker expects project folders there."
}

$comment = '# utilities repo profile'
$dotSourceLine = ". '$repoProfile'"

$documents = [Environment]::GetFolderPath('MyDocuments')

# Detect installed editions and their profile paths.
$targets = @()
$targets += [pscustomobject]@{
    Edition = 'Windows PowerShell 5.1'
    Path    = Join-Path $documents 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
}

$pwshFound = $false
$pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
if ($pwshCommand) {
    $pwshFound = $true
} elseif (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')) {
    $pwshFound = $true
}
if ($pwshFound) {
    $targets += [pscustomobject]@{
        Edition = 'PowerShell 7+'
        Path    = Join-Path $documents 'PowerShell\Microsoft.PowerShell_profile.ps1'
    }
} else {
    Write-Host 'PowerShell 7+          : not detected, skipped' -ForegroundColor DarkGray
}

foreach ($target in $targets) {
    $label = $target.Edition.PadRight(22)
    $profilePath = $target.Path

    if (Test-Path -LiteralPath $profilePath) {
        $item = Get-Item -LiteralPath $profilePath -Force

        # Existing symlink pointing at the repo profile: leave it alone.
        if ($item.LinkType -eq 'SymbolicLink') {
            $linkTarget = @($item.Target) | Select-Object -First 1
            if ($linkTarget -and ([string]$linkTarget).TrimEnd('\') -ieq $repoProfile) {
                Write-Host "${label}: already installed (symlink) -> $profilePath"
                continue
            }
        }

        # Already dot-sourcing the repo profile?
        $content = Get-Content -LiteralPath $profilePath -Raw
        if ($null -eq $content) { $content = '' }
        if ($content.IndexOf($repoProfile, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            Write-Host "${label}: already installed -> $profilePath"
            continue
        }

        # Existing profile with other content: append the dot-source stub.
        $suffix = ''
        if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) { $suffix = "`r`n" }
        Add-Content -LiteralPath $profilePath -Value "$suffix$comment`r`n$dotSourceLine" -Encoding utf8
        Write-Host "${label}: appended -> $profilePath"
        continue
    }

    # No profile yet: create parent directory and stub.
    $parent = Split-Path -Parent $profilePath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Set-Content -LiteralPath $profilePath -Value "$comment`r`n$dotSourceLine" -Encoding utf8
    Write-Host "${label}: created -> $profilePath"
}
