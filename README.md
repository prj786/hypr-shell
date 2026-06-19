<p align="center">
  <img src="system/branding/hypr-shell-logo.png" width="240" alt="hypr-shell logo — a line-art scallop shell in a ring above the hypr-shell wordmark">
</p>

# hypr-shell — a macOS-style Hyprland + Quickshell desktop (Arch)

An opinionated, installable desktop environment for **Arch Linux**: **Hyprland**
(Wayland compositor, Lua-configured) + **Quickshell** (QML shell — bar, dock,
launcher, notifications, control center, settings app, lock, OSD, clipboard, an
app installer, a RunCat, and a "Welcome `<user>`" session splash). A Plymouth boot
splash hides the kernel/systemd text before the greeter. One script turns a
minimal Arch install into the full DE.

> **Arch only.** Package install assumes `pacman` + the **AUR**. Arch derivatives
> (EndeavourOS, CachyOS, Garuda, Manjaro) should work. Artix (systemd-free) is
> detected but the service-enable phases are skipped — wire the equivalents into
> your init manually.

## Status

**Alpha — `0.1.0-alpha`.** Usable and daily-drivable, but expect rough edges and
breaking changes between versions. Tested on a minimal Arch install in a QEMU/KVM
VM. Feedback and issues welcome.

Versioning is **semver** (`MAJOR.MINOR.PATCH`) with an `-alpha`/`-beta` pre-release
suffix until the first stable cut. The canonical version lives in the repo-root
**`VERSION`** file; the shell mirrors it in `dotfiles/quickshell/Globals.qml`
(`Globals.version`, shown in the Settings sidebar). Releases are git tags
(`vX.Y.Z`). Bump both on release.

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
| 35 bootsplash | **Plymouth** boot splash (Arch logo + spinner): installs the theme, adds the `plymouth` initramfs hook, and adds `quiet splash …` to the kernel cmdline (systemd-boot/GRUB, auto-detected + backed up) so the boot `[OK]` text is hidden |
| 40 gpu | per-vendor Vulkan + VAAPI drivers (Intel `xe` DPMS guard, NVIDIA suspend fix, AMD) |
| 50 dotfiles | symlinks `~/.config/{hypr,quickshell,fresh,kitty,tmux,mise}` (backing up any existing), installs the session target |
| 60 userconfig | default apps (**Fresh** as editor), `EDITOR=fresh`, **mise** Node toolchain (`mise install`), zram (laptops) |
| 90 postcheck | green/red verification checklist |

Everything routes through one `run()`/`sudo_run()` choke point, so `--dry-run` is
genuinely safe and the whole thing is re-runnable.

## Packages

- **`packages/common.list`** — official-repo packages (real Arch names), installed
  with `pacman -S --needed`. Grouped: core session, greeter, audio, network,
  bluetooth, power, terminals, **GTK utility apps** (Nemo, Engrampa, imv, Zathura,
  mpv), browser, utilities, theming + fonts, dev tooling, gaming (multilib),
  tuning, build deps.
- **`packages/aur.list`** — AUR packages (built via paru): just `gpu-screen-recorder`.
  Kept deliberately short. Theme/icon/cursor/accent are owned by the Quickshell
  Settings app (no `nwg-look` or other theme-settings GUI).
- **GPU/Vulkan drivers** are *not* in the lists — phase 40 installs the right set
  for the detected vendor (intel / amd / nvidia).

### Why traditional GTK apps (not Qt/KDE, not libadwaita)

The shipped first-party apps are **traditional GTK**: **Nemo** (file manager),
**Engrampa** (archives), **imv** (images), **Zathura** (PDF/docs), **mpv** (video).
These use a normal menubar/toolbar + server-side decorations, so under Hyprland —
which draws **no titlebar**, just the accent border — they come up clean, the
macOS-borderless look. The "GTK forces an unhideable headerbar" rule only applies
to **GNOME/libadwaita** apps (Nautilus, GNOME Calendar, Evince); ordinary GTK apps
don't, which is why we can have the no-titlebar aesthetic *and* GTK.

