# omarchy-zen-sync

Sync [Zen Browser](https://zen-browser.app/)'s interface colors with your active
[Omarchy](https://omarchy.org/) theme — automatically, on every `omarchy theme set`.

No patched builds, no Zen Mods, no manual color picking. The whole thing is one
CSS template rendered by Omarchy's native theming engine, plus a tiny hook that
restarts Zen so it picks the colors up.

## How it works

Zen derives its entire UI palette from a handful of root CSS variables
(`--zen-primary-color`, `--zen-branding-bg`, `--toolbox-textcolor`, …) via
`color-mix()`. Instead of restyling elements one by one, this project overrides
**only those root variables** with your Omarchy theme colors and lets Zen
compute every hover/active/panel shade itself. That's why it looks native with
any theme — dark or light.

The pipeline:

```
omarchy theme set <name>
  └─ renders ~/.config/omarchy/themed/zen-userchrome.css.tpl   (native Omarchy templates)
       └─ ~/.local/state/omarchy/current/theme/zen-userchrome.css
            └─ symlinked as userChrome.css in your Zen profile
  └─ theme-set hook gracefully restarts Zen (session restores)
```

## Features

- **Full palette sync** — accent, backgrounds, text, borders, dialogs, urlbar,
  all derived from the theme's `colors.toml`.
- **Light & dark themes** — `color-scheme` follows the theme's mode, and is
  forced consistently so a Space's custom gradient can't flip parts of the UI
  into the wrong scheme (no more dark-on-dark text).
- **Theme-colored background gradient** — a near-vertical gradient along the
  sidebar: selection tint → background → accent tint.
- **Per-Space gradient variants** — each Zen Space gets its own bottom tint,
  rotating through the theme palette (see table below), so you can tell Spaces
  apart at a glance while everything stays on-theme.
- **Automatic restart** — a `theme-set` hook restarts Zen after every theme
  change (Zen only reads `userChrome.css` at startup). Zen's session restore
  brings all tabs back.

### Per-Space tints

| Space | Gradient bottom color |
|-------|-----------------------|
| 1     | `accent`              |
| 2     | `magenta`             |
| 3     | `yellow`              |
| 4     | `green`               |
| 5     | `red`                 |
| 6     | `cyan`                |

(`magenta` comes second because in many themes `accent` *is* `blue`.)

## Requirements

- Omarchy with native user-template support — the version that renders
  `~/.config/omarchy/themed/*.tpl` and ships `omarchy-theme-color`
- Zen Browser (AUR `zen-browser-bin`, tarball, or flatpak)
- Hyprland (used to restart Zen with the correct session environment; falls
  back to `setsid` elsewhere)

## Install

```bash
git clone https://github.com/aonatsky/omarchy-zen-sync.git
cd omarchy-zen-sync
./install.sh
```

The installer:

1. copies the template to `~/.config/omarchy/themed/zen-userchrome.css.tpl`
2. installs the restart hook to `~/.config/omarchy/hooks/theme-set.d/50-restart-zen`
3. renders the CSS once for your current theme
4. finds every used Zen profile, enables
   `toolkit.legacyUserProfileCustomizations.stylesheets`, and symlinks
   `chrome/userChrome.css` to the rendered file (an existing `userChrome.css`
   is backed up, never deleted)

Then restart Zen once (or run the hook: `~/.config/omarchy/hooks/theme-set.d/50-restart-zen`).
From that point on, every `omarchy theme set <name>` does everything by itself.

## Customization

Everything lives in one file: `~/.config/omarchy/themed/zen-userchrome.css.tpl`.
Any Omarchy color key works as `{{ key }}` (plus `{{ key_rgb }}`, `{{ key_strip }}`,
`{{ mode }}`, and `{{ mix a b 30% }}`). After editing, re-apply your theme:
`omarchy theme set "$(omarchy theme current)"`.

Common tweaks:

- **Gradient strength** — the `color-mix(... 55%, ...)` percentages.
- **Gradient direction** — the `170deg` angle (near-vertical keeps it visible
  along the sidebar; diagonal corners hide behind the web content).
- **Per-Space colors** — reorder the `{{ magenta }}` / `{{ yellow }}` / … tokens
  in the `nth-of-type(N)` blocks.
- **Bookmarks bar text** — tuned to match the tab labels; adjust the `88%` mix.

## Troubleshooting

**Web content / new-tab renders light on a dark theme.** Zen was launched
without the session's DBus/portal environment, so it can't read the system
color scheme. Restart it from your launcher or via the hook (which uses
`hyprctl dispatch exec` exactly for this reason).

**Zen's theme picker still shows old gradient dots.** The picker edits Zen's
stored per-Space gradient, which this project overrides — it's inert. Reset the
Space gradients to default in the picker if the stale state bothers you.

**Colors didn't change after `omarchy theme set`.** The theme must ship a
`colors.toml` (all stock themes do). Also check that the hook is executable:
`ls -l ~/.config/omarchy/hooks/theme-set.d/50-restart-zen`.

## Uninstall

```bash
./uninstall.sh
```

Removes the template, the hook, and the symlinks; restores any backed-up
`userChrome.css`.

## License

MIT
