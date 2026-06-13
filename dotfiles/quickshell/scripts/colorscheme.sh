#!/bin/sh
# colorscheme.sh <dark|light> — apply a light or dark appearance across BOTH
# GTK (2/3/4 + libadwaita) and Qt (5/6 via qt5ct/qt6ct), so the whole app
# ecosystem matches the shell. Called by:
#   • Settings → Theme → Appearance (live toggle)
#   • Quickshell at startup (Globals re-applies the persisted choice so gsettings
#     stays in sync every session)
#   • phase 60 of the installer (sets the dark default on first install)
#
# Always writes the config files (works from a bare TTY); gsettings is a
# best-effort nudge for already-running libadwaita apps and needs a session bus.
set -eu

MODE="${1:-dark}"
case "$MODE" in dark|light) ;; *) MODE=dark ;; esac
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"

if [ "$MODE" = "dark" ]; then
    GTK_THEME="adw-gtk3-dark"; PREFER_DARK=1; ICONS="Papirus-Dark"; CS="prefer-dark"
else
    GTK_THEME="adw-gtk3";      PREFER_DARK=0; ICONS="Papirus";      CS="default"
fi

# ── GTK3 / GTK4 settings.ini — for apps that read the toolkit config directly ──
for v in 3.0 4.0; do
    mkdir -p "$CFG/gtk-$v"
    cat > "$CFG/gtk-$v/settings.ini" <<EOF
[Settings]
gtk-theme-name=$GTK_THEME
gtk-icon-theme-name=$ICONS
gtk-application-prefer-dark-theme=$PREFER_DARK
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-cursor-theme-size=24
EOF
done

# ── gsettings — libadwaita / GTK4 (e.g. Nautilus) follow color-scheme live ──
if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface color-scheme "$CS"        2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme   "$GTK_THEME"  2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme  "$ICONS"      2>/dev/null || true
fi

# ── Qt (qt6ct + qt5ct) — Fusion style driven by a custom QPalette ──
# The 20 entries are QPalette::ColorRole order 0..19 (WindowText, Button, Light,
# Midlight, Dark, Mid, Text, BrightText, ButtonText, Base, Window, Shadow,
# Highlight, HighlightedText, Link, LinkVisited, AlternateBase, ToolTipBase,
# ToolTipText, PlaceholderText).
COLORS="$CFG/qt6ct/colors"
mkdir -p "$COLORS"

cat > "$COLORS/hyprshell-dark.conf" <<'EOF'
[ColorScheme]
active_colors=#ffdcdcdc, #ff2d2d2d, #ff3a3a3a, #ff333333, #ff1a1a1a, #ff262626, #ffdcdcdc, #ffffffff, #ffdcdcdc, #ff1e1e1e, #ff2a2a2a, #ff000000, #ff0a84ff, #ffffffff, #ff0a84ff, #ffb38aff, #ff242424, #ff2d2d2d, #ffdcdcdc, #ff7f7f7f
inactive_colors=#ffdcdcdc, #ff2d2d2d, #ff3a3a3a, #ff333333, #ff1a1a1a, #ff262626, #ffdcdcdc, #ffffffff, #ffdcdcdc, #ff1e1e1e, #ff2a2a2a, #ff000000, #ff3a3a3a, #ffdcdcdc, #ff0a84ff, #ffb38aff, #ff242424, #ff2d2d2d, #ffdcdcdc, #ff7f7f7f
disabled_colors=#ff6f6f6f, #ff2d2d2d, #ff3a3a3a, #ff333333, #ff1a1a1a, #ff262626, #ff6f6f6f, #ffffffff, #ff6f6f6f, #ff1e1e1e, #ff2a2a2a, #ff000000, #ff3a3a3a, #ff9f9f9f, #ff0a84ff, #ffb38aff, #ff242424, #ff2d2d2d, #ff6f6f6f, #ff5f5f5f
EOF

cat > "$COLORS/hyprshell-light.conf" <<'EOF'
[ColorScheme]
active_colors=#ff1a1a1a, #ffefefef, #ffffffff, #fff5f5f5, #ffb0b0b0, #ffc8c8c8, #ff1a1a1a, #ffffffff, #ff1a1a1a, #ffffffff, #ffefefef, #ff000000, #ff0a84ff, #ffffffff, #ff0066cc, #ff6f42c1, #fff7f7f7, #ffffffdc, #ff1a1a1a, #ff808080
inactive_colors=#ff1a1a1a, #ffefefef, #ffffffff, #fff5f5f5, #ffb0b0b0, #ffc8c8c8, #ff1a1a1a, #ffffffff, #ff1a1a1a, #ffffffff, #ffefefef, #ff000000, #ff0a84ff, #ffffffff, #ff0066cc, #ff6f42c1, #fff7f7f7, #ffffffdc, #ff1a1a1a, #ff808080
disabled_colors=#ffa0a0a0, #ffefefef, #ffffffff, #fff5f5f5, #ffb0b0b0, #ffc8c8c8, #ffa0a0a0, #ffffffff, #ffa0a0a0, #ffffffff, #ffefefef, #ff000000, #ffb0b0b0, #ffe0e0e0, #ff0066cc, #ff6f42c1, #fff7f7f7, #ffffffdc, #ffa0a0a0, #ffb0b0b0
EOF

SCHEME="$COLORS/hyprshell-$MODE.conf"
for q in qt6ct qt5ct; do
    mkdir -p "$CFG/$q"
    cat > "$CFG/$q/$q.conf" <<EOF
[Appearance]
custom_palette=true
color_scheme_path=$SCHEME
icon_theme=$ICONS
standard_dialogs=default
style=Fusion
EOF
done

exit 0
