/* Omarchy -> Zen Browser color sync (omarchy-zen-sync).
 * Rendered by sync.sh from zen-userchrome.css.tpl on every theme change. Zen
 * loads it via the userChrome.css symlink in the profile's chrome/ directory
 * (sync.sh restarts Zen when the rendered CSS changes).
 *
 * Strategy: override only the root variables Zen derives its palette from
 * (see zen-styles/zen-theme.css in omni.ja) and let Zen's color-mix cascade
 * compute every hover/active/panel shade. !important beats the inline styles
 * Zen's workspace gradient picker writes.
 */

:root {
  color-scheme: {{ mode }} !important;

  /* Accent everything derives from */
  --zen-primary-color: {{ accent }} !important;

  /* Base surfaces Zen mixes against */
  --zen-branding-bg: {{ background }} !important;
  --zen-branding-bg-reverse: {{ foreground }} !important;

  /* Text */
  --toolbox-textcolor: {{ foreground }} !important;

  /* Secondary surfaces */
  --zen-themed-toolbar-bg-transparent: {{ background }} !important;
  --zen-dialog-background: {{ dark_background }} !important;
  --zen-in-content-dialog-background: {{ dark_background }} !important;
  --zen-urlbar-background: {{ dark_background }} !important;
  --zen-colors-input-bg: {{ dark_background }} !important;

  /* Borders */
  --zen-colors-border: color-mix(in srgb, {{ foreground }} 18%, transparent) !important;
  --zen-input-border-color: color-mix(in srgb, {{ foreground }} 25%, transparent) !important;

  /* Zen decides light/dark per window/Space (zen.view.window.scheme pref,
   * overridden by the Space gradient's dominant color) — force it to the
   * theme's mode everywhere, otherwise a "light" Space renders dark text on
   * our dark surfaces. Selector list mirrors zen-theme.css's own forcing. */
  --toolbar-color-scheme: {{ mode }} !important;
  --tab-selected-color-scheme: {{ mode }} !important;
}

:root,
#browser,
#navigator-toolbox,
#titlebar,
toolbar,
panel,
menupopup,
.zen-browser-generic-background,
#zen-appcontent-navbar-container,
#zen-appcontent-navbar-wrapper,
#zen-main-app-wrapper,
#urlbar,
#zen-toast-container {
  color-scheme: {{ mode }} !important;
}

/* Text color forced directly, not via variables: at startup zen's scheme
 * detection can race and resolve text vars dark-on-dark until the theme
 * picker JS reapplies them. Direct color removes that dependency. */
#navigator-toolbox,
#titlebar,
#zen-appcontent-navbar-container,
#urlbar-input,
.tabbrowser-tab .tab-label {
  color: {{ foreground }} !important;
}

/* Bookmarks bar text: match the sidebar tab labels. Opaque color only —
 * mixing with transparent kills subpixel antialiasing and distorts the font. */
#PersonalToolbar .toolbarbutton-text {
  color: color-mix(in srgb, {{ foreground }} 88%, {{ background }}) !important;
  font-weight: normal !important;
}

/* The workspace gradient is written as inline style on these two elements,
 * so the override must target the elements themselves. Near-vertical gradient
 * so it stays visible along the sidebar strip (the bottom-right corner is
 * hidden behind web content): selection-tinted top -> background -> strong
 * accent-tinted bottom. */
#zen-browser-background {
  --zen-main-browser-background: linear-gradient(
    170deg,
    color-mix(in srgb, {{ selection }} 60%, {{ background }}) 0%,
    {{ background }} 45%,
    color-mix(in srgb, {{ accent }} 55%, {{ background }}) 100%
  ) !important;
}

#zen-toolbar-background {
  --zen-main-browser-background-toolbar: linear-gradient(
    170deg,
    color-mix(in srgb, {{ selection }} 40%, {{ background }}) 0%,
    {{ background }} 45%,
    color-mix(in srgb, {{ accent }} 35%, {{ background }}) 100%
  ) !important;
}

/* Per-Space variation: same gradient shape, the bottom tint rotates through
 * the theme palette by Space position. Space 1 keeps the accent (rule above). */
:root:has(zen-workspace:nth-of-type(2)[active]) #zen-browser-background {
  --zen-main-browser-background: linear-gradient(
    170deg,
    color-mix(in srgb, {{ selection }} 60%, {{ background }}) 0%,
    {{ background }} 45%,
    color-mix(in srgb, {{ magenta }} 55%, {{ background }}) 100%
  ) !important;
}

:root:has(zen-workspace:nth-of-type(3)[active]) #zen-browser-background {
  --zen-main-browser-background: linear-gradient(
    170deg,
    color-mix(in srgb, {{ selection }} 60%, {{ background }}) 0%,
    {{ background }} 45%,
    color-mix(in srgb, {{ yellow }} 55%, {{ background }}) 100%
  ) !important;
}

:root:has(zen-workspace:nth-of-type(4)[active]) #zen-browser-background {
  --zen-main-browser-background: linear-gradient(
    170deg,
    color-mix(in srgb, {{ selection }} 60%, {{ background }}) 0%,
    {{ background }} 45%,
    color-mix(in srgb, {{ green }} 55%, {{ background }}) 100%
  ) !important;
}

:root:has(zen-workspace:nth-of-type(5)[active]) #zen-browser-background {
  --zen-main-browser-background: linear-gradient(
    170deg,
    color-mix(in srgb, {{ selection }} 60%, {{ background }}) 0%,
    {{ background }} 45%,
    color-mix(in srgb, {{ red }} 55%, {{ background }}) 100%
  ) !important;
}

:root:has(zen-workspace:nth-of-type(6)[active]) #zen-browser-background {
  --zen-main-browser-background: linear-gradient(
    170deg,
    color-mix(in srgb, {{ selection }} 60%, {{ background }}) 0%,
    {{ background }} 45%,
    color-mix(in srgb, {{ cyan }} 55%, {{ background }}) 100%
  ) !important;
}
