#!/usr/bin/env bash
# phase 40 — per-vendor GPU setup. Drivers themselves come from common.list +
# the family map (mesa/vulkan are pulled as deps); this phase does the
# vendor-specific *config* that packages can't.

phase_gpu() {
    step "40 · GPU ($GPU_VENDOR)"

    case " $GPU_VENDOR " in
        *" intel "*)
            # Lunar Lake / Xe2 uses the `xe` kernel driver. Its DPMS-resume bug can
            # strand a black screen, so the shipped hypridle.conf deliberately has
            # NO `dpms off` listener (lock-only). Just confirm the VAAPI driver.
            if command -v vainfo >/dev/null 2>&1; then
                info "Intel: ensure intel-media-driver (iHD) provides VAAPI — phase 90 verifies."
            fi
            if lspci -k 2>/dev/null | grep -qi 'in use: xe'; then
                ok "xe driver detected — hypridle ships without dpms-off (resume-bug guard)."
            fi ;;
    esac

    case " $GPU_VENDOR " in
        *" amd "*)
            ok "AMD: mesa + vulkan-radeon (RADV) need no extra config." ;;
    esac

    case " $GPU_VENDOR " in
        *" nvidia "*)
            warn "NVIDIA needs care. Recommended:"
            echo "    - install the OPEN kernel modules (nvidia-open) for Turing+"
            echo "    - kernel params: nvidia_drm.modeset=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1"
            echo "    - enable the suspend fix services (prevents resume corruption):"
            for u in nvidia-suspend nvidia-resume nvidia-hibernate; do
                _enable_system "${u}.service"
            done
            echo "    - set env in hypr/conf: LIBVA_DRIVER_NAME=nvidia, __GL_GSYNC_ALLOWED=1" ;;
    esac

    [ "$GPU_VENDOR" = "unknown" ] && warn "could not detect a GPU vendor (no lspci?) — skipped GPU config."
    ok "GPU phase done"
}
