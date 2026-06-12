#!/usr/bin/env bash
# phase 30 — enable services, install the SDDM config + Wayland session entry.

_enable_system() {  # <unit> — enable (+start) if present
    command -v systemctl >/dev/null 2>&1 || return 0
    if systemctl list-unit-files "$1" 2>/dev/null | grep -q "^$1"; then
        sudo_run systemctl enable "$1" && ok "enabled $1" || warn "could not enable $1"
    else
        info "service not present, skipping: $1"
    fi
}

phase_services() {
    step "30 · services + greeter + session entry"
    command -v systemctl >/dev/null 2>&1 || { warn "no systemd — skipping service enablement (enable equivalents in your init)."; return 0; }

    # ── user audio stack (socket-activated) ──
    run systemctl --user enable pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null \
        || info "pipewire user units will come up with the session"

    # ── system services ──
    _enable_system NetworkManager.service
    _enable_system bluetooth.service
    _enable_system power-profiles-daemon.service

    # ── Wayland session entry (system-wide, read by SDDM) ──
    local tmpl="$DOTREPO/templates/hyprland-de.desktop.in"
    local wrap="$HOME/.config/hypr/start-hyprland.sh"
    local dest=/usr/local/share/wayland-sessions/hyprland-de.desktop
    if [ -r "$tmpl" ]; then
        sudo_run install -d /usr/local/share/wayland-sessions
        if [ "${DRY_RUN:-0}" = "1" ]; then info "would write $dest (Exec=$wrap)"
        else sed "s|@EXEC@|$wrap|g" "$tmpl" | sudo_run tee "$dest" >/dev/null && ok "installed session entry $dest"; fi
    fi

    # ── SDDM (Qt greeter, matches the shell) ──
    if command -v sddm >/dev/null 2>&1 || pkg_present sddm; then
        sudo_run install -d /etc/sddm.conf.d
        sudo_run install -m 644 "$DOTREPO/system/sddm.conf.d/10-hyprdots.conf" /etc/sddm.conf.d/10-hyprdots.conf \
            && ok "installed SDDM config"
        _enable_system sddm.service
        info "SDDM is the greeter — it lists 'Hyprland (DE)'. (Disable any other display-manager.service first.)"
    else
        warn "sddm not installed — start the session from a TTY with start-hyprland.sh, or enable a greeter."
    fi

    ok "services done"
}
