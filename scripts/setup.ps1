# model-set Setup Script for Windows
# Usage: .\scripts\setup.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir
$HomeDir = $env:USERPROFILE
$CurrentDir = Get-Location

Write-Host "model-set Setup" -ForegroundColor Cyan
Write-Host "===============" -ForegroundColor Cyan
Write-Host ""

# =====================================================
# 1. Install/Update CLI Tools
# =====================================================
Write-Host "Installing/Updating CLI tools..." -ForegroundColor Yellow

# Claude Code
Write-Host "  - Claude Code..." -NoNewline
try {
    $claudeVersion = claude --version 2>$null
    Write-Host " (already installed: $claudeVersion)" -ForegroundColor Green
} catch {
    Write-Host " installing..." -ForegroundColor Yellow
    irm https://claude.ai/install.ps1 | iex
    Write-Host "    Installed!" -ForegroundColor Green
}

# Gemini CLI
Write-Host "  - Gemini CLI..." -NoNewline
try {
    $geminiVersion = gemini --version 2>$null
    Write-Host " (already installed)" -ForegroundColor Green
} catch {
    Write-Host " installing..." -ForegroundColor Yellow
    npm install -g @google/gemini-cli
    Write-Host "    Installed!" -ForegroundColor Green
}

# open-code
Write-Host "  - open-code..." -NoNewline
try {
    $opencodeVersion = opencode --version 2>$null
    Write-Host " (already installed)" -ForegroundColor Green
} catch {
    Write-Host " installing..." -ForegroundColor Yellow
    npm install -g opencode-ai@latest
    Write-Host "    Installed!" -ForegroundColor Green
}

# agent-browser
Write-Host "  - agent-browser..." -NoNewline
try {
    $abVersion = agent-browser --version 2>$null
    Write-Host " (already installed)" -ForegroundColor Green
} catch {
    Write-Host " installing..." -ForegroundColor Yellow
    npm install -g agent-browser
    agent-browser install
    Write-Host "    Installed!" -ForegroundColor Green
}

# Codex CLI
Write-Host "  - Codex CLI..." -NoNewline
try {
    $codexVersion = codex --version 2>$null
    Write-Host " (already installed: $codexVersion)" -ForegroundColor Green
} catch {
    Write-Host " installing..." -ForegroundColor Yellow
    npm install -g @openai/codex
    Write-Host "    Installed!" -ForegroundColor Green
}

Write-Host ""

# =====================================================
# 2. Setup Stitch MCP (OAuth-based)
# =====================================================
Write-Host "Setting up Stitch MCP..." -ForegroundColor Yellow
Write-Host "  This will open a browser for Google OAuth authentication." -ForegroundColor White
Write-Host ""

$setupStitch = Read-Host "  Run Stitch MCP setup now? [y/N]"

if ($setupStitch -match "^[Yy]$") {
    Write-Host "  Running stitch-mcp-auto-setup..." -ForegroundColor Yellow
    npx stitch-mcp-auto-setup
    Write-Host "  Stitch MCP setup complete!" -ForegroundColor Green
} else {
    Write-Host "  Skipped. Run later with: npx stitch-mcp-auto-setup" -ForegroundColor Yellow
}

Write-Host ""

# =====================================================
# 3. Check for .env file
# =====================================================
$EnvFile = Join-Path $RepoDir ".env"
$EnvExample = Join-Path $RepoDir ".env.example"

if (-not (Test-Path $EnvFile)) {
    Write-Host "WARNING: .env file not found!" -ForegroundColor Yellow
    Write-Host "  Create it from .env.example and fill in your API keys:" -ForegroundColor Yellow
    Write-Host "    Copy-Item `"$EnvExample`" `"$EnvFile`"" -ForegroundColor Cyan
    Write-Host ""
}

# =====================================================
# 4. Create Global Symlinks
# =====================================================
Write-Host "Creating global config symlinks..." -ForegroundColor Yellow

function New-SymlinkSafe {
    param (
        [string]$Link,
        [string]$Target
    )

    if (Test-Path $Link) {
        $existing = Get-Item $Link
        if ($existing.LinkType -eq "SymbolicLink" -or $existing.LinkType -eq "Junction") {
            Write-Host "  $Link -> already linked" -ForegroundColor Green
            return
        } else {
            Write-Host "  $Link -> backing up existing to ${Link}.backup" -ForegroundColor Yellow
            Move-Item $Link "${Link}.backup" -Force
        }
    }

    # Create parent directory if needed
    $parent = Split-Path -Parent $Link
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    # Try symlink first, fall back to junction if permissions fail
    try {
        New-Item -ItemType SymbolicLink -Path $Link -Target $Target -Force | Out-Null
        Write-Host "  $Link -> $Target" -ForegroundColor Green
    } catch {
        # Fall back to junction (doesn't require admin)
        cmd /c mklink /J "$Link" "$Target" 2>$null
        Write-Host "  $Link -> $Target (junction)" -ForegroundColor Green
    }
}

