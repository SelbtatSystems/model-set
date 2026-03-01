# model-set Uninstall Script for Windows
# Reverses everything done by setup.ps1
# Usage: .\scripts\uninstall.ps1 [-Force]

param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir
$HomeDir = $env:USERPROFILE
$CurrentDir = Get-Location

Write-Host "model-set Uninstall" -ForegroundColor Cyan
Write-Host "===================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will remove all configs, symlinks, and CLI tools installed by setup.ps1."
Write-Host "Repo directory: $RepoDir"
Write-Host ""

if (-not $Force) {
    $confirm = Read-Host "Continue? [y/N]"
    if ($confirm -notmatch "^[Yy]$") {
        Write-Host "Aborted."
        exit 0
    }
    Write-Host ""
}

# Helper: check if a path is a symlink/junction pointing into this repo
function Test-RepoLink {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    $item = Get-Item $Path -Force
    if ($item.LinkType -eq "SymbolicLink" -or $item.LinkType -eq "Junction") {
        $target = $item.Target
        # Target can be an array on some PS versions
        if ($target -is [array]) { $target = $target[0] }
        return $target -like "$RepoDir*"
    }
    return $false
}

# Helper: remove a symlink/junction only if it points into this repo, restore backup
function Remove-RepoLink {
    param([string]$Link)
    if (-not (Test-Path $Link)) {
        Write-Host "  Skipped: $Link (not found)" -ForegroundColor Yellow
        return $false
    }
    $item = Get-Item $Link -Force
    if ($item.LinkType -eq "SymbolicLink" -or $item.LinkType -eq "Junction") {
        $target = $item.Target
        if ($target -is [array]) { $target = $target[0] }
        if ($target -like "$RepoDir*") {
            $item.Delete()
            Write-Host "  Removed symlink: $Link -> $target" -ForegroundColor Green

            # Restore backup if it exists
            $backup = "${Link}.backup"
            if (Test-Path $backup) {
                Move-Item $backup $Link -Force
                Write-Host "  Restored: ${backup} -> $Link" -ForegroundColor Green
            }
            return $true
        } else {
            Write-Host "  Skipped: $Link -> $target (not pointing to this repo)" -ForegroundColor Yellow
            return $false
        }
    } else {
        Write-Host "  Skipped: $Link (not a symlink)" -ForegroundColor Yellow
        return $false
    }
}

# =====================================================
# 1. Generated config files
# =====================================================
Write-Host "Removing generated config files..." -ForegroundColor Yellow

$McpOutput = Join-Path $HomeDir ".mcp.json"
if (Test-Path $McpOutput) {
    Remove-Item $McpOutput -Force
    Write-Host "  Removed: ~/.mcp.json" -ForegroundColor Green
} else {
    Write-Host "  Skipped: ~/.mcp.json (not found)" -ForegroundColor Yellow
}

$CodexConfig = Join-Path $RepoDir "global\codex\config.toml"
if (Test-Path $CodexConfig) {
    Remove-Item $CodexConfig -Force
    Write-Host "  Removed: global\codex\config.toml" -ForegroundColor Green
} else {
    Write-Host "  Skipped: global\codex\config.toml (not found)" -ForegroundColor Yellow
}

Write-Host ""

# =====================================================
# 2. MCP servers
# =====================================================
Write-Host "Removing MCP servers..." -ForegroundColor Yellow

