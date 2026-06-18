#!/usr/bin/env bash
# phase 20 — install the official-repo set (pacman), the AUR set (helper), then
# the two upstream themes that aren't reliably packaged (built from source,
# system-wide, so the accent icons + cursor always land — no silent AUR skips).

# Reversal icon theme (all accent variants) + Mocu cursor → /usr/share/icons.
# System-wide so every user AND the greeter see them. Loud on failure; idempotent.
_install_themes() {
    command -v git >/dev/null 2>&1 || { warn "git missing — cannot install icon/cursor themes"; return 0; }
    local d

    # ── Reversal icon theme: sudo ./install.sh -d /usr/share/icons -t all ──
    if [ -d /usr/share/icons/Reversal-blue-dark ]; then
        ok "Reversal icon theme already installed"
    else
        info "installing Reversal icon theme (all accent variants → /usr/share/icons)…"
        d="$(mktemp -d)"
        if git clone --depth 1 https://github.com/yeyushengfan258/Reversal-icon-theme.git "$d/rev"; then
            ( cd "$d/rev" && sudo_run bash ./install.sh -d /usr/share/icons -t all ) \
                && ok "Reversal icon theme installed" \
                || warn "Reversal install.sh FAILED — icons will fall back to Papirus."
        else
            warn "Reversal clone failed (network?) — icons will fall back to Papirus."
        fi
        rm -rf "$d"
    fi

    # ── Mocu cursor: build (rsvg-convert/xcursorgen/xmlstarlet) then copy dist/* ──
    if [ -d /usr/share/icons/Mocu-White-Right ]; then
        ok "Mocu cursor already installed"
    else
        info "building Mocu cursor (→ /usr/share/icons)…"
        d="$(mktemp -d)"
        if git clone --depth 1 https://github.com/sevmeyer/mocu-xcursor.git "$d/mocu"; then
            if ( cd "$d/mocu" && bash ./make.sh ); then
                sudo_run cp -r "$d/mocu/dist/." /usr/share/icons/ \
                    && ok "Mocu cursor installed" \
                    || warn "Mocu copy FAILED — cursor falls back to default."
            else
                warn "Mocu make.sh FAILED (need librsvg/xorg-xcursorgen/xmlstarlet) — cursor falls back."
            fi
        else
            warn "Mocu clone failed (network?) — cursor falls back to default."
        fi
        rm -rf "$d"
    fi
}

phase_packages() {
    step "20 · packages"
    [ "${NO_PACKAGES:-0}" = "1" ] && { info "--no-packages: skipping install"; return 0; }

    local off aur
    mapfile -t off < <(read_list common.list)
    mapfile -t aur < <(read_list aur.list)

    info "${#off[@]} official packages + ${#aur[@]} AUR packages + 2 source themes (Reversal, Mocu)"
    if [ "${DRY_RUN:-0}" = "1" ]; then
        printf '%s   pacman:%s %s\n' "$C_DIM" "$C_0" "${off[*]}"
        printf '%s   aur:%s    %s\n' "$C_DIM" "$C_0" "${aur[*]}"
        printf '%s   source:%s Reversal-icon-theme (all variants), mocu-xcursor → /usr/share/icons\n' "$C_DIM" "$C_0"
        return 0
    fi

    # Known provider conflict: pipewire-jack and jack2 both provide `jack` and
    # can't coexist. We ship the PipeWire stack, so PipeWire owns JACK. If the
    # standalone jack2 is installed it dead-ends the non-interactive install on
    # the "Remove jack2? [y/N]" prompt (--noconfirm answers N → whole batch
    # fails). Force-remove jack2 (keeping its dependents — `jack` is immediately
    # re-satisfied by pipewire-jack in the batch below).
    if pkg_present jack2; then
        info "removing jack2 (conflicts with pipewire-jack; PipeWire provides JACK)"
        sudo_run pacman -Rdd --noconfirm jack2 || warn "could not remove jack2 — pipewire-jack may be skipped"
    fi

    ask_yes "Install ${#off[@]} official packages now?" && install_official "${off[@]}" || warn "skipped official packages"
    if [ "${#aur[@]}" -gt 0 ]; then
        ask_yes "Build & install ${#aur[@]} AUR packages now? (compiles from source)" \
            && install_aur "${aur[@]}" || warn "skipped AUR packages"
    fi
    _install_themes
    ok "package phase done"
}
