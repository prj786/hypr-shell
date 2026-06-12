# Hyprland desktop (Lua) — macOS-style

A from-scratch replacement for the old Qtile `desktop_env`, built on **Hyprland
0.55+** configured in **Lua** (`hyprland.lua`), with a **macOS-style Waybar top
bar** as the centrepiece. Gruvbox dark throughout, the same Super-based vim
keybindings, and the same Wayland/Qt/GTK environment carried over from Qtile.

> **Lua, confirmed.** Since Hyprland 0.55 (2026) the config language *is* Lua —
> `~/.config/hypr/hyprland.lua` is loaded in preference to the deprecated
> `hyprland.conf`. So "Hyprland with Lua" was exactly right.

## Status

Configuration is **complete and statically validated** (Lua parses, Waybar JSON
is valid, every Nerd-Font glyph used is present, all scripts pass `bash -n`).
The only remaining step needs **root** — installing the packages and removing the
Qtile RPM. Run:

```bash
bash ~/.config/hypr/install.sh
```

That enables the right COPR, installs Hyprland + Waybar + the few missing tools,
registers the **"Hyprland (DE)"** GDM session, and removes Qtile. Then log out of
GNOME and pick **Hyprland (DE)** from the gear menu on the login screen.

GNOME is left completely untouched — it stays your fallback session.

## Why the ashbuk COPR (not solopasha)

Hyprland isn't in Fedora's official repos. The usual `solopasha/hyprland` COPR
was still on 0.51 for Fedora 44 (pre-Lua); **`ashbuk/Hyprland-Fedora` ships
0.55.1**, which is what the Lua config needs. `install.sh` enables it for you.

## Layout

```
~/.config/hypr/
├── hyprland.lua          # main config: env, look&feel, input, keybinds, rules, autostart
├── colors.lua            # Gruvbox palette (single source of truth, mirrors Waybar CSS)
├── start-hyprland.sh     # session wrapper (desktop identity + software-render escape hatch)
├── hyprland-de.desktop   # GDM session entry (installed to /usr/local/share by install.sh)
├── install.sh            # the one root step
├── scripts/
│   ├── autostart.sh      # run-once daemons: quickshell, swaync, polkit, tray, idle, wallpaper
│   ├── wallpaper.sh      # swaybg (drop ~/.config/hypr/wallpaper.jpg)
│   ├── screenshot.sh     # grim/slurp → file + clipboard
│   ├── lock.sh           # hyprlock || swaylock(gruvbox) || gtklock
│   ├── install-sf-pro.sh # fetch Apple SF Pro fonts (user-level)
│   └── calendar.sh       # Super+C
├── SHORTCUTS.md          # every keybinding
└── README.md
~/.config/quickshell/     # the shell: Bar.qml (top bar) + Spotlight.qml (launcher)
│   ├── shell.qml            # entry point
│   ├── Theme.qml            # graphite-dark + SF Pro tokens (macOS redesign)
│   ├── Bar.qml              # top bar (currently a 1:1 gruvbox Waybar replica)
│   └── Spotlight.qml        # Super+Space fuzzy launcher
~/.config/xdg-desktop-portal/hyprland-portals.conf
```

## The top bar (the feature)

A thin, flush, full-width bar that reads like the macOS menu bar but in Gruvbox:

- **Left** — Apple  menu (left-click = power/session, right-click = app launcher)
  and the **focused app title** in bold.
- **Centre** — workspaces 1–8 as pills; the active one gets a yellow-tinted pill.
- **Right** — a restrained, monochrome status cluster (tray, brightness, volume,
  bluetooth, network, battery), a control-centre bell (swaync), and a macOS-style
  12-hour clock with a calendar tooltip.

It's translucent and **frosted by Hyprland's blur**; items get rounded hover
highlights. Text is Adwaita Sans, glyphs are Hurmit Nerd Font (both already
installed). Toggle it with `Super`+`Shift`+`B`.

## GPU notes (Lunar Lake / Arc 140V, `xe` driver)

Carried over from the Qtile setup's hard-won findings:

- The `xe` hardware-cursor plane is flaky (`drmModeAtomicCommit: Invalid argument`
  + a PSR2 selective-fetch bug) → cursor freeze/garble. Fixed in `hyprland.lua`
  via `cursor:no_hardware_cursors = true` (the Hyprland equivalent of the old
  `WLR_NO_HARDWARE_CURSORS=1`).
- If the screen ever tears/hangs/corrupts: log in once with `DE_SOFTWARE_RENDER=1`
  in your environment (the `start-hyprland.sh` wrapper honours it), or boot with
  the kernel param `xe.enable_psr=0`.

## Theming

Colours live once in `colors.lua` (Hyprland) and the matching hex in
`quickshell/Bar.qml` (and `Theme.qml` for the redesign). GTK/Qt theming (adw-gtk3-dark + qt6ct)
comes from the packages `install.sh` lays down; the env that wires Qt/GTK to
Wayland is set in `hyprland.lua` via `hl.env()`.

## Future work (deliberately not done yet — quality over quantity)

This first pass nails the foundation + the bar. Natural next features:

- A proper **hyprlock** + **hypridle** config (currently swaylock/swayidle).
- A real **dropdown terminal** pinned to the scratchpad (Super+backtick).
- A **control-centre panel** (swaync styling + quick toggles) and a themed
  swaync `style.css`.
- Per-monitor `hl.monitor` rules; **hyprpaper**/wallpaper rotation.
- CPU/mem/temp in a secondary bar or the control centre (the old Qtile bar had
  these; the macOS bar intentionally stays minimal).

## Reverting

The old Qtile config is backed up at **`~/qtile-backup-*.tar.gz`**. To restore:
`tar xzf ~/qtile-backup-*.tar.gz -C ~/.config` and reinstall qtile
(`sudo dnf install qtile`). GNOME was never modified.
