#!/usr/bin/env bash
# lib/detect.sh — Arch-only. Confirm we're on Arch (or an Arch derivative),
# then detect chassis (laptop/desktop) and GPU vendor.
# Exports: DISTRO_ID, CHASSIS (laptop|desktop), GPU_VENDOR (intel|amd|nvidia…).

detect_distro() {
    [ -r /etc/os-release ] || die "no /etc/os-release — unsupported system."
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    local like="${ID_LIKE:-}"
    case " $DISTRO_ID $like " in
        *" arch "*) : ;;
        *) case "$DISTRO_ID" in
               arch|artix|manjaro|endeavouros|cachyos|garuda) : ;;
               *) die "this installer is Arch-only (got '$DISTRO_ID'). Pacman + AUR are assumed." ;;
           esac ;;
    esac
    command -v pacman >/dev/null 2>&1 || die "pacman not found — Arch-only installer."
    # Artix is systemd-free; several phases assume systemctl. Warn, don't block.
    command -v systemctl >/dev/null 2>&1 || warn "no systemctl ($DISTRO_ID is likely systemd-free) — service phases will be skipped; enable units with your init manually."
    export DISTRO_ID
}

detect_chassis() {
    CHASSIS=desktop
    local t=""
    command -v hostnamectl >/dev/null 2>&1 && t="$(hostnamectl chassis 2>/dev/null)"
    [ -z "$t" ] && [ -r /sys/class/dmi/id/chassis_type ] && t="$(cat /sys/class/dmi/id/chassis_type)"
    case "$t" in
        laptop|notebook|portable|convertible|8|9|10|14) CHASSIS=laptop ;;
        *) { [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ]; } && CHASSIS=laptop ;;
    esac
    export CHASSIS
}

detect_gpu() {
    GPU_VENDOR=""
    local out=""
    command -v lspci >/dev/null 2>&1 && out="$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display')"
    case "$out" in *[Ii]ntel*) GPU_VENDOR="$GPU_VENDOR intel" ;; esac
    case "$out" in *AMD*|*ATI*|*Radeon*) GPU_VENDOR="$GPU_VENDOR amd" ;; esac
    case "$out" in *NVIDIA*|*nVidia*) GPU_VENDOR="$GPU_VENDOR nvidia" ;; esac
    GPU_VENDOR="$(echo "$GPU_VENDOR" | xargs)"
    [ -z "$GPU_VENDOR" ] && GPU_VENDOR="unknown"
    export GPU_VENDOR
}

detect_all() {
    detect_distro; detect_chassis; detect_gpu
    info "distro:  $DISTRO_ID (Arch family)"
    info "chassis: $CHASSIS"
    info "gpu:     $GPU_VENDOR"
}
