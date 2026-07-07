#!/usr/bin/env bash
# Data360 Retail Solution Kit — one-time machine prep (macOS / Linux)
#
# Installs the Playwright Claude Code plugin from claude-plugins-official.
# This is the SAME plugin Windows users get via setup.bat — it exposes
# Playwright tools under prefix `mcp__plugin_playwright_playwright__*`,
# which is what every Data360 skill calls.
#
# Run ONCE per laptop. After this + `/reload-plugins` inside Claude Code,
# every future "install Data360 retail" runs end-to-end with no prompts.

set -e

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "  Data360 Retail — one-time machine prep (macOS / Linux)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# ---------- 1. Verify the `claude` CLI is on PATH ----------
if ! command -v claude >/dev/null 2>&1; then
  echo "❌ The 'claude' CLI is not on PATH."
  echo ""
  echo "   Install Claude Code first: https://claude.com/claude-code"
  echo "   (macOS / Linux native install:  curl -fsSL https://claude.ai/install.sh | bash)"
  echo ""
  echo "   Then re-run this script."
  exit 1
fi
echo "✅ Claude Code CLI detected: $(claude --version 2>/dev/null | head -1)"

# ---------- 2. Verify Node.js 18+ (Microsoft Playwright MCP requirement) ----------
if ! command -v node >/dev/null 2>&1; then
  echo "❌ Node.js is not installed."
  echo ""
  echo "   The Playwright MCP plugin requires Node.js 18 or newer."
  if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
    echo "   Install:  brew install node"
  else
    echo "   Install:  sudo apt install nodejs npm   (Debian/Ubuntu)"
    echo "             sudo dnf install nodejs       (Fedora/RHEL)"
  fi
  echo "   OR download from https://nodejs.org/ (LTS)"
  echo ""
  echo "   Then re-run this script."
  exit 1
fi
NODE_MAJOR="$(node -v | sed 's/^v\([0-9][0-9]*\).*/\1/')"
if [ "${NODE_MAJOR:-0}" -lt 18 ]; then
  echo "❌ Node.js $(node -v) is too old. Playwright MCP requires Node.js 18+."
  if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
    echo "   Upgrade:  brew upgrade node"
  else
    echo "   Upgrade via your distro's package manager or https://nodejs.org/"
  fi
  exit 1
fi
echo "✅ Node.js $(node -v) detected."

# ---------- 3. Ensure claude-plugins-official marketplace is registered ----------
# Per official docs: the marketplace auto-registers on first INTERACTIVE Claude
# launch. Non-interactive scripts may run before that, so add it defensively.
if ! claude plugin marketplace list 2>/dev/null | grep -q "claude-plugins-official"; then
  echo ""
  echo "📦 Registering claude-plugins-official marketplace..."
  claude plugin marketplace add anthropics/claude-plugins-official
fi

# ---------- 4. Install the Playwright plugin (idempotent) ----------
if claude plugin list 2>/dev/null | grep -q "playwright@claude-plugins-official"; then
  echo "✅ Playwright plugin is already installed. No action needed."
  echo ""
  echo "   If Data360 still asks you to install it, the plugin is installed"
  echo "   but Claude Code hasn't reloaded yet. Run this INSIDE Claude Code:"
  echo ""
  echo "        /reload-plugins"
  echo ""
  exit 0
fi

echo ""
echo "📦 Installing Playwright plugin from claude-plugins-official..."
claude plugin install playwright@claude-plugins-official

# ---------- 5. Final instruction: use /reload-plugins (universal, cross-platform) ----------
echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "  🎉  Playwright plugin installed."
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "  ONE manual step remains — Claude Code needs to load the plugin."
echo ""
echo "  Inside Claude Code's chat input, type and press Enter:"
echo ""
echo "        /reload-plugins"
echo ""
echo "  (Universal command — works on macOS, Linux, Windows, and every"
echo "   Claude Code surface: CLI, VS Code, Desktop, Web.)"
echo ""
echo "  Then re-run:"
echo ""
echo "        install Data360 retail"
echo ""
echo "  Every future Data360 install on this laptop is now unattended."
echo "═══════════════════════════════════════════════════════════════════"
