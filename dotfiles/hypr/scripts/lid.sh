#!/usr/bin/env bash
# lid.sh — clamshell lid handling for Hyprland (Lua config).
#   close: if an external monitor is connected, just turn off the laptop panel
#          (keep working on the external); if the laptop is alone, lock + suspend.
#   open:  re-enable the laptop panel.
#
# NOTE: this only runs if systemd-logind is told to ignore the lid (so it doesn't
# also suspend). See /etc/systemd/logind.conf.d/10-lid.conf.

set -u
INTERNAL="eDP-1"

externals() { hyprctl monitors -j | jq "[.[] | select(.name != \"$INTERNAL\")] | length"; }

case "${1:-}" in
  close)
    if [ "$(externals)" -gt 0 ]; then
        # docked-style: external present → power off just the laptop panel
        hyprctl eval "hl.monitor({output=\"$INTERNAL\", disabled=true})" >/dev/null 2>&1
    else
        # laptop alone → lock, then sleep
        qs ipc call lock lock >/dev/null 2>&1
        sleep 0.5
        systemctl suspend
    fi
    ;;
  open)
    hyprctl eval "hl.monitor({output=\"$INTERNAL\", disabled=false, mode=\"preferred\", position=\"auto\", scale=2})" >/dev/null 2>&1
    ;;
esac
