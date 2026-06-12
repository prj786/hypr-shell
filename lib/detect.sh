#!/usr/bin/env bash
# lib/detect.sh — figure out distro family, chassis (laptop/desktop), GPU vendor.
# Exports: DISTRO_ID, FAMILY (arch|fedora|debian|suse), CHASSIS (laptop|desktop),
#          GPU_VENDOR (intel|amd|nvidia, space-separated if multiple).

detect_distro() {
    [ -r /etc/os-release ] || die "no /etc/os-release — unsupported system."
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    local like="${ID_LIKE:-}"
    case " $DISTRO_ID $like " in
        *" arch "*|*manjaro*|*endeavouros*) FAMILY=arch ;;
        *" fedora "*|*rhel*|*centos*)       FAMILY=fedora ;;
        *" debian "*|*ubuntu*)              FAMILY=debian ;;
        *" suse "*|*opensuse*|*sles*)       FAMILY=suse ;;
        *)
            case "$DISTRO_ID" in
                arch|manjaro|endeavouros) FAMILY=arch ;;
                fedora)                   FAMILY=fedora ;;
                debian|ubuntu|pop|mint)   FAMILY=debian ;;
                opensuse*|sles)           FAMILY=suse ;;
                *) die "unrecognized distro '$DISTRO_ID' (ID_LIKE='$like'). Supported families: arch, fedora, debian, suse." ;;
            esac ;;
    esac
    export DISTRO_ID FAMILY
}

detect_chassis() {
    CHASSIS=desktop
    local t=""
    if command -v hostnamectl >/dev/null 2>&1; then
        t="$(hostnamectl chassis 2>/dev/null)"
    fi
    [ -z "$t" ] && [ -r /sys/class/dmi/id/chassis_type ] && t="$(cat /sys/class/dmi/id/chassis_type)"
    case "$t" in
        laptop|notebook|portable|convertible|8|9|10|14) CHASSIS=laptop ;;
        *) [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ] && CHASSIS=laptop ;;
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
    GPU_VENDOR="$(echo "$GPU_VENDOR" | xargs)"   # trim
    [ -z "$GPU_VENDOR" ] && GPU_VENDOR="unknown"
    export GPU_VENDOR
}

detect_all() {
    detect_distro; detect_chassis; detect_gpu
    info "distro:  $DISTRO_ID  (family: $FAMILY)"
    info "chassis: $CHASSIS"
    info "gpu:     $GPU_VENDOR"
    [ "$FAMILY" = "debian" ] && warn "Debian/Ubuntu is TIER 3: Hyprland & Quickshell are not packaged; this installer will flag what must be built from source. See README."
}
