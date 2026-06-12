# hyprdots — a macOS-style Hyprland + Quickshell desktop (Arch)

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
git clone <this-repo> ~/hyprdots && cd ~/hyprdots
bash install.sh              # prompts before each change
# or:
bash install.sh --dry-run    # show everything it would do, change nothing
bash install.sh --yes        # unattended
bash install.sh --check-only # just run the verification checklist
```

Run it as your **normal user** (not root) — the AUR helper and `makepkg` refuse
root, and the script uses `sudo` only where it must. Then reboot, pick
**“Hyprland (DE)”** at the SDDM login screen, and log in. `Super+,` opens
Settings; full keymap in `dotfiles/hypr/SHORTCUTS.md`.

## What it does (phases)

| Phase | Does |
|------|------|
| 00 preflight | tool/network/disk checks; announces the backup policy |
| 10 repos | enables **[multilib]** (Steam + 32-bit libs); bootstraps **paru** |
| 20 packages | installs `packages/common.list` (pacman) + `packages/aur.list` (AUR) |
| 30 services | pipewire/NM/bluetooth/ppd; installs **SDDM** config + the Wayland session entry |
| 40 gpu | per-vendor Vulkan + VAAPI drivers (Intel `xe` DPMS guard, NVIDIA suspend fix, AMD) |
| 50 dotfiles | symlinks `~/.config/{hypr,quickshell}` (backing up any existing), installs the session target |
| 60 userconfig | default apps, `EDITOR=nvim`, zram (laptops) |
| 90 postcheck | green/red verification checklist |

Everything routes through one `run()`/`sudo_run()` choke point, so `--dry-run` is
genuinely safe and the whole thing is re-runnable.

## Packages

- **`packages/common.list`** — official-repo packages (real Arch names), installed
  with `pacman -S --needed`. Grouped: core session, greeter, audio, network,
  bluetooth, power, terminals, file manager, browser/editors, utilities, theming +
  fonts, dev tooling, gaming (multilib), tuning, build deps.
- **`packages/aur.list`** — AUR packages (built via paru): cursor theme, `nwg-look`,
  `gpu-screen-recorder`. Kept deliberately short.
- **GPU/Vulkan drivers** are *not* in the lists — phase 40 installs the right set
  for the detected vendor (intel / amd / nvidia).

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
system/   sddm.conf.d/            ← installed to /etc by phase 30
templates/hyprland-de.desktop.in  ← rendered into the wayland-sessions dir
```

## Notes for this hardware (Lunar Lake / Arc 140V)

The `xe` kernel driver has a DPMS-resume bug that can strand a black screen, so the
shipped `hypridle.conf` locks but **never powers the panel off**. If the iGPU ever
tears or hangs, log in once with `DE_SOFTWARE_RENDER=1` set (see
`dotfiles/hypr/start-hyprland.sh`).
