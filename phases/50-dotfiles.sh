#!/usr/bin/env bash
# phase 50 — deploy the dotfiles payload (symlink + backup) and the user units.

phase_dotfiles() {
    step "50 · dotfiles"
    deploy_dotfiles   # from lib/deploy.sh: links hypr/ + quickshell/, copies the target

    # the start wrapper + scripts must be executable after a fresh checkout
    if [ -d "$DOTREPO/dotfiles/hypr" ]; then
        run chmod +x "$DOTREPO/dotfiles/hypr/start-hyprland.sh" 2>/dev/null || true
        run chmod +x "$DOTREPO"/dotfiles/hypr/scripts/*.sh 2>/dev/null || true
    fi
    ok "dotfiles deployed"
}
