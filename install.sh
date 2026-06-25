#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  install.sh — turn a minimal base install into the Hyprland + Quickshell   ║
# ║  macOS-style desktop. Multi-distro (arch / fedora / debian / suse).        ║
# ║                                                                            ║
# ║  Usage:                                                                    ║
# ║    bash install.sh                 full install (prompts before changes)   ║
# ║    bash install.sh --yes           no prompts                              ║
# ║    bash install.sh --dry-run       print every action, change nothing      ║
# ║    bash install.sh --no-packages   skip the package install (config only)  ║
# ║    bash install.sh --check-only    run only the verification checklist     ║
# ║    bash install.sh --gaming        also install the gaming stack           ║
# ║                                                                            ║
# ║  Idempotent: re-running re-links (no-op), skips installed packages, and    ║
# ║  never clobbers an existing config without a timestamped .bak backup.      ║
# ╚══════════════════════════════════════════════════════════════════════════╝
set -u

DOTREPO="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export DOTREPO

# --- flags ---
DRY_RUN=0; ASSUME_YES=0; NO_PACKAGES=0; CHECK_ONLY=0; GAMING=0
for a in "$@"; do
    case "$a" in
        --dry-run)     DRY_RUN=1 ;;
        --yes|-y)      ASSUME_YES=1 ;;
        --no-packages) NO_PACKAGES=1 ;;
        --check-only)  CHECK_ONLY=1 ;;
        --gaming)      GAMING=1 ;;
        -h|--help)     sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown flag: $a (see --help)"; exit 2 ;;
    esac
done
export DRY_RUN ASSUME_YES NO_PACKAGES GAMING

# A fixed per-run timestamp for backups (passed without Date.now-style drift).
RUN_STAMP="$(date -u +%Y%m%d-%H%M%S 2>/dev/null || echo manual)"
export RUN_STAMP

# --- load libraries + phases ---
for f in lib/log.sh lib/detect.sh lib/pkg.sh lib/deploy.sh \
         phases/00-preflight.sh phases/10-repos.sh phases/20-packages.sh \
         phases/30-services.sh phases/35-bootsplash.sh phases/37-microcode.sh \
         phases/40-gpu.sh phases/50-dotfiles.sh \
         phases/60-userconfig.sh phases/90-postcheck.sh; do
    # shellcheck disable=SC1090
    . "$DOTREPO/$f"
done

detect_all

if [ "$CHECK_ONLY" = "1" ]; then
    phase_postcheck
    exit 0
fi

[ "$DRY_RUN" = "1" ] && info "DRY RUN — no changes will be made."

# The gaming stack (Steam, gamescope, gamemode, mangohud + 32-bit libs) is OPT-IN.
# It pulls in [multilib] (phase 10) and the lib32 GPU drivers (phase 40), so the
# choice must be settled BEFORE those phases run. Default: not installed.
if [ "$GAMING" = "1" ]; then
    info "gaming stack: enabled (--gaming) — [multilib] + Steam, gamescope, gamemode, mangohud."
elif [ "$ASSUME_YES" = "1" ] || [ "$DRY_RUN" = "1" ] || [ "$NO_PACKAGES" = "1" ]; then
    info "gaming stack: not selected (opt-in) — pass --gaming for Steam, gamescope, gamemode, mangohud."
elif ask_yes "Install the optional gaming stack? (Steam, gamescope, gamemode, mangohud + 32-bit libs)"; then
    GAMING=1
else
    info "gaming stack: skipped — re-run with --gaming to add it later."
fi

phase_preflight
phase_repos
phase_packages
phase_services
phase_bootsplash
phase_microcode
phase_gpu
phase_dotfiles
phase_userconfig
phase_postcheck

step "done"
cat <<EOF
  Next:
    1. Reboot (or restart your display manager) so the greeter picks up the
       'Hyprland (DE)' session entry.
    2. Pick 'Hyprland (DE)' at login.
    3. First keys:  Super+Return (terminal) · Super+D (apps) · Super+, (Settings)
       Full list in ~/.config/hypr/SHORTCUTS.md
    4. Re-run the checklist any time:  bash install.sh --check-only
  Backups (if any) are at ~/.config/<name>.bak.$RUN_STAMP
EOF
ok "install complete"
