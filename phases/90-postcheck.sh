#!/usr/bin/env bash
# phase 90 — verification checklist. Read-only; prints a green/red summary.
# Most checks are meaningful only inside a running Hyprland session; run
#   bash install.sh --check-only
# after logging in for the real picture.

# _check "<label>" <cmd...> — green tick on success, red cross on fail
_check() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then printf '  %s✓%s %s\n' "$C_G" "$C_0" "$label"; else printf '  %s✗%s %s\n' "$C_R" "$C_0" "$label"; fi; }

phase_postcheck() {
    step "90 · verification"
    echo "  (✗ on pre-login items is expected until you log into the Hyprland session)"

    _check "binaries: Hyprland + qs present"      sh -c 'command -v Hyprland && command -v qs'
    _check "session target active"                systemctl --user is-active hyprland-session.target
    _check "portal: xdg-desktop-portal active"    systemctl --user is-active xdg-desktop-portal.service
    _check "portal: hyprland backend active"      systemctl --user is-active xdg-desktop-portal-hyprland.service
    _check "portal: gtk backend active"           systemctl --user is-active xdg-desktop-portal-gtk.service
    _check "audio: a default sink exists"         sh -c 'wpctl status 2>/dev/null | grep -qi sink'
    _check "network: NetworkManager active"       systemctl is-active NetworkManager.service
    _check "GPU: VAAPI entrypoint available"      sh -c 'vainfo 2>/dev/null | grep -q VAEntrypoint'
    _check "screenshot: grim can capture"         sh -c 'grim - 2>/dev/null | head -c1 | grep -q .'
    _check "keyring agent running"                pgrep -f gnome-keyring-daemon
    _check "kb layout includes us,ge"             sh -c 'hyprctl getoption input:kb_layout 2>/dev/null | grep -q ge'

    echo
    info "manual: open Firefox → about:support → Compositing should read 'WebRender'; play a video and watch \`intel_gpu_top\` Video engine."
    ok "verification done"
}
