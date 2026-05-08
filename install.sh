#!/bin/sh
set -eu

WG_UTIL_URL="https://raw.githubusercontent.com/emilibota/wireguard-util/main/wg-util.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UTIL="$SCRIPT_DIR/wg-util.sh"

if [ ! -f "$UTIL" ]; then
  printf 'wg-util.sh not found locally; downloading...\n'
  UTIL="$(mktemp)"
  _UTIL_TMPFILE="$UTIL"
  curl -fsSL "$WG_UTIL_URL" -o "$UTIL" || { printf 'Error: failed to download wg-util.sh\n' >&2; exit 1; }
fi

# Determine install dir
if [ "$(id -u)" -eq 0 ]; then
  INSTALL_DIR="/usr/local/bin"
  BASH_COMP_DIR="/etc/bash_completion.d"
  ZSH_COMP_DIR=""
  IS_ROOT=1
else
  INSTALL_DIR="$HOME/.local/bin"
  BASH_COMP_DIR="$HOME/.bash_completion.d"
  ZSH_COMP_DIR="$HOME/.zsh/completions"
  IS_ROOT=0
fi

# Create install dir if needed
if [ ! -d "$INSTALL_DIR" ]; then
  mkdir -p "$INSTALL_DIR"
  printf 'Created %s\n' "$INSTALL_DIR"
fi

# Warn if install dir not in PATH
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    printf 'Warning: %s is not in your PATH.\n' "$INSTALL_DIR"
    printf 'Add this to your shell profile:\n'
    printf '  export PATH="%s:$PATH"\n\n' "$INSTALL_DIR" ;;
esac

# Copy wg-util.sh
cp "$UTIL" "$INSTALL_DIR/wg-util.sh"
chmod 755 "$INSTALL_DIR/wg-util.sh"
printf 'Installed wg-util.sh -> %s/wg-util.sh\n' "$INSTALL_DIR"

# Create wgu wrapper
WGU="$INSTALL_DIR/wgu"
printf '#!/bin/sh\nexec "%s/wg-util.sh" "$@"\n' "$INSTALL_DIR" > "$WGU"
chmod 755 "$WGU"
printf 'Installed wrapper    -> %s\n' "$WGU"

# Install bash completions
mkdir -p "$BASH_COMP_DIR"
"$INSTALL_DIR/wg-util.sh" completions bash > "$BASH_COMP_DIR/wgu"
printf 'Installed bash completions -> %s/wgu\n' "$BASH_COMP_DIR"

if [ "$IS_ROOT" -eq 0 ]; then
  # Ensure ~/.bashrc sources bash_completion.d
  BASHRC="$HOME/.bashrc"
  if [ -f "$BASHRC" ] && grep -qF '# BEGIN wgu' "$BASHRC" 2>/dev/null; then
    : # already present
  else
    cat >> "$BASHRC" <<'EOF'

# BEGIN wgu
for f in "$HOME/.bash_completion.d/"*; do [ -f "$f" ] && . "$f"; done
# END wgu
EOF
    printf 'Added bash completion sourcing to %s\n' "$BASHRC"
  fi
fi

# Install zsh completions
if command -v zsh >/dev/null 2>&1; then
  if [ "$IS_ROOT" -eq 1 ]; then
    # Detect zsh site-functions directory
    ZSH_COMP_DIR="$(zsh -c 'echo ${(j: :)fpath}' 2>/dev/null | tr ' ' '\n' | grep site-functions | head -1 || true)"
    [ -n "$ZSH_COMP_DIR" ] || ZSH_COMP_DIR="/usr/local/share/zsh/site-functions"
  fi
  mkdir -p "$ZSH_COMP_DIR"
  "$INSTALL_DIR/wg-util.sh" completions zsh > "$ZSH_COMP_DIR/_wgu"
  printf 'Installed zsh completions  -> %s/_wgu\n' "$ZSH_COMP_DIR"

  if [ "$IS_ROOT" -eq 0 ]; then
    ZSHRC="$HOME/.zshrc"
    if [ -f "$ZSHRC" ] && grep -qF '# BEGIN wgu' "$ZSHRC" 2>/dev/null; then
      : # already present
    else
      printf '\n# BEGIN wgu\nfpath=("%s" $fpath)\nautoload -Uz compinit && compinit\n# END wgu\n' "$ZSH_COMP_DIR" >> "$ZSHRC"
      printf 'Added zsh fpath + compinit to %s\n' "$ZSHRC"
    fi
  fi
else
  printf 'zsh not found; skipping zsh completions.\n'
fi

[ -n "${_UTIL_TMPFILE:-}" ] && rm -f "$_UTIL_TMPFILE"

printf '\nInstall complete.\n'
printf 'Run: wgu -h\n'
if [ "$IS_ROOT" -eq 0 ]; then
  printf 'Reload completions: source ~/.bashrc  (or open a new shell)\n'
fi
