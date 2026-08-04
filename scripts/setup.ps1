# model-set Setup Script for Windows
# Usage: .\scripts\setup.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir
$HomeDir = $env:USERPROFILE
$CurrentDir = Get-Location

function Refresh-SessionPath {
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")
}

function Ensure-PathEntry {
    param ([string]$Entry)

    if (-not $Entry -or -not (Test-Path $Entry)) {
        return
    }

    $paths = $env:PATH -split ";"
    if ($paths -notcontains $Entry) {
        $env:PATH = "$Entry;$env:PATH"
    }

    $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $userPaths = @()
    if ($userPath) {
        $userPaths = $userPath -split ";"
    }
    if ($userPaths -notcontains $Entry) {
        $newUserPath = if ($userPath) { "$Entry;$userPath" } else { $Entry }
        [System.Environment]::SetEnvironmentVariable("PATH", $newUserPath, "User")
        Write-Host "    Added $Entry to user PATH" -ForegroundColor Green
    }
}

function Ensure-NpmGlobalPath {
    try {
        $npmPrefix = npm prefix -g 2>$null
        if ($npmPrefix) {
            Ensure-PathEntry -Entry $npmPrefix
        }
    } catch {}
}

function Set-AgentBrowserNoSandbox {
    $configDir = Join-Path $HomeDir ".agent-browser"
    $configFile = Join-Path $configDir "config.json"

    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $config = [ordered]@{}
    if (Test-Path $configFile) {
        try {
            $existing = Get-Content $configFile -Raw | ConvertFrom-Json
            foreach ($property in $existing.PSObject.Properties) {
                $config[$property.Name] = $property.Value
            }
        } catch {
            $config = [ordered]@{}
        }
    }

    if (-not $config.Contains("args") -or -not $config["args"]) {
        $config["args"] = "--no-sandbox"
    } elseif ($config["args"] -is [System.Array]) {
        if ($config["args"] -notcontains "--no-sandbox") {
            $config["args"] = @($config["args"] + "--no-sandbox")
        }
    } else {
        $argsText = [string]$config["args"]
        if ($argsText -notmatch "(^|,|\s)--no-sandbox(,|\s|$)") {
            $config["args"] = "$argsText,--no-sandbox"
        }
    }

    $config | ConvertTo-Json -Depth 10 | Set-Content $configFile
}

function Test-AgentBrowserDoctor {
    Write-Host "  - agent-browser doctor..." -NoNewline

    $doctorOutput = agent-browser doctor 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host " passed" -ForegroundColor Green
        return
    }

    $doctorText = $doctorOutput | Out-String
    if ($doctorText -match "No usable sandbox") {
        Write-Host " needs --no-sandbox" -ForegroundColor Yellow
        Write-Host "    Configuring ~/.agent-browser/config.json with --no-sandbox" -ForegroundColor Yellow
        Set-AgentBrowserNoSandbox
        try { agent-browser close *> $null } catch {}

        $quickDoctorOutput = agent-browser doctor --offline --quick 2>&1
        $quickDoctorPassed = ($LASTEXITCODE -eq 0)
        $openOutput = agent-browser open about:blank 2>&1
        $openPassed = ($LASTEXITCODE -eq 0)
        $closeOutput = agent-browser close 2>&1
        $closePassed = ($LASTEXITCODE -eq 0)

        if ($quickDoctorPassed -and $openPassed -and $closePassed) {
            Write-Host "    Quick doctor and launch smoke passed after --no-sandbox config" -ForegroundColor Green
            return
        }
        $doctorText = @($quickDoctorOutput, $openOutput, $closeOutput) | Out-String
    }

    Write-Host " failed" -ForegroundColor Red
    Write-Host $doctorText
    throw "agent-browser doctor failed. Re-run with: agent-browser doctor"
}

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
        $pyVer = py -3 --version 2>$null
        if ($pyVer -match "Python 3") {
            Write-Host " ($pyVer via 'py -3')" -ForegroundColor Green
            $PythonCmd = "py -3"
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

    # Refresh PATH in current session so python3/py launcher is found immediately
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")

    # Verify install succeeded
    $pyVer = $null
    try {
        $pyVer = python3 --version 2>$null
        if ($pyVer -match "Python 3") {
            $PythonCmd = "python3"
        }
    } catch {}
    if (-not $PythonCmd) {
        try {
            $pyVer = py -3 --version 2>$null
            if ($pyVer -match "Python 3") {
                $PythonCmd = "py -3"
            }
        } catch {}
    }
    if ($PythonCmd) {
        Write-Host "    Installed: $pyVer" -ForegroundColor Green
    } else {
        Write-Host "  ERROR: Python 3 installed but not found on PATH." -ForegroundColor Red
        Write-Host "  Please open a new terminal and re-run setup." -ForegroundColor Yellow
        exit 1
    }
}

