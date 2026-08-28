#!/usr/bin/env bash
# Renders Zen's userChrome.css from the active Omarchy theme, wires Zen
# profiles on first run (idempotent), and restarts Zen only when the rendered
# CSS actually changed. Invoked by Service.qml; safe to run by hand.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$PLUGIN_DIR/zen-userchrome.css.tpl"
COLORS="$HOME/.local/state/omarchy/current/theme/colors.toml"
OUT_DIR="$HOME/.local/state/omarchy-zen-sync"
OUT="$OUT_DIR/zen-userchrome.css"

[[ -f $COLORS ]] || exit 0
command -v omarchy-theme-color >/dev/null 2>&1 || exit 0

mkdir -p "$OUT_DIR"

# --- render ------------------------------------------------------------------

tmp=$(mktemp)
sed_script=$(mktemp)
trap 'rm -f "$tmp" "$sed_script"' EXIT
while IFS=$'\t' read -r key value; do
  printf 's|{{ %s }}|%s|g\n' "$key" "$value"
done < <(omarchy-theme-color --file "$COLORS" --all) >"$sed_script"
sed -f "$sed_script" "$TPL" >"$tmp"

# --- wire Zen profiles (idempotent) ------------------------------------------

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
    mv "$target" "$target.pre-omarchy-zen-sync"
  fi
  [[ $(readlink "$target" 2>/dev/null) == "$OUT" ]] || ln -sfn "$OUT" "$target"
  ensure_user_pref "$profile" "toolkit.legacyUserProfileCustomizations.stylesheets" "true"
}

for base in "$HOME/.config/zen" "$HOME/.zen" "$HOME/.var/app/app.zen_browser.zen/.zen"; do
  ini="$base/profiles.ini"
  [[ -f $ini ]] || continue
  while IFS= read -r rel; do
    profile="$base/$rel"
    [[ -f "$profile/prefs.js" ]] || continue
    wire_profile "$profile"
  done < <(awk -F= '/^IsRelative=1/{rel=1} /^Path=/{path=$2} /^\[/{if (rel && path) print path; rel=0; path=""} END{if (rel && path) print path}' "$ini")
done

# --- apply only on change ----------------------------------------------------

if [[ -f $OUT ]] && cmp -s "$tmp" "$OUT"; then
  exit 0
fi
cp "$tmp" "$OUT"

# --- restart Zen so it reloads userChrome.css --------------------------------

pgrep -x zen-bin >/dev/null || exit 0
pkill -TERM -x zen-bin
for _ in $(seq 1 50); do
  pgrep -x zen-bin >/dev/null || break
  sleep 0.1
done
# Launch via Hyprland so Zen gets the real session environment (DBus/portal);
# a bare shell launch can lose it and the content color-scheme goes light.
hyprctl dispatch exec zen-browser >/dev/null 2>&1 || setsid -f zen-browser >/dev/null 2>&1
