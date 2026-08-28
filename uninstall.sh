#!/usr/bin/env bash
# omarchy-zen-sync uninstaller: removes the template, the hook, and the
# userChrome.css symlinks (restoring any backed-up userChrome.css).
set -euo pipefail

TPL="$HOME/.config/omarchy/themed/zen-userchrome.css.tpl"
HOOK="$HOME/.config/omarchy/hooks/theme-set.d/50-restart-zen"
RENDERED="$HOME/.local/state/omarchy/current/theme/zen-userchrome.css"

info() { printf '\033[1;34m::\033[0m %s\n' "$*"; }

rm -f "$TPL" && info "Removed template: $TPL"
rm -f "$HOOK" && info "Removed hook: $HOOK"
rm -f "$RENDERED" && info "Removed rendered CSS: $RENDERED"

for base in "$HOME/.config/zen" "$HOME/.zen" "$HOME/.var/app/app.zen_browser.zen/.zen"; do
  [[ -d $base ]] || continue
  for link in "$base"/*/chrome/userChrome.css; do
    [[ -L $link ]] || continue
    [[ $(readlink "$link") == *"/omarchy/current/theme/zen-userchrome.css" ]] || continue
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
