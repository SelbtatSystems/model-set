# Apply local configs to a project
# Usage: .\scripts\apply-local.ps1 -ProjectDir C:\path\to\project [-Tool claude|gemini|opencode]

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectDir,

    [ValidateSet("claude", "gemini", "opencode", "codex")]
    [string]$Tool = "claude"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir

# Resolve to absolute path
$ProjectDir = Resolve-Path $ProjectDir -ErrorAction Stop

Write-Host "Applying $Tool config to: $ProjectDir" -ForegroundColor Cyan
Write-Host ""

# =====================================================
# 1. Copy tool-specific configs
# =====================================================
switch ($Tool) {
    "claude" {
        $LocalDir = Join-Path $RepoDir "local\claude"
        $ContextFile = "CLAUDE.md"
        $ContextTemplate = Join-Path $LocalDir "CLAUDE.md.template"
        $McpTemplate = Join-Path $LocalDir ".mcp.json.template"

        # Create .claude directory
        $ClaudeDir = Join-Path $ProjectDir ".claude"
        if (-not (Test-Path $ClaudeDir)) {
            New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
        }

        # Copy context file if it doesn't exist
        $ContextDst = Join-Path $ProjectDir $ContextFile
        if (-not (Test-Path $ContextDst)) {
            Copy-Item $ContextTemplate $ContextDst
            Write-Host "  Created $ContextFile" -ForegroundColor Green
        } else {
            Write-Host "  $ContextFile already exists (skipped)" -ForegroundColor Yellow
        }

        # Copy MCP template
        if (Test-Path $McpTemplate) {
            Copy-Item $McpTemplate (Join-Path $ProjectDir ".mcp.json.template")
            Write-Host "  Created .mcp.json.template" -ForegroundColor Green
        }
    }

    "gemini" {
        $LocalDir = Join-Path $RepoDir "local\gemini"
        $ContextFile = "GEMINI.md"
        $ContextTemplate = Join-Path $LocalDir "GEMINI.md.template"

        # Create .gemini directory
        $GeminiDir = Join-Path $ProjectDir ".gemini"
        if (-not (Test-Path $GeminiDir)) {
            New-Item -ItemType Directory -Path $GeminiDir -Force | Out-Null
        }

        # Copy context file if it doesn't exist
        $ContextDst = Join-Path $ProjectDir $ContextFile
        if (-not (Test-Path $ContextDst)) {
            Copy-Item $ContextTemplate $ContextDst
            Write-Host "  Created $ContextFile" -ForegroundColor Green
        } else {
            Write-Host "  $ContextFile already exists (skipped)" -ForegroundColor Yellow
        }
    }

    "opencode" {
        $LocalDir = Join-Path $RepoDir "local\opencode"
        $ContextFile = "AGENT.md"
        $ContextTemplate = Join-Path $LocalDir "AGENT.md.template"

        # Create .opencode directory
        $OpencodeDir = Join-Path $ProjectDir ".opencode"
        if (-not (Test-Path $OpencodeDir)) {
            New-Item -ItemType Directory -Path $OpencodeDir -Force | Out-Null
        }

        # Copy context file if it doesn't exist
        $ContextDst = Join-Path $ProjectDir $ContextFile
        if (-not (Test-Path $ContextDst)) {
            Copy-Item $ContextTemplate $ContextDst
            Write-Host "  Created $ContextFile" -ForegroundColor Green
        } else {
            Write-Host "  $ContextFile already exists (skipped)" -ForegroundColor Yellow
        }
    }

    "codex" {
        $LocalDir = Join-Path $RepoDir "local\codex"
        $ContextFile = "AGENTS.md"
        $ContextTemplate = Join-Path $LocalDir "AGENTS.md.template"

        # Create .codex directory
        $CodexDir = Join-Path $ProjectDir ".codex"
        if (-not (Test-Path $CodexDir)) {
            New-Item -ItemType Directory -Path $CodexDir -Force | Out-Null
        }

        # Copy AGENTS.md to project root if it doesn't exist
        $ContextDst = Join-Path $ProjectDir $ContextFile
        if (-not (Test-Path $ContextDst)) {
            Copy-Item $ContextTemplate $ContextDst
            Write-Host "  Created $ContextFile" -ForegroundColor Green
        } else {
            Write-Host "  $ContextFile already exists (skipped)" -ForegroundColor Yellow
        }
    }
}

# =====================================================
# 2. Copy ralph directory
# =====================================================
$RalphSrc = Join-Path $RepoDir "ralph"
$RalphDst = Join-Path $ProjectDir "ralph"

if (-not (Test-Path $RalphDst)) {
    New-Item -ItemType Directory -Path $RalphDst -Force | Out-Null
    Copy-Item (Join-Path $RalphSrc "prompt.md") $RalphDst
    Copy-Item (Join-Path $RalphSrc "ralph.sh") $RalphDst

    # Create empty prd.json template
    $PrdContent = @'
{
  "projectName": "Your Project",
  "branchName": "ralph/feature-name",
  "userStories": [
    {
      "id": "US-001",
      "title": "Example Story",
      "description": "As a user, I want to...",
      "acceptanceCriteria": [
        "Criterion 1",
        "Criterion 2"
      ],
      "priority": 1,
      "passes": false
    }
  ]
}
'@
    $PrdContent | Set-Content (Join-Path $RalphDst "prd.json")

    # Create empty progress.txt
    $ProgressContent = @"
# Ralph Progress Log
Started: $(Get-Date)
---
"@
    $ProgressContent | Set-Content (Join-Path $RalphDst "progress.txt")

    Write-Host "  Created ralph/ directory" -ForegroundColor Green
} else {
    Write-Host "  ralph/ already exists (skipped)" -ForegroundColor Yellow
}

# =====================================================
# 3. Create project .env template
# =====================================================
$EnvExample = Join-Path $ProjectDir ".env.local.example"
if (-not (Test-Path $EnvExample)) {
    $EnvContent = @'
# Project-specific environment variables
# Copy to .env.local and fill in your values

# Database
POSTGRES_DATABASE_URI=postgresql://user:password@localhost:5432/dbname

# Redis (if using)
REDIS_URL=redis://:password@localhost:6379/0
'@
    $EnvContent | Set-Content $EnvExample
    Write-Host "  Created .env.local.example" -ForegroundColor Green
}

Write-Host ""
Write-Host "Applied $Tool config to $ProjectDir" -ForegroundColor Green
Write-Host "  Copied ralph/ to $ProjectDir\ralph"
if ($Tool -eq "claude") {
    Write-Host "  Created .mcp.json template"
}
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Edit $ProjectDir\$ContextFile with project-specific info"
Write-Host "  2. Edit $ProjectDir\ralph\prd.json with user stories"
if ($Tool -eq "claude") {
    Write-Host "  3. Copy .mcp.json.template to .mcp.json and fill in credentials"
}
