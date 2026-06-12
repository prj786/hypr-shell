# Hyprland Shortcuts

**Mod = Super (Windows key).** Defined in `~/.config/hypr/hyprland.lua`.
Edit that file and reload with **Super + Ctrl + R** (Hyprland also auto-reloads
on save). Ported from the old Qtile bindings so most muscle memory carries over.

## Launching apps

| Shortcut | Action | Program |
|---|---|---|
| `Super` + `Return` | Terminal | `foot` |
| `Super` + `Space` | **Spotlight** search (press again to close) | Quickshell |
| `Super` + `D` | App launcher (same Spotlight) | Quickshell |
| `Super` + `E` | File manager | `nautilus` |
| `Super` + `B` | Web browser | `firefox` |
| `Super` + `C` | Calendar | GNOME Calendar / popup |
| `Super` + `N` | Toggle notification centre | `swaync` |

> The bar + launcher are now **Quickshell** (`~/.config/quickshell/`). The Apple
> glyph at the top-left opens Spotlight. (A Quickshell power menu is on the list.)

## Windows

| Shortcut | Action |
|---|---|
| `Super` + `H` / `J` / `K` / `L` | Focus left / down / up / right |
| `Super` + `Shift` + `H/J/K/L` | Move window in that direction |
| `Super` + `Ctrl` + `H/J/K/L` | Resize the focused window |
| `Super` + `Shift` + `N` | Reset split ratio |
| `Super` + `Q` | Close focused window |
| `Super` + `F` | Fullscreen |
| `Super` + `Shift` + `F` | Maximise (keep bar/gaps) |
| `Super` + `V` | Toggle floating |
| `Super` + `Shift` + `V` | Pseudo-tile |
| `Super` + `T` | Toggle split direction (dwindle) |
| `Super` + `Tab` / `Super` + `Shift` + `Tab` | Cycle to next / previous window |

### Mouse (hold `Super`)

| Action | Result |
|---|---|
| `Super` + drag **left button** | Move window |
| `Super` + drag **right button** | Resize window |
| `Super` + **scroll** | Cycle workspaces |

## Workspaces (1–8)

| Shortcut | Action |
|---|---|
| `Super` + `1`…`8` | Switch to workspace 1–8 |
| `Super` + `Shift` + `1`…`8` | Move focused window to workspace (and follow) |
| 3-finger horizontal swipe | Switch workspaces (touchpad) |

### Scratchpad (Hyprland "special" workspace)

| Shortcut | Action |
|---|---|
| `Super` + `` ` `` (backtick) or `Super` + `S` | Toggle the scratchpad |
| `Super` + `Shift` + `S` | Send focused window to the scratchpad |

## Session

| Shortcut | Action |
|---|---|
| `Super` + `Ctrl` + `R` | Reload Hyprland config |
| `Super` + `Ctrl` + `Q` | Quit Hyprland (log out) |
| `Super` + `Shift` + `B` | Toggle the top bar (Waybar) |
| `Super` + `Shift` + `Space` | Switch keyboard layout (US ↔ Georgian) |
| `Super` + `Alt` + `L` | Lock session |

## Media & hardware keys (no modifier)

| Key | Action |
|---|---|
| `XF86AudioRaiseVolume` / `LowerVolume` | Volume ±5% (`wpctl`) |
| `XF86AudioMute` / `MicMute` | Toggle output / mic mute |
| `XF86AudioPlay` / `Next` / `Prev` | Media control (`playerctl`) |
| `XF86MonBrightnessUp` / `Down` | Brightness ±5% (`brightnessctl`) |

## Screenshots (saved to `~/Pictures/Screenshots` **and** clipboard)

| Shortcut | Action |
|---|---|
| `Print` | Focused monitor |
| `Shift` + `Print` | Select a region |
| `Super` + `Print` | Focused window (instant) |

> Also in the bar: the **camera icon** — Left = region · Right = focused monitor · Middle = focused window.

---

### What changed vs Qtile

- `Super` + `Tab` now **cycles windows** (Hyprland has one global layout, so there
  is no layout to cycle). New: `Super` + `T` toggles the dwindle split, `Super` + `V`
  pseudo-tiles, `Super` + `Shift` + `F` maximises.
- The dropdown terminal/file/music scratchpads became one Hyprland "special"
  workspace (`Super` + backtick / `Super` + `S`). Populate it with `Super` + `Shift` + `S`.
