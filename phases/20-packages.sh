#!/usr/bin/env bash
# phase 20 — install the official-repo set (pacman) then the AUR set (helper).

phase_packages() {
    step "20 · packages"
    [ "${NO_PACKAGES:-0}" = "1" ] && { info "--no-packages: skipping install"; return 0; }

    local off aur
    mapfile -t off < <(read_list common.list)
    mapfile -t aur < <(read_list aur.list)

    info "${#off[@]} official packages + ${#aur[@]} AUR packages"
    if [ "${DRY_RUN:-0}" = "1" ]; then
        printf '%s   pacman:%s %s\n' "$C_DIM" "$C_0" "${off[*]}"
        printf '%s   aur:%s    %s\n' "$C_DIM" "$C_0" "${aur[*]}"
        return 0
    fi

    ask_yes "Install ${#off[@]} official packages now?" && install_official "${off[@]}" || warn "skipped official packages"
    if [ "${#aur[@]}" -gt 0 ]; then
        ask_yes "Build & install ${#aur[@]} AUR packages now? (compiles from source)" \
            && install_aur "${aur[@]}" || warn "skipped AUR packages"
    fi
    ok "package phase done"
}
