#!/usr/bin/env bash
# omarchy-zen-sync uninstaller: removes hook-mode artifacts, rendered CSS
# state, and the userChrome.css symlinks (restoring any backed-up
# userChrome.css). Plugin mode itself is removed with:
#   omarchy plugin remove io.github.aonatsky.zen-sync
set -euo pipefail

SHARE_DIR="$HOME/.local/share/omarchy-zen-sync"
STATE_DIR="$HOME/.local/state/omarchy-zen-sync"
HOOK_DIR="$HOME/.config/omarchy/hooks/theme-set.d"
# Current + legacy (pre-1.0.1) artifact paths.
LEGACY_TPL="$HOME/.config/omarchy/themed/zen-userchrome.css.tpl"
LEGACY_RENDERED="$HOME/.local/state/omarchy/current/theme/zen-userchrome.css"

info() { printf '\033[1;34m::\033[0m %s\n' "$*"; }

rm -f -- "$HOOK_DIR/50-zen-sync" "$HOOK_DIR/50-restart-zen"
rm -rf -- "$SHARE_DIR" "$STATE_DIR"
rm -f -- "$LEGACY_TPL" "$LEGACY_RENDERED"
info "Removed renderer, hooks, and rendered CSS"

for base in "$HOME/.config/zen" "$HOME/.zen" "$HOME/.var/app/app.zen_browser.zen/.zen"; do
  [[ -d $base ]] || continue
  for link in "$base"/*/chrome/userChrome.css; do
    [[ -L $link ]] || continue
    case $(readlink -- "$link") in
      *"/omarchy-zen-sync/zen-userchrome.css" | *"/omarchy/current/theme/zen-userchrome.css") ;;
      *) continue ;;
    esac
    rm -f -- "$link"
    backup="$link.pre-omarchy-zen-sync"
    if [[ -f $backup && ! -L $backup ]]; then
      mv -n -- "$backup" "$link"
      info "Restored original userChrome.css in ${link%/chrome/*}"
    else
      info "Removed symlink: $link"
    fi
  done
done

info "Done. Restart Zen to go back to its own theming."
