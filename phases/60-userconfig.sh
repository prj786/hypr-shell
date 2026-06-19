#!/usr/bin/env bash
# phase 60 — per-user defaults that don't need root: default apps, EDITOR, zram.

phase_userconfig() {
    step "60 · user config"

    # default applications (writes ~/.config/mimeapps.list — no Hyprland involvement)
    if command -v xdg-settings >/dev/null 2>&1; then
        for b in firefox.desktop firefox-esr.desktop org.mozilla.firefox.desktop; do
            [ -r "/usr/share/applications/$b" ] && { run xdg-settings set default-web-browser "$b" && break; }
        done
    fi
    # Install our Fresh launcher (runs `fresh` inside kitty) so it can be the GUI
    # default text/code editor. Shipped in the repo; copied to the user apps dir.
    if [ -r "$DOTREPO/system/applications/fresh.desktop" ]; then
        run mkdir -p "$HOME/.local/share/applications"
        run cp -f "$DOTREPO/system/applications/fresh.desktop" "$HOME/.local/share/applications/fresh.desktop"
        run update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi

    # Default apps. _mime <desktop> <mimes…> (looks in both system + user app dirs).
    _mime() {
        local d="$1"; shift
        [ -r "/usr/share/applications/$d" ] || [ -r "$HOME/.local/share/applications/$d" ] || return 0
        local m; for m in "$@"; do run xdg-mime default "$d" "$m"; done
    }
    if command -v xdg-mime >/dev/null 2>&1; then
        _mime nemo.desktop             inode/directory
        # Fresh IDE is the default text + code editor (terminal IDE; no GUI editor ships).
        _mime fresh.desktop text/plain text/markdown text/html text/css text/javascript \
              application/json application/javascript application/xml text/xml application/x-yaml \
              text/x-python text/x-csrc text/x-chdr text/x-c++src application/x-shellscript \
              text/x-rust text/x-go
        _mime imv.desktop              image/png image/jpeg image/gif image/webp image/bmp image/tiff
        _mime org.pwmt.zathura.desktop application/pdf application/epub+zip
        _mime mpv.desktop              video/mp4 video/x-matroska video/webm video/quicktime audio/mpeg audio/flac
        _mime engrampa.desktop         application/zip application/x-tar application/gzip application/x-xz \
              application/x-bzip2 application/x-7z-compressed application/x-rar application/zstd application/x-compressed-tar
    fi

    # GTK/GIO reads ~/.config/mimeapps.list directly — there is no KDE ksycoca cache
    # to rebuild. Just refresh the desktop-file/mimeinfo cache so "Open With" lists
    # are current (covers Fresh, which we copied into the user apps dir above).
    if command -v update-desktop-database >/dev/null 2>&1; then
        run update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi

    # Nemo right-click actions: "Compress…" / "Extract Here" via engrampa. Shipped
    # in the repo, copied to the user's Nemo actions dir (Nemo loads *.nemo_action).
    if [ -d "$DOTREPO/system/nemo-actions" ]; then
        run mkdir -p "$HOME/.local/share/nemo/actions"
        run sh -c "cp -f '$DOTREPO/system/nemo-actions/'*.nemo_action '$HOME/.local/share/nemo/actions/' 2>/dev/null || true"
    fi

    # (Reversal icon theme + Mocu cursor are installed system-wide in phase 20.)

    # default app appearance: dark across GTK + Qt + KDE, tinted with the default
    # accent. Writes the toolkit config files now (gsettings is best-effort from a
    # TTY; Quickshell re-applies it live at first login, then honours user-theme.json).
    local cs="$HOME/.config/quickshell/scripts/colorscheme.sh"
    if [ -r "$cs" ]; then
        run sh "$cs" dark 0a84ff && ok "default appearance set to dark (GTK + Qt fallback)"
    else
        info "colorscheme.sh not found yet (dotfiles not linked?) — skipping appearance default."
    fi

    # EDITOR/VISUAL for the user shell (idempotent: only append once)
    local rc="$HOME/.profile"
    if [ -w "$rc" ] || [ ! -e "$rc" ]; then
        if ! grep -q 'hypr-shell: default editor' "$rc" 2>/dev/null; then
            run sh -c "printf '\n# hypr-shell: default editor\nexport EDITOR=fresh VISUAL=fresh\n' >> '$rc'"
        fi
    fi

    # ── Node toolchain via mise (no system nodejs) ──
    # mise owns Node here. Provision Node LTS + pnpm + the front-end language
    # servers/formatter declared in dotfiles/mise/config.toml, and wire mise into
    # the shells. The shims dir is also added to PATH by start-hyprland.sh so
    # GUI-launched Fresh finds the servers without an interactive shell.
    if command -v mise >/dev/null 2>&1; then
        run mise trust "$HOME/.config/mise/config.toml" 2>/dev/null || true
        if [ "${DRY_RUN:-0}" = "1" ]; then
            info "would run 'mise install' (node LTS, pnpm, TS/CSS/HTML/JSON/Tailwind/Vue/Svelte servers, prettier)"
        else
            info "provisioning Node toolchain via mise (this builds/downloads node + npm tools)…"
            run mise install || warn "mise install reported errors — run 'mise install' again after login."
        fi
        # activate mise in interactive shells (shims also live on PATH via the session wrapper)
        for rcf in "$HOME/.bashrc" "$HOME/.zshrc"; do
            [ -e "$rcf" ] || continue
            local sh_name; sh_name="$(basename "$rcf" | sed 's/^\.//; s/rc$//')"   # bashrc→bash, zshrc→zsh
            grep -q 'mise activate' "$rcf" 2>/dev/null || \
                run sh -c "printf '\n# hypr-shell: mise (node toolchain)\neval \"\$(mise activate %s)\"\n' '$sh_name' >> '$rcf'"
        done
    else
        warn "mise not installed — Node toolchain not provisioned (install mise, then 'mise install')."
    fi

    # zram (laptop benefit). Ship a sane generator config if none exists.
    if [ "$CHASSIS" = "laptop" ] && [ ! -e /etc/systemd/zram-generator.conf ]; then
        info "writing /etc/systemd/zram-generator.conf (zstd, capped at 8G)"
        if [ "${DRY_RUN:-0}" != "1" ]; then
            printf '[zram0]\nzram-size = min(ram, 8192)\ncompression-algorithm = zstd\n' \
                | sudo_run tee /etc/systemd/zram-generator.conf >/dev/null && ok "zram configured"
        fi
    fi

    ok "user config done"
}
