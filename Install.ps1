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

if ($repoRoot -ne 'C:\DEV\~Cerbrus\utilities') {
    Write-Warning "Repository is at '$repoRoot' instead of 'C:\DEV\~Cerbrus\utilities'. Installers use absolute paths, so moving the repo later requires re-running this script."
}

# Self-update; a failed pull (offline, local changes) is not fatal.
if (Test-Path (Join-Path $repoRoot '.git')) {
    Write-Host "Updating repository..."
    git -C $repoRoot pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "git pull failed; continuing with the current checkout."
    }
}

# Claude Code is needed by powershell-profile ('dev' launches it) and claude-statusline.
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "Claude Code ('claude') is not installed."
    $answer = Read-Host "Install it now via the official installer (irm https://claude.ai/install.ps1 | iex)? [Y/n]"
    if ($answer -eq '' -or $answer -match '^[yY]') {
        Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
        Write-Host "Note: 'claude' may only be on PATH in new shells. Start it once so it creates its settings file, then re-run this script if claude-statusline was skipped."
    } else {
        Write-Warning "Skipping Claude Code install; the 'dev' command and claude-statusline need it."
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
