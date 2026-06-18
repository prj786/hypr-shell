# hypr-shell — a macOS-style Hyprland + Quickshell desktop (Arch)

An opinionated, installable desktop environment for **Arch Linux**: **Hyprland**
(Wayland compositor, Lua-configured) + **Quickshell** (QML shell — bar, dock,
launcher, notifications, control center, settings app, lock, OSD, clipboard, an
app installer, and a RunCat). One script turns a minimal Arch install into the
full DE.

> **Arch only.** Package install assumes `pacman` + the **AUR**. Arch derivatives
> (EndeavourOS, CachyOS, Garuda, Manjaro) should work. Artix (systemd-free) is
> detected but the service-enable phases are skipped — wire the equivalents into
> your init manually.

## Quick start

```sh
git clone https://github.com/prj786/hypr-shell ~/hypr-shell && cd ~/hypr-shell
bash install.sh              # prompts before each change
# or:
bash install.sh --dry-run    # show everything it would do, change nothing
bash install.sh --yes        # unattended
bash install.sh --check-only # just run the verification checklist
```

**Updating** is the same command — pull and re-run:

```sh
cd ~/hypr-shell && git pull && bash install.sh
```

The installer is fully **re-runnable**: package installs are skipped if already
present, dotfiles are a symlink farm (re-linking is a no-op), and a package that
isn't in the repos is **warned and skipped** rather than aborting the run — so a
single missing package never blocks the rest of the install.

Run it as your **normal user** (not root) — the AUR helper and `makepkg` refuse
root, and the script uses `sudo` only where it must. Then reboot, pick
**“Hyprland (DE)”** at the greetd/ReGreet login screen, and log in. `Super+,` opens
Settings; full keymap in `dotfiles/hypr/SHORTCUTS.md`.

## What it does (phases)

| Phase | Does |
|------|------|
| 00 preflight | tool/network/disk checks; announces the backup policy |
| 10 repos | enables **[multilib]** (Steam + 32-bit libs); bootstraps **paru** |
| 20 packages | installs `packages/common.list` (pacman) + `packages/aur.list` (AUR) |
| 30 services | pipewire/NM/bluetooth/ppd; installs **greetd + ReGreet** (fully-Wayland greeter) + the Wayland session entry |
| 40 gpu | per-vendor Vulkan + VAAPI drivers (Intel `xe` DPMS guard, NVIDIA suspend fix, AMD) |
| 50 dotfiles | symlinks `~/.config/{hypr,quickshell,fresh,kitty,tmux,mise}` (backing up any existing), installs the session target |
| 60 userconfig | default apps (**Fresh** as editor), `EDITOR=fresh`, **mise** Node toolchain (`mise install`), zram (laptops) |
| 90 postcheck | green/red verification checklist |

Everything routes through one `run()`/`sudo_run()` choke point, so `--dry-run` is
genuinely safe and the whole thing is re-runnable.

## Packages

- **`packages/common.list`** — official-repo packages (real Arch names), installed
  with `pacman -S --needed`. Grouped: core session, greeter, audio, network,
  bluetooth, power, terminals, **Qt/KDE utility apps** (Dolphin, Ark, Gwenview,
  Okular, Kate, mpv), GTK browser/editors, utilities, theming + fonts, dev tooling,
  gaming (multilib), tuning, build deps.
- **`packages/aur.list`** — AUR packages (built via paru): just `gpu-screen-recorder`.
  Kept deliberately short. Theme/icon/cursor/accent are owned by the Quickshell
  Settings app (no `nwg-look` or other theme-settings GUI).
- **GPU/Vulkan drivers** are *not* in the lists — phase 40 installs the right set
  for the detected vendor (intel / amd / nvidia).

### Why Qt/KDE for utility apps, GTK for browsers

