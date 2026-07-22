function Select-DevFolder {
    param([string[]]$Options)
    $count = $Options.Count
    $cap = [Math]::Max(3, [Math]::Min(10, [Console]::WindowHeight - 5))
    $visible = [Math]::Min($count, $cap)
    $rows = $visible + [int]($count -gt $visible)
    $selected = 0
    $offset = 0
    $numWidth = "$count".Length
    Write-Host ''
    for ($i = 0; $i -lt $rows; $i++) { Write-Host '' }
    $top = [Console]::CursorTop - $rows
    $width = [Console]::WindowWidth - 1
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            if ($selected -lt $offset) { $offset = $selected }
            if ($selected -ge $offset + $visible) { $offset = $selected - $visible + 1 }
            for ($i = 0; $i -lt $visible; $i++) {
                $idx = $offset + $i
                [Console]::SetCursorPosition(0, $top + $i)
                $num = "$($idx + 1)".PadLeft($numWidth)
                $line = "[$num] $($Options[$idx])".PadRight($width - 2)
                if ($idx -eq $selected) {
                    $esc = [char]27
                    Write-Host "  $esc[48;2;34;92;43m$esc[38;2;255;255;255m$line$esc[0m"
                } else {
                    Write-Host "  $line"
                }
            }
            if ($count -gt $visible) {
                $left = if ($offset -gt 0) { [char]0x25C4 } else { ' ' }
                $right = if ($offset + $visible -lt $count) { [char]0x25BA } else { ' ' }
                [Console]::SetCursorPosition(0, $top + $visible)
                Write-Host ("  {0} ({1}-{2} of {3}) {4}" -f $left, ($offset + 1), ($offset + $visible), $count, $right).PadRight($width) -ForegroundColor DarkGray
            }
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { $selected = ($selected + $count - 1) % $count }
                'DownArrow' { $selected = ($selected + 1) % $count }
                'PageUp'     { $selected = [Math]::Max(0, $selected - $visible) }
                'PageDown'   { $selected = [Math]::Min($count - 1, $selected + $visible) }
                'LeftArrow'  { $selected = [Math]::Max(0, $selected - $visible) }
                'RightArrow' { $selected = [Math]::Min($count - 1, $selected + $visible) }
                'Home'      { $selected = 0 }
                'End'       { $selected = $count - 1 }
                'Enter'     { return $Options[$selected] }
                'Escape'    { return $null }
                default {
                    $n = [int]$key.KeyChar - [int][char]'1'
                    if ($n -ge 0 -and $n -lt $count) { return $Options[$n] }
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
    $path = "C:\DEV\$folder"
    if (-not $folder) {
        $options = @('DEV root') + @(Get-ChildItem "C:\DEV" -Directory | Select-Object -ExpandProperty Name)
        $pick = Select-DevFolder $options
        if (-not $pick) { return }
        $path = if ($pick -eq 'DEV root') { 'C:\DEV' } else { "C:\DEV\$pick" }
    } elseif (-not (Test-Path $path -PathType Container)) {
        $suggestions = @(Get-ChildItem "C:\DEV" -Directory -Filter "*$folder*" | Select-Object -ExpandProperty Name)
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