<#
.SYNOPSIS
Merges what a Herdr app update changed in its shipped mods and layouts into the clones in this repository.

.DESCRIPTION
Herdr replaces its own mods and layouts on every start and never updates clones.
The upstream folder holds each shipped file as it was when its clone was last
brought up to date. When a shipped file differs from that copy, the difference
is merged into the clone with a three-way merge (git merge-file), the copy in
upstream is renewed and the clone's cloned_from version is raised.

A clean merge is written to the clone. A merge with conflicts is written too,
with conflict markers; Install.ps1 does not copy such a file to the app.
Idempotent, non-elevated. Works on the repository copies only.

.PARAMETER Check
Report what changed and how it would merge, without writing anything.
#>
[CmdletBinding()]
param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

$appHome = Join-Path $HOME '.config\herdr-app'
if ($env:HERDR_APP_HOME) { $appHome = $env:HERDR_APP_HOME }
if (-not (Test-Path -LiteralPath $appHome)) {
    Write-Host "Herdr app not found ($appHome); skipping the upstream merge."
    return
}

$repoApp = Join-Path $PSScriptRoot 'app'
$upstream = Join-Path $PSScriptRoot 'upstream'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
$hasApp = [bool](Get-Command herdr-app -ErrorAction SilentlyContinue)

$appVersion = $null
if ($hasApp) {
    $reported = (& herdr-app --version | Select-Object -First 1)
    if ($reported -match '(\d+\.\d+\.\d+\S*)') { $appVersion = $Matches[1] }
}