# jq (required for Claude Code status line)
Write-Host "  - jq..." -NoNewline
$jqFound = $false
try {
    $jqVer = jq --version 2>$null
    if ($jqVer) {
        Write-Host " ($jqVer)" -ForegroundColor Green
        $jqFound = $true
    }
} catch {}

if (-not $jqFound) {
    Write-Host " not found - attempting auto-install..." -ForegroundColor Yellow
    $jqInstalled = $false

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            winget install jqlang.jq --silent --accept-source-agreements --accept-package-agreements
            $jqInstalled = $true
        } catch {}
    }

    if (-not $jqInstalled -and (Get-Command choco -ErrorAction SilentlyContinue)) {
        try {
            choco install jq -y
            $jqInstalled = $true
        } catch {}
    }

    if (-not $jqInstalled -and (Get-Command scoop -ErrorAction SilentlyContinue)) {
        try {
            scoop install jq
            $jqInstalled = $true
        } catch {}
    }

    # Refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")

    if ($jqInstalled -and (Get-Command jq -ErrorAction SilentlyContinue)) {
        Write-Host "    Installed: $(jq --version 2>$null)" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Could not auto-install jq. Status line will not work." -ForegroundColor Yellow
        Write-Host "  Install manually: https://jqlang.github.io/jq/download/" -ForegroundColor Yellow
    }
}

# Node.js/npm (required for npm-installed CLIs and npx skills)
Write-Host "  - Node.js/npm..." -NoNewline
$nodeReady = $false
try {
    $nodeVer = node --version 2>$null
    $npmVer = npm --version 2>$null
    if ($nodeVer -and $npmVer) {
        Write-Host " ($nodeVer, npm $npmVer)" -ForegroundColor Green
        $nodeReady = $true
    }
} catch {}

if (-not $nodeReady) {
    Write-Host " not found - attempting auto-install..." -ForegroundColor Yellow
    $nodeInstalled = $false

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            winget install OpenJS.NodeJS.LTS --silent --accept-source-agreements --accept-package-agreements
            $nodeInstalled = $true
        } catch {
            Write-Host "    winget install failed." -ForegroundColor Yellow
        }
    }

    if (-not $nodeInstalled -and (Get-Command choco -ErrorAction SilentlyContinue)) {
        try {
            choco install nodejs-lts -y
            $nodeInstalled = $true
        } catch {
            Write-Host "    choco install failed." -ForegroundColor Yellow
        }
    }

    if (-not $nodeInstalled -and (Get-Command scoop -ErrorAction SilentlyContinue)) {
        try {
            scoop install nodejs-lts
            $nodeInstalled = $true
        } catch {
            Write-Host "    scoop install failed." -ForegroundColor Yellow
        }
    }

    Refresh-SessionPath

    try {
        $nodeVer = node --version 2>$null
        $npmVer = npm --version 2>$null
        if ($nodeVer -and $npmVer) {
            Write-Host "    Installed: $nodeVer, npm $npmVer" -ForegroundColor Green
            $nodeReady = $true
        }
    } catch {}

    if (-not $nodeReady) {
        Write-Host "  ERROR: Could not install Node.js/npm. Install Node.js LTS manually and re-run setup." -ForegroundColor Red
        exit 1
    }
}
Ensure-NpmGlobalPath

Write-Host ""

