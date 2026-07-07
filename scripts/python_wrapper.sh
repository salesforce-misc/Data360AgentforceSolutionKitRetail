#!/bin/bash
# Cross-platform Python wrapper with auto-install fallback
# - Tries python3 first, falls back to python
# - If neither is found, attempts to auto-install via the platform's
#   package manager (winget on Windows, brew on macOS, apt/dnf/yum on Linux)
# - Re-checks for python3/python after install and runs the command, or
#   exits non-zero with a clear error if auto-install failed.
#
# Usage:
#   ./python_wrapper.sh --version
#   ./python_wrapper.sh -c "import sys; print(sys.version)"
#   ./python_wrapper.sh some_script.py arg1 arg2

set -u

run_python() {
    if command -v python3 &> /dev/null; then
        python3 "$@"
        return $?
    elif command -v python &> /dev/null; then
        python "$@"
        return $?
    fi
    return 127
}

detect_os() {
    case "$(uname -s 2>/dev/null)" in
        Linux*)   echo "linux" ;;
        Darwin*)  echo "macos" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *)
            # OSTYPE may be set in Git Bash on Windows even when uname isn't
            case "${OSTYPE:-}" in
                msys*|cygwin*|win32*) echo "windows" ;;
                darwin*) echo "macos" ;;
                linux*)  echo "linux" ;;
                *) echo "unknown" ;;
            esac
            ;;
    esac
}

install_python_windows() {
    echo "Attempting to install Python via winget..." >&2
    if ! command -v winget &> /dev/null; then
        echo "Error: winget is not available. Install Python 3.x manually from https://www.python.org/downloads/" >&2
        return 1
    fi
    winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements --silent >&2
    return $?
}

install_python_macos() {
    echo "Attempting to install Python via Homebrew..." >&2
    if ! command -v brew &> /dev/null; then
        echo "Error: Homebrew is not installed. Install it from https://brew.sh, or install Python from https://www.python.org/downloads/" >&2
        return 1
    fi
    brew install python3 >&2
    return $?
}

install_python_linux() {
    echo "Attempting to install Python via system package manager..." >&2
    if command -v apt-get &> /dev/null; then
        sudo apt-get update >&2 && sudo apt-get install -y python3 >&2
        return $?
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y python3 >&2
        return $?
    elif command -v yum &> /dev/null; then
        sudo yum install -y python3 >&2
        return $?
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm python >&2
        return $?
    else
        echo "Error: No supported Linux package manager found (apt-get, dnf, yum, pacman). Install Python 3.x manually." >&2
        return 1
    fi
}

# Fast path: Python already present
if run_python "$@"; then
    exit 0
fi

rc=$?
# rc=127 means we couldn't find python at all; any other non-zero is the user's
# script returning non-zero — pass that through, do NOT trigger an install.
if [ "$rc" -ne 127 ]; then
    exit "$rc"
fi

echo "Python is not installed or not in PATH. Attempting auto-install..." >&2

OS=$(detect_os)
case "$OS" in
    windows) install_python_windows ;;
    macos)   install_python_macos ;;
    linux)   install_python_linux ;;
    *)
        echo "Error: Could not detect OS for auto-install. Install Python 3.x manually." >&2
        exit 1
        ;;
esac

install_rc=$?
if [ "$install_rc" -ne 0 ]; then
    echo "Error: Auto-install of Python failed (exit code $install_rc)." >&2
    echo "Install Python 3.x manually and ensure it's on PATH, then retry." >&2
    exit 1
fi

# Refresh PATH for the current shell where possible (winget puts python in
# %LOCALAPPDATA%\Programs\Python\PythonXY which may not be on the existing
# PATH until a new shell starts).
if [ "$OS" = "windows" ]; then
    for v in 3.12 3.11 3.13; do
        candidate="$LOCALAPPDATA/Programs/Python/Python${v//./}"
        if [ -d "$candidate" ]; then
            export PATH="$candidate:$candidate/Scripts:$PATH"
        fi
    done
fi

# Retry running the user command
if run_python "$@"; then
    exit 0
fi

echo "Error: Python install reported success but 'python3'/'python' is still not on PATH." >&2
echo "Open a new terminal and re-run the command." >&2
exit 1
