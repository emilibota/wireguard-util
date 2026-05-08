#!/bin/sh
set -eu

# Determine install dirs (must mirror install.sh)
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

remove_file() {
  if [ -f "$1" ]; then
    rm -f "$1"
    printf 'Removed %s\n' "$1"
  fi
}

remove_wgu_block() {
  _file="$1"
  if [ -f "$_file" ] && grep -qF '# BEGIN wgu' "$_file" 2>/dev/null; then
    _tmp="$(mktemp)"
    sed '/# BEGIN wgu/,/# END wgu/d' "$_file" > "$_tmp"
    mv "$_tmp" "$_file"
    printf 'Cleaned %s\n' "$_file"
  fi
}

# Remove binaries
remove_file "$INSTALL_DIR/wg-util.sh"
remove_file "$INSTALL_DIR/wgu"

# Remove bash completions
remove_file "$BASH_COMP_DIR/wgu"
if [ "$IS_ROOT" -eq 0 ]; then
  remove_wgu_block "$HOME/.bashrc"
fi

# Remove zsh completions
if [ "$IS_ROOT" -eq 1 ]; then
  ZSH_COMP_DIR="$(zsh -c 'echo ${(j: :)fpath}' 2>/dev/null | tr ' ' '\n' | grep site-functions | head -1 || true)"
  [ -n "$ZSH_COMP_DIR" ] || ZSH_COMP_DIR="/usr/local/share/zsh/site-functions"
fi
remove_file "$ZSH_COMP_DIR/_wgu"
if [ "$IS_ROOT" -eq 0 ]; then
  remove_wgu_block "$HOME/.zshrc"
fi

printf '\nUninstall complete.\n'