if (Get-Command claude -ErrorAction SilentlyContinue) {
    try {
        claude mcp remove stitch -s user 2>$null
        Write-Host "  Removed stitch from Claude Code (user scope)" -ForegroundColor Green
    } catch {
        Write-Host "  Skipped: stitch not found in Claude Code" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Skipped: claude not installed" -ForegroundColor Yellow
}

$GeminiStitch = Join-Path $HomeDir ".gemini\extensions\Stitch"
if (Test-Path $GeminiStitch) {
    Remove-Item $GeminiStitch -Recurse -Force
    Write-Host "  Removed: ~/.gemini/extensions/Stitch" -ForegroundColor Green
} else {
    Write-Host "  Skipped: ~/.gemini/extensions/Stitch (not found)" -ForegroundColor Yellow
}

Write-Host ""

# =====================================================
# 3. Home directory symlinks
# =====================================================
Write-Host "Removing home directory symlinks..." -ForegroundColor Yellow

foreach ($tool in @(".claude", ".gemini", ".opencode", ".codex")) {
    $link = Join-Path $HomeDir $tool

    if (-not (Test-Path $link)) {
        Write-Host "  Skipped: $link (not found)" -ForegroundColor Yellow
        continue
    }

    $item = Get-Item $link -Force
    if ($item.LinkType -eq "SymbolicLink" -or $item.LinkType -eq "Junction") {
        # Case 1: entire dir is a symlink/junction to repo
        Remove-RepoLink -Link $link | Out-Null
    } else {
        # Case 2: real dir with skills-only symlink inside
        $skillsLink = Join-Path $link "skills"
        if (Test-Path $skillsLink) {
            $skillsItem = Get-Item $skillsLink -Force
            if ($skillsItem.LinkType -eq "SymbolicLink" -or $skillsItem.LinkType -eq "Junction") {
                Remove-RepoLink -Link $skillsLink | Out-Null
            }
        }
    }
}

Write-Host ""

# =====================================================
# 4. Copied files (context-monitor in real ~/.claude)
# =====================================================
Write-Host "Removing copied files..." -ForegroundColor Yellow

$claudeDir = Join-Path $HomeDir ".claude"
$contextMonitor = Join-Path $claudeDir "scripts\context-monitor.py"
$isRealDir = $false
if (Test-Path $claudeDir) {
    $item = Get-Item $claudeDir -Force
    $isRealDir = (-not $item.LinkType)
}

if ($isRealDir -and (Test-Path $contextMonitor)) {
    Remove-Item $contextMonitor -Force
    Write-Host "  Removed: $contextMonitor" -ForegroundColor Green
    # Remove scripts dir if empty
    $scriptsDir = Join-Path $claudeDir "scripts"
    if ((Test-Path $scriptsDir) -and @(Get-ChildItem $scriptsDir).Count -eq 0) {
        Remove-Item $scriptsDir -Force
        Write-Host "  Removed empty dir: ~/.claude/scripts" -ForegroundColor Green
    }
} else {
    Write-Host "  Skipped: context-monitor.py (not found or ~/.claude is a symlink)" -ForegroundColor Yellow
}

Write-Host ""

# =====================================================
# 5. Repo-internal skills/agents symlinks
# =====================================================
Write-Host "Removing repo-internal symlinks..." -ForegroundColor Yellow

foreach ($tool in @("claude", "gemini", "opencode", "codex")) {
    $link = Join-Path $RepoDir "global\$tool\skills"
    if (Test-Path $link) {
        $item = Get-Item $link -Force
        if ($item.LinkType -eq "SymbolicLink" -or $item.LinkType -eq "Junction") {
            $item.Delete()
            Write-Host "  Removed: global\$tool\skills" -ForegroundColor Green
        } else {
            Write-Host "  Skipped: global\$tool\skills (not a symlink)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Skipped: global\$tool\skills (not found)" -ForegroundColor Yellow
    }
}

foreach ($tool in @("claude", "gemini")) {
    $link = Join-Path $RepoDir "global\$tool\agents"
    if (Test-Path $link) {
        $item = Get-Item $link -Force
        if ($item.LinkType -eq "SymbolicLink" -or $item.LinkType -eq "Junction") {
            $item.Delete()
            Write-Host "  Removed: global\$tool\agents" -ForegroundColor Green
        } else {
            Write-Host "  Skipped: global\$tool\agents (not a symlink)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Skipped: global\$tool\agents (not found)" -ForegroundColor Yellow
    }
}

Write-Host ""

# =====================================================
# 6. Screenshots directory
# =====================================================
Write-Host "Removing screenshots directory..." -ForegroundColor Yellow

$ScreenshotsDir = Join-Path $RepoDir "skills\agent-browser\screenshots"
if (Test-Path $ScreenshotsDir) {
    Remove-Item $ScreenshotsDir -Recurse -Force
    Write-Host "  Removed: skills\agent-browser\screenshots\" -ForegroundColor Green
} else {
    Write-Host "  Skipped: screenshots dir (not found)" -ForegroundColor Yellow
}

Write-Host ""

# =====================================================
# 7. CLI tools
# =====================================================
Write-Host "Removing CLI tools..." -ForegroundColor Yellow

# Gemini CLI
Write-Host "  - Gemini CLI..." -NoNewline
if (Get-Command gemini -ErrorAction SilentlyContinue) {
    try { npm uninstall -g @google/gemini-cli 2>$null; Write-Host " removed" -ForegroundColor Green }
    catch { Write-Host " failed" -ForegroundColor Red }
} else {
    Write-Host " not installed" -ForegroundColor Yellow
}

# open-code
Write-Host "  - open-code..." -NoNewline
if (Get-Command opencode -ErrorAction SilentlyContinue) {
    try { npm uninstall -g opencode-ai 2>$null; Write-Host " removed" -ForegroundColor Green }
    catch { Write-Host " failed" -ForegroundColor Red }
} else {
    Write-Host " not installed" -ForegroundColor Yellow
}

# agent-browser
Write-Host "  - agent-browser..." -NoNewline
if (Get-Command agent-browser -ErrorAction SilentlyContinue) {
    try { npm uninstall -g agent-browser 2>$null; Write-Host " removed" -ForegroundColor Green }
    catch { Write-Host " failed" -ForegroundColor Red }
} else {
    Write-Host " not installed" -ForegroundColor Yellow
}

# Codex CLI
Write-Host "  - Codex CLI..." -NoNewline
if (Get-Command codex -ErrorAction SilentlyContinue) {
    try { npm uninstall -g @openai/codex 2>$null; Write-Host " removed" -ForegroundColor Green }
    catch { Write-Host " failed" -ForegroundColor Red }
} else {
    Write-Host " not installed" -ForegroundColor Yellow
}

# Claude Code
Write-Host "  - Claude Code..." -NoNewline
if (Get-Command claude -ErrorAction SilentlyContinue) {
    try { npm uninstall -g @anthropic-ai/claude-code 2>$null; Write-Host " removed" -ForegroundColor Green }
    catch { Write-Host " failed" -ForegroundColor Red }
} else {
    Write-Host " not installed" -ForegroundColor Yellow
}

Write-Host ""

# =====================================================
# 8. Local project folders (opt-in)
# =====================================================
Write-Host "Local project folders..." -ForegroundColor Yellow
Write-Host "  These folders may contain your own work:" -ForegroundColor White
Write-Host "    .claude\  .gemini\  .opencode\  .codex\  ralph\  AGENTS.md" -ForegroundColor White
Write-Host ""

$removeLocal = $false
if ($Force) {
    $removeLocal = $true
} else {
    $reply = Read-Host "  Remove local project folders from current directory? [y/N]"
    if ($reply -match "^[Yy]$") { $removeLocal = $true }
}

if ($removeLocal) {
    foreach ($dir in @(".claude", ".gemini", ".opencode", ".codex", "ralph")) {
        $target = Join-Path $CurrentDir $dir
        if (Test-Path $target) {
            Remove-Item $target -Recurse -Force
            Write-Host "  Removed: $dir\" -ForegroundColor Green
        }
    }
    $agentsMd = Join-Path $CurrentDir "AGENTS.md"
    if (Test-Path $agentsMd) {
        Remove-Item $agentsMd -Force
        Write-Host "  Removed: AGENTS.md" -ForegroundColor Green
    }
} else {
    Write-Host "  Skipped local folder removal." -ForegroundColor Yellow
}

Write-Host ""

# =====================================================
# Done!
# =====================================================
Write-Host "Uninstall complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Verify:" -ForegroundColor Cyan
Write-Host "  Get-Command claude, gemini, opencode, codex, agent-browser"
Write-Host "  Test-Path ~\.claude, ~\.gemini, ~\.opencode, ~\.codex"
Write-Host "  Test-Path ~\.mcp.json"
