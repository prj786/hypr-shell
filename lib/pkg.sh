#!/usr/bin/env bash
# lib/pkg.sh — Arch package handling: official repos via pacman, AUR via the
# helper bootstrapped in phase 10 (paru). No name mapping needed — the lists
# carry real Arch package names.

# read_list <file> — echo package names (strip # comments, inline comments, blanks)
read_list() { awk '{sub(/#.*/,"")} NF {print $1}' "$DOTREPO/packages/$1"; }

# install_official <pkg...> — pacman, idempotent (--needed skips installed).
# RESILIENT: pacman is all-or-nothing, so a single unknown/unavailable name
# (typo, AUR-only package, or a multilib/lib32 target when [multilib] is off)
# aborts the WHOLE batch and installs nothing — which once silently wiped out
# hyprland/quickshell/greetd. So: try the batch (fast path, correct dep order);
# if it fails, retry package-by-package so one missing package can't block the
# rest. Missing ones are warned and skipped — never fatal. Always returns 0.
install_official() {
    [ "$#" -gt 0 ] || return 0
    if sudo_run pacman -S --needed --noconfirm "$@"; then return 0; fi
    warn "official batch hit an error — retrying one-by-one so a missing package can't block the rest"
    local p; local -a missed=()
    for p in "$@"; do
        sudo_run pacman -S --needed --noconfirm -- "$p" || missed+=("$p")
    done
    [ "${#missed[@]}" -gt 0 ] && warn "skipped (not in repos / unavailable): ${missed[*]}"
    return 0
}

# install_aur <pkg...> — via $AUR_HELPER (set in phase 10). Runs as the normal
# user (makepkg refuses root); the helper escalates only for the final install.
# Same resilience as install_official: one failed build can't sink the batch.
install_aur() {
    [ "$#" -gt 0 ] || return 0
    [ -n "${AUR_HELPER:-}" ] || { warn "no AUR helper — skipping AUR packages: $*"; return 0; }
    if run "$AUR_HELPER" -S --needed --noconfirm "$@"; then return 0; fi
    warn "AUR batch hit an error — retrying one-by-one so a failed build can't block the rest"
    local p; local -a missed=()
    for p in "$@"; do
        run "$AUR_HELPER" -S --needed --noconfirm -- "$p" || missed+=("$p")
    done
    [ "${#missed[@]}" -gt 0 ] && warn "skipped (build/install failed): ${missed[*]}"
    return 0
}

# pkg_present <pkg> — installed? (official or AUR, pacman tracks both)
pkg_present() { pacman -Qq "$1" >/dev/null 2>&1; }

# multilib_enabled — is the [multilib] repo active in pacman.conf?
multilib_enabled() { pacman-conf --repo-list 2>/dev/null | grep -qx multilib; }
