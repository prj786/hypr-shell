#!/usr/bin/env bash
# phase 30 — enable services + install the Wayland session entry + display mgr.

_enable_system() {  # <unit> — enable+start if the unit exists
    if systemctl list-unit-files "$1" >/dev/null 2>&1 && \
       systemctl list-unit-files "$1" 2>/dev/null | grep -q "$1"; then
        sudo_run systemctl enable --now "$1" && ok "enabled $1" || warn "could not enable $1"
    else
        info "service not present, skipping: $1"
    fi
}

phase_services() {
    step "30 · services + session entry"

    # ── user audio stack (socket-activated; enable is harmless if already on) ──
    run systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null \
        || info "pipewire user units will come up with the session"

    # ── system services ──
    _enable_system NetworkManager.service
    _enable_system bluetooth.service
    _enable_system power-profiles-daemon.service

    # ── Wayland session entry (system-wide, for the greeter) ──
    local tmpl="$DOTREPO/templates/hyprland-de.desktop.in"
    local wrap="$HOME/.config/hypr/start-hyprland.sh"
    local dest=/usr/local/share/wayland-sessions/hyprland-de.desktop
    if [ -r "$tmpl" ]; then
        local rendered; rendered="$(sed "s|@EXEC@|$wrap|g" "$tmpl")"
        sudo_run install -d /usr/local/share/wayland-sessions
        if [ "${DRY_RUN:-0}" = "1" ]; then
            info "would write $dest (Exec=$wrap)"
        else
            printf '%s\n' "$rendered" | sudo_run tee "$dest" >/dev/null && ok "installed session entry $dest"
        fi
    fi

    # ── display manager: prefer greetd, fall back to SDDM, else leave it ──
    if command -v greetd >/dev/null 2>&1; then
        _enable_system greetd.service
        info "greetd enabled — configure /etc/greetd/config.toml to launch start-hyprland.sh (regreet recommended)."
    elif command -v sddm >/dev/null 2>&1; then
        _enable_system sddm.service
    else
        warn "no display manager found (greetd/sddm). You can start the session with start-hyprland.sh from a TTY."
    fi

    ok "services done"
}
