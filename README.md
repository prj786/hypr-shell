# hyprdots — a macOS-style Hyprland + Quickshell desktop

An opinionated, installable desktop environment: **Hyprland** (Wayland compositor,
Lua-configured) + **Quickshell** (QML shell — bar, dock, launcher, notifications,
control center, settings app, lock, OSD, clipboard, app store, and a RunCat). One
script turns a minimal base install into the full DE.

## Quick start

```sh
git clone <this-repo> ~/hyprdots && cd ~/hyprdots
bash install.sh              # prompts before each change
# or:
bash install.sh --dry-run    # show everything it would do, change nothing
bash install.sh --yes        # unattended
bash install.sh --check-only # just run the verification checklist
```

Then reboot, pick **“Hyprland (DE)”** at the login screen, and log in.
`Super+,` opens Settings; full keymap in `dotfiles/hypr/SHORTCUTS.md`.

## What it does (phases)

| Phase | Does |
|------|------|
| 00 preflight | tool/network/disk checks; announces the backup policy |
| 10 repos | AUR helper (Arch) · COPRs + RPM Fusion (Fedora) · OBS (openSUSE) |
| 20 packages | maps `packages/common.list` → native names, installs in one batch |
| 30 services | pipewire/NM/bluetooth/ppd; renders the Wayland session entry; enables greetd/SDDM |
| 40 gpu | per-vendor config (Intel `xe` DPMS guard, NVIDIA suspend fix, AMD no-op) |
| 50 dotfiles | symlinks `~/.config/{hypr,quickshell}` (backing up any existing), installs the session target |
| 60 userconfig | default apps, `EDITOR=nvim`, zram (laptops) |
| 90 postcheck | green/red verification checklist |

Everything routes through one `run()`/`sudo_run()` choke point, so `--dry-run` is
genuinely safe and the whole thing is re-runnable.

## Safety

- **Never clobbers configs.** An existing `~/.config/hypr` (etc.) is moved to
  `…​.bak.<timestamp>` before the symlink is created. `uninstall.sh` restores it.
- **Symlink farm, not copy** — re-running re-links (no-op); `uninstall.sh` unlinks
  and restores the newest backup. Packages are left installed (use `--purge` to also
  disable the display manager).
- The single most important step is the **`hyprland-session.target`** user unit
  (`BindsTo=graphical-session.target`) — it activates `xdg-desktop-portal` on a
  non-uwsm session. Without it, screen sharing, file pickers, and app/URL handoff
  (e.g. Slack sign-in) silently fail.

## Distro support tiers

| Tier | Distros | Hyprland / Quickshell source |
|------|---------|------------------------------|
| **1 — best** | Arch, Fedora | Arch `extra` + AUR · Fedora COPRs (`solopasha/hyprland`, `errornointernet/quickshell`) |
| **2** | openSUSE Tumbleweed | OBS `X11:Wayland` |
| **3 — advanced** | Debian / Ubuntu | **not packaged** — built from pinned `VERSIONS` tags, *or* run the DE in a **distrobox Arch** container (recommended) |

`packages/<family>.map` translates the canonical names in `common.list`; entries
marked `SKIP` aren’t packaged on that family (handled elsewhere/optional) and
`BUILD` must be compiled from source. "Stable only" is enforced by `VERSIONS` —
nothing tracks `main`/`-git`.

## Repo layout

```
install.sh  uninstall.sh  VERSIONS
lib/      log.sh detect.sh pkg.sh deploy.sh
packages/ common.list  {arch,fedora,debian,suse}.map
phases/   00…90
dotfiles/ hypr/  quickshell/      ← the actual configs, symlinked into ~/.config
systemd/  hyprland-session.target ← the portal-activation fix
templates/hyprland-de.desktop.in  ← rendered into the wayland-sessions dir
```

## Notes for this hardware (Lunar Lake / Arc 140V)

The `xe` kernel driver has a DPMS-resume bug that can strand a black screen, so the
shipped `hypridle.conf` locks but **never powers the panel off**. If the iGPU ever
tears or hangs, log in once with `DE_SOFTWARE_RENDER=1` set (see
`dotfiles/hypr/start-hyprland.sh`).
