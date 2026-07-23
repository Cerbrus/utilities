<#
.SYNOPSIS
Installs all utilities in this repository.

.DESCRIPTION
Updates the repository (git pull), then discovers and runs every
<utility-folder>\Install.ps1. Idempotent - safe to re-run at any time
to update an existing installation.

Runs non-elevated; individual installers must not require admin.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot

Write-Host "== utilities installer =="

if ($repoRoot -ne 'C:\DEV\utilities') {
    Write-Warning "Repository is at '$repoRoot' instead of 'C:\DEV\utilities'. Installers use absolute paths, so moving the repo later requires re-running this script."
}

# Self-update; a failed pull (offline, local changes) is not fatal.
if (Test-Path (Join-Path $repoRoot '.git')) {
    Write-Host "Updating repository..."
    git -C $repoRoot pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "git pull failed; continuing with the current checkout."
    }
}

# Discover per-utility installers (any direct subfolder containing Install.ps1).
$installers = Get-ChildItem -Path $repoRoot -Directory |
    ForEach-Object { Join-Path $_.FullName 'Install.ps1' } |
    Where-Object { Test-Path $_ }

if (-not $installers) {
    Write-Warning "No utility installers found."
    return
}

$failed = @()
foreach ($installer in $installers) {
    $name = Split-Path (Split-Path $installer -Parent) -Leaf
    Write-Host ""
    Write-Host "-- $name --"
    try {
        & $installer
    } catch {
        Write-Warning "$name failed: $_"
        $failed += $name
    }
}

Write-Host ""
if ($failed) {
    Write-Warning ("Done, with failures: {0}" -f ($failed -join ', '))
} else {
    Write-Host "Done. All utilities installed."
}