# Global configs
New-SymlinkSafe -Link "$HomeDir\.claude" -Target "$RepoDir\global\claude"
New-SymlinkSafe -Link "$HomeDir\.gemini" -Target "$RepoDir\global\gemini"
New-SymlinkSafe -Link "$HomeDir\.opencode" -Target "$RepoDir\global\opencode"
New-SymlinkSafe -Link "$HomeDir\.codex" -Target "$RepoDir\global\codex"

# Skills symlinks (shared across all tools)
New-SymlinkSafe -Link "$RepoDir\global\claude\skills" -Target "$RepoDir\.agents\skills"
New-SymlinkSafe -Link "$RepoDir\global\gemini\skills" -Target "$RepoDir\.agents\skills"
New-SymlinkSafe -Link "$RepoDir\global\opencode\skills" -Target "$RepoDir\.agents\skills"
New-SymlinkSafe -Link "$RepoDir\global\codex\skills" -Target "$RepoDir\.agents\skills"

Write-Host ""

# =====================================================
# 5. Generate ~/.mcp.json from template
# =====================================================
Write-Host "Generating MCP config..." -ForegroundColor Yellow

$McpTemplate = Join-Path $RepoDir "global\mcp\mcp.json.template"
$McpOutput = Join-Path $HomeDir ".mcp.json"

if (Test-Path $EnvFile) {
    # Load .env file
    $envContent = Get-Content $EnvFile | Where-Object { $_ -match "^\s*[^#]" }
    $envVars = @{}
    foreach ($line in $envContent) {
        if ($line -match "^\s*([^=]+)\s*=\s*(.*)$") {
            $envVars[$matches[1].Trim()] = $matches[2].Trim()
        }
    }

    # Read template and substitute
    $template = Get-Content $McpTemplate -Raw
    foreach ($key in $envVars.Keys) {
        $template = $template -replace "\`$\{$key\}", $envVars[$key]
    }

    $template | Set-Content $McpOutput
    Write-Host "  Generated: $McpOutput" -ForegroundColor Green

    # Generate Codex config.toml from template
    $CodexTemplate = Join-Path $RepoDir "global\codex\config.toml.template"
    $CodexOutput = Join-Path $RepoDir "global\codex\config.toml"

    if (Test-Path $CodexTemplate) {
        $codexConfig = Get-Content $CodexTemplate -Raw
        foreach ($key in $envVars.Keys) {
            $codexConfig = $codexConfig -replace "\`$\{$key\}", $envVars[$key]
        }
        $codexConfig | Set-Content $CodexOutput
        Write-Host "  Generated: $CodexOutput" -ForegroundColor Green
    }
} else {
    Write-Host "  Skipped: Create .env file first" -ForegroundColor Yellow
}

Write-Host ""

# =====================================================
# 6. Ask about Local Folder Setup
# =====================================================
Write-Host "Local folder setup..." -ForegroundColor Yellow
Write-Host "  Current directory: $CurrentDir" -ForegroundColor White
Write-Host ""
Write-Host "  This will create project-specific config folders in your current directory:" -ForegroundColor White
Write-Host "    - .claude\     (Claude Code local config)" -ForegroundColor White
Write-Host "    - .gemini\     (Gemini CLI local config)" -ForegroundColor White
Write-Host "    - .opencode\   (OpenCode local config)" -ForegroundColor White
Write-Host "    - .codex\      (Codex CLI local config)" -ForegroundColor White
Write-Host "    - ralph\       (Ralph autonomous agent)" -ForegroundColor White
Write-Host ""

$createLocal = Read-Host "  Create local folders in current directory? [y/N]"

