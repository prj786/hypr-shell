#!/usr/bin/env bash
# phase 10 — enable [multilib] (for 32-bit gaming libs + Steam) and bootstrap an
# AUR helper. Both are idempotent.

_enable_multilib() {
    if multilib_enabled; then ok "[multilib] already enabled"; return; fi
    info "enabling [multilib] in /etc/pacman.conf (needed for steam + lib32-*)"
    if [ "${DRY_RUN:-0}" = "1" ]; then info "would uncomment the [multilib] block in /etc/pacman.conf"; return; fi
    # uncomment the standard two-line [multilib] block
    sudo_run sed -i '/^#\[multilib\]/{N;s/^#\[multilib\]\n#Include = \(.*\)/[multilib]\nInclude = \1/}' /etc/pacman.conf
    if multilib_enabled; then ok "[multilib] enabled"; else
        warn "could not auto-enable [multilib] — uncomment the [multilib] block in /etc/pacman.conf by hand, then re-run."
    fi
    sudo_run pacman -Sy
}

_bootstrap_aur() {
    if command -v paru >/dev/null 2>&1; then AUR_HELPER=paru; export AUR_HELPER; ok "AUR helper present (paru)"; return; fi
    if command -v yay  >/dev/null 2>&1; then AUR_HELPER=yay;  export AUR_HELPER; ok "AUR helper present (yay)";  return; fi
    info "bootstrapping paru (AUR helper)…"
    install_official base-devel git
    if [ "${DRY_RUN:-0}" = "1" ]; then info "would clone + makepkg paru-bin"; AUR_HELPER=paru; export AUR_HELPER; return; fi
    if [ "$(id -u)" = "0" ]; then
        warn "running as root — makepkg refuses root, so paru can't be bootstrapped here. Install an AUR helper as your normal user, then re-run."
        return
    fi
    local t; t="$(mktemp -d)"
    if git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$t" \
       && ( cd "$t" && makepkg -si --noconfirm ); then
        AUR_HELPER=paru; export AUR_HELPER; ok "paru installed"
    else
        warn "paru bootstrap failed — AUR packages (aur.list) will be skipped. Install a helper manually."
    fi
    rm -rf "$t"
}

phase_repos() {
    step "10 · repositories"
    _enable_multilib
    _bootstrap_aur
    ok "repositories ready"
}
