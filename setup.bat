@echo off
REM Data360 Retail Solution Kit - one-time machine prep (Windows)
REM
REM Installs the Playwright Claude Code plugin from claude-plugins-official.
REM This is the SAME plugin Mac/Linux users get via setup.sh - it exposes
REM Playwright tools under prefix mcp__plugin_playwright_playwright__*,
REM which is what every Data360 skill calls.
REM
REM Run ONCE per laptop. After this + /reload-plugins inside Claude Code,
REM every future "install Data360 retail" runs end-to-end with no prompts.

setlocal enabledelayedexpansion

echo.
echo ===================================================================
echo   Data360 Retail - one-time machine prep (Windows)
echo ===================================================================
echo.

REM ---------- 1. Verify the claude CLI is on PATH ----------
where claude >nul 2>nul
if errorlevel 1 (
    echo [X] The 'claude' CLI is not on PATH.
    echo.
    echo     Install Claude Code first: https://claude.com/claude-code
    echo     ^(Windows PowerShell:    irm https://claude.ai/install.ps1 ^| iex^)
    echo     ^(Windows CMD via WinGet: winget install Anthropic.ClaudeCode^)
    echo.
    echo     Then re-run this script.
    exit /b 1
)
for /f "delims=" %%v in ('claude --version 2^>nul') do (
    echo [OK] Claude Code CLI detected: %%v
    goto :version_done
)
:version_done

REM ---------- 2. Verify Node.js 18+ (Microsoft Playwright MCP requirement) ----------
where node >nul 2>nul
if errorlevel 1 (
    echo [X] Node.js is not installed.
    echo.
    echo     The Playwright MCP plugin requires Node.js 18 or newer.
    echo     Install:  winget install OpenJS.NodeJS.LTS
    echo     OR download from https://nodejs.org/ ^(LTS^)
    echo.
    echo     Then re-run this script.
    exit /b 1
)
for /f "tokens=1 delims=." %%a in ('node -v') do set NODE_MAJOR=%%a
set NODE_MAJOR=!NODE_MAJOR:v=!
if !NODE_MAJOR! lss 18 (
    for /f %%v in ('node -v') do echo [X] Node.js %%v is too old. Playwright MCP requires Node.js 18+.
    echo     Upgrade:  winget upgrade OpenJS.NodeJS.LTS
    exit /b 1
)
for /f %%v in ('node -v') do echo [OK] Node.js %%v detected.

REM ---------- 3. Ensure claude-plugins-official marketplace is registered ----------
REM Per official docs: the marketplace auto-registers on first INTERACTIVE Claude
REM launch. Non-interactive scripts may run before that, so add it defensively.
call claude plugin marketplace list 2>nul | findstr /c:"claude-plugins-official" >nul
if errorlevel 1 (
    echo.
    echo [..] Registering claude-plugins-official marketplace...
    call claude plugin marketplace add anthropics/claude-plugins-official
)

REM ---------- 4. Install the Playwright plugin (idempotent) ----------
call claude plugin list 2>nul | findstr /c:"playwright@claude-plugins-official" >nul
if not errorlevel 1 (
    echo [OK] Playwright plugin is already installed. No action needed.
    echo.
    echo     If Data360 still asks you to install it, the plugin is installed
    echo     but Claude Code hasn't reloaded yet. Run this INSIDE Claude Code:
    echo.
    echo          /reload-plugins
    echo.
    exit /b 0
)

echo.
echo [..] Installing Playwright plugin from claude-plugins-official...
call claude plugin install playwright@claude-plugins-official

REM ---------- 5. Final instruction: /reload-plugins (universal command) ----------
echo.
echo ===================================================================
echo   Playwright plugin installed.
echo ===================================================================
echo.
echo   ONE manual step remains - Claude Code needs to load the plugin.
echo.
echo   Inside Claude Code's chat input, type and press Enter:
echo.
echo          /reload-plugins
echo.
echo   ^(Universal command - works on Windows, macOS, Linux, and every
echo    Claude Code surface: CLI, VS Code, Desktop, Web.^)
echo.
echo   Then re-run:
echo.
echo          install Data360 retail
echo.
echo   Every future Data360 install on this laptop is now unattended.
echo ===================================================================

endlocal
