#!/usr/bin/env bash
# wallpaper.sh — set the desktop background with swaybg (idempotent).
#
# Looks for, in order: $DE_WALLPAPER, ~/.config/hypr/wallpaper.{jpg,jpeg,png}.
# If none is found, paints a solid Gruvbox bg0 so the root is never garbage.

set -u

command -v swaybg >/dev/null 2>&1 || exit 0
pgrep -x swaybg >/dev/null 2>&1 && exit 0   # already running

for f in \
    "${DE_WALLPAPER:-}" \
    "$HOME/.config/hypr/wallpaper.jpg" \
    "$HOME/.config/hypr/wallpaper.jpeg" \
    "$HOME/.config/hypr/wallpaper.png"
do
    if [ -n "$f" ] && [ -r "$f" ]; then
        exec swaybg -i "$f" -m fill
    fi
done

# No image → solid Gruvbox background.
exec swaybg -c "#282828"
