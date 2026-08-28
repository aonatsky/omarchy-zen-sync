#!/usr/bin/env bash
# omarchy-zen-sync installer.
# Wires Zen Browser's colors to the active Omarchy theme:
#   1. installs the template into ~/.config/omarchy/themed/
#   2. installs the theme-set hook that restarts Zen after a theme change
#   3. symlinks userChrome.css in every Zen profile to the rendered CSS
#   4. renders the CSS once for the current theme
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL_NAME="zen-userchrome.css.tpl"
HOOK_NAME="50-restart-zen"

THEMED_DIR="$HOME/.config/omarchy/themed"
HOOKS_DIR="$HOME/.config/omarchy/hooks/theme-set.d"
THEME_STATE_DIR="$HOME/.local/state/omarchy/current/theme"
RENDERED_CSS="$THEME_STATE_DIR/zen-userchrome.css"

info()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die()   { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# --- sanity checks ---------------------------------------------------------

command -v omarchy-theme-color >/dev/null 2>&1 ||
  die "omarchy-theme-color not found. This tool needs an Omarchy version with themed templates (~/.config/omarchy/themed support)."

[[ -d $THEME_STATE_DIR ]] ||
  die "No active Omarchy theme state at $THEME_STATE_DIR. Apply a theme first: omarchy theme set <name>"

# --- 1. template -----------------------------------------------------------

mkdir -p "$THEMED_DIR"
cp "$REPO_DIR/$TPL_NAME" "$THEMED_DIR/$TPL_NAME"
info "Template installed: $THEMED_DIR/$TPL_NAME"

# --- 2. hook ---------------------------------------------------------------

mkdir -p "$HOOKS_DIR"
cp "$REPO_DIR/hooks/$HOOK_NAME" "$HOOKS_DIR/$HOOK_NAME"
chmod +x "$HOOKS_DIR/$HOOK_NAME"
info "Hook installed: $HOOKS_DIR/$HOOK_NAME"

# --- 3. render once for the current theme ----------------------------------

render() {
  local colors="$THEME_STATE_DIR/colors.toml"
  [[ -f $colors ]] || { warn "Current theme has no colors.toml — skipping initial render (it will render on the next theme change)."; return; }

  local sed_script
  sed_script=$(mktemp)
  while IFS=$'\t' read -r key value; do
    printf 's|{{ %s }}|%s|g\n' "$key" "$value"
  done < <(omarchy-theme-color --file "$colors" --all) >"$sed_script"
  sed -f "$sed_script" "$THEMED_DIR/$TPL_NAME" >"$RENDERED_CSS"
  rm -f "$sed_script"

  if grep -q '{{' "$RENDERED_CSS"; then
    warn "Some template variables did not resolve — check $RENDERED_CSS"
  else
    info "Rendered CSS for the current theme: $RENDERED_CSS"
  fi
}
render

# --- 4. wire Zen profiles --------------------------------------------------

ensure_user_pref() {
  local profile="$1" pref="$2" value="$3"
  local user_js="$profile/user.js"
  local line="user_pref(\"$pref\", $value);"

  if [[ -f $user_js ]] && grep -qxF "$line" "$user_js"; then
    return
  fi
  if [[ -f $user_js ]] && grep -qF "\"$pref\"" "$user_js"; then
    grep -vF "\"$pref\"" "$user_js" >"$user_js.tmp" && mv "$user_js.tmp" "$user_js"
  fi
  echo "$line" >>"$user_js"
}

wire_profile() {
  local profile="$1"
  local chrome="$profile/chrome"
  local target="$chrome/userChrome.css"

  mkdir -p "$chrome"

  if [[ -f $target && ! -L $target ]]; then
    local backup="$target.pre-omarchy-zen-sync"
    mv "$target" "$backup"
    warn "Existing userChrome.css backed up to $backup — re-add your own rules via @import if needed."
  fi

  ln -sfn "$RENDERED_CSS" "$target"
  ensure_user_pref "$profile" "toolkit.legacyUserProfileCustomizations.stylesheets" "true"
  info "Wired profile: $profile"
}

wired=0
for base in "$HOME/.config/zen" "$HOME/.zen" "$HOME/.var/app/app.zen_browser.zen/.zen"; do
  ini="$base/profiles.ini"
  [[ -f $ini ]] || continue

  while IFS= read -r rel; do
    profile="$base/$rel"
    # Skip placeholder profiles Zen created but never ran
    [[ -f "$profile/prefs.js" ]] || continue
    wire_profile "$profile"
    wired=$((wired + 1))
  done < <(awk -F= '/^IsRelative=1/{rel=1} /^Path=/{path=$2} /^\[/{if (rel && path) print path; rel=0; path=""} END{if (rel && path) print path}' "$ini")
done

[[ $wired -gt 0 ]] || die "No used Zen profiles found (looked in ~/.config/zen, ~/.zen, flatpak). Start Zen once, then re-run."

# --- done -------------------------------------------------------------------

echo
info "Done. Restart Zen to load the current theme colors:"
echo "     $HOOKS_DIR/$HOOK_NAME"
echo
info "From now on 'omarchy theme set <name>' re-renders Zen's colors and restarts it automatically."
