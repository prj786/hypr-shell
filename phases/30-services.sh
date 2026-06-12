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

    # ── Wayland session entry — installed to BOTH standard dirs so ReGreet finds
    #    it regardless of its scan paths. ──
    local tmpl="$DOTREPO/templates/hyprland-de.desktop.in"
    local wrap="$HOME/.config/hypr/start-hyprland.sh"
    if [ -r "$tmpl" ]; then
        local d
        for d in /usr/share/wayland-sessions /usr/local/share/wayland-sessions; do
            sudo_run install -d "$d"
            if [ "${DRY_RUN:-0}" = "1" ]; then info "would write $d/hyprland-de.desktop (Exec=$wrap)"
            else sed "s|@EXEC@|$wrap|g" "$tmpl" | sudo_run tee "$d/hyprland-de.desktop" >/dev/null && ok "installed session entry $d/hyprland-de.desktop"; fi
        done
    fi

    # ── greetd + ReGreet (fully Wayland greeter via cage; zero Xorg) ──
    if command -v greetd >/dev/null 2>&1 || pkg_present greetd; then
        sudo_run install -d /etc/greetd
        sudo_run install -m 644 "$DOTREPO/system/greetd/config.toml"  /etc/greetd/config.toml  && ok "installed greetd config"
        # Environment for the greeter (cage), set on greetd.service so cage —
        # which greetd execs as a child — inherits it. Done as a drop-in rather
        # than an `env …` prefix in config.toml's command (greetd word-splits the
        # command and mis-parses such a prefix).
        #   WLR_NO_HARDWARE_CURSORS — fixes the inverted virtio-gpu pointer and
        #     the flaky `xe` cursor plane on Lunar Lake.
        #   WLR_RENDERER_ALLOW_SOFTWARE (VM only) — lets cage fall back to
        #     software GL when the guest's virgl path can't allocate a surface.
        sudo_run install -d /etc/systemd/system/greetd.service.d
        local dropin="[Service]
Environment=WLR_NO_HARDWARE_CURSORS=1"
        [ "${IS_VM:-0}" = "1" ] && dropin="$dropin
Environment=WLR_RENDERER_ALLOW_SOFTWARE=1"
        if [ "${DRY_RUN:-0}" = "1" ]; then info "would write /etc/systemd/system/greetd.service.d/hypr-shell.conf"
        else printf '%s\n' "$dropin" | sudo_run tee /etc/systemd/system/greetd.service.d/hypr-shell.conf >/dev/null \
            && ok "installed greetd.service drop-in (cursor${IS_VM:+ + VM software-render} env)"
            sudo_run systemctl daemon-reload 2>/dev/null || true
        fi
        sudo_run install -m 644 "$DOTREPO/system/greetd/regreet.toml" /etc/greetd/regreet.toml && ok "installed ReGreet config"
        # PAM keyring unlock: login keyring opens with your password at the greeter,
        # so the "login keyring did not get unlocked" prompt never appears.
        if [ -f /usr/lib/security/pam_gnome_keyring.so ] || [ -f /lib/security/pam_gnome_keyring.so ] || pkg_present gnome-keyring; then
            sudo_run install -m 644 "$DOTREPO/system/pam.d/greetd" /etc/pam.d/greetd && ok "installed greetd PAM (gnome-keyring auto-unlock)"
        else
            info "gnome-keyring not present — skipped greetd PAM keyring integration."
        fi
        # Only enable greetd if the greeter binary actually exists. cage's
        # "Failed to spawn client: No such file or directory" means regreet is
        # missing — booting straight into that is a black/looping greeter, so we
        # refuse to enable the service and tell the user how to finish.
        if command -v regreet >/dev/null 2>&1 || pkg_present greetd-regreet; then
            _enable_system greetd.service
            info "greetd is the greeter (cage → ReGreet) and lists 'Hyprland (DE)'. Disable any other display-manager.service first."
        else
            warn "regreet NOT installed (AUR build skipped or failed) — NOT enabling greetd.service to avoid a broken boot."
            warn "Finish with:  $AUR_HELPER -S greetd-regreet  &&  sudo systemctl enable greetd.service"
        fi
    else
        warn "greetd not installed — start the session from a TTY with start-hyprland.sh, or enable a greeter."
    fi

    ok "services done"
}
