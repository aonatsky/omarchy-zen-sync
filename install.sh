#!/usr/bin/env bash
# Manual (hook mode) installer, for setups that don't run Omarchy shell
# plugins. Copies the renderer and template to ~/.local/share/omarchy-zen-sync,
# installs a theme-set hook that runs it, and runs it once now. The renderer
# (sync.sh) is the same hardened code path the plugin uses.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARE_DIR="$HOME/.local/share/omarchy-zen-sync"
HOOK_DIR="$HOME/.config/omarchy/hooks/theme-set.d"
HOOK="$HOOK_DIR/50-zen-sync"

info() { printf '\033[1;34m::\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

command -v omarchy-theme-color >/dev/null 2>&1 ||
  die "omarchy-theme-color not found. This tool needs an Omarchy version that ships it."

mkdir -p -m 700 -- "$SHARE_DIR"
cp -- "$REPO_DIR/sync.sh" "$REPO_DIR/zen-userchrome.css.tpl" "$SHARE_DIR/"
chmod +x -- "$SHARE_DIR/sync.sh"
info "Renderer installed: $SHARE_DIR"

mkdir -p -- "$HOOK_DIR"
tmp=$(mktemp -- "$HOOK_DIR/.50-zen-sync.XXXXXX")
printf '#!/bin/bash\nexec "%s/sync.sh"\n' "$SHARE_DIR" >"$tmp"
chmod +x -- "$tmp"
mv -f -- "$tmp" "$HOOK"
info "Hook installed: $HOOK"

"$SHARE_DIR/sync.sh"
info "Initial sync done. Every 'omarchy theme set <name>' now re-renders Zen's colors and restarts Zen when needed."
