#!/usr/bin/env bash
# start-hyprland.sh — the session-entry wrapper used by "Hyprland (DE)".
#
# Most toolkit env (Qt/GTK/cursor) is set inside hyprland.lua via hl.env() so
# every client inherits it. This wrapper only sets the pre-launch desktop
# identity (so portals resolve the Hyprland backend) and a software-render
# escape hatch for the brand-new Lunar Lake iGPU, then exec's Hyprland.

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_DESKTOP=Hyprland
export DESKTOP_SESSION=hyprland

# Locally-built tools (e.g. hyprland-per-window-layout in step 6 of install.sh)
# live in ~/.local/bin — make sure the session and its children can find them.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac

# GPU escape hatch: if the Arc 140V (xe) driver ever tears/hangs/corrupts, log
# in once with DE_SOFTWARE_RENDER=1 in your environment to fall back to Mesa
# software rendering. (The cursor-plane bug is already handled in hyprland.lua
# via cursor:use_cpu_buffer.)
if [ "${DE_SOFTWARE_RENDER:-0}" = "1" ]; then
    export LIBGL_ALWAYS_SOFTWARE=1
    export WLR_RENDERER_ALLOW_SOFTWARE=1
fi

exec Hyprland
