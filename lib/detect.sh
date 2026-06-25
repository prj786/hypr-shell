#!/usr/bin/env bash
# lib/detect.sh — Arch-only. Confirm we're on Arch (or an Arch derivative),
# then detect chassis (laptop/desktop), GPU vendor and CPU vendor.
# Exports: DISTRO_ID, CHASSIS (laptop|desktop), GPU_VENDOR (intel|amd|nvidia…),
#          CPU_VENDOR (intel|amd|unknown — picks intel-ucode/amd-ucode in phase 37).

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
    IS_VM=0
    # Virtual machine? A virtio/QEMU/VMware vGPU has no vendor ICD — it must use
    # plain mesa (the host does the real GL via virgl). Detect this first so we
    # never try to install nvidia/intel/amd drivers for a paravirtual GPU.
    if command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt -q 2>/dev/null; then
        IS_VM=1
    fi
    # Primary: scan sysfs — works with ZERO extra packages. detect runs at startup,
    # BEFORE the package phase, so lspci (pciutils) may not be installed yet; relying
    # on it alone silently yields GPU_VENDOR=unknown → no vendor drivers → software
    # rendering. PCI class 0x03xxxx = display controller; the vendor id says who made it.
    local d vnd cls
    for d in /sys/bus/pci/devices/*/; do
        [ -r "$d/class" ] && [ -r "$d/vendor" ] || continue
        cls="$(cat "$d/class" 2>/dev/null)"
        case "$cls" in 0x03*) ;; *) continue ;; esac
        vnd="$(cat "$d/vendor" 2>/dev/null)"
        case "$vnd" in
            0x8086) case " $GPU_VENDOR " in *" intel "*) ;; *) GPU_VENDOR="$GPU_VENDOR intel" ;; esac ;;
            0x1002) case " $GPU_VENDOR " in *" amd "*) ;;   *) GPU_VENDOR="$GPU_VENDOR amd" ;; esac ;;
            0x10de) case " $GPU_VENDOR " in *" nvidia "*) ;; *) GPU_VENDOR="$GPU_VENDOR nvidia" ;; esac ;;
        esac
    done

    # Secondary/confirmatory: lspci if present — also names paravirtual vGPUs so we
    # force the mesa-only path in a VM. Deduped against the sysfs scan above.
    local out=""
    command -v lspci >/dev/null 2>&1 && out="$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display')"
    case "$out" in *Virtio*|*"Red Hat"*|*QXL*|*VMware*|*"Cirrus"*|*"Bochs"*) IS_VM=1 ;; esac
    case "$out" in *[Ii]ntel*)            case " $GPU_VENDOR " in *" intel "*) ;;  *) GPU_VENDOR="$GPU_VENDOR intel" ;; esac ;; esac
    case "$out" in *AMD*|*ATI*|*Radeon*)  case " $GPU_VENDOR " in *" amd "*) ;;    *) GPU_VENDOR="$GPU_VENDOR amd" ;; esac ;; esac
    case "$out" in *NVIDIA*|*nVidia*)     case " $GPU_VENDOR " in *" nvidia "*) ;; *) GPU_VENDOR="$GPU_VENDOR nvidia" ;; esac ;; esac
    GPU_VENDOR="$(echo "$GPU_VENDOR" | xargs)"
    # In a VM, the only correct GPU stack is mesa — force vendor to "virtual" so
    # phase 40 installs nothing vendor-specific (passing through a host Intel iGPU
    # via virgl must NOT pull intel-vulkan into the guest).
    [ "$IS_VM" = "1" ] && GPU_VENDOR="virtual"
    [ -z "$GPU_VENDOR" ] && GPU_VENDOR="unknown"
    export GPU_VENDOR IS_VM
}

detect_cpu() {
    # CPU vendor → which microcode package phase 37 installs (intel-ucode vs
    # amd-ucode). `vendor_id` in /proc/cpuinfo is the canonical signal
    # (GenuineIntel / AuthenticAMD); fall back to lscpu if it's ever absent.
    CPU_VENDOR=unknown
    local v=""
    [ -r /proc/cpuinfo ] && v="$(awk -F': ' '/^vendor_id/{print $2; exit}' /proc/cpuinfo)"
    case "$v" in
        GenuineIntel) CPU_VENDOR=intel ;;
        AuthenticAMD) CPU_VENDOR=amd ;;
        *) if command -v lscpu >/dev/null 2>&1; then
               case "$(lscpu 2>/dev/null)" in
                   *GenuineIntel*|*Intel*) CPU_VENDOR=intel ;;
                   *AuthenticAMD*|*AMD*)   CPU_VENDOR=amd ;;
               esac
           fi ;;
    esac
    export CPU_VENDOR
}

detect_all() {
    detect_distro; detect_chassis; detect_gpu; detect_cpu
    info "distro:  $DISTRO_ID (Arch family)"
    info "chassis: $CHASSIS"
    info "gpu:     $GPU_VENDOR"
    info "cpu:     $CPU_VENDOR"
}
