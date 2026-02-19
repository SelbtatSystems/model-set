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
# 0. Check Prerequisites
# =====================================================
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

# Python 3 (required for skill scripts)
Write-Host "  - Python 3..." -NoNewline
$PythonCmd = $null
try {
    $pyVer = python3 --version 2>$null
    if ($pyVer -match "Python 3") {
        Write-Host " ($pyVer)" -ForegroundColor Green
        $PythonCmd = "python3"
    }
} catch {}

if (-not $PythonCmd) {
    try {
        $pyVer = python --version 2>$null
        if ($pyVer -match "Python 3") {
            Write-Host " ($pyVer via 'python')" -ForegroundColor Green
            $PythonCmd = "python"
        }
    } catch {}
}

if (-not $PythonCmd) {
    Write-Host " not found - attempting auto-install..." -ForegroundColor Yellow
    $Installed = $false

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "    Installing via winget..." -ForegroundColor Yellow
        try {
            winget install Python.Python.3 --silent --accept-source-agreements --accept-package-agreements
            $Installed = $true
        } catch {
            Write-Host "    winget install failed." -ForegroundColor Yellow
        }
    }

    if (-not $Installed -and (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "    Installing via Chocolatey..." -ForegroundColor Yellow
        try {
            choco install python -y
            $Installed = $true
        } catch {
            Write-Host "    choco install failed." -ForegroundColor Yellow
        }
    }

    if (-not $Installed) {
        Write-Host "    Downloading Python 3 installer from python.org..." -ForegroundColor Yellow
        $PythonVersion = "3.12.9"
        $InstallerUrl = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe"
        $InstallerPath = "$env:TEMP\python-installer.exe"
        try {
            Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing
            # /quiet = no UI, PrependPath=1 = add to PATH, InstallAllUsers=0 = current user only
            Start-Process -FilePath $InstallerPath -ArgumentList "/quiet PrependPath=1 InstallAllUsers=0" -Wait
            Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
            $Installed = $true
        } catch {
            Write-Host "  ERROR: Could not download Python installer. Install manually from https://www.python.org/downloads/" -ForegroundColor Red
            exit 1
        }
    }

    # Refresh PATH in current session so python3/python is found immediately
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")

    # Verify install succeeded
    $pyVer = python --version 2>$null
    if ($pyVer -match "Python 3") {
        Write-Host "    Installed: $pyVer" -ForegroundColor Green
        $PythonCmd = "python"
    } else {
        Write-Host "  ERROR: Python 3 installed but not found on PATH." -ForegroundColor Red
        Write-Host "  Please open a new terminal and re-run setup." -ForegroundColor Yellow
        exit 1
    }
}

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

# agent-browser system dependencies (Chromium needs libnspr4, libnss3, etc.)
Write-Host "  - agent-browser system deps..." -NoNewline
try {
    npx playwright install-deps chromium 2>$null
    Write-Host " installed" -ForegroundColor Green
} catch {
    Write-Host " (skipped - may need admin)" -ForegroundColor Yellow
}

