<#
.SYNOPSIS
Installs the herdr customization in this repository.

.DESCRIPTION
Copies the terminal herdr config and the Herdr app layouts and mods from this
repository to where herdr reads them. Idempotent, non-elevated.

.PARAMETER Pull
Copy the other way: take the live files back into the repository, to commit
changes that were made in place.
#>
[CmdletBinding()]
param(
    [switch]$Pull
)

$ErrorActionPreference = 'Stop'

$appHome = Join-Path $HOME '.config\herdr-app'
if ($env:HERDR_APP_HOME) { $appHome = $env:HERDR_APP_HOME }
$terminalConfig = Join-Path $env:APPDATA 'herdr\config.toml'
if ($env:HERDR_CONFIG_PATH) { $terminalConfig = $env:HERDR_CONFIG_PATH }

$repoApp = Join-Path $PSScriptRoot 'app'
$pairs = @()
$pairs += [pscustomobject]@{ Repo = Join-Path $PSScriptRoot 'terminal\config.toml'; Live = $terminalConfig; Part = 'terminal' }
foreach ($file in Get-ChildItem -LiteralPath $repoApp -Recurse -File) {
    $relative = $file.FullName.Substring($repoApp.Length + 1)
    $pairs += [pscustomobject]@{ Repo = $file.FullName; Live = Join-Path $appHome $relative; Part = 'app' }
}

if ($Pull) {
    foreach ($mod in Get-ChildItem -LiteralPath (Join-Path $repoApp 'mods') -Directory) {
        $liveMod = Join-Path $appHome "mods\$($mod.Name)"
        if (-not (Test-Path -LiteralPath $liveMod)) { continue }
        $added = Get-ChildItem -LiteralPath $liveMod -File |
            Where-Object { $_.Extension -in '.js', '.json', '.svg' -and $_.Name -ne 'jsconfig.json' } |
            Where-Object { -not (Test-Path -LiteralPath (Join-Path $mod.FullName $_.Name)) }
        foreach ($file in $added) {
            $pairs += [pscustomobject]@{ Repo = Join-Path $mod.FullName $file.Name; Live = $file.FullName; Part = 'app' }
        }
    }
}

$skip = @{}
if (-not (Test-Path -LiteralPath (Split-Path -Parent $terminalConfig))) {
    Write-Host "Terminal herdr not found ($(Split-Path -Parent $terminalConfig)); skipping its config."
    $skip['terminal'] = $true
}
if (-not (Test-Path -LiteralPath $appHome)) {
    Write-Host "Herdr app not found ($appHome); skipping layouts and mods."
    $skip['app'] = $true
}

foreach ($pair in $pairs) {
    if ($skip[$pair.Part]) { continue }
    $from = $pair.Repo
    $to = $pair.Live
    if ($Pull) { $from = $pair.Live; $to = $pair.Repo }
    if (-not (Test-Path -LiteralPath $from)) {
        Write-Warning "Missing, skipped: $from"
        continue
    }
    $parent = Split-Path -Parent $to
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    if ((Test-Path -LiteralPath $to) -and (Get-FileHash -LiteralPath $from).Hash -eq (Get-FileHash -LiteralPath $to).Hash) {
        Write-Host "unchanged  $to"
        continue
    }
    Copy-Item -LiteralPath $from -Destination $to -Force
    Write-Host "copied     $to"
}

$keysPath = Join-Path $appHome 'keys.json'
if (-not $Pull -and -not $skip['app'] -and (Test-Path -LiteralPath $keysPath)) {
    $keys = [System.IO.File]::ReadAllText($keysPath)
    $bound = $keys.Replace('"ctrl-shift-n": "space.new"', '"ctrl-shift-n": "mod.open:space-open"')
    if ($bound -ne $keys) {
        [System.IO.File]::WriteAllText($keysPath, $bound)
        Write-Host "rebound    ctrl-shift-n to the space-open picker in $keysPath"
    }
}

if (-not $Pull) {
    Write-Host ''
    Write-Host 'Terminal herdr: run "herdr server reload-config" to apply config.toml.'
    Write-Host 'Herdr app: files apply at once; pick the layout with: herdr-app do layout.switch --name main-folders'
}
