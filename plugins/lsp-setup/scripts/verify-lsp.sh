#!/usr/bin/env bash
# verify-lsp.sh — Verify LSP prerequisites for given languages
# Usage: bash verify-lsp.sh <lang1> [lang2] ...
# Supported: csharp python typescript go rust java kotlin lua php ruby swift cpp
# Output: JSON-like status per language (binary found, PATH issues, env var)

set -euo pipefail

# Map language to binary name
binary_for() {
  case "$1" in
    csharp)     echo "csharp-ls" ;;
    python)     echo "pyright" ;;
    typescript) echo "typescript-language-server" ;;
    go)         echo "gopls" ;;
    rust)       echo "rust-analyzer" ;;
    java)       echo "jdtls" ;;
    kotlin)     echo "kotlin-lsp" ;;
    lua)        echo "lua-language-server" ;;
    php)        echo "intelephense" ;;
    ruby)       echo "ruby-lsp" ;;
    swift)      echo "sourcekit-lsp" ;;
    cpp)        echo "clangd" ;;
    *)          echo "" ;;
  esac
}

# Map language to plugin name
plugin_for() {
  case "$1" in
    csharp)     echo "csharp-lsp" ;;
    python)     echo "pyright-lsp" ;;
    typescript) echo "typescript-lsp" ;;
    go)         echo "gopls-lsp" ;;
    rust)       echo "rust-analyzer-lsp" ;;
    java)       echo "jdtls-lsp" ;;
    kotlin)     echo "kotlin-lsp" ;;
    lua)        echo "lua-lsp" ;;
    php)        echo "php-lsp" ;;
    ruby)       echo "ruby-lsp" ;;
    swift)      echo "swift-lsp" ;;
    cpp)        echo "clangd-lsp" ;;
    *)          echo "" ;;
  esac
}

# Detect environment
detect_env() {
  if [[ "$(uname -s)" == MINGW* ]] || [[ "$(uname -s)" == MSYS* ]]; then
    echo "mingw"
  elif grep -qi microsoft /proc/version 2>/dev/null; then
    echo "wsl"
  elif [[ "$(uname -s)" == Darwin ]]; then
    echo "macos"
  else
    echo "linux"
  fi
}

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <lang1> [lang2] ..."
  echo "Supported: csharp python typescript go rust java kotlin lua php ruby swift cpp"
  exit 1
fi

ENV=$(detect_env)
echo "=== Environment: $ENV ==="
echo ""

# Check ENABLE_LSP_TOOL
SETTINGS_FILE="$HOME/.claude/settings.json"
ENV_OK=false
if [[ -f "$SETTINGS_FILE" ]]; then
  if grep -Eq '"ENABLE_LSP_TOOL"[[:space:]]*:[[:space:]]*"1"' "$SETTINGS_FILE" 2>/dev/null; then
    echo "[OK] ENABLE_LSP_TOOL=1 in $SETTINGS_FILE"
    ENV_OK=true
  elif grep -q '"ENABLE_LSP_TOOL"' "$SETTINGS_FILE" 2>/dev/null; then
    echo "[WARN] ENABLE_LSP_TOOL found but not set to \"1\" in $SETTINGS_FILE"
  else
    echo "[MISSING] ENABLE_LSP_TOOL not set in $SETTINGS_FILE"
  fi
else
  echo "[MISSING] Settings file not found: $SETTINGS_FILE"
fi
echo ""

# Check each language
PASS=0
FAIL=0
if [[ "$ENV_OK" != "true" ]]; then
  FAIL=$((FAIL + 1))
fi
for lang in "$@"; do
  bin=$(binary_for "$lang")
  plugin=$(plugin_for "$lang")

  if [[ -z "$bin" ]]; then
    echo "[$lang] UNKNOWN — not a supported language"
    FAIL=$((FAIL + 1))
    continue
  fi

  bin_path=$(command -v "$bin" 2>/dev/null || true)
  if [[ -n "$bin_path" ]]; then
    echo "[$lang] BINARY OK — $bin found at $bin_path"
    PASS=$((PASS + 1))
  else
    echo "[$lang] BINARY MISSING — $bin not found on PATH"
    FAIL=$((FAIL + 1))

    # Check common non-PATH locations
    if [[ "$lang" == "csharp" ]]; then
      dotnet_path="$HOME/.dotnet/tools/$bin"
      if [[ -f "$dotnet_path" ]]; then
        echo "  HINT: Found at $dotnet_path — add \$HOME/.dotnet/tools to PATH"
      fi
    fi
  fi

  echo "  Plugin: $plugin@claude-plugins-official"
done

echo ""
echo "=== Summary: $PASS OK, $FAIL issues ==="