# =====================================================
# 1. Create Global Symlinks
# =====================================================
# NOTE: Symlinks MUST be created before CLI tools are installed.
# CLI installers (e.g. Claude Code) create ~/.claude as a real directory,
# which prevents the full-directory symlink from being established later.
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
# Always creates a full symlink → repo/global/<tool>.
# Backs up any existing real directory to <dir>.backup.
function Link-ToolConfig {
    param (
        [string]$ConfigDir,   # e.g. ~/.claude
        [string]$RepoGlobal   # e.g. repo\global\claude
    )

    if (Test-Path $ConfigDir) {
        $existing = Get-Item $ConfigDir
        if ($existing.LinkType -eq "SymbolicLink" -or $existing.LinkType -eq "Junction") {
            Write-Host "  $ConfigDir -> already linked" -ForegroundColor Green
            return
        }
        Write-Host "  $ConfigDir -> backing up existing to ${ConfigDir}.backup" -ForegroundColor Yellow
        if (Test-Path "${ConfigDir}.backup") {
            Remove-Item "${ConfigDir}.backup" -Recurse -Force
        }
        Move-Item $ConfigDir "${ConfigDir}.backup" -Force
    }

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

# Seed a tool's own skills directory from repo\skills.
# Each agent owns its skills from here on, so this only ever SEEDS: an existing
# directory is left untouched, however far it has diverged. Never backs up, never
# overwrites — the dirs are gitignored, so a clobber would be unrecoverable.
function Initialize-SkillsDir {
    param (
        [string]$Dir,     # e.g. repo\global\claude\skills
        [string]$Source   # e.g. repo\skills
    )

    if (Test-Path $Dir) {
        $item = Get-Item $Dir -Force
        if ($item.LinkType -eq "SymbolicLink" -or $item.LinkType -eq "Junction") {
            # Migration from the old shared-symlink layout.
            Write-Host "  $Dir -> replacing shared link with own copy" -ForegroundColor Yellow
            $item.Delete()
        } else {
            Write-Host "  $Dir -> already present, left untouched" -ForegroundColor Green
            return
        }
    }

    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    Copy-Item -Path "$Source\*" -Destination $Dir -Recurse -Force
    Write-Host "  $Dir -> seeded from $Source" -ForegroundColor Green
}

# Each agent gets its own skills directory (gitignored); repo\skills is the source
# they are seeded from, not a live shared target.
Initialize-SkillsDir -Dir "$RepoDir\global\claude\skills"   -Source "$RepoDir\skills"
Initialize-SkillsDir -Dir "$RepoDir\global\gemini\skills"   -Source "$RepoDir\skills"
Initialize-SkillsDir -Dir "$RepoDir\global\opencode\skills" -Source "$RepoDir\skills"
Initialize-SkillsDir -Dir "$RepoDir\global\codex\skills"    -Source "$RepoDir\skills"
# Link tool config dirs (always full symlink, backup existing)
Link-ToolConfig -ConfigDir "$HomeDir\.claude"   -RepoGlobal "$RepoDir\global\claude"
Link-ToolConfig -ConfigDir "$HomeDir\.gemini"   -RepoGlobal "$RepoDir\global\gemini"
Link-ToolConfig -ConfigDir "$HomeDir\.opencode" -RepoGlobal "$RepoDir\global\opencode"
Link-ToolConfig -ConfigDir "$HomeDir\.codex"    -RepoGlobal "$RepoDir\global\codex"

Write-Host ""

# =====================================================
# 2. Install/Update CLI Tools
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

# Claude Code - Warp plugin (warpdotdev/claude-code-warp)
# Plugin state lives in ~/.claude/plugins which is gitignored runtime data
# (not carried by the global symlink), so it must be installed here.
Write-Host "  - Warp plugin for Claude Code..." -NoNewline
if (Get-Command claude -ErrorAction SilentlyContinue) {
    $pluginList = claude plugin list 2>$null
    if ($pluginList -match "warp@claude-code-warp") {
        Write-Host " (already installed)" -ForegroundColor Green
    } else {
        Write-Host " installing..." -ForegroundColor Yellow
        claude plugin marketplace add warpdotdev/claude-code-warp 2>$null
        claude plugin install warp@claude-code-warp -s user 2>$null
        if ((claude plugin list 2>$null) -match "warp@claude-code-warp") {
            Write-Host "    Installed: warp@claude-code-warp" -ForegroundColor Green
        } else {
            Write-Host "  WARNING: Failed to install Warp plugin - run manually: claude plugin install warp@claude-code-warp" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host " (skipped - claude not on PATH)" -ForegroundColor Yellow
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
$agentBrowserCmd = Get-Command agent-browser -ErrorAction SilentlyContinue
$upgradedAgentBrowser = $false
if ($agentBrowserCmd) {
    $abVersion = agent-browser --version 2>$null
    Write-Host " updating ($abVersion)..." -ForegroundColor Yellow
    try {
        agent-browser upgrade *> $null
        if ($LASTEXITCODE -eq 0) {
            $upgradedAgentBrowser = $true
        }
    } catch {}
}

if (-not $agentBrowserCmd) {
    Write-Host " installing..." -ForegroundColor Yellow
}

if (-not $upgradedAgentBrowser) {
    npm install -g agent-browser@latest
    if ($LASTEXITCODE -ne 0) {
        throw "npm install -g agent-browser@latest failed"
    }
}
Refresh-SessionPath
Ensure-NpmGlobalPath
$abVersion = agent-browser --version 2>$null
if (-not $abVersion) {
    Write-Host "  ERROR: agent-browser installed but is not on PATH." -ForegroundColor Red
    exit 1
}
Write-Host "    Installed: $abVersion" -ForegroundColor Green

Write-Host "  - agent-browser browser..." -ForegroundColor Yellow
agent-browser install
if ($LASTEXITCODE -ne 0) {
    throw "agent-browser install failed"
}
Write-Host "    Browser install complete" -ForegroundColor Green

Test-AgentBrowserDoctor

Write-Host "  - agent-browser skill..." -ForegroundColor Yellow
Push-Location $RepoDir
try {
    npx -y skills add vercel-labs/agent-browser *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "npx skills add vercel-labs/agent-browser failed"
    }
    Write-Host "    Skill synced from vercel-labs/agent-browser" -ForegroundColor Green
} finally {
    Pop-Location
}

# Ensure screenshots directory exists
$screenshotDir = Join-Path $RepoDir "skills\agent-browser\screenshots"
if (-not (Test-Path $screenshotDir)) {
    New-Item -ItemType Directory -Path $screenshotDir -Force | Out-Null
}

# Ollama
Write-Host "  - Ollama..." -NoNewline
try {
    $ollamaVersion = ollama --version 2>$null
    Write-Host " (already installed: $ollamaVersion)" -ForegroundColor Green
} catch {
    Write-Host " installing..." -ForegroundColor Yellow
    $Installed = $false

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            winget install Ollama.Ollama --silent --accept-source-agreements --accept-package-agreements
            $Installed = $true
        } catch {}
    }

    if (-not $Installed) {
        $OllamaInstaller = "$env:TEMP\OllamaSetup.exe"
        try {
            Invoke-WebRequest -Uri "https://ollama.com/download/OllamaSetup.exe" -OutFile $OllamaInstaller -UseBasicParsing
            Start-Process -FilePath $OllamaInstaller -ArgumentList "/SILENT" -Wait
            Remove-Item $OllamaInstaller -Force -ErrorAction SilentlyContinue
            $Installed = $true
        } catch {
            Write-Host "    Failed to download installer. Install manually from https://ollama.com/download" -ForegroundColor Yellow
        }
    }

    # Refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")

    if ($Installed) {
        Write-Host "    Installed!" -ForegroundColor Green
    }
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
# 3. Setup Stitch (Gemini CLI extension only)
# =====================================================
Write-Host "Setting up Stitch (Gemini CLI extension)..." -ForegroundColor Yellow

$EnvFile = Join-Path $RepoDir ".env"
$StitchKey = ""
if (Test-Path $EnvFile) {
    $StitchKey = (Get-Content $EnvFile | Where-Object { $_ -match "^STITCH_API_KEY=" }) -replace "^STITCH_API_KEY=", "" | ForEach-Object { $_.Trim() }
}

if ($StitchKey -and $StitchKey -ne "AQ.STITCH_API_KEY") {
    Write-Host "  Stitch API key found in .env" -ForegroundColor Green

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
# 4. Check for .env file
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
Write-Host "  - context7 (API key in .env)"
Write-Host "  - aiguide (no auth required)"
Write-Host ""

if (-not (Test-Path $EnvFile)) {
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Create .env file: Copy-Item `"$EnvExample`" `"$EnvFile`""
    Write-Host "  2. Fill in your API keys (CONTEXT7_API_KEY, etc.)"
    Write-Host "  3. Run setup again to generate ~/.mcp.json"
}