function Read-Text([string]$Path) {
    return [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
}

function Write-Text([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Get-TrackedNames([string]$Folder) {
    if (-not (Test-Path -LiteralPath $Folder)) { return @() }
    return @(Get-ChildItem -LiteralPath $Folder -File |
        Where-Object { $_.Extension -in '.js', '.json', '.svg' -and $_.Name -ne 'jsconfig.json' } |
        ForEach-Object { $_.Name })
}

function Merge-Text([string]$Ours, [string]$Base, [string]$Theirs, [string]$OldLabel, [string]$NewLabel) {
    if ($Ours -eq $Base) { return [pscustomobject]@{ Text = $Theirs; Conflicts = 0; Failed = $false } }
    if ($Ours -eq $Theirs) { return [pscustomobject]@{ Text = $Ours; Conflicts = 0; Failed = $false } }
    if (-not $hasGit) { return [pscustomobject]@{ Text = $Ours; Conflicts = 0; Failed = $true } }
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("herdr-merge-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $oursFile = Join-Path $work 'ours'
        $baseFile = Join-Path $work 'base'
        $theirsFile = Join-Path $work 'theirs'
        Write-Text $oursFile $Ours
        Write-Text $baseFile $Base
        Write-Text $theirsFile $Theirs
        & git merge-file -L 'clone' -L $OldLabel -L $NewLabel $oursFile $baseFile $theirsFile | Out-Null
        $code = $LASTEXITCODE
        if ($code -lt 0 -or $code -ge 128) { return [pscustomobject]@{ Text = $Ours; Conflicts = 0; Failed = $true } }
        return [pscustomobject]@{ Text = (Read-Text $oursFile); Conflicts = $code; Failed = $false }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force
    }
}

$clones = @()
foreach ($mod in Get-ChildItem -LiteralPath (Join-Path $repoApp 'mods') -Directory) {
    $manifest = Join-Path $mod.FullName 'mod.json'
    if (-not (Test-Path -LiteralPath $manifest)) { continue }
    $from = (Read-Text $manifest | ConvertFrom-Json).cloned_from
    if (-not $from) { continue }
    $shipped = Join-Path $appHome "mods\$($from.name)"
    $base = Join-Path $upstream "mods\$($from.name)"
    $files = @()
    foreach ($name in @((Get-TrackedNames $shipped) + (Get-TrackedNames $base) | Sort-Object -Unique)) {
        $files += [pscustomobject]@{ Name = $name; Ours = Join-Path $mod.FullName $name; Base = Join-Path $base $name; Theirs = Join-Path $shipped $name }
    }
    $clones += [pscustomobject]@{
        Label = "mod $($mod.Name)"; Clone = $mod.Name; Origin = $from.name; Version = $from.version; Manifest = $manifest
        Folder = $mod.FullName; Seeded = (Test-Path -LiteralPath $base); Found = (Test-Path -LiteralPath $shipped); Files = $files
    }
}
foreach ($layout in Get-ChildItem -LiteralPath (Join-Path $repoApp 'layouts') -File -Filter '*.json') {
    $from = (Read-Text $layout.FullName | ConvertFrom-Json).cloned_from
    if (-not $from) { continue }
    $shipped = Join-Path $appHome "layouts\$($from.name).json"
    $base = Join-Path $upstream "layouts\$($from.name).json"
    $clones += [pscustomobject]@{
        Label = "layout $($layout.BaseName)"; Clone = $null; Origin = $from.name; Version = $from.version; Manifest = $layout.FullName
        Folder = $null; Seeded = (Test-Path -LiteralPath $base); Found = (Test-Path -LiteralPath $shipped)
        Files = @([pscustomobject]@{ Name = $layout.Name; Ours = $layout.FullName; Base = $base; Theirs = $shipped })
    }
}

$conflicted = @()
$unmerged = @()
$quiet = $true

foreach ($clone in $clones) {
    if (-not $clone.Found) {
        Write-Warning "$($clone.Label): Herdr no longer ships '$($clone.Origin)'; nothing to merge from."
        $quiet = $false
        continue
    }
    $rename = { param($text) $text }
    if ($clone.Clone) {
        $origin = $clone.Origin
        $name = $clone.Clone
        $rename = { param($text) $text.Replace("mods/$origin/", "mods/$name/").Replace("mod: `"$origin`"", "mod: `"$name`"") }.GetNewClosure()
    }
    $touched = $false
    $blocked = $false
    foreach ($file in $clone.Files) {
        $hasBase = Test-Path -LiteralPath $file.Base
        $hasTheirs = Test-Path -LiteralPath $file.Theirs
        $hasOurs = Test-Path -LiteralPath $file.Ours

        if (-not $hasTheirs) {
            Write-Host "removed    $($clone.Label): Herdr dropped $($file.Name); the clone keeps its copy"
            $quiet = $false
            if (-not $Check) { Remove-Item -LiteralPath $file.Base -Force }
            $touched = $true
            continue
        }
        $theirs = Read-Text $file.Theirs
        if (-not $hasBase) {
            if ($clone.Seeded) {
                Write-Host "new        $($clone.Label): Herdr added $($file.Name)"
                $quiet = $false
                if (-not $Check -and -not $hasOurs) { Write-Text $file.Ours (& $rename $theirs) }
                $touched = $true
            } else {
                Write-Host "stored     $($clone.Label): $($file.Name) as shipped in $($clone.Version)"
                $quiet = $false
            }
            if (-not $Check) { Write-Text $file.Base $theirs }
            continue
        }
        $base = Read-Text $file.Base
        if ($base -eq $theirs) { continue }

        $quiet = $false
        $touched = $true
        if ($file.Name -eq 'mod.json' -and $clone.Clone) {
            Write-Warning "$($clone.Label): Herdr changed mod.json of '$($clone.Origin)'; compare it with the clone's by hand."
            if (-not $Check) { Write-Text $file.Base $theirs }
            continue
        }
        if (-not $hasOurs) {
            Write-Host "changed    $($clone.Label): $($file.Name) changed upstream; the clone has no such file"
            if (-not $Check) { Write-Text $file.Base $theirs }
            continue
        }
        $merged = Merge-Text (Read-Text $file.Ours) (& $rename $base) (& $rename $theirs) "shipped $($clone.Version)" "shipped $appVersion"
        if ($merged.Failed) {
            Write-Warning "$($clone.Label): $($file.Name) changed upstream and could not be merged (git is needed). Left as it was."
            $unmerged += $file.Ours
            $blocked = $true
            continue
        }
        if ($merged.Conflicts) {
            Write-Warning "$($clone.Label): $($file.Name) merged with $($merged.Conflicts) conflict(s)."
            $conflicted += $file.Ours
        } else {
            Write-Host "merged     $($clone.Label): $($file.Name)"
        }
        if (-not $Check) {
            Write-Text $file.Ours $merged.Text
            Write-Text $file.Base $theirs
        }
    }

    if ($Check -or -not $touched -or $blocked) { continue }
    if ($appVersion -and $appVersion -ne $clone.Version) {
        $manifest = Read-Text $clone.Manifest
        $pattern = '("cloned_from"\s*:\s*\{[^}]*"version"\s*:\s*")[^"]*(")'
        $raised = [regex]::Replace($manifest, $pattern, ('${1}' + $appVersion + '${2}'))
        if ($raised -ne $manifest) {
            Write-Text $clone.Manifest $raised
            Write-Host "version    $($clone.Label): cloned_from $($clone.Version) -> $appVersion"
        }
    }
    if ($clone.Folder -and $hasApp -and -not ($conflicted | Where-Object { $_.StartsWith($clone.Folder) })) {
        & herdr-app check $clone.Folder | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warning "$($clone.Label): herdr-app check fails after the merge. Run: herdr-app check `"$($clone.Folder)`"" }
    }
}

if ($quiet) {
    Write-Host "Herdr's shipped mods and layouts are unchanged since the clones were last brought up to date ($($clones.Count) clones)."
    return
}
if ($conflicted.Count) {
    Write-Warning 'Resolve the <<<<<<< markers in these files, then run Install.ps1 again:'
    foreach ($path in $conflicted) { Write-Warning "  $path" }
}
if ($Check) {
    Write-Host 'Check only: nothing was written.'
} elseif (-not $unmerged.Count -and -not $conflicted.Count) {
    Write-Host 'Clones are up to date with the shipped files. Review the changes with git diff, then try the mods in the app.'
}
