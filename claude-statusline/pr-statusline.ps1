[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Esc = [char]27
$Reset = "$Esc[0m"
$Dim = "$Esc[2m"
$ColorBranch = "$Esc[38;5;114m"
$ColorModel = "$Esc[38;5;110m"
$ColorLabel = "$Esc[38;5;250m"
$ColorCaveman = "$Esc[38;5;172m"
$Sep = " ${Dim}|${Reset} "

# --- helpers -------------------------------------------------------------

# Green -> yellow -> red ramp across 0..100% (256-color cube: 16 + 36r + 6g + b).
function Get-RampColor([double]$Pct) {
    $t = [math]::Max(0.0, [math]::Min(1.0, $Pct / 100.0))
    if ($t -le 0.5) { $r = [int][math]::Round($t * 2 * 5); $g = 5 }
    else { $r = 5; $g = [int][math]::Round((1 - ($t - 0.5) * 2) * 5) }
    $code = 16 + 36 * $r + 6 * $g
    return "$Esc[38;5;${code}m"
}

# Filled portion in the ramp color, empty portion dim.
function Get-Bar([double]$Pct, [int]$Width = 8) {
    $p = [math]::Max(0.0, [math]::Min(100.0, $Pct))
    $fill = [int][math]::Round($Width * $p / 100.0)
    if ($fill -gt $Width) { $fill = $Width }
    $color = Get-RampColor $p
    $filled = ('#' * $fill) -replace '#', ([char]0x2588)
    $empty = ('#' * ($Width - $fill)) -replace '#', ([char]0x2591)
    return "${color}${filled}${Reset}${Dim}${empty}${Reset}"
}

function Get-PlainBar([double]$Pct, [int]$Width = 8) {
    $p = [math]::Max(0.0, [math]::Min(100.0, $Pct))
    $fill = [math]::Min($Width, [int][math]::Round($Width * $p / 100.0))
    return ([string][char]0x2588) * $fill + ([string][char]0x2591) * ($Width - $fill)
}

function Format-Tokens([double]$N) {
    if ($N -ge 1000000) { return ('{0:0.#}M' -f ($N / 1000000)) }
    if ($N -ge 1000) { return ('{0:0}k' -f ($N / 1000)) }
    return [string][int]$N
}

# Compact time-until-reset from a unix-epoch-seconds value ("" if past/absent).
function Format-Reset($Unix) {
    if ($null -eq $Unix) { return "" }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $diff = [long]$Unix - $now
    if ($diff -le 0) { return "" }
    if ($diff -ge 3600) { return ('{0}h' -f [math]::Floor($diff / 3600)) }
    return ('{0}m' -f [math]::Floor($diff / 60))
}

# --- input ---------------------------------------------------------------

$StdinRaw = [Console]::In.ReadToEnd()

$Data = $null
if ($StdinRaw) {
    try { $Data = $StdinRaw | ConvertFrom-Json -ErrorAction Stop } catch { $Data = $null }
}

$Segments = New-Object System.Collections.Generic.List[string]

# 1. Git branch of the current workspace dir (omitted if not a git repo)
if ($Data) {
    $Dir = $null
    if ($Data.workspace -and $Data.workspace.current_dir) { $Dir = $Data.workspace.current_dir }
    elseif ($Data.cwd) { $Dir = $Data.cwd }

    if ($Dir -and (Test-Path -LiteralPath $Dir)) {
        try {
            $BranchRaw = git -C "$Dir" --no-optional-locks rev-parse --abbrev-ref HEAD 2>$null
            if ($LASTEXITCODE -eq 0 -and $BranchRaw) {
                $Branch = ([string]$BranchRaw).Trim()
                if ($Branch -eq "HEAD") {
                    $ShortRaw = git -C "$Dir" --no-optional-locks rev-parse --short HEAD 2>$null
                    if ($LASTEXITCODE -eq 0 -and $ShortRaw) { $Branch = ([string]$ShortRaw).Trim() }
                }
                if ($Branch) { $Segments.Add("${ColorBranch}$Branch${Reset}") }
            }
        } catch {}
    }
}

# 2. Model display name
if ($Data -and $Data.model -and $Data.model.display_name) {
    $Segments.Add("${ColorModel}$($Data.model.display_name)${Reset}")
}

# 3. Context window: bar + percent + used/total tokens
if ($Data -and $Data.context_window) {
    $Cw = $Data.context_window
    $Pct = $null
    if ($null -ne $Cw.used_percentage) {
        $Pct = [double]$Cw.used_percentage
    } elseif ($Cw.context_window_size -and [double]$Cw.context_window_size -gt 0 -and $null -ne $Cw.total_input_tokens) {
        $Pct = ([double]$Cw.total_input_tokens / [double]$Cw.context_window_size) * 100
    }
    if ($null -ne $Pct) {
        $rc = Get-RampColor $Pct
        $tokPart = ""
        if ($null -ne $Cw.total_input_tokens -and $Cw.context_window_size) {
            $used = Format-Tokens ([double]$Cw.total_input_tokens)
            $total = Format-Tokens ([double]$Cw.context_window_size)
            $tokPart = " ${Dim}${used}/${total}${Reset}"
        }
        $Segments.Add("${ColorLabel}Ctx${Reset} $(Get-Bar $Pct) ${rc}$([math]::Round($Pct))%${Reset}${tokPart}")
    }
}

# 4. Session rate limits: 5-hour and 7-day usage, each with a bar + reset countdown
if ($Data -and $Data.rate_limits) {
    $rl = $Data.rate_limits
    foreach ($lim in @(
            @{ Key = $rl.five_hour; Label = '5h' },
            @{ Key = $rl.seven_day; Label = '7d' })) {
        $obj = $lim.Key
        if ($obj -and $null -ne $obj.used_percentage) {
            $p = [double]$obj.used_percentage
            $rc = Get-RampColor $p
            $resetTxt = Format-Reset $obj.resets_at
            $resetPart = if ($resetTxt) { " ${Dim}${resetTxt}${Reset}" } else { "" }
            $Segments.Add("${ColorLabel}$($lim.Label)${Reset} $(Get-Bar $p) ${rc}$([math]::Round($p))%${Reset}${resetPart}")
        }
    }
}

# 5. Caveman mode - mirrors detection/validation from caveman-statusline.ps1.
#    Shows the mode explicitly for every active level, including FULL.
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
$Flag = Join-Path $ClaudeDir ".caveman-active"
if (Test-Path -LiteralPath $Flag) {
    try {
        $Item = Get-Item -LiteralPath $Flag -Force -ErrorAction Stop
        if (-not ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and $Item.Length -le 64) {
            $Raw = Get-Content -LiteralPath $Flag -TotalCount 1 -ErrorAction Stop
            $Mode = ""
            if ($null -ne $Raw) { $Mode = ([string]$Raw).Trim() }
            $Mode = $Mode.ToLowerInvariant()
            $Mode = ($Mode -replace '[^a-z0-9-]', '')
            $Valid = @('off','lite','full','ultra','wenyan-lite','wenyan','wenyan-full','wenyan-ultra','commit','review','compress')
            if ([string]::IsNullOrEmpty($Mode)) { $Mode = 'full' }
            if ($Valid -contains $Mode -and $Mode -ne 'off') {
                $Segments.Add("${ColorCaveman}[CAVEMAN:$($Mode.ToUpperInvariant())]${Reset}")
            }
        }
    } catch {}
}

if ($Data -and $env:HERDR_ENV -and $env:HERDR_PANE_ID -and $env:HERDR_BIN_PATH) {
    $HerdrTokens = New-Object System.Collections.Generic.List[string]
    if ($Data.model -and $Data.model.display_name) {
        $HerdrTokens.Add("model=$($Data.model.display_name)")
    }
    if ($Data.context_window -and $null -ne $Data.context_window.used_percentage) {
        $CtxPct = [double]$Data.context_window.used_percentage
        $HerdrTokens.Add("ctx=ctx $(Get-PlainBar $CtxPct 5) $([math]::Round($CtxPct))%")
    }
    if ($HerdrTokens.Count) {
        $HerdrArgs = @('pane', 'report-metadata', $env:HERDR_PANE_ID, '--source', 'claude-statusline')
        foreach ($Token in $HerdrTokens) { $HerdrArgs += @('--token', $Token) }
        try { & $env:HERDR_BIN_PATH @HerdrArgs 2>$null | Out-Null } catch {}
    }
}

[Console]::Write(($Segments -join $Sep))
