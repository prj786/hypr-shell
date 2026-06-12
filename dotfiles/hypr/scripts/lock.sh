#!/usr/bin/env bash
# lock.sh — lock the session. Prefers hyprlock (if installed), then a
# Gruvbox-tinted swaylock, then gtklock. Never stacks two lockers.

set -u

pgrep -x hyprlock >/dev/null 2>&1 && exit 0
pgrep -x swaylock >/dev/null 2>&1 && exit 0
pgrep -x gtklock  >/dev/null 2>&1 && exit 0

if command -v hyprlock >/dev/null 2>&1; then
    exec hyprlock
elif command -v swaylock >/dev/null 2>&1; then
    exec swaylock -f \
        --color 1d2021 \
        --inside-color 282828 --inside-clear-color 504945 \
        --ring-color fabd2f --ring-clear-color 8ec07c --ring-ver-color 83a598 --ring-wrong-color fb4934 \
        --key-hl-color fe8019 --line-uses-inside \
        --text-color ebdbb2 --text-clear-color ebdbb2 --text-wrong-color fb4934 \
        --indicator-radius 90 --indicator-thickness 8
elif command -v gtklock >/dev/null 2>&1; then
    exec gtklock
else
    notify-send "Lock" "No screen locker installed (hyprlock/swaylock/gtklock)." 2>/dev/null
fi
