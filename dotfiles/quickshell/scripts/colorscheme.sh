#!/bin/bash
# colorscheme.sh <dark|light> [accent-hex] — apply a light/dark appearance,
# tinted with the shell accent, UNIFORMLY across the whole app ecosystem:
#   • GTK 3/4 + libadwaita   (settings.ini + gsettings)
#   • Qt 5/6                 (qt6ct/qt5ct, Breeze style + Fusion-palette fallback)
#   • KDE / KF6              (kdeglobals: Fusion widgetStyle + full colour scheme)
#   • Icon theme             (Reversal, accent-matched colour variant)
#   • Cursor                 (Mocu, forced everywhere so it never flips per-toolkit)
#
# Called by: Settings → Theme (live), Quickshell at startup (re-sync), phase 60
# (install default). Writes config files always; gsettings is a best-effort live
# nudge for already-running apps.
#
# NOT `set -e`: the GTK config is written first and kdeglobals (the KDE/Qt colours)
# LAST, so any non-zero line in between (a stray test, a missing gsettings key)
# would abort before kdeglobals and leave GTK dark but KDE apps on Breeze's light
# default — the exact "GTK dark, KDE light" split. `set -u` only: every file is
# written best-effort and the script always reaches the kdeglobals write.
set -u

MODE="${1:-dark}"
case "$MODE" in dark|light) ;; *) MODE=dark ;; esac