The shipped file manager / viewers / editor are **Qt/KDE** (Dolphin, Gwenview,
Okular, Kate, Ark) because, with `QT_WAYLAND_DISABLE_WINDOWDECORATION=1`, Qt apps
render **with no titlebar** — just the Hyprland accent border — and theme exactly
to the shell. GTK apps force a client-side headerbar (with its own window buttons)
that can't be hidden, so GTK is kept only where the app dictates it (Firefox/Zen,
Electron apps). **Appearance** (light/dark + accent) is applied across *every*
toolkit by `dotfiles/quickshell/scripts/colorscheme.sh` and toggled live in
**Settings → Theme → App appearance** (defaults to dark):

- **GTK** — gsettings + `gtk-3.0/4.0/settings.ini` (adw-gtk3[-dark]).
- **Qt / KDE** — the **`kde` platform theme** (`plasma-integration`,
  `QT_QPA_PLATFORMTHEME=kde`) reads the full `kdeglobals` colour scheme we write
  and applies our dark colours **and accent** to every KDE/Qt app — *including*
  the item views (Dolphin/Ark file panes) that no env/style trick can reach,
  because KDE apps colour those via `KColorScheme`. Widget style is **Fusion**.
  `plasma-integration` pulls only KF6 libraries (mostly already present via the
  KDE apps) — **no** `plasmashell`/`kwin`/`plasma-desktop`. qt6ct stays as a
  fallback palette. Changing the accent rewrites `kdeglobals` and recolours
  running KDE apps live (plasma-integration watches the file).
- **Icons** — **Reversal**, auto-matched to the accent by hue (`Reversal-<colour>[-dark]`).
- **Cursor** — **Mocu** (`mocu-xcursor`), forced via `XCURSOR_THEME`,
  `~/.icons/default`, GTK, gsettings, qt6ct and kdeglobals so it never flips
  between GTK and Qt apps.

The **app installer** inside the DE (dock “store” button) searches and
installs/removes via **pacman + AUR** (not Flatpak) — actions open a terminal so
you drive the sudo/build steps.

## Safety

- **Never clobbers configs.** An existing `~/.config/hypr` (etc.) is moved to
  `…​.bak.<timestamp>` before the symlink is created; `uninstall.sh` restores it.
- **Symlink farm, not copy** — re-running re-links (no-op); `uninstall.sh` unlinks
  and restores the newest backup. Packages are left installed (use `--purge` to
  also disable the display manager).
- The single most important step is the **`hyprland-session.target`** user unit
  (`BindsTo=graphical-session.target`) — it activates `xdg-desktop-portal` on a
  non-uwsm session. Without it, screen sharing, file pickers, and app/URL handoff
  silently fail.
- **User-state files** (`user-theme.json`, `pinned-apps.json`, `generated/user.lua`)
  are gitignored; committed `*.default` templates seed them only when missing, so a
  fresh clone has working defaults while your edits are never committed or clobbered.

## Repo layout

```
install.sh  uninstall.sh  VERSIONS
lib/      log.sh detect.sh pkg.sh deploy.sh
packages/ common.list  aur.list
phases/   00…90
dotfiles/ hypr/  quickshell/      ← the actual configs, symlinked into ~/.config
systemd/  hyprland-session.target ← the portal-activation fix
system/   greetd/                ← greetd + ReGreet configs, installed to /etc by phase 30
templates/hyprland-de.desktop.in  ← rendered into the wayland-sessions dir
```

## Notes for this hardware (Lunar Lake / Arc 140V)

The `xe` kernel driver has a DPMS-resume bug that can strand a black screen, so the
shipped `hypridle.conf` locks but **never powers the panel off**. If the iGPU ever
tears or hangs, log in once with `DE_SOFTWARE_RENDER=1` set (see
`dotfiles/hypr/start-hyprland.sh`).

## Credits

Designed and built by **scubba**, pair-programmed with **[Claude Code](https://claude.com/claude-code)** (Anthropic's Claude) — which scaffolded the installer, the Quickshell components, and this documentation.

Built on the work of the [Hyprland](https://hypr.land) and [Quickshell](https://quickshell.org) projects.

## License

**GPL-2.0-only** — see [LICENSE](LICENSE). Like the Linux kernel: use it, study it,
share it, and build on it freely; but if you distribute a modified version, your
changes must ship under the same terms (copyleft). Improvements are welcome
upstream via pull request.
