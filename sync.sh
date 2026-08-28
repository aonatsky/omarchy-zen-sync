#!/usr/bin/env bash
# Renders Zen's userChrome.css from the active Omarchy theme, wires Zen
# profiles (idempotent), and restarts Zen only when the rendered CSS changed.
# Single code path used by Service.qml (plugin mode) and by the theme-set hook
# (manual mode). Safe to run by hand.
#
# Hardening notes:
# - Theme keys/values are treated strictly as data: keys must match
#   [a-z0-9_]+, values must match an allowlisted color grammar. Nothing from
#   the theme is ever used to build executable syntax (no generated sed/awk).
# - profiles.ini entries are canonicalized and must resolve strictly beneath
#   the profile root; escaping, absolute, symlinked, or non-directory entries
#   are rejected.
# - Every read is a size-capped regular-file read (no symlinks, FIFOs, or
#   devices); every write goes through an unpredictable same-directory
#   temporary followed by an atomic rename.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$SELF_DIR/zen-userchrome.css.tpl"
COLORS="$HOME/.local/state/omarchy/current/theme/colors.toml"
OUT_DIR="$HOME/.local/state/omarchy-zen-sync"
OUT="$OUT_DIR/zen-userchrome.css"
MAX_INPUT_BYTES=65536
PREF_LINE='user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'

# Keep ${var//pat/repl} replacements literal (bash 5.2's patsub_replacement
# would otherwise expand & and \ inside the replacement).
shopt -u patsub_replacement 2>/dev/null || true

# Regular file, not a symlink, non-empty, size-capped. Refuses FIFOs, devices,
# and oversized inputs before any read happens.
safe_regular() {
  local f="$1" size
  [[ -f $f && ! -L $f ]] || return 1
  size=$(stat -c %s -- "$f" 2>/dev/null) || return 1
  ((size > 0 && size <= MAX_INPUT_BYTES))
}

command -v omarchy-theme-color >/dev/null 2>&1 || exit 0
safe_regular "$COLORS" || exit 0
safe_regular "$TPL" || exit 0

# --- render ------------------------------------------------------------------

KEY_RE='^[a-z0-9_]+$'
VALUE_RE='^(#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?|[0-9]{1,3}(,[0-9]{1,3}){2}|light|dark)$'

render_css() {
  local content key value
  content=$(<"$TPL")
  while IFS=$'\t' read -r key value; do
    [[ $key =~ $KEY_RE ]] || continue
    [[ $value =~ $VALUE_RE ]] || continue
    content=${content//"{{ ${key} }}"/${value}}
  done < <(omarchy-theme-color --file "$COLORS" --all 2>/dev/null | head -c "$MAX_INPUT_BYTES")
  # A leftover token means a missing or rejected value: don't ship broken CSS.
  [[ $content != *'{{'* ]] || return 1
  printf '%s\n' "$content"
}

css=$(render_css) || exit 0

# --- write the rendered CSS atomically ----------------------------------------

mkdir -p -m 700 -- "$OUT_DIR"
[[ -d $OUT_DIR && ! -L $OUT_DIR ]] || exit 0

changed=1
tmp=$(mktemp -- "$OUT_DIR/.render.XXXXXX")
printf '%s' "$css" >"$tmp"
if [[ -f $OUT && ! -L $OUT ]] && cmp -s -- "$tmp" "$OUT"; then
  rm -f -- "$tmp"
  changed=0
else
  mv -f -- "$tmp" "$OUT"
fi

# --- wire Zen profiles (idempotent) --------------------------------------------

wire_profile() {
  local base_real="$1" profile="$2"
  local profile_real chrome target user_js tmp_link tmp_js

  # The profile must be a real directory that canonicalizes strictly beneath
  # the profile root.
  [[ -d $profile && ! -L $profile ]] || return 0
  profile_real=$(realpath -e -- "$profile" 2>/dev/null) || return 0
  [[ $profile_real == "$base_real"/* ]] || return 0

  chrome="$profile_real/chrome"
  if [[ -e $chrome || -L $chrome ]]; then
    [[ -d $chrome && ! -L $chrome ]] || return 0
  else
    mkdir -- "$chrome" || return 0
  fi

  # Back up a pre-existing regular userChrome.css once; never follow or
  # overwrite anything that isn't ours.
  target="$chrome/userChrome.css"
  if [[ ! -L $target && -e $target ]]; then
    [[ -f $target ]] || return 0
    mv -n -- "$target" "$target.pre-omarchy-zen-sync" || return 0
    [[ ! -e $target ]] || return 0
  fi

  # Atomic symlink replacement: create under a temporary name, rename over.
  tmp_link=$(mktemp -u -- "$chrome/.userChrome.XXXXXX")
  ln -sn -- "$OUT" "$tmp_link" || return 0
  mv -Tf -- "$tmp_link" "$target" || { rm -f -- "$tmp_link"; return 0; }

  # user.js: only ever touch a regular, sanely sized file (or create one).
  user_js="$profile_real/user.js"
  if [[ -L $user_js ]] || [[ -e $user_js && ! -f $user_js ]]; then
    return 0
  fi
  if [[ -f $user_js ]]; then
    safe_regular "$user_js" || return 0
    grep -qxF -- "$PREF_LINE" "$user_js" && return 0
    tmp_js=$(mktemp -- "$profile_real/.user.js.XXXXXX")
    grep -vF -- '"toolkit.legacyUserProfileCustomizations.stylesheets"' "$user_js" >"$tmp_js" || true
  else
    tmp_js=$(mktemp -- "$profile_real/.user.js.XXXXXX")
  fi
  printf '%s\n' "$PREF_LINE" >>"$tmp_js"
  mv -f -- "$tmp_js" "$user_js"
}

for base in "$HOME/.config/zen" "$HOME/.zen" "$HOME/.var/app/app.zen_browser.zen/.zen"; do
  ini="$base/profiles.ini"
  safe_regular "$ini" || continue
  base_real=$(realpath -e -- "$base" 2>/dev/null) || continue

  while IFS= read -r rel; do
    # Reject empty, absolute, escaping, backslashed, or dot-dot entries
    # outright ("*..*" is deliberately stricter than path semantics require).
    case $rel in
      '' | /* | *..* | *\\* | .* ) continue ;;
    esac
    [[ -f "$base/$rel/prefs.js" ]] || continue
    wire_profile "$base_real" "$base/$rel"
  done < <(awk -F= '/^IsRelative=1/{rel=1} /^Path=/{path=$2} /^\[/{if (rel && path) print path; rel=0; path=""} END{if (rel && path) print path}' "$ini")
done

# --- restart Zen only when the CSS actually changed ---------------------------

((changed)) || exit 0
pgrep -x zen-bin >/dev/null || exit 0
pkill -TERM -x zen-bin
for _ in $(seq 1 50); do
  pgrep -x zen-bin >/dev/null || break
  sleep 0.1
done
# Launch via Hyprland so Zen gets the real session environment (DBus/portal);
# a bare shell launch can lose it and the content color-scheme goes light.
hyprctl dispatch exec zen-browser >/dev/null 2>&1 || setsid -f zen-browser >/dev/null 2>&1
