#!/usr/bin/env bash
# phase 90 — verification checklist. Read-only; prints a green/red summary.
# Most session checks only pass once logged into Hyprland; re-run after login:
#   bash install.sh --check-only

# _check "<label>" <cmd...> — green tick on success, red cross on fail
_check() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then printf '  %s✓%s %s\n' "$C_G" "$C_0" "$label"; else printf '  %s✗%s %s\n' "$C_R" "$C_0" "$label"; fi; }
# _note "<label>" — neutral, non-failing line (for things that are expected to be N/A)
_note()  { printf '  %s•%s %s\n' "$C_DIM" "$C_0" "$1"; }
# running under a VM/container? hardware GPU accel is expected to be absent there.
_in_vm() { systemd-detect-virt -q 2>/dev/null; }

phase_postcheck() {
    step "90 · verification"
    echo "  (✗ on session items is expected until you log into the Hyprland session)"

    _check "binaries: Hyprland + qs present"      sh -c 'command -v Hyprland && command -v qs'
    _check "AUR helper present (paru)"            sh -c 'command -v paru'
    _check "multilib repo enabled"                sh -c 'pacman-conf --repo-list | grep -qx multilib'
    _check "greeter: greetd + regreet + cage"     sh -c 'pacman -Qq greetd && pacman -Qq greetd-regreet && pacman -Qq cage'
    _check "greeter: Quickshell config installed"  test -r /etc/xdg/quickshell/hyprshell-greeter/shell.qml
    _check "fully Wayland: no xorg-server"         sh -c '! pacman -Qq xorg-server 2>/dev/null'
    _check "theming: qt6ct (Qt palette) installed" sh -c 'pacman -Qq qt6ct'
    _check "theming: Reversal icons installed"     test -d /usr/share/icons/Reversal-blue-dark
    _check "theming: Mocu cursor installed"        test -d /usr/share/icons/Mocu-White-Right
    _check "session target active"                systemctl --user is-active hyprland-session.target
    _check "portal: xdg-desktop-portal active"    systemctl --user is-active xdg-desktop-portal.service
    _check "portal: hyprland backend active"      systemctl --user is-active xdg-desktop-portal-hyprland.service
    _check "portal: gtk backend active"           systemctl --user is-active xdg-desktop-portal-gtk.service
    _check "audio: a default sink exists"         sh -c 'wpctl status 2>/dev/null | grep -qi sink'
    _check "network: NetworkManager active"       systemctl is-active NetworkManager.service
    # GPU hardware accel is expected to be unavailable in a VM (software rendering),
    # so don't flag it red there — just note it.
    if _in_vm; then
        _note "GPU: hardware accel skipped (VM — software rendering)"
    else
        _check "GPU: VAAPI entrypoint available"      sh -c 'vainfo 2>/dev/null | grep -q VAEntrypoint'
        _check "GPU: a Vulkan device is visible"      sh -c 'vulkaninfo --summary 2>/dev/null | grep -qi deviceName'
    fi
    # grim uses wlr-screencopy, which is unreliable on a VM's software-rendered
    # virtio-gpu (the capture can come back empty). Real check on hardware; in a
    # VM it's a neutral note, not a red ✗ — screenshots work fine on real GPUs.
    if _in_vm; then
        _note "screenshot: grim (screencopy unreliable under VM software rendering)"
    else
        _check "screenshot: grim can capture"         sh -c 'grim - 2>/dev/null | head -c1 | grep -q .'
    fi
    _check "keyring agent running"                pgrep -f gnome-keyring-daemon
    _check "kb layout includes us,ge"             sh -c 'hyprctl getoption input:kb_layout 2>/dev/null | grep -q ge'
    _check "gaming: gamemode + steam installed"   sh -c 'pacman -Qq gamemode && pacman -Qq steam'
    _check "editor: Fresh (fresh) on PATH"        sh -c 'command -v fresh'
    _check "terminal: kitty installed"            sh -c 'command -v kitty'
    _check "dev: node via mise shims"             sh -c 'command -v mise && [ -x "$HOME/.local/share/mise/shims/node" ]'
    _check "dev: TypeScript language server"      sh -c '[ -x "$HOME/.local/share/mise/shims/typescript-language-server" ] || command -v typescript-language-server'

    echo
    info "manual: Firefox → about:support → Compositing = 'WebRender'; play a video and watch \`intel_gpu_top\` Video engine."
    ok "verification done"
}
