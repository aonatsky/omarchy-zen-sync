#!/usr/bin/env bash
# omarchy-zen-sync uninstaller: removes hook-mode artifacts (template, hook),
# plugin-mode artifacts (rendered CSS state dir), and the userChrome.css
# symlinks, restoring any backed-up userChrome.css.
# Plugin itself: omarchy plugin remove io.github.aonatsky.zen-sync
set -euo pipefail

TPL="$HOME/.config/omarchy/themed/zen-userchrome.css.tpl"
HOOK="$HOME/.config/omarchy/hooks/theme-set.d/50-restart-zen"
RENDERED_HOOK_MODE="$HOME/.local/state/omarchy/current/theme/zen-userchrome.css"
STATE_DIR="$HOME/.local/state/omarchy-zen-sync"

info() { printf '\033[1;34m::\033[0m %s\n' "$*"; }

rm -f "$TPL" && info "Removed template: $TPL"
rm -f "$HOOK" && info "Removed hook: $HOOK"
rm -f "$RENDERED_HOOK_MODE"
rm -rf "$STATE_DIR" && info "Removed rendered CSS state: $STATE_DIR"

for base in "$HOME/.config/zen" "$HOME/.zen" "$HOME/.var/app/app.zen_browser.zen/.zen"; do
  [[ -d $base ]] || continue
  for link in "$base"/*/chrome/userChrome.css; do
    [[ -L $link ]] || continue
    case $(readlink "$link") in
      *"/omarchy/current/theme/zen-userchrome.css" | *"/omarchy-zen-sync/zen-userchrome.css") ;;
      *) continue ;;
    esac
    rm -f "$link"
    backup="$link.pre-omarchy-zen-sync"
    if [[ -f $backup ]]; then
      mv "$backup" "$link"
      info "Restored original userChrome.css in ${link%/chrome/*}"
    else
      info "Removed symlink: $link"
    fi
  done
done

info "Done. Restart Zen to go back to its own theming."
