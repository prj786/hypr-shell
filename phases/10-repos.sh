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

_sync_system() {
    # Full upgrade BEFORE building/installing anything. A fresh archinstall box
    # carries an older pacman/libalpm than the live repos; installing prebuilt
    # AUR helpers (paru-bin links libalpm.so.N) or new packages onto it triggers
    # "libalpm.so.NN: cannot open shared object file" and other partial-upgrade
    # breakage. -Syu brings the whole system to a consistent state first.
    if [ "${DRY_RUN:-0}" = "1" ]; then info "would run pacman -Syu (full system upgrade)"; return; fi
    info "full system upgrade (pacman -Syu) — avoids partial-upgrade / soname mismatches"
    sudo_run pacman -Syu --noconfirm || warn "pacman -Syu reported errors — review before continuing."
}

# Does a helper actually RUN? A stale prebuilt paru-bin can be installed but
# broken ("libalpm.so.NN: cannot open shared object file" after a soname bump),
# so test execution — not just `command -v`.
_helper_works() { command -v "$1" >/dev/null 2>&1 && "$1" --version >/dev/null 2>&1; }

_bootstrap_aur() {
    if _helper_works paru; then AUR_HELPER=paru; export AUR_HELPER; ok "AUR helper present (paru)"; return; fi
    if _helper_works yay;  then AUR_HELPER=yay;  export AUR_HELPER; ok "AUR helper present (yay)";  return; fi

    info "bootstrapping paru (AUR helper, built from source)…"
    install_official base-devel git rust
    if [ "${DRY_RUN:-0}" = "1" ]; then info "would (remove broken paru-bin then) build paru from source"; AUR_HELPER=paru; export AUR_HELPER; return; fi
    if [ "$(id -u)" = "0" ]; then
        warn "running as root — makepkg refuses root. Build paru as your normal user, then re-run."
        return
    fi
    # A broken prebuilt paru-bin blocks both running AND installing source paru
    # (file conflict on /usr/bin/paru) — remove it so we can rebuild.
    if command -v paru >/dev/null 2>&1 && ! _helper_works paru; then
        warn "existing paru is broken (shared-library mismatch) — removing it to rebuild from source."
        pkg_present paru-bin && sudo_run pacman -Rdd --noconfirm paru-bin
        pkg_present paru     && sudo_run pacman -Rdd --noconfirm paru
    fi
    # Build `paru` (source) — it links the CURRENTLY-installed libalpm, so it
    # survives the soname bumps that break the prebuilt paru-bin package.
    local t; t="$(mktemp -d)"
    if git clone --depth 1 https://aur.archlinux.org/paru.git "$t" \
       && ( cd "$t" && makepkg -si --noconfirm ); then
        if _helper_works paru; then AUR_HELPER=paru; export AUR_HELPER; ok "paru installed (built from source)"
        else warn "paru built but still not runnable — AUR packages will be skipped."; fi
    else
        warn "paru bootstrap failed — AUR extras (gpu-screen-recorder) skipped. Non-critical: themes install from source regardless."
    fi
    rm -rf "$t"
}

phase_repos() {
    step "10 · repositories"
    _enable_multilib
    _sync_system
    _bootstrap_aur
    ok "repositories ready"
}