Going all-GTK also fixes default-app management: **one `~/.config/mimeapps.list`**
is the single source of truth, read natively by **GIO** — so "Open With" always
sees your installed apps, with no KDE `ksycoca` cache to rebuild (the old Dolphin
"offers to find it in Discover" problem is gone). Manage it from **Settings →
Default Apps**. Right-click **Compress… / Extract Here** in Nemo are shipped as
`system/nemo-actions/*.nemo_action` (calling engrampa).

**Appearance** (light/dark + accent) is applied by
`dotfiles/quickshell/scripts/colorscheme.sh` and toggled live in **Settings →
Theme → App appearance** (defaults to dark):

- **GTK** (primary) — gsettings + `gtk-3.0/4.0/settings.ini` (adw-gtk3[-dark]);
  accent changes recolour GTK apps live.
- **Qt** — `qt6ct`/`qt5ct` write a dark **Fusion** palette
  (`QT_QPA_PLATFORMTHEME=qt6ct`) so any *stray* Qt app you install — and the
  Quickshell shell's own Qt dialogs — stay dark instead of blinding white. No
  `plasma-integration`/KDE platform theme: we ship no KDE apps. A `kdeglobals`
  fallback is still written so a KDE app added later is dark too.
- **Icons** — **Reversal**, auto-matched to the accent by hue (`Reversal-<colour>[-dark]`).
- **Cursor** — **Mocu** (`mocu-xcursor`), forced via `XCURSOR_THEME`,
  `~/.icons/default`, GTK, gsettings and qt6ct so it never flips between toolkits.

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
install.sh  uninstall.sh  VERSION (project semver)  VERSIONS (min tool versions)
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

## Known limitations (alpha)

Set expectations before you daily-drive it:

- **The screen never powers off on idle** (only locks) — a deliberate workaround
  for the Lunar Lake `xe` DPMS-resume bug above. On a laptop that means a lit,
  locked panel while idle. Re-add a `dpms off` listener in `hypridle.conf` on
  hardware without the bug.
- **Idle behaviour, laptop on battery:** locks at 5 min, **suspends at 15 min**
  (only on battery — never on a desktop or while plugged in). Delete the second
  listener in `hypridle.conf` to disable.
- **Low battery is handled automatically:** a warning at 20% and 10%, and a
  **suspend at 5%** to protect unsaved work. Don't expect a second prompt — it
  acts to avoid a hard power-off.
- **The shell auto-respawns.** Quickshell runs as a `Restart=on-failure` systemd
  user service (`hypr-shell.service`), so a crash brings the bar/dock/lock back
  on its own. The lock uses the Wayland session-lock protocol, so the outputs
  stay locked even if the shell dies while locked.
- **The session lock is a new Quickshell component**, not battle-tested hyprlock.
  It works, but it's the youngest security-relevant piece — report anything off.
- **Multi-monitor hotplug is lightly tested.** Initial layouts and the
  Settings → Displays pane work; plug/unplug reflow needs more mileage.
- **No input method (IME) yet** — CJK / complex-script input isn't wired.
- Tested on a minimal Arch install in a QEMU/KVM VM; real-hardware coverage is
  still thin. Issues and PRs welcome.

## Credits

Designed and built by **scubba**, pair-programmed with **[Claude Code](https://claude.com/claude-code)** (Anthropic's Claude) — which scaffolded the installer, the Quickshell components, and this documentation.

Built on the work of the [Hyprland](https://hypr.land) and [Quickshell](https://quickshell.org) projects.

## License

**GPL-2.0-only** — see [LICENSE](LICENSE). Like the Linux kernel: use it, study it,
share it, and build on it freely; but if you distribute a modified version, your
changes must ship under the same terms (copyleft). Improvements are welcome
upstream via pull request.
