function Select-DevFolder {
    param([string[]]$Options)
    $esc = [char]27
    $cap = [Math]::Max(3, [Math]::Min(10, [Console]::WindowHeight - 6))
    $maxVisible = [Math]::Min($Options.Count, $cap)
    $rows = $maxVisible + 2
    $selected = 0
    $offset = 0
    $filter = ''
    $numWidth = "$($Options.Count)".Length
    Write-Host ''
    for ($i = 0; $i -lt $rows; $i++) { Write-Host '' }
    $top = [Console]::CursorTop - $rows
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            $width = [Console]::WindowWidth - 1
            $filtered = @($Options | Where-Object { $_.IndexOf($filter, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
            $count = $filtered.Count
            if ($selected -ge $count) { $selected = [Math]::Max(0, $count - 1) }
            $visible = [Math]::Min($count, $maxVisible)
            if ($selected -lt $offset) { $offset = $selected }
            if ($selected -ge $offset + $visible) { $offset = $selected - $visible + 1 }
            if ($offset + $visible -gt $count) { $offset = [Math]::Max(0, $count - $visible) }
            for ($i = 0; $i -lt $maxVisible; $i++) {
                [Console]::SetCursorPosition(0, $top + $i)
                if ($i -ge $visible) { Write-Host (' ' * $width); continue }
                $idx = $offset + $i
                $num = "$($idx + 1)".PadLeft($numWidth)
                $text = "[$num] $($filtered[$idx])"
                if ($text.Length -gt $width - 2) { $text = $text.Substring(0, $width - 3) + [char]0x2026 }
                $line = $text.PadRight($width - 2)
                if ($idx -eq $selected) {
                    Write-Host "  $esc[48;2;34;92;43m$esc[38;2;255;255;255m$line$esc[0m"
                } else {
                    Write-Host "  $line"
                }
            }
            $status = if ($count -eq 0) {
                '  (no match)'
            } elseif ($count -gt $visible) {
                $left = if ($offset -gt 0) { [char]0x25C4 } else { ' ' }
                $right = if ($offset + $visible -lt $count) { [char]0x25BA } else { ' ' }
                '  {0} ({1}-{2} of {3}) {4}' -f $left, ($offset + 1), ($offset + $visible), $count, $right
            } else {
                ''
            }
            [Console]::SetCursorPosition(0, $top + $maxVisible)
            Write-Host $status.PadRight($width) -ForegroundColor DarkGray
            $filterText = if ($filter) { "  filter: $filter" } else { '' }
            [Console]::SetCursorPosition(0, $top + $maxVisible + 1)
            Write-Host $filterText.PadRight($width) -ForegroundColor DarkGray
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'    { if ($count) { $selected = ($selected + $count - 1) % $count } }
                'DownArrow'  { if ($count) { $selected = ($selected + 1) % $count } }
                { $_ -in 'PageUp', 'LeftArrow' }    { $selected = [Math]::Max(0, $selected - $visible) }
                { $_ -in 'PageDown', 'RightArrow' } { if ($count) { $selected = [Math]::Min($count - 1, $selected + $visible) } }
                'Home'       { $selected = 0 }
                'End'        { $selected = [Math]::Max(0, $count - 1) }
                'Enter'      { if ($count) { return $filtered[$selected] } }
                'Escape'     { if ($filter) { $filter = ''; $selected = 0; $offset = 0 } else { return $null } }
                'Backspace'  { if ($filter) { $filter = $filter.Substring(0, $filter.Length - 1); $selected = 0; $offset = 0 } }
                default {
                    $n = [int]$key.KeyChar - [int][char]'1'
                    if ($n -ge 0 -and $n -le 8) {
                        if ($n -lt $count) { return $filtered[$n] }
                    } elseif (-not [char]::IsControl($key.KeyChar)) {
                        $filter += $key.KeyChar
                        $selected = 0
                        $offset = 0
                    }
                }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
        [Console]::SetCursorPosition(0, $top + $rows)
    }
}

# Root folder for the dev picker; override with $env:DEV_ROOT.
function Get-DevRoot {
    if ($env:DEV_ROOT) { return $env:DEV_ROOT.TrimEnd('\') }
    return 'C:\DEV'
}

function Get-DevNestedFolders {
    $root = Get-DevRoot
    foreach ($parent in '~Cerbrus') {
        $dir = Join-Path $root $parent
        if (Test-Path -LiteralPath $dir -PathType Container) {
            Get-ChildItem -LiteralPath $dir -Directory | ForEach-Object { "$parent\$($_.Name)" }
        }
    }
}

function dev {
    param([string]$folder)
    $root = Get-DevRoot
    $base = $root
    $prefix = ''
    $leaf = $folder
    if ($folder) {
        # Nested paths ('proj/backend' or 'proj\backend'): resolve everything up to
        # the last separator as the base folder, match only on the leaf.
        $idx = $folder.LastIndexOfAny([char[]]('\', '/'))
        if ($idx -ge 0) {
            $prefix = $folder.Substring(0, $idx + 1) -replace '/', '\'
            $leaf = $folder.Substring($idx + 1)
            $base = Join-Path $root $prefix
            if (-not (Test-Path -LiteralPath $base -PathType Container)) {
                Write-Host ''
                Write-Host "No folder '$base'." -ForegroundColor Yellow
                return
            }
        }
    }
    $names = @(Get-ChildItem $base -Directory | Select-Object -ExpandProperty Name)
    $nested = if ($prefix) { @() } else { @(Get-DevNestedFolders) }
    $nestedExact = @($nested | Where-Object { (Split-Path $_ -Leaf) -eq $leaf })
    if (-not $folder) {
        $pick = Select-DevFolder (@('DEV root') + $names + $nested)
        if (-not $pick) { return }
        $path = if ($pick -eq 'DEV root') { $root } else { Join-Path $root $pick }
    } elseif (-not $leaf) {
        # Trailing separator ('dev proj/'): pick among that folder's subfolders.
        if (-not $names) {
            $path = $base
        } else {
            $pick = Select-DevFolder $names
            if (-not $pick) { return }
            $path = Join-Path $base $pick
        }
    } elseif ($names -contains $leaf) {
        $path = Join-Path $base $leaf
    } elseif ($nestedExact.Count -eq 1) {
        $path = Join-Path $base $nestedExact[0]
    } else {
        $suggestions = @(($names + $nested) |
            Where-Object { (Split-Path $_ -Leaf).IndexOf($leaf, [StringComparison]::OrdinalIgnoreCase) -ge 0 } |
            Sort-Object @{ Expression = { -not (Split-Path $_ -Leaf).StartsWith($leaf, 'OrdinalIgnoreCase') } }, { $_ })
        if ($suggestions.Count -eq 1) {
            Write-Host "Use '$prefix$($suggestions[0])'? (Y/n) " -NoNewline -ForegroundColor Cyan
            $key = [Console]::ReadKey($true)
            Write-Host ''
            if ($key.Key -notin 'Y', 'Enter') { return }
            $path = Join-Path $base $suggestions[0]
        } elseif ($suggestions) {
            Write-Host ''
            Write-Host "No folder '$(Join-Path $base $leaf)'. Pick:" -ForegroundColor Yellow
            $pick = Select-DevFolder $suggestions
            if (-not $pick) { return }
            $path = Join-Path $base $pick
        } else {
            Write-Host ''
            Write-Host "No folder '$(Join-Path $base $leaf)'." -ForegroundColor Yellow
            return
        }
    }
    Set-Location $path
    if ($env:HERDR_ENV -and $env:HERDR_WORKSPACE_ID) {
        try {
            $workspace = (& $env:HERDR_BIN_PATH workspace get $env:HERDR_WORKSPACE_ID | ConvertFrom-Json).result.workspace
            if ($workspace.pane_count -eq 1) {
                & $env:HERDR_BIN_PATH workspace rename $env:HERDR_WORKSPACE_ID (Split-Path $path -Leaf) | Out-Null
            }
        } catch {}
    }
    Clear-Host; claude
}
Set-Alias agent dev

Register-ArgumentCompleter -CommandName dev, agent -ParameterName folder -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    $prefix = ''
    $leaf = $wordToComplete
    $idx = $wordToComplete.LastIndexOfAny([char[]]('\', '/'))
    if ($idx -ge 0) {
        $prefix = $wordToComplete.Substring(0, $idx + 1)
        $leaf = $wordToComplete.Substring($idx + 1)
    }
    $base = Join-Path (Get-DevRoot) ($prefix -replace '/', '\')
    if (-not (Test-Path -LiteralPath $base -PathType Container)) { return }
    $items = @(Get-ChildItem -Path $base -Directory | ForEach-Object { "$prefix$($_.Name)" })
    if (-not $prefix) { $items += @(Get-DevNestedFolders | ForEach-Object { $_ -replace '\\', '/' }) }
    $items |
        Where-Object { (Split-Path $_ -Leaf) -like "*$leaf*" } |
        Sort-Object @{ Expression = { -not (Split-Path $_ -Leaf).StartsWith($leaf, 'OrdinalIgnoreCase') } }, { $_ } |
        ForEach-Object { if ($_ -match '\s') { "'$_'" } else { $_ } }
}
function Test-HerdrOnlyPaneInTab {
    if (-not ($env:HERDR_ENV -and $env:HERDR_TAB_ID -and $env:HERDR_BIN_PATH)) { return $false }
    try {
        $tab = (& $env:HERDR_BIN_PATH tab get $env:HERDR_TAB_ID | ConvertFrom-Json).result.tab
    } catch { return $false }
    return $tab.pane_count -eq 1
}

function Test-HerdrAppFirstTerminalInSpace {
    if (-not $env:HC_TERMINAL_ID) { return $false }
    if (-not (Get-Command hc -ErrorAction SilentlyContinue)) { return $false }
    try {
        $space = (hc get $env:HC_TERMINAL_ID --json | ConvertFrom-Json).labels.'herdr.space'
        if (-not $space) { return $false }
        $terminals = @((hc ls --json --label "herdr.space=$space" | ConvertFrom-Json).terminals)
    } catch { return $false }
    return $terminals.Count -eq 1
}

function Start-HerdrClaude {
    if ($env:CLAUDECODE -or $env:DEV_NO_AUTO_CLAUDE -or $env:DEV_AUTO_CLAUDE_STARTED) { return }
    $shellArgs = [Environment]::GetCommandLineArgs()
    if ($shellArgs -match '^-(noni|noninteractive)$') { return }
    if (($shellArgs -match '^-(c|command|f|file|e|ec|encodedcommand)$') -and -not ($shellArgs -match '^-(noe|noexit)$')) { return }
    if ($shellArgs -match '\bclaude\b') { return }
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { return }
    if (-not ((Test-HerdrOnlyPaneInTab) -or (Test-HerdrAppFirstTerminalInSpace))) { return }
    $env:DEV_AUTO_CLAUDE_STARTED = '1'
    claude
}
Start-HerdrClaude
