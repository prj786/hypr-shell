#!/usr/bin/env bash
# phase 10 — enable the extra repos each family needs for Hyprland/Quickshell.

# bootstrap an AUR helper on Arch (paru) if none present
_bootstrap_aur() {
    command -v paru >/dev/null 2>&1 && { ok "AUR helper present (paru)"; return; }
    command -v yay  >/dev/null 2>&1 && { ok "AUR helper present (yay)";  return; }
    info "bootstrapping paru (AUR helper)…"
    sudo_run pacman -S --needed --noconfirm base-devel git
    if [ "${DRY_RUN:-0}" = "1" ]; then info "would clone+makepkg paru-bin"; return; fi
    local t; t="$(mktemp -d)"
    git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$t" \
        && ( cd "$t" && makepkg -si --noconfirm ) \
        && ok "paru installed" || warn "paru bootstrap failed — install an AUR helper manually."
    rm -rf "$t"
}

phase_repos() {
    step "10 · repositories"
    case "$FAMILY" in
        arch)
            _bootstrap_aur
            # route the package install through the AUR helper so AUR names resolve
            AUR_HELPER="$(command -v paru || command -v yay || true)"
            export AUR_HELPER ;;
        fedora)
            sudo_run dnf install -y dnf5-plugins 2>/dev/null \
                || sudo_run dnf install -y dnf-plugins-core
            # ashbuk/Hyprland-Fedora ships Hyprland 0.55+ (Lua-capable). Do NOT use
            # solopasha/hyprland — it lagged at 0.51 (pre-Lua) and breaks hyprland.lua.
            sudo_run dnf -y copr enable ashbuk/Hyprland-Fedora || warn "copr ashbuk/Hyprland-Fedora failed"
            # Quickshell is in Fedora's official repos — no COPR needed.
            # RPM Fusion (steam, gpu-screen-recorder)
            local rel; rel="$(rpm -E %fedora 2>/dev/null || echo 41)"
            sudo_run dnf install -y \
                "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${rel}.noarch.rpm" \
                "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${rel}.noarch.rpm" \
                2>/dev/null || info "RPM Fusion already enabled or unavailable (steam may be skipped)" ;;
        suse)
            sudo_run zypper --non-interactive addrepo --refresh \
                'https://download.opensuse.org/repositories/X11:/Wayland/openSUSE_Tumbleweed/X11:Wayland.repo' \
                2>/dev/null || info "OBS X11:Wayland repo already present"
            sudo_run zypper --non-interactive --gpg-auto-import-keys refresh ;;
        debian)
            warn "TIER 3: no Hyprland/Quickshell packages. Phase 20 will mark them BUILD."
            sudo_run apt-get update ;;
    esac
    ok "repositories ready"
}