if ($createLocal -match "^[Yy]$") {
    Write-Host "  Creating local folders..." -ForegroundColor Yellow

    # Create .claude local
    $claudeLocal = Join-Path $CurrentDir ".claude"
    if (-not (Test-Path $claudeLocal)) {
        New-Item -ItemType Directory -Path $claudeLocal -Force | Out-Null
        $claudeTemplate = Join-Path $RepoDir "local\claude\CLAUDE.md.template"
        if (Test-Path $claudeTemplate) {
            Copy-Item $claudeTemplate (Join-Path $claudeLocal "CLAUDE.md")
        }
        Write-Host "    Created: .claude\" -ForegroundColor Green
    } else {
        Write-Host "    Exists: .claude\" -ForegroundColor Green
    }

    # Create .gemini local
    $geminiLocal = Join-Path $CurrentDir ".gemini"
    if (-not (Test-Path $geminiLocal)) {
        New-Item -ItemType Directory -Path $geminiLocal -Force | Out-Null
        $geminiTemplate = Join-Path $RepoDir "local\gemini\GEMINI.md.template"
        if (Test-Path $geminiTemplate) {
            Copy-Item $geminiTemplate (Join-Path $geminiLocal "GEMINI.md")
        }
        Write-Host "    Created: .gemini\" -ForegroundColor Green
    } else {
        Write-Host "    Exists: .gemini\" -ForegroundColor Green
    }

    # Create .opencode local
    $opencodeLocal = Join-Path $CurrentDir ".opencode"
    if (-not (Test-Path $opencodeLocal)) {
        New-Item -ItemType Directory -Path $opencodeLocal -Force | Out-Null
        $opencodeTemplate = Join-Path $RepoDir "local\opencode\AGENT.md.template"
        if (Test-Path $opencodeTemplate) {
            Copy-Item $opencodeTemplate (Join-Path $opencodeLocal "AGENT.md")
        }
        Write-Host "    Created: .opencode\" -ForegroundColor Green
    } else {
        Write-Host "    Exists: .opencode\" -ForegroundColor Green
    }

    # Create .codex local
    $codexLocal = Join-Path $CurrentDir ".codex"
    if (-not (Test-Path $codexLocal)) {
        New-Item -ItemType Directory -Path $codexLocal -Force | Out-Null
        Write-Host "    Created: .codex\" -ForegroundColor Green
    } else {
        Write-Host "    Exists: .codex\" -ForegroundColor Green
    }

    # Copy AGENTS.md to project root (Codex reads it from project root)
    $agentsMd = Join-Path $CurrentDir "AGENTS.md"
    if (-not (Test-Path $agentsMd)) {
        $codexTemplate = Join-Path $RepoDir "local\codex\AGENTS.md.template"
        if (Test-Path $codexTemplate) {
            Copy-Item $codexTemplate $agentsMd
            Write-Host "    Created: AGENTS.md" -ForegroundColor Green
        }
    } else {
        Write-Host "    Exists: AGENTS.md" -ForegroundColor Green
    }

    # Create ralph folder
    $ralphLocal = Join-Path $CurrentDir "ralph"
    if (-not (Test-Path $ralphLocal)) {
        New-Item -ItemType Directory -Path $ralphLocal -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $ralphLocal "archive") -Force | Out-Null

        Copy-Item (Join-Path $RepoDir "local\ralph\claude_ralph.sh") $ralphLocal
        Copy-Item (Join-Path $RepoDir "local\ralph\gemini_ralph.sh") $ralphLocal
        Copy-Item (Join-Path $RepoDir "local\ralph\opencode_ralph.sh") $ralphLocal
        Copy-Item (Join-Path $RepoDir "local\ralph\codex_ralph.sh") $ralphLocal
        Copy-Item (Join-Path $RepoDir "local\ralph\prompt.md") $ralphLocal
        Copy-Item (Join-Path $RepoDir "local\ralph\README.md") $ralphLocal

        Write-Host "    Created: ralph\" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Ralph setup complete! Next steps:" -ForegroundColor Cyan
        Write-Host "    1. Create a plan.md file in ralph\"
        Write-Host "    2. Run: bash ralph\claude_ralph.sh"
    } else {
        Write-Host "    Exists: ralph\" -ForegroundColor Green
    }
} else {
    Write-Host "  Skipped local folder creation." -ForegroundColor Yellow
    Write-Host "  Run setup again from your project directory to create local folders." -ForegroundColor Yellow
}

Write-Host ""

# =====================================================
# Done!
# =====================================================
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Global configs installed:" -ForegroundColor Cyan
Write-Host "  - ~/.claude -> model-set/global/claude"
Write-Host "  - ~/.gemini -> model-set/global/gemini"
Write-Host "  - ~/.opencode -> model-set/global/opencode"
Write-Host "  - ~/.codex -> model-set/global/codex"
Write-Host ""
Write-Host "MCP Servers configured:" -ForegroundColor Cyan
Write-Host "  - stitch (OAuth via stitch-mcp-auto)"
Write-Host "  - context7 (API key in .env)"
Write-Host "  - aiguide (no auth required)"
Write-Host ""

if (-not (Test-Path $EnvFile)) {
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Create .env file: Copy-Item `"$EnvExample`" `"$EnvFile`""
    Write-Host "  2. Fill in your API keys (CONTEXT7_API_KEY, etc.)"
    Write-Host "  3. Run setup again to generate ~/.mcp.json"
}
