#!/usr/bin/env bash
# phase 20 — resolve common.list → native names and install in one batch.

phase_packages() {
    step "20 · packages"
    [ "${NO_PACKAGES:-0}" = "1" ] && { info "--no-packages: skipping install"; return 0; }

    resolve_packages   # fills TO_INSTALL / TO_BUILD / SKIPPED

    info "${#TO_INSTALL[@]} packages to install via the $FAMILY package manager"
    [ "${#SKIPPED[@]}"  -gt 0 ] && info "not packaged on $FAMILY (handled elsewhere/optional): ${SKIPPED[*]}"
    [ "${#TO_BUILD[@]}" -gt 0 ] && warn "must be BUILT from source on $FAMILY: ${TO_BUILD[*]}  (see VERSIONS / README tier-3 notes)"

    if [ "${DRY_RUN:-0}" = "1" ]; then
        printf '%s   would install:%s %s\n' "$C_DIM" "$C_0" "${TO_INSTALL[*]}"
    else
        ask_yes "Install ${#TO_INSTALL[@]} packages now?" || { warn "skipped package install"; return 0; }
        # On Arch, prefer the AUR helper so AUR names (regreet, satty, bibata…) resolve.
        if [ "$FAMILY" = "arch" ] && [ -n "${AUR_HELPER:-}" ]; then
            run "$AUR_HELPER" -S --needed --noconfirm "${TO_INSTALL[@]}"
        else
            install_packages
        fi
    fi
    ok "package phase done"
}
