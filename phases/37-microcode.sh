#!/usr/bin/env bash
# phase 37 — CPU microcode: install the vendor's early-boot microcode (intel-ucode
# or amd-ucode, per the CPU detected in lib/detect.sh) and wire it into the
# bootloader so the CPU's errata/security fixes load BEFORE the kernel. This is
# the CPU counterpart to phase 40's per-vendor GPU drivers. Idempotent and
# best-effort: a missing piece warns, never aborts. Skipped in a VM (the host /
# hypervisor owns microcode) and when the vendor isn't intel/amd.
#
# Only systemd-boot loader entries need EXPLICIT editing (the ucode initrd must
# precede the main initramfs). GRUB auto-detects /boot/*-ucode.img on
# grub-mkconfig, and UKI/dracut embed it on the next initramfs build — so for
# those we just (re)generate the relevant config/initramfs.

# Add an `initrd /<ucode>.img` line ahead of the first initrd in each systemd-boot
# loader entry; else regenerate GRUB; else rebuild the initramfs/UKI. Backs up any
# edited file to *.bak.$RUN_STAMP.
_wire_microcode_initrd() {
    local img="$1" did=""

    # ── systemd-boot loader entries (the only case needing explicit editing) ──
    if ls /boot/loader/entries/*.conf >/dev/null 2>&1; then
        did="$(sudo_run bash -c '
            img="'"$img"'"; stamp="'"$RUN_STAMP"'"; changed=0
            for f in /boot/loader/entries/*.conf; do
                [ -f "$f" ] || continue
                grep -q "$img" "$f" && continue              # ucode already referenced
                grep -qE "^initrd " "$f" || continue         # no initrd line to anchor to
                cp "$f" "$f.bak.$stamp"
                # insert the ucode initrd BEFORE the first existing initrd line
                sed -i "0,/^initrd /s|^initrd |initrd /$img\ninitrd |" "$f"
                changed=1
            done
            [ "$changed" = 1 ] && echo yes
        ' 2>/dev/null)"
        if [ -n "$did" ]; then ok "systemd-boot: added 'initrd /$img' to loader entries"
        else info "systemd-boot: entries already reference /$img (nothing to do)"; fi
        return 0
    fi

    # ── GRUB: grub-mkconfig prepends the early microcode initrd automatically ──
    if [ -f /etc/default/grub ] && command -v grub-mkconfig >/dev/null 2>&1 && [ -f /boot/grub/grub.cfg ]; then
        sudo_run grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 \
            && ok "GRUB: regenerated grub.cfg (early microcode initrd included)" \
            || warn "grub-mkconfig failed — run it yourself so /$img is loaded at boot."
        return 0
    fi

    # ── UKI / mkinitcpio / dracut: rebuild the initramfs to embed the ucode ──
    if command -v mkinitcpio >/dev/null 2>&1; then
        sudo_run mkinitcpio -P >/dev/null 2>&1 \
            && ok "mkinitcpio -P: rebuilt initramfs/UKI with microcode embedded" \
            || warn "mkinitcpio -P failed — rebuild your initramfs so /$img is loaded."
        return 0
    fi

    warn "no recognised bootloader (systemd-boot/GRUB) or initramfs tool found — $img installed, but wire it into your boot manager manually."
}

phase_microcode() {
    step "37 · CPU microcode ($CPU_VENDOR)"

    case "$CPU_VENDOR" in
        intel|amd) : ;;
        *) info "CPU vendor '$CPU_VENDOR' — no intel/amd microcode to install; skipping."; return 0 ;;
    esac
    if [ "${IS_VM:-0}" = "1" ]; then
        ok "VM detected — the host/hypervisor applies CPU microcode; skipping guest ucode."
        return 0
    fi

    local pkg="${CPU_VENDOR}-ucode" img="${CPU_VENDOR}-ucode.img"

    if [ "${NO_PACKAGES:-0}" = "1" ]; then
        info "--no-packages: would install $pkg and wire /$img into the bootloader."
        return 0
    fi
    if [ "${DRY_RUN:-0}" = "1" ]; then
        info "would install $pkg, then wire /$img (systemd-boot entries get an 'initrd /$img' line; GRUB/UKI get a config/initramfs regen)."
        return 0
    fi

    install_official "$pkg"
    pkg_present "$pkg" || { warn "$pkg not installed (not in repos?) — cannot wire CPU microcode."; return 0; }

    _wire_microcode_initrd "$img"
    ok "CPU microcode ready ($pkg) — loads before the kernel on the next reboot."
}