# Ensure screenshots directory exists
$screenshotDir = Join-Path $RepoDir "skills\agent-browser\screenshots"
if (-not (Test-Path $screenshotDir)) {
    New-Item -ItemType Directory -Path $screenshotDir -Force | Out-Null
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
# 2. Setup Stitch MCP (API key-based)
# =====================================================
Write-Host "Setting up Stitch MCP..." -ForegroundColor Yellow

$EnvFile = Join-Path $RepoDir ".env"
$StitchKey = ""
if (Test-Path $EnvFile) {
    $StitchKey = (Get-Content $EnvFile | Where-Object { $_ -match "^STITCH_API_KEY=" }) -replace "^STITCH_API_KEY=", "" | ForEach-Object { $_.Trim() }
}

if ($StitchKey -and $StitchKey -ne "AQ.STITCH_API_KEY") {
    Write-Host "  Stitch API key found in .env" -ForegroundColor Green

    # Add Stitch to Claude Code (HTTP transport, user scope)
    try {
        claude mcp add stitch --transport http https://stitch.googleapis.com/mcp `
            --header "X-Goog-Api-Key: $StitchKey" -s user 2>$null
        Write-Host "    Added stitch to Claude Code (user scope)" -ForegroundColor Green
    } catch {
        Write-Host "    Warning: Failed to add stitch to Claude Code" -ForegroundColor Yellow
    }

    # Install Stitch extension for Gemini CLI and configure with API key
    try {
        gemini extensions install https://github.com/gemini-cli-extensions/stitch --auto-update 2>$null
        Write-Host "    Installed stitch extension for Gemini CLI" -ForegroundColor Green
    } catch {
        Write-Host "    Stitch extension already installed or updated" -ForegroundColor Yellow
    }

    $ExtDir = Join-Path $HomeDir ".gemini\extensions\Stitch"
    $ApiKeyTemplate = Join-Path $ExtDir "gemini-extension-apikey.json"
    $ExtConfig = Join-Path $ExtDir "gemini-extension.json"
    if (Test-Path $ApiKeyTemplate) {
        (Get-Content $ApiKeyTemplate -Raw) -replace "YOUR_API_KEY", $StitchKey | Set-Content $ExtConfig
        Write-Host "    Configured stitch extension with API key auth" -ForegroundColor Green
    }
} else {
    Write-Host "  WARNING: No STITCH_API_KEY in .env" -ForegroundColor Yellow
    Write-Host "  Add your Stitch API key to $RepoDir\.env" -ForegroundColor Yellow
    Write-Host "  Get one at: https://aistudio.google.com/apikey" -ForegroundColor Yellow
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

    $parent = Split-Path -Parent $Link
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    try {
        New-Item -ItemType SymbolicLink -Path $Link -Target $Target -Force | Out-Null
        Write-Host "  $Link -> $Target" -ForegroundColor Green
    } catch {
        cmd /c mklink /J "$Link" "$Target" 2>$null
        Write-Host "  $Link -> $Target (junction)" -ForegroundColor Green
    }
}

# Link a tool's config directory.
# New machine (dir doesn't exist): full symlink → repo/global/<tool>
# Existing machine (real dir):     skills-only symlink inside existing dir
function Link-ToolConfig {
    param (
        [string]$ConfigDir,   # e.g. ~/.claude
        [string]$RepoGlobal,  # e.g. repo\global\claude
        [string]$SkillsSrc    # e.g. repo\skills
    )

    if (Test-Path $ConfigDir) {
        $existing = Get-Item $ConfigDir
        if ($existing.LinkType -eq "SymbolicLink" -or $existing.LinkType -eq "Junction") {
            Write-Host "  $ConfigDir -> already linked" -ForegroundColor Green
        } else {
            Write-Host "  $ConfigDir already exists - linking skills only" -ForegroundColor Yellow
            New-SymlinkSafe -Link "$ConfigDir\skills" -Target $SkillsSrc
        }
    } else {
        $parent = Split-Path -Parent $ConfigDir
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        try {
            New-Item -ItemType SymbolicLink -Path $ConfigDir -Target $RepoGlobal -Force | Out-Null
            Write-Host "  $ConfigDir -> $RepoGlobal" -ForegroundColor Green
        } catch {
            cmd /c mklink /J "$ConfigDir" "$RepoGlobal" 2>$null
            Write-Host "  $ConfigDir -> $RepoGlobal (junction)" -ForegroundColor Green
        }
    }
}

# Always ensure skills symlinks exist inside repo global dirs
# (used when the full-dir symlink path is taken on a new machine)
New-SymlinkSafe -Link "$RepoDir\global\claude\skills"   -Target "$RepoDir\skills"
New-SymlinkSafe -Link "$RepoDir\global\gemini\skills"   -Target "$RepoDir\skills"
New-SymlinkSafe -Link "$RepoDir\global\opencode\skills" -Target "$RepoDir\skills"
New-SymlinkSafe -Link "$RepoDir\global\codex\skills"    -Target "$RepoDir\skills"

# Link tool config dirs (smart: full on new machine, skills-only on existing)
Link-ToolConfig -ConfigDir "$HomeDir\.claude"   -RepoGlobal "$RepoDir\global\claude"   -SkillsSrc "$RepoDir\skills"
Link-ToolConfig -ConfigDir "$HomeDir\.gemini"   -RepoGlobal "$RepoDir\global\gemini"   -SkillsSrc "$RepoDir\skills"
Link-ToolConfig -ConfigDir "$HomeDir\.opencode" -RepoGlobal "$RepoDir\global\opencode" -SkillsSrc "$RepoDir\skills"
Link-ToolConfig -ConfigDir "$HomeDir\.codex"    -RepoGlobal "$RepoDir\global\codex"    -SkillsSrc "$RepoDir\skills"

Write-Host ""

# =====================================================
# 5. Generate ~/.mcp.json from template
# =====================================================
Write-Host "Generating MCP config..." -ForegroundColor Yellow

$McpTemplate = Join-Path $RepoDir "global\mcp\mcp.json.template"
$McpOutput = Join-Path $HomeDir ".mcp.json"

if (Test-Path $EnvFile) {
    # Load .env file (needed for both mcp.json and codex config)
    $envContent = Get-Content $EnvFile | Where-Object { $_ -match "^\s*[^#]" }
    $envVars = @{}
    foreach ($line in $envContent) {
        if ($line -match "^\s*([^=]+)\s*=\s*(.*)$") {
            $envVars[$matches[1].Trim()] = $matches[2].Trim()
        }
    }

    # Generate ~/.mcp.json (only if it doesn't already exist)
    if (Test-Path $McpOutput) {
        Write-Host "  Skipped: $McpOutput already exists (not overwriting)" -ForegroundColor Yellow
    } else {
        $template = Get-Content $McpTemplate -Raw
        foreach ($key in $envVars.Keys) {
            $template = $template -replace "\`$\{$key\}", $envVars[$key]
        }
        $template | Set-Content $McpOutput
        Write-Host "  Generated: $McpOutput" -ForegroundColor Green
    }

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
