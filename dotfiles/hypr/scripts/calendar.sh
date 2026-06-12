#!/usr/bin/env bash
# calendar.sh — Super+C. Opens GNOME Calendar if present, otherwise pops a
# notification with the current month (the Waybar clock also has a calendar
# tooltip on hover/click).

set -u

if command -v gnome-calendar >/dev/null 2>&1; then
    exec gnome-calendar
elif command -v notify-send >/dev/null 2>&1; then
    notify-send " $(date '+%A, %d %B %Y')" "$(cal)"
fi