# accent → 6 lowercase hex (fallback macOS blue) + decimal R,G,B
ACC="$(printf '%s' "${2:-}" | tr -dc 'a-fA-F0-9' | tr 'A-F' 'a-f')"
if [ "${#ACC}" -ge 6 ]; then ACC="${ACC: -6}"; else ACC="0a84ff"; fi
AR=$((16#${ACC:0:2})); AG=$((16#${ACC:2:2})); AB=$((16#${ACC:4:2}))

# map any accent to the nearest Reversal colour variant (by HSV hue/saturation)
reversal_color() {
    local r=$AR g=$AG b=$AB max=$AR min=$AR
    [ $g -gt $max ] && max=$g; [ $b -gt $max ] && max=$b
    [ $g -lt $min ] && min=$g; [ $b -lt $min ] && min=$b
    local d=$((max - min))
    if [ $d -eq 0 ] || [ $(( d * 100 / (max > 0 ? max : 1) )) -lt 15 ]; then echo grey; return; fi
    local hue
    if   [ $max -eq $r ]; then hue=$(( ( (g - b) * 60 / d + 360) % 360 ))
    elif [ $max -eq $g ]; then hue=$(( ( (b - r) * 60 / d + 120 + 360) % 360 ))
    else                       hue=$(( ( (r - g) * 60 / d + 240 + 360) % 360 )); fi
    if   [ $hue -lt 12 ];  then echo red
    elif [ $hue -lt 70 ];  then echo orange    # incl. yellow → orange (no yellow variant)
    elif [ $hue -lt 160 ]; then echo green
    elif [ $hue -lt 195 ]; then echo cyan
    elif [ $hue -lt 235 ]; then echo blue
    elif [ $hue -lt 300 ]; then echo purple
    elif [ $hue -lt 352 ]; then echo pink
    else echo red; fi
}
RC="$(reversal_color)"
# Mocu theme names are Mocu-{White,Black}-{Right,Left}; white reads best on dark.
CURSOR="Mocu-White-Right"; CURSOR_SIZE=24

if [ "$MODE" = "dark" ]; then
    GTK_THEME="adw-gtk3-dark"; PREFER_DARK=1; CS="prefer-dark"; ICONS="Reversal-${RC}-dark"
else
    GTK_THEME="adw-gtk3";      PREFER_DARK=0; CS="default";     ICONS="Reversal-${RC}"
fi

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"

# ── universal cursor: ~/.icons/default is the fallback every toolkit reads ──
mkdir -p "$HOME/.icons/default"
cat > "$HOME/.icons/default/index.theme" <<EOF
[Icon Theme]
Name=Default
Comment=Default cursor theme
Inherits=$CURSOR
EOF

# ── GTK3 / GTK4 settings.ini ──────────────────────────────────────────────────
for v in 3.0 4.0; do
    mkdir -p "$CFG/gtk-$v"
    cat > "$CFG/gtk-$v/settings.ini" <<EOF
[Settings]
gtk-theme-name=$GTK_THEME
gtk-icon-theme-name=$ICONS
gtk-application-prefer-dark-theme=$PREFER_DARK
gtk-cursor-theme-name=$CURSOR
gtk-cursor-theme-size=$CURSOR_SIZE
EOF
done

# ── gsettings — live nudge for libadwaita/GTK + cursor ──
if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface color-scheme "$CS"        2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme    "$GTK_THEME" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme   "$ICONS"     2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR"    2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-size  "$CURSOR_SIZE" 2>/dev/null || true
fi

# ── Qt (qt6ct + qt5ct) — fallback palette when the kde platform theme is absent ──
# Primary Qt/KDE theming is the "kde" platform theme (plasma-integration,
# QT_QPA_PLATFORMTHEME=kde in start-hyprland.sh): it reads the kdeglobals written
# below and applies our colours to EVERY app incl. KColorScheme item views (the
# Dolphin/Ark file panes). qt6ct's custom dark palette here is just a fallback for
# when plasma-integration isn't installed. Style is Fusion (set in kdeglobals).
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

# ── KDE / KF6 (Dolphin, Ark, Gwenview, Okular, Kate) — kdeglobals ──
# KColorScheme-aware KDE apps read these [Colors:*] groups (incl. View, the
# Dolphin file-pane). With the Fusion style the QPalette already carries the dark
# colours, so this is belt-and-suspenders; still written in full so nothing falls
# back to a light default. Accent = Selection + Decoration*.
if [ "$MODE" = "dark" ]; then
    C_WIN="42,42,42";  C_WINA="36,36,36";  C_VIEW="30,30,30";  C_VIEWA="36,36,36"
    C_BTN="45,45,45";  C_FG="220,220,220";  C_FGI="130,130,130"; C_TIP="45,45,45"
    C_VIS="150,120,200"
else
    C_WIN="239,239,239"; C_WINA="247,247,247"; C_VIEW="255,255,255"; C_VIEWA="247,247,247"
    C_BTN="232,232,232"; C_FG="26,26,26";       C_FGI="130,130,130"; C_TIP="255,255,220"
    C_VIS="100,80,160"
fi
A="$AR,$AG,$AB"
_cgroup() {  # $1 bg  $2 bgAlt
    cat <<EOF
BackgroundNormal=$1
BackgroundAlternate=$2
ForegroundNormal=$C_FG
ForegroundInactive=$C_FGI
ForegroundActive=$A
ForegroundLink=$A
ForegroundVisited=$C_VIS
ForegroundNegative=218,68,83
ForegroundNeutral=246,116,0
ForegroundPositive=39,174,96
DecorationFocus=$A
DecorationHover=$A
EOF
}
{
    echo "[General]";  echo "ColorScheme=HyprShell"; echo
    echo "[KDE]";      echo "widgetStyle=Fusion";    echo
    echo "[Icons]";    echo "Theme=$ICONS";          echo
    echo "[Colors:Window]";        _cgroup "$C_WIN"  "$C_WINA";  echo
    echo "[Colors:View]";          _cgroup "$C_VIEW" "$C_VIEWA"; echo
    echo "[Colors:Button]";        _cgroup "$C_BTN"  "$C_WINA";  echo
    echo "[Colors:Tooltip]";       _cgroup "$C_TIP"  "$C_TIP";   echo
    echo "[Colors:Complementary]"; _cgroup "$C_VIEW" "$C_VIEWA"; echo
    echo "[Colors:Selection]"
    echo "BackgroundNormal=$A"; echo "BackgroundAlternate=$A"
    echo "ForegroundNormal=255,255,255"; echo "ForegroundInactive=220,220,220"
    echo "ForegroundActive=255,255,255"; echo "ForegroundLink=255,255,255"
    echo "ForegroundVisited=235,235,235"; echo "ForegroundNegative=255,255,255"
    echo "ForegroundNeutral=255,255,255"; echo "ForegroundPositive=255,255,255"
    echo "DecorationFocus=$A"; echo "DecorationHover=$A"
} > "$CFG/kdeglobals"

# ── live update: nudge already-running KDE apps to re-read kdeglobals ──
# plasma-integration file-watches kdeglobals, so a colour/accent change usually
# recolours running KDE apps on its own; this legacy KGlobalSettings signal is a
# best-effort extra for apps that listen for it. Harmless if nothing receives it.
if command -v dbus-send >/dev/null 2>&1; then
    dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32 0 int32 0 2>/dev/null || true
fi

exit 0
