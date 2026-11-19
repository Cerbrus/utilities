<#
.SYNOPSIS
Installs the Herdr app mods from the herdr-mods repository.

.DESCRIPTION
The mods live in their own repository, https://github.com/Cerbrus/herdr-mods.
This clones it next to this repository (or pulls it when it is already there)
and runs its Install.ps1. Idempotent, non-elevated.

Set HERDR_MODS_DIR to keep the clone somewhere else.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$url = 'https://github.com/Cerbrus/herdr-mods.git'
$repo = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'herdr-mods'
if ($env:HERDR_MODS_DIR) { $repo = $env:HERDR_MODS_DIR }

$appHome = Join-Path $HOME '.config\herdr-app'
if ($env:HERDR_APP_HOME) { $appHome = $env:HERDR_APP_HOME }
if (-not (Test-Path -LiteralPath $appHome)) {
    Write-Host "Herdr app not found ($appHome); skipping herdr-mods."
    return
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host 'git not found; skipping herdr-mods.'
    return
}

if (Test-Path -LiteralPath (Join-Path $repo '.git')) {
    Write-Host "Updating $repo..."
    git -C $repo pull --ff-only
    if ($LASTEXITCODE -ne 0) { Write-Warning 'git pull failed; installing from the current checkout.' }
} elseif (Test-Path -LiteralPath $repo) {
    Write-Warning "$repo exists but is not a git repository; skipping herdr-mods."
    return
} else {
    Write-Host "Cloning $url to $repo..."
    git clone $url $repo
    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'git clone failed; skipping herdr-mods.'
        return
    }
}

& (Join-Path $repo 'Install.ps1')
