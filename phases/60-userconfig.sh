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
    # KDE/Qt utility apps as defaults (themed, titlebar-less). _mime <desktop> <mimes…>
    _mime() {
        local d="$1"; shift
        [ -r "/usr/share/applications/$d" ] || return 0
        local m; for m in "$@"; do run xdg-mime default "$d" "$m"; done
    }
    if command -v xdg-mime >/dev/null 2>&1; then
        _mime org.kde.dolphin.desktop  inode/directory
        _mime org.kde.kate.desktop     text/plain
        _mime org.kde.gwenview.desktop image/png image/jpeg image/gif image/webp image/bmp image/tiff
        _mime org.kde.okular.desktop   application/pdf application/epub+zip
        _mime mpv.desktop              video/mp4 video/x-matroska video/webm video/quicktime audio/mpeg audio/flac
    fi

    # default app appearance: dark across GTK + Qt. Writes the toolkit config
    # files now (gsettings is best-effort from a TTY; Quickshell re-applies it
    # live at first login). Users flip light/dark later in Settings → Theme.
    local cs="$HOME/.config/quickshell/scripts/colorscheme.sh"
    if [ -r "$cs" ]; then
        run sh "$cs" dark && ok "default appearance set to dark (GTK + Qt)"
    else
        info "colorscheme.sh not found yet (dotfiles not linked?) — skipping appearance default."
    fi

    # EDITOR/VISUAL for the user shell (idempotent: only append once)
    local rc="$HOME/.profile"
    if [ -w "$rc" ] || [ ! -e "$rc" ]; then
        if ! grep -q 'EDITOR=nvim' "$rc" 2>/dev/null; then
            run sh -c "printf '\n# hyprdots: default editor\nexport EDITOR=nvim VISUAL=nvim\n' >> '$rc'"
        fi
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
