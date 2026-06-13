#!/bin/bash
# colorscheme.sh <dark|light> [accent-hex] — apply a light or dark appearance,
# tinted with the shell accent, across the WHOLE app ecosystem:
#   • GTK 3/4 + libadwaita  (settings.ini + gsettings)        — Firefox/Zen, GTK apps
#   • Qt 5/6 via qt6ct/qt5ct (Fusion + custom QPalette)       — generic Qt apps
#   • KDE / KF6 via kdeglobals (Fusion style + colour scheme) — Dolphin, Ark,
#       Gwenview, Okular, Kate (which prefer kdeglobals over the qt6ct palette)
#
# Called by: Settings → Theme (live), Quickshell at startup (re-sync), phase 60
# (install default). Always writes config files (works from a bare TTY); the
# gsettings calls are best-effort live nudges for already-running libadwaita apps.
set -eu

MODE="${1:-dark}"
case "$MODE" in dark|light) ;; *) MODE=dark ;; esac

# accent → 6 lowercase hex (fall back to macOS blue)
ACC="$(printf '%s' "${2:-}" | tr -dc 'a-fA-F0-9' | tr 'A-F' 'a-f')"
if [ "${#ACC}" -ge 6 ]; then ACC="${ACC: -6}"; else ACC="0a84ff"; fi
AR=$((16#${ACC:0:2})); AG=$((16#${ACC:2:2})); AB=$((16#${ACC:4:2}))   # decimal R,G,B

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"

if [ "$MODE" = "dark" ]; then
    GTK_THEME="adw-gtk3-dark"; PREFER_DARK=1; ICONS="Papirus-Dark"; CS="prefer-dark"
else
    GTK_THEME="adw-gtk3";      PREFER_DARK=0; ICONS="Papirus";      CS="default"
fi

# ── GTK3 / GTK4 settings.ini ──────────────────────────────────────────────────
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

# ── gsettings — libadwaita / GTK4 (e.g. Firefox/Zen, GTK apps) follow live ──
if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface color-scheme "$CS"       2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme   "$GTK_THEME" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme  "$ICONS"     2>/dev/null || true
fi

# ── Qt (qt6ct + qt5ct) — Fusion driven by a custom QPalette ──
# 20 entries = QPalette::ColorRole 0..19; index 12 (Highlight) + 14 (Link) carry
# the accent so selections/links match the shell. (Built with the accent inlined.)
COLORS="$CFG/qt6ct/colors"
mkdir -p "$COLORS"

cat > "$COLORS/hyprshell-dark.conf" <<EOF
[ColorScheme]
active_colors=#ffdcdcdc, #ff2d2d2d, #ff3a3a3a, #ff333333, #ff1a1a1a, #ff262626, #ffdcdcdc, #ffffffff, #ffdcdcdc, #ff1e1e1e, #ff2a2a2a, #ff000000, #ff${ACC}, #ffffffff, #ff${ACC}, #ffb38aff, #ff242424, #ff2d2d2d, #ffdcdcdc, #ff7f7f7f
inactive_colors=#ffdcdcdc, #ff2d2d2d, #ff3a3a3a, #ff333333, #ff1a1a1a, #ff262626, #ffdcdcdc, #ffffffff, #ffdcdcdc, #ff1e1e1e, #ff2a2a2a, #ff000000, #ff3a3a3a, #ffdcdcdc, #ff${ACC}, #ffb38aff, #ff242424, #ff2d2d2d, #ffdcdcdc, #ff7f7f7f
disabled_colors=#ff6f6f6f, #ff2d2d2d, #ff3a3a3a, #ff333333, #ff1a1a1a, #ff262626, #ff6f6f6f, #ffffffff, #ff6f6f6f, #ff1e1e1e, #ff2a2a2a, #ff000000, #ff3a3a3a, #ff9f9f9f, #ff${ACC}, #ffb38aff, #ff242424, #ff2d2d2d, #ff6f6f6f, #ff5f5f5f
EOF

cat > "$COLORS/hyprshell-light.conf" <<EOF
[ColorScheme]
active_colors=#ff1a1a1a, #ffefefef, #ffffffff, #fff5f5f5, #ffb0b0b0, #ffc8c8c8, #ff1a1a1a, #ffffffff, #ff1a1a1a, #ffffffff, #ffefefef, #ff000000, #ff${ACC}, #ffffffff, #ff${ACC}, #ff6f42c1, #fff7f7f7, #ffffffdc, #ff1a1a1a, #ff808080
inactive_colors=#ff1a1a1a, #ffefefef, #ffffffff, #fff5f5f5, #ffb0b0b0, #ffc8c8c8, #ff1a1a1a, #ffffffff, #ff1a1a1a, #ffffffff, #ffefefef, #ff000000, #ff${ACC}, #ffffffff, #ff${ACC}, #ff6f42c1, #fff7f7f7, #ffffffdc, #ff1a1a1a, #ff808080
disabled_colors=#ffa0a0a0, #ffefefef, #ffffffff, #fff5f5f5, #ffb0b0b0, #ffc8c8c8, #ffa0a0a0, #ffffffff, #ffa0a0a0, #ffffffff, #ffefefef, #ff000000, #ff${ACC}, #ffe0e0e0, #ff${ACC}, #ff6f42c1, #fff7f7f7, #ffffffdc, #ffa0a0a0, #ffb0b0b0
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

# ── KDE / KF6 (Dolphin, Ark, Gwenview, Okular, Kate) via kdeglobals ──
# KDE apps prefer their own colour scheme over the qt6ct palette, so set it
# explicitly. widgetStyle=Fusion keeps them consistent with the generic Qt apps
# (and avoids pulling Plasma's Breeze style). Selection = the accent.
if [ "$MODE" = "dark" ]; then
    WIN="42,42,42"; WIN_ALT="36,36,36"; VIEW="30,30,30"; VIEW_ALT="36,36,36"
    BTN="45,45,45"; FG="220,220,220"; FG_INACT="140,140,140"; TIP="45,45,45"
else
    WIN="239,239,239"; WIN_ALT="247,247,247"; VIEW="255,255,255"; VIEW_ALT="247,247,247"
    BTN="232,232,232"; FG="26,26,26"; FG_INACT="130,130,130"; TIP="255,255,220"
fi
cat > "$CFG/kdeglobals" <<EOF
[General]
ColorScheme=HyprShell

[KDE]
widgetStyle=Fusion

[Icons]
Theme=$ICONS

[Colors:Window]
BackgroundNormal=$WIN
BackgroundAlternate=$WIN_ALT
ForegroundNormal=$FG
ForegroundInactive=$FG_INACT
DecorationFocus=$AR,$AG,$AB
DecorationHover=$AR,$AG,$AB

[Colors:View]
BackgroundNormal=$VIEW
BackgroundAlternate=$VIEW_ALT
ForegroundNormal=$FG
ForegroundInactive=$FG_INACT
DecorationFocus=$AR,$AG,$AB
DecorationHover=$AR,$AG,$AB

[Colors:Button]
BackgroundNormal=$BTN
BackgroundAlternate=$WIN_ALT
ForegroundNormal=$FG
ForegroundInactive=$FG_INACT
DecorationFocus=$AR,$AG,$AB
DecorationHover=$AR,$AG,$AB

[Colors:Selection]
BackgroundNormal=$AR,$AG,$AB
BackgroundAlternate=$AR,$AG,$AB
ForegroundNormal=255,255,255

[Colors:Tooltip]
BackgroundNormal=$TIP
ForegroundNormal=$FG

[Colors:Complementary]
BackgroundNormal=$VIEW
ForegroundNormal=$FG
EOF

exit 0
