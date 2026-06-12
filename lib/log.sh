#!/usr/bin/env bash
# lib/log.sh — output helpers, the dry-run guard, and the sudo wrapper.
# Sourced by install.sh; every other phase/lib uses these.

# Colors (disabled if not a tty)
if [ -t 1 ]; then
    C_R=$'\033[1;31m'; C_G=$'\033[1;32m'; C_Y=$'\033[1;33m'
    C_B=$'\033[1;34m'; C_DIM=$'\033[2m'; C_0=$'\033[0m'
else
    C_R=; C_G=; C_Y=; C_B=; C_DIM=; C_0=
fi

step()  { printf '\n%s==>%s %s%s%s\n' "$C_B" "$C_0" "$C_B" "$*" "$C_0"; }
info()  { printf '%s::%s %s\n' "$C_Y" "$C_0" "$*"; }
ok()    { printf '%s ok%s %s\n' "$C_G" "$C_0" "$*"; }
warn()  { printf '%s !!%s %s\n' "$C_R" "$C_0" "$*" >&2; }
die()   { warn "$*"; exit 1; }

# run <cmd...> — execute, or just print under --dry-run. The single choke point
# for everything that mutates the system, so --dry-run is genuinely safe.
run() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        printf '%s   would run:%s %s\n' "$C_DIM" "$C_0" "$*"
        return 0
    fi
    "$@"
}

# sudo_run <cmd...> — same, but as root. Prompts once for the password (sudo
# caches it). Refuses if no sudo and not already root.
sudo_run() {
    if [ "$(id -u)" = "0" ]; then run "$@"; return $?; fi
    command -v sudo >/dev/null 2>&1 || die "need root for: $*  (no sudo found; re-run as root)"
    if [ "${DRY_RUN:-0}" = "1" ]; then
        printf '%s   would sudo:%s %s\n' "$C_DIM" "$C_0" "$*"
        return 0
    fi
    sudo "$@"
}

# ask_yes <prompt> — y/N. Auto-yes under --yes. Defaults to No on EOF.
ask_yes() {
    [ "${ASSUME_YES:-0}" = "1" ] && return 0
    printf '   %s [y/N] ' "$1"
    local r; read -r r </dev/tty 2>/dev/null || r=""
    case "$r" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}
