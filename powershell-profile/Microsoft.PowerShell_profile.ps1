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

function dev {
    param([string]$folder)
    $names = @(Get-ChildItem "C:\DEV" -Directory | Select-Object -ExpandProperty Name)
    $path = "C:\DEV\$folder"
    if (-not $folder) {
        $pick = Select-DevFolder (@('DEV root') + $names)
        if (-not $pick) { return }
        $path = if ($pick -eq 'DEV root') { 'C:\DEV' } else { "C:\DEV\$pick" }
    } elseif ($names -notcontains $folder) {
        $suggestions = @($names |
            Where-Object { $_.IndexOf($folder, [StringComparison]::OrdinalIgnoreCase) -ge 0 } |
            Sort-Object @{ Expression = { -not $_.StartsWith($folder, 'OrdinalIgnoreCase') } }, { $_ })
        if ($suggestions.Count -eq 1) {
            Write-Host "Use '$($suggestions[0])'? (Y/n) " -NoNewline -ForegroundColor Cyan
            $key = [Console]::ReadKey($true)
            Write-Host ''
            if ($key.Key -notin 'Y', 'Enter') { return }
            $path = "C:\DEV\$($suggestions[0])"
        } elseif ($suggestions) {
            Write-Host ''
            Write-Host "No folder 'C:\DEV\$folder'. Pick:" -ForegroundColor Yellow
            $pick = Select-DevFolder $suggestions
            if (-not $pick) { return }
            $path = "C:\DEV\$pick"
        } else {
            Write-Host ''
            Write-Host "No folder 'C:\DEV\$folder'." -ForegroundColor Yellow
            return
        }
    }
    Set-Location $path; Clear-Host; claude
}
Set-Alias agent dev

Register-ArgumentCompleter -CommandName dev, agent -ParameterName folder -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    Get-ChildItem -Path "C:\DEV\" -Directory |
        Where-Object { $_.Name -like "*$wordToComplete*" } |
        Sort-Object @{ Expression = { -not $_.Name.StartsWith($wordToComplete, 'OrdinalIgnoreCase') } }, Name |
        ForEach-Object { $_.Name }
}