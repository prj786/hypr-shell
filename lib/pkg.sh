#!/usr/bin/env bash
# lib/pkg.sh — Arch package handling: official repos via pacman, AUR via the
# helper bootstrapped in phase 10 (paru). No name mapping needed — the lists
# carry real Arch package names.

# read_list <file> — echo package names (strip # comments, inline comments, blanks)
read_list() { awk '{sub(/#.*/,"")} NF {print $1}' "$DOTREPO/packages/$1"; }

# install_official <pkg...> — pacman, idempotent (--needed skips installed).
install_official() {
    [ "$#" -gt 0 ] || return 0
    sudo_run pacman -S --needed --noconfirm "$@"
}

# install_aur <pkg...> — via $AUR_HELPER (set in phase 10). Runs as the normal
# user (makepkg refuses root); the helper escalates only for the final install.
install_aur() {
    [ "$#" -gt 0 ] || return 0
    [ -n "${AUR_HELPER:-}" ] || { warn "no AUR helper — skipping AUR packages: $*"; return 0; }
    run "$AUR_HELPER" -S --needed --noconfirm "$@"
}

# pkg_present <pkg> — installed? (official or AUR, pacman tracks both)
pkg_present() { pacman -Qq "$1" >/dev/null 2>&1; }

# multilib_enabled — is the [multilib] repo active in pacman.conf?
multilib_enabled() { pacman-conf --repo-list 2>/dev/null | grep -qx multilib; }
